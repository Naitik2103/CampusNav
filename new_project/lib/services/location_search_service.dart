import 'package:latlong2/latlong.dart';
import '../models/place_model.dart';

/// Service for location search with auto-complete and nearby places
class LocationSearchService {
  /// Search places by name or department
  static List<CampusPlace> searchPlaces(
    String query,
    List<CampusPlace> allPlaces,
  ) {
    if (query.isEmpty) {
      return allPlaces;
    }

    final lowerQuery = query.toLowerCase();

    return allPlaces.where((place) {
      return place.name.toLowerCase().contains(lowerQuery) ||
          (place.department?.toLowerCase().contains(lowerQuery) ?? false) ||
          (place.placeType.toLowerCase().contains(lowerQuery));
    }).toList();
  }

  /// Get auto-complete suggestions
  static List<String> getAutocompleteSuggestions(
    String query,
    List<CampusPlace> allPlaces,
  ) {
    if (query.isEmpty) {
      return [];
    }

    final lowerQuery = query.toLowerCase();
    final suggestions = <String>{};

    for (final place in allPlaces) {
      if (place.name.toLowerCase().startsWith(lowerQuery)) {
        suggestions.add(place.name);
      }
      if (place.department != null &&
          place.department!.toLowerCase().startsWith(lowerQuery)) {
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
    return allPlaces
        .where((place) =>
            place.placeType.toLowerCase() == placeType.toLowerCase())
        .toList();
  }

  /// Search by department
  static List<CampusPlace> searchByDepartment(
    String department,
    List<CampusPlace> allPlaces,
  ) {
    return allPlaces
        .where((place) =>
            place.department?.toLowerCase() == department.toLowerCase())
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
    final lowerQuery = query.toLowerCase();

    // Sort by relevance:
    // 1. Exact name match first
    // 2. Name starts with query
    // 3. Contains query in name
    // 4. Contains query in department

    results.sort((a, b) {
      final aNameLower = a.name.toLowerCase();
      final bNameLower = b.name.toLowerCase();

      // Exact match
      if (aNameLower == lowerQuery && bNameLower != lowerQuery) return -1;
      if (bNameLower == lowerQuery && aNameLower != lowerQuery) return 1;

      // Starts with query
      if (aNameLower.startsWith(lowerQuery) &&
          !bNameLower.startsWith(lowerQuery)) {
        return -1;
      }
      if (bNameLower.startsWith(lowerQuery) &&
          !aNameLower.startsWith(lowerQuery)) {
        return 1;
      }

      // Contains query in name
      if (aNameLower.contains(lowerQuery) &&
          !bNameLower.contains(lowerQuery)) {
        return -1;
      }
      if (bNameLower.contains(lowerQuery) &&
          !aNameLower.contains(lowerQuery)) {
        return 1;
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
