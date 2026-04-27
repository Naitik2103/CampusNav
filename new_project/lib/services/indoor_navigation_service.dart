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

  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  List<IndoorBuilding> get buildings => List.unmodifiable(_buildings);

  List<IndoorRoom> get rooms => List.unmodifiable(_rooms);

  Future<void> loadIndoorConfigs({
    String boundariesAsset = 'assets/data/indoor_building_boundaries.json',
    String roomsAsset = 'assets/data/indoor_rooms.json',
  }) async {
    if (_isLoaded) {
      return;
    }

    try {
      final boundaryJson = await rootBundle.loadString(boundariesAsset);
      final roomsJson = await rootBundle.loadString(roomsAsset);

      final boundaryMap = jsonDecode(boundaryJson) as Map<String, dynamic>;
      final roomsMap = jsonDecode(roomsJson) as Map<String, dynamic>;

      final parsedBuildings = _parseBuildings(boundaryMap);
      final parsedRooms = _parseRooms(roomsMap);

      _buildings
        ..clear()
        ..addAll(parsedBuildings);
      _rooms
        ..clear()
        ..addAll(parsedRooms);
      _isLoaded = true;
    } catch (_) {
      _buildings.clear();
      _rooms.clear();
      _isLoaded = false;
    }
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
      final buildingKey = _normalizeKey(building.name);
      final buildingIdKey = _normalizeKey(building.buildingId);
      if (buildingKey == normalizedName ||
          buildingIdKey == normalizedName ||
          buildingKey == normalizedId ||
          buildingIdKey == normalizedId ||
          normalizedId.contains(buildingIdKey) ||
          normalizedName.contains(buildingIdKey)) {
        return building;
      }
    }

    return null;
  }

  IndoorBuilding? findBuildingById(String buildingId) {
    if (!_isLoaded) return null;

    final key = _normalizeKey(buildingId);
    for (final building in _buildings) {
      if (_normalizeKey(building.buildingId) == key) {
        return building;
      }
    }

    return null;
  }

  List<IndoorRoom> searchRooms(String query, {int limit = 20}) {
    if (!_isLoaded || query.trim().isEmpty) {
      return [];
    }

    final lowerQuery = query.toLowerCase().trim();
    final matches = _rooms.where((room) {
      return room.name.toLowerCase().contains(lowerQuery) ||
          room.id.toLowerCase().contains(lowerQuery) ||
          room.category.toLowerCase().contains(lowerQuery);
    }).toList();

    matches.sort((a, b) {
      final aExact = a.name.toLowerCase() == lowerQuery;
      final bExact = b.name.toLowerCase() == lowerQuery;
      if (aExact && !bExact) return -1;
      if (bExact && !aExact) return 1;

      final aStarts = a.name.toLowerCase().startsWith(lowerQuery);
      final bStarts = b.name.toLowerCase().startsWith(lowerQuery);
      if (aStarts && !bStarts) return -1;
      if (bStarts && !aStarts) return 1;

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
      final boundaryData = item['boundary'] as List<dynamic>? ?? const [];
      final transitionData =
          item['floorTransitions'] as List<dynamic>? ?? const [];

      return IndoorBuilding(
        buildingId: (item['buildingId'] ?? '').toString(),
        name: (item['name'] ?? 'Unknown Building').toString(),
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
      return IndoorRoom(
        id: (item['id'] ?? '').toString(),
        buildingId: (item['buildingId'] ?? '').toString(),
        name: (item['name'] ?? 'Unknown Room').toString(),
        floor: (item['floor'] as num?)?.toInt() ?? 0,
        category: (item['category'] ?? 'room').toString(),
        description: item['description']?.toString(),
        coordinate: _latLngFromMap(item['coordinate']),
      );
    }).toList();
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

  String _normalizeKey(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}
