import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../models/indoor_models.dart';
import '../models/place_model.dart';

class IndoorNavigationService {
  IndoorNavigationService._();

  static final IndoorNavigationService instance = IndoorNavigationService._();

  final List<IndoorBuilding> _buildings = [];
  final List<IndoorRoom> _rooms = [];
  final Map<String, _IndoorPathBuilding> _indoorPathGraphs = {};

  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  List<IndoorBuilding> get buildings => List.unmodifiable(_buildings);

  List<IndoorRoom> get rooms => List.unmodifiable(_rooms);

  Future<void> loadIndoorConfigs({
    String boundariesAsset = 'assets/data/indoor_building_boundaries.json',
    String roomsAsset = 'assets/data/indoor_rooms.json',
    String pathsAsset = 'assets/data/indoor_paths.json',
    String stairsAsset = 'assets/data/indoor_stairs.json',
  }) async {
    if (_isLoaded) {
      return;
    }

    try {
      final boundaryJson = await rootBundle.loadString(boundariesAsset);
      final roomsJson = await rootBundle.loadString(roomsAsset);
      final pathsJson = await rootBundle.loadString(pathsAsset);

      final boundaryMap = jsonDecode(boundaryJson) as Map<String, dynamic>;
      final roomsMap = jsonDecode(roomsJson) as Map<String, dynamic>;
      final pathsMap = jsonDecode(pathsJson) as Map<String, dynamic>;

      // Try to load optional stairs file and merge into pathsMap
      try {
        final stairsJson = await rootBundle.loadString(stairsAsset);
        final stairsMap = jsonDecode(stairsJson) as Map<String, dynamic>;

        if (stairsMap.isNotEmpty) {
          final buildingsList = (pathsMap['buildings'] as List<dynamic>?) ?? [];

          // Determine target building index by buildingId if provided in stairs file
          final stairsBuildingId = (stairsMap['buildingId'] as String?)
              ?.toLowerCase();
          int targetIndex = 0;
          if (stairsBuildingId != null && buildingsList.isNotEmpty) {
            for (var i = 0; i < buildingsList.length; i++) {
              final b = buildingsList[i] as Map<String, dynamic>;
              if ((b['buildingId'] as String?)?.toLowerCase() ==
                  stairsBuildingId) {
                targetIndex = i;
                break;
              }
            }
          }

          // merge nodes
          final targetBuilding = buildingsList.isNotEmpty
              ? buildingsList[targetIndex] as Map<String, dynamic>
              : null;
          if (targetBuilding != null) {
            targetBuilding['nodes'] =
                (targetBuilding['nodes'] as List<dynamic>?) ?? [];
            targetBuilding['edges'] =
                (targetBuilding['edges'] as List<dynamic>?) ?? [];
            targetBuilding['entrances'] =
                (targetBuilding['entrances'] as List<dynamic>?) ?? [];

            final stairsNodes = stairsMap['nodes'] as List<dynamic>?;
            final stairsEdges = stairsMap['edges'] as List<dynamic>?;
            final stairsEntrances = stairsMap['entrances'] as List<dynamic>?;

            if (stairsNodes != null) {
              for (final n in stairsNodes) {
                (targetBuilding['nodes'] as List).add(n);
              }
            }
            if (stairsEdges != null) {
              for (final e in stairsEdges) {
                (targetBuilding['edges'] as List).add(e);
              }
            }
            if (stairsEntrances != null) {
              for (final ent in stairsEntrances) {
                if (!(targetBuilding['entrances'] as List).contains(ent)) {
                  (targetBuilding['entrances'] as List).add(ent);
                }
              }
            }
          } else {
            // If no building entries exist yet, merge top-level nodes/edges into pathsMap directly
            pathsMap['nodes'] = (pathsMap['nodes'] as List<dynamic>?) ?? [];
            pathsMap['edges'] = (pathsMap['edges'] as List<dynamic>?) ?? [];
            pathsMap['entrances'] =
                (pathsMap['entrances'] as List<dynamic>?) ?? [];
            final stairsNodes = stairsMap['nodes'] as List<dynamic>?;
            final stairsEdges = stairsMap['edges'] as List<dynamic>?;
            final stairsEntrances = stairsMap['entrances'] as List<dynamic>?;
            if (stairsNodes != null) pathsMap['nodes'].addAll(stairsNodes);
            if (stairsEdges != null) pathsMap['edges'].addAll(stairsEdges);
            if (stairsEntrances != null) {
              for (final ent in stairsEntrances) {
                if (!(pathsMap['entrances'] as List).contains(ent)) {
                  (pathsMap['entrances'] as List).add(ent);
                }
              }
            }
          }
        }
      } catch (e) {
        // optional stairs file absent or parse error — continue without merging
      }

      final parsedBuildings = _parseBuildings(boundaryMap);
      final parsedRooms = _parseRooms(roomsMap);
      final parsedPathGraphs = _parseIndoorPathGraphs(pathsMap);

      // Ensure every room has a corresponding node in the path graph
      // and is connected to the nearest path node on the same floor.
      _attachMissingRoomNodes(parsedRooms, parsedPathGraphs);

      _buildings
        ..clear()
        ..addAll(parsedBuildings);
      _rooms
        ..clear()
        ..addAll(parsedRooms);
      _indoorPathGraphs
        ..clear()
        ..addAll(parsedPathGraphs);
      _isLoaded = true;
    } catch (_) {
      _buildings.clear();
      _rooms.clear();
      _indoorPathGraphs.clear();
      _isLoaded = false;
    }
  }

