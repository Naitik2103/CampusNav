import 'package:latlong2/latlong.dart';

class IndoorBuilding {
  final String buildingId;
  final String name;
  final List<String> aliases;
  final bool hasIndoorMap;
  final int groundFloor;
  final List<int> floors;
  final List<LatLng> boundary;
  final List<IndoorTransitionPoint> transitionPoints;

  IndoorBuilding({
    required this.buildingId,
    required this.name,
    this.aliases = const [],
    required this.hasIndoorMap,
    required this.groundFloor,
    required this.floors,
    required this.boundary,
    required this.transitionPoints,
  });
}

class IndoorTransitionPoint {
  final String id;
  final String label;
  final String type;
  final List<int> floors;
  final LatLng coordinate;

  IndoorTransitionPoint({
    required this.id,
    required this.label,
    required this.type,
    required this.floors,
    required this.coordinate,
  });
}

class IndoorRoom {
  final String id;
  final String buildingId;
  final String name;
  final List<String> aliases;
  final int floor;
  final String category;
  final String? description;
  final LatLng coordinate;

  IndoorRoom({
    required this.id,
    required this.buildingId,
    required this.name,
    this.aliases = const [],
    required this.floor,
    required this.category,
    this.description,
    required this.coordinate,
  });
}

class IndoorRouteSuggestion {
  final IndoorRoom room;
  final int fromFloor;
  final int toFloor;
  final IndoorTransitionPoint? transitionPoint;

  IndoorRouteSuggestion({
    required this.room,
    required this.fromFloor,
    required this.toFloor,
    this.transitionPoint,
  });

  bool get requiresFloorTransition => fromFloor != toFloor;
}
