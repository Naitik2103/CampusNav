import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math';
import 'dart:async';
import 'dart:io' show Platform;
import '../models/path_model.dart';
import '../models/place_model.dart';
import '../models/route_model.dart' as route_model;
import '../services/geojson_loader.dart';
import '../services/location_search_service.dart';
import '../services/routing_service.dart';
import '../services/campus_routing_service.dart';
import '../services/path_based_routing_service.dart';
import '../services/indoor_navigation_service.dart';
import '../models/indoor_models.dart';
import 'route_comparison_screen.dart';
import 'indoor_navigation_screen.dart';
import 'navigation_screen.dart';

enum OutdoorMapQuickAction { none, planRoute, planMultiStopRoute }

/// Main map screen for outdoor navigation
class OutdoorMapScreen extends StatefulWidget {
  final OutdoorMapQuickAction initialQuickAction;
  final VoidCallback? onQuickActionHandled;

  const OutdoorMapScreen({
    super.key,
    this.initialQuickAction = OutdoorMapQuickAction.none,
    this.onQuickActionHandled,
  });

  @override
  State<OutdoorMapScreen> createState() => _OutdoorMapScreenState();
}

class _OutdoorMapScreenState extends State<OutdoorMapScreen> {
  static const Color _brandColor = Color(0xFF0B5FFF);
  static const Color _textStrong = Color(0xFF162033);
  static const double _maxLiveAccuracyMeters = 45;
  static const int _maxFixAgeSeconds = 15;
  static const double _maxWalkingSpeedMps = 8;
  static const double _positionSmoothingFactor = 0.35;

  late MapController _mapController;
  List<CampusPath> _paths = [];
  List<CampusPlace> _places = [];
  List<CampusPlace> _filteredPlaces = [];
  List<IndoorRoom> _filteredRooms = [];
  final Set<String> _visibleLayers = {'paths', 'places'};
  bool _isLoading = true;
  LatLng? _userLocation;
  bool _gettingLocation = false;
  String _searchQuery = '';
  StreamSubscription<Position>? _positionSubscription;
  bool _hasCenteredOnUser = false;
  Position? _lastAcceptedPosition;
  DateTime? _lastAcceptedAt;
  double? _lastAccuracyMeters;
  double _currentZoom = 15.0;
  CampusPlace? _lastPlannerFrom;
  CampusPlace? _lastPlannerTo;
  List<CampusPlace> _lastPlannerIntermediateStops = [];
  bool _lastPlannerOptimizeOrder = true;
  bool _lastPlannerUseLiveSource = false;
  bool _indoorConfigLoaded = false;
  String? _currentDetectedIndoorBuildingId;
  bool _isIndoorScreenActive = false;
  OutdoorMapQuickAction _pendingQuickAction = OutdoorMapQuickAction.none;

  // New: Track current active route for display
  List<LatLng>? _activeRoutePath;
  List<CampusPlace> _activeRoutePlaces = [];

