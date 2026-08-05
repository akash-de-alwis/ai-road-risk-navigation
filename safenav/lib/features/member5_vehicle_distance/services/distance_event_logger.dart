import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import '../models/distance_estimate_model.dart';

class DistanceEventLogger {
  static String get _baseUrl =>
      dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:8000';

  static Future<void> log({
    required String tripId,
    required DistanceEstimate estimate,
    required double durationSeconds,
  }) async {
    try {
      await http
          .post(
            Uri.parse('$_baseUrl/v3/distance/event'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'trip_id': tripId,
              'timestamp': estimate.timestamp.toIso8601String(),
              'distance_m': estimate.distanceM,
              'safe_distance_m': estimate.safeDistanceM,
              'following_gap_ratio': estimate.followingGapRatio,
              'speed_kmh': estimate.speedKmh,
              'severity': estimate.severityLabel,
              'ttc_seconds': estimate.ttcSeconds,
              'duration_seconds': durationSeconds,
            }),
          )
          .timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('[distance_logger] $e');
    }
  }
}