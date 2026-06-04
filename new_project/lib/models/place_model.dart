import 'package:latlong2/latlong.dart';

/// Represents a campus location/place (building, landmark, etc.)
class CampusPlace {
  final String id;
  final String name;
  final List<String> aliases;
  final LatLng location;
  final String placeType; // building, landmark, parking, restroom, canteen, restaurant, atm, bank, office, gate, library, pond, playground, gym, coffee_shop, cafe, music, music_room, clinic, hospital, bakery, theatre, auditorium, store_room, lab, laboratory, amul, fruit_shop, etc.
  final String? department;
  final String? description;
  final String? imageUrl;
  final int? floors;
  final bool hasIndoorMap;

  CampusPlace({
    required this.id,
    required this.name,
    this.aliases = const [],
    required this.location,
    required this.placeType,
    this.department,
    this.description,
    this.imageUrl,
    this.floors,
    this.hasIndoorMap = false,
  });

  /// Parse from GeoJSON Feature
  factory CampusPlace.fromGeoJson(Map<String, dynamic> feature) {
    final geometry = feature['geometry'] as Map<String, dynamic>;
    final properties = feature['properties'] as Map<String, dynamic>;

    // Handle Point geometry
    final List<dynamic> coordinates =
        (geometry['coordinates'] as List<dynamic>?) ?? [0, 0];
    final LatLng location = LatLng(
      (coordinates[1] as num).toDouble(),
      (coordinates[0] as num).toDouble(),
    );

    final aliasData = properties['aliases'];
    final aliases = aliasData is List
        ? aliasData.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : const <String>[];

    return CampusPlace(
      id: properties['id'] ?? 'unknown',
      name: properties['name'] ?? 'Unknown Place',
      aliases: aliases,
      location: location,
      placeType: properties['placeType'] ?? 'landmark',
      department: properties['department'],
      description: properties['description'],
      imageUrl: properties['imageUrl'],
      floors: properties['floors'],
      hasIndoorMap: properties['hasIndoorMap'] ?? false,
    );
  }

  /// Convert to GeoJSON Feature
  Map<String, dynamic> toGeoJson() {
    return {
      'type': 'Feature',
      'geometry': {
        'type': 'Point',
        'coordinates': [location.longitude, location.latitude],
      },
      'properties': {
        'id': id,
        'name': name,
        'aliases': aliases,
        'placeType': placeType,
        'department': department,
        'description': description,
        'imageUrl': imageUrl,
        'floors': floors,
        'hasIndoorMap': hasIndoorMap,
      },
    };
  }
}
