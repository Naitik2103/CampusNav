import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../models/indoor_models.dart';
import '../services/indoor_navigation_service.dart';

class IndoorNavigationScreen extends StatefulWidget {
  final IndoorBuilding building;
  final int? initialFloor;
  final LatLng? currentGpsLocation;

  const IndoorNavigationScreen({
    super.key,
    required this.building,
    this.initialFloor,
    this.currentGpsLocation,
  });

  @override
  State<IndoorNavigationScreen> createState() => _IndoorNavigationScreenState();
}

class _IndoorNavigationScreenState extends State<IndoorNavigationScreen> {
  late int _selectedFloor;
  IndoorRoom? _selectedRoom;
  String? _transitionHint;

  @override
  void initState() {
    super.initState();
    _selectedFloor = widget.initialFloor ?? widget.building.groundFloor;
    if (!widget.building.floors.contains(_selectedFloor)) {
      _selectedFloor = widget.building.groundFloor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rooms = IndoorNavigationService.instance.getRoomsForFloor(
      widget.building.buildingId,
      _selectedFloor,
    );

    return Scaffold(
      appBar: AppBar(title: Text('${widget.building.name} Indoor Navigation')),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                children: [
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: IndoorFloorPlanCanvas(
                          building: widget.building,
                          floor: _selectedFloor,
                          rooms: rooms,
                          selectedRoom: _selectedRoom,
                          onRoomTap: _onRoomSelected,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Card(
                      child: rooms.isEmpty
                          ? const Center(
                              child: Text(
                                'No room coordinates configured for this floor.',
                              ),
                            )
                          : ListView.builder(
                              itemCount: rooms.length,
                              itemBuilder: (context, index) {
                                final room = rooms[index];
                                final isSelected = _selectedRoom?.id == room.id;

                                return ListTile(
                                  title: Text(room.name),
                                  subtitle: Text(
                                    '${room.category} • Floor ${room.floor}',
                                  ),
                                  trailing: isSelected
                                      ? const Icon(
                                          Icons.check_circle,
                                          color: Colors.green,
                                        )
                                      : null,
                                  onTap: () => _onRoomSelected(room),
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: const Color(0xFFF5F7FB),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ground floor is shown first when you enter a building.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<int>(
                value: _selectedFloor,
                items: widget.building.floors
                    .map(
                      (floor) => DropdownMenuItem<int>(
                        value: floor,
                        child: Text('Floor $floor'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedFloor = value;
                    _selectedRoom = null;
                    _transitionHint = null;
                  });
                },
              ),
              if (_transitionHint != null)
                Chip(
                  label: Text(_transitionHint!),
                  backgroundColor: const Color(0xFFE7F1FF),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _onRoomSelected(IndoorRoom room) {
    final suggestion = IndoorNavigationService.instance.suggestRouteToRoom(
      building: widget.building,
      fromFloor: _selectedFloor,
      room: room,
    );

    if (suggestion == null) {
      return;
    }

    var nextHint = 'Room ${room.name} is on Floor ${room.floor}';
    var nextFloor = _selectedFloor;

    if (suggestion.requiresFloorTransition) {
      final transitionLabel =
          suggestion.transitionPoint?.label ?? 'nearest staircase/elevator';
      nextHint =
          'Switch from Floor ${suggestion.fromFloor} to Floor ${suggestion.toFloor} via $transitionLabel';
      nextFloor = room.floor;
    }

    setState(() {
      _selectedRoom = room;
      _selectedFloor = nextFloor;
      _transitionHint = nextHint;
    });
  }
}

class IndoorFloorPlanCanvas extends StatelessWidget {
  final IndoorBuilding building;
  final int floor;
  final List<IndoorRoom> rooms;
  final IndoorRoom? selectedRoom;
  final ValueChanged<IndoorRoom> onRoomTap;

  const IndoorFloorPlanCanvas({
    super.key,
    required this.building,
    required this.floor,
    required this.rooms,
    required this.selectedRoom,
    required this.onRoomTap,
  });

  @override
  Widget build(BuildContext context) {
    final bounds = _getBounds(building.boundary);
    final transitions = building.transitionPoints.where(
      (point) => point.floors.contains(floor),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _FloorPlanPainter(
                boundary: building.boundary,
                rooms: rooms,
                transitions: transitions.toList(),
                selectedRoom: selectedRoom,
                bounds: bounds,
              ),
            ),
            ...rooms.map((room) {
              final offset = _project(
                room.coordinate,
                bounds,
                constraints.maxWidth,
                constraints.maxHeight,
              );

              return Positioned(
                left: offset.dx - 8,
                top: offset.dy - 8,
                child: GestureDetector(
                  onTap: () => onRoomTap(room),
                  child: const SizedBox(width: 22, height: 22),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Rect _getBounds(List<LatLng> points) {
    final minLat = points
        .map((e) => e.latitude)
        .reduce((a, b) => a < b ? a : b);
    final maxLat = points
        .map((e) => e.latitude)
        .reduce((a, b) => a > b ? a : b);
    final minLng = points
        .map((e) => e.longitude)
        .reduce((a, b) => a < b ? a : b);
    final maxLng = points
        .map((e) => e.longitude)
        .reduce((a, b) => a > b ? a : b);

    return Rect.fromLTRB(minLng, minLat, maxLng, maxLat);
  }

  Offset _project(LatLng coordinate, Rect bounds, double width, double height) {
    final safeWidth = (bounds.width).abs() < 1e-8 ? 1e-8 : bounds.width;
    final safeHeight = (bounds.height).abs() < 1e-8 ? 1e-8 : bounds.height;

    // Mirror across vertical axis (left-right flip).
    final x = 1 - ((coordinate.longitude - bounds.left) / safeWidth);
    final y = (coordinate.latitude - bounds.top) / safeHeight;

    const pad = 18.0;
    return Offset(
      pad + x * (width - (pad * 2)),
      pad + y * (height - (pad * 2)),
    );
  }
}

class _FloorPlanPainter extends CustomPainter {
  final List<LatLng> boundary;
  final List<IndoorRoom> rooms;
  final List<IndoorTransitionPoint> transitions;
  final IndoorRoom? selectedRoom;
  final Rect bounds;

  _FloorPlanPainter({
    required this.boundary,
    required this.rooms,
    required this.transitions,
    required this.selectedRoom,
    required this.bounds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintBoundary = Paint()
      ..color = const Color(0xFF0B5FFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    final fillBoundary = Paint()
      ..color = const Color(0xFFDCE8FF)
      ..style = PaintingStyle.fill;

    final roomPaint = Paint()
      ..color = const Color(0xFF1D4ED8)
      ..style = PaintingStyle.fill;

    final selectedPaint = Paint()
      ..color = const Color(0xFFEF4444)
      ..style = PaintingStyle.fill;

    final transitionPaint = Paint()
      ..color = const Color(0xFFEA580C)
      ..style = PaintingStyle.fill;

    final path = Path();
    for (var i = 0; i < boundary.length; i++) {
      final point = _project(boundary[i], size);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();

    canvas.drawPath(path, fillBoundary);
    canvas.drawPath(path, paintBoundary);

    for (final room in rooms) {
      final center = _project(room.coordinate, size);
      final isSelected = selectedRoom?.id == room.id;
      canvas.drawCircle(
        center,
        isSelected ? 7 : 5,
        isSelected ? selectedPaint : roomPaint,
      );
    }

    for (final transition in transitions) {
      final center = _project(transition.coordinate, size);
      canvas.drawRect(
        Rect.fromCenter(center: center, width: 10, height: 10),
        transitionPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FloorPlanPainter oldDelegate) {
    return oldDelegate.rooms != rooms ||
        oldDelegate.selectedRoom?.id != selectedRoom?.id ||
        oldDelegate.transitions.length != transitions.length;
  }

  Offset _project(LatLng coordinate, Size size) {
    final safeWidth = (bounds.width).abs() < 1e-8 ? 1e-8 : bounds.width;
    final safeHeight = (bounds.height).abs() < 1e-8 ? 1e-8 : bounds.height;

    // Mirror across vertical axis (left-right flip).
    final x = 1 - ((coordinate.longitude - bounds.left) / safeWidth);
    final y = (coordinate.latitude - bounds.top) / safeHeight;

    const pad = 18.0;
    return Offset(
      pad + x * (size.width - (pad * 2)),
      pad + y * (size.height - (pad * 2)),
    );
  }
}
