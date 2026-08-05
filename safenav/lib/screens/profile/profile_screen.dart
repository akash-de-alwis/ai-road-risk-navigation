import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../shared/services/auth_service.dart';
import '../../shared/services/offline_map_service.dart';
import '../../member3_alert_system/part1/services/alert_service.dart';
import '../../member4_driver_scoring/part1/models/trip_session.dart';
import '../../member4_driver_scoring/part1/services/sensor_service.dart';
import '../../shared/widgets/offline_map_sheet.dart';
import '../../member1_risk_prediction/part2/models/vehicle_type_model.dart';
import '../../member1_risk_prediction/part2/services/vehicle_preference_service.dart';
import '../../member1_risk_prediction/part2/widgets/vehicle_selection_sheet.dart';
import '../../member3_alert_system/part2/widgets/obstacle_settings_card.dart';
import '../../features/member4_part2/widgets/drowsiness_settings_card.dart';
import '../../features/member5_vehicle_distance/widgets/distance_settings_card.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<List<TripSession>> _historyFuture;
  final _scrollCtrl = ScrollController();
  final _settingsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _historyFuture = context.read<SensorService>().getTripHistory();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToSettings() {
    final ctx = _settingsKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    }
  }

  String _timeAgo(DateTime start) {
    final diff = DateTime.now().difference(start);
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return h == 0 ? 'Just now' : '$h hour${h > 1 ? 's' : ''} ago';
    }
    if (diff.inDays == 1) return 'Yesterday';
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${names[start.weekday - 1]} ${start.day}/${start.month}';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final sensor = context.watch<SensorService>();
    final alertSvc = context.watch<AlertService>();
    final offlineSvc = context.watch<OfflineMapService>();
    final currentScore = sensor.currentTrip?.safetyScore ?? 78;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Fixed hero — never scrolls ─────────────────────────────────
          FutureBuilder<List<TripSession>>(
            future: _historyFuture,
            builder: (_, snap) =>
                _HeroHeader(auth: auth, trips: snap.data ?? []),
          ),

          // ── Scrollable white section ────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // White card
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(28)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 20),
                        _QuickActions(
                          onMap: () => context.go('/map'),
                          onScore: () => context.go('/score'),
                          onOffline: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => ChangeNotifierProvider.value(
                              value: offlineSvc,
                              child: const OfflineMapSheet(),
                            ),
                          ),
                          onSettings: _scrollToSettings,
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Divider(height: 1, color: Color(0xFFEEF1F5)),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _SafetyBadge(score: currentScore),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),

                  // ── Recent trips ─────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Recent Trips',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0D1B2A),
                          ),
                        ),
                        const Text(
                          'See all',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF2979FF),
                          ),
                        ),
                      ],
                    ),
                  ),

                  FutureBuilder<List<TripSession>>(
                    future: _historyFuture,
                    builder: (_, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF2979FF),
                            ),
                          ),
                        );
                      }
                      final trips = snap.data ?? [];
                      if (trips.isEmpty) return const _EmptyTrips();
                      return Column(
                        children: trips
                            .take(5)
                            .map((t) => _TripCard(
                                  trip: t,
                                  userName: auth.userName,
                                  timeAgo: _timeAgo(t.startTime),
                                ))
                            .toList(),
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // ── Settings ──────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Text(
                      'Settings',
                      key: _settingsKey,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0D1B2A),
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _SettingsCard(
                      alertSvc: alertSvc,
                      offlineSvc: offlineSvc,
                    ),
                  ),

                  const ObstacleSettingsCard(),

                  const DrowsinessSettingsCard(),

                  const DistanceSettingsCard(),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // ── Fixed sign-out footer — always above the nav bar ───────────
          Container(
            color: const Color(0xFFF5F7FF),
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              MediaQuery.of(context).viewPadding.bottom + 92 + 12,
            ),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton(
                onPressed: () async {
                  await auth.signOut();
                  if (context.mounted) context.go('/login');
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(
                      color: Color(0xFFFF3B5C), width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout_rounded,
                        color: Color(0xFFFF3B5C), size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Sign out',
                      style: TextStyle(
                        color: Color(0xFFFF3B5C),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hero header ───────────────────────────────────────────────────────────────

class _HeroHeader extends StatelessWidget {
  final AuthService auth;
  final List<TripSession> trips;
  const _HeroHeader({required this.auth, required this.trips});

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.of(context).padding.top;
    final totalDist =
        trips.fold<double>(0, (s, t) => s + t.totalDistanceKm);
    final bestScore = trips.isEmpty
        ? 78
        : trips.map((t) => t.safetyScore).reduce((a, b) => a > b ? a : b);
    final badgeScore = bestScore.toString();

    return Container(
      height: 260,
      padding: EdgeInsets.only(top: safeTop + 8, left: 20, right: 20),
      decoration: const BoxDecoration(
        color: Color(0xFF1A56CC),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(Icons.arrow_back_ios_rounded,
                  color: Colors.white, size: 20),
              Icon(Icons.more_vert_rounded, color: Colors.white, size: 22),
            ],
          ),

          const SizedBox(height: 16),

          // Avatar + name
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  auth.userPhotoUrl.isNotEmpty
                      ? CircleAvatar(
                          radius: 30,
                          backgroundImage: NetworkImage(auth.userPhotoUrl),
                        )
                      : CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.white,
                          child: Text(
                            auth.userInitials,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2979FF),
                            ),
                          ),
                        ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFF2979FF), width: 2),
                      ),
                      child: Center(
                        child: Text(
                          badgeScore,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2979FF),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      auth.userName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'SafeNav Driver',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.70),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.location_on_rounded,
                            size: 14,
                            color: Colors.white.withValues(alpha: 0.70)),
                        const SizedBox(width: 4),
                        Text(
                          'Panadura, Sri Lanka',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.70),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _HeroStat(value: trips.length.toString(), label: 'TRIPS'),
              Container(
                  width: 1,
                  height: 28,
                  color: Colors.white.withValues(alpha: 0.30)),
              _HeroStat(
                value: '${totalDist.toStringAsFixed(1)} km',
                label: 'DISTANCE',
              ),
              Container(
                  width: 1,
                  height: 28,
                  color: Colors.white.withValues(alpha: 0.30)),
              _HeroStat(value: bestScore.toString(), label: 'BEST SCORE'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String value;
  final String label;
  const _HeroStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 11,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

// ── Quick actions ─────────────────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  final VoidCallback onMap;
  final VoidCallback onScore;
  final VoidCallback onOffline;
  final VoidCallback onSettings;

  const _QuickActions({
    required this.onMap,
    required this.onScore,
    required this.onOffline,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _HexButton(icon: Icons.map_rounded, label: 'My Map', onTap: onMap),
          _HexButton(
              icon: Icons.shield_rounded, label: 'My Score', onTap: onScore),
          _HexButton(
              icon: Icons.download_rounded, label: 'Offline', onTap: onOffline),
          _HexButton(
              icon: Icons.settings_rounded,
              label: 'Settings',
              onTap: onSettings),
        ],
      ),
    );
  }
}

