import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/realtime_pipeline_service.dart';

// Expandable panel (for demo/defense purposes) showing the raw rolling
// features coming off the stream — useful to show the pipeline is
// genuinely computing windowed features, not just relaying raw GPS.
class StreamDebugPanel extends StatelessWidget {
  const StreamDebugPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RealtimePipelineService>(
      builder: (ctx, pipeline, _) {
        final u = pipeline.latestUpdate;
        if (u == null) return const SizedBox.shrink();
        final f = u.rollingFeatures;

        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEEF1F5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.podcasts, size: 14, color: Color(0xFF0D1B2A)),
                  SizedBox(width: 6),
                  Text(
                    'Live Pipeline Features',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0D1B2A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _row('Avg speed', '${f.avgSpeedKmh} km/h'),
              _row('Speed volatility', f.speedVolatility.toStringAsFixed(2)),
              _row('Harsh brake events', '${f.harshBrakeEvents}'),
              _row('Volatility multiplier', '×${u.volatilityMultiplier}'),
              _row('Samples in window', '${f.sampleCount}'),
            ],
          ),
        );
      },
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF5C6B7A))),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0D1B2A),
            ),
          ),
        ],
      ),
    );
  }
}
