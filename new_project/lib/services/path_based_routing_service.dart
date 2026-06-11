import 'package:latlong2/latlong.dart';
import 'dart:collection';
import 'dart:math' as math;
import '../models/route_model.dart' as route_model;
import '../models/path_model.dart';
import 'routing_service.dart';

/// Node representing an intersection / vertex on the campus path graph.
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
  /// The map key under which this node lives in graphNodes.
  final String nodeKey;
  final double snapDistanceMeters;
  final _PathSegment? segment;
  final double? t;

  _SnapResult({
    required this.node,
    required this.nodeKey,
    required this.snapDistanceMeters,
    this.segment,
    this.t,
  });
}

class NearestPathTargetResult {
  final int index;
  final double distanceMeters;
  final PathNode targetNode;

  NearestPathTargetResult({
    required this.index,
    required this.distanceMeters,
    required this.targetNode,
  });
}

/// Path-based routing service using campus paths from GeoJSON.
/// Builds an undirected graph from campus path segments and finds
/// the shortest walk using Dijkstra's algorithm.
class PathBasedRoutingService {
  // Two vertices closer than this are treated as the SAME node.
  // 2.5 m keeps distinct nearby junctions separate while handling GPS noise.
  static const double _nodeMergeToleranceMeters = 2.5;

  // If the nearest existing node is within this distance from the
  // point-to-snap, snap directly to it instead of creating a mid-edge node.
  static const double _snapToExistingNodeToleranceMeters = 3.0;

  // Unconnected path endpoints within this distance are stitched together.
  // Analysis of campus_paths.geojson shows gaps up to ~30 m between logically
  // connected paths, so we use 35 m to bridge all of them.
  static const double _endpointStitchToleranceMeters = 35.0;

  // ─────────────────────────────────────────────────────────────────────────
  // Graph construction helpers
  // ─────────────────────────────────────────────────────────────────────────

  static String _keyForLocation(LatLng point) =>
      '${point.latitude.toStringAsFixed(6)},${point.longitude.toStringAsFixed(6)}';

  /// Returns the key of an existing node within merge tolerance, or creates
  /// a new node and returns its key.
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

