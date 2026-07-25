import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../../shared/constants/app_constants.dart';
import '../../member1_risk_prediction/part1/models/hotspot_model.dart';
import '../../shared/providers/app_provider.dart';
import '../../shared/services/api_service.dart';
import '../../shared/services/offline_map_service.dart';
import '../../member3_alert_system/part1/services/alert_service.dart';
import '../../member4_driver_scoring/part1/models/trip_session.dart';
import '../../member4_driver_scoring/part1/services/sensor_service.dart';
import '../../shared/theme/app_colors.dart';
import '../../member1_risk_prediction/part1/widgets/hotspot_marker_painter.dart';
import '../../shared/widgets/place_search_sheet.dart';
import '../../member2_route_engine/part1/widgets/route_layer_widget.dart';
import '../../member4_driver_scoring/part1/screens/trip_summary_screen.dart';
import '../../member1_risk_prediction/part2/widgets/realtime_risk_hud.dart';
import '../../member1_risk_prediction/part2/services/realtime_risk_service.dart';
import '../../member1_risk_prediction/part2/models/realtime_risk_model.dart';
import '../../member1_risk_prediction/part2/services/vehicle_preference_service.dart';
import '../../member1_risk_prediction/part2/widgets/vehicle_selection_sheet.dart';
import '../../member1_risk_prediction/part2/widgets/vehicle_picker_button.dart';
import '../../member2_route_engine/part2/models/enhanced_route_model.dart';
import '../../member2_route_engine/part2/services/enhanced_route_service.dart';
import '../../member2_route_engine/part2/widgets/enhanced_route_options_sheet.dart';
import '../../core/map/widgets/unified_search_bar.dart';
import '../../core/map/widgets/map_action_stack.dart';
import '../../core/map/widgets/layers_popup.dart';
import '../../core/map/widgets/legend_popup.dart';
import '../../core/map/widgets/quick_destinations_row.dart';
import '../../core/map/widgets/high_risk_banner.dart';
import '../../member3_alert_system/part2/models/obstacle_model.dart';
import '../../member3_alert_system/part2/services/obstacle_preference_service.dart';
import '../../member3_alert_system/part2/services/obstacle_scan_service.dart';
import '../../member3_alert_system/part2/services/obstacle_alert_orchestrator.dart';
import '../../member3_alert_system/part2/widgets/obstacle_marker_painter.dart';
import '../../core/map/widgets/obstacle_alert_card.dart';
import '../../features/member4_part2/services/drowsiness_preference_service.dart';
import '../../features/member4_part2/services/drowsiness_calibration_service.dart';
import '../../features/member4_part2/services/drowsiness_detection_service.dart';
import '../../features/member4_part2/services/drowsiness_alert_service.dart';
import '../../features/member4_part2/widgets/drowsiness_calibration_overlay.dart';
import '../../features/member4_part2/widgets/drowsiness_alert_overlay.dart';
import '../../features/member4_part2/widgets/drowsiness_status_chip.dart';
import '../../features/member4_part2/widgets/drowsiness_camera_preview.dart';
import '../../features/member1b_realtime_pipeline/services/realtime_pipeline_service.dart';
import '../../features/member1b_realtime_pipeline/widgets/live_stream_indicator.dart';
import '../../features/member1b_realtime_pipeline/widgets/stream_debug_panel.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapboxMap? _mapboxMap;
  geo.Position? _currentPosition;
  double? _currentLat;
  double? _currentLng;
  PointAnnotationManager? _pointAnnotationManager;
  PointAnnotationManager? _destinationPointAnnotationManager;
  PointAnnotationManager? _tripAnnotationManager;
  PointAnnotationManager? _obstacleAnnotationManager;
  ObstacleScanService? _obstacleScanServiceRef;
  AppProvider? _appProvider;
  StreamSubscription<geo.Position>? _positionSub;
  bool _hasFlewToLocation = false;

  String? _activeDestinationName;
  double? _destLat;
  double? _destLng;
  double? _originLat;
  double? _originLng;

  bool _isPickingLocation = false;
  bool _pickingForOrigin = false;
  bool _isReverseGeocoding = false;

  int _lastDrawnRouteCount = 0;
  int _lastDrawnSelectedIndex = -1;
  int _lastDrawnGeoCount = -1;
  bool _showHighRisk = true;
  bool _showMediumRisk = true;
  bool _showLowRisk = true;

  int get _activeFilters {
    int n = 0;
    if (!_showHighRisk) n++;
    if (!_showMediumRisk) n++;
    if (!_showLowRisk) n++;
    return n;
  }

  PolylineAnnotationManager? _enhancedRouteManager;
  EnhancedRouteService? _enhancedRouteSvcRef;

  // ── Member 4 Part 2 — drowsiness calibration overlay state ───────────────
  bool _showCalibrationOverlay = false;
  int _calibrationSecondsLeft = 15;

  // ── Member 1b — real-time pipeline debug panel toggle ────────────────────
  bool _showStreamDebugPanel = false;

  List<Map<String, dynamic>> _activeAlerts = [];
  AlertService? _alertServiceRef;

  @override
  void initState() {
    super.initState();
    _initLocation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pref = context.read<VehiclePreferenceService>();
      if (!pref.hasSelectedThisSession) {
        VehicleSelectionSheet.show(context, showSetDefaultOption: true);
      }
      // Always sync risk service with the current vehicle on map entry
      context.read<RealtimeRiskService>().vehicleType = pref.currentVehicle;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<AppProvider>();
    if (_appProvider == null) {
      _appProvider = provider;
      _appProvider!.addListener(_onHotspotsUpdated);
      _appProvider!.initializeApp();
      context.read<OfflineMapService>().checkIfAlreadyDownloaded();
    }
    final alertSvc = context.read<AlertService>();
    if (_alertServiceRef == null) {
      _alertServiceRef = alertSvc;
      _alertServiceRef!.addListener(_onAlertsChanged);
      alertSvc.startAlertMonitoring();
    }
    if (_enhancedRouteSvcRef == null) {
      _enhancedRouteSvcRef = context.read<EnhancedRouteService>();
      _enhancedRouteSvcRef!.onRouteChanged = (_) => _drawAllEnhancedRoutes();
    }
    if (_obstacleScanServiceRef == null) {
      _obstacleScanServiceRef = context.read<ObstacleScanService>();
      _obstacleScanServiceRef!.addListener(_onObstaclesUpdated);
    }
  }

  void _onObstaclesUpdated() {
    if (!mounted) return;
    final svc = _obstacleScanServiceRef;
    if (svc != null && !svc.isLoading) {
      _drawObstacleMarkers(svc.obstacles);
    }
  }

  void _onAlertsChanged() {
    if (!mounted) return;
    setState(() {
      final svc = _alertServiceRef;
      _activeAlerts = (svc != null && svc.isEnabled)
          ? List<Map<String, dynamic>>.from(svc.activeAlerts)
          : [];
    });
  }

  @override
  void dispose() {
    _enhancedRouteSvcRef?.onRouteChanged = null;
    _alertServiceRef?.removeListener(_onAlertsChanged);
    _obstacleScanServiceRef?.removeListener(_onObstaclesUpdated);
    _positionSub?.cancel();
    _appProvider?.removeListener(_onHotspotsUpdated);
    super.dispose();
  }

  void _onHotspotsUpdated() {
    if (!mounted) return;
    if (_pointAnnotationManager != null) _refreshHotspotAnnotations();
    _maybeDrawRoutes();
  }

  void _maybeDrawRoutes() {
    final provider = _appProvider;
    final map = _mapboxMap;
    if (provider == null || map == null) return;

    if (provider.currentRoutes.isEmpty) {
      _lastDrawnRouteCount = 0;
      _lastDrawnSelectedIndex = -1;
      _lastDrawnGeoCount = -1;
      return;
    }

    final routeCount = provider.currentRoutes.length;
    final selectedIndex = provider.selectedRouteIndex;
    final geoCount = provider.roadGeometries.length;

    if (routeCount == _lastDrawnRouteCount &&
        selectedIndex == _lastDrawnSelectedIndex &&
        geoCount == _lastDrawnGeoCount) {
      return;
    }

    _lastDrawnRouteCount = routeCount;
    _lastDrawnSelectedIndex = selectedIndex;
    _lastDrawnGeoCount = geoCount;

    drawRoutesOnMap(
      map,
      provider.currentRoutes,
      selectedIndex,
      roadGeometries: provider.roadGeometries.isNotEmpty
          ? provider.roadGeometries
          : null,
    );
  }

  // ── Location ──────────────────────────────────────────────────────────────

  Future<void> _initLocation() async {
    try {
      final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
      }
      if (permission == geo.LocationPermission.denied ||
          permission == geo.LocationPermission.deniedForever) {
        return;
      }

      if (!mounted) return;

      try {
        final pos = await geo.Geolocator.getCurrentPosition(
          desiredAccuracy: geo.LocationAccuracy.bestForNavigation,
        ).timeout(const Duration(seconds: 15));
        if (mounted) _applyPosition(pos, fly: true);
      } catch (_) {}

      _positionSub = geo.Geolocator.getPositionStream(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.bestForNavigation,
          distanceFilter: 10,
        ),
      ).listen(
        (pos) {
          if (!mounted) return;
          _applyPosition(pos, fly: !_hasFlewToLocation);
        },
        onError: (_) {},
      );
    } catch (_) {}
  }

  void _applyPosition(geo.Position pos, {bool fly = false}) {
    setState(() {
      _currentPosition = pos;
      _currentLat = pos.latitude;
      _currentLng = pos.longitude;
    });
    if (_appProvider?.isUsingGps == true) {
      _appProvider?.setGpsLocation(pos.latitude, pos.longitude);
    }
    if (fly && !_hasFlewToLocation) {
      _hasFlewToLocation = true;
      _flyToLocation(pos.longitude, pos.latitude);
    }
  }

  // ── Map pick mode ─────────────────────────────────────────────────────────

  void _enterPickMode({required bool isOrigin}) {
    setState(() {
      _isPickingLocation = true;
      _pickingForOrigin = isOrigin;
    });
  }

  void _cancelPickMode() => setState(() => _isPickingLocation = false);

  void _onMapTap(MapContentGestureContext context) {
    if (!_isPickingLocation) return;
    final lat = context.point.coordinates.lat.toDouble();
    final lng = context.point.coordinates.lng.toDouble();
    _handlePickedCoordinates(lat, lng);
  }

  Future<void> _confirmPickedLocation() async {
    if (_mapboxMap == null) return;
    try {
      final cameraState = await _mapboxMap!.getCameraState();
      final lat = cameraState.center.coordinates.lat.toDouble();
      final lng = cameraState.center.coordinates.lng.toDouble();
      _handlePickedCoordinates(lat, lng);
    } catch (_) {}
  }

  Future<void> _handlePickedCoordinates(double lat, double lng) async {
    if (_isReverseGeocoding) return;
    setState(() => _isReverseGeocoding = true);
    try {
      final name = await ApiService.instance.reverseGeocode(lat, lng);
      final label =
          name ?? '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
      if (!mounted) return;
      setState(() {
        _isPickingLocation = false;
        _isReverseGeocoding = false;
      });
      if (_pickingForOrigin) {
        _appProvider?.setManualLocation(lat, lng, label);
      } else {
        _showRouteOptionsSheet(label, lat, lng);
      }
    } catch (_) {
      if (mounted) setState(() => _isReverseGeocoding = false);
    }
  }

  // ── Sheets ────────────────────────────────────────────────────────────────

  void _openDestinationSearch() {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PlaceSearchSheet(
        title: 'Where to?',
        hint: 'Search for a destination…',
        nearLat: _currentPosition?.latitude,
        nearLng: _currentPosition?.longitude,
        onPickOnMap: () {
          Navigator.pop(context);
          _enterPickMode(isOrigin: false);
        },
        onSelected: (name, lat, lng) {
          Navigator.pop(context);
          _showRouteOptionsSheet(name, lat, lng);
        },
      ),
    );
  }

  void _showRouteOptionsSheet(
      String destination, double destLat, double destLng) {
    if (!mounted) return;
    // Cache coords so _showTripMarkers can use them when navigation starts
    _originLat = _currentLat;
    _originLng = _currentLng;
    _destLat = destLat;
    _destLng = destLng;
    _activeDestinationName = destination;
    setState(() {
      _lastDrawnRouteCount = 0;
      _lastDrawnSelectedIndex = -1;
      _lastDrawnGeoCount = -1;
    });
    EnhancedRouteOptionsSheet.show(
      context,
      _currentLat ?? 6.7133,
      _currentLng ?? 79.9063,
      destLat,
      destLng,
      destinationName: destination,
    ).then((picked) async {
      if (!mounted) return;
      // Cache service refs before any await
      final sensorSvc = context.read<SensorService>();
      final alertSvc = context.read<AlertService>();
      final riskSvc = context.read<RealtimeRiskService>();
      final pipelineSvc = context.read<RealtimePipelineService>();
      final enhSvc = context.read<EnhancedRouteService>();
      if (picked == null) {
        // User dismissed without navigating — clear any live preview
        await _clearEnhancedRoute();
        enhSvc.clearRoutes();
        return;
      }
      sensorSvc.startTrip(destination);
      alertSvc.startAlertMonitoring();
      await _pointAnnotationManager?.deleteAll();
      await _showTripMarkers();
      if (mounted) riskSvc.startMonitoring();
      if (mounted) {
        pipelineSvc.connect(
          sensorSvc.currentTrip!.tripId,
          vehicleType: context.read<VehiclePreferenceService>().currentVehicle,
        );
      }
      if (mounted) {
        context.read<ObstacleScanService>().scanRoute(
          picked.geometry.map((p) => [p[0], p[1]]).toList(),
          context.read<ObstaclePreferenceService>(),
        );
        context.read<ObstacleAlertOrchestrator>().startMonitoring();
      }
      if (mounted) await _startDrowsinessIfEnabled();
      // Route already drawn via onRouteChanged; redraw cleanly after trip starts
      await _drawAllEnhancedRoutes();
    });
  }

  Future<void> _drawAllEnhancedRoutes() async {
    if (!mounted) return;
    final map = _mapboxMap;
    final svc = _enhancedRouteSvcRef;
    if (map == null || svc == null || svc.routes.isEmpty) return;

    _enhancedRouteManager ??=
        await map.annotations.createPolylineAnnotationManager();
    await _enhancedRouteManager!.deleteAll();

    final selected = svc.selectedRoute;

    // Pass 1 — draw unselected routes dimmed
    for (final route in svc.routes) {
      if (selected != null && route.routeType == selected.routeType) continue;

      final allCoords = route.geometry
          .map((p) => Position(p[0], p[1]))
          .toList();
      if (allCoords.length < 2) continue;

      int dimColor = 0xFFB5BFCC;
      if (route.routeType == 'safest') dimColor = 0xFF8FCBB1;
      if (route.routeType == 'balanced') dimColor = 0xFF9FB8E8;
      if (route.routeType == 'fastest') dimColor = 0xFFE8B89A;

      await _enhancedRouteManager!.create(
        PolylineAnnotationOptions(
          geometry: LineString(coordinates: allCoords),
          lineColor: dimColor,
          lineWidth: 4.0,
          lineOpacity: 0.65,
        ),
      );
    }

    // Pass 2 — draw selected route with full congestion-colored segments on top
    if (selected != null) {
      for (final seg in selected.segments) {
        final coords = seg.geometry
            .where((p) => p.length >= 2)
            .map((p) => Position(p[0], p[1]))
            .toList();
        if (coords.length < 2) continue;

        final colorInt = int.parse(seg.colorHex.replaceAll('#', '0xFF'));
        await _enhancedRouteManager!.create(
          PolylineAnnotationOptions(
            geometry: LineString(coordinates: coords),
            lineColor: colorInt,
            lineWidth: 8.0,
            lineOpacity: 0.95,
          ),
        );
      }
      await _fitCameraToEnhancedRoute(selected);
    }

  }

  Future<void> _fitCameraToEnhancedRoute(EnhancedRouteModel route) async {
    final map = _mapboxMap;
    if (map == null || route.geometry.isEmpty) return;

    double minLng = route.geometry.first[0], maxLng = route.geometry.first[0];
    double minLat = route.geometry.first[1], maxLat = route.geometry.first[1];

    for (final p in route.geometry) {
      if (p[0] < minLng) minLng = p[0];
      if (p[0] > maxLng) maxLng = p[0];
      if (p[1] < minLat) minLat = p[1];
      if (p[1] > maxLat) maxLat = p[1];
    }

    const pad = 0.005;
    try {
      final camera = await map.cameraForCoordinateBounds(
        CoordinateBounds(
          southwest: Point(coordinates: Position(minLng - pad, minLat - pad)),
          northeast: Point(coordinates: Position(maxLng + pad, maxLat + pad)),
          infiniteBounds: false,
        ),
        MbxEdgeInsets(top: 100, left: 50, bottom: 250, right: 50),
        null, null, null, null,
      );
      await map.flyTo(camera, MapAnimationOptions(duration: 1000));
    } catch (_) {}
  }

  Future<void> _clearEnhancedRoute() async {
    await _enhancedRouteManager?.deleteAll();
    _enhancedRouteManager = null;
  }

  // ── Map ───────────────────────────────────────────────────────────────────

  Future<void> _flyToLocation(double lng, double lat) async {
    await _mapboxMap?.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(lng, lat)),
        zoom: AppConstants.defaultZoom,
      ),
      MapAnimationOptions(duration: 1500),
    );
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    _mapboxMap = map;
    await map.location.updateSettings(
      LocationComponentSettings(
        enabled: true,
        pulsingEnabled: true,
        pulsingColor: AppColors.primary.toARGB32(),
        pulsingMaxRadius: 50.0,
      ),
    );
    _pointAnnotationManager =
        await map.annotations.createPointAnnotationManager();
    _destinationPointAnnotationManager =
        await map.annotations.createPointAnnotationManager();
    if (!mounted) return;
    final hotspots = _appProvider?.hotspots ?? [];
    if (hotspots.isNotEmpty) await _buildAnnotations(hotspots);
    if (_currentPosition != null) {
      await _flyToLocation(
          _currentPosition!.longitude, _currentPosition!.latitude);
    }
  }

  Future<void> _showTripMarkers() async {
    final map = _mapboxMap;
    if (map == null ||
        _originLat == null ||
        _originLng == null ||
        _destLat == null ||
        _destLng == null) return;

    if (_tripAnnotationManager != null) {
      await _tripAnnotationManager!.deleteAll();
    }
    _tripAnnotationManager =
        await map.annotations.createPointAnnotationManager();

    // Start marker at origin
    final startImg = await HotspotMarkerPainter.createStartMarker();
    await _tripAnnotationManager!.create(PointAnnotationOptions(
      geometry: Point(coordinates: Position(_originLng!, _originLat!)),
      image: startImg,
      iconSize: 1.0,
      iconAnchor: IconAnchor.CENTER,
    ));

    // End marker at destination
    final endImg = await HotspotMarkerPainter.createEndMarker(
        _activeDestinationName ?? 'Destination');
    await _tripAnnotationManager!.create(PointAnnotationOptions(
      geometry: Point(coordinates: Position(_destLng!, _destLat!)),
      image: endImg,
      iconSize: 1.0,
      iconAnchor: IconAnchor.BOTTOM,
    ));

    // Fly camera to show both points
    await map.flyTo(
      CameraOptions(
        center: Point(
            coordinates: Position(
          (_originLng! + _destLng!) / 2,
          (_originLat! + _destLat!) / 2,
        )),
        zoom: 13.5,
        bearing: 0,
        pitch: 0,
      ),
      MapAnimationOptions(duration: 1200),
    );
  }

  Future<void> _clearTripMarkers() async {
    if (_tripAnnotationManager != null) {
      await _tripAnnotationManager!.deleteAll();
      _tripAnnotationManager = null;
    }
  }

  Future<void> _refreshHotspotAnnotations() async {
    final manager = _pointAnnotationManager;
    if (manager == null) return;
    // Hide hotspot dots during active navigation to keep map clean
    if (context.read<SensorService>().isTracking) {
      await manager.deleteAll();
      return;
    }
    final hotspots = _appProvider?.hotspots ?? [];
    await manager.deleteAll();
    await _buildAnnotations(hotspots);
  }

  Future<void> _buildAnnotations(List<HotspotModel> hotspots) async {
    final manager = _pointAnnotationManager;
    if (manager == null || hotspots.isEmpty) return;

    final filtered = hotspots.where((h) {
      final level = h.riskLevel.toUpperCase();
      if (level == 'HIGH' && !_showHighRisk) return false;
      if (level == 'MEDIUM' && !_showMediumRisk) return false;
      if (level == 'LOW' && !_showLowRisk) return false;
      return true;
    }).toList();

    if (filtered.isEmpty) return;

    final highImg = await HotspotMarkerPainter.createHotspotMarker('HIGH');
    final medImg = await HotspotMarkerPainter.createHotspotMarker('MEDIUM');
    final lowImg = await HotspotMarkerPainter.createHotspotMarker('LOW');

    final annotations = filtered.map((h) {
      final img = switch (h.riskLevel.toUpperCase()) {
        'HIGH' => highImg,
        'MEDIUM' => medImg,
        _ => lowImg,
      };
      return PointAnnotationOptions(
        geometry: Point(coordinates: Position(h.longitude, h.latitude)),
        image: img,
        iconSize: 1.0,
        iconAnchor: IconAnchor.CENTER,
      );
    }).toList();

    await manager.createMulti(annotations);
  }

  Future<void> _drawObstacleMarkers(List<ObstacleModel> obstacles) async {
    final map = _mapboxMap;
    if (map == null) return;
    _obstacleAnnotationManager ??=
        await map.annotations.createPointAnnotationManager();
    await _obstacleAnnotationManager!.deleteAll();
    if (obstacles.isEmpty) return;

    // Pre-render one image per unique color to avoid N async calls
    final colorCache = <String, Uint8List>{};
    for (final o in obstacles) {
      if (!colorCache.containsKey(o.colorHex)) {
        colorCache[o.colorHex] =
            await ObstacleMarkerPainter.createMarker(o.severityColor);
      }
    }

    final annotations = obstacles.map((o) {
      return PointAnnotationOptions(
        geometry: Point(coordinates: Position(o.longitude, o.latitude)),
        image: colorCache[o.colorHex]!,
        iconSize: 0.9,
        iconAnchor: IconAnchor.CENTER,
      );
    }).toList();

    await _obstacleAnnotationManager!.createMulti(annotations);
  }

  Future<void> _clearObstacleMarkers() async {
    await _obstacleAnnotationManager?.deleteAll();
  }

  // ── Behavior alert data ───────────────────────────────────────────────────

  List<({Color color, IconData icon, String message, String badge,
      String description, String tip})>
      _buildBehaviorAlerts(TripSession trip) {
    final list = <({
      Color color,
      IconData icon,
      String message,
      String badge,
      String description,
      String tip,
    })>[];

    if (trip.overSpeedingCount >= 1) {
      list.add((
        color: const Color(0xFFFF3B5C),
        icon: Icons.speed,
        message: 'Overspeeding — reduce speed immediately',
        badge: 'CRITICAL',
        description:
            'You exceeded safe speed limits ${trip.overSpeedingCount} time${trip.overSpeedingCount > 1 ? "s" : ""} this trip.',
        tip: 'Maintain a steady speed and follow posted speed signs.',
      ));
    }

    if (trip.harshBrakingCount >= 3) {
      list.add((
        color: const Color(0xFFFF3B5C),
        icon: Icons.warning_amber_rounded,
        message:
            'Harsh braking ${trip.harshBrakingCount}× — increase following distance',
        badge: 'WARNING',
        description:
            '${trip.harshBrakingCount} sudden stops detected this trip.',
        tip: 'Keep at least a 3-second gap from the vehicle ahead.',
      ));
    } else if (trip.harshBrakingCount > 0)
      list.add((
        color: const Color(0xFFFFB300),
        icon: Icons.warning_amber_rounded,
        message: 'Harsh braking detected — brake more gradually',
        badge: 'CAUTION',
        description: 'A sudden brake was detected.',
        tip: 'Anticipate stops early and brake smoothly.',
      ));

    if (trip.sharpTurnCount >= 2) {
      list.add((
        color: const Color(0xFFFFB300),
        icon: Icons.turn_right,
        message: 'Sharp turns ${trip.sharpTurnCount}× — slow before corners',
        badge: 'CAUTION',
        description: '${trip.sharpTurnCount} sharp turns recorded.',
        tip: 'Reduce speed before entering a corner.',
      ));
    }

    if (trip.safetyScore < 50) {
      list.add((
        color: const Color(0xFFFF3B5C),
        icon: Icons.shield_outlined,
        message: 'Score critical: ${trip.safetyScore}/100 — drive carefully',
        badge: 'CRITICAL',
        description:
            'Your safety score has dropped to ${trip.safetyScore}/100.',
        tip: 'Slow down and avoid sudden maneuvers.',
      ));
    }

    return list;
  }

  void _showBehaviorAlertDetail(
    BuildContext context, {
    required Color color,
    required IconData icon,
    required String badge,
    required String message,
    required String description,
    required String tip,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _BehaviorAlertSheet(
        color: color,
        icon: icon,
        badge: badge,
        message: message,
        description: description,
        tip: tip,
      ),
    );
  }

  void _showProximityAlertDetail(
      BuildContext context, Map<String, dynamic> alert) {
    final hex = (alert['alert_color'] as String? ?? '#2979FF')
        .replaceAll('#', '0xFF');
    final color = Color(int.parse(hex));
    final severity = alert['severity'] as String? ?? 'CAUTION';
    final icon = switch (severity) {
      'CRITICAL' => Icons.warning_rounded,
      'WARNING' => Icons.warning_amber_rounded,
      _ => Icons.info_outline,
    };
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _ProximityAlertSheet(
        alert: alert,
        color: color,
        icon: icon,
      ),
    );
  }

  // ── End trip ──────────────────────────────────────────────────────────────

  // ── Member 4 Part 2 — start drowsiness detection with calibration ────────
  Future<void> _startDrowsinessIfEnabled() async {
    final prefs = context.read<DrowsinessPreferenceService>();
    if (!prefs.detectionEnabled) return;

    final detection = context.read<DrowsinessDetectionService>();
    final calibSvc = context.read<DrowsinessCalibrationService>();

    // Start camera + metrics timer
    await detection.startDetection();
    if (!mounted) return;

    final baseline = prefs.baseline;
    final needsCalibration = baseline == null || baseline.isStale;

    if (needsCalibration) {
      setState(() {
        _showCalibrationOverlay = true;
        _calibrationSecondsLeft = 15;
      });

      final result = await calibSvc.start(
        onTick: (s) {
          if (mounted) setState(() => _calibrationSecondsLeft = s);
        },
      );

      if (!mounted) return;
      setState(() => _showCalibrationOverlay = false);

      if (result != null) await prefs.saveBaseline(result);
      // Detection is already running — no need to restart
    }
  }

  Future<void> _endTrip(BuildContext context) async {
    context.read<RealtimeRiskService>().stopMonitoring();
    context.read<RealtimePipelineService>().disconnect();
    setState(() => _showStreamDebugPanel = false);
    context.read<ObstacleAlertOrchestrator>().stopMonitoring();
    context.read<DrowsinessDetectionService>().stopDetection();
    context.read<ObstacleScanService>().clear();
    final sensorService = context.read<SensorService>();
    final alertService = context.read<AlertService>();
    final nav = Navigator.of(context, rootNavigator: true);
    alertService.clearAlertsForNewTrip();
    final trip = await sensorService.endTrip();
    if (!mounted || trip == null) return;

    await nav.push(MaterialPageRoute<void>(
      builder: (_) => TripSummaryScreen(trip: trip),
    ));

    if (!mounted) return;
    _resetMapAfterTrip();
  }

  void _resetMapAfterTrip() {
    if (_mapboxMap != null) clearRoutesOnMap(_mapboxMap!);
    _destinationPointAnnotationManager?.deleteAll();
    _clearTripMarkers(); // async fire-and-forget
    _clearObstacleMarkers(); // async fire-and-forget
    _clearEnhancedRoute(); // async fire-and-forget

    _appProvider?.clearRoutes();
    _enhancedRouteSvcRef?.clearRoutes();

    // Restore hotspot markers now that tracking is done
    final hotspots = _appProvider?.hotspots ?? [];
    if (_pointAnnotationManager != null && hotspots.isNotEmpty) {
      _buildAnnotations(hotspots); // async fire-and-forget
    }

    setState(() {
      _activeDestinationName = null;
      _destLat = null;
      _destLng = null;
      _originLat = null;
      _originLng = null;
      _lastDrawnRouteCount = 0;
      _lastDrawnSelectedIndex = -1;
      _lastDrawnGeoCount = -1;
    });

    if (_currentPosition != null) {
      _flyToLocation(_currentPosition!.longitude, _currentPosition!.latitude);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final sensorService = context.watch<SensorService>();
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            // ── 1. Full-screen map ───────────────────────────────────────
            MapWidget(
              key: const ValueKey('mapScreen'),
              styleUri: AppConstants.mapboxStyle,
              onMapCreated: _onMapCreated,
              onTapListener: _onMapTap,
              cameraOptions: CameraOptions(
                center: Point(
                  coordinates: Position(
                      AppConstants.defaultLng, AppConstants.defaultLat),
                ),
                zoom: AppConstants.defaultZoom,
              ),
            ),

            // ── 2. Server-offline banner ─────────────────────────────────
            if (!appProvider.isServerConnected &&
                !_isPickingLocation &&
                !sensorService.isTracking)
              Positioned(
                top: MediaQuery.of(context).padding.top + 4,
                left: 16,
                right: 16,
                child: const _ServerBanner(),
              ),

            // ── 3. Unified search bar (no active trip) ───────────────────
            if (!_isPickingLocation && !sensorService.isTracking)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: UnifiedSearchBar(
                  onTap: _openDestinationSearch,
                  vehiclePill: const VehiclePickerButton(),
                ),
              ),

            // ── 4. Right action stack (no active trip) ───────────────────
            if (!_isPickingLocation && !sensorService.isTracking)
              Positioned(
                top: MediaQuery.of(context).padding.top + 100,
                right: 16,
                child: MapActionStack(
                  layersBadgeCount: _activeFilters,
                  onLayers: () => LayersPopup.show(
                    context,
                    showHighRisk: _showHighRisk,
                    showMediumRisk: _showMediumRisk,
                    showLowRisk: _showLowRisk,
                    totalHotspots: appProvider.hotspots.length,
                    onHighToggle: () {
                      setState(() => _showHighRisk = !_showHighRisk);
                      _refreshHotspotAnnotations();
                    },
                    onMediumToggle: () {
                      setState(() => _showMediumRisk = !_showMediumRisk);
                      _refreshHotspotAnnotations();
                    },
                    onLowToggle: () {
                      setState(() => _showLowRisk = !_showLowRisk);
                      _refreshHotspotAnnotations();
                    },
                  ),
                  onLegend: () => LegendPopup.show(context),
                  onRecenter: () {
                    if (_currentPosition != null) {
                      _flyToLocation(
                        _currentPosition!.longitude,
                        _currentPosition!.latitude,
                      );
                    }
                  },
                ),
              ),

            // ── 5. Real-time risk HUD (member1_part2) ────────────────────
            if (!_isPickingLocation && !sensorService.isTracking)
              Positioned(
                top: MediaQuery.of(context).padding.top + 92,
                left: 0,
                right: 0,
                child: const RealtimeRiskHUD(),
              ),

            // ── 6. Blue navigation sheet (active trip) ───────────────────
            if (!_isPickingLocation && sensorService.isTracking)
              Positioned.fill(
                child: _DarkNavSheet(
                  destinationName: _activeDestinationName,
                  onEndTrip: () => _endTrip(context),
                ),
              ),

            // ── 7. Navigation active banner ──────────────────────────────
            if (!_isPickingLocation && sensorService.isTracking)
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: const _NavActiveBanner(),
                ),
              ),

            // ── 8. Obstacle alert card ──────────────────────────────────
            if (!_isPickingLocation && sensorService.isTracking)
              Positioned(
                top: MediaQuery.of(context).padding.top + 72,
                left: 0,
                right: 0,
                child: const ObstacleAlertCard(),
              ),

            // ── 8b. Obstacle scan loading card ──────────────────────────
            if (!_isPickingLocation && sensorService.isTracking)
              Consumer<ObstacleScanService>(
                builder: (ctx, scanSvc, _) {
                  if (!scanSvc.isLoading) return const SizedBox.shrink();
                  return Positioned(
                    top: MediaQuery.of(ctx).padding.top + 72,
                    left: 0,
                    right: 0,
                    child: const _ObstacleScanLoadingCard(),
                  );
                },
              ),

            // ── 8c. Live stream indicator (member1b, active trip) ────────
            if (!_isPickingLocation && sensorService.isTracking)
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 16,
                child: LiveStreamIndicator(
                  onLongPress: () => setState(
                      () => _showStreamDebugPanel = !_showStreamDebugPanel),
                ),
              ),

            // ── 8d. Stream debug panel (member1b, toggled via long-press) ─
            if (!_isPickingLocation &&
                sensorService.isTracking &&
                _showStreamDebugPanel)
              Positioned(
                top: MediaQuery.of(context).padding.top + 44,
                right: 0,
                child: const StreamDebugPanel(),
              ),

            // ── 9a. Drowsiness monitoring chip (active trip) ─────────────
            Consumer<DrowsinessPreferenceService>(
              builder: (ctx, drowsyPrefs, _) {
                if (!drowsyPrefs.detectionEnabled ||
                    !sensorService.isTracking) {
                  return const SizedBox.shrink();
                }
                return Positioned(
                  top: MediaQuery.of(context).padding.top + 90,
                  left: 16,
                  child: drowsyPrefs.showCameraPreview
                      ? const DrowsinessCameraPreview()
                      : const DrowsinessStatusChip(),
                );
              },
            ),

            // ── 9b. Drowsiness alert overlay (active trip) ───────────────
            Consumer<DrowsinessAlertService>(
              builder: (ctx, alertSvc, _) {
                if (alertSvc.activeAlert == null) {
                  return const SizedBox.shrink();
                }
                return Positioned(
                  top: MediaQuery.of(context).padding.top + 60,
                  left: 0,
                  right: 0,
                  child: DrowsinessAlertOverlay(
                    metrics: alertSvc.activeAlert!,
                    onDismiss: alertSvc.clearAlert,
                  ),
                );
              },
            ),

            // ── 9c. Calibration overlay — full-screen, on top of all ─────
            if (_showCalibrationOverlay)
              DrowsinessCalibrationOverlay(
                secondsRemaining: _calibrationSecondsLeft,
                onCancel: () {
                  context.read<DrowsinessCalibrationService>().cancel();
                  context.read<DrowsinessDetectionService>().stopDetection();
                  setState(() => _showCalibrationOverlay = false);
                },
              ),

            // ── 10. Pick mode: floating pin ──────────────────────────────
            if (_isPickingLocation)
              IgnorePointer(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF2979FF), Color(0xFF1557D6)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x502979FF),
                                blurRadius: 14,
                                offset: Offset(0, 4)),
                          ],
                        ),
                        child: const Icon(Icons.my_location,
                            color: Colors.white, size: 24),
                      ),
                      Container(width: 2, height: 10, color: AppColors.primary),
                      Container(
                        width: 10,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── 11. Pick mode: instruction banner ────────────────────────
            if (_isPickingLocation)
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _cancelPickMode,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(
                                  color: AppColors.shadow,
                                  blurRadius: 8,
                                  offset: Offset(0, 2)),
                            ],
                          ),
                          child: const Icon(Icons.arrow_back,
                              size: 20, color: AppColors.textPrimary),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: const [
                              BoxShadow(
                                  color: AppColors.shadow,
                                  blurRadius: 8,
                                  offset: Offset(0, 2)),
                            ],
                          ),
                          child: Text(
                            _pickingForOrigin
                                ? 'Move map to set starting point'
                                : 'Move map to set destination',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── 12. Pick mode: confirm button ────────────────────────────
            if (_isPickingLocation)
              Positioned(
                bottom: 24 + bottomPadding,
                left: 24,
                right: 24,
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed:
                          _isReverseGeocoding ? null : _confirmPickedLocation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shadowColor: AppColors.primary.withValues(alpha: 0.4),
                        shape: const StadiumBorder(),
                      ),
                      child: _isReverseGeocoding
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                              ),
                            )
                          : Text(
                              _pickingForOrigin
                                  ? 'Confirm Starting Point'
                                  : 'Confirm Destination',
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),
                ),
              ),

            // ── 13. Bottom area: risk banner + quick destinations ─────────
            if (!_isPickingLocation && !sensorService.isTracking)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        HighRiskBanner(
                          highRiskCount: appProvider.hotspots
                              .where((h) =>
                                  h.riskLevel.toUpperCase() == 'HIGH')
                              .length,
                          onTap: _openDestinationSearch,
                        ),
                        const SizedBox(height: 4),
                        QuickDestinationsRow(
                            onTap: (_) => _openDestinationSearch()),
                      ],
                    ),
                  ),
                ),
              ),

            // ── 14. Alert cards ──────────────────────────────────────────
            if (!_isPickingLocation &&
                (_alertServiceRef?.isInAppAlertsEnabled == true))
              Positioned(
                bottom: 220 + bottomPadding,
                left: 12,
                right: 12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (sensorService.isTracking &&
                        sensorService.currentTrip != null)
                      ..._buildBehaviorAlerts(sensorService.currentTrip!)
                          .take(1)
                          .map((a) => _CompactAlertCard(
                                color: a.color,
                                icon: a.icon,
                                message: a.message,
                                badge: a.badge,
                                onTap: () => _showBehaviorAlertDetail(context,
                                    color: a.color,
                                    icon: a.icon,
                                    badge: a.badge,
                                    message: a.message,
                                    description: a.description,
                                    tip: a.tip),
                              )),
                    ..._activeAlerts.take(2).map((alert) {
                      final hex =
                          (alert['alert_color'] as String? ?? '#2979FF')
                              .replaceAll('#', '0xFF');
                      final color = Color(int.parse(hex));
                      final severity =
                          alert['severity'] as String? ?? 'CAUTION';
                      final icon = switch (severity) {
                        'CRITICAL' => Icons.warning_rounded,
                        'WARNING' => Icons.warning_amber_rounded,
                        _ => Icons.info_outline,
                      };
                      return _CompactAlertCard(
                        color: color,
                        icon: icon,
                        message: alert['message_en'] as String? ?? '',
                        badge: severity,
                        onTap: () =>
                            _showProximityAlertDetail(context, alert),
                        onDismiss: () => _alertServiceRef?.dismissAlert(
                            alert['hotspot_id'] as int),
                      );
                    }),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Compact alert card ────────────────────────────────────────────────────────

class _CompactAlertCard extends StatefulWidget {
  final Color color;
  final IconData icon;
  final String message;
  final String badge;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;
  final int autoDismissSeconds;

  const _CompactAlertCard({
    required this.color,
    required this.icon,
    required this.message,
    required this.badge,
    this.onTap,
    this.onDismiss,
    this.autoDismissSeconds = 8,
  });

  @override
  State<_CompactAlertCard> createState() => _CompactAlertCardState();
}

class _CompactAlertCardState extends State<_CompactAlertCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressCtrl;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _progressCtrl = AnimationController(
      vsync: this,
      duration: Duration(seconds: widget.autoDismissSeconds),
    )..forward();

    if (widget.onDismiss != null) {
      _dismissTimer = Timer(
        Duration(seconds: widget.autoDismissSeconds),
        widget.onDismiss!,
      );
    }
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: widget.color, width: 4)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 12,
                offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                        color: widget.color.withValues(alpha: 0.12),
                        shape: BoxShape.circle),
                    child: Icon(widget.icon, color: widget.color, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: widget.color.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(4)),
                          child: Text(widget.badge,
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  color: widget.color,
                                  letterSpacing: 0.6)),
                        ),
                        const SizedBox(height: 3),
                        Text(widget.message,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A2332)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  if (widget.onDismiss != null) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: widget.onDismiss,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                            color: Colors.grey.shade100, shape: BoxShape.circle),
                        child: Icon(Icons.close_rounded,
                            size: 14, color: Colors.grey.shade500),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Auto-dismiss progress bar
            if (widget.onDismiss != null)
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(14),
                ),
                child: AnimatedBuilder(
                  animation: _progressCtrl,
                  builder: (_, __) => LinearProgressIndicator(
                    value: 1.0 - _progressCtrl.value,
                    minHeight: 3,
                    backgroundColor: Colors.grey.shade100,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(widget.color.withValues(alpha: 0.5)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Alert detail sheets ───────────────────────────────────────────────────────

class _BehaviorAlertSheet extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String badge;
  final String message;
  final String description;
  final String tip;

  const _BehaviorAlertSheet({
    required this.color,
    required this.icon,
    required this.badge,
    required this.message,
    required this.description,
    required this.tip,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(badge,
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: color,
                              letterSpacing: 0.8)),
                    ),
                    const SizedBox(height: 4),
                    const Text('Driving Behaviour Alert',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A2332))),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            Divider(color: Colors.grey.shade100, height: 1),
            const SizedBox(height: 16),
            _SheetSection(
              icon: Icons.info_outline_rounded,
              label: 'What happened',
              color: color,
              child: Text(description,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF4A5568), height: 1.5)),
            ),
            const SizedBox(height: 16),
            _SheetSection(
              icon: Icons.lightbulb_outline_rounded,
              label: 'How to improve',
              color: const Color(0xFF00C06A),
              child: Text(tip,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF4A5568), height: 1.5)),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Got it',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProximityAlertSheet extends StatelessWidget {
  final Map<String, dynamic> alert;
  final Color color;
  final IconData icon;

  const _ProximityAlertSheet({
    required this.alert,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final severity = alert['severity'] as String? ?? 'CAUTION';
    final message = alert['message_en'] as String? ?? '';
    final explanation = alert['explanation_en'] as String? ?? '';
    final roadName = alert['road_name'] as String? ?? '';
    final distanceM = (alert['distance_m'] as num?)?.toInt() ?? 0;
    final riskScore = (alert['risk_score'] as num?)?.toDouble() ?? 0.0;
    final accidentCount = alert['accident_count'] as int? ?? 0;
    final topCause = alert['top_cause'] as String? ?? '';
    final timePeriod = alert['time_period'] as String? ?? '';

    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(severity,
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: color,
                                letterSpacing: 0.8)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        roadName.isNotEmpty ? roadName : 'Accident Hotspot',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A2332)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text('${distanceM}m ahead',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF8A9BB0))),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border(left: BorderSide(color: color, width: 3)),
              ),
              child: Text(message,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: color.withValues(alpha: 0.9),
                      height: 1.4)),
            ),
            if (explanation.isNotEmpty) ...[
              const SizedBox(height: 14),
              _SheetSection(
                icon: Icons.analytics_outlined,
                label: 'Why this spot is dangerous',
                color: color,
                child: Text(explanation,
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF4A5568), height: 1.5)),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                if (riskScore > 0)
                  Expanded(
                      child: _StatChip(
                          icon: Icons.bar_chart_rounded,
                          label: 'Risk',
                          value: '${riskScore.toInt()}/100',
                          color: color)),
                if (accidentCount > 0) ...[
                  const SizedBox(width: 8),
                  Expanded(
                      child: _StatChip(
                          icon: Icons.history_rounded,
                          label: 'Accidents',
                          value: '$accidentCount',
                          color: color)),
                ],
                if (topCause.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Expanded(
                      child: _StatChip(
                          icon: Icons.gpp_maybe_outlined,
                          label: 'Top cause',
                          value: topCause,
                          color: color)),
                ],
              ],
            ),
            if (timePeriod.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.access_time_rounded,
                      size: 13, color: Color(0xFF8A9BB0)),
                  const SizedBox(width: 5),
                  Text('Peak risk: $timePeriod',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF8A9BB0))),
                ],
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Stay Alert',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetSection extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Widget child;

  const _SheetSection(
      {required this.icon,
      required this.label,
      required this.color,
      required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 0.4)),
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatChip(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
          color: const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(label,
                  style: const TextStyle(
                      fontSize: 10, color: Color(0xFF8A9BB0))),
            ],
          ),
          const SizedBox(height: 3),
          Text(value,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A2332)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ── Navigation active banner ──────────────────────────────────────────────────

