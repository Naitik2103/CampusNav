import 'package:latlong2/latlong.dart';
import '../models/place_model.dart';

/// Service for location search with auto-complete and nearby places
class LocationSearchService {
  static Iterable<String> _placeNames(CampusPlace place) {
    return <String>[place.name, ...place.aliases];
  }

  static String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static int _bestNameMatchScore(CampusPlace place, String normalizedQuery) {
    var bestScore = 0;

    for (final name in _placeNames(place)) {
      final normalizedName = _normalize(name);
      if (normalizedName == normalizedQuery) {
        return 3;
      }
      if (normalizedName.startsWith(normalizedQuery) && bestScore < 2) {
        bestScore = 2;
      } else if (normalizedName.contains(normalizedQuery) && bestScore < 1) {
        bestScore = 1;
      }
    }

    return bestScore;
  }

  /// Search places by name or department
  static List<CampusPlace> searchPlaces(
    String query,
    List<CampusPlace> allPlaces,
  ) {
    if (query.trim().isEmpty) {
      return allPlaces;
    }

    final normalizedQuery = _normalize(query);

    return allPlaces.where((place) {
      final hasNameMatch = _placeNames(
        place,
      ).any((name) => _normalize(name).contains(normalizedQuery));

      return hasNameMatch ||
          (_normalize(place.department ?? '').contains(normalizedQuery)) ||
          _normalize(place.placeType).contains(normalizedQuery);
    }).toList();
  }

  /// Get auto-complete suggestions
  static List<String> getAutocompleteSuggestions(
    String query,
    List<CampusPlace> allPlaces,
  ) {
    if (query.trim().isEmpty) {
      return [];
    }

    final normalizedQuery = _normalize(query);
    final suggestions = <String>{};

    for (final place in allPlaces) {
      for (final name in _placeNames(place)) {
        if (_normalize(name).startsWith(normalizedQuery)) {
          suggestions.add(name);
        }
      }
      if (place.department != null &&
          _normalize(place.department!).startsWith(normalizedQuery)) {
        suggestions.add(place.department!);
      }
    }

    return suggestions.toList()..sort();
  }

  /// Find nearby places
  static List<CampusPlace> findNearbyPlaces(
    LatLng location,
    List<CampusPlace> allPlaces, {
    double radiusKm = 0.5,
  }) {
    final distance = const Distance();
    final nearby = <CampusPlace>[];

    for (final place in allPlaces) {
      final distanceToPlace = distance(location, place.location);
      if (distanceToPlace <= radiusKm) {
        nearby.add(place);
      }
    }

    // Sort by distance
    nearby.sort((a, b) {
      final distA = distance(location, a.location);
      final distB = distance(location, b.location);
      return distA.compareTo(distB);
    });

    return nearby;
  }

  /// Find nearby places with details
  static List<PlaceDistance> findNearbyPlacesWithDistance(
    LatLng location,
    List<CampusPlace> allPlaces, {
    double radiusKm = 0.5,
  }) {
    final distance = const Distance();
    final nearby = <PlaceDistance>[];

    for (final place in allPlaces) {
      final distanceToPlace = distance(location, place.location);
      if (distanceToPlace <= radiusKm) {
        nearby.add(
          PlaceDistance(
            place: place,
            distanceKm: distanceToPlace,
            distanceM: distanceToPlace * 1000,
          ),
        );
      }
    }

    // Sort by distance
    nearby.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

    return nearby;
  }

  /// Search by place type (building, parking, restroom, etc.)
  static List<CampusPlace> searchByType(
    String placeType,
    List<CampusPlace> allPlaces,
  ) {
    final normalizedType = _normalize(placeType);
    return allPlaces
        .where((place) => _normalize(place.placeType) == normalizedType)
        .toList();
  }

  /// Search by department
  static List<CampusPlace> searchByDepartment(
    String department,
    List<CampusPlace> allPlaces,
  ) {
    final normalizedDepartment = _normalize(department);
    return allPlaces
        .where((place) =>
            _normalize(place.department ?? '') == normalizedDepartment)
        .toList();
  }

  /// Get all departments (for filtering)
  static List<String> getAllDepartments(List<CampusPlace> allPlaces) {
    final departments = <String>{};
    for (final place in allPlaces) {
      if (place.department != null) {
        departments.add(place.department!);
      }
    }
    return departments.toList()..sort();
  }

  /// Get all place types (for filtering)
  static List<String> getAllPlaceTypes(List<CampusPlace> allPlaces) {
    final types = <String>{};
    for (final place in allPlaces) {
      types.add(place.placeType);
    }
    return types.toList()..sort();
  }

  /// Rank results by search quality
  static List<CampusPlace> rankResults(
    String query,
    List<CampusPlace> results,
  ) {
    final normalizedQuery = _normalize(query);

    // Sort by relevance:
    // 1. Exact name match first
    // 2. Name starts with query
    // 3. Contains query in name
    // 4. Contains query in department

    results.sort((a, b) {
      final aScore = _bestNameMatchScore(a, normalizedQuery);
      final bScore = _bestNameMatchScore(b, normalizedQuery);
      if (aScore != bScore) {
        return bScore.compareTo(aScore);
      }

      return 0;
    });

    return results;
  }
}

/// Model for nearby places with distance information
class PlaceDistance {
  final CampusPlace place;
  final double distanceKm;
  final double distanceM;

  PlaceDistance({
    required this.place,
    required this.distanceKm,
    required this.distanceM,
  });

  String getFormattedDistance() {
    if (distanceM < 1000) {
      return '${distanceM.toStringAsFixed(0)}m';
    }
    return '${distanceKm.toStringAsFixed(2)}km';
  }
}