  /// Adds bidirectional edge between two nodes (by map key).
  static void _connectNodes(
    Map<String, PathNode> nodes,
    String aKey,
    String bKey,
    double distanceMeters,
  ) {
    final a = nodes[aKey];
    final b = nodes[bKey];
    if (a == null || b == null) {
      print('⚠️ _connectNodes: missing node for key $aKey or $bKey');
      return;
    }
    a.addNeighbor(b, distanceMeters);
    b.addNeighbor(a, distanceMeters);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build graph
  // ─────────────────────────────────────────────────────────────────────────

  static _PathGraph _buildPathGraph(List<CampusPath> paths) {
    final Map<String, PathNode> nodes = {};
    final List<_PathSegment> segments = [];
    const Distance distanceCalc = Distance();

    print('📦 Loading ${paths.length} campus paths...');

    for (final path in paths) {
      if (!path.walkable) continue;
      if (path.coordinates.length < 2) continue;

      print('   ✓ ${path.id} (${path.coordinates.length} coords)');

      for (int i = 0; i < path.coordinates.length - 1; i++) {
        final a = path.coordinates[i];
        final b = path.coordinates[i + 1];

        final aKey = _findOrCreateNodeKey(a, nodes, distanceCalc);
        final bKey = _findOrCreateNodeKey(b, nodes, distanceCalc);

        // Skip degenerate zero-length edges.
        if (aKey == bKey) continue;

        final segLen = distanceCalc(nodes[aKey]!.location, nodes[bKey]!.location);
        if (segLen < 0.01) continue;

        _connectNodes(nodes, aKey, bKey, segLen);
        segments.add(
          _PathSegment(
            aKey: aKey,
            bKey: bKey,
            a: nodes[aKey]!.location,
            b: nodes[bKey]!.location,
            lengthMeters: segLen,
          ),
        );
      }
    }

    print('🗺️ Graph: ${nodes.length} nodes, ${segments.length} segments');
    _stitchNearbyEndpoints(nodes, distanceCalc);
    return _PathGraph(nodes: nodes, segments: segments);
  }

  /// Stitch dangling endpoints that are near each other but not yet connected.
  /// Only connects the *closest* unpaired endpoint — avoids creating web of
  /// phantom connections when multiple paths nearly converge.
  static void _stitchNearbyEndpoints(
    Map<String, PathNode> nodes,
    Distance distanceCalc,
  ) {
    // Collect nodes with degree ≤ 1 (tips / isolated nodes).
    final endpoints = nodes.entries
        .where((e) => e.value.neighbors.length <= 1)
        .toList();

    final stitchedPairs = <String>{};

    for (final source in endpoints) {
      double nearestDist = double.infinity;
      String? nearestKey;

      for (final target in endpoints) {
        if (identical(source.value, target.value)) continue;
        if (source.value.neighbors.contains(target.value)) continue;

        final pairKey = source.key.compareTo(target.key) < 0
            ? '${source.key}|${target.key}'
            : '${target.key}|${source.key}';
        if (stitchedPairs.contains(pairKey)) continue;

        final d = distanceCalc(source.value.location, target.value.location);
        if (d < nearestDist) {
          nearestDist = d;
          nearestKey = target.key;
        }
      }

      if (nearestKey != null && nearestDist <= _endpointStitchToleranceMeters) {
        final pairKey = source.key.compareTo(nearestKey) < 0
            ? '${source.key}|$nearestKey'
            : '$nearestKey|${source.key}';
        if (!stitchedPairs.add(pairKey)) continue;

        _connectNodes(nodes, source.key, nearestKey, nearestDist);
        print(
          '🔗 Stitched ${source.value.id} ↔ ${nodes[nearestKey]!.id} (${nearestDist.toStringAsFixed(1)} m)',
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Snapping a free point onto the graph
  // ─────────────────────────────────────────────────────────────────────────

  static _ProjectedPoint _projectPointOnSegment(LatLng p, LatLng a, LatLng b) {
    final latRef = (a.latitude + b.latitude + p.latitude) / 3.0;
    final cosLat = math.cos(latRef * (math.pi / 180.0));

    final ax = a.longitude * cosLat, ay = a.latitude;
    final bx = b.longitude * cosLat, by = b.latitude;
    final px = p.longitude * cosLat, py = p.latitude;

    final abx = bx - ax, aby = by - ay;
    final apx = px - ax, apy = py - ay;
    final ab2 = abx * abx + aby * aby;

    final rawT = ab2 == 0 ? 0.0 : (apx * abx + apy * aby) / ab2;
    final t = rawT.clamp(0.0, 1.0);

    return _ProjectedPoint(
      point: LatLng(ay + aby * t, (ax + abx * t) / cosLat),
      t: t,
    );
  }

  /// Snap [location] onto the graph.
  /// 1. If the nearest existing node is within [_snapToExistingNodeToleranceMeters], snap to it.
  /// 2. Otherwise project onto the nearest segment, insert a temporary node, and
  ///    wire it to the segment's two endpoints.
  /// Returns null only if the graph has no nodes/segments.
  static _SnapResult? _snapToGraph(
    LatLng location,
    Map<String, PathNode> nodes,
    List<_PathSegment> segments,
    String tempNodeId,
  ) {
    if (nodes.isEmpty || segments.isEmpty) return null;

    const Distance distanceCalc = Distance();

    // Find nearest existing node.
    String? nearestNodeKey;
    double nearestNodeDist = double.infinity;
    for (final entry in nodes.entries) {
      final d = distanceCalc(location, entry.value.location);
      if (d < nearestNodeDist) {
        nearestNodeDist = d;
        nearestNodeKey = entry.key;
      }
    }

    // Snap directly to existing node if close enough.
    if (nearestNodeKey != null &&
        nearestNodeDist <= _snapToExistingNodeToleranceMeters) {
      return _SnapResult(
        node: nodes[nearestNodeKey]!,
        nodeKey: nearestNodeKey,
        snapDistanceMeters: nearestNodeDist,
      );
    }

    // Find nearest segment and project onto it.
    _PathSegment? nearestSeg;
    LatLng? nearestProj;
    double nearestSegDist = double.infinity;
    double nearestT = 0.0;

    for (final seg in segments) {
      final proj = _projectPointOnSegment(location, seg.a, seg.b);
      final d = distanceCalc(location, proj.point);
      if (d < nearestSegDist) {
        nearestSegDist = d;
        nearestSeg = seg;
        nearestProj = proj.point;
        nearestT = proj.t;
      }
    }

    if (nearestSeg == null || nearestProj == null) return null;

    // If the projection is very close to one of the segment endpoints,
    // snap to that endpoint node instead of inserting a tiny temp node.
    if (nearestT < 0.01) {
      return _SnapResult(
        node: nodes[nearestSeg.aKey]!,
        nodeKey: nearestSeg.aKey,
        snapDistanceMeters: distanceCalc(location, nearestSeg.a),
      );
    }
    if (nearestT > 0.99) {
      return _SnapResult(
        node: nodes[nearestSeg.bKey]!,
        nodeKey: nearestSeg.bKey,
        snapDistanceMeters: distanceCalc(location, nearestSeg.b),
      );
    }

    // Insert a temporary node on the segment.
    final tempNode = PathNode(location: nearestProj, id: tempNodeId);
    final tempKey = _keyForLocation(nearestProj);
    nodes[tempKey] = tempNode;

    final distToA = nearestSeg.lengthMeters * nearestT;
    final distToB = nearestSeg.lengthMeters * (1.0 - nearestT);
    _connectNodes(nodes, tempKey, nearestSeg.aKey, distToA);
    _connectNodes(nodes, tempKey, nearestSeg.bKey, distToB);

    return _SnapResult(
      node: tempNode,
      nodeKey: tempKey,
      snapDistanceMeters: nearestSegDist,
      segment: nearestSeg,
      t: nearestT,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Dijkstra shortest path — uses a SplayTreeSet as a priority queue.
  // ─────────────────────────────────────────────────────────────────────────

  static List<PathNode>? _dijkstraShortestPath(PathNode start, PathNode end) {
    final dist = <PathNode, double>{start: 0.0};
    final prev = <PathNode, PathNode?>{start: null};

    // SplayTreeSet sorted by (cost, hashCode) — hashCode breaks ties so we
    // never accidentally treat two different nodes as equal.
    final pq = SplayTreeSet<(double, int, PathNode)>((a, b) {
      final c = a.$1.compareTo(b.$1);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });
    pq.add((0.0, start.hashCode, start));

    while (pq.isNotEmpty) {
      final (currentCost, _, current) = pq.first;
      pq.remove(pq.first);

      if (current == end) break;
      if (currentCost > (dist[current] ?? double.infinity)) continue;

      for (int i = 0; i < current.neighbors.length; i++) {
        final neighbor = current.neighbors[i];
        final newCost = currentCost + current.edgeDistances[i];
        if (newCost < (dist[neighbor] ?? double.infinity)) {
          dist[neighbor] = newCost;
          prev[neighbor] = current;
          pq.add((newCost, neighbor.hashCode, neighbor));
        }
      }
    }

    if (!dist.containsKey(end)) {
      print('❌ No path found: ${start.id} → ${end.id}');
      return null;
    }

    final path = <PathNode>[];
    PathNode? cur = end;
    while (cur != null) {
      path.insert(0, cur);
      cur = prev[cur];
    }

    print('✅ Path: ${start.id} → ${end.id} | '
        '${path.length} nodes | '
        '${dist[end]!.toStringAsFixed(1)} m');
    return path;
  }

  /// Run Dijkstra from [start] and return cost map to all reachable nodes.
  static Map<PathNode, double> _dijkstraDistances(PathNode start) {
    final dist = <PathNode, double>{start: 0.0};
    final pq = SplayTreeSet<(double, int, PathNode)>((a, b) {
      final c = a.$1.compareTo(b.$1);
      return c != 0 ? c : a.$2.compareTo(b.$2);
    });
    pq.add((0.0, start.hashCode, start));

    while (pq.isNotEmpty) {
      final (currentCost, _, current) = pq.first;
      pq.remove(pq.first);
      if (currentCost > (dist[current] ?? double.infinity)) continue;
      for (int i = 0; i < current.neighbors.length; i++) {
        final neighbor = current.neighbors[i];
        final newCost = currentCost + current.edgeDistances[i];
        if (newCost < (dist[neighbor] ?? double.infinity)) {
          dist[neighbor] = newCost;
          pq.add((newCost, neighbor.hashCode, neighbor));
        }
      }
    }
    return dist;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BFS fallback: closest reachable node to a target LatLng
  // ─────────────────────────────────────────────────────────────────────────

  static PathNode? _closestReachable(PathNode start, LatLng target) {
    const Distance d = Distance();
    final visited = <PathNode>{start};
    final queue = Queue<PathNode>()..add(start);
    PathNode best = start;
    double bestDist = d(start.location, target);

    while (queue.isNotEmpty) {
      final cur = queue.removeFirst();
      final dist = d(cur.location, target);
      if (dist < bestDist) {
        bestDist = dist;
        best = cur;
      }
      for (final nb in cur.neighbors) {
        if (visited.add(nb)) queue.add(nb);
      }
    }
    return best;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Compute a campus-path-following route from [start] to [end].
  static Future<route_model.Route?> getPathBasedRoute(
    LatLng start,
    LatLng end,
    List<CampusPath> campusPaths,
  ) async {
    try {
      print('\n🛤️  ===== Path-Based Routing =====');
      print('📍 Start : ${start.latitude}, ${start.longitude}');
      print('📍 End   : ${end.latitude}, ${end.longitude}');

      const Distance distanceCalc = Distance();

      // 1. Build graph.
      final graph = _buildPathGraph(campusPaths);
      if (graph.nodes.isEmpty || graph.segments.isEmpty) {
        print('❌ No valid campus paths loaded');
        return null;
      }

      // Work on a mutable copy so we can insert temporary snap nodes.
      final graphNodes = Map<String, PathNode>.from(graph.nodes);

      // 2. Snap start and end to graph.
      final startSnap = _snapToGraph(start, graphNodes, graph.segments, 'snap_start');
      final endSnap   = _snapToGraph(end,   graphNodes, graph.segments, 'snap_end');

      if (startSnap == null || endSnap == null) {
        print('❌ Could not snap start or end to graph');
        return null;
      }

      print('📍 Start snapped: ${startSnap.snapDistanceMeters.toStringAsFixed(1)} m');
      print('📍 End   snapped: ${endSnap.snapDistanceMeters.toStringAsFixed(1)} m');

      // 3. If both land on the same segment, connect their temp nodes directly
      //    to avoid forced backtracking through a segment endpoint.
      if (startSnap.segment != null &&
          endSnap.segment != null &&
          startSnap.segment == endSnap.segment) {
        final directDist =
            startSnap.segment!.lengthMeters * (startSnap.t! - endSnap.t!).abs();
        // Use nodeKey (the map key) — NOT node.id — to look up in graphNodes.
        _connectNodes(graphNodes, startSnap.nodeKey, endSnap.nodeKey, directDist);
        print('🔗 Same-segment direct link: ${directDist.toStringAsFixed(1)} m');
      }

      // 4. Run Dijkstra.
      List<PathNode>? pathNodes =
          _dijkstraShortestPath(startSnap.node, endSnap.node);

      // 4a. Fallback: snap directly to nearest graph node and retry.
      if (pathNodes == null || pathNodes.isEmpty) {
        print('⚠️ Snap-node Dijkstra failed — trying nearest-node fallback');
        PathNode? fallbackStart, fallbackEnd;
        double bestS = double.infinity, bestE = double.infinity;
        for (final n in graph.nodes.values) {
          final ds = distanceCalc(start, n.location);
          final de = distanceCalc(end,   n.location);
          if (ds < bestS) { bestS = ds; fallbackStart = n; }
          if (de < bestE) { bestE = de; fallbackEnd   = n; }
        }
        if (fallbackStart != null && fallbackEnd != null) {
          pathNodes = _dijkstraShortestPath(fallbackStart, fallbackEnd);
        }
      }

      // 4b. Last resort: route to closest reachable node from start.
      if ((pathNodes == null || pathNodes.isEmpty) && graph.nodes.isNotEmpty) {
        print('⚠️ Full Dijkstra failed — routing to closest reachable node');
        PathNode? fallbackStart;
        double bestS = double.infinity;
        for (final n in graph.nodes.values) {
          final ds = distanceCalc(start, n.location);
          if (ds < bestS) { bestS = ds; fallbackStart = n; }
        }
        if (fallbackStart != null) {
          final closest = _closestReachable(fallbackStart, end);
          if (closest != null) {
            pathNodes = _dijkstraShortestPath(fallbackStart, closest);
          }
        }
      }

      if (pathNodes == null || pathNodes.isEmpty) {
        print('❌ No route found through campus paths');
        return null;
      }

      // 5. Assemble waypoint list.
      final waypoints = <LatLng>[];
      waypoints.add(start);
      if (distanceCalc(start, startSnap.node.location) > 1.0) {
        waypoints.add(startSnap.node.location);
      }
      for (final node in pathNodes) {
        if (distanceCalc(waypoints.last, node.location) > 0.5) {
          waypoints.add(node.location);
        }
      }
      if (distanceCalc(waypoints.last, endSnap.node.location) > 1.0) {
        waypoints.add(endSnap.node.location);
      }
      if (distanceCalc(waypoints.last, end) > 2.0) {
        waypoints.add(end);
      }

      // 6. Compute total distance.
      double totalDistance = 0;
      for (int i = 0; i < waypoints.length - 1; i++) {
        totalDistance += distanceCalc(waypoints[i], waypoints[i + 1]);
      }
      final totalDuration = totalDistance / 1.4; // walking 1.4 m/s

      // 7. Build navigation steps.
      final steps = RoutingService.buildTurnAwareSteps(waypoints);

      print('✅ Route ready | ${waypoints.length} waypoints | '
          '${totalDistance.toStringAsFixed(0)} m | '
          '${(totalDuration / 60).toStringAsFixed(0)} min');
      print('🛤️  =================================\n');

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
    } catch (e, st) {
      print('❌ Error in path-based routing: $e');
      print('   ${st.toString().split('\n').take(4).join('\n   ')}');
      return null;
    }
  }

  /// Summary info about all paths (for debugging / UI display).
  static List<Map<String, dynamic>> getPathsInfo(List<CampusPath> paths) {
    const Distance d = Distance();
    return paths.map((path) {
      double total = 0;
      for (int i = 0; i < path.coordinates.length - 1; i++) {
        total += d(path.coordinates[i], path.coordinates[i + 1]);
      }
      return {
        'id': path.id,
        'name': path.name,
        'distance': total,
        'difficulty': path.difficulty,
        'walkable': path.walkable,
        'type': path.pathType,
      };
    }).toList();
  }

  /// Find the nearest target by walking distance (not straight-line).
  static NearestPathTargetResult? findNearestTargetByPathDistance(
    LatLng start,
    List<LatLng> targets,
    List<CampusPath> campusPaths,
  ) {
    if (targets.isEmpty) return null;

    final graph = _buildPathGraph(campusPaths);
    if (graph.nodes.isEmpty || graph.segments.isEmpty) return null;

    final graphNodes = Map<String, PathNode>.from(graph.nodes);

    final startSnap = _snapToGraph(start, graphNodes, graph.segments, 'snap_start');
    if (startSnap == null) return null;

    final targetSnaps = <({int index, PathNode node, double snapDist})>[];
    for (int i = 0; i < targets.length; i++) {
      final snap = _snapToGraph(targets[i], graphNodes, graph.segments, 'snap_t$i');
      if (snap != null) {
        targetSnaps.add((index: i, node: snap.node, snapDist: snap.snapDistanceMeters));
      }
    }
    if (targetSnaps.isEmpty) return null;

    final distances = _dijkstraDistances(startSnap.node);

    NearestPathTargetResult? best;
    for (final t in targetSnaps) {
      final base = distances[t.node];
      if (base == null || base == double.infinity) continue;
      final total = startSnap.snapDistanceMeters + base + t.snapDist;
      if (best == null || total < best.distanceMeters) {
        best = NearestPathTargetResult(
          index: t.index,
          distanceMeters: total,
          targetNode: t.node,
        );
      }
    }
    return best;
  }
}