import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import '../services/drowsiness_detection_service.dart';
import '../models/drowsiness_metrics_model.dart';

class DrowsinessCameraPreview extends StatelessWidget {
  const DrowsinessCameraPreview({super.key});

  Color _borderColorFor(DrowsinessMetrics? metrics) {
    if (metrics == null) return const Color(0xFF00C06A);
    return metrics.levelColor;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DrowsinessDetectionService>(
      builder: (context, service, _) {
        final isReady = service.isCameraReady;
        final borderColor = _borderColorFor(service.currentMetrics);

        return Container(
          width: 92,
          height: 122,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: !isReady
              ? Container(
                  color: const Color(0xFF0D1B2A),
                  alignment: Alignment.center,
                  child: const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white54),
                    ),
                  ),
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Transform(
                      alignment: Alignment.center,
                      // Mirror horizontally for natural front-camera view
                      transform: Matrix4.rotationY(math.pi),
                      child: CameraPreview(service.cameraController!),
                    ),
                    // Small live indicator dot, top-right corner
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFFF3B5C),
                        ),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