class _HexButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _HexButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F0FE),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: const Color(0xFF2979FF), size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Color(0xFF5C6B7A)),
          ),
        ],
      ),
    );
  }
}


// ── Safety badge ──────────────────────────────────────────────────────────────

class _SafetyBadge extends StatelessWidget {
  final int score;
  const _SafetyBadge({required this.score});

  @override
  Widget build(BuildContext context) {
    final label = score >= 85
        ? 'Excellent Driver'
        : score >= 70
            ? 'Good Driver'
            : score >= 50
                ? 'Fair Driver'
                : 'Keep Improving';
    final stars = score >= 85
        ? 5
        : score >= 70
            ? 4
            : score >= 50
                ? 3
                : 2;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A56CC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SAFETY RATING',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.70),
                  fontSize: 11,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$score/100',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: List.generate(
              5,
              (i) => Icon(
                Icons.star_rounded,
                size: 18,
                color: i < stars
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.30),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyTrips extends StatelessWidget {
  const _EmptyTrips();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEEF1F5), width: 0.5),
        ),
        child: const Column(
          children: [
            Icon(Icons.map_outlined, size: 48, color: Color(0xFFB5D4F4)),
            SizedBox(height: 12),
            Text(
              'No trips yet',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF0D1B2A),
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Start navigation to record your first trip',
              style: TextStyle(fontSize: 12, color: Color(0xFF5C6B7A)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Trip card ─────────────────────────────────────────────────────────────────

class _TripCard extends StatelessWidget {
  final TripSession trip;
  final String userName;
  final String timeAgo;
  const _TripCard(
      {required this.trip, required this.userName, required this.timeAgo});

  @override
  Widget build(BuildContext context) {
    final color = trip.scoreColor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: const Color(0xFFEEF1F5), width: 0.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Route icon
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFE8F0FE),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.route_rounded,
                  color: Color(0xFF2979FF), size: 26),
            ),

            const SizedBox(width: 12),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    timeAgo,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFFADB8C3)),
                  ),
                  const SizedBox(height: 3),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF5C6B7A)),
                      children: [
                        TextSpan(
                          text: userName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0D1B2A),
                          ),
                        ),
                        const TextSpan(text: ' completed a trip '),
                        const WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Icon(Icons.directions_car_rounded,
                              size: 14, color: Color(0xFF2979FF)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _MiniStat(
                        value:
                            '${trip.totalDistanceKm.toStringAsFixed(1)} km',
                        label: 'DISTANCE',
                      ),
                      const _StatDivider(),
                      _MiniStat(
                        value:
                            '${trip.maxSpeedKmh.toStringAsFixed(0)} km/h',
                        label: 'MAX SPEED',
                      ),
                      const _StatDivider(),
                      _MiniStat(
                        value: '${trip.duration} min',
                        label: 'DURATION',
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Score badge
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${trip.safetyScore}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                const Text('/100',
                    style: TextStyle(
                        fontSize: 10, color: Color(0xFF5C6B7A))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String value;
  final String label;
  const _MiniStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0D1B2A),
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Color(0xFF5C6B7A),
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: const Color(0xFFEEF1F5),
    );
  }
}

