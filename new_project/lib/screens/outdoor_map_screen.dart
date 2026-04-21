import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math';
import 'dart:async';
import 'dart:io' show Platform;
import '../models/path_model.dart';
import '../models/place_model.dart';
import '../services/geojson_loader.dart';
import '../services/location_search_service.dart';
import '../services/routing_service.dart';
import '../services/campus_routing_service.dart';
import '../services/path_based_routing_service.dart';
import 'route_comparison_screen.dart';

/// Main map screen for outdoor navigation
class OutdoorMapScreen extends StatefulWidget {
  const OutdoorMapScreen({super.key});

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

  // New: Track current active route for display
  List<LatLng>? _activeRoutePath;

  // Default campus location (example coordinates - Delhi area)
  static const LatLng defaultLocation = LatLng(23.189382, 72.628233);

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _loadCampusData();
    _requestLocationPermission();
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
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading campus data: $e');
      setState(() => _isLoading = false);
    }
  }

  void _searchPlaces(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredPlaces = _places;
      } else {
        // Use the location search service for better filtering
        _filteredPlaces = LocationSearchService.searchPlaces(query, _places);
        // Rank results by relevance
        _filteredPlaces = LocationSearchService.rankResults(
          query,
          _filteredPlaces,
        );
      }
    });
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
        title: const Text('Campus Navigator'),
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
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
                          ..._filteredPlaces.map(
                            (place) {
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
                            },
                          ),
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
                        hintText: 'Search buildings, gates, parking...',
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
                if (_searchQuery.isNotEmpty && _filteredPlaces.isNotEmpty)
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
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _filteredPlaces.length,
                          itemBuilder: (context, index) {
                            final place = _filteredPlaces[index];
                            return ListTile(
                              leading: Icon(
                                _getPlaceIcon(place),
                                color: _getPlaceColor(place),
                              ),
                              title: Text(place.name),
                              subtitle: Text(
                                place.placeType.toUpperCase(),
                                style: TextStyle(
                                  letterSpacing: 0.4,
                                  color: colors.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.directions,
                                  color: _brandColor,
                                ),
                                tooltip: 'Get Route',
                                onPressed: () {
                                  if (_userLocation != null) {
                                    _navigateToRoutingScreen(place);
                                  } else {
                                    _showRoutePlannerPanel(
                                      prefilledDestination: place,
                                    );
                                  }
                                },
                              ),
                              onTap: () => _showPlaceInfo(place),
                            );
                          },
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
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Indoor map for ${place.name} coming soon!',
                      ),
                    ),
                  );
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

      // Step 3: Fallback to standard OSRM route
      print('📍 Step 3: Attempting STANDARD OSRM ROUTING...');
      final standardRoute = await RoutingService.getRoute(start, destination);

      if (standardRoute != null) {
        print('   ⚠️  FALLBACK: OSRM route found (may go outside campus)');
        print('   Waypoints: ${standardRoute.waypoints.length}');
        setState(() {
          _activeRoutePath = standardRoute.waypoints;
        });
        _zoomToFitRoute(standardRoute.waypoints);
        print('✓ Route displayed on map\n');
        return;
      }

      print('   ❌ OSRM routing failed\n');

      // Step 4: Final fallback to demo route
      print('📍 Step 4: Using DEMO ROUTE...');
      final demoRoute = RoutingService.getDemoRoute(start, destination);
      setState(() {
        _activeRoutePath = demoRoute.waypoints;
      });
      _zoomToFitRoute(demoRoute.waypoints);
      print('✓ Demo route displayed\n');
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
