import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/vehicle_distance_service.dart';

class DistanceCameraOverlay extends StatelessWidget {
  const DistanceCameraOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<VehicleDistanceService>(
      builder: (context, service, _) {
        final isReady = service.cameraController != null &&
            service.cameraController!.value.isInitialized;
        final estimate = service.currentEstimate;
        final tracked = service.currentTrackedVehicle;
        final borderColor = estimate?.severityColor ?? const Color(0xFF00C06A);

        return Container(
          width: 108,
          height: 144,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
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
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final frame = service.lastFrameSize;
                    final previewSize = constraints.biggest;
                    Rect? boxRect;
                    if (frame != null && tracked != null &&
                        frame.width > 0 && frame.height > 0) {
                      final scaleX = previewSize.width / frame.width;
                      final scaleY = previewSize.height / frame.height;
                      boxRect = Rect.fromLTWH(
                        tracked.left * scaleX,
                        tracked.top * scaleY,
                        tracked.width * scaleX,
                        tracked.height * scaleY,
                      ).intersect(Offset.zero & previewSize);
                    }

                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(service.cameraController!),
                        if (boxRect != null)
                          Positioned.fromRect(
                            rect: boxRect,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: borderColor,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        if (estimate != null && boxRect != null)
                          Positioned(
                            left: math.max(4, boxRect.left),
                            top: math.max(4, boxRect.top - 18),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: borderColor,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${estimate.distanceM.toStringAsFixed(1)} m',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
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
                    );
                  },
                ),
        );
      },
    );
  }
}