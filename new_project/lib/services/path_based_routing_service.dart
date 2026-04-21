import 'package:latlong2/latlong.dart';
import 'dart:math' as math;
import '../models/route_model.dart' as route_model;
import '../models/path_model.dart';
import 'routing_service.dart';

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
  String toString() =>
      'PathNode($id at ${location.latitude}, ${location.longitude})';
}

class _PathSegment {
  final String aKey;
  final String bKey;
  final LatLng a;
  final LatLng b;
  final double lengthMeters;

  _PathSegment({
    required this.aKey,
    required this.bKey,
    required this.a,
    required this.b,
    required this.lengthMeters,
  });
}

class _PathGraph {
  final Map<String, PathNode> nodes;
  final List<_PathSegment> segments;

  _PathGraph({required this.nodes, required this.segments});
}

class _ProjectedPoint {
  final LatLng point;
  final double t;

  _ProjectedPoint({required this.point, required this.t});
}

class _SnapResult {
  final PathNode node;
  final double snapDistanceMeters;

  _SnapResult({required this.node, required this.snapDistanceMeters});
}

/// Path-based routing service using campus paths from GeoJSON
/// Builds a graph from campus paths and finds optimal routes through them
class PathBasedRoutingService {
  static const double _nodeMergeToleranceMeters = 2.5;
  static const double _snapToExistingNodeToleranceMeters = 1.8;

  static String _keyForLocation(LatLng point) {
    return '${point.latitude.toStringAsFixed(6)},${point.longitude.toStringAsFixed(6)}';
  }

  static String _findOrCreateNodeKey(
    LatLng point,
    Map<String, PathNode> nodes,
    Distance distanceCalc,
  ) {
    for (final entry in nodes.entries) {
      if (distanceCalc(point, entry.value.location) <=
          _nodeMergeToleranceMeters) {
        return entry.key;
      }
    }

    final key = _keyForLocation(point);
    nodes[key] = PathNode(location: point, id: 'node_${nodes.length}');
    return key;
  }

  static void _connectNodes(
    Map<String, PathNode> nodes,
    String aKey,
    String bKey,
    double distanceMeters,
  ) {
    final a = nodes[aKey]!;
    final b = nodes[bKey]!;
    a.addNeighbor(b, distanceMeters);
    b.addNeighbor(a, distanceMeters);
  }

  /// Build a graph from campus paths
  static _PathGraph _buildPathGraph(List<CampusPath> paths) {
    final Map<String, PathNode> nodes = {};
    final List<_PathSegment> segments = [];
    const Distance distanceCalc = Distance();

    print('📦 Loading ${paths.length} campus paths...');
    for (final path in paths) {
      print(
        '   Path: ${path.id} (walkable: ${path.walkable}, coords: ${path.coordinates.length})',
      );
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
        segments.add(
          _PathSegment(
            aKey: aKey,
            bKey: bKey,
            a: nodes[aKey]!.location,
            b: nodes[bKey]!.location,
            lengthMeters: segmentDistance,
          ),
        );
      }
    }

