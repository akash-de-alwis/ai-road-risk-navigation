import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/drowsiness_preference_service.dart';
import 'drowsiness_permission_dialog.dart';

class DrowsinessSettingsCard extends StatelessWidget {
  const DrowsinessSettingsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DrowsinessPreferenceService>(
      builder: (ctx, prefs, _) => _Body(prefs: prefs),
    );
  }
}

class _Body extends StatelessWidget {
  final DrowsinessPreferenceService prefs;
  const _Body({required this.prefs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEEF1F5), width: 0.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Master toggle row ──────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F0FE),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.remove_red_eye_rounded,
                        color: Color(0xFF2979FF), size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Drowsiness Detection',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0D1B2A),
                          ),
                        ),
                        Text(
                          'Front camera monitors alertness on-device',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF5C6B7A)),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: prefs.detectionEnabled,
                    onChanged: (v) async {
                      if (v) {
                        final granted =
                            await DrowsinessPermissionDialog.show(context);
                        if (granted == true) {
                          await prefs.setDetectionEnabled(true);
                        }
                      } else {
                        await prefs.setDetectionEnabled(false);
                      }
                    },
                    activeThumbColor: const Color(0xFF2979FF),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
            ),

            if (prefs.detectionEnabled) ...[
              const Divider(height: 1, color: Color(0xFFEEF1F5)),

              // ── Sensitivity ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sensitivity',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0D1B2A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: ['LOW', 'MEDIUM', 'HIGH'].map((s) {
                        final selected = prefs.sensitivity == s;
                        final label =
                            s[0] + s.substring(1).toLowerCase();
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => prefs.setSensitivity(s),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFF2979FF)
                                    : const Color(0xFFF4F6F9),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: selected
                                      ? Colors.white
                                      : const Color(0xFF5C6B7A),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, color: Color(0xFFEEF1F5)),

              // ── Alert style ────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Alert Style',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0D1B2A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: const [
                        ('voice_visual', 'Voice + Visual'),
                        ('visual_only', 'Visual only'),
                      ].map((opt) {
                        final selected = prefs.alertStyle == opt.$1;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => prefs.setAlertStyle(opt.$1),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFF2979FF)
                                    : const Color(0xFFF4F6F9),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                opt.$2,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: selected
                                      ? Colors.white
                                      : const Color(0xFF5C6B7A),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, color: Color(0xFFEEF1F5)),

              // ── Camera preview ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Row(
                  children: [
                    const Icon(Icons.camera_alt_outlined,
                        size: 18, color: Color(0xFF5C6B7A)),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Show camera preview',
                            style: TextStyle(
                                fontSize: 13, color: Color(0xFF0D1B2A)),
                          ),
                          Text(
                            'Replaces the monitoring chip with a live view',
                            style: TextStyle(
                                fontSize: 10.5, color: Color(0xFF5C6B7A)),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: prefs.showCameraPreview,
                      activeThumbColor: const Color(0xFF2979FF),
                      onChanged: (v) => prefs.setShowCameraPreview(v),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, color: Color(0xFFEEF1F5)),

              // ── Recalibrate ────────────────────────────────────────────────
              GestureDetector(
                onTap: () async {
                  await prefs.clearBaseline();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Baseline cleared — calibration runs on next trip.'),
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F0FE),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.refresh_rounded,
                            color: Color(0xFF2979FF), size: 18),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Recalibrate now',
                          style: TextStyle(
                              fontSize: 13, color: Color(0xFF0D1B2A)),
                        ),
                      ),
                      prefs.baseline != null
                          ? const Icon(Icons.check_circle_rounded,
                              color: Color(0xFF00C06A), size: 16)
                          : const Icon(Icons.radio_button_unchecked,
                              color: Color(0xFFADB8C3), size: 16),
                    ],
                  ),
                ),
              ),

              const Divider(height: 1, color: Color(0xFFEEF1F5)),

              // ── Privacy notice ─────────────────────────────────────────────
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_rounded,
                        size: 14, color: Color(0xFF00C06A)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'All processing happens on your device. No images '
                        'are recorded or uploaded.',
                        style: TextStyle(
                            fontSize: 11, color: Color(0xFF5C6B7A)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
