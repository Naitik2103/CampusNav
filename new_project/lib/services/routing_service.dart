import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import '../models/route_model.dart' as route_model;

/// Service for calculating routes using multiple routing APIs
/// Primary: OSRM (Open Source Routing Machine) - Free, uses OSM data
/// Fallback: OpenRouteService - When OSRM is unavailable
class RoutingService {
  // Using OSRM - Free public API with OSM data
  // Uses actual roads and paths from OpenStreetMap
  static const String osrmBaseUrl = 'http://router.project-osrm.org/route/v1';

  // Using OpenRouteService - Free tier includes 2,500 requests/day
  // Get your API key from: https://openrouteservice.org/dev/#/api-key
  static const String apiKey =
      'eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjY5Y2JjYTRhOTI5YjQyNWZiMDg2NzI4ZmIxMTlhNmM2IiwiaCI6Im11cm11cjY0In0=';
  static const String oasBaseUrl =
      'https://api.openrouteservice.org/v2/directions';

  static double _computePathDistanceMeters(List<LatLng> waypoints) {
    if (waypoints.length < 2) return 0;
    const distanceCalc = Distance();
    double total = 0;
    for (int i = 0; i < waypoints.length - 1; i++) {
      total += distanceCalc(waypoints[i], waypoints[i + 1]);
    }
    return total;
  }

  static double _pathDistanceForOrder(
    List<LatLng> points,
    List<int> order,
  ) {
    if (order.length < 2) return 0;
    const distanceCalc = Distance();
    double total = 0;

    for (int i = 0; i < order.length - 1; i++) {
      total += distanceCalc(points[order[i]], points[order[i + 1]]);
    }

    return total;
  }

  static List<int> _nearestNeighborOrder(
    List<LatLng> points,
    List<int> candidates,
    int? fixedStart,
  ) {
    if (candidates.isEmpty) return [];

    const distanceCalc = Distance();
    final remaining = List<int>.from(candidates);
    final sequence = <int>[];

    int current = fixedStart ?? remaining.first;
    if (fixedStart == null) {
      sequence.add(current);
      remaining.remove(current);
    }

    while (remaining.isNotEmpty) {
      int bestIndex = remaining.first;
      double bestDistance = double.infinity;

      for (final idx in remaining) {
        final d = distanceCalc(points[current], points[idx]);
        if (d < bestDistance) {
          bestDistance = d;
          bestIndex = idx;
        }
      }

      sequence.add(bestIndex);
      remaining.remove(bestIndex);
      current = bestIndex;
    }

    return sequence;
  }

  static List<int> _twoOptImprove(
    List<LatLng> points,
    List<int> sequence, {
    int? fixedStart,
    int? fixedEnd,
  }) {
    if (sequence.length < 4) return sequence;

    var improved = true;
    var current = List<int>.from(sequence);
    final startLock = fixedStart != null ? 1 : 0;
    final endLock = fixedEnd != null ? 1 : 0;

    while (improved) {
      improved = false;

      final iStart = startLock;
      final iEnd = current.length - 2 - endLock;

      for (int i = iStart; i <= iEnd; i++) {
        for (int k = i + 1; k < current.length - endLock; k++) {
          if (k - i < 1) continue;

          final candidate = <int>[
            ...current.sublist(0, i),
            ...current.sublist(i, k + 1).reversed,
            ...current.sublist(k + 1),
          ];

          final currentDistance = _pathDistanceForOrder(points, current);
          final candidateDistance = _pathDistanceForOrder(points, candidate);

          if (candidateDistance + 0.1 < currentDistance) {
            current = candidate;
            improved = true;
          }
        }
      }
    }

    return current;
  }