  void _attachMissingRoomNodes(
    List<IndoorRoom> rooms,
    Map<String, _IndoorPathBuilding> graphs,
  ) {
    final distanceCalc = Distance();

    for (final room in rooms) {
      final key = _normalizeKey(room.buildingId);
      final graph = graphs[key];
      if (graph == null) continue;

      // If graph already maps this room, skip
      if (graph.roomNodeMap.containsKey(room.id)) continue;
      if (graph.nodes.values.any((n) => n.roomId == room.id)) continue;

      // Create a unique node id for the room
      var baseId = 'room_${room.id}';
      var nodeId = baseId;
      var suffix = 0;
      while (graph.nodes.containsKey(nodeId)) {
        suffix++;
        nodeId = '${baseId}_$suffix';
      }

      // Add the node
      graph.nodes[nodeId] = _IndoorPathNode(
        id: nodeId,
        floor: room.floor,
        coordinate: room.coordinate,
        roomId: room.id,
        type: 'room-door',
      );

      // Find nearest existing node on the same floor to connect to
      String? nearestId;
      var bestDist = double.infinity;
      for (final n in graph.nodes.values) {
        if (n.id == nodeId) continue;
        if (n.floor != room.floor) continue;
        final d = distanceCalc(room.coordinate, n.coordinate);
        if (d < bestDist) {
          bestDist = d;
          nearestId = n.id;
        }
      }

      if (nearestId != null) {
        graph.edges.add(
          _IndoorPathEdge(from: nodeId, to: nearestId, bidirectional: true),
        );
      }

      // Register in roomNodeMap
      graph.roomNodeMap[room.id] = nodeId;
    }
  }

  List<LatLng> getIndoorRoutePolyline({
    required IndoorBuilding building,
    required IndoorRoom destinationRoom,
    int? fromFloor,
  }) {
    if (!_isLoaded) {
      return [];
    }

    final buildingKey = _normalizeKey(building.buildingId);
    final graph = _indoorPathGraphs[buildingKey];
    if (graph == null) {
      return [];
    }

    final destinationNodeId =
        graph.roomNodeMap[destinationRoom.id] ??
        graph.nodes.values
            .where((node) => node.roomId == destinationRoom.id)
            .map((node) => node.id)
            .cast<String?>()
            .firstWhere((_) => true, orElse: () => null);

    if (destinationNodeId == null ||
        !graph.nodes.containsKey(destinationNodeId)) {
      return [];
    }

    final sourceFloor = fromFloor ?? destinationRoom.floor;
    final startNodeId = _pickBestStartNode(
      graph: graph,
      targetFloor: sourceFloor,
      fallbackFloor: destinationRoom.floor,
    );

    if (startNodeId == null || !graph.nodes.containsKey(startNodeId)) {
      return [];
    }

    final pathNodeIds = _dijkstraPathNodeIds(
      graph: graph,
      startId: startNodeId,
      endId: destinationNodeId,
    );

    if (pathNodeIds.isEmpty) {
      return [];
    }

    return pathNodeIds
        .map((id) => graph.nodes[id])
        .whereType<_IndoorPathNode>()
        .map((node) => node.coordinate)
        .toList();
  }

