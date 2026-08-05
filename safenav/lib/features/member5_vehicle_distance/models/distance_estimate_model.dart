import 'package:flutter/material.dart';

enum DistanceSeverity { safe, caution, warning, critical }

class DistanceEstimate {
  final double distanceM;
  final double safeDistanceM;
  final double followingGapRatio;
  final double speedKmh;
  final double? ttcSeconds;
  final DistanceSeverity severity;
  final DateTime timestamp;

  DistanceEstimate({
    required this.distanceM,
    required this.safeDistanceM,
    required this.followingGapRatio,
    required this.speedKmh,
    this.ttcSeconds,
    required this.severity,
    required this.timestamp,
  });

  String get severityLabel {
    switch (severity) {
      case DistanceSeverity.critical:
        return 'CRITICAL';
      case DistanceSeverity.warning:
        return 'WARNING';
      case DistanceSeverity.caution:
        return 'CAUTION';
      default:
        return 'SAFE';
    }
  }

  Color get severityColor {
    switch (severity) {
      case DistanceSeverity.critical:
        return const Color(0xFFFF3B5C);
      case DistanceSeverity.warning:
        return const Color(0xFFFF8C42);
      case DistanceSeverity.caution:
        return const Color(0xFFFFB300);
      default:
        return const Color(0xFF00C06A);
    }
  }
}