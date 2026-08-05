import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

import '../../../member4_driver_scoring/part1/services/sensor_service.dart';
import '../models/distance_estimate_model.dart';
import '../models/tracked_vehicle_model.dart';
import 'distance_alert_service.dart';
import 'distance_event_logger.dart';
import 'distance_preference_service.dart';

class VehicleDistanceService extends ChangeNotifier {
  CameraController? _cameraController;
  ObjectDetector? _objectDetector;

  bool isInitialized = false;
  bool isRunning = false;
  String? errorMessage;
  DistanceEstimate? currentEstimate;
  TrackedVehicle? currentTrackedVehicle;

  Size? _lastFrameSize;
  double? _previousDistanceM;
  DateTime? _previousDistanceAt;
  DateTime _lastFrameTime = DateTime.now();

  int _loggedEventCount = 0;
  DistanceSeverity? _activeLoggedSeverity;
  DateTime? _severityStartedAt;
  DateTime? _lastSeverityLogAt;

  static const double _averageVehicleWidthM = 1.8;
  static const double _assumedFocalLengthPx = 700;
  static const double _minSpeedForWarningKmh = 10;
  static const int _logThrottleSeconds = 3;

  final DistancePreferenceService preferences;
  final DistanceAlertService alertService;

  VehicleDistanceService({
    required this.preferences,
    required this.alertService,
  });

  CameraController? get cameraController => _cameraController;
  Size? get lastFrameSize => _lastFrameSize;
  bool get hasLoggedEvents => _loggedEventCount > 0;

  Future<bool> initialize() async {
    try {
      final cameras = await availableCameras();
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        back,
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();

      _objectDetector = ObjectDetector(
        options: ObjectDetectorOptions(
          mode: DetectionMode.stream,
          classifyObjects: false,
          multipleObjects: true,
        ),
      );

      isInitialized = true;
      errorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = 'Rear camera init failed: $e';
      notifyListeners();
      return false;
    }
  }

  Future<void> startDetection() async {
    if (!isInitialized) {
      final ok = await initialize();
      if (!ok) return;
    }
    if (isRunning) return;

    _loggedEventCount = 0;
    _activeLoggedSeverity = null;
    _severityStartedAt = null;
    _lastSeverityLogAt = null;
    _previousDistanceM = null;
    _previousDistanceAt = null;

    isRunning = true;
    notifyListeners();

    try {
      await _cameraController!.startImageStream(_onFrame);
    } catch (e) {
      isRunning = false;
      errorMessage = 'Rear camera stream failed: $e';
      notifyListeners();
    }
  }

  Future<void> _onFrame(CameraImage img) async {
    if (!isRunning || _objectDetector == null) return;

    final now = DateTime.now();
    if (now.difference(_lastFrameTime).inMilliseconds < 200) return;
    _lastFrameTime = now;

    try {
      final inputImage = _convertCameraImage(img);
      if (inputImage == null) return;

      final objects = await _objectDetector!.processImage(inputImage);
      if (objects.isEmpty) {
        currentTrackedVehicle = null;
        currentEstimate = null;
        _clearActiveSeverity();
        notifyListeners();
        return;
      }

      _lastFrameSize = Size(img.width.toDouble(), img.height.toDouble());

      final frameWidth = img.width.toDouble();
      final centerBandMin = frameWidth * 0.25;
      final centerBandMax = frameWidth * 0.75;

      DetectedObject? best;
      double bestArea = 0;
      for (final obj in objects) {
        final box = obj.boundingBox;
        final boxCenterX = box.left + box.width / 2;
        if (boxCenterX < centerBandMin || boxCenterX > centerBandMax) {
          continue;
        }
        final area = box.width * box.height;
        if (area > bestArea) {
          bestArea = area;
          best = obj;
        }
      }

      if (best == null) {
        currentTrackedVehicle = null;
        currentEstimate = null;
        _clearActiveSeverity();
        notifyListeners();
        return;
      }

      final box = best.boundingBox;
      currentTrackedVehicle = TrackedVehicle(
        trackingId: best.trackingId ?? -1,
        left: box.left,
        top: box.top,
        width: box.width,
        height: box.height,
      );

      await _computeDistanceEstimate(box.width);
    } catch (e) {
      debugPrint('[distance] frame error: $e');
    }
  }

