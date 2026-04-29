import 'package:latlong2/latlong.dart';

class FacultyEntry {
  final String id;
  final String name;
  final String? department;
  final String buildingId;
  final String? block;
  final String? room;
  final List<String> keywords;

  FacultyEntry({
    required this.id,
    required this.name,
    this.department,
    required this.buildingId,
    this.block,
    this.room,
    this.keywords = const [],
  });

  factory FacultyEntry.fromJson(Map<String, dynamic> json) {
    final kw =
        (json['keywords'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList() ??
        <String>[];

    return FacultyEntry(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      department: json['department'],
      buildingId: json['buildingId'] ?? '',
      block: json['block'],
      room: json['room'],
      keywords: kw,
    );
  }
}
