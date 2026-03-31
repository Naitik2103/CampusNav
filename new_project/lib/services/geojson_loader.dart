import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/path_model.dart';
import '../models/place_model.dart';

/// Service for loading and parsing GeoJSON data
class GeoJsonLoader {
  /// Load campus paths from GeoJSON
  static Future<List<CampusPath>> loadPaths(String filePath) async {
    try {
      final jsonString = await rootBundle.loadString(filePath);
      final Map<String, dynamic> geojson = jsonDecode(jsonString);
      final List<dynamic> features = geojson['features'] ?? [];

      return features
          .cast<Map<String, dynamic>>()
          .map((feature) => CampusPath.fromGeoJson(feature))
          .toList();
    } catch (e) {
      print('Error loading paths: $e');
      return [];
    }
  }

  /// Load campus places from GeoJSON
  static Future<List<CampusPlace>> loadPlaces(String filePath) async {
    try {
      final jsonString = await rootBundle.loadString(filePath);
      final Map<String, dynamic> geojson = jsonDecode(jsonString);
      final List<dynamic> features = geojson['features'] ?? [];

      return features
          .cast<Map<String, dynamic>>()
          .map((feature) => CampusPlace.fromGeoJson(feature))
          .toList();
    } catch (e) {
      print('Error loading places: $e');
      return [];
    }
  }

  /// Convert a list of CampusPath objects to GeoJSON FeatureCollection
  static String pathsToGeoJson(List<CampusPath> paths) {
    final features = paths.map((path) => path.toGeoJson()).toList();
    final geojson = {
      'type': 'FeatureCollection',
      'features': features,
    };
    return jsonEncode(geojson);
  }

  /// Convert a list of CampusPlace objects to GeoJSON FeatureCollection
  static String placesToGeoJson(List<CampusPlace> places) {
    final features = places.map((place) => place.toGeoJson()).toList();
    final geojson = {
      'type': 'FeatureCollection',
      'features': features,
    };
    return jsonEncode(geojson);
  }
}
