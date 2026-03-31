import 'package:latlong2/latlong.dart';

/// Represents a campus path with metadata
class CampusPath {
  final String id;
  final String name;
  final List<LatLng> coordinates;
  final bool walkable;
  final String pathType; // concrete, grass, asphalt, etc.
  final String difficulty; // easy, medium, hard
  final bool wheelchairAccessible;
  final String? restrictions; // no_vehicles, no_bikes, etc.
  final String? description;

  CampusPath({
    required this.id,
    required this.name,
    required this.coordinates,
    required this.walkable,
    required this.pathType,
    required this.difficulty,
    required this.wheelchairAccessible,
    this.restrictions,
    this.description,
  });

  /// Parse from GeoJSON Feature
  factory CampusPath.fromGeoJson(Map<String, dynamic> feature) {
    final geometry = feature['geometry'] as Map<String, dynamic>;
    final properties = feature['properties'] as Map<String, dynamic>;

    // Handle LineString geometry
    final List<dynamic> coordinates =
        (geometry['coordinates'] as List<dynamic>?) ?? [];
    final List<LatLng> latLngs = coordinates
        .map((coord) => LatLng(
              (coord[1] as num).toDouble(),
              (coord[0] as num).toDouble(),
            ))
        .toList();

    return CampusPath(
      id: properties['id'] ?? 'unknown',
      name: properties['name'] ?? 'Unknown Path',
      coordinates: latLngs,
      walkable: properties['walkable'] ?? true,
      pathType: properties['pathType'] ?? 'concrete',
      difficulty: properties['difficulty'] ?? 'easy',
      wheelchairAccessible: properties['wheelchair_accessible'] ?? false,
      restrictions: properties['restrictions'],
      description: properties['description'],
    );
  }

  /// Convert to GeoJSON Feature
  Map<String, dynamic> toGeoJson() {
    return {
      'type': 'Feature',
      'geometry': {
        'type': 'LineString',
        'coordinates': coordinates
            .map((coord) => [coord.longitude, coord.latitude])
            .toList(),
      },
      'properties': {
        'id': id,
        'name': name,
        'walkable': walkable,
        'pathType': pathType,
        'difficulty': difficulty,
        'wheelchair_accessible': wheelchairAccessible,
        'restrictions': restrictions,
        'description': description,
      },
    };
  }
}
