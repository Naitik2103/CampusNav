import 'package:latlong2/latlong.dart';

enum WashroomType { men, women }

WashroomType? washroomTypeFromString(String? value) {
  final normalized = (value ?? '').toLowerCase().trim();
  if (normalized.isEmpty) return null;
  if (normalized == 'men' || normalized == 'mens' || normalized == 'male') {
    return WashroomType.men;
  }
  if (normalized == 'women' || normalized == 'womens' || normalized == 'female') {
    return WashroomType.women;
  }
  return null;
}

String washroomTypeLabel(WashroomType type) {
  switch (type) {
    case WashroomType.men:
      return "Men's";
    case WashroomType.women:
      return "Women's";
  }
}

class Washroom {
  final String id;
  final WashroomType type;
  final LatLng location;
  final String? building;
  final String? description;

  Washroom({
    required this.id,
    required this.type,
    required this.location,
    this.building,
    this.description,
  });

  factory Washroom.fromJson(Map<String, dynamic> json) {
    final type = washroomTypeFromString(json['type']?.toString()) ??
        WashroomType.men;
    final coord = json['coordinate'] as Map<String, dynamic>?;
    final lat = (coord?['lat'] ?? json['lat'] ?? json['latitude'] ?? 0.0)
      .toDouble();
    final lng = (coord?['lng'] ?? json['lng'] ?? json['longitude'] ?? 0.0)
      .toDouble();

    return Washroom(
      id: (json['id'] ?? '').toString(),
      type: type,
      location: LatLng(lat, lng),
      building: json['building']?.toString(),
      description: json['description']?.toString(),
    );
  }

  String get displayName {
    if (building == null || building!.trim().isEmpty) {
      return "${washroomTypeLabel(type)} Washroom";
    }
    return "${washroomTypeLabel(type)} Washroom - ${building!.trim()}";
  }
}

class WashroomDistance {
  final Washroom washroom;
  final double distanceMeters;
  final bool usesPathDistance;

  WashroomDistance({
    required this.washroom,
    required this.distanceMeters,
    required this.usesPathDistance,
  });
}
