// Campus Configuration
// Update these values with your actual campus boundaries

import 'package:latlong2/latlong.dart';

class CampusConfig {
  /// Campus center coordinate (Update with your campus center)
  static const LatLng campusCenter = LatLng(23.188382, 72.628233);

  /// Campus radius in kilometers
  static const double campusRadiusKm = 1.5;

  /// Campus boundary polygon (Update with your actual campus corners)
  /// Order: NorthEast → NorthWest → SouthWest → SouthEast (counterclockwise)
  ///
  /// HOW TO UPDATE:
  /// 1. Open your campus map (use Google Maps)
  /// 2. Identify the four corners of your campus (NE, NW, SW, SE)
  /// 3. Note down the latitude and longitude for each corner
  /// 4. Replace the coordinates below
  ///
  /// Example for a rectangular campus:
  /// NorthEast corner: 28.5370, 77.0515 (top-right)
  /// NorthWest corner: 28.5370, 77.0495 (top-left)
  /// SouthWest corner: 28.5350, 77.0495 (bottom-left)
  /// SouthEast corner: 28.5350, 77.0515 (bottom-right)
  static const List<LatLng> campusBoundary = [
    LatLng(23.190, 72.630),  // Northeast corner
    LatLng(23.190, 72.627),  // Northwest corner
    LatLng(23.186, 72.627),  // Southwest corner
    LatLng(23.186, 72.630),  // Southeast corner
  ];

  /// Maximum allowed deviation from campus (in degrees)
  /// If a waypoint is beyond this, it will be snapped to campus boundary
  static const double maxAllowedDeviation = 0.01; // ~1 km

  /// Check if the boundaries are correctly configured
  static bool isBoundaryValid() {
    if (campusBoundary.length != 4) {
      print('❌ Campus boundary must have exactly 4 corners, found ${campusBoundary.length}');
      return false;
    }

    // Print current boundaries for debugging
    print('📍 Current Campus Boundaries:');
    print('   NorthEast: ${campusBoundary[0]}');
    print('   NorthWest: ${campusBoundary[1]}');
    print('   SouthWest: ${campusBoundary[2]}');
    print('   SouthEast: ${campusBoundary[3]}');

    return true;
  }

  /// Print campus configuration
  static void printConfiguration() {
    print('🏫 Campus Configuration:');
    print('   Center: $campusCenter');
    print('   Radius: ${campusRadiusKm}km');
    isBoundaryValid();
  }

  /// Helper: Calculate bounds from boundary
  static Map<String, double> getBounds() {
    double minLat = campusBoundary.first.latitude;
    double maxLat = campusBoundary.first.latitude;
    double minLng = campusBoundary.first.longitude;
    double maxLng = campusBoundary.first.longitude;

    for (final point in campusBoundary) {
      minLat = minLat > point.latitude ? point.latitude : minLat;
      maxLat = maxLat < point.latitude ? point.latitude : maxLat;
      minLng = minLng > point.longitude ? point.longitude : minLng;
      maxLng = maxLng < point.longitude ? point.longitude : maxLng;
    }

    return {
      'minLat': minLat,
      'maxLat': maxLat,
      'minLng': minLng,
      'maxLng': maxLng,
    };
  }
}
