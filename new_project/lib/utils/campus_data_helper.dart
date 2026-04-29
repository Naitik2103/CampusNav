/// Helper utility for working with campus map data locally
/// 
/// Usage Example:
/// ```dart
/// // Create a new path
/// final newPath = CampusPathHelper.createPath(
///   id: 'path_new_1',
///   name: 'New Campus Path',
///   coordinates: [
///     LatLng(28.5355, 77.0495),
///     LatLng(28.5360, 77.0500),
///   ],
///   difficulty: 'easy',
/// );
///
/// // Create a new place
/// final newPlace = CampusPlaceHelper.createPlace(
///   id: 'place_new_1',
///   name: 'New Building',
///   location: LatLng(28.5365, 77.0510),
///   placeType: 'building',
/// );
/// ```
library;

import 'package:latlong2/latlong.dart';
import '../models/path_model.dart';
import '../models/place_model.dart';

class CampusPathHelper {
  /// Create a new campus path with sensible defaults
  static CampusPath createPath({
    required String id,
    required String name,
    required List<LatLng> coordinates,
    String difficulty = 'easy',
    bool walkable = true,
    String pathType = 'concrete',
    bool wheelchairAccessible = false,
    String? restrictions,
    String? description,
  }) {
    return CampusPath(
      id: id,
      name: name,
      coordinates: coordinates,
      walkable: walkable,
      pathType: pathType,
      difficulty: difficulty,
      wheelchairAccessible: wheelchairAccessible,
      restrictions: restrictions,
      description: description,
    );
  }

  /// Create common path types
  static CampusPath createMainPath(String id, String name, List<LatLng> coords) {
    return createPath(
      id: id,
      name: name,
      coordinates: coords,
      pathType: 'concrete',
      difficulty: 'easy',
      wheelchairAccessible: true,
      description: 'Main accessible pathway',
    );
  }

  static CampusPath createTrail(String id, String name, List<LatLng> coords) {
    return createPath(
      id: id,
      name: name,
      coordinates: coords,
      pathType: 'grass',
      difficulty: 'medium',
      wheelchairAccessible: false,
      description: 'Natural trail path',
    );
  }

  static CampusPath createHiking(String id, String name, List<LatLng> coords) {
    return createPath(
      id: id,
      name: name,
      coordinates: coords,
      pathType: 'grass',
      difficulty: 'hard',
      wheelchairAccessible: false,
      restrictions: 'no_vehicles,no_bikes',
      description: 'Hiking trail with elevation',
    );
  }

  static CampusPath createAccessiblePath(String id, String name, List<LatLng> coords) {
    return createPath(
      id: id,
      name: name,
      coordinates: coords,
      pathType: 'concrete',
      difficulty: 'easy',
      wheelchairAccessible: true,
      restrictions: null,
      description: 'Wheelchair accessible pathway',
    );
  }
}

class CampusPlaceHelper {
  /// Create a new campus place with sensible defaults
  static CampusPlace createPlace({
    required String id,
    required String name,
    List<String> aliases = const [],
    required LatLng location,
    required String placeType,
    String? department,
    String? description,
    int? floors,
    bool hasIndoorMap = false,
  }) {
    return CampusPlace(
      id: id,
      name: name,
      aliases: aliases,
      location: location,
      placeType: placeType,
      department: department,
      description: description,
      floors: floors,
      hasIndoorMap: hasIndoorMap,
    );
  }

  /// Create specific building types
  static CampusPlace createBuilding(
    String id,
    String name,
    LatLng location,
    String? department, {
    int floors = 3,
    bool hasIndoorMap = false,
  }) {
    return createPlace(
      id: id,
      name: name,
      location: location,
      placeType: 'building',
      department: department,
      floors: floors,
      hasIndoorMap: hasIndoorMap,
      description: '$floors-floor building',
    );
  }

  static CampusPlace createLibrary(String id, String name, LatLng location) {
    return createPlace(
      id: id,
      name: name,
      location: location,
      placeType: 'building',
      department: 'Academic Affairs',
      floors: 5,
      hasIndoorMap: true,
      description: 'Library with 5 floors',
    );
  }

  static CampusPlace createParking(String id, String name, LatLng location) {
    return createPlace(
      id: id,
      name: name,
      location: location,
      placeType: 'parking',
      description: 'Parking facility',
    );
  }

  static CampusPlace createRestroom(String id, String name, LatLng location) {
    return createPlace(
      id: id,
      name: name,
      location: location,
      placeType: 'restroom',
      description: 'Public restroom facility',
    );
  }

  static CampusPlace createLandmark(String id, String name, LatLng location) {
    return createPlace(
      id: id,
      name: name,
      location: location,
      placeType: 'landmark',
      description: 'Campus landmark',
    );
  }
}

/// Example: How to use these helpers
void exampleUsage() {
  // Create paths
  final mainPath = CampusPathHelper.createMainPath(
    'path_main_1',
    'Main Campus Walkway',
    [
      LatLng(28.5355, 77.0495),
      LatLng(28.5360, 77.0500),
      LatLng(28.5365, 77.0505),
    ],
  );

  CampusPathHelper.createHiking(
    'path_hike_1',
    'North Ridge Trail',
    [
      LatLng(28.5370, 77.0510),
      LatLng(28.5375, 77.0515),
      LatLng(28.5380, 77.0520),
    ],
  );

  // Create places
  final library = CampusPlaceHelper.createLibrary(
    'place_lib_1',
    'Central Library',
    LatLng(28.5365, 77.0505),
  );

  CampusPlaceHelper.createParking(
    'place_park_1',
    'North Lot',
    LatLng(28.5350, 77.0490),
  );

  // Use them in maps
  print('Path: ${mainPath.name}');
  print('Place: ${library.name}');
}
