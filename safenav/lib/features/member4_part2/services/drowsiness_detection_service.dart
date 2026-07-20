import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../models/drowsiness_metrics_model.dart';
import 'drowsiness_preference_service.dart';
import 'drowsiness_calibration_service.dart';
import 'drowsiness_alert_service.dart';

class DrowsinessDetectionService extends ChangeNotifier {
  CameraController? _cameraController;
  FaceDetector? _faceDetector;

  DrowsinessMetrics? currentMetrics;
  bool isInitialized = false;
  bool isRunning = false;
  String? errorMessage;

  // Rolling window data (last 60 seconds)
  final List<MapEntry<DateTime, bool>> _eyeClosedHistory = [];
  final List<DateTime> _yawnTimestamps = [];
  final List<DateTime> _headNodTimestamps = [];

  final DrowsinessPreferenceService preferences;
  final DrowsinessCalibrationService calibration;
  final DrowsinessAlertService alertService;

  DateTime _lastFrameTime = DateTime.now();
  Timer? _metricsTimer;

  CameraController? get cameraController => _cameraController;

  bool get isCameraReady =>
      _cameraController != null && _cameraController!.value.isInitialized;

  DrowsinessDetectionService({
    required this.preferences,
    required this.calibration,
    required this.alertService,
  });

  Future<bool> initialize() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        front,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();

      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          enableContours: true,
          enableLandmarks: true,
          enableTracking: true,
          minFaceSize: 0.15,
          performanceMode: FaceDetectorMode.fast,
        ),
      );

      isInitialized = true;
      errorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = 'Camera init failed: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> startDetection() async {
    if (!isInitialized) {
      final ok = await initialize();
      if (!ok) return;
    }

    isRunning = true;

    // Process at ~5 FPS by skipping frames under 200ms apart
    await _cameraController!.startImageStream((img) async {
      if (!isRunning) return;

      final now = DateTime.now();
      if (now.difference(_lastFrameTime).inMilliseconds < 200) return;
      _lastFrameTime = now;

      try {
        final inputImage = _convertCameraImage(img);
        if (inputImage == null) return;

        final faces = await _faceDetector!.processImage(inputImage);
        if (faces.isEmpty) return;

        await _processFace(faces.first);
      } catch (e) {
        debugPrint('[drowsiness] frame error: $e');
      }
    });

    // Rolling metrics calculator every 2 seconds
    _metricsTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _computeRollingMetrics(),
    );

    notifyListeners();
  }

  Future<void> _processFace(Face face) async {
    final leftProb = face.leftEyeOpenProbability ?? 1.0;
    final rightProb = face.rightEyeOpenProbability ?? 1.0;
    final avgEyeOpen = (leftProb + rightProb) / 2;

    // Feed into calibration if active — do not record metrics yet
    if (calibration.isCalibrating) {
      calibration.addSample(avgEyeOpen);
      return;
    }

    final baseline = preferences.baseline;
    if (baseline == null) return;

    final isEyeClosed =
        avgEyeOpen < (baseline.baselineEar * preferences.earClosedRatio);
    _eyeClosedHistory.add(MapEntry(DateTime.now(), isEyeClosed));

    // Yawn detection via lip contour gap
    final upperLip = face.contours[FaceContourType.upperLipBottom];
    final lowerLip = face.contours[FaceContourType.lowerLipTop];
    if (upperLip != null &&
        lowerLip != null &&
        upperLip.points.isNotEmpty &&
        lowerLip.points.isNotEmpty) {
      final upperY = upperLip.points
              .map((p) => p.y)
              .reduce((a, b) => a + b) /
          upperLip.points.length;
      final lowerY = lowerLip.points
              .map((p) => p.y)
              .reduce((a, b) => a + b) /
          lowerLip.points.length;
      // Threshold tuned for low-res 320x240 camera
      if ((lowerY - upperY).abs() > 25) {
        _yawnTimestamps.add(DateTime.now());
      }
    }

    // Head nod detection via Euler pitch
    final pitch = face.headEulerAngleX ?? 0;
    if (pitch < -15) {
      _headNodTimestamps.add(DateTime.now());
    }
  }

  void _computeRollingMetrics() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 60));
    _eyeClosedHistory.removeWhere((e) => e.key.isBefore(cutoff));
    _yawnTimestamps.removeWhere((t) => t.isBefore(cutoff));
    _headNodTimestamps.removeWhere((t) => t.isBefore(cutoff));

    if (_eyeClosedHistory.isEmpty) return;

    final closedCount = _eyeClosedHistory.where((e) => e.value).length;
    final perclos = (closedCount / _eyeClosedHistory.length) * 100;

    final perclosComp = (perclos / preferences.perclosThreshold) * 50;
    final yawnComp = (_yawnTimestamps.length / 3.0) * 25;
    final nodComp = (_headNodTimestamps.length / 4.0) * 25;
    final score = (perclosComp + yawnComp + nodComp).clamp(0.0, 100.0);

    DrowsinessLevel level;
    if (score >= 70) {
      level = DrowsinessLevel.critical;
    } else if (score >= 50) {
      level = DrowsinessLevel.warning;
    } else if (score >= 30) {
      level = DrowsinessLevel.caution;
    } else {
      level = DrowsinessLevel.alert;
    }

    final avgEar = _eyeClosedHistory
            .map((e) => e.value ? 0.2 : 0.7)
            .reduce((a, b) => a + b) /
        _eyeClosedHistory.length;

    currentMetrics = DrowsinessMetrics(
      currentEar: avgEar,
      perclosPct: perclos,
      yawnCount60s: _yawnTimestamps.length,
      headNods60s: _headNodTimestamps.length,
      drowsinessScore: score,
      level: level,
      timestamp: DateTime.now(),
    );

    notifyListeners();

    if (level == DrowsinessLevel.warning ||
        level == DrowsinessLevel.critical) {
      alertService.triggerAlert(currentMetrics!);
    }
  }

  InputImage? _convertCameraImage(CameraImage img) {
    try {
      final bytes = _concatenatePlanes(img.planes);
      final imageSize =
          Size(img.width.toDouble(), img.height.toDouble());
      final format = Platform.isAndroid
          ? InputImageFormat.nv21
          : InputImageFormat.bgra8888;
      final metadata = InputImageMetadata(
        size: imageSize,
        rotation: InputImageRotation.rotation270deg,
        format: format,
        bytesPerRow: img.planes[0].bytesPerRow,
      );
      return InputImage.fromBytes(bytes: bytes, metadata: metadata);
    } catch (_) {
      return null;
    }
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final builder = BytesBuilder();
    for (final plane in planes) {
      builder.add(plane.bytes);
    }
    return builder.toBytes();
  }

  Future<void> stopDetection() async {
    isRunning = false;
    _metricsTimer?.cancel();
    _metricsTimer = null;
    try {
      await _cameraController?.stopImageStream();
    } catch (_) {}
    notifyListeners();
  }

  @override
  void dispose() {
    stopDetection();
    _cameraController?.dispose();
    _faceDetector?.close();
    super.dispose();
  }
}
