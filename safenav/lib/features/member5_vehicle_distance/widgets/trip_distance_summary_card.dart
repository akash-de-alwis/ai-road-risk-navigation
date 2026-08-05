import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class TripDistanceSummaryCard extends StatefulWidget {
  final String tripId;

  const TripDistanceSummaryCard({super.key, required this.tripId});

  @override
  State<TripDistanceSummaryCard> createState() => _TripDistanceSummaryCardState();
}

class _TripDistanceSummaryCardState extends State<TripDistanceSummaryCard> {
  late Future<_TripDistanceStats?> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetchStats();
  }

  static String get _baseUrl =>
      dotenv.env['API_BASE_URL'] ?? 'http://10.0.2.2:8000';

  Future<_TripDistanceStats?> _fetchStats() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/v3/distance/trip/${widget.tripId}/stats'),
      );
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return _TripDistanceStats.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_TripDistanceStats?>(
      future: _future,
      builder: (context, snapshot) {
        final stats = snapshot.data;
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F0FE),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.school_rounded,
                        color: Color(0xFF2979FF), size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Distance Coaching Summary',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0D1B2A),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (stats == null)
                const Text(
                  'No distance summary is available for this trip yet.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF5C6B7A)),
                )
              else if (stats.totalEvents == 0)
                const Text(
                  'No close-following events were logged on this trip.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF5C6B7A)),
                )
              else ...[
                _StatRow(
                  label: 'Closest distance',
                  value: '${stats.closestDistanceM.toStringAsFixed(1)} m',
                ),
                const SizedBox(height: 8),
                _StatRow(
                  label: 'Too-close events',
                  value:
                      '${stats.criticalEvents} critical • ${stats.warningEvents} warning • ${stats.cautionEvents} caution',
                ),
                const SizedBox(height: 8),
                _StatRow(
                  label: 'Average following gap',
                  value: stats.avgFollowingGapRatio.toStringAsFixed(2),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F6F9),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.school_rounded,
                          color: Color(0xFF2979FF), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          stats.coachingTip,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF0D1B2A),
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF5C6B7A),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0D1B2A),
          ),
        ),
      ],
    );
  }
}

class _TripDistanceStats {
  final int totalEvents;
  final int criticalEvents;
  final int warningEvents;
  final int cautionEvents;
  final double closestDistanceM;
  final double avgFollowingGapRatio;
  final double totalTooCloseSeconds;
  final double safetyDeduction;
  final String coachingTip;

  _TripDistanceStats({
    required this.totalEvents,
    required this.criticalEvents,
    required this.warningEvents,
    required this.cautionEvents,
    required this.closestDistanceM,
    required this.avgFollowingGapRatio,
    required this.totalTooCloseSeconds,
    required this.safetyDeduction,
    required this.coachingTip,
  });

  factory _TripDistanceStats.fromJson(Map<String, dynamic> json) {
    return _TripDistanceStats(
      totalEvents: (json['total_events'] as num).toInt(),
      criticalEvents: (json['critical_events'] as num).toInt(),
      warningEvents: (json['warning_events'] as num).toInt(),
      cautionEvents: (json['caution_events'] as num).toInt(),
      closestDistanceM: (json['closest_distance_m'] as num?)?.toDouble() ?? 0,
      avgFollowingGapRatio:
          (json['avg_following_gap_ratio'] as num).toDouble(),
      totalTooCloseSeconds:
          (json['total_too_close_seconds'] as num).toDouble(),
      safetyDeduction: (json['safety_deduction'] as num).toDouble(),
      coachingTip: json['coaching_tip'] as String? ?? '',
    );
  }
}