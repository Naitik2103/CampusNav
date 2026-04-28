import 'package:latlong2/latlong.dart';

/// Represents a single navigation step
class NavigationStep {
  final int index;
  final String instruction;
  final double distance;
  final double duration;
  final LatLng location;
  final String? turnType; // left, right, straight, uturn
  final double? bearing; // Direction in degrees

  NavigationStep({
    required this.index,
    required this.instruction,
    required this.distance,
    required this.duration,
    required this.location,
    this.turnType,
    this.bearing,
  });

  factory NavigationStep.fromJson(Map<String, dynamic> json, int index) {
    try {
      return NavigationStep(
        index: index,
        instruction: json['instruction'] ?? 'Continue',
        distance: (json['distance'] as num?)?.toDouble() ?? 0,
        duration: (json['duration'] as num?)?.toDouble() ?? 0,
        location: LatLng(0, 0), // Will be updated from coordinates
        turnType: _getTurnType(json['instruction'] ?? ''),
      );
    } catch (e) {
      return NavigationStep(
        index: index,
        instruction: 'Continue',
        distance: 0,
        duration: 0,
        location: LatLng(0, 0),
      );
    }
  }

  static String? _getTurnType(String instruction) {
    final lower = instruction.toLowerCase();
    if (lower.contains('left')) return 'left';
    if (lower.contains('right')) return 'right';
    if (lower.contains('back') || lower.contains('u-turn')) return 'uturn';
    return 'straight';
  }

  String getFormattedDistance() {
    if (distance < 1000) {
      return '${distance.toStringAsFixed(0)}m';
    }
    return '${(distance / 1000).toStringAsFixed(1)}km';
  }

  String getFormattedDuration() {
    if (duration < 60) {
      return '${duration.toStringAsFixed(0)}s';
    }
    return '${(duration / 60).toStringAsFixed(0)} min';
  }
}

/// Represents a complete route with multiple steps
class Route {
  final String id;
  final String name;
  final List<NavigationStep> steps;
  final double totalDistance;
  final double totalDuration;
  final int routeQuality; // 1-5 stars (1=shortest, 5=most accessible)
  final String routeType; // shortest, fastest, safest, scenic
  final bool wheelchairAccessible;
  final List<LatLng> waypoints;

  Route({
    required this.id,
    required this.name,
    required this.steps,
    required this.totalDistance,
    required this.totalDuration,
    required this.routeQuality,
    required this.routeType,
    required this.wheelchairAccessible,
    required this.waypoints,
  });

  String getFormattedTotalDistance() {
    if (totalDistance < 1000) {
      return '${totalDistance.toStringAsFixed(0)}m';
    }
    return '${(totalDistance / 1000).toStringAsFixed(2)}km';
  }

  String getFormattedTotalDuration() {
    final minutes = totalDuration ~/ 60;
    final hours = minutes ~/ 60;
    
    if (hours > 0) {
      return '${hours}h ${minutes % 60}m';
    }
    return '${minutes}m';
  }

  factory Route.fromJson(Map<String, dynamic> json, String routeType) {
    try {
      final features = json['features'] as List<dynamic>? ?? [];
      if (features.isEmpty) {
        return _createEmptyRoute(routeType);
      }

      final feature = features[0] as Map<String, dynamic>;
      final properties = feature['properties'] as Map<String, dynamic>? ?? {};
      final geometry = feature['geometry'] as Map<String, dynamic>? ?? {};
      
      final segments = properties['segments'] as List<dynamic>? ?? [];
      final List<NavigationStep> steps = [];
      int stepIndex = 0;

      for (var segment in segments) {
        final segmentSteps = segment['steps'] as List<dynamic>? ?? [];
        for (var stepJson in segmentSteps) {
          steps.add(NavigationStep.fromJson(stepJson as Map<String, dynamic>, stepIndex));
          stepIndex++;
        }
      }

      final totalDistance = (properties['summary']?[0]?['distance'] as num?)?.toDouble() ?? 0;
      final totalDuration = (properties['summary']?[0]?['duration'] as num?)?.toDouble() ?? 0;

      // Extract waypoints from coordinates
      final coordinates = geometry['coordinates'] as List<dynamic>? ?? [];
      final waypoints = coordinates
          .map((coord) => LatLng(
                (coord[1] as num).toDouble(),
                (coord[0] as num).toDouble(),
              ))
          .toList();

      final wheelchairAccessible = routeType != 'hiking' && 
          (totalDistance / totalDuration < 2); // Reasonable pace

      return Route(
        id: '${routeType}_${DateTime.now().millisecondsSinceEpoch}',
        name: _getRouteName(routeType),
        steps: steps,
        totalDistance: totalDistance,
        totalDuration: totalDuration,
        routeQuality: _getRouteQuality(routeType),
        routeType: routeType,
        wheelchairAccessible: wheelchairAccessible,
        waypoints: waypoints,
      );
    } catch (e) {
      return _createEmptyRoute(routeType);
    }
  }

  static Route _createEmptyRoute(String routeType) {
    return Route(
      id: '${routeType}_empty',
      name: _getRouteName(routeType),
      steps: [],
      totalDistance: 0,
      totalDuration: 0,
      routeQuality: 3,
      routeType: routeType,
      wheelchairAccessible: false,
      waypoints: [],
    );
  }

  static String _getRouteName(String type) {
    switch (type) {
      case 'shortest':
        return 'Shortest Route';
      case 'fastest':
        return 'Fastest Route';
      case 'safest':
        return 'Safest Route';
      case 'scenic':
        return 'Scenic Route';
      default:
        return 'Route';
    }
  }

  static int _getRouteQuality(String type) {
    switch (type) {
      case 'shortest':
        return 2;
      case 'fastest':
        return 3;
      case 'safest':
        return 5;
      case 'scenic':
        return 4;
      default:
        return 3;
    }
  }
}

/// Route comparison for showing multiple options
class RouteComparison {
  final Route shortestRoute;
  final Route fastestRoute;
  final Route? safestRoute;
  final Route? scenicRoute;

  RouteComparison({
    required this.shortestRoute,
    required this.fastestRoute,
    this.safestRoute,
    this.scenicRoute,
  });

  List<Route> getAllRoutes() {
    return [
      shortestRoute,
      fastestRoute,
      ?safestRoute,
      ?scenicRoute,
    ];
  }
}
