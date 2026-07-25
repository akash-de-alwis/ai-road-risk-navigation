import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/realtime_pipeline_service.dart';

// Small floating pill showing the streaming pipeline is active, distinct
// from Member 1's existing polling HUD. Shows a pulsing dot + the current
// risk score from the STREAM (not the polled endpoint). Long-press toggles
// the debug panel via [onLongPress], when provided.
class LiveStreamIndicator extends StatefulWidget {
  final VoidCallback? onLongPress;

  const LiveStreamIndicator({super.key, this.onLongPress});

  @override
  State<LiveStreamIndicator> createState() => _LiveStreamIndicatorState();
}

class _LiveStreamIndicatorState extends State<LiveStreamIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RealtimePipelineService>(
      builder: (ctx, pipeline, _) {
        if (!pipeline.isConnected || pipeline.latestUpdate == null) {
          return const SizedBox.shrink();
        }
        final update = pipeline.latestUpdate!;
        return GestureDetector(
          onLongPress: widget.onLongPress,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.10),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, child) => Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color.lerp(
                        const Color(0xFF00C06A),
                        const Color(0xFF00E080),
                        _pulseCtrl.value,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Text(
                  'LIVE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF5C6B7A),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                Container(width: 1, height: 12, color: const Color(0xFFEEF1F5)),
                const SizedBox(width: 8),
                Text(
                  update.riskScore.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: update.levelColor,
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
