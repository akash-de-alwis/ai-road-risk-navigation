import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class DistancePermissionDialog extends StatelessWidget {
  const DistancePermissionDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const DistancePermissionDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F0FE),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.camera_rear_rounded,
                color: Color(0xFF2979FF), size: 32),
          ),
          const SizedBox(height: 16),
          const Text(
            'Rear Camera Access Needed',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0D1B2A),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          const Text(
            'SafeNav uses the rear camera to watch the road ahead and estimate following distance on-device. No video is recorded or uploaded.',
            style: TextStyle(fontSize: 13, color: Color(0xFF5C6B7A)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_rounded, size: 14, color: Color(0xFF00873E)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'All camera analysis happens entirely on your device.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF00873E)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(
            'Not now',
            style: TextStyle(color: Color(0xFF5C6B7A)),
          ),
        ),
        ElevatedButton(
          onPressed: () async {
            final status = await Permission.camera.request();
            if (context.mounted) {
              Navigator.of(context).pop(status.isGranted);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2979FF),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: const Text('Allow Camera Access'),
        ),
      ],
    );
  }
}