import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/faculty_model.dart';
import 'package:latlong2/latlong.dart';

class _FacultyBlock {
  final String buildingId;
  final String blockId;
  final String name;
  final LatLng coordinate;
  final List<String> departments;

  _FacultyBlock({
    required this.buildingId,
    required this.blockId,
    required this.name,
    required this.coordinate,
    this.departments = const [],
  });

  factory _FacultyBlock.fromJson(Map<String, dynamic> json) {
    final coord = json['coordinate'] as Map<String, dynamic>?;
    return _FacultyBlock(
      buildingId: (json['buildingId'] ?? '') as String,
      blockId: (json['blockId'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      coordinate: LatLng(
        (coord?['lat'] ?? 0.0).toDouble(),
        (coord?['lng'] ?? 0.0).toDouble(),
      ),
      departments:
          (json['departments'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

class FacultyService {
  FacultyService._();

  static final FacultyService instance = FacultyService._();

  final List<FacultyEntry> _entries = [];
  final List<_FacultyBlock> _blocks = [];

  List<FacultyEntry> get entries => List.unmodifiable(_entries);

  Future<void> loadFacultyDirectory({
    String asset = 'assets/data/faculty_directory.json',
  }) async {
    try {
      final jsonStr = await rootBundle.loadString(asset);
      final map = json.decode(jsonStr) as Map<String, dynamic>;
      final list = (map['faculty'] as List<dynamic>?) ?? [];
      _entries.clear();
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          _entries.add(FacultyEntry.fromJson(item));
        }
      }
      // Try to load optional blocks file
      try {
        final blocksStr = await rootBundle.loadString(
          'assets/data/faculty_blocks.json',
        );
        final bmap = json.decode(blocksStr) as Map<String, dynamic>;
        final blist = (bmap['blocks'] as List<dynamic>?) ?? [];
        _blocks.clear();
        for (final b in blist) {
          if (b is Map<String, dynamic>) {
            _blocks.add(_FacultyBlock.fromJson(b));
          }
        }
      } catch (e) {
        // ignore missing blocks
      }
    } catch (e) {
      // ignore and keep empty
    }
  }

  LatLng? getBlockCoordinate(String buildingId, String blockId) {
    final keyB = _normalize(buildingId);
    final keyBlock = _normalize(blockId);
    for (final b in _blocks) {
      if (_normalize(b.buildingId) == keyB &&
          _normalize(b.blockId) == keyBlock) {
        return b.coordinate;
      }
    }
    return null;
  }

  LatLng? getBlockForDepartment(String buildingId, String department) {
    final keyB = _normalize(buildingId);
    final keyDept = _normalize(department);
    for (final b in _blocks) {
      if (_normalize(b.buildingId) == keyB) {
        for (final d in b.departments) {
          if (_normalize(d) == keyDept) return b.coordinate;
        }
      }
    }
    return null;
  }

  List<FacultyEntry> searchFaculty(String query, {int limit = 20}) {
    final q = _normalize(query);
    if (q.isEmpty) return [];

    final matches = _entries.where((f) {
      final nameKey = _normalize(f.name);
      final idKey = _normalize(f.id);
      final deptKey = _normalize(f.department ?? '');
      final buildingKey = _normalize(f.buildingId);
      final kw = f.keywords.map(_normalize).join(' ');
      return nameKey.contains(q) ||
          idKey.contains(q) ||
          deptKey.contains(q) ||
          buildingKey.contains(q) ||
          kw.contains(q);
    }).toList();

    return matches.take(limit).toList();
  }

  String _normalize(String? s) {
    if (s == null) return '';
    return s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}
