import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/distance_estimate_model.dart';
import '../services/distance_alert_service.dart';

class DistanceAlertBanner extends StatelessWidget {
  const DistanceAlertBanner({super.key});

  String _messageFor(DistanceEstimate estimate) {
    switch (estimate.severity) {
      case DistanceSeverity.critical:
        return 'Too close — increase your gap now';
      case DistanceSeverity.warning:
        return 'Following distance getting tight';
      case DistanceSeverity.caution:
        return 'Leave a little more space';
      default:
        return 'Safe following distance';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DistanceAlertService>(
      builder: (ctx, alertSvc, _) {
        final estimate = alertSvc.activeAlert;
        if (estimate == null) return const SizedBox.shrink();

        final color = estimate.severityColor;
        return AnimatedSlide(
          offset: Offset.zero,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: color.withValues(alpha: 0.4),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.12),
                    border: Border.all(
                      color: color,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    estimate.severity == DistanceSeverity.critical
                        ? Icons.warning_rounded
                        : Icons.info_outline_rounded,
                    size: 22,
                    color: color,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          estimate.severityLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_messageFor(estimate)} • ${estimate.distanceM.toStringAsFixed(1)} m',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0D1B2A),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}