  List<LatLng> getIndoorRoutePolylineFromLocation({
    required IndoorBuilding building,
    required LatLng startLocation,
    required IndoorRoom destinationRoom,
    int? fromFloor,
  }) {
    if (!_isLoaded) {
      return [];
    }

    final buildingKey = _normalizeKey(building.buildingId);
    final graph = _indoorPathGraphs[buildingKey];
    if (graph == null) {
      return [];
    }

    final destinationNodeId =
        graph.roomNodeMap[destinationRoom.id] ??
        graph.nodes.values
            .where((node) => node.roomId == destinationRoom.id)
            .map((node) => node.id)
            .cast<String?>()
            .firstWhere((_) => true, orElse: () => null);

    if (destinationNodeId == null ||
        !graph.nodes.containsKey(destinationNodeId)) {
      return [];
    }

    final targetFloor = fromFloor ?? destinationRoom.floor;
    final nearestNodeId =
        _findNearestEntryNodeOnFloor(
          graph: graph,
          location: startLocation,
          floor: targetFloor,
        ) ??
        _findNearestNodeOnFloor(
          graph: graph,
          location: startLocation,
          floor: targetFloor,
        );

    final startNodeId =
        nearestNodeId ??
        _pickBestStartNode(
          graph: graph,
          targetFloor: targetFloor,
          fallbackFloor: destinationRoom.floor,
        );

    if (startNodeId == null || !graph.nodes.containsKey(startNodeId)) {
      return [];
    }

    final pathNodeIds = _dijkstraPathNodeIds(
      graph: graph,
      startId: startNodeId,
      endId: destinationNodeId,
    );

    if (pathNodeIds.isEmpty) {
      return [];
    }

    return pathNodeIds
        .map((id) => graph.nodes[id])
        .whereType<_IndoorPathNode>()
        .map((node) => node.coordinate)
        .toList();
  }

  IndoorBuilding? findBuildingByGps(LatLng location) {
    if (!_isLoaded) return null;

    for (final building in _buildings) {
      if (_isPointInsidePolygon(location, building.boundary)) {
        return building;
      }
    }
    return null;
  }

  IndoorBuilding? findBuildingForPlace(CampusPlace place) {
    if (!_isLoaded) return null;

    final normalizedName = _normalizeKey(place.name);
    final normalizedId = _normalizeKey(place.id);

    for (final building in _buildings) {
      final buildingKeys = _collectNormalizedBuildingKeys(building);
      final hasDirectMatch =
          buildingKeys.contains(normalizedName) ||
          buildingKeys.contains(normalizedId);
      final hasContainsMatch = buildingKeys.any(
        (key) =>
            key.isNotEmpty &&
            (normalizedName.contains(key) || normalizedId.contains(key)),
      );

      if (hasDirectMatch || hasContainsMatch) {
        return building;
      }
    }

    return null;
  }

  IndoorBuilding? findBuildingById(String buildingId) {
    if (!_isLoaded) return null;

    final key = _normalizeKey(buildingId);
    for (final building in _buildings) {
      final buildingKeys = _collectNormalizedBuildingKeys(building);
      if (buildingKeys.contains(key)) {
        return building;
      }
    }

    return null;
  }

  List<IndoorRoom> searchRooms(String query, {int limit = 20}) {
    if (!_isLoaded || query.trim().isEmpty) {
      return [];
    }

    final normalizedQuery = _normalizeKey(query);
    final matches = _rooms.where((room) {
      final roomNameMatches = _allRoomNames(
        room,
      ).any((name) => _normalizeKey(name).contains(normalizedQuery));

      return roomNameMatches ||
          _normalizeKey(room.id).contains(normalizedQuery) ||
          _normalizeKey(room.category).contains(normalizedQuery);
    }).toList();

    matches.sort((a, b) {
      final aScore = _bestRoomNameMatchScore(a, normalizedQuery);
      final bScore = _bestRoomNameMatchScore(b, normalizedQuery);
      if (aScore != bScore) {
        return bScore.compareTo(aScore);
      }

      return a.name.compareTo(b.name);
    });

    return matches.take(limit).toList();
  }

