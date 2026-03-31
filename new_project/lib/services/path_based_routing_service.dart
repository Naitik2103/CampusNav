import 'package:latlong2/latlong.dart';
import '../models/route_model.dart' as route_model;
import '../models/path_model.dart';

/// Node representing an intersection on campus
class PathNode {
  final LatLng location;
  final String id;
  final List<PathNode> neighbors = [];
  final List<double> edgeDistances = [];

  PathNode({required this.location, required this.id});

  void addNeighbor(PathNode neighbor, double distance) {
    if (!neighbors.contains(neighbor)) {
      neighbors.add(neighbor);
      edgeDistances.add(distance);
    }
  }

  @override
  String toString() => 'PathNode($id at ${location.latitude}, ${location.longitude})';
}

/// Path-based routing service using campus paths from GeoJSON
/// Builds a graph from campus paths and finds optimal routes through them
class PathBasedRoutingService {
  static const double _nodeMergeToleranceMeters = 8.0;

  static String _keyForLocation(LatLng point) {
    return '${point.latitude.toStringAsFixed(6)},${point.longitude.toStringAsFixed(6)}';
  }

  static String _findOrCreateNodeKey(
    LatLng point,
    Map<String, PathNode> nodes,
    Distance distanceCalc,
  ) {
    for (final entry in nodes.entries) {
      if (distanceCalc(point, entry.value.location) <= _nodeMergeToleranceMeters) {
        return entry.key;
      }
    }

    final key = _keyForLocation(point);
    nodes[key] = PathNode(location: point, id: 'node_${nodes.length}');
    return key;
  }

  static void _connectNodes(Map<String, PathNode> nodes, String aKey, String bKey, double distanceKm) {
    final a = nodes[aKey]!;
    final b = nodes[bKey]!;
    a.addNeighbor(b, distanceKm);
    b.addNeighbor(a, distanceKm);
  }

  /// Build a graph from campus paths
  static Map<String, PathNode> _buildPathGraph(List<CampusPath> paths) {
    final Map<String, PathNode> nodes = {};
    const Distance distanceCalc = Distance();

    print('📦 Loading ${paths.length} campus paths...');
    for (final path in paths) {
      print('   Path: ${path.id} (walkable: ${path.walkable}, coords: ${path.coordinates.length})');
      if (!path.walkable) {
        print('      ⊘ Skipped: not walkable');
        continue;
      }
      if (path.coordinates.length < 2) {
        print('      ⊘ Skipped: less than 2 coordinates');
        continue;
      }

      // Build a full graph by linking every consecutive path vertex.
      // This preserves bends/intersections and avoids over-simplified routing.
      for (int i = 0; i < path.coordinates.length - 1; i++) {
        final a = path.coordinates[i];
        final b = path.coordinates[i + 1];

        final aKey = _findOrCreateNodeKey(a, nodes, distanceCalc);
        final bKey = _findOrCreateNodeKey(b, nodes, distanceCalc);
        final segmentDistance = distanceCalc(a, b);

        _connectNodes(nodes, aKey, bKey, segmentDistance);
      }
    }

    print('🗺️ Built path graph with ${nodes.length} nodes');
    for (final entry in nodes.entries) {
      final node = entry.value;
      print('   ${node.id}: [${node.location.latitude.toStringAsFixed(6)}, ${node.location.longitude.toStringAsFixed(6)}] (${node.neighbors.length} connections)');
    }
    return nodes;
  }

  /// Find nearest path node to a location using snapping
  static PathNode? _findNearestNode(LatLng location, Map<String, PathNode> nodes) {
    if (nodes.isEmpty) return null;

    const Distance distanceCalc = Distance();
    PathNode? nearest;
    double minDistance = double.infinity;

    for (final node in nodes.values) {
      final distance = distanceCalc(location, node.location);
      if (distance < minDistance) {
        minDistance = distance;
        nearest = node;
      }
    }

    final distanceMeters = minDistance;
    print('📍 Snapped location [${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}]');
    print('   → Nearest node: ${nearest?.id} at [${nearest?.location.latitude.toStringAsFixed(6)}, ${nearest?.location.longitude.toStringAsFixed(6)}]');
    print('   → Distance: ${distanceMeters.toStringAsFixed(1)}m');
    
    return nearest;
  }

