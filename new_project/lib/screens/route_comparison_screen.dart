import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/path_model.dart';
import '../models/route_model.dart' as route_model;
import '../services/geojson_loader.dart';
import '../services/path_based_routing_service.dart';
import '../services/campus_routing_service.dart';
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
  static const Color _brandColor = Color(0xFF0B5FFF);

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
      final loadedPaths = await GeoJsonLoader.loadPaths(
        'assets/data/campus_paths.geojson',
      );
      final campusRoute = await PathBasedRoutingService.getPathBasedRoute(
        widget.startLocation,
        widget.endLocation,
        loadedPaths,
      );

      if (campusRoute != null && campusRoute.waypoints.length > 2) {
        setState(() {
          campusPaths = loadedPaths;
          routeComparison = null;
          selectedRoute = campusRoute;
          errorMessage = null;
          isLoading = false;
        });
        return;
      }

      final campusConstrainedRoute = await CampusRoutingService.getCampusRoute(
        widget.startLocation,
        widget.endLocation,
        loadedPaths,
      );

      if (campusConstrainedRoute != null &&
          campusConstrainedRoute.waypoints.length > 2) {
        setState(() {
          campusPaths = loadedPaths;
          routeComparison = null;
          selectedRoute = campusConstrainedRoute;
          errorMessage =
              'Using campus-constrained route because path graph route was unavailable.';
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
          errorMessage = null;
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
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: widget.startLocation,
              initialZoom: 17,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.new_project',
              ),
              PolylineLayer(
                polylines: routes.map((route) {
                  final isSelected = route == selectedRoute;
                  return Polyline(
                    points: route.waypoints,
                    color: isSelected ? _brandColor : const Color(0x99FFFFFF),
                    strokeWidth: isSelected ? 6 : 3,
                    borderColor: isSelected
                        ? const Color(0xFF0A3FA6)
                        : Colors.transparent,
                    borderStrokeWidth: isSelected ? 1.5 : 0,
                  );
                }).toList(),
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    width: 46,
                    height: 46,
                    point: widget.startLocation,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _brandColor,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [
                          BoxShadow(color: Color(0x400B5FFF), blurRadius: 10),
                        ],
                      ),
                      child: const Icon(
                        Icons.near_me_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                  Marker(
                    width: 48,
                    height: 48,
                    point: widget.endLocation,
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: Color(0xFFE11D48),
                      size: 44,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.center,
                colors: [Color(0x800B1220), Color(0x000B1220)],
              ),
            ),
          ),
          Positioned(
            top: topPadding + 12,
            left: 16,
            right: 16,
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xE61E293B),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'Route to ${widget.destinationName}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (errorMessage != null)
            Positioned(
              top: topPadding + 74,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xE6FFF7ED),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFCD9BD)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Color(0xFF9A3412),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        errorMessage!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF7C2D12),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 380),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFF),
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 24,
                    offset: Offset(0, -8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1D9E6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text(
                        'Available Routes',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${routes.length} option${routes.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
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
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFEAF1FF)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: isSelected
                                    ? _brandColor
                                    : const Color(0xFFDDE5F0),
                                width: isSelected ? 1.8 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    _getRouteIcon(route.routeType),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _getRouteTitle(route.routeType),
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                    ),
                                    _buildRatingStars(route.routeQuality),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    _metricBlock(
                                      'Distance',
                                      route.getFormattedTotalDistance(),
                                    ),
                                    _metricBlock(
                                      'Time',
                                      route.getFormattedTotalDuration(),
                                    ),
                                    _metricBlock(
                                      'Steps',
                                      '${route.steps.length}',
                                    ),
                                  ],
                                ),
                                if (route.wheelchairAccessible) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFDCFCE7),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.accessible_rounded,
                                          size: 14,
                                          color: Color(0xFF166534),
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Wheelchair Accessible',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF166534),
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                if (isSelected) ...[
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: () => _startNavigation(route),
                                      icon: const Icon(
                                        Icons.navigation_rounded,
                                      ),
                                      label: const Text('Start Navigation'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _brandColor,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricBlock(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
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
    return Icon(icon, color: _brandColor, size: 20);
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
