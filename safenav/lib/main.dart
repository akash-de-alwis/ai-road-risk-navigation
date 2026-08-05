import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import './shared/constants/app_constants.dart';
import './shared/providers/app_provider.dart';
import './shared/services/auth_service.dart';
import './shared/services/offline_map_service.dart';
import './member3_alert_system/part1/services/alert_service.dart';
import './member3_alert_system/part1/services/notification_service.dart';
import './member4_driver_scoring/part1/services/sensor_service.dart';
import './member1_risk_prediction/part2/services/realtime_risk_service.dart';
import './member1_risk_prediction/part2/services/vehicle_preference_service.dart';
import './member2_route_engine/part2/services/enhanced_route_service.dart';
import './member3_alert_system/part2/services/obstacle_preference_service.dart';
import './member3_alert_system/part2/services/obstacle_scan_service.dart';
import './member3_alert_system/part2/services/obstacle_voice_service.dart';
import './member3_alert_system/part2/services/obstacle_alert_orchestrator.dart';
import './features/member4_part2/services/drowsiness_preference_service.dart';
import './features/member4_part2/services/drowsiness_calibration_service.dart';
import './features/member4_part2/services/drowsiness_alert_service.dart';
import './features/member4_part2/services/drowsiness_detection_service.dart';
import './features/member5_vehicle_distance/services/distance_alert_service.dart';
import './features/member5_vehicle_distance/services/distance_preference_service.dart';
import './features/member5_vehicle_distance/services/vehicle_distance_service.dart';
import './features/member1b_realtime_pipeline/services/realtime_pipeline_service.dart';
import './app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  MapboxOptions.setAccessToken(AppConstants.mapboxToken);
  await Firebase.initializeApp();
  await _requestPermissions();
  await NotificationService.instance.init();

  runApp(const AppRoot());
}

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppProvider()),
        ChangeNotifierProvider(create: (_) => OfflineMapService()),
        ChangeNotifierProvider(create: (_) => SensorService.instance),
        ChangeNotifierProvider(
          create: (ctx) => AlertService(
            sensorService: ctx.read<SensorService>(),
          ),
        ),
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => RealtimeRiskService()),
        ChangeNotifierProvider(create: (_) => RealtimePipelineService()),
        ChangeNotifierProvider(create: (_) => EnhancedRouteService()),
        ChangeNotifierProvider(
          create: (_) {
            final svc = VehiclePreferenceService();
            svc.loadFromStorage();
            return svc;
          },
        ),
        ChangeNotifierProvider(
          create: (_) {
            final svc = ObstaclePreferenceService();
            svc.loadFromStorage();
            return svc;
          },
        ),
        ChangeNotifierProvider(create: (_) => ObstacleScanService()),
        Provider(
          create: (_) {
            final v = ObstacleVoiceService();
            v.init();
            return v;
          },
          dispose: (_, v) => v.dispose(),
        ),
        ChangeNotifierProxyProvider3<ObstacleScanService, ObstacleVoiceService,
            ObstaclePreferenceService, ObstacleAlertOrchestrator>(
          create: (ctx) => ObstacleAlertOrchestrator(
            scanService: ctx.read<ObstacleScanService>(),
            voiceService: ctx.read<ObstacleVoiceService>(),
            preferences: ctx.read<ObstaclePreferenceService>(),
          ),
          update: (_, scan, voice, prefs, prev) =>
              prev ??
              ObstacleAlertOrchestrator(
                scanService: scan,
                voiceService: voice,
                preferences: prefs,
              ),
        ),
        // ── Member 4 Part 2 — Drowsiness Detection ──────────────────────
        ChangeNotifierProvider(
          create: (_) {
            final p = DrowsinessPreferenceService();
            p.loadFromStorage();
            return p;
          },
        ),
        ChangeNotifierProvider(
          create: (_) => DrowsinessCalibrationService(),
        ),
        ChangeNotifierProxyProvider<DrowsinessPreferenceService,
            DrowsinessAlertService>(
          create: (ctx) {
            final a = DrowsinessAlertService(
              preferences: ctx.read<DrowsinessPreferenceService>(),
            );
            a.init();
            return a;
          },
          update: (_, prefs, prev) => prev!,
        ),
        ChangeNotifierProxyProvider3<DrowsinessPreferenceService,
            DrowsinessCalibrationService, DrowsinessAlertService,
            DrowsinessDetectionService>(
          create: (ctx) => DrowsinessDetectionService(
            preferences: ctx.read<DrowsinessPreferenceService>(),
            calibration: ctx.read<DrowsinessCalibrationService>(),
            alertService: ctx.read<DrowsinessAlertService>(),
          ),
          update: (_, prefs, calib, alert, prev) => prev!,
        ),
        ChangeNotifierProvider(
          create: (_) {
            final p = DistancePreferenceService();
            p.loadFromStorage();
            return p;
          },
        ),
        ChangeNotifierProxyProvider<DistancePreferenceService,
            DistanceAlertService>(
          create: (ctx) {
            final a = DistanceAlertService(
              preferences: ctx.read<DistancePreferenceService>(),
            );
            a.init();
            return a;
          },
          update: (_, prefs, prev) => prev!,
        ),
        ChangeNotifierProxyProvider2<DistancePreferenceService,
            DistanceAlertService, VehicleDistanceService>(
          create: (ctx) => VehicleDistanceService(
            preferences: ctx.read<DistancePreferenceService>(),
            alertService: ctx.read<DistanceAlertService>(),
          ),
          update: (_, prefs, alert, prev) => prev!,
        ),
      ],
      child: const SafeNavApp(),
    );
  }
}

Future<void> _requestPermissions() async {
  final whenInUse = await Permission.locationWhenInUse.request();
  if (whenInUse.isGranted) {
    await Permission.locationAlways.request();
  }
  await Permission.notification.request();
}