  /// Dijkstra's algorithm to find shortest path through campus paths
  static List<PathNode>? _dijkstraShortestPath(PathNode start, PathNode end) {
    final Map<PathNode, double> distances = {};
    final Map<PathNode, PathNode?> previous = {};
    final Set<PathNode> unvisited = {};

    // Initialize
    distances[start] = 0;
    
    // Collect all reachable nodes using BFS
    final List<PathNode> toProcess = [start];
    final Set<PathNode> visited = {};
    
    while (toProcess.isNotEmpty) {
      final current = toProcess.removeAt(0);
      if (visited.contains(current)) continue;
      visited.add(current);
      unvisited.add(current);

      for (final neighbor in current.neighbors) {
        if (!visited.contains(neighbor)) {
          toProcess.add(neighbor);
        }
      }
    }

    // Dijkstra's algorithm
    while (unvisited.isNotEmpty) {
      // Find unvisited node with smallest distance
      PathNode? current;
      double minDist = double.infinity;

      for (final node in unvisited) {
        final dist = distances[node] ?? double.infinity;
        if (dist < minDist) {
          minDist = dist;
          current = node;
        }
      }

      if (current == null || current == end) break;

      unvisited.remove(current);
      final currentDist = distances[current]!;

      // Check neighbors
      for (int i = 0; i < current.neighbors.length; i++) {
        final neighbor = current.neighbors[i];
        final edgeDist = current.edgeDistances[i];

        if (unvisited.contains(neighbor)) {
          final newDist = currentDist + edgeDist;
          if (newDist < (distances[neighbor] ?? double.infinity)) {
            distances[neighbor] = newDist;
            previous[neighbor] = current;
          }
        }
      }
    }

    // Reconstruct path
    if (distances[end] == double.infinity) {
      print('❌ No path found from ${start.id} to ${end.id}');
      print('   Start node reachability: ${distances[start] != null ? "reachable" : "unreachable"}');
      print('   End node distance: ${distances[end]}');
      return null;
    }

    final path = <PathNode>[];
    PathNode? current = end;
    while (current != null) {
      path.insert(0, current);
      current = previous[current];
    }

    final totalDistanceM = distances[end] ?? 0;
    print('✅ Found path: ${start.id} → ${end.id}');
    print('   Path length: ${path.length} nodes');
    print('   Total distance: ${totalDistanceM.toStringAsFixed(1)}m');
    
    // Print path nodes for debugging
    for (int i = 0; i < path.length; i++) {
      final node = path[i];
      print('   Step $i: ${node.id} [${node.location.latitude.toStringAsFixed(6)}, ${node.location.longitude.toStringAsFixed(6)}]');
    }
    
    return path;
  }

  /// Get route using campus paths
  static Future<route_model.Route?> getPathBasedRoute(
    LatLng start,
    LatLng end,
    List<CampusPath> campusPaths,
  ) async {
    try {
      print('\n🛤️  ========== Path-Based Routing ==========');
      print('📍 Start: ${start.latitude}, ${start.longitude}');
      print('📍 End: ${end.latitude}, ${end.longitude}');
      const Distance distanceCalc = Distance();

      // Step 1: Build graph from campus paths
      final pathGraph = _buildPathGraph(campusPaths);
      if (pathGraph.isEmpty) {
        print('❌ No valid campus paths found');
        return null;
      }

      // Step 2: Find nearest nodes to start and end
      final startNode = _findNearestNode(start, pathGraph);
      final endNode = _findNearestNode(end, pathGraph);

      if (startNode == null || endNode == null) {
        print('❌ Could not find valid start or end nodes');
        return null;
      }

      // Step 3: Find shortest path through campus paths
      final pathNodes = _dijkstraShortestPath(startNode, endNode);
      if (pathNodes == null || pathNodes.isEmpty) {
        print('❌ No route found through campus paths');
        return null;
      }

      // Step 4: Convert node path to waypoints and include exact source/destination
      final waypoints = <LatLng>[];
      waypoints.add(start);
      for (final node in pathNodes) {
        if (waypoints.isEmpty || distanceCalc(waypoints.last, node.location) > 2.0) {
          waypoints.add(node.location);
        }
      }
      if (distanceCalc(waypoints.last, end) > 2.0) {
        waypoints.add(end);
      }

      // Step 5: Calculate total distance
      double totalDistance = 0;
      for (int i = 0; i < waypoints.length - 1; i++) {
        totalDistance += distanceCalc(waypoints[i], waypoints[i + 1]);
      }

      // Estimate duration (average walking speed: 1.4 m/s)
      final totalDuration = totalDistance / 1.4;

      // Step 6: Create navigation steps
      final steps = <route_model.NavigationStep>[];
      for (int i = 0; i < waypoints.length - 1; i++) {
        final instruction = i == 0
            ? 'Head towards destination'
            : i == waypoints.length - 2
                ? 'Arrive at destination'
                : 'Continue on path';

        steps.add(
          route_model.NavigationStep(
            index: i,
            instruction: instruction,
            distance: totalDistance / (waypoints.length - 1),
            duration: totalDuration / (waypoints.length - 1),
            location: waypoints[i],
            turnType: 'straight',
          ),
        );
      }

      print('✅ Route ready with ${waypoints.length} waypoints');
      print('📏 Total distance: ${totalDistance.toStringAsFixed(1)} m');
      print('⏱️  Estimated duration: ${(totalDuration / 60).toStringAsFixed(0)} minutes');
      print('🛤️  ==========================================\n');

      return route_model.Route(
        id: 'path_based_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Campus Path Route',
        steps: steps,
        totalDistance: totalDistance,
        totalDuration: totalDuration,
        routeQuality: 5,
        routeType: 'path_based',
        wheelchairAccessible: true,
        waypoints: waypoints,
      );
    } catch (e, stackTrace) {
      print('❌ Error in path-based routing: $e');
      print('📍 Stack: ${stackTrace.toString().split('\n').take(3).join('\n')}');
      return null;
    }
  }

  /// Get all available paths in the campus
  static List<Map<String, dynamic>> getPathsInfo(List<CampusPath> paths) {
    const Distance distanceCalc = Distance();
    return paths.map((path) {
      double totalDist = 0;

      for (int i = 0; i < path.coordinates.length - 1; i++) {
        totalDist += distanceCalc(path.coordinates[i], path.coordinates[i + 1]);
      }

      return {
        'id': path.id,
        'name': path.name,
        'distance': totalDist,
        'difficulty': path.difficulty,
        'walkable': path.walkable,
        'type': path.pathType,
      };
    }).toList();
  }
}