  List<IndoorRoom> getRoomsForFloor(String buildingId, int floor) {
    return _rooms
        .where(
          (room) =>
              room.buildingId.toLowerCase() == buildingId.toLowerCase() &&
              room.floor == floor,
        )
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  List<List<LatLng>> getIndoorGraphLines({
    required String buildingId,
    required int floor,
  }) {
    if (!_isLoaded) {
      return [];
    }

    final graph = _indoorPathGraphs[_normalizeKey(buildingId)];
    if (graph == null) {
      return [];
    }

    final lines = <List<LatLng>>[];
    for (final edge in graph.edges) {
      final fromNode = graph.nodes[edge.from];
      final toNode = graph.nodes[edge.to];
      if (fromNode == null || toNode == null) {
        continue;
      }
      if (fromNode.type != 'room-door' || toNode.type != 'room-door') {
        continue;
      }
      if (fromNode.floor != floor || toNode.floor != floor) {
        continue;
      }
      lines.add([fromNode.coordinate, toNode.coordinate]);
    }

    return lines;
  }

  IndoorRouteSuggestion? suggestRouteToRoom({
    required IndoorBuilding building,
    required int fromFloor,
    required IndoorRoom room,
  }) {
    if (room.buildingId.toLowerCase() != building.buildingId.toLowerCase()) {
      return null;
    }

    IndoorTransitionPoint? transitionPoint;
    if (fromFloor != room.floor) {
      transitionPoint = building.transitionPoints.firstWhere(
        (point) =>
            point.floors.contains(fromFloor) &&
            point.floors.contains(room.floor),
        orElse: () => building.transitionPoints.firstWhere(
          (point) => point.floors.contains(room.floor),
          orElse: () => IndoorTransitionPoint(
            id: 'none',
            label: 'Nearest staircase/elevator',
            type: 'stairs',
            floors: [fromFloor, room.floor],
            coordinate: room.coordinate,
          ),
        ),
      );
    }

    return IndoorRouteSuggestion(
      room: room,
      fromFloor: fromFloor,
      toFloor: room.floor,
      transitionPoint: transitionPoint,
    );
  }

  List<IndoorBuilding> _parseBuildings(Map<String, dynamic> jsonMap) {
    final dynamic data = jsonMap['buildings'];
    if (data is! List) return [];

    return data.whereType<Map<String, dynamic>>().map((item) {
      final names = _extractNameVariants(
        item['name'],
        aliasValue: item['aliases'],
        fallback: 'Unknown Building',
      );
      final boundaryData = item['boundary'] as List<dynamic>? ?? const [];
      final transitionData =
          item['floorTransitions'] as List<dynamic>? ?? const [];

      return IndoorBuilding(
        buildingId: (item['buildingId'] ?? '').toString(),
        name: names.first,
        aliases: names.skip(1).toList(),
        hasIndoorMap: item['hasIndoorMap'] == true,
        groundFloor: (item['groundFloor'] as num?)?.toInt() ?? 0,
        floors: (item['floors'] as List<dynamic>? ?? const [])
            .map((e) => (e as num).toInt())
            .toList(),
        boundary: boundaryData
            .whereType<Map<String, dynamic>>()
            .map(_latLngFromMap)
            .toList(),
        transitionPoints: transitionData
            .whereType<Map<String, dynamic>>()
            .map(
              (entry) => IndoorTransitionPoint(
                id: (entry['id'] ?? '').toString(),
                label: (entry['label'] ?? 'Transition').toString(),
                type: (entry['type'] ?? 'stairs').toString(),
                floors: (entry['floors'] as List<dynamic>? ?? const [])
                    .map((e) => (e as num).toInt())
                    .toList(),
                coordinate: _latLngFromMap(entry['coordinate']),
              ),
            )
            .toList(),
      );
    }).toList();
  }

  List<IndoorRoom> _parseRooms(Map<String, dynamic> jsonMap) {
    final dynamic data = jsonMap['rooms'];
    if (data is! List) return [];

    return data.whereType<Map<String, dynamic>>().map((item) {
      final names = _extractNameVariants(
        item['name'],
        aliasValue: item['aliases'],
        fallback: 'Unknown Room',
      );

      return IndoorRoom(
        id: (item['id'] ?? '').toString(),
        buildingId: (item['buildingId'] ?? '').toString(),
        name: names.first,
        aliases: names.skip(1).toList(),
        floor: (item['floor'] as num?)?.toInt() ?? 0,
        category: (item['category'] ?? 'room').toString(),
        description: item['description']?.toString(),
        coordinate: _latLngFromMap(item['coordinate']),
      );
    }).toList();
  }

  Map<String, _IndoorPathBuilding> _parseIndoorPathGraphs(
    Map<String, dynamic> jsonMap,
  ) {
    final data = jsonMap['buildings'];
    if (data is! List) {
      return {};
    }

    final Map<String, _IndoorPathBuilding> parsed = {};

    for (final raw in data.whereType<Map<String, dynamic>>()) {
      final buildingId = (raw['buildingId'] ?? '').toString();
      if (buildingId.isEmpty) {
        continue;
      }

      final nodesData = raw['nodes'] as List<dynamic>? ?? const [];
      final edgesData = raw['edges'] as List<dynamic>? ?? const [];
      final roomNodeData =
          raw['roomNodeMap'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      final entrancesData = raw['entrances'] as List<dynamic>? ?? const [];
      final entrancesByFloorData = raw['entrancesByFloor'];

      final Map<String, _IndoorPathNode> nodes = {};
      for (final nodeRaw in nodesData.whereType<Map<String, dynamic>>()) {
        final id = (nodeRaw['id'] ?? '').toString();
        if (id.isEmpty) {
          continue;
        }

        nodes[id] = _IndoorPathNode(
          id: id,
          floor: (nodeRaw['floor'] as num?)?.toInt() ?? 0,
          coordinate: _latLngFromMap(nodeRaw['coordinate']),
          roomId: nodeRaw['roomId']?.toString(),
          type: (nodeRaw['type'] ?? '').toString(),
        );
      }

      final List<_IndoorPathEdge> edges = [];
      for (final edgeRaw in edgesData.whereType<Map<String, dynamic>>()) {
        final from = (edgeRaw['from'] ?? '').toString();
        final to = (edgeRaw['to'] ?? '').toString();
        if (from.isEmpty || to.isEmpty) {
          continue;
        }

        edges.add(
          _IndoorPathEdge(
            from: from,
            to: to,
            bidirectional: edgeRaw['bidirectional'] != false,
          ),
        );
      }

      final roomNodeMap = <String, String>{};
      roomNodeData.forEach((key, value) {
        roomNodeMap[key.toString()] = value.toString();
      });

      final entrances = entrancesData
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList();
      final entrancesByFloor = _parseEntrancesByFloor(entrancesByFloorData);

      final normalizedKey = _normalizeKey(buildingId);
      parsed[normalizedKey] = _IndoorPathBuilding(
        buildingId: buildingId,
        nodes: nodes,
        edges: edges,
        roomNodeMap: roomNodeMap,
        entrances: entrances,
        entrancesByFloor: entrancesByFloor,
      );
    }

    return parsed;
  }

  String? _pickBestStartNode({
    required _IndoorPathBuilding graph,
    required int targetFloor,
    required int fallbackFloor,
  }) {
    final targetEntrances = graph.entrancesByFloor[targetFloor];
    if (targetEntrances != null) {
      for (final entranceId in targetEntrances) {
        final node = graph.nodes[entranceId];
        if (node != null && node.floor == targetFloor) {
          return entranceId;
        }
      }
    }

    for (final entranceId in graph.entrances) {
      final node = graph.nodes[entranceId];
      if (node != null && node.floor == targetFloor) {
        return entranceId;
      }
    }

    final fallbackEntrances = graph.entrancesByFloor[fallbackFloor];
    if (fallbackEntrances != null) {
      for (final entranceId in fallbackEntrances) {
        final node = graph.nodes[entranceId];
        if (node != null && node.floor == fallbackFloor) {
          return entranceId;
        }
      }
    }

    for (final entranceId in graph.entrances) {
      final node = graph.nodes[entranceId];
      if (node != null && node.floor == fallbackFloor) {
        return entranceId;
      }
    }

    if (graph.entrances.isNotEmpty &&
        graph.nodes.containsKey(graph.entrances.first)) {
      return graph.entrances.first;
    }

    final sameFloorNode = graph.nodes.values
        .where((node) => node.floor == fallbackFloor)
        .map((node) => node.id)
        .cast<String?>()
        .firstWhere((_) => true, orElse: () => null);

    return sameFloorNode ??
        (graph.nodes.isNotEmpty ? graph.nodes.keys.first : null);
  }

  String? _findNearestNodeOnFloor({
    required _IndoorPathBuilding graph,
    required LatLng location,
    required int floor,
  }) {
    final distanceCalc = Distance();
    String? bestId;
    double bestDistance = double.infinity;

    for (final node in graph.nodes.values) {
      if (node.floor != floor) {
        continue;
      }

      final currentDistance = distanceCalc(location, node.coordinate);
      if (currentDistance < bestDistance) {
        bestDistance = currentDistance;
        bestId = node.id;
      }
    }

    return bestId;
  }

  String? _findNearestEntryNodeOnFloor({
    required _IndoorPathBuilding graph,
    required LatLng location,
    required int floor,
  }) {
    final entryCandidates = <String>[
      ...?graph.entrancesByFloor[floor],
      ...graph.entrances,
    ];
    if (entryCandidates.isEmpty) {
      return null;
    }

    final distanceCalc = Distance();
    String? bestId;
    double bestDistance = double.infinity;

    for (final entryId in entryCandidates) {
      final node = graph.nodes[entryId];
      if (node == null || node.floor != floor) {
        continue;
      }
      final currentDistance = distanceCalc(location, node.coordinate);
      if (currentDistance < bestDistance) {
        bestDistance = currentDistance;
        bestId = entryId;
      }
    }

    return bestId;
  }

  List<String> _dijkstraPathNodeIds({
    required _IndoorPathBuilding graph,
    required String startId,
    required String endId,
  }) {
    if (!graph.nodes.containsKey(startId) || !graph.nodes.containsKey(endId)) {
      return [];
    }

    final adjacency = <String, List<_IndoorEdgeNeighbor>>{};
    const distanceCalc = Distance();

    void addDirectedEdge(String from, String to) {
      final fromNode = graph.nodes[from];
      final toNode = graph.nodes[to];
      if (fromNode == null || toNode == null) {
        return;
      }

      adjacency.putIfAbsent(from, () => []);
      adjacency[from]!.add(
        _IndoorEdgeNeighbor(
          to: to,
          weight: distanceCalc(fromNode.coordinate, toNode.coordinate),
        ),
      );
    }

    for (final edge in graph.edges) {
      addDirectedEdge(edge.from, edge.to);
      if (edge.bidirectional) {
        addDirectedEdge(edge.to, edge.from);
      }
    }

    final distances = <String, double>{};
    final previous = <String, String?>{};
    final unvisited = <String>{...graph.nodes.keys};

    for (final nodeId in graph.nodes.keys) {
      distances[nodeId] = double.infinity;
      previous[nodeId] = null;
    }
    distances[startId] = 0;

    while (unvisited.isNotEmpty) {
      String? current;
      var bestDistance = double.infinity;

      for (final nodeId in unvisited) {
        final nodeDistance = distances[nodeId] ?? double.infinity;
        if (nodeDistance < bestDistance) {
          bestDistance = nodeDistance;
          current = nodeId;
        }
      }

      if (current == null || bestDistance == double.infinity) {
        break;
      }

      if (current == endId) {
        break;
      }

      unvisited.remove(current);
      for (final neighbor
          in adjacency[current] ?? const <_IndoorEdgeNeighbor>[]) {
        if (!unvisited.contains(neighbor.to)) {
          continue;
        }

        final alt = bestDistance + neighbor.weight;
        if (alt < (distances[neighbor.to] ?? double.infinity)) {
          distances[neighbor.to] = alt;
          previous[neighbor.to] = current;
        }
      }
    }

    if ((distances[endId] ?? double.infinity) == double.infinity) {
      return [];
    }

    final path = <String>[];
    String? cursor = endId;
    while (cursor != null) {
      path.add(cursor);
      cursor = previous[cursor];
    }

    return path.reversed.toList();
  }

  LatLng _latLngFromMap(dynamic value) {
    if (value is! Map<String, dynamic>) {
      return const LatLng(0, 0);
    }

    final lat = (value['lat'] as num?)?.toDouble() ?? 0;
    final lng = (value['lng'] as num?)?.toDouble() ?? 0;
    return LatLng(lat, lng);
  }

  bool _isPointInsidePolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) {
      return false;
    }

    final x = point.longitude;
    final y = point.latitude;
    var inside = false;

    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].longitude;
      final yi = polygon[i].latitude;
      final xj = polygon[j].longitude;
      final yj = polygon[j].latitude;

