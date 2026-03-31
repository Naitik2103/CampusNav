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
              content: Text('Location permanently denied. Enable it in app settings.'),
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
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: _buildLocationSettings(),
    ).listen((Position position) {
      if (!mounted) return;

      // Ignore very noisy fixes once a reasonable position is already available.
      if (position.accuracy > 80 && _userLocation != null) {
        return;
      }

      final nextLocation = LatLng(position.latitude, position.longitude);
      setState(() {
        _userLocation = nextLocation;
      });

      if (!_hasCenteredOnUser) {
        _mapController.move(nextLocation, 18.0);
        _hasCenteredOnUser = true;
      }
    }, onError: (error) {
      print('Live location stream error: $error');
    });
  }

  Future<void> _getUserLocation() async {
    setState(() => _gettingLocation = true);
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 10),
      );
      
      if (mounted) {
        setState(() {
          _userLocation = LatLng(position.latitude, position.longitude);
          _gettingLocation = false;
        });
        
        // Automatically center on location after getting it
        _mapController.move(_userLocation!, 18.0);
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

  Future<void> _loadCampusData() async {
    try {
      print('\n===== LOADING CAMPUS DATA =====');
      final paths = await GeoJsonLoader.loadPaths('assets/data/campus_paths.geojson');
      print('✓ Loaded ${paths.length} paths from GeoJSON');
      for (var path in paths) {
        print('  - ${path.id}: "${path.name}" (${path.coordinates.length} coords, walkable: ${path.walkable})');
      }
      
      final places = await GeoJsonLoader.loadPlaces('assets/data/campus_places.geojson');
      print('✓ Loaded ${places.length} places from GeoJSON');
      for (var place in places) {
        print('  - ${place.id}: "${place.name}" at [${place.location.latitude.toStringAsFixed(6)}, ${place.location.longitude.toStringAsFixed(6)}]');
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
        _filteredPlaces = LocationSearchService.rankResults(query, _filteredPlaces);
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
    return Scaffold(
      appBar: AppBar(
        title: null,
        centerTitle: true,
        elevation: 0,
        toolbarHeight: 70,
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.layers, color: Colors.blue),
            onPressed: () => _showLayerPanel(context),
            tooltip: 'Toggle Layers',
          ),
        ],
        flexibleSpace: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          alignment: Alignment.bottomCenter,
          child: TextField(
            onChanged: _searchPlaces,
            decoration: InputDecoration(
              hintText: 'Search places...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        _searchPlaces('');
                      },
                    )
                  : null,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.grey),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.grey),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.blue, width: 2),
              ),
            ),
          ),
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
                    if (_activeRoutePath != null && _activeRoutePath!.isNotEmpty)
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
                          ..._filteredPlaces
                              .map(
                                (place) => Marker(
                                  point: place.location,
                                  width: 40,
                                  height: 40,
                                  child: GestureDetector(
                                    onTap: () => _showPlaceInfo(place),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: _getPlaceColor(place),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black26,
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        _getPlaceIcon(place),
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                              ,
                        ],
                      ),
                  ],
                ),
                // Legend
                Positioned(
                  bottom: 16,
                  left: 16,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Path Difficulty',
                          style: TextStyle(fontWeight: FontWeight.bold),
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
                    top: 90,
                    left: 16,
                    right: 16,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 8,
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
                              subtitle: Text(place.placeType),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.directions,
                                  color: Colors.blue,
                                ),
                                tooltip: 'Get Route',
                                onPressed: () => _navigateToRoutingScreen(place),
                              ),
                              onTap: () => _showPlaceInfo(place),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                // Location button - combined get location and center
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: FloatingActionButton(
                    onPressed: _gettingLocation ? null : () async {
                      if (_userLocation == null) {
                        await _getUserLocation();
                      } else {
                        _centerOnCampus();
                      }
                    },
                    tooltip: _userLocation == null ? 'Get My Location' : 'Center on My Location',
                    backgroundColor: _gettingLocation ? Colors.grey : Colors.blue,
                    child: _gettingLocation
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.my_location),
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
            width: 16,
            height: 4,
            color: color,
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
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
                      content: Text('Indoor map for ${place.name} coming soon!'),
                    ),
                  );
                },
                icon: const Icon(Icons.layers),
                label: const Text('View Indoor Map'),
              ),
            ],
            // Get Route button - only show if we have user location
            if (_userLocation != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _navigateToRoutingScreen(place);
                  },
                  icon: const Icon(Icons.directions),
                  label: const Text('Get Route'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
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
      print('Start: [${ start.latitude.toStringAsFixed(6)}, ${start.longitude.toStringAsFixed(6)}]');
      print('Destination: [${destination.latitude.toStringAsFixed(6)}, ${destination.longitude.toStringAsFixed(6)}]');
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
      
      final route = await PathBasedRoutingService.getPathBasedRoute(start, destination, _paths);
      
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
      final campusRoute = await CampusRoutingService.getCampusRoute(start, destination, _paths);
      
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading route: $e')),
      );
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
              onChanged: (_) => _toggleLayer('paths'),
            ),
            CheckboxListTile(
              title: const Text('Places & Buildings'),
              value: _visibleLayers.contains('places'),
              onChanged: (_) => _toggleLayer('places'),
            ),
          ],
        ),
      ),
    );
  }
}