    print('🗺️ Built path graph with ${nodes.length} nodes');
    for (final entry in nodes.entries) {
      final node = entry.value;
      print(
        '   ${node.id}: [${node.location.latitude.toStringAsFixed(6)}, ${node.location.longitude.toStringAsFixed(6)}] (${node.neighbors.length} connections)',
      );
    }
    return _PathGraph(nodes: nodes, segments: segments);
  }

  static _ProjectedPoint _projectPointOnSegment(LatLng p, LatLng a, LatLng b) {
    final latRef = (a.latitude + b.latitude + p.latitude) / 3.0;
    final cosLat = math.cos(latRef * (math.pi / 180.0));

    final ax = a.longitude * cosLat;
    final ay = a.latitude;
    final bx = b.longitude * cosLat;
    final by = b.latitude;
    final px = p.longitude * cosLat;
    final py = p.latitude;

    final abx = bx - ax;
    final aby = by - ay;
    final apx = px - ax;
    final apy = py - ay;
    final ab2 = (abx * abx) + (aby * aby);

    final rawT = ab2 == 0 ? 0.0 : ((apx * abx) + (apy * aby)) / ab2;
    final t = rawT.clamp(0.0, 1.0);

    final projX = ax + (abx * t);
    final projY = ay + (aby * t);

    return _ProjectedPoint(point: LatLng(projY, projX / cosLat), t: t);
  }

  static _SnapResult? _snapToGraph(
    LatLng location,
    Map<String, PathNode> nodes,
    List<_PathSegment> segments,
    String tempNodeId,
  ) {
    if (nodes.isEmpty || segments.isEmpty) return null;

    const Distance distanceCalc = Distance();

    PathNode? nearestNode;
    double nearestNodeDistance = double.infinity;

    for (final node in nodes.values) {
      final d = distanceCalc(location, node.location);
      if (d < nearestNodeDistance) {
        nearestNodeDistance = d;
        nearestNode = node;
      }
    }

    _PathSegment? nearestSegment;
    LatLng? nearestProjectedPoint;
    double nearestSegmentDistance = double.infinity;
    double nearestT = 0.0;

    for (final segment in segments) {
      final projected = _projectPointOnSegment(location, segment.a, segment.b);
      final d = distanceCalc(location, projected.point);
      if (d < nearestSegmentDistance) {
        nearestSegmentDistance = d;
        nearestSegment = segment;
        nearestProjectedPoint = projected.point;
        nearestT = projected.t;
      }
    }

    if (nearestNode == null ||
        nearestSegment == null ||
        nearestProjectedPoint == null) {
      return null;
    }

    if (nearestNodeDistance <= _snapToExistingNodeToleranceMeters) {
      return _SnapResult(
        node: nearestNode,
        snapDistanceMeters: nearestNodeDistance,
      );
    }

    final tempNode = PathNode(location: nearestProjectedPoint, id: tempNodeId);
    final tempKey = _keyForLocation(nearestProjectedPoint);
    nodes[tempKey] = tempNode;

    final distanceToA = nearestSegment.lengthMeters * nearestT;
    final distanceToB = nearestSegment.lengthMeters * (1.0 - nearestT);

    _connectNodes(nodes, tempKey, nearestSegment.aKey, distanceToA);
    _connectNodes(nodes, tempKey, nearestSegment.bKey, distanceToB);

    return _SnapResult(
      node: tempNode,
      snapDistanceMeters: nearestSegmentDistance,
    );
  }

  /// Find nearest path node to a location using snapping
  static PathNode? _findNearestNode(
    LatLng location,
    Map<String, PathNode> nodes,
  ) {
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
    print(
      '📍 Snapped location [${location.latitude.toStringAsFixed(6)}, ${location.longitude.toStringAsFixed(6)}]',
    );
    print(
      '   → Nearest node: ${nearest?.id} at [${nearest?.location.latitude.toStringAsFixed(6)}, ${nearest?.location.longitude.toStringAsFixed(6)}]',
    );
    print('   → Distance: ${distanceMeters.toStringAsFixed(1)}m');

    return nearest;
  }

  static PathNode? _findClosestReachableNodeToTarget(
    PathNode start,
    LatLng target,
  ) {
    const Distance distanceCalc = Distance();
    final List<PathNode> queue = <PathNode>[];
    final Set<PathNode> visited = <PathNode>{};

    queue.add(start);
    visited.add(start);

    PathNode best = start;
    double bestDistance = distanceCalc(start.location, target);

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final d = distanceCalc(current.location, target);

      if (d < bestDistance) {
        bestDistance = d;
        best = current;
      }

      for (final neighbor in current.neighbors) {
        if (!visited.contains(neighbor)) {
          visited.add(neighbor);
          queue.add(neighbor);
        }
      }
    }

    return best;
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
    if (!distances.containsKey(end) || distances[end] == double.infinity) {
      print('❌ No path found from ${start.id} to ${end.id}');
      print(
        '   Start node reachability: ${distances[start] != null ? "reachable" : "unreachable"}',
      );
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
      print(
        '   Step $i: ${node.id} [${node.location.latitude.toStringAsFixed(6)}, ${node.location.longitude.toStringAsFixed(6)}]',
      );
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
      final graph = _buildPathGraph(campusPaths);
      if (graph.nodes.isEmpty || graph.segments.isEmpty) {
        print('❌ No valid campus paths found');
        return null;
      }

      final graphNodes = Map<String, PathNode>.from(graph.nodes);

      // Step 2: Snap source and destination to nearest campus segments (more stable at intersections)
      final startSnap = _snapToGraph(
        start,
        graphNodes,
        graph.segments,
        'snap_start',
      );
      final endSnap = _snapToGraph(end, graphNodes, graph.segments, 'snap_end');

      final startNode = startSnap?.node;
      final endNode = endSnap?.node;

      if (startNode == null || endNode == null) {
        print('❌ Could not find valid start or end nodes');
        return null;
      }

      print(
        '📍 Start snapped at ${startSnap!.snapDistanceMeters.toStringAsFixed(1)}m',
      );
      print(
        '📍 End snapped at ${endSnap!.snapDistanceMeters.toStringAsFixed(1)}m',
      );

      // Step 3: Find shortest path through campus paths
      List<PathNode>? pathNodes = _dijkstraShortestPath(startNode, endNode);

      if (pathNodes == null || pathNodes.isEmpty) {
        print('⚠️ Direct snapped-node routing failed, trying nearest-node fallback...');

        // Fallback: connect start/end to nearest existing graph nodes.
        // This helps when live location/destination is off-path or snapped to a
        // disconnected micro-segment.
        final fallbackStart = _findNearestNode(start, graph.nodes);
        final fallbackEnd = _findNearestNode(end, graph.nodes);

        if (fallbackStart != null && fallbackEnd != null) {
          pathNodes = _dijkstraShortestPath(fallbackStart, fallbackEnd);
          if (pathNodes != null && pathNodes.isNotEmpty) {
            print(
              '✅ Fallback routing succeeded via nearest graph nodes (${fallbackStart.id} → ${fallbackEnd.id})',
            );
          }

          if (pathNodes == null || pathNodes.isEmpty) {
            // Last-resort campus fallback:
            // route as far as possible on connected walkable graph from start,
            // then connect to destination.
            final closestReachableToEnd = _findClosestReachableNodeToTarget(
              fallbackStart,
              end,
            );

            if (closestReachableToEnd != null) {
              pathNodes = _dijkstraShortestPath(
                fallbackStart,
                closestReachableToEnd,
              );
              if (pathNodes != null && pathNodes.isNotEmpty) {
                print(
                  '✅ Last-resort fallback succeeded via reachable node ${closestReachableToEnd.id}',
                );
              }
            }
          }
        }
      }

      if (pathNodes == null || pathNodes.isEmpty) {
        print('❌ No route found through campus paths');
        return null;
      }

      // Step 4: Convert node path to waypoints and include exact source/destination
      final waypoints = <LatLng>[];
      waypoints.add(start);

      // Ensure there is an explicit connector from live location to path.
      if (distanceCalc(waypoints.last, startNode.location) > 0.8) {
        waypoints.add(startNode.location);
      }

      for (final node in pathNodes) {
        if (waypoints.isEmpty ||
            distanceCalc(waypoints.last, node.location) > 0.8) {
          waypoints.add(node.location);
        }
      }

      // Ensure connector from path network to destination side.
      if (distanceCalc(waypoints.last, endNode.location) > 0.8) {
        waypoints.add(endNode.location);
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

      // Step 6: Create turn-aware navigation steps
      final steps = RoutingService.buildTurnAwareSteps(waypoints);

      print('✅ Route ready with ${waypoints.length} waypoints');
      print('📏 Total distance: ${totalDistance.toStringAsFixed(1)} m');
      print(
        '⏱️  Estimated duration: ${(totalDuration / 60).toStringAsFixed(0)} minutes',
      );
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
      print(
        '📍 Stack: ${stackTrace.toString().split('\n').take(3).join('\n')}',
      );
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