      final intersects =
          ((yi > y) != (yj > y)) &&
          (x <
              ((xj - xi) * (y - yi)) / ((yj - yi) == 0 ? 1e-10 : (yj - yi)) +
                  xi);

      if (intersects) {
        inside = !inside;
      }
    }

    return inside;
  }

  Set<String> _collectNormalizedBuildingKeys(IndoorBuilding building) {
    final keys = <String>{
      _normalizeKey(building.buildingId),
      _normalizeKey(building.name),
    };

    for (final alias in building.aliases) {
      keys.add(_normalizeKey(alias));
    }

    keys.removeWhere((entry) => entry.isEmpty);
    return keys;
  }

  List<String> _allRoomNames(IndoorRoom room) {
    return <String>[
      room.name,
      ...room.aliases,
    ].where((name) => name.trim().isNotEmpty).toList();
  }

  int _bestRoomNameMatchScore(IndoorRoom room, String normalizedQuery) {
    var bestScore = 0;

    for (final rawName in _allRoomNames(room)) {
      final name = _normalizeKey(rawName);
      if (name == normalizedQuery) {
        bestScore = 3;
        break;
      }
      if (name.startsWith(normalizedQuery) && bestScore < 2) {
        bestScore = 2;
      } else if (name.contains(normalizedQuery) && bestScore < 1) {
        bestScore = 1;
      }
    }

    return bestScore;
  }

  List<String> _extractNameVariants(
    dynamic nameValue, {
    dynamic aliasValue,
    required String fallback,
  }) {
    final results = <String>[];

    void addName(dynamic value) {
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          results.add(trimmed);
        }
        return;
      }

      if (value is List) {
        for (final entry in value) {
          addName(entry);
        }
      }
    }

    addName(nameValue);
    addName(aliasValue);

    if (results.isEmpty) {
      results.add(fallback);
      return results;
    }

    final deduped = <String>[];
    final seen = <String>{};
    for (final entry in results) {
      final normalized = _normalizeKey(entry);
      if (normalized.isEmpty || seen.contains(normalized)) {
        continue;
      }
      seen.add(normalized);
      deduped.add(entry);
    }

    return deduped.isEmpty ? <String>[fallback] : deduped;
  }

  String _normalizeKey(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  Map<int, List<String>> _parseEntrancesByFloor(dynamic value) {
    if (value is! Map) {
      return {};
    }

    final parsed = <int, List<String>>{};
    value.forEach((key, rawList) {
      final floor = int.tryParse(key.toString());
      if (floor == null || rawList is! List) {
        return;
      }

      final entries = rawList
          .map((entry) => entry.toString())
          .where((entry) => entry.isNotEmpty)
          .toList();

      if (entries.isNotEmpty) {
        parsed[floor] = entries;
      }
    });

    return parsed;
  }
}

class _IndoorPathBuilding {
  final String buildingId;
  final Map<String, _IndoorPathNode> nodes;
  final List<_IndoorPathEdge> edges;
  final Map<String, String> roomNodeMap;
  final List<String> entrances;
  final Map<int, List<String>> entrancesByFloor;

  _IndoorPathBuilding({
    required this.buildingId,
    required this.nodes,
    required this.edges,
    required this.roomNodeMap,
    required this.entrances,
    required this.entrancesByFloor,
  });
}

class _IndoorPathNode {
  final String id;
  final int floor;
  final LatLng coordinate;
  final String? roomId;
  final String type;

  _IndoorPathNode({
    required this.id,
    required this.floor,
    required this.coordinate,
    required this.roomId,
    required this.type,
  });
}

class _IndoorPathEdge {
  final String from;
  final String to;
  final bool bidirectional;

  _IndoorPathEdge({
    required this.from,
    required this.to,
    required this.bidirectional,
  });
}

class _IndoorEdgeNeighbor {
  final String to;
  final double weight;

  const _IndoorEdgeNeighbor({required this.to, required this.weight});
}
