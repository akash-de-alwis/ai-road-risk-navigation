import 'package:flutter/material.dart';

class RollingFeatures {
  final double avgSpeedKmh;
  final double speedVolatility;
  final int harshBrakeEvents;
  final double headingVariance;
  final double distanceCoveredM;
  final int sampleCount;
  final double windowSeconds;

  RollingFeatures({
    required this.avgSpeedKmh,
    required this.speedVolatility,
    required this.harshBrakeEvents,
    required this.headingVariance,
    required this.distanceCoveredM,
    required this.sampleCount,
    required this.windowSeconds,
  });

  factory RollingFeatures.fromJson(Map<String, dynamic> json) =>
      RollingFeatures(
        avgSpeedKmh: (json['avg_speed_kmh'] as num).toDouble(),
        speedVolatility: (json['speed_volatility'] as num).toDouble(),
        harshBrakeEvents: json['harsh_brake_events'] as int,
        headingVariance: (json['heading_variance'] as num).toDouble(),
        distanceCoveredM: (json['distance_covered_m'] as num).toDouble(),
        sampleCount: json['sample_count'] as int,
        windowSeconds: (json['window_seconds'] as num).toDouble(),
      );
}

class StreamRiskUpdate {
  final String sessionId;
  final String riskLevel;
  final String timestamp;
  final double riskScore;
  final double volatilityMultiplier;
  final RollingFeatures rollingFeatures;

  StreamRiskUpdate({
    required this.sessionId,
    required this.riskScore,
    required this.riskLevel,
    required this.rollingFeatures,
    required this.volatilityMultiplier,
    required this.timestamp,
  });

  factory StreamRiskUpdate.fromJson(Map<String, dynamic> json) =>
      StreamRiskUpdate(
        sessionId: json['session_id'] as String,
        riskScore: (json['risk_score'] as num).toDouble(),
        riskLevel: json['risk_level'] as String,
        rollingFeatures: RollingFeatures.fromJson(
            json['rolling_features'] as Map<String, dynamic>),
        volatilityMultiplier:
            (json['volatility_multiplier'] as num).toDouble(),
        timestamp: json['timestamp'] as String,
      );

  Color get levelColor {
    switch (riskLevel) {
      case 'CRITICAL':
        return const Color(0xFFFF3B5C);
      case 'HIGH':
        return const Color(0xFFFF8C42);
      case 'MODERATE':
        return const Color(0xFFFFB300);
      default:
        return const Color(0xFF00C06A);
    }
  }
}