// ── Settings card ─────────────────────────────────────────────────────────────

class _SettingsCard extends StatelessWidget {
  final AlertService alertSvc;
  final OfflineMapService offlineSvc;
  const _SettingsCard({required this.alertSvc, required this.offlineSvc});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF1F5), width: 0.5),
      ),
      child: Column(
        children: [
          _SettingRow(
            icon: Icons.notifications_rounded,
            label: 'Safety Alerts',
            trailing: Switch(
              value: alertSvc.isEnabled,
              onChanged: (_) => alertSvc.toggleAlerts(),
              activeThumbColor: const Color(0xFF2979FF),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const _SettingsDivider(),
          _SettingRow(
            icon: Icons.notifications_active_rounded,
            label: 'In-App Alerts',
            trailing: Switch(
              value: alertSvc.isInAppAlertsEnabled,
              onChanged: alertSvc.isEnabled
                  ? (_) => alertSvc.toggleInAppAlerts()
                  : null,
              activeThumbColor: const Color(0xFF2979FF),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const _SettingsDivider(),
          _SettingRow(
            icon: Icons.volume_up_rounded,
            label: 'Voice Alerts',
            trailing: Switch(
              value: alertSvc.isVoiceEnabled,
              onChanged: alertSvc.isEnabled ? (_) => alertSvc.toggleVoice() : null,
              activeThumbColor: const Color(0xFF2979FF),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const _SettingsDivider(),
          _SettingRow(
            icon: Icons.translate_rounded,
            label: 'Alert Language',
            trailing: GestureDetector(
              onTap: alertSvc.toggleLanguage,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2979FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  alertSvc.currentLanguage == 'en' ? 'EN' : 'සිං',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          const _SettingsDivider(),
          _SettingRow(
            icon: Icons.download_rounded,
            label: 'Offline Map',
            trailing: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: offlineSvc.isDownloaded
                    ? const Color(0xFFE8F5E9)
                    : const Color(0xFFF4F6F9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                offlineSvc.isDownloaded ? 'Downloaded' : 'Not saved',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: offlineSvc.isDownloaded
                      ? const Color(0xFF00873E)
                      : const Color(0xFF5C6B7A),
                ),
              ),
            ),
          ),
          const _SettingsDivider(),
          Consumer<VehiclePreferenceService>(
            builder: (ctx, pref, _) {
              final v = VehicleTypes.byId(pref.defaultVehicle);
              return _SettingRow(
                icon: Icons.directions_car_rounded,
                label: 'Default Vehicle',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      v.displayName,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF5C6B7A),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right,
                        size: 18, color: Color(0xFF9AA3B2)),
                  ],
                ),
                onTap: () async {
                  await VehicleSelectionSheet.show(
                    context,
                    showSetDefaultOption: false,
                    forceSetDefault: true,
                  );
                },
              );
            },
          ),
          const _SettingsDivider(),
          _SettingRow(
            icon: Icons.credit_card_rounded,
            label: 'Plans & Billing',
            onTap: () => context.push('/billing'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F0FE),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Free',
                    style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFF2979FF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right,
                    size: 18, color: Color(0xFF9AA3B2)),
              ],
            ),
          ),
          const _SettingsDivider(),
          _SettingRow(
            icon: Icons.info_rounded,
            label: 'About SafeNav',
            isLast: true,
            onLongPress: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('onboarding_complete', false);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content:
                        Text('Onboarding reset — restart app to see it'),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  final bool isLast;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _SettingRow({
    required this.icon,
    required this.label,
    this.trailing,
    this.isLast = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F0FE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: const Color(0xFF2979FF), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                      fontSize: 14, color: Color(0xFF0D1B2A)),
                ),
              ),
              trailing ??
                  const Icon(Icons.chevron_right,
                      size: 18, color: Color(0xFF9AA3B2)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, indent: 56, color: Color(0xFFEEF1F5));
  }
}
