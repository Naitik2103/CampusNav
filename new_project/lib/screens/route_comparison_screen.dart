import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/path_model.dart';
import '../models/route_model.dart' as route_model;
import '../services/geojson_loader.dart';
import '../services/path_based_routing_service.dart';
import '../services/routing_service.dart';
import 'navigation_screen.dart';

class RouteComparisonScreen extends StatefulWidget {
  final LatLng startLocation;
  final LatLng endLocation;
  final String destinationName;

  const RouteComparisonScreen({
    Key? key,
    required this.startLocation,
    required this.endLocation,
    required this.destinationName,
  }) : super(key: key);

  @override
  State<RouteComparisonScreen> createState() => _RouteComparisonScreenState();
}

class _RouteComparisonScreenState extends State<RouteComparisonScreen> {
  route_model.RouteComparison? routeComparison;
  List<CampusPath> campusPaths = [];
  late route_model.Route selectedRoute;
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    try {
      final loadedPaths = await GeoJsonLoader.loadPaths('assets/data/campus_paths.geojson');
      final campusRoute = await PathBasedRoutingService.getPathBasedRoute(
        widget.startLocation,
        widget.endLocation,
        loadedPaths,
      );

      if (campusRoute != null) {
        setState(() {
          campusPaths = loadedPaths;
          routeComparison = null;
          selectedRoute = campusRoute;
          errorMessage = 'Using campus path routing.';
          isLoading = false;
        });
        return;
      }

      final routes = await RoutingService.getMultipleRoutes(
        widget.startLocation,
        widget.endLocation,
      );

      if (routes != null) {
        setState(() {
          campusPaths = loadedPaths;
          routeComparison = routes;
          selectedRoute = routes.shortestRoute;
          isLoading = false;
        });
      } else {
        setState(() {
          campusPaths = loadedPaths;
          errorMessage = 'Could not load routes. Using demo route.';
          selectedRoute = RoutingService.getDemoRoute(
            widget.startLocation,
            widget.endLocation,
          );
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = 'Error: ${e.toString()}';
        selectedRoute = RoutingService.getDemoRoute(
          widget.startLocation,
          widget.endLocation,
        );
        isLoading = false;
      });
    }
  }

  void _startNavigation(route_model.Route route) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NavigationScreen(
          startLocation: widget.startLocation,
          endLocation: widget.endLocation,
          destinationName: widget.destinationName,
          initialRoute: route,
          campusPaths: campusPaths,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Choose Route')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final routes = routeComparison?.getAllRoutes() ?? [selectedRoute];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Route'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Info banner
          if (errorMessage != null)
            Container(
              color: Colors.orange.shade100,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.info, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      errorMessage!,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          // Map showing all routes
          Expanded(
            flex: 2,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: widget.startLocation,
                initialZoom: 17,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.new_project',
                ),
                if (campusPaths.isNotEmpty)
                  PolylineLayer(
                    polylines: campusPaths
                        .map(
                          (path) => Polyline(
                            points: path.coordinates,
                            color: Colors.blue.withOpacity(0.45),
                            strokeWidth: 3,
                          ),
                        )
                        .toList(),
                  ),
                PolylineLayer(
                  polylines: routes.map((route) {
                    final isSelected = route == selectedRoute;
                    return Polyline(
                      points: route.waypoints,
                      color: isSelected ? Colors.blue : Colors.grey.shade400,
                      strokeWidth: isSelected ? 6 : 2,
                      borderColor: isSelected ? Colors.blue.shade900 : Colors.transparent,
                      borderStrokeWidth: isSelected ? 1 : 0,
                    );
                  }).toList(),
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      width: 40,
                      height: 40,
                      point: widget.startLocation,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.blue,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.navigation,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                    Marker(
                      width: 40,
                      height: 40,
                      point: widget.endLocation,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Route cards
          Expanded(
            flex: 2,
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: routes.length,
              itemBuilder: (context, index) {
                final route = routes[index];
                final isSelected = route == selectedRoute;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedRoute = route;
                    });
                  },
                  child: Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    elevation: isSelected ? 8 : 2,
                    color: isSelected ? Colors.blue.shade50 : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: isSelected
                          ? const BorderSide(color: Colors.blue, width: 2)
                          : BorderSide.none,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Route type header
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  _getRouteIcon(route.routeType),
                                  const SizedBox(width: 8),
                                  Text(
                                    _getRouteTitle(route.routeType),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              _buildRatingStars(route.routeQuality),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Distance and duration
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Distance',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      route.getFormattedTotalDistance(),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Time',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      route.getFormattedTotalDuration(),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Steps',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    Text(
                                      '${route.steps.length}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Accessibility badge
                          if (route.wheelchairAccessible)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.accessible,
                                    size: 14,
                                    color: Colors.green.shade700,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Wheelchair Accessible',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (isSelected) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () => _startNavigation(route),
                                icon: const Icon(Icons.navigation),
                                label: const Text('Start Navigation'),
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
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _getRouteIcon(String routeType) {
    IconData icon;
    switch (routeType) {
      case 'path_based':
        icon = Icons.alt_route;
        break;
      case 'shortest':
        icon = Icons.compress;
        break;
      case 'fastest':
        icon = Icons.flash_on;
        break;
      case 'safest':
        icon = Icons.shield;
        break;
      case 'scenic':
        icon = Icons.landscape;
        break;
      default:
        icon = Icons.route;
    }
    return Icon(icon, color: Colors.blue, size: 20);
  }

  String _getRouteTitle(String routeType) {
    switch (routeType) {
      case 'path_based':
        return 'Campus Path';
      case 'shortest':
        return 'Shortest';
      case 'fastest':
        return 'Fastest';
      case 'safest':
        return 'Safest';
      case 'scenic':
        return 'Scenic';
      default:
        return 'Route';
    }
  }

  Widget _buildRatingStars(int quality) {
    return Row(
      children: List.generate(5, (index) {
        return Icon(
          index < quality ? Icons.star : Icons.star_outline,
          size: 16,
          color: Colors.amber,
        );
      }),
    );
  }
}