class _NavActiveBanner extends StatefulWidget {
  const _NavActiveBanner();

  @override
  State<_NavActiveBanner> createState() => _NavActiveBannerState();
}

class _NavActiveBannerState extends State<_NavActiveBanner> {
  Timer? _timer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    final start = context.read<SensorService>().currentTrip?.startTime;
    if (start != null) {
      _elapsedSeconds = DateTime.now().difference(start).inSeconds;
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmt(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final speed = context.watch<SensorService>().currentSpeedKmh;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0D1117).withValues(alpha: 0.95),
            const Color(0xFF1A2234).withValues(alpha: 0.90),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          // Green pulsing dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: const Color(0xFF00C06A),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00C06A).withValues(alpha: 0.5),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            'LIVE',
            style: TextStyle(
              color: Color(0xFF00C06A),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Trip in Progress',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            _fmt(_elapsedSeconds),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${speed.toStringAsFixed(0)} km/h',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared small widgets ──────────────────────────────────────────────────────

class _ServerBanner extends StatelessWidget {
  const _ServerBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.danger,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.wifi_off, color: Colors.white, size: 14),
          SizedBox(width: 8),
          Text('No server connection',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ── Blue navigation sheet (active trip) ──────────────────────────────────────

class _DarkNavSheet extends StatefulWidget {
  final String? destinationName;
  final VoidCallback onEndTrip;

  const _DarkNavSheet({
    required this.destinationName,
    required this.onEndTrip,
  });

  @override
  State<_DarkNavSheet> createState() => _DarkNavSheetState();
}

class _DarkNavSheetState extends State<_DarkNavSheet> {
  int _activeTab = 0;

  String _formatTime(DateTime? time) {
    if (time == null) return '--';
    final h = time.hour;
    final m = time.minute;
    final suffix = h >= 12 ? 'PM' : 'AM';
    final hour = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    return '$hour:${m.toString().padLeft(2, '0')} $suffix';
  }

  double _getTripProgress(SensorService sensor) {
    final trip = sensor.currentTrip;
    if (trip == null) return 0.0;
    final elapsed = DateTime.now().difference(trip.startTime).inSeconds;
    return (elapsed / 1800.0).clamp(0.0, 0.85);
  }

  Widget _miniStat(
      IconData icon, String value, String unit, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 16, color: const Color(0xFF2979FF)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(value,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0D1B2A))),
              Text(unit,
                  style: const TextStyle(
                      fontSize: 10, color: Color(0xFF5C6B7A))),
            ],
          ),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: Color(0xFFADB8C3))),
        ],
      ),
    );
  }

  Widget _vertDivider() => Container(
        width: 1,
        height: 36,
        color: const Color(0xFFEEF1F5),
        margin: const EdgeInsets.symmetric(horizontal: 8),
      );

  Widget _timelineRow({
    required Color dotColor,
    required bool dotFilled,
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    required bool isFirst,
    required bool isLast,
  }) {
    return SizedBox(
      height: isLast ? 44 : 56,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotFilled ? dotColor : Colors.white,
                    border: Border.all(
                      color: dotColor,
                      width: dotFilled ? 0 : 2,
                    ),
                    boxShadow: dotFilled
                        ? [
                            BoxShadow(
                                color: dotColor.withOpacity(0.25),
                                blurRadius: 6)
                          ]
                        : [],
                  ),
                  child: Icon(icon,
                      size: 12,
                      color: dotFilled ? Colors.white : dotColor),
                ),
                if (!isLast)
                  Expanded(
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: 3),
                      child: LayoutBuilder(
                        builder: (_, c) => Column(
                          children: List.generate(
                            (c.maxHeight / 6).floor(),
                            (_) => Container(
                              width: 2,
                              height: 3,
                              margin:
                                  const EdgeInsets.only(bottom: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDDE3EA),
                                borderRadius:
                                    BorderRadius.circular(1),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0D1B2A))),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF5C6B7A))),
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _wxChip(IconData? icon, String text) {
    return Column(
      children: [
        if (icon != null)
          Icon(icon, size: 16, color: const Color(0xFF2979FF)),
        const SizedBox(height: 4),
        Text(text,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Color(0xFF0D1B2A)),
            textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildTripDetailsContent(SensorService sensor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _timelineRow(
          dotColor: const Color(0xFF2979FF),
          dotFilled: true,
          icon: Icons.circle,
          title: 'My Location',
          subtitle:
              'Started ${_formatTime(sensor.currentTrip?.startTime)}',
          isFirst: true,
          isLast: false,
        ),
        _timelineRow(
          dotColor: const Color(0xFF00C06A),
          dotFilled: true,
          icon: Icons.navigation_rounded,
          title: 'Trip in progress...',
          subtitle:
              '${sensor.currentTrip?.totalDistanceKm.toStringAsFixed(1) ?? "0.0"} km traveled',
          trailing: Text(
            '${sensor.currentTrip?.duration ?? 0} min',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0D1B2A)),
          ),
          isFirst: false,
          isLast: false,
        ),
        _timelineRow(
          dotColor: const Color(0xFF0D1B2A),
          dotFilled: false,
          icon: Icons.location_on_rounded,
          title: widget.destinationName ?? 'Destination',
          subtitle: 'Estimated arrival',
          isFirst: false,
          isLast: true,
        ),
        const SizedBox(height: 18),
        Container(height: 0.5, color: const Color(0xFFEEF1F5)),
        const SizedBox(height: 16),
        Row(
          children: [
            _miniStat(
              Icons.timer_outlined,
              '${sensor.currentTrip?.duration ?? 0}',
              'min',
              'Duration',
            ),
            _vertDivider(),
            _miniStat(
              Icons.straighten_rounded,
              sensor.currentTrip?.totalDistanceKm
                      .toStringAsFixed(1) ??
                  '0.0',
              'km',
              'Distance',
            ),
            _vertDivider(),
            _miniStat(
              Icons.speed_rounded,
              sensor.currentSpeedKmh.toStringAsFixed(0),
              'km/h',
              'Speed',
            ),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: widget.onEndTrip,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2979FF),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.stop_circle_outlined, size: 18),
                SizedBox(width: 8),
                Text('End Trip',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRiskInfoContent(RealtimeRiskModel? risk) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: const Color(0xFFF5F8FF),
              borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (risk?.riskColor ?? const Color(0xFFFFB300))
                      .withOpacity(0.12),
                  border: Border.all(
                      color:
                          risk?.riskColor ?? const Color(0xFFFFB300),
                      width: 2.5),
                ),
                child: Center(
                  child: Text(
                    risk?.riskScore.toStringAsFixed(0) ?? '--',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: risk?.riskColor ??
                            const Color(0xFFFFB300)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: risk?.riskColor ??
                              const Color(0xFFFFB300),
                          borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        risk?.riskLabel ?? 'N/A',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      risk?.recommendation ?? '...',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF0D1B2A),
                          height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text('Weather',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0D1B2A))),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: const Color(0xFFF5F8FF),
              borderRadius: BorderRadius.circular(12)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _wxChip(risk?.weather.icon,
                  risk?.weather.description ?? '--'),
              _wxChip(
                  Icons.thermostat_rounded,
                  '${risk?.weather.temperatureC.toStringAsFixed(0) ?? "--"}°C'),
              _wxChip(Icons.water_drop_outlined,
                  '${risk?.weather.humidityPct ?? "--"}%'),
              _wxChip(
                  Icons.air_rounded,
                  '${risk?.weather.windSpeedKmh.toStringAsFixed(0) ?? "--"} km/h'),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Text('Risk Factors',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0D1B2A))),
        const SizedBox(height: 8),
        if (risk != null)
          ...risk.contributingFactors.map((f) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xFFFAFBFF),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: const Color(0xFFEEF1F5))),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(f.name,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF0D1B2A))),
                        const Spacer(),
                        Text(f.value,
                            style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF5C6B7A))),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                              color: const Color(0xFF2979FF)
                                  .withOpacity(0.08),
                              borderRadius:
                                  BorderRadius.circular(4)),
                          child: Text(
                            '×${f.multiplier.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF2979FF)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: f.contributionPct / 100,
                        backgroundColor: const Color(0xFFEEF1F5),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(
                                Color(0xFF2979FF)),
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${f.contributionPct.toStringAsFixed(1)}%',
                        style: const TextStyle(
                            fontSize: 9,
                            color: Color(0xFF2979FF),
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              )),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: widget.onEndTrip,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2979FF),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.stop_circle_outlined, size: 18),
                SizedBox(width: 8),
                Text('End Trip',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final sensor = context.watch<SensorService>();
    final risk = context.watch<RealtimeRiskService>().currentRisk;

    return DraggableScrollableSheet(
      initialChildSize: 0.48,
      minChildSize: 0.30,
      maxChildSize: 0.78,
      snap: true,
      snapSizes: const [0.30, 0.48, 0.78],
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2979FF), Color(0xFF5C9AFF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2979FF).withOpacity(0.30),
              blurRadius: 24,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: ListView(
          controller: scrollController,
          padding: EdgeInsets.zero,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── Section A: Risk summary + progress bar ───────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Risk score circle
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.18),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.5),
                            width: 2.5,
                          ),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              Text(
                                risk?.riskScore
                                        .toStringAsFixed(0) ??
                                    '--',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1,
                                ),
                              ),
                              Text('risk',
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: Colors.white
                                        .withOpacity(0.6),
                                  )),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color:
                                    Colors.white.withOpacity(0.20),
                                borderRadius:
                                    BorderRadius.circular(8),
                              ),
                              child: Text(
                                risk?.riskLabel ?? 'ANALYZING',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              risk?.recommendation ??
                                  'Analyzing conditions...',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color:
                                    Colors.white.withOpacity(0.85),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (risk != null)
                        Column(
                          children: [
                            Icon(risk.weather.icon,
                                size: 18,
                                color:
                                    Colors.white.withOpacity(0.75)),
                            const SizedBox(height: 3),
                            Text(
                              '${risk.weather.temperatureC.toStringAsFixed(0)}°C',
                              style: TextStyle(
                                fontSize: 11,
                                color:
                                    Colors.white.withOpacity(0.75),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // Progress bar: From ────●──── To
                  SizedBox(
                    height: 50,
                    child: Column(
                      children: [
                        SizedBox(
                          height: 14,
                          child: LayoutBuilder(
                            builder: (ctx, constraints) {
                              final totalW =
                                  constraints.maxWidth;
                              final progress =
                                  _getTripProgress(sensor);
                              return Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned(
                                    top: 5,
                                    left: 6,
                                    right: 6,
                                    child: Container(
                                      height: 3,
                                      decoration: BoxDecoration(
                                        color: Colors.white
                                            .withOpacity(0.20),
                                        borderRadius:
                                            BorderRadius.circular(
                                                2),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 5,
                                    left: 6,
                                    child: Container(
                                      width: (totalW - 12) *
                                          progress,
                                      height: 3,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(
                                                2),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 0,
                                    top: 0,
                                    child: Container(
                                      width: 12,
                                      height: 12,
                                      decoration:
                                          const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: (totalW - 12) *
                                            progress -
                                        2,
                                    top: -2,
                                    child: Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white,
                                        border: Border.all(
                                          color: const Color(
                                              0xFF2979FF),
                                          width: 3,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.white
                                                .withOpacity(0.4),
                                            blurRadius: 6,
                                          )
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 0,
                                    top: 1,
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white
                                            .withOpacity(0.40),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text('From',
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.white
                                            .withOpacity(0.45),
                                        letterSpacing: 0.3)),
                                const Text('My Location',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                        fontWeight:
                                            FontWeight.w600)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.end,
                              children: [
                                Text('To',
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.white
                                            .withOpacity(0.45),
                                        letterSpacing: 0.3)),
                                Text(
                                  widget.destinationName ??
                                      'Destination',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white,
                                      fontWeight:
                                          FontWeight.w600),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Thin white divider
            Container(
              height: 0.5,
              margin: const EdgeInsets.symmetric(horizontal: 20),
              color: Colors.white.withOpacity(0.15),
            ),

            const SizedBox(height: 14),

            // ── Section B: Tab toggle ────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _activeTab = 0),
                        child: AnimatedContainer(
                          duration:
                              const Duration(milliseconds: 250),
                          height: 34,
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: _activeTab == 0
                                ? Colors.white
                                : Colors.transparent,
                            borderRadius:
                                BorderRadius.circular(9),
                            boxShadow: _activeTab == 0
                                ? [
                                    BoxShadow(
                                      color: Colors.black
                                          .withOpacity(0.08),
                                      blurRadius: 4,
                                      offset:
                                          const Offset(0, 2),
                                    )
                                  ]
                                : [],
                          ),
                          child: Center(
                            child: Text(
                              'Trip Details',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _activeTab == 0
                                    ? const Color(0xFF2979FF)
                                    : Colors.white
                                        .withOpacity(0.7),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _activeTab = 1),
                        child: AnimatedContainer(
                          duration:
                              const Duration(milliseconds: 250),
                          height: 34,
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: _activeTab == 1
                                ? Colors.white
                                : Colors.transparent,
                            borderRadius:
                                BorderRadius.circular(9),
                            boxShadow: _activeTab == 1
                                ? [
                                    BoxShadow(
                                      color: Colors.black
                                          .withOpacity(0.08),
                                      blurRadius: 4,
                                      offset:
                                          const Offset(0, 2),
                                    )
                                  ]
                                : [],
                          ),
                          child: Center(
                            child: Text(
                              'Risk Info',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _activeTab == 1
                                    ? const Color(0xFF2979FF)
                                    : Colors.white
                                        .withOpacity(0.7),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Section C: Tab content (white card inside blue sheet) ─
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: _activeTab == 0
                  ? _buildTripDetailsContent(sensor)
                  : _buildRiskInfoContent(risk),
            ),

            // Bottom spacing for floating nav bar
            const SizedBox(height: 110),
          ],
        ),
      ),
    );
  }
}

// ── Obstacle scan loading card ────────────────────────────────────────────────

class _ObstacleScanLoadingCard extends StatefulWidget {
  const _ObstacleScanLoadingCard();

  @override
  State<_ObstacleScanLoadingCard> createState() =>
      _ObstacleScanLoadingCardState();
}

class _ObstacleScanLoadingCardState extends State<_ObstacleScanLoadingCard>
    with TickerProviderStateMixin {
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  static const _blue = Color(0xFF2979FF);

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..forward();
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnim,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: const Border(left: BorderSide(color: _blue, width: 3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  // Pulsing radar icon
                  AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (_, child) => Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _blue.withValues(alpha: 0.10 + 0.10 * _pulseAnim.value),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _blue.withValues(alpha: 0.18 * _pulseAnim.value),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: child,
                    ),
                    child: const Icon(Icons.radar_rounded, size: 20, color: _blue),
                  ),
                  const SizedBox(width: 12),
                  // Title + subtitle + chips
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Scanning Route',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0D1B2A),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: _blue.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'LIVE',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: _blue,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Identifying obstacles on your route…',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF5C6B7A),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            _chip(Icons.car_crash_outlined, 'Accidents'),
                            const SizedBox(width: 5),
                            _chip(Icons.construction_rounded, 'Road Works'),
                            const SizedBox(width: 5),
                            _chip(Icons.warning_amber_rounded, 'Hazards'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Indeterminate scan progress bar
            ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              child: LinearProgressIndicator(
                minHeight: 3,
                backgroundColor: Colors.grey.shade100,
                valueColor: const AlwaysStoppedAnimation<Color>(_blue),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF4FF),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: _blue),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: _blue,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