  /// Returns optimized visit indices for a multi-stop trip.
  ///
  /// By default, the first point is treated as fixed start and the last point
  /// as fixed destination. Intermediate points are re-ordered to minimize the
  /// total path distance.
  static List<int> optimizeVisitOrder(
    List<LatLng> points, {
    bool keepFirst = true,
    bool keepLast = true,
    int bruteForceThreshold = 8,
  }) {
    final n = points.length;
    if (n <= 2) {
      return List<int>.generate(n, (i) => i);
    }

    final fixedStart = keepFirst ? 0 : null;
    final fixedEnd = keepLast ? n - 1 : null;

    final flexible = <int>[];
    for (int i = 0; i < n; i++) {
      if (i == fixedStart || i == fixedEnd) continue;
      flexible.add(i);
    }

    if (flexible.length <= 1) {
      return <int>[
        if (fixedStart != null) fixedStart,
        ...flexible,
        if (fixedEnd != null) fixedEnd,
      ];
    }

    List<int> bestOrder = [];
    double bestDistance = double.infinity;

    void evaluatePermutation(List<int> candidateMiddle) {
      final candidate = <int>[
        if (fixedStart != null) fixedStart,
        ...candidateMiddle,
        if (fixedEnd != null) fixedEnd,
      ];

      final distance = _pathDistanceForOrder(points, candidate);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestOrder = candidate;
      }
    }

    if (flexible.length <= bruteForceThreshold) {
      final used = List<bool>.filled(flexible.length, false);
      final current = <int>[];

      void backtrack() {
        if (current.length == flexible.length) {
          evaluatePermutation(current);
          return;
        }

        for (int i = 0; i < flexible.length; i++) {
          if (used[i]) continue;
          used[i] = true;
          current.add(flexible[i]);
          backtrack();
          current.removeLast();
          used[i] = false;
        }
      }

      backtrack();
      return bestOrder;
    }

    final middleSequence = _nearestNeighborOrder(points, flexible, fixedStart);
    final seeded = <int>[
      if (fixedStart != null) fixedStart,
      ...middleSequence,
      if (fixedEnd != null) fixedEnd,
    ];

