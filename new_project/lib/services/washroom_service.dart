import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/washroom_model.dart';
import '../models/place_model.dart';

class WashroomService {
  WashroomService._();

  static final WashroomService instance = WashroomService._();

  final List<Washroom> _washrooms = [];

  List<Washroom> get washrooms => List.unmodifiable(_washrooms);

  Future<void> loadWashrooms({
    String asset = 'assets/data/washrooms.json',
  }) async {
    try {
      final jsonStr = await rootBundle.loadString(asset);
      final map = json.decode(jsonStr) as Map<String, dynamic>;
      final list = (map['washrooms'] as List<dynamic>?) ?? [];
      _washrooms.clear();
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          _washrooms.add(Washroom.fromJson(item));
        }
      }
    } catch (_) {
      _washrooms.clear();
    }
  }

  List<Washroom> filterByType(WashroomType? type) {
    if (type == null) return List<Washroom>.from(_washrooms);
    return _washrooms.where((w) => w.type == type).toList();
  }

  CampusPlace toCampusPlace(Washroom washroom) {
    final label = washroom.displayName;
    final normalizedType = washroom.type == WashroomType.men ? 'men' : 'women';

    return CampusPlace(
      id: 'washroom_${washroom.id}',
      name: label,
      aliases: <String>[
        '${normalizedType} washroom',
        "${normalizedType}'s washroom",
        '${normalizedType} restroom',
        'washroom',
        'restroom',
        'toilet',
      ],
      location: washroom.location,
      placeType: 'restroom',
      description: washroom.description,
    );
  }

  List<CampusPlace> toPlaces(List<Washroom> washrooms) {
    return washrooms.map(toCampusPlace).toList();
  }
}
