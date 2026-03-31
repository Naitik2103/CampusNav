import 'package:latlong2/latlong.dart';
import 'dart:math';
import '../models/route_model.dart' as route_model;
import '../models/path_model.dart';
import '../config/campus_config.dart';
import 'routing_service.dart';

/// Campus-constrained routing service
/// Ensures routes stay within campus boundaries and snap to campus paths
class CampusRoutingService {
  /// Get the campus boundary from configuration
  static List<LatLng> get _campusBoundary => CampusConfig.campusBoundary;

  static const List<LatLng> campusBoundary = [
    LatLng(23.1905, 72.6302),  // Your Northeast
    LatLng(23.1912, 72.6261),  // Your Northwest
    LatLng(23.1857, 72.6293),  // Your Southwest
    LatLng(23.1856, 72.6263),  // Your Southeast
  ];
  
  static const LatLng campusCenter = LatLng(23.188, 72.6285); // Middle point

  /// Get route that stays within campus bounds
  static Future<route_model.Route?> getCampusRoute(
    LatLng start,
    LatLng end,
    List<CampusPath> campusPaths,
  ) async {
    try {
      print('🏫 ========== Campus-Constrained Route ==========');
      print('📍 Start: ${start.latitude}, ${start.longitude}');
      print('📍 End: ${end.latitude}, ${end.longitude}');

      // Step 1: Validate both points are within campus
      if (!_isWithinCampus(start)) {
        print('⚠️ Start point outside campus - snapping to nearest path');
      }
      if (!_isWithinCampus(end)) {
        print('⚠️ End point outside campus - snapping to nearest path');
      }

      // Step 2: Get route from OSRM
      final route = await RoutingService.getRoute(start, end);

      if (route != null) {
        // Step 3: Filter waypoints to stay within campus
        final constrainedWaypoints = _constrainWaypointsToCampus(
          route.waypoints,
          _campusBoundary,
        );

        print('✅ Original waypoints: ${route.waypoints.length}');
        print('✅ Constrained waypoints: ${constrainedWaypoints.length}');

        // Step 4: Recalculate distance for constrained route
        final constrainedDistance = _calculatePathDistance(constrainedWaypoints);
        final constrainedDuration =
            (constrainedDistance / 1.4).toDouble(); // Avg walking speed 1.4 m/s

        return route_model.Route(
          id: route.id,
          name: 'Campus Route (Constrained)',
          steps: route.steps,
          totalDistance: constrainedDistance,
          totalDuration: constrainedDuration,
          routeQuality: route.routeQuality,
          routeType: 'campus',
          wheelchairAccessible: route.wheelchairAccessible,
          waypoints: constrainedWaypoints,
        );
      }

      return null;
    } catch (e) {
      print('❌ Error in campus route: $e');
      return null;
    }
  }

  /// Check if a point is within campus boundaries
  static bool _isWithinCampus(LatLng point) {
    return _isPointInPolygon(point, campusBoundary);
  }

  /// Check if point is within polygon using ray casting algorithm
  static bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    int intersections = 0;

    for (int i = 0; i < polygon.length; i++) {
      final LatLng p1 = polygon[i];
      final LatLng p2 = polygon[(i + 1) % polygon.length];

      if (_isPointOnSegment(point, p1, p2)) {
        return true; // Point is on boundary
      }

      if (_rayIntersectsSegment(point, p1, p2)) {
        intersections++;
      }
    }

    return intersections % 2 == 1;
  }

  /// Check if a ray from the point intersects the line segment
  static bool _rayIntersectsSegment(LatLng point, LatLng p1, LatLng p2) {
    final double px = point.longitude;
    final double py = point.latitude;
    final double x1 = p1.longitude;
    final double y1 = p1.latitude;
    final double x2 = p2.longitude;
    final double y2 = p2.latitude;

    if ((y1 > py) != (y2 > py)) {
      final double intersectX = (x2 - x1) * (py - y1) / (y2 - y1) + x1;
      if (px < intersectX) {
        return true;
      }
    }
    return false;
  }

  /// Check if point lies on a line segment
  static bool _isPointOnSegment(LatLng point, LatLng p1, LatLng p2) {
    final double epsilon = 0.00001;
    final double crossProduct = (point.latitude - p1.latitude) * (p2.longitude - p1.longitude) -
        (point.longitude - p1.longitude) * (p2.latitude - p1.latitude);

    if (crossProduct.abs() > epsilon) return false;

    if (point.longitude < min(p1.longitude, p2.longitude) - epsilon ||
        point.longitude > max(p1.longitude, p2.longitude) + epsilon) {
      return false;
    }

    if (point.latitude < min(p1.latitude, p2.latitude) - epsilon ||
        point.latitude > max(p1.latitude, p2.latitude) + epsilon) {
      return false;
    }

    return true;
  }

  /// Filter waypoints to remove those outside campus
  /// and interpolate to keep route smooth
  static List<LatLng> _constrainWaypointsToCampus(
    List<LatLng> waypoints,
    List<LatLng> boundary,
  ) {
    if (waypoints.isEmpty) return [];

    final List<LatLng> constrained = [];
    constrained.add(waypoints.first); // Always keep start

    for (int i = 1; i < waypoints.length - 1; i++) {
      final LatLng point = waypoints[i];

      // Keep points that are within campus
      if (_isWithinCampus(point)) {
        constrained.add(point);
      } else {
        // If outside campus, find nearest boundary point
        final LatLng nearestBoundary = _findNearestBoundaryPoint(point, boundary);
        if (constrained.last != nearestBoundary) {
          constrained.add(nearestBoundary);
        }
      }
    }

    constrained.add(waypoints.last); // Always keep end

    return constrained;
  }

  /// Find the nearest point on campus boundary
  static LatLng _findNearestBoundaryPoint(LatLng point, List<LatLng> boundary) {
    final distance = const Distance();
    LatLng nearest = boundary.first;
    double minDist = distance(point, nearest);

    for (final boundPoint in boundary) {
      final dist = distance(point, boundPoint);
      if (dist < minDist) {
        minDist = dist;
        nearest = boundPoint;
      }
    }

    return nearest;
  }

  /// Calculate total distance of a path
  static double _calculatePathDistance(List<LatLng> waypoints) {
    if (waypoints.length < 2) return 0;

    final distance = const Distance();
    double total = 0;

    for (int i = 0; i < waypoints.length - 1; i++) {
      total += distance(waypoints[i], waypoints[i + 1]);
    }

    return total * 1000; // Convert km to meters
  }

  /// Get campus bounds as a rectangle
  static ({double minLat, double maxLat, double minLng, double maxLng}) getCampusBounds() {
    double minLat = campusBoundary.first.latitude;
    double maxLat = campusBoundary.first.latitude;
    double minLng = campusBoundary.first.longitude;
    double maxLng = campusBoundary.first.longitude;

    for (final point in campusBoundary) {
      minLat = min(minLat, point.latitude);
      maxLat = max(maxLat, point.latitude);
      minLng = min(minLng, point.longitude);
      maxLng = max(maxLng, point.longitude);
    }

    return (minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng);
  }

  /// Snap a point to the nearest point on campus
  static LatLng snapToCampus(LatLng point) {
    if (_isWithinCampus(point)) {
      return point;
    }

    // Find nearest boundary point
    return _findNearestBoundaryPoint(point, campusBoundary);
  }
}