  // Default campus location (example coordinates - Delhi area)
  static const LatLng defaultLocation = LatLng(23.189382, 72.628233);

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _pendingQuickAction = widget.initialQuickAction;
    _loadCampusData();
    _requestLocationPermission();
  }

  @override
  void didUpdateWidget(covariant OutdoorMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.initialQuickAction != oldWidget.initialQuickAction &&
        widget.initialQuickAction != OutdoorMapQuickAction.none) {
      _pendingQuickAction = widget.initialQuickAction;
      _consumePendingQuickAction();
    }
  }

  Future<void> _requestLocationPermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enable phone location services'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Location permanently denied. Enable it in app settings.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        await _getUserLocation();
        _startLiveLocationTracking();
      }
    } catch (e) {
      print('Error requesting location permission: $e');
    }
  }

  LocationSettings _buildLocationSettings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 3,
        intervalDuration: Duration(seconds: 2),
      );
    }

    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 3,
    );
  }

  void _startLiveLocationTracking() {
    _positionSubscription?.cancel();
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: _buildLocationSettings(),
        ).listen(
          (Position position) {
            if (!mounted) return;

            if (!_isReliableFix(
              position,
              allowInitialRelaxation: _userLocation == null,
            )) {
              return;
            }

            final nextLocation = _smoothedLocation(
              LatLng(position.latitude, position.longitude),
            );

            setState(() {
              _userLocation = nextLocation;
              _lastAccuracyMeters = position.accuracy;
            });

            _lastAcceptedPosition = position;
            _lastAcceptedAt = DateTime.now();

            _handleIndoorBuildingDetection(nextLocation);

            if (!_hasCenteredOnUser) {
              _mapController.move(nextLocation, 18.0);
              _hasCenteredOnUser = true;
            }
          },
          onError: (error) {
            print('Live location stream error: $error');
          },
        );
  }

  Future<void> _getUserLocation() async {
    setState(() => _gettingLocation = true);
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 10),
      );

      if (!_isReliableFix(position, allowInitialRelaxation: true)) {
        throw Exception('Low-quality GPS fix, trying again');
      }

      final smoothed = _smoothedLocation(
        LatLng(position.latitude, position.longitude),
      );

      if (mounted) {
        setState(() {
          _userLocation = smoothed;
          _gettingLocation = false;
          _lastAccuracyMeters = position.accuracy;
        });

        _lastAcceptedPosition = position;
        _lastAcceptedAt = DateTime.now();
        _handleIndoorBuildingDetection(smoothed);

        // Automatically center on location after getting it
        _mapController.move(smoothed, 18.0);
        _hasCenteredOnUser = true;

        // Show a snackbar when location is obtained
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Your location obtained'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _gettingLocation = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not get your location'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      print('Error getting location: $e');
    }
  }

  bool _isReliableFix(
    Position position, {
    bool allowInitialRelaxation = false,
  }) {
    final now = DateTime.now();
    final fixTime = position.timestamp ?? now;
    final ageSeconds = now.difference(fixTime).inSeconds;

    final maxAllowedAccuracy = allowInitialRelaxation
        ? 70.0
        : _maxLiveAccuracyMeters;
    if (position.accuracy <= 0 || position.accuracy > maxAllowedAccuracy) {
      return false;
    }

    if (ageSeconds > _maxFixAgeSeconds) {
      return false;
    }

    if (_lastAcceptedPosition != null) {
      const distanceCalc = Distance();
      final previousPoint = LatLng(
        _lastAcceptedPosition!.latitude,
        _lastAcceptedPosition!.longitude,
      );
      final currentPoint = LatLng(position.latitude, position.longitude);
      final deltaMeters = distanceCalc(previousPoint, currentPoint);

      final previousTime =
          _lastAcceptedPosition!.timestamp ?? _lastAcceptedAt ?? now;
      final dtMillis =
          (fixTime.millisecondsSinceEpoch - previousTime.millisecondsSinceEpoch)
              .abs();

      if (dtMillis > 0) {
        final speedMps = deltaMeters / (dtMillis / 1000.0);
        if (speedMps > _maxWalkingSpeedMps && position.accuracy > 18) {
          return false;
        }
      }
    }

    return true;
  }

  LatLng _smoothedLocation(LatLng raw) {
    if (_userLocation == null) return raw;

    final lat =
        _userLocation!.latitude +
        (raw.latitude - _userLocation!.latitude) * _positionSmoothingFactor;
    final lng =
        _userLocation!.longitude +
        (raw.longitude - _userLocation!.longitude) * _positionSmoothingFactor;

    return LatLng(lat, lng);
  }

  String _accuracyLabel(double meters) {
    if (meters <= 8) return 'High';
    if (meters <= 20) return 'Medium';
    return 'Low';
  }

  Color _accuracyColor(double meters) {
    if (meters <= 8) return const Color(0xFF16A34A);
    if (meters <= 20) return const Color(0xFFD97706);
    return const Color(0xFFDC2626);
  }

  Future<void> _loadCampusData() async {
    try {
      print('\n===== LOADING CAMPUS DATA =====');
      final paths = await GeoJsonLoader.loadPaths(
        'assets/data/campus_paths.geojson',
      );
      print('✓ Loaded ${paths.length} paths from GeoJSON');
      for (var path in paths) {
        print(
          '  - ${path.id}: "${path.name}" (${path.coordinates.length} coords, walkable: ${path.walkable})',
        );
      }

      final places = await GeoJsonLoader.loadPlaces(
        'assets/data/campus_places.geojson',
      );
      await IndoorNavigationService.instance.loadIndoorConfigs();
      print('✓ Loaded ${places.length} places from GeoJSON');
      for (var place in places) {
        print(
          '  - ${place.id}: "${place.name}" at [${place.location.latitude.toStringAsFixed(6)}, ${place.location.longitude.toStringAsFixed(6)}]',
        );
      }
      print('===============================\n');

      setState(() {
        _paths = paths;
        _places = places;
        _filteredPlaces = places;
        _indoorConfigLoaded = IndoorNavigationService.instance.isLoaded;
        _isLoading = false;
      });

      _consumePendingQuickAction();
    } catch (e) {
      print('❌ Error loading campus data: $e');
      setState(() => _isLoading = false);
    }
  }

  void _consumePendingQuickAction() {
    if (!mounted || _isLoading) return;
    if (_pendingQuickAction == OutdoorMapQuickAction.none) return;

    final action = _pendingQuickAction;
    _pendingQuickAction = OutdoorMapQuickAction.none;
    widget.onQuickActionHandled?.call();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (action == OutdoorMapQuickAction.planRoute) {
        await _showRoutePlannerPanel();
        return;
      }
      if (action == OutdoorMapQuickAction.planMultiStopRoute) {
        await _showMultiStopRoutePlannerPanel();
      }
    });
  }

  void _searchPlaces(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredPlaces = _places;
        _filteredRooms = [];
      } else {
        // Use the location search service for better filtering
        _filteredPlaces = LocationSearchService.searchPlaces(query, _places);
        // Rank results by relevance
        _filteredPlaces = LocationSearchService.rankResults(
          query,
          _filteredPlaces,
        );
        _filteredRooms = _indoorConfigLoaded
            ? IndoorNavigationService.instance.searchRooms(query)
            : [];
      }
    });
  }

  String _normalizeKey(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  CampusPlace? _findNearestGateForBuilding(IndoorBuilding building) {
    final buildingIdKey = _normalizeKey(building.buildingId);
    final buildingNameKeys = <String>{
      _normalizeKey(building.name),
      ...building.aliases.map(_normalizeKey),
    }..removeWhere((key) => key.isEmpty);

    final matchingGates = _places.where((place) {
      if (place.placeType.toLowerCase() != 'gate') {
        return false;
      }

      final placeNameKey = _normalizeKey(place.name);
      final placeIdKey = _normalizeKey(place.id);

      return placeNameKey.contains(buildingIdKey) ||
          placeIdKey.contains(buildingIdKey) ||
          buildingNameKeys.any(
          (buildingNameKey) =>
            placeNameKey.contains(buildingNameKey) ||
            placeIdKey.contains(buildingNameKey),
          );
    }).toList();

    if (matchingGates.isEmpty) {
      return null;
    }

    if (_userLocation == null) {
      return matchingGates.first;
    }

    final distance = const Distance();
    matchingGates.sort(
      (a, b) => distance(
        _userLocation!,
        a.location,
      ).compareTo(distance(_userLocation!, b.location)),
    );

    return matchingGates.first;
  }

  Future<void> _navigateToRoomViaNearestGate(IndoorRoom room) async {
    if (_userLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enable location to navigate.')),
      );
      return;
    }

    if (!_indoorConfigLoaded) {
      await IndoorNavigationService.instance.loadIndoorConfigs();
      _indoorConfigLoaded = IndoorNavigationService.instance.isLoaded;
    }

    final building = IndoorNavigationService.instance.findBuildingById(
      room.buildingId,
    );
    if (building == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Building config missing for ${room.buildingId}.'),
        ),
      );
      return;
    }

    final nearestGate = _findNearestGateForBuilding(building);
    if (nearestGate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No gate found for ${building.name}. Add gate in place data.',
          ),
        ),
      );
      return;
    }

    await _fetchAndDisplayRoute(_userLocation!, nearestGate.location);
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RouteComparisonScreen(
          startLocation: _userLocation!,
          endLocation: nearestGate.location,
          destinationName: '${nearestGate.name} (for ${room.name})',
        ),
      ),
    );

    if (!mounted) return;
    setState(() {
      _activeRoutePath = null;
    });

    await _openIndoorMap(building: building, initialFloor: room.floor);
  }

  Color _getPathColor(CampusPath path) {
    if (!path.walkable) return Colors.red;
    switch (path.difficulty) {
      case 'easy':
        return Colors.blue;
      case 'medium':
        return Colors.orange;
      case 'hard':
        return Colors.red.shade700;
      default:
        return Colors.blue;
    }
  }

  IconData _getPlaceIcon(CampusPlace place) {
    switch (place.placeType) {
      case 'building':
        return Icons.apartment;
      case 'parking':
        return Icons.local_parking;
      case 'restroom':
        return Icons.wc;
      case 'landmark':
        return Icons.place;
      default:
        return Icons.location_on;
    }
  }

  Color _getPlaceColor(CampusPlace place) {
    switch (place.placeType) {
      case 'building':
        return Colors.purple;
      case 'parking':
        return Colors.blue;
      case 'restroom':
        return Colors.green;
      case 'landmark':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  void _toggleLayer(String layer) {
    setState(() {
      if (_visibleLayers.contains(layer)) {
        _visibleLayers.remove(layer);
      } else {
        _visibleLayers.add(layer);
      }
    });
  }

  void _centerOnCampus() {
    if (_userLocation != null) {
      _mapController.move(_userLocation!, 18.0);
    } else {
      _mapController.move(defaultLocation, 18.0);
    }
  }

  void _handleIndoorBuildingDetection(LatLng location) {
    if (!_indoorConfigLoaded || _isIndoorScreenActive || !mounted) {
      return;
    }

    final building = IndoorNavigationService.instance.findBuildingByGps(
      location,
    );
    final detectedId = building?.buildingId;

    if (detectedId == _currentDetectedIndoorBuildingId) {
      return;
    }

    _currentDetectedIndoorBuildingId = detectedId;

    if (building != null && building.hasIndoorMap) {
      unawaited(_openIndoorMap(building: building));
    }
  }

  Future<void> _openIndoorMapForPlace(CampusPlace place) async {
    if (!_indoorConfigLoaded) {
      await IndoorNavigationService.instance.loadIndoorConfigs();
      _indoorConfigLoaded = IndoorNavigationService.instance.isLoaded;
    }

    if (!_indoorConfigLoaded) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Indoor configuration is not available yet.'),
        ),
      );
      return;
    }

    final building = IndoorNavigationService.instance.findBuildingForPlace(
      place,
    );
    if (building == null || !building.hasIndoorMap) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Indoor map is not configured for ${place.name}.'),
        ),
      );
      return;
    }

    await _openIndoorMap(building: building);
  }

  Future<void> _openIndoorMap({
    required IndoorBuilding building,
    int? initialFloor,
  }) async {
    if (_isIndoorScreenActive || !mounted) return;

    _isIndoorScreenActive = true;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => IndoorNavigationScreen(
          building: building,
          initialFloor: initialFloor ?? building.groundFloor,
          currentGpsLocation: _userLocation,
        ),
      ),
    );
    _isIndoorScreenActive = false;
  }

  Widget _buildPlaceSearchTile(CampusPlace place, ColorScheme colors) {
    final displayName = _getPlaceDisplayName(place);

    return ListTile(
      leading: Icon(_getPlaceIcon(place), color: _getPlaceColor(place)),
      title: Text(displayName),
      subtitle: place.aliases.isNotEmpty && displayName != place.name
          ? Text(
              '${place.name} • ${place.placeType.toUpperCase()}',
              style: TextStyle(
                letterSpacing: 0.4,
                color: colors.onSurfaceVariant,
                fontSize: 11,
              ),
            )
          : Text(
              place.placeType.toUpperCase(),
              style: TextStyle(
                letterSpacing: 0.4,
                color: colors.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
      trailing: IconButton(
        icon: const Icon(Icons.directions, color: _brandColor),
        tooltip: 'Get Route',
        onPressed: () {
          if (_userLocation != null) {
            _navigateToRoutingScreen(place);
          } else {
            _showRoutePlannerPanel(prefilledDestination: place);
          }
        },
      ),
      onTap: () => _showPlaceInfo(place),
    );
  }

  String _getPlaceDisplayName(CampusPlace place) {
    final query = _normalizeKey(_searchQuery);
    if (query.isEmpty) {
      return place.name;
    }

    if (_normalizeKey(place.name) == query) {
      return place.name;
    }

    for (final alias in place.aliases) {
      if (_normalizeKey(alias) == query) {
        return alias;
      }
    }

    final matchingAlias = place.aliases.firstWhere(
      (alias) => _normalizeKey(alias).contains(query),
      orElse: () => '',
    );

    if (matchingAlias.isNotEmpty) {
      return matchingAlias;
    }

    return place.name;
  }

  Widget _buildRoomSearchTile(IndoorRoom room, ColorScheme colors) {
    final building = IndoorNavigationService.instance.findBuildingById(
      room.buildingId,
    );
    final buildingName = building?.name ?? room.buildingId.toUpperCase();

    return ListTile(
      leading: const Icon(Icons.meeting_room_rounded, color: _brandColor),
      title: Text(room.name),
      subtitle: Text(
        '$buildingName • Floor ${room.floor}',
        style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
      ),
      trailing: const Icon(Icons.alt_route_rounded, color: _brandColor),
      onTap: () => _navigateToRoomViaNearestGate(room),
    );
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        titleSpacing: 4,
        title: const Text('Campus Navigator'),
        leading: IconButton(
          icon: const Icon(Icons.route_rounded, color: _brandColor),
          onPressed: _showMultiStopRoutePlannerPanel,
          tooltip: 'Plan Multi-Stop Route',
        ),
        toolbarHeight: 72,
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.alt_route_rounded, color: _brandColor),
            onPressed: _showRoutePlannerPanel,
            tooltip: 'Plan Route (From/To)',
          ),
          IconButton(
            icon: const Icon(Icons.layers_outlined, color: _brandColor),
            onPressed: () => _showLayerPanel(context),
            tooltip: 'Toggle Layers',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Divider(height: 2, thickness: 1, color: colors.outlineVariant),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: defaultLocation,
                    initialZoom: 15.0,
                    minZoom: 10.0,
                    maxZoom: 20.0,
                    onPositionChanged: (position, _) {
                      final zoom = position.zoom;
                      if (zoom != null && (zoom - _currentZoom).abs() > 0.05) {
                        setState(() => _currentZoom = zoom);
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.new_project',
                    ),
                    // Render paths
                    if (_visibleLayers.contains('paths'))
                      PolylineLayer(
                        polylines: _paths
                            .map(
                              (path) => Polyline(
                                points: path.coordinates,
                                color: _getPathColor(path),
                                strokeWidth: 4.0,
                                isDotted: !path.walkable,
                              ),
                            )
                            .toList(),
                      ),
                    // Render active route path (from user to destination)
                    if (_activeRoutePath != null &&
                        _activeRoutePath!.isNotEmpty)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _activeRoutePath!,
                            color: Colors.blue,
                            strokeWidth: 6.0,
                            borderColor: Colors.blue.shade900,
                            borderStrokeWidth: 2.0,
                          ),
                        ],
                      ),
                    if (_activeRoutePlaces.isNotEmpty)
                      MarkerLayer(
                        markers: _activeRoutePlaces.asMap().entries
                            .where((entry) {
                              final isFirst = entry.key == 0;
                              final isLiveSource =
                                  entry.value.id == '__live_source__';
                              // Keep existing live-location marker style for live source.
                              return !(isFirst && isLiveSource);
                            })
                            .map((entry) {
                          final index = entry.key;
                          final place = entry.value;
                          final isFirst = index == 0;
                          final isLast = index == _activeRoutePlaces.length - 1;
                          final isLiveSource = place.id == '__live_source__';
                          final showGreenSourcePin = isFirst && !isLiveSource;
                          final showRedDestinationPin = isLast;
                          final markerSize = _placeMarkerSizeForZoom();
                          final iconSize = _placeIconSizeForZoom();

                          return Marker(
                            point: place.location,
                            width: markerSize,
                            height: markerSize,
                            child: showGreenSourcePin
                                ? Icon(
                                    Icons.location_pin,
                                    color: Colors.green,
                                    size: iconSize + 10,
                                  )
                                : showRedDestinationPin
                                ? Icon(
                                    Icons.location_pin,
                                    color: Colors.red,
                                    size: iconSize + 10,
                                  )
                                : Container(
                                    decoration: BoxDecoration(
                                      color: _getPlaceColor(place),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: markerSize >= 36 ? 2 : 1.6,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black26,
                                          blurRadius:
                                              markerSize >= 36 ? 4 : 3,
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      _getPlaceIcon(place),
                                      color: Colors.white,
                                      size: iconSize,
                                    ),
                                  ),
                          );
                        }).toList(),
                      ),
                    // Render places
                    if (_visibleLayers.contains('places'))
                      MarkerLayer(
                        markers: [
                          // User location marker
                          if (_userLocation != null)
                            Marker(
                              point: _userLocation!,
                              width: 40,
                              height: 40,
                              child: Column(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: Colors.blue,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.blue.withOpacity(0.3),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // Place markers
                          ..._filteredPlaces.map((place) {
                            final markerSize = _placeMarkerSizeForZoom();
                            final iconSize = _placeIconSizeForZoom();

                            return Marker(
                              point: place.location,
                              width: markerSize,
                              height: markerSize,
                              child: GestureDetector(
                                onTap: () => _showPlaceInfo(place),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: _getPlaceColor(place),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: markerSize >= 36 ? 2 : 1.6,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: markerSize >= 36 ? 4 : 3,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    _getPlaceIcon(place),
                                    color: Colors.white,
                                    size: iconSize,
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                  ],
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(18),
                    color: Colors.white,
                    child: TextField(
                      onChanged: _searchPlaces,
                      decoration: InputDecoration(
                        hintText:
                            'Search buildings, gates, parking, room no...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 22),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 20),
                                onPressed: () => _searchPlaces(''),
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(
                            color: _brandColor,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Legend
                Positioned(
                  bottom: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: colors.outlineVariant),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Path Difficulty',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _textStrong,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildLegendItem('Easy', Colors.blue),
                        _buildLegendItem('Medium', Colors.orange),
                        _buildLegendItem('Hard', Colors.red),
                      ],
                    ),
                  ),
                ),
                // Search Results Panel
                if (_searchQuery.isNotEmpty &&
                    (_filteredPlaces.isNotEmpty || _filteredRooms.isNotEmpty))
                  Positioned(
                    top: 78,
                    left: 16,
                    right: 16,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: colors.outlineVariant),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 300),
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            if (_filteredRooms.isNotEmpty)
                              const Padding(
                                padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
                                child: Text(
                                  'Rooms',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ..._filteredRooms.map(
                              (room) => _buildRoomSearchTile(room, colors),
                            ),
                            if (_filteredRooms.isNotEmpty &&
                                _filteredPlaces.isNotEmpty)
                              const Divider(height: 1),
                            if (_filteredPlaces.isNotEmpty)
                              const Padding(
                                padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
                                child: Text(
                                  'Places',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ..._filteredPlaces.map(
                              (place) => _buildPlaceSearchTile(place, colors),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                // Location button - combined get location and center
                if (_lastAccuracyMeters != null)
                  Positioned(
                    bottom: 86,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.gps_fixed_rounded,
                            size: 14,
                            color: _accuracyColor(_lastAccuracyMeters!),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'GPS ${_accuracyLabel(_lastAccuracyMeters!)} (${_lastAccuracyMeters!.toStringAsFixed(0)}m)',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: FloatingActionButton.extended(
                    onPressed: _gettingLocation
                        ? null
                        : () async {
                            if (_userLocation == null) {
                              await _getUserLocation();
                            } else {
                              _centerOnCampus();
                            }
                          },
                    tooltip: _userLocation == null
                        ? 'Get My Location'
                        : 'Center on My Location',
                    backgroundColor: _gettingLocation
                        ? Colors.grey
                        : _brandColor,
                    icon: _gettingLocation
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Icon(Icons.my_location_rounded),
                    label: Text(
                      _userLocation == null ? 'Locate Me' : 'Recenter',
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  double _placeMarkerSizeForZoom() {
    // Keep existing visual size for zoomed-in levels, shrink gradually when zooming out.
    if (_currentZoom >= 15.0) return 30.0;
    if (_currentZoom <= 10.0) return 18.0;

    final t = (_currentZoom - 10.0) / 5.0;
    return 18.0 + (22.0 * t);
  }

  double _placeIconSizeForZoom() {
    if (_currentZoom >= 15.0) return 20.0;
    if (_currentZoom <= 10.0) return 10.0;

    final t = (_currentZoom - 10.0) / 5.0;
    return 10.0 + (10.0 * t);
  }

  void _showPlaceInfo(CampusPlace place) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_getPlaceIcon(place), color: _getPlaceColor(place)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        place.placeType,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (place.description != null)
              Text(place.description!, style: const TextStyle(fontSize: 14)),
            if (place.department != null) ...[
              const SizedBox(height: 8),
              Text(
                'Department: ${place.department}',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
            if (place.floors != null) ...[
              const SizedBox(height: 8),
              Text(
                'Floors: ${place.floors}',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
            if (place.hasIndoorMap) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await _openIndoorMapForPlace(place);
                },
                icon: const Icon(Icons.layers),
                label: const Text('View Indoor Map'),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  if (_userLocation != null) {
                    _navigateToRoutingScreen(place);
                  } else {
                    _showRoutePlannerPanel(prefilledDestination: place);
                  }
                },
                icon: const Icon(Icons.directions),
                label: Text(
                  _userLocation != null
                      ? 'Get Route from My Location'
                      : 'Plan Route Between Places',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _brandColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRoutePlannerPanel({
    CampusPlace? prefilledDestination,
  }) async {
    if (_places.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Not enough places loaded to plan a route.'),
        ),
      );
      return;
    }

    CampusPlace? selectedFrom = _lastPlannerFrom;
    CampusPlace? selectedTo = prefilledDestination ?? _lastPlannerTo;

    final result = await showModalBottomSheet<Map<String, CampusPlace>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Plan Route Between Places',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Example: Canteen to LT1 (even if you are currently at G Wing)',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 14),
                  DropdownMenu<CampusPlace>(
                    width: double.infinity,
                    enableFilter: true,
                    requestFocusOnTap: true,
                    initialSelection: selectedFrom,
                    leadingIcon: const Icon(Icons.trip_origin_rounded),
                    label: const Text('From'),
                    dropdownMenuEntries: _places
                        .map(
                          (place) => DropdownMenuEntry<CampusPlace>(
                            value: place,
                            label: place.name,
                          ),
                        )
                        .toList(),
                    onSelected: (place) {
                      setModalState(() {
                        selectedFrom = place;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: IconButton.filledTonal(
                      onPressed: selectedFrom != null && selectedTo != null
                          ? () {
                              setModalState(() {
                                final tmp = selectedFrom;
                                selectedFrom = selectedTo;
                                selectedTo = tmp;
                              });
                            }
                          : null,
                      icon: const Icon(Icons.swap_vert_rounded),
                      tooltip: 'Swap from and to',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownMenu<CampusPlace>(
                    width: double.infinity,
                    enableFilter: true,
                    requestFocusOnTap: true,
                    initialSelection: selectedTo,
                    leadingIcon: const Icon(Icons.location_on_rounded),
                    label: const Text('To'),
                    dropdownMenuEntries: _places
                        .map(
                          (place) => DropdownMenuEntry<CampusPlace>(
                            value: place,
                            label: place.name,
                          ),
                        )
                        .toList(),
                    onSelected: (place) {
                      setModalState(() {
                        selectedTo = place;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: selectedFrom != null && selectedTo != null
                              ? () {
                                  Navigator.pop(context, {
                                    'from': selectedFrom!,
                                    'to': selectedTo!,
                                  });
                                }
                              : null,
                          icon: const Icon(Icons.alt_route_rounded),
                          label: const Text('Show Route'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _lastPlannerFrom = result['from'];
      _lastPlannerTo = result['to'];
    });

    await _navigateBetweenPlaces(result['from']!, result['to']!);
  }

  List<CampusPlace> _optimizeStopOrder(
    List<CampusPlace> selectedStops, {
    required bool keepLast,
  }) {
    if (selectedStops.length <= 2) return selectedStops;

    final order = RoutingService.optimizeVisitOrder(
      selectedStops.map((p) => p.location).toList(),
      keepFirst: true,
      keepLast: keepLast,
    );

    return order.map((idx) => selectedStops[idx]).toList();
  }

  String _orderedStopNames(List<CampusPlace> orderedStops) {
    return orderedStops.map((p) => p.name).join(' -> ');
  }

  CampusPlace _liveLocationAsPlace() {
    return CampusPlace(
      id: '__live_source__',
      name: 'My Live Location',
      location: _userLocation!,
      placeType: 'live_source',
    );
  }

  Future<void> _showMultiStopRoutePlannerPanel() async {
    CampusPlace? selectedFrom = _lastPlannerFrom;
    CampusPlace? selectedTo = _lastPlannerTo;
    List<CampusPlace> draftSelectedStops = List<CampusPlace>.from(
      _lastPlannerIntermediateStops,
    );
    bool draftOptimizeOrder = _lastPlannerOptimizeOrder;
    bool draftUseLiveSource = _lastPlannerUseLiveSource;

    final result =
        await showModalBottomSheet<Map<String, dynamic>>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) {
            return StatefulBuilder(
              builder: (context, setModalState) {
                final selectableStops = _places.where((place) {
                  if (selectedFrom?.id == place.id) return false;
                  if (selectedTo?.id == place.id) return false;
                  return true;
                }).toList()
                  ..sort(
                    (a, b) => a.name.toLowerCase().compareTo(
                      b.name.toLowerCase(),
                    ),
                  );

                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    MediaQuery.of(context).viewInsets.bottom + 16,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Plan Multi-Stop Route',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Choose start, destination, and intermediate stops. We can optimize stop order for shortest path.',
                          style: TextStyle(color: Colors.black54),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          value: draftUseLiveSource,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Use my live location as source'),
                          subtitle: Text(
                            _userLocation == null
                                ? 'Waiting for GPS fix. Enable location for real-time start.'
                                : 'Start route from your current GPS position.',
                          ),
                          onChanged: (value) {
                            setModalState(() {
                              draftUseLiveSource = value;
                              if (value) {
                                selectedFrom = null;
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 14),
                        DropdownMenu<CampusPlace>(
                          width: double.infinity,
                          enabled: !draftUseLiveSource,
                          enableFilter: true,
                          requestFocusOnTap: false,
                          initialSelection: selectedFrom,
                          leadingIcon: const Icon(Icons.trip_origin_rounded),
                          label: const Text('Start (From)'),
                          dropdownMenuEntries: _places
                              .map(
                                (place) => DropdownMenuEntry<CampusPlace>(
                                  value: place,
                                  label: place.name,
                                ),
                              )
                              .toList(),
                          onSelected: (place) {
                            setModalState(() {
                              selectedFrom = place;
                              draftSelectedStops.removeWhere(
                                (stop) => stop.id == place?.id,
                              );
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownMenu<CampusPlace>(
                          width: double.infinity,
                          enableFilter: true,
                          requestFocusOnTap: false,
                          initialSelection: selectedTo,
                          leadingIcon: const Icon(Icons.location_on_rounded),
                          label: const Text('Destination (Optional)'),
                          dropdownMenuEntries: _places
                              .map(
                                (place) => DropdownMenuEntry<CampusPlace>(
                                  value: place,
                                  label: place.name,
                                ),
                              )
                              .toList(),
                          onSelected: (place) {
                            setModalState(() {
                              selectedTo = place;
                              draftSelectedStops.removeWhere(
                                (stop) => stop.id == place?.id,
                              );
                            });
                          },
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Intermediate Stops',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        if (selectableStops.isEmpty)
                          const Text(
                            'No additional places available for stops.',
                            style: TextStyle(color: Colors.black54),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: selectableStops.map((place) {
                              final selected = draftSelectedStops.any(
                                (stop) => stop.id == place.id,
                              );

                              return FilterChip(
                                label: Text(place.name),
                                selected: selected,
                                onSelected: (pick) {
                                  setModalState(() {
                                    if (pick) {
                                      draftSelectedStops.add(place);
                                    } else {
                                      draftSelectedStops.removeWhere(
                                        (stop) => stop.id == place.id,
                                      );
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        const SizedBox(height: 10),
                        SwitchListTile(
                          value: draftOptimizeOrder,
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Optimize stop order'),
                          subtitle: const Text(
                            'Recommended: avoids visiting far stops too early.',
                          ),
                          onChanged: (value) {
                            setModalState(() {
                              draftOptimizeOrder = value;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  if (draftUseLiveSource &&
                                      _userLocation == null) {
                                    showDialog<void>(
                                      context: context,
                                      builder: (dialogContext) => AlertDialog(
                                        title: const Text('Location Needed'),
                                        content: const Text(
                                          'Live location is not available yet. Please enable location and try again.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(
                                              dialogContext,
                                            ),
                                            child: const Text('OK'),
                                          ),
                                        ],
                                      ),
                                    );
                                    return;
                                  }

                                  final selectedSequence = <CampusPlace>[
                                    if (draftUseLiveSource &&
                                        _userLocation != null)
                                      _liveLocationAsPlace(),
                                    if (selectedFrom != null) selectedFrom!,
                                    ...draftSelectedStops,
                                    if (selectedTo != null) selectedTo!,
                                  ];

                                  final uniqueCount = selectedSequence
                                      .map((p) => p.id)
                                      .toSet()
                                      .length;

                                  if (uniqueCount < 2) {
                                    showDialog<void>(
                                      context: context,
                                      builder: (dialogContext) => AlertDialog(
                                        title: const Text('Not Enough Places'),
                                        content: const Text(
                                          'Please choose at least two places to generate a route.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(
                                              dialogContext,
                                            ),
                                            child: const Text('OK'),
                                          ),
                                        ],
                                      ),
                                    );
                                    return;
                                  }

                                  Navigator.pop(context, {
                                    'from': selectedFrom,
                                    'to': selectedTo,
                                    'stops': draftSelectedStops,
                                    'optimize': draftOptimizeOrder,
                                          'useLiveSource': draftUseLiveSource,
                                  });
                                },
                                icon: const Icon(Icons.route_rounded),
                                label: const Text('Start Multi-Stop'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );

    if (!mounted || result == null) return;

    final start = result['from'] as CampusPlace?;
    final end = result['to'] as CampusPlace?;
    final stops = (result['stops'] as List).cast<CampusPlace>();
    final optimizeOrder = (result['optimize'] as bool?) ?? true;
    final useLiveSource = (result['useLiveSource'] as bool?) ?? false;

    final selectedStops = <CampusPlace>[
      if (useLiveSource && _userLocation != null) _liveLocationAsPlace(),
      ?start,
      ...stops,
      ?end,
    ];

    final uniqueSelectedStops = <CampusPlace>[];
    final seenIds = <String>{};
    for (final place in selectedStops) {
      if (seenIds.add(place.id)) {
        uniqueSelectedStops.add(place);
      }
    }

    if (uniqueSelectedStops.length < 2) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Not Enough Places'),
          content: const Text(
            'Please choose at least two places to generate a route.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final keepLastFixed = end != null;
    final orderedStops = optimizeOrder
        ? _optimizeStopOrder(uniqueSelectedStops, keepLast: keepLastFixed)
        : uniqueSelectedStops;

    setState(() {
      _lastPlannerFrom = start;
      _lastPlannerTo = end;
      _lastPlannerIntermediateStops = stops;
      _lastPlannerOptimizeOrder = optimizeOrder;
      _lastPlannerUseLiveSource = useLiveSource;
    });

    await _startMultiStopNavigation(orderedStops, optimizeOrder: optimizeOrder);
  }

  Future<void> _startMultiStopNavigation(
    List<CampusPlace> orderedStops, {
    required bool optimizeOrder,
  }) async {
    if (orderedStops.length < 2) {
      return;
    }

    final route = await _buildFallbackMultiStopRoute(orderedStops);

    if (route == null || route.waypoints.length < 2) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not generate multi-stop route right now.'),
        ),
      );
      return;
    }

    final resolvedRoute = route;

    setState(() {
      _activeRoutePath = resolvedRoute.waypoints;
      _activeRoutePlaces = List<CampusPlace>.from(orderedStops);
    });
    _zoomToFitRoute(resolvedRoute.waypoints);

    if (!mounted) return;

    final summaryPrefix = optimizeOrder ? 'Optimized order' : 'Selected order';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$summaryPrefix: ${_orderedStopNames(orderedStops)}'),
        behavior: SnackBarBehavior.floating,
      ),
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NavigationScreen(
          startLocation: orderedStops.first.location,
          endLocation: orderedStops.last.location,
          destinationName: orderedStops.last.name,
          initialRoute: resolvedRoute,
          campusPaths: _paths,
          routePlaces: orderedStops,
        ),
      ),
    );

    if (!mounted) return;

    setState(() {
      _activeRoutePath = null;
      _activeRoutePlaces = [];
    });
  }

  Future<route_model.Route?> _buildFallbackMultiStopRoute(
    List<CampusPlace> orderedStops,
  ) async {
    if (orderedStops.length < 2) return null;

    final stitched = <LatLng>[];
    double totalDistance = 0;
    double totalDuration = 0;
    const distanceCalc = Distance();

    for (int i = 0; i < orderedStops.length - 1; i++) {
      final from = orderedStops[i].location;
      final to = orderedStops[i + 1].location;

      route_model.Route? segment = await PathBasedRoutingService.getPathBasedRoute(
        from,
        to,
        _paths,
      );

      segment ??= await CampusRoutingService.getCampusRoute(from, to, _paths);
      if (segment == null || segment.waypoints.length < 2) {
        return null;
      }

      final segmentPoints = segment.waypoints;
      if (stitched.isEmpty) {
        stitched.addAll(segmentPoints);
      } else {
        // Avoid duplicating the join point between two consecutive segments.
        stitched.addAll(segmentPoints.skip(1));
      }

      totalDistance += segment.totalDistance;
      totalDuration += segment.totalDuration;
    }

    if (stitched.length < 2) return null;

    if (totalDistance <= 0) {
      for (int i = 0; i < stitched.length - 1; i++) {
        totalDistance += distanceCalc(stitched[i], stitched[i + 1]);
      }
      totalDuration = totalDistance / 1.4;
    }

    return route_model.Route(
      id: 'multi_stop_fallback_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Multi-stop Route',
      steps: RoutingService.buildTurnAwareSteps(stitched),
      totalDistance: totalDistance,
      totalDuration: totalDuration,
      routeQuality: 4,
      routeType: 'multi_stop',
      wheelchairAccessible: true,
      waypoints: stitched,
    );
  }

  Future<void> _navigateBetweenPlaces(
    CampusPlace start,
    CampusPlace end,
  ) async {
    if (start.id == end.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start and destination cannot be same.')),
      );
      return;
    }

    await _fetchAndDisplayRoute(start.location, end.location);

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RouteComparisonScreen(
          startLocation: start.location,
          endLocation: end.location,
          destinationName: end.name,
        ),
      ),
    ).then((_) {
      setState(() {
        _activeRoutePath = null;
        _activeRoutePlaces = [];
      });
    });
  }

  void _navigateToRoutingScreen(CampusPlace destination) {
    // Route FROM the destination's location back to current location
    // This allows routing between campus places, not just from current GPS
    if (_userLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enable location to get routes')),
      );
      return;
    }

    // First, fetch and display the route on the map
    _fetchAndDisplayRoute(_userLocation!, destination.location);

    // Then navigate to the routing screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RouteComparisonScreen(
          startLocation: _userLocation!,
          endLocation: destination.location,
          destinationName: destination.name,
        ),
      ),
    ).then((_) {
      // Clear the active route when returning from routing screen
      setState(() {
        _activeRoutePath = null;
        _activeRoutePlaces = [];
      });
    });
  }

  Future<void> _fetchAndDisplayRoute(LatLng start, LatLng destination) async {
    try {
      print('════════════════════════════════════════');
      print('🧭 FETCHING ROUTE REQUEST');
      print(
        'Start: [${start.latitude.toStringAsFixed(6)}, ${start.longitude.toStringAsFixed(6)}]',
      );
      print(
        'Destination: [${destination.latitude.toStringAsFixed(6)}, ${destination.longitude.toStringAsFixed(6)}]',
      );
      print('Available paths in system: ${_paths.length}');

      // Always ensure paths are visible
      if (!_visibleLayers.contains('paths')) {
        setState(() {
          _visibleLayers.add('paths');
          print('✓ Re-enabled paths visibility');
        });
      }

      // Step 1: Try path-based routing first (uses campus paths from GeoJSON)
      print('\n📍 Step 1: Attempting PATH-BASED ROUTING...');
      print('   Passing ${_paths.length} campus paths to routing service');

      final route = await PathBasedRoutingService.getPathBasedRoute(
        start,
        destination,
        _paths,
      );

      if (route != null) {
        print('   ✅ SUCCESS! Path-based route found');
        print('   Waypoints: ${route.waypoints.length}');
        print('   Distance: ${route.totalDistance.toStringAsFixed(1)}m');
        setState(() {
          _activeRoutePath = route.waypoints;
        });
        _zoomToFitRoute(route.waypoints);
        print('✓ Route displayed on map\n');
        return;
      }

      print('   ❌ Path-based routing returned NULL\n');

      // Step 2: Fallback to campus-constrained routing
      print('📍 Step 2: Attempting CAMPUS-CONSTRAINED ROUTING...');
      final campusRoute = await CampusRoutingService.getCampusRoute(
        start,
        destination,
        _paths,
      );

      if (campusRoute != null) {
        print('   ✅ SUCCESS! Campus-constrained route found');
        print('   Waypoints: ${campusRoute.waypoints.length}');
        setState(() {
          _activeRoutePath = campusRoute.waypoints;
        });
        _zoomToFitRoute(campusRoute.waypoints);
        print('✓ Route displayed on map\n');
        return;
      }

      print('   ❌ Campus routing returned NULL\n');

      setState(() {
        _activeRoutePath = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No campus path found between selected locations. Please verify campus_paths.geojson connectivity.',
            ),
          ),
        );
      }
      print('════════════════════════════════════════\n');
    } catch (e, stacktrace) {
      print('════════════════════════════════════════');
      print('❌ ERROR FETCHING ROUTE: $e');
      print('Stack trace: $stacktrace');
      print('════════════════════════════════════════\n');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading route: $e')));
    }
  }

  void _zoomToFitRoute(List<LatLng> waypoints) {
    if (waypoints.isEmpty) return;

    try {
      // Calculate bounds for all waypoints
      double minLat = waypoints.first.latitude;
      double maxLat = waypoints.first.latitude;
      double minLng = waypoints.first.longitude;
      double maxLng = waypoints.first.longitude;

      for (var point in waypoints) {
        minLat = min(minLat, point.latitude);
        maxLat = max(maxLat, point.latitude);
        minLng = min(minLng, point.longitude);
        maxLng = max(maxLng, point.longitude);
      }

      // Create center point and zoom to fit
      final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);

      _mapController.move(center, 16.0);
    } catch (e) {
      print('Error zooming to route: $e');
    }
  }

  void _showLayerPanel(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Map Layers',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              title: const Text('Campus Paths'),
              value: _visibleLayers.contains('paths'),
              activeColor: _brandColor,
              onChanged: (_) => _toggleLayer('paths'),
            ),
            CheckboxListTile(
              title: const Text('Places & Buildings'),
              value: _visibleLayers.contains('places'),
              activeColor: _brandColor,
              onChanged: (_) => _toggleLayer('places'),
            ),
          ],
        ),
      ),
    );
  }
}
