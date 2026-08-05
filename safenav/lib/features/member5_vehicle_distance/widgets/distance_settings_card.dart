import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/distance_preference_service.dart';
import 'distance_permission_dialog.dart';

class DistanceSettingsCard extends StatelessWidget {
  const DistanceSettingsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DistancePreferenceService>(
      builder: (ctx, prefs, _) => _Body(prefs: prefs),
    );
  }
}

class _Body extends StatelessWidget {
  final DistancePreferenceService prefs;
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
                    child: const Icon(Icons.directions_car_rounded,
                        color: Color(0xFF2979FF), size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vehicle Distance Estimator',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0D1B2A),
                          ),
                        ),
                        Text(
                          'Rear camera monitors the road ahead on-device',
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
                            await DistancePermissionDialog.show(context);
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

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Following distance rule',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0D1B2A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _RuleChip(
                          label: 'New Learner (3s)',
                          selected: prefs.followingRule == 'NEW_LEARNER',
                          onTap: () => prefs.setFollowingRule('NEW_LEARNER'),
                        ),
                        _RuleChip(
                          label: 'Standard (2s)',
                          selected: prefs.followingRule == 'STANDARD',
                          onTap: () => prefs.setFollowingRule('STANDARD'),
                        ),
                        _RuleChip(
                          label: 'Extra Cautious (4s)',
                          selected: prefs.followingRule == 'CAUTIOUS',
                          onTap: () => prefs.setFollowingRule('CAUTIOUS'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, color: Color(0xFFEEF1F5)),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Row(
                  children: [
                    const Icon(Icons.photo_camera_outlined,
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
                            'Shows a small rear-camera preview during trips',
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

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Alert style',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0D1B2A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _RuleChip(
                          label: 'Voice + Visual',
                          selected: prefs.alertStyle == 'voice_visual',
                          onTap: () => prefs.setAlertStyle('voice_visual'),
                        ),
                        _RuleChip(
                          label: 'Visual only',
                          selected: prefs.alertStyle == 'visual_only',
                          onTap: () => prefs.setAlertStyle('visual_only'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, color: Color(0xFFEEF1F5)),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Camera analysis happens entirely on your device.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF5C6B7A),
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'If drowsiness detection is also enabled, only one camera feature can run at a time on some devices.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF5C6B7A),
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

class _RuleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RuleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2979FF) : const Color(0xFFF4F6F9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF5C6B7A),
          ),
        ),
      ),
    );
  }
}