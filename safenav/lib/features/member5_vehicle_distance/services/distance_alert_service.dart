import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/distance_estimate_model.dart';
import 'distance_preference_service.dart';

class DistanceAlertService extends ChangeNotifier {
  late FlutterTts _tts;
  final DistancePreferenceService preferences;

  DistanceEstimate? activeAlert;
  DateTime? _lastAlertedAt;
  static const _minIntervalSeconds = 6;

  static const Map<DistanceSeverity, Map<String, String>> _voiceMap = {
    DistanceSeverity.critical: {
      'en': 'Too close. Increase your following distance now.',
      'si': 'ඉතා ලඟින් යනවා. දැන්මම ඉදිරි වාහනයෙන් වැඩි දුරක් තබන්න.',
    },
    DistanceSeverity.warning: {
      'en': 'You are following closely. Ease back to a safer distance.',
      'si': 'ඔබ ඉතා ලඟින් යනවා. තව ටිකක් ඉඩ තබන්න.',
    },
    DistanceSeverity.caution: {
      'en': 'Following distance getting tight. Leave a little more space.',
      'si': 'පසුපස දුර ටිකක් අඩු වෙලා. තව ටිකක් ඉඩ තබන්න.',
    },
  };

  DistanceAlertService({required this.preferences});

  Future<void> init() async {
    _tts = FlutterTts();
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
  }

  Future<void> triggerAlert(DistanceEstimate estimate) async {
    if (_lastAlertedAt != null) {
      final delta = DateTime.now().difference(_lastAlertedAt!).inSeconds;
      if (delta < _minIntervalSeconds) return;
    }

    activeAlert = estimate;
    _lastAlertedAt = DateTime.now();
    notifyListeners();

    if (preferences.alertStyle == 'voice_visual') {
      final language = Platform.localeName.toLowerCase().startsWith('si')
          ? 'si'
          : 'en';
      final text = _voiceMap[estimate.severity]?[language] ??
          _voiceMap[estimate.severity]?['en'];
      if (text != null) {
        try {
          await _tts.setLanguage(language == 'si' ? 'si-LK' : 'en-US');
        } catch (_) {}
        await _tts.stop();
        await _tts.speak(text);
      }
    }

    Future.delayed(const Duration(seconds: 6), () {
      if (activeAlert?.timestamp == estimate.timestamp) {
        activeAlert = null;
        notifyListeners();
      }
    });
  }

  void clearAlert() {
    activeAlert = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }
}