  Future<void> _computeDistanceEstimate(double boxWidthPx) async {
    if (boxWidthPx <= 0) return;

    final distanceM =
        (_averageVehicleWidthM * _assumedFocalLengthPx) / boxWidthPx;

    double speedKmh = 0;
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      speedKmh = (pos.speed * 3.6).clamp(0, 200);
    } catch (_) {}

    if (speedKmh < _minSpeedForWarningKmh) {
      currentEstimate = null;
      _clearActiveSeverity();
      _previousDistanceM = distanceM;
      _previousDistanceAt = DateTime.now();
      notifyListeners();
      return;
    }

    final speedMps = speedKmh / 3.6;
    final safeDistanceM = speedMps * preferences.followingTimeSeconds;
    final gapRatio = safeDistanceM > 0 ? (distanceM / safeDistanceM) : 1.0;

    double? ttc;
    final now = DateTime.now();
    if (_previousDistanceM != null && _previousDistanceAt != null) {
      final dt = now.difference(_previousDistanceAt!).inMilliseconds / 1000.0;
      final closingRate = (_previousDistanceM! - distanceM) / (dt > 0 ? dt : 1);
      if (closingRate > 0.3) {
        ttc = distanceM / closingRate;
      }
    }
    _previousDistanceM = distanceM;
    _previousDistanceAt = now;

    final severity = _severityFor(gapRatio, ttc);
    final estimate = DistanceEstimate(
      distanceM: distanceM,
      safeDistanceM: safeDistanceM,
      followingGapRatio: gapRatio,
      speedKmh: speedKmh,
      ttcSeconds: ttc,
      severity: severity,
      timestamp: now,
    );

    currentEstimate = estimate;
    notifyListeners();

    if (severity != DistanceSeverity.safe) {
      await _logDistanceEvent(estimate);
      await alertService.triggerAlert(estimate);
    } else {
      _clearActiveSeverity();
    }
  }

  DistanceSeverity _severityFor(double gapRatio, double? ttc) {
    if (gapRatio < 0.4 || (ttc != null && ttc < 2.0)) {
      return DistanceSeverity.critical;
    }
    if (gapRatio < 0.7) {
      return DistanceSeverity.warning;
    }
    if (gapRatio < 1.0) {
      return DistanceSeverity.caution;
    }
    return DistanceSeverity.safe;
  }

  Future<void> _logDistanceEvent(DistanceEstimate estimate) async {
    final tripId = SensorService.instance.currentTrip?.tripId;
    if (tripId == null) return;

    if (_activeLoggedSeverity != estimate.severity) {
      _activeLoggedSeverity = estimate.severity;
      _severityStartedAt = estimate.timestamp;
      _lastSeverityLogAt = null;
    }

    final now = estimate.timestamp;
    final shouldLog = _lastSeverityLogAt == null ||
        now.difference(_lastSeverityLogAt!).inSeconds >= _logThrottleSeconds;
    if (!shouldLog) return;

    final durationSeconds = _severityStartedAt == null
        ? 0.0
        : now.difference(_severityStartedAt!).inMilliseconds / 1000.0;
    await DistanceEventLogger.log(
      tripId: tripId,
      estimate: estimate,
      durationSeconds: durationSeconds,
    );

    _loggedEventCount++;
    _lastSeverityLogAt = now;
  }

  void _clearActiveSeverity() {
    _activeLoggedSeverity = null;
    _severityStartedAt = null;
    _lastSeverityLogAt = null;
  }

  InputImage? _convertCameraImage(CameraImage img) {
    try {
      final bytes = _concatenatePlanes(img.planes);
      final imageSize = Size(img.width.toDouble(), img.height.toDouble());
      final format = Platform.isAndroid
          ? InputImageFormat.nv21
          : InputImageFormat.bgra8888;
      final metadata = InputImageMetadata(
        size: imageSize,
        rotation: InputImageRotation.rotation90deg,
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
    try {
      await _cameraController?.stopImageStream();
    } catch (_) {}
    currentEstimate = null;
    currentTrackedVehicle = null;
    _previousDistanceM = null;
    _previousDistanceAt = null;
    _clearActiveSeverity();
    alertService.clearAlert();
    notifyListeners();
  }

  @override
  void dispose() {
    stopDetection();
    _cameraController?.dispose();
    _objectDetector?.close();
    super.dispose();
  }
}