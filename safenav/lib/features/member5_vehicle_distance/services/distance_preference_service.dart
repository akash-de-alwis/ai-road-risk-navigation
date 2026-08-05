import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DistancePreferenceService extends ChangeNotifier {
  static const _enabledKey = 'distance_estimator_enabled';
  static const _ruleKey = 'distance_following_rule';
  static const _previewKey = 'distance_camera_preview_enabled';
  static const _alertStyleKey = 'distance_alert_style';

  bool detectionEnabled = false;
  String followingRule = 'NEW_LEARNER';
  bool showCameraPreview = false;
  String alertStyle = 'voice_visual';

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    detectionEnabled = prefs.getBool(_enabledKey) ?? false;
    followingRule = prefs.getString(_ruleKey) ?? 'NEW_LEARNER';
    showCameraPreview = prefs.getBool(_previewKey) ?? false;
    alertStyle = prefs.getString(_alertStyleKey) ?? 'voice_visual';
    notifyListeners();
  }

  Future<void> setDetectionEnabled(bool v) async {
    detectionEnabled = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, v);
    notifyListeners();
  }

  Future<void> setFollowingRule(String rule) async {
    followingRule = rule;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ruleKey, rule);
    notifyListeners();
  }

  Future<void> setShowCameraPreview(bool v) async {
    showCameraPreview = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_previewKey, v);
    notifyListeners();
  }

  Future<void> setAlertStyle(String s) async {
    alertStyle = s;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_alertStyleKey, s);
    notifyListeners();
  }

  double get followingTimeSeconds {
    switch (followingRule) {
      case 'CAUTIOUS':
        return 4.0;
      case 'STANDARD':
        return 2.0;
      default:
        return 3.0;
    }
  }
}