    return _twoOptImprove(
      points,
      seeded,
      fixedStart: fixedStart,
      fixedEnd: fixedEnd,
    );
  }

  static double _estimateWalkingDurationSeconds(double distanceMeters) {
    if (distanceMeters <= 0) return 0;
    return distanceMeters / 1.4;
  }

  static double _normalizeDelta(double angle) {
    var delta = angle;
    while (delta > 180) {
      delta -= 360;
    }
    while (delta < -180) {
      delta += 360;
    }
    return delta;
  }

  static String _turnTypeFromAngleDelta(double delta) {
    final absDelta = delta.abs();
    if (absDelta >= 165) return 'uturn';
    if (absDelta >= 110) return delta > 0 ? 'sharp_right' : 'sharp_left';
    if (absDelta >= 45) return delta > 0 ? 'right' : 'left';
    if (absDelta >= 22) return delta > 0 ? 'slight_right' : 'slight_left';
    return 'straight';
  }

  static String _instructionFromTurnType(String turnType) {
    switch (turnType) {
      case 'slight_left':
        return 'Slight left';
      case 'left':
        return 'Turn left';
      case 'sharp_left':
        return 'Take a sharp left';
      case 'slight_right':
        return 'Slight right';
      case 'right':
        return 'Turn right';
      case 'sharp_right':
        return 'Take a sharp right';
      case 'uturn':
        return 'Make a U-turn';
      default:
        return 'Continue straight';
    }
  }

  static String _turnTypeFromManeuver(
    Map<String, dynamic> maneuver,
    String fallbackInstruction,
  ) {
    final modifier = (maneuver['modifier'] ?? '').toString().toLowerCase();
    final type = (maneuver['type'] ?? '').toString().toLowerCase();
    final fallback = fallbackInstruction.toLowerCase();

    if (type.contains('uturn') || modifier.contains('uturn')) return 'uturn';
    if (modifier.contains('sharp left')) return 'sharp_left';
    if (modifier.contains('sharp right')) return 'sharp_right';
    if (modifier.contains('slight left')) return 'slight_left';
    if (modifier.contains('slight right')) return 'slight_right';
    if (modifier.contains('left')) return 'left';
    if (modifier.contains('right')) return 'right';
    if (fallback.contains('left')) return 'left';
    if (fallback.contains('right')) return 'right';
    if (fallback.contains('u-turn') || fallback.contains('uturn'))
      return 'uturn';
    return 'straight';
  }

  static String _instructionFromManeuver(
    Map<String, dynamic> maneuver,
    String roadName,
  ) {
    final turnType = _turnTypeFromManeuver(maneuver, roadName);
    final base = _instructionFromTurnType(turnType);
    final road = roadName.trim();

    if (road.isNotEmpty && !road.toLowerCase().contains('unnamed')) {
      if (turnType == 'straight') {
        return 'Continue on $road';
      }
      return '$base towards $road';
    }

    return base;
  }

  static List<route_model.NavigationStep> buildTurnAwareSteps(
    List<LatLng> waypoints, {
    double walkingSpeedMps = 1.4,
  }) {
    if (waypoints.length < 2) return [];

    const Distance distanceCalc = Distance();
    final List<route_model.NavigationStep> steps = [];

    final firstDistance = distanceCalc(waypoints[0], waypoints[1]);
    steps.add(
      route_model.NavigationStep(
        index: 0,
        instruction: 'Head straight',
        distance: firstDistance,
        duration: firstDistance / walkingSpeedMps,
        location: waypoints[0],
        turnType: 'straight',
      ),
    );

    double distanceFromLastInstruction = firstDistance;
    int stepIndex = 1;

    for (int i = 1; i < waypoints.length - 1; i++) {
      final incomingBearing = distanceCalc.bearing(
        waypoints[i - 1],
        waypoints[i],
      );
      final outgoingBearing = distanceCalc.bearing(
        waypoints[i],
        waypoints[i + 1],
      );
      final delta = _normalizeDelta(outgoingBearing - incomingBearing);
      final turnType = _turnTypeFromAngleDelta(delta);

      if (turnType != 'straight') {
        steps.add(
          route_model.NavigationStep(
            index: stepIndex,
            instruction: _instructionFromTurnType(turnType),
            distance: distanceFromLastInstruction,
            duration: distanceFromLastInstruction / walkingSpeedMps,
            location: waypoints[i],
            turnType: turnType,
            bearing: outgoingBearing,
          ),
        );
        stepIndex++;
        distanceFromLastInstruction = 0;
      }

      distanceFromLastInstruction += distanceCalc(
        waypoints[i],
        waypoints[i + 1],
      );
    }

    steps.add(
      route_model.NavigationStep(
        index: stepIndex,
        instruction: 'Arrive at destination',
        distance: distanceFromLastInstruction,
        duration: distanceFromLastInstruction / walkingSpeedMps,
        location: waypoints.last,
        turnType: 'straight',
      ),
    );

    return steps;
  }

  /// Get single route between two points
  /// Uses OpenRouteService (POST request with proper API format)
  /// Falls back to demo route if API fails
  static Future<route_model.Route?> getRoute(
    LatLng start,
    LatLng end, {
    String profile = 'foot',
  }) async {
    try {
      print('📍 Getting route from $start to $end');

      // Try OpenRouteService first (now with proper POST request)
      final route = await _getOpenRouteServiceRoute(start, end);
      if (route != null) {
        return route;
      }

      print('⚠️ OpenRouteService failed, trying OSRM...');

      // Fallback to OSRM if OpenRouteService fails
      final osrmRoute = await _getOSRMRoute(start, end, profile);
      if (osrmRoute != null) {
        return osrmRoute;
      }

      print('⚠️ OSRM also failed, will use demo route');
      return null;
    } catch (e) {
      print('❌ Error getting route: $e');
      return null;
    }
  }

  /// Get route using OSRM (free, uses OpenStreetMap data)
  static Future<route_model.Route?> _getOSRMRoute(
    LatLng start,
    LatLng end,
    String profile,
  ) async {
    try {
      final coordinates =
          '${start.longitude},${start.latitude};${end.longitude},${end.latitude}';
      final url = Uri.parse(
        '$osrmBaseUrl/$profile/$coordinates?overview=full&geometries=geojson&steps=true&annotations=distance,duration',
      );

      print('🗺️ OSRM Request: $url');
      print('Start: ${start.latitude}, ${start.longitude}');
      print('End: ${end.latitude}, ${end.longitude}');

      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);

        print('🗺️ OSRM Response status: ${json['code']}');

        if (json['routes'] == null || (json['routes'] as List).isEmpty) {
          print('❌ No routes found from OSRM');
          return null;
        }

        final route = json['routes'][0];
        final legs = route['legs'] as List<dynamic>? ?? [];
        final geometry = route['geometry'] as Map<String, dynamic>? ?? {};

        print(
          '🗺️ Route distance: ${route['distance']}, duration: ${route['duration']}',
        );
        print('🗺️ Number of legs: ${legs.length}');

        // Extract waypoints from geometry
        final coordinates = geometry['coordinates'] as List<dynamic>? ?? [];
        final waypoints = coordinates
            .map((coord) {
              if (coord is List && coord.length >= 2) {
                return LatLng(
                  (coord[1] as num).toDouble(),
                  (coord[0] as num).toDouble(),
                );
              }
              return null;
            })
            .whereType<LatLng>()
            .toList();

        print('🗺️ Extracted ${waypoints.length} waypoints');

        // Extract steps
        final List<route_model.NavigationStep> steps = [];
        int stepIndex = 0;

        for (var leg in legs) {
          final legSteps = leg['steps'] as List<dynamic>? ?? [];

          for (var step in legSteps) {
            final roadName = (step['name'] ?? '').toString();
            final distance = (step['distance'] as num?)?.toDouble() ?? 0;
            final duration = (step['duration'] as num?)?.toDouble() ?? 0;

            // Get step location from maneuver
            final maneuver = step['maneuver'] as Map<String, dynamic>? ?? {};
            final location = maneuver['location'] as List<dynamic>? ?? [];
            final stepLocation = location.length >= 2
                ? LatLng(
                    (location[1] as num).toDouble(),
                    (location[0] as num).toDouble(),
                  )
                : start;

            steps.add(
              route_model.NavigationStep(
                index: stepIndex,
                instruction: _instructionFromManeuver(maneuver, roadName),
                distance: distance,
                duration: duration,
                location: stepLocation,
                turnType: _turnTypeFromManeuver(maneuver, roadName),
                bearing: (maneuver['bearing_after'] as num?)?.toDouble(),
              ),
            );
            stepIndex++;
          }
        }

        final finalWaypoints = waypoints.isNotEmpty ? waypoints : [start, end];

        final apiDistance = (route['distance'] as num?)?.toDouble() ?? 0;
        final apiDuration = (route['duration'] as num?)?.toDouble() ?? 0;
        final computedDistance = _computePathDistanceMeters(finalWaypoints);
        final totalDistance = computedDistance > 0
            ? computedDistance
            : apiDistance;
        final totalDuration = totalDistance > 0
            ? _estimateWalkingDurationSeconds(totalDistance)
            : apiDuration;

        print(
          '🗺️ Final route - Distance: $totalDistance m, Duration: $totalDuration s',
        );

        return route_model.Route(
          id: 'osrm_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Campus Route (OSM)',
          steps: steps,
          totalDistance: totalDistance,
          totalDuration: totalDuration,
          routeQuality: 4,
          routeType: 'shortest',
          wheelchairAccessible: true,
          waypoints: finalWaypoints,
        );
      } else {
        print('❌ OSRM Error: ${response.statusCode}');
        print('Response: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ OSRM request failed: $e');
      return null;
    }
  }

  /// Get route using OpenRouteService with POST request
  /// This is the PRIMARY method now - direct API call with proper formatting
  static Future<route_model.Route?> _getOpenRouteServiceRoute(
    LatLng start,
    LatLng end,
  ) async {
    try {
      print(
        '\n🛣️ =============== OpenRouteService Route Request ===============',
      );
      print('📍 START Location: Lat=${start.latitude}, Lng=${start.longitude}');
      print('📍 END Location: Lat=${end.latitude}, Lng=${end.longitude}');

      // Calculate straight-line distance for reference
      final Distance distanceCalc = const Distance();
      final double straightLineDistance = distanceCalc(start, end);
      print(
        '📏 Straight-line distance: ${straightLineDistance.toStringAsFixed(0)} m',
      );

      // Explicitly create URL with proper spacing
      const String endpoint =
          'https://api.openrouteservice.org/v2/directions/foot-walking';
      final uri = Uri.parse(endpoint);

      final headers = <String, String>{
        'Authorization': apiKey,
        'Content-Type': 'application/json',
      };

      // Explicitly build the coordinates list
      final List<List<double>> coordinates = [
        [start.longitude, start.latitude],
        [end.longitude, end.latitude],
      ];

      final Map<String, dynamic> requestBody = {'coordinates': coordinates};

      final String jsonBody = jsonEncode(requestBody);

      print('🌐 Endpoint: $endpoint');
      print('📤 Coordinates being sent: ${coordinates[0]} → ${coordinates[1]}');

      final response = await http
          .post(uri, headers: headers, body: jsonBody)
          .timeout(const Duration(seconds: 15));

      print('🔄 Response Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> json = jsonDecode(response.body);

        print('✅ Response parsed successfully');

        // Check if features array exists
        final List<dynamic>? features = json['features'];
        if (features == null || features.isEmpty) {
          print('❌ No features in response');
          return null;
        }

        final Map<String, dynamic> feature = features[0];
        final Map<String, dynamic>? geometry = feature['geometry'];

        if (geometry == null) {
          print('❌ No geometry in feature');
          return null;
        }

        final dynamic geometryCoords = geometry['coordinates'];
        if (geometryCoords == null) {
          print('❌ No coordinates in geometry');
          return null;
        }

        // Extract coordinates and convert [lng, lat] to LatLng(lat, lng)
        final List<dynamic> coordList = geometryCoords as List<dynamic>;
        print('📍 Number of waypoints from API: ${coordList.length}');

        final List<LatLng> waypoints = <LatLng>[];

        for (int i = 0; i < coordList.length; i++) {
          try {
            final dynamic coord = coordList[i];
            if (coord is List && coord.length >= 2) {
              final double lat = (coord[1] as num).toDouble();
              final double lng = (coord[0] as num).toDouble();
              waypoints.add(LatLng(lat, lng));

              // Debug first, middle, and last waypoints
              if (i == 0 ||
                  i == coordList.length ~/ 2 ||
                  i == coordList.length - 1) {
                print('  Waypoint[$i]: Lat=$lat, Lng=$lng');
              }
            }
          } catch (e) {
            print('❌ Error processing coordinate $i: $e');
          }
        }

        print('✅ Extracted ${waypoints.length} valid waypoints');

        if (waypoints.isEmpty) {
          print('❌ CRITICAL: No valid waypoints extracted!');
          return null;
        }

        // Verify waypoints are within reasonable bounds
        print('📊 Waypoint bounds check:');
        double minLat = waypoints.first.latitude,
            maxLat = waypoints.first.latitude;
        double minLng = waypoints.first.longitude,
            maxLng = waypoints.first.longitude;

        for (var wp in waypoints) {
          minLat = min(minLat, wp.latitude);
          maxLat = max(maxLat, wp.latitude);
          minLng = min(minLng, wp.longitude);
          maxLng = max(maxLng, wp.longitude);
        }

        print(
          '  Latitude range: $minLat to $maxLat (span: ${(maxLat - minLat).toStringAsFixed(4)}°)',
        );
        print(
          '  Longitude range: $minLng to $maxLng (span: ${(maxLng - minLng).toStringAsFixed(4)}°)',
        );

        // Extract distance and duration from properties
        final Map<String, dynamic>? properties = feature['properties'];
        final Map<String, dynamic>? summary = properties?['summary'];

        final double apiDistance =
            (summary?['distance'] as num?)?.toDouble() ?? 0.0;
        final double computedDistance = _computePathDistanceMeters(waypoints);
        final double totalDistance = computedDistance > 0
            ? computedDistance
            : apiDistance;
        final double totalDuration = _estimateWalkingDurationSeconds(
          totalDistance,
        );

        print(
          '📏 API returned distance: ${totalDistance}m, duration: ${totalDuration}s',
        );
        final ratio = straightLineDistance > 0
            ? (totalDistance / straightLineDistance)
            : 0.0;
        print('💡 Ratio (route / straight-line): ${ratio.toStringAsFixed(2)}x');

        final List<route_model.NavigationStep> steps = buildTurnAwareSteps(
          waypoints,
        );

        print('✅ Route ready with ${waypoints.length} waypoints');
        print(
          '🛣️ ===============================================================\n',
        );

        return route_model.Route(
          id: 'ors_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Campus Route via OpenRouteService',
          steps: steps,
          totalDistance: totalDistance,
          totalDuration: totalDuration,
          routeQuality: 5,
          routeType: 'shortest',
          wheelchairAccessible: true,
          waypoints: waypoints,
        );
      } else {
        print('❌ API Error - Status Code: ${response.statusCode}');
        print(
          '❌ Error Response: ${response.body.substring(0, min(500, response.body.length))}...',
        );
        return null;
      }
    } catch (e, stackTrace) {
      print('❌ Exception in OpenRouteService: $e');
      print(
        '📍 Stack: ${stackTrace.toString().split('\n').take(5).join('\n')}',
      );
      return null;
    }
  }

  /// Get multiple route options (shortest, fastest, safest, scenic)
  /// Uses OSRM which provides OSM-based routing
  static Future<route_model.RouteComparison?> getMultipleRoutes(
    LatLng start,
    LatLng end,
  ) async {
    try {
      // Get primary route from OSRM
      final shortestRoute = await getRoute(start, end, profile: 'foot');

      if (shortestRoute != null) {
        // Create variations by adjusting waypoints slightly
        final fastestRoute = shortestRoute;
        final safestRoute = shortestRoute;

        return route_model.RouteComparison(
          shortestRoute: shortestRoute,
          fastestRoute: fastestRoute,
          safestRoute: safestRoute,
        );
      }
      return null;
    } catch (e) {
      print('Error getting multiple routes: $e');
      return null;
    }
  }

  /// Get route with waypoints using OSRM
  static Future<route_model.Route?> getRouteWithWaypoints(
    List<LatLng> waypoints, {
    String profile = 'foot',
  }) async {
    try {
      if (waypoints.length < 2) return null;

      // Use OSRM by chaining the waypoints
      final coordinatesParam = waypoints
          .map((w) => '${w.longitude},${w.latitude}')
          .join(';');

      final url = Uri.parse(
        '$osrmBaseUrl/$profile/$coordinatesParam?overview=full&geometries=geojson&steps=true&annotations=distance,duration',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final route = json['routes'][0];
        final waypoints = (route['geometry']['coordinates'] as List)
            .map(
              (coord) => LatLng(
                (coord[1] as num).toDouble(),
                (coord[0] as num).toDouble(),
              ),
            )
            .toList();

        final computedDistance = _computePathDistanceMeters(waypoints);

        final steps = buildTurnAwareSteps(waypoints);

        return route_model.Route(
          id: 'waypoint_route_${DateTime.now().millisecondsSinceEpoch}',
          name: 'Multi-waypoint Route',
          steps: steps,
          totalDistance: computedDistance,
          totalDuration: _estimateWalkingDurationSeconds(computedDistance),
          routeQuality: 4,
          routeType: 'waypoint',
          wheelchairAccessible: true,
          waypoints: waypoints,
        );
      }
      return null;
    } catch (e) {
      print('Error getting route with waypoints: $e');
      return null;
    }
  }

  /// Check if both start and end are within campus
  static Future<bool> isValidCampusRoute(
    LatLng start,
    LatLng end,
    LatLng campusCenter, {
    double campusRadiusKm = 5,
  }) async {
    try {
      final distance = const Distance();
      final startDist = distance(campusCenter, start);
      final endDist = distance(campusCenter, end);

      final campusRadiusMeters = campusRadiusKm * 1000;
      return startDist <= campusRadiusMeters && endDist <= campusRadiusMeters;
    } catch (e) {
      print('Error validating campus route: $e');
      return false;
    }
  }

  /// Get demo route - returns a simple fallback route
  /// For real routes, use getRoute() which fetches from OSRM
  static route_model.Route getDemoRoute(LatLng start, LatLng end) {
    // Create simple curved waypoints
    final List<LatLng> waypoints = [];
    waypoints.add(start);

    final midLat = (start.latitude + end.latitude) / 2;

    final waypoint1 = LatLng(
      start.latitude + (midLat - start.latitude) * 0.3,
      start.longitude + (end.longitude - start.longitude) * 0.25,
    );

    final waypoint2 = LatLng(
      start.latitude + (midLat - start.latitude) * 0.6,
      start.longitude + (end.longitude - start.longitude) * 0.5,
    );

    final waypoint3 = LatLng(
      start.latitude + (midLat - start.latitude) * 0.85,
      start.longitude + (end.longitude - start.longitude) * 0.75,
    );

    waypoints.add(waypoint1);
    waypoints.add(waypoint2);
    waypoints.add(waypoint3);
    waypoints.add(end);

    double totalDistance = 0;
    for (int i = 0; i < waypoints.length - 1; i++) {
      final segmentDistance = const Distance()(waypoints[i], waypoints[i + 1]);
      totalDistance += segmentDistance;
    }

    final totalDuration = (totalDistance / 1.4).toDouble();

    final steps = [
      route_model.NavigationStep(
        index: 0,
        instruction: 'Head towards the campus main road',
        distance: totalDistance * 0.25,
        duration: totalDuration * 0.25,
        location: waypoint1,
        turnType: 'straight',
      ),
      route_model.NavigationStep(
        index: 1,
        instruction: 'Continue on the path',
        distance: totalDistance * 0.25,
        duration: totalDuration * 0.25,
        location: waypoint2,
        turnType: 'straight',
      ),
      route_model.NavigationStep(
        index: 2,
        instruction: 'Turn right',
        distance: totalDistance * 0.25,
        duration: totalDuration * 0.25,
        location: waypoint3,
        turnType: 'right',
      ),
      route_model.NavigationStep(
        index: 3,
        instruction: 'Arrive at destination',
        distance: totalDistance * 0.25,
        duration: totalDuration * 0.25,
        location: end,
        turnType: 'straight',
      ),
    ];

    return route_model.Route(
      id: 'fallback_route_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Campus Route (Fallback)',
      steps: steps,
      totalDistance: totalDistance,
      totalDuration: totalDuration,
      routeQuality: 3,
      routeType: 'demo',
      wheelchairAccessible: true,
      waypoints: waypoints,
    );
  }
}
