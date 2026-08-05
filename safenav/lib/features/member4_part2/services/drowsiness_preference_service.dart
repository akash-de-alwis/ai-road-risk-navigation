import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/baseline_calibration_model.dart';

class DrowsinessPreferenceService extends ChangeNotifier {
  static const _enabledKey = 'drowsiness_detection_enabled';
  static const _sensKey = 'drowsiness_sensitivity';
  static const _alertKey = 'drowsiness_alert_style';
  static const _baselineKey = 'drowsiness_baseline_json';
  static const _cameraPreviewKey = 'drowsiness_camera_preview_enabled';

  bool detectionEnabled = false;
  String sensitivity = 'MEDIUM';
  String alertStyle = 'voice_visual';
  BaselineCalibration? baseline;
  bool showCameraPreview = false;

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    detectionEnabled = prefs.getBool(_enabledKey) ?? false;
    sensitivity = prefs.getString(_sensKey) ?? 'MEDIUM';
    alertStyle = prefs.getString(_alertKey) ?? 'voice_visual';
    showCameraPreview = prefs.getBool(_cameraPreviewKey) ?? false;
    final baselineJson = prefs.getString(_baselineKey);
    if (baselineJson != null) {
      try {
        baseline = BaselineCalibration.fromJson(
          jsonDecode(baselineJson) as Map<String, dynamic>,
        );
      } catch (_) {
        baseline = null;
      }
    }
    notifyListeners();
  }

  Future<void> setDetectionEnabled(bool v) async {
    detectionEnabled = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, v);
  }

  Future<void> setSensitivity(String s) async {
    sensitivity = s;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sensKey, s);
  }

  Future<void> setAlertStyle(String s) async {
    alertStyle = s;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_alertKey, s);
  }

  Future<void> saveBaseline(BaselineCalibration b) async {
    baseline = b;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baselineKey, jsonEncode(b.toJson()));
  }

  Future<void> clearBaseline() async {
    baseline = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_baselineKey);
  }

  Future<void> setShowCameraPreview(bool v) async {
    showCameraPreview = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_cameraPreviewKey, v);
    notifyListeners();
  }

  // Sensitivity-adjusted thresholds
  double get earClosedRatio {
    switch (sensitivity) {
      case 'HIGH':
        return 0.78;
      case 'LOW':
        return 0.55;
      default:
        return 0.65;
    }
  }

  double get perclosThreshold {
    switch (sensitivity) {
      case 'HIGH':
        return 12.0;
      case 'LOW':
        return 25.0;
      default:
        return 18.0;
    }
  }
}
