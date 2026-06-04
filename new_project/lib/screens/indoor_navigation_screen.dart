import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../models/indoor_models.dart';
import '../services/indoor_navigation_service.dart';

class IndoorNavigationScreen extends StatefulWidget {
  final IndoorBuilding building;
  final int? initialFloor;
  final LatLng? currentGpsLocation;
  final IndoorRoom? targetRoom; // PRE-SELECTED DESTINATION

  const IndoorNavigationScreen({
    super.key,
    required this.building,
    this.initialFloor,
    this.currentGpsLocation,
    this.targetRoom,
  });

  @override
  State<IndoorNavigationScreen> createState() => _IndoorNavigationScreenState();
}

class _IndoorNavigationScreenState extends State<IndoorNavigationScreen> {
  late int _selectedFloor;
  IndoorRoom? _selectedRoom;
  String? _transitionHint;
  List<LatLng> _routePolyline = [];

  @override
  void initState() {
    super.initState();
    // Default to target room's floor if available, otherwise fallback
    _selectedFloor = widget.targetRoom?.floor ?? widget.initialFloor ?? widget.building.groundFloor;
    if (!widget.building.floors.contains(_selectedFloor)) {
      _selectedFloor = widget.building.groundFloor;
    }

    if (widget.targetRoom != null) {
      _selectedRoom = widget.targetRoom;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onRoomSelected(widget.targetRoom!);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rooms = IndoorNavigationService.instance.getRoomsForFloor(
      widget.building.buildingId,
      _selectedFloor,
    );
    final graphLines = IndoorNavigationService.instance.getIndoorGraphLines(
      buildingId: widget.building.buildingId,
      floor: _selectedFloor,
    );
    final showGraphAsRoute = _selectedRoom != null;

    // Get the entrance coordinate of the ground floor to highlight it as "You are here" using the nearest building gate
    final entryPoint = _selectedFloor == widget.building.groundFloor
        ? IndoorNavigationService.instance.getEntryNodeCoordinate(
            buildingId: widget.building.buildingId,
            floor: _selectedFloor,
            referenceLocation: widget.currentGpsLocation,
          )
        : null;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.building.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const Text(
              'Indoor Navigation',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0B5FFF), Color(0xFF4F46E5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 4,
      ),
      body: Column(
        children: [
          _buildHeaderControlPanel(colors),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                children: [
                  // Interactive Canvas Card
                  Expanded(
                    flex: 11,
                    child: Card(
                      elevation: 4,
                      shadowColor: Colors.black12,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            _buildLegend(),
                            const SizedBox(height: 8),
                            Expanded(
                              child: IndoorFloorPlanCanvas(
                                building: widget.building,
                                floor: _selectedFloor,
                                rooms: rooms,
                                selectedRoom: _selectedRoom,
                                graphLines: graphLines,
                                showGraphAsRoute: showGraphAsRoute,
                                routePolyline: _routePolyline,
                                onRoomTap: _onRoomSelected,
                                entryPoint: entryPoint,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Room List Container
                  Expanded(
                    flex: 9,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              color: const Color(0xFFF1F5F9),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Available Rooms (${rooms.length})',
                                    style: const TextStyle(
                                      color: Color(0xFF1E293B),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (_selectedRoom != null)
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _selectedRoom = null;
                                          _transitionHint = null;
                                          _routePolyline = [];
                                        });
                                      },
                                      child: const Text('Clear path'),
                                    ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: rooms.isEmpty
                                  ? const Center(
                                      child: Text(
                                        'No room coordinates configured for this floor.',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    )
                                  : ListView.builder(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      itemCount: rooms.length,
                                      itemBuilder: (context, index) {
                                        final room = rooms[index];
                                        final isSelected = _selectedRoom?.id == room.id;
                                        return _buildRoomItem(room, isSelected);
                                      },
                                    ),
                            ),
                          ],
                        ),
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

  Widget _buildHeaderControlPanel(ColorScheme colors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SELECT FLOOR',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
              letterSpacing: 1.2,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          _buildFloorSelector(colors),
          if (_transitionHint != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFC7D2FE),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.directions_rounded,
                    color: Color(0xFF4F46E5),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _transitionHint!,
                      style: const TextStyle(
                        color: Color(0xFF3730A3),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFloorSelector(ColorScheme colors) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: widget.building.floors.map((floor) {
          final isSelected = _selectedFloor == floor;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedFloor = floor;
                  _selectedRoom = null;
                  _transitionHint = null;
                  _routePolyline = [];
                });
              },
              borderRadius: BorderRadius.circular(24),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF0B5FFF) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF0B5FFF).withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          )
                        ]
                      : [],
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.layers_rounded,
                      size: 16,
                      color: isSelected ? Colors.white : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      floor == 0 ? 'Ground Floor (L0)' : 'Floor $floor',
                      style: TextStyle(
                        color: isSelected ? Colors.white : const Color(0xFF1E293B),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLegend() {
    final showYouAreHere = _selectedFloor == widget.building.groundFloor;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (showYouAreHere)
            Row(
              children: [
                const Icon(Icons.circle, color: Color(0xFF10B981), size: 12),
                const SizedBox(width: 6),
                Text(
                  'You are here',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
                ),
              ],
            ),
          Row(
            children: [
              const Icon(Icons.circle, color: Color(0xFFEF4444), size: 12),
              const SizedBox(width: 6),
              Text(
                'Room Door',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
              ),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.crop_square_rounded, color: Color(0xFF2563EB), size: 14),
              const SizedBox(width: 6),
              Text(
                'Stairs',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _getRoomIcon(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('lab') || cat.contains('computer')) return Icons.computer_rounded;
    if (cat.contains('seminar') || cat.contains('conference') || cat.contains('meeting')) return Icons.groups_rounded;
    if (cat.contains('classroom') || cat.contains('class') || cat.contains('studio')) return Icons.school_rounded;
    if (cat.contains('office') || cat.contains('admin')) return Icons.admin_panel_settings_rounded;
    if (cat.contains('security')) return Icons.security_rounded;
    if (cat.contains('electrical') || cat.contains('server')) return Icons.developer_board_rounded;
    return Icons.meeting_room_rounded;
  }

  Color _getRoomColor(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('lab') || cat.contains('computer')) return const Color(0xFF0F766E); // Teal
    if (cat.contains('seminar') || cat.contains('conference') || cat.contains('meeting')) return const Color(0xFF6B21A8); // Purple
    if (cat.contains('classroom') || cat.contains('class') || cat.contains('studio')) return const Color(0xFF1E3A8A); // Indigo
    if (cat.contains('office') || cat.contains('admin')) return const Color(0xFFB45309); // Amber
    if (cat.contains('security')) return const Color(0xFF334155); // Slate
    return const Color(0xFF0B5FFF); // Default Blue
  }

  Widget _buildRoomItem(IndoorRoom room, bool isSelected) {
    final roomColor = _getRoomColor(room.category);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      elevation: isSelected ? 4 : 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? const Color(0xFF0B5FFF) : Colors.grey.shade200,
          width: isSelected ? 2 : 1,
        ),
      ),
      color: isSelected ? const Color(0xFFEEF2FF) : Colors.white,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: roomColor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(_getRoomIcon(room.category), color: roomColor, size: 20),
        ),
        title: Text(
          room.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          room.category,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle_rounded, color: Color(0xFF0B5FFF))
            : const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Colors.grey),
        onTap: () => _onRoomSelected(room),
      ),
    );
  }

  void _onRoomSelected(IndoorRoom room) {
    // Generate route polyline filtered specifically for the current/selected floor!
    final routePolyline = widget.currentGpsLocation != null
        ? IndoorNavigationService.instance.getIndoorRoutePolylineFromLocation(
            building: widget.building,
            startLocation: widget.currentGpsLocation!,
            destinationRoom: room,
            fromFloor: _selectedFloor,
            filterFloor: _selectedFloor,
          )
        : IndoorNavigationService.instance.getIndoorRoutePolyline(
            building: widget.building,
            destinationRoom: room,
            fromFloor: _selectedFloor,
            filterFloor: _selectedFloor,
          );

    final suggestion = IndoorNavigationService.instance.suggestRouteToRoom(
      building: widget.building,
      fromFloor: _selectedFloor,
      room: room,
    );

    if (suggestion == null) {
      return;
    }

    var nextHint = widget.currentGpsLocation != null
        ? 'Route active from entrance to room ${room.name}.'
        : 'Follow path from entrance directly to ${room.name}.';
    var nextFloor = _selectedFloor;

    if (suggestion.requiresFloorTransition) {
      final transitionLabel =
          suggestion.transitionPoint?.label ?? 'nearest staircase';
      nextHint =
          'Go to $transitionLabel and switch to Floor ${suggestion.toFloor} to reach ${room.name}.';
    }

    setState(() {
      _selectedRoom = room;
      _selectedFloor = nextFloor;
      _transitionHint = nextHint;
      _routePolyline = routePolyline;
    });
  }
}

class IndoorFloorPlanCanvas extends StatefulWidget {
  final IndoorBuilding building;
  final int floor;
  final List<IndoorRoom> rooms;
  final IndoorRoom? selectedRoom;
  final List<List<LatLng>> graphLines;
  final bool showGraphAsRoute;
  final List<LatLng> routePolyline;
  final ValueChanged<IndoorRoom> onRoomTap;
  final LatLng? entryPoint;

  const IndoorFloorPlanCanvas({
    super.key,
    required this.building,
    required this.floor,
    required this.rooms,
    required this.selectedRoom,
    required this.graphLines,
    required this.showGraphAsRoute,
    required this.routePolyline,
    required this.onRoomTap,
    this.entryPoint,
  });

  @override
  State<IndoorFloorPlanCanvas> createState() => _IndoorFloorPlanCanvasState();
}

class _IndoorFloorPlanCanvasState extends State<IndoorFloorPlanCanvas> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bounds = _getBounds(widget.building.boundary);
    final transitions = widget.building.transitionPoints.where(
      (point) => point.floors.contains(widget.floor),
    );

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                CustomPaint(
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                  painter: _FloorPlanPainter(
                    boundary: widget.building.boundary,
                    rooms: widget.rooms,
                    transitions: transitions.toList(),
                    selectedRoom: widget.selectedRoom,
                    graphLines: widget.graphLines,
                    showGraphAsRoute: widget.showGraphAsRoute,
                    routePolyline: widget.routePolyline,
                    bounds: bounds,
                    entryPoint: widget.entryPoint,
                    pulseValue: _pulseController.value,
                  ),
                ),
                ...widget.rooms.map((room) {
                  final offset = _project(
                    room.coordinate,
                    bounds,
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );

                  return Positioned(
                    left: offset.dx - 12,
                    top: offset.dy - 12,
                    child: GestureDetector(
                      onTap: () => widget.onRoomTap(room),
                      child: Container(
                        width: 24,
                        height: 24,
                        color: Colors.transparent,
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }

  Rect _getBounds(List<LatLng> points) {
    if (points.isEmpty) return Rect.zero;
    final minLat = points.map((e) => e.latitude).reduce((a, b) => a < b ? a : b);
    final maxLat = points.map((e) => e.latitude).reduce((a, b) => a > b ? a : b);
    final minLng = points.map((e) => e.longitude).reduce((a, b) => a < b ? a : b);
    final maxLng = points.map((e) => e.longitude).reduce((a, b) => a > b ? a : b);

    return Rect.fromLTRB(minLng, minLat, maxLng, maxLat);
  }

  Offset _project(LatLng coordinate, Rect bounds, double width, double height) {
    final safeWidth = (bounds.width).abs() < 1e-8 ? 1e-8 : bounds.width;
    final safeHeight = (bounds.height).abs() < 1e-8 ? 1e-8 : bounds.height;

    final x = (coordinate.longitude - bounds.left) / safeWidth;
    final y = 1 - ((coordinate.latitude - bounds.top) / safeHeight);

    const pad = 24.0;
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
  final List<List<LatLng>> graphLines;
  final bool showGraphAsRoute;
  final List<LatLng> routePolyline;
  final Rect bounds;
  final LatLng? entryPoint;
  final double pulseValue;

  _FloorPlanPainter({
    required this.boundary,
    required this.rooms,
    required this.transitions,
    required this.selectedRoom,
    required this.graphLines,
    required this.showGraphAsRoute,
    required this.routePolyline,
    required this.bounds,
    this.entryPoint,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (boundary.isEmpty) return;

    final paintBoundary = Paint()
      ..color = const Color(0xFF4F46E5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    final fillBoundary = Paint()
      ..color = const Color(0xFFEEF2FF)
      ..style = PaintingStyle.fill;

    final roomPaint = Paint()
      ..color = const Color(0xFFEF4444)
      ..style = PaintingStyle.fill;

    final selectedPaint = Paint()
      ..color = const Color(0xFFFF0000)
      ..style = PaintingStyle.fill;

    final transitionPaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.fill;

    final graphPaint = Paint()
      ..color = const Color(0xFF94A3B8).withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final routePaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;

    // Draw building floor boundary
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

    // Draw general graph connections
    for (final segment in graphLines) {
      if (segment.length < 2) continue;
      final graphPath = Path();
      for (var i = 0; i < segment.length; i++) {
        final point = _project(segment[i], size);
        if (i == 0) {
          graphPath.moveTo(point.dx, point.dy);
        } else {
          graphPath.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(graphPath, graphPaint);
    }

    // Draw route path if generated
    if (routePolyline.length >= 2) {
      final routePath = Path();
      for (var i = 0; i < routePolyline.length; i++) {
        final point = _project(routePolyline[i], size);
        if (i == 0) {
          routePath.moveTo(point.dx, point.dy);
        } else {
          routePath.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(routePath, routePaint);
    }

    // Draw general floor rooms
    for (final room in rooms) {
      final center = _project(room.coordinate, size);
      final isSelected = selectedRoom?.id == room.id;
      
      if (isSelected) {
        // Pulse ring around active room
        final pulsePaint = Paint()
          ..color = const Color(0xFFEF4444).withOpacity(0.1 + (1 - pulseValue) * 0.3)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, 8 + pulseValue * 6, pulsePaint);
      }

      canvas.drawCircle(
        center,
        isSelected ? 6.5 : 4.5,
        isSelected ? selectedPaint : roomPaint,
      );

      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(center, isSelected ? 6.5 : 4.5, borderPaint);

      // Label rooms
      final textPainter = TextPainter(
        text: TextSpan(
          text: room.name,
          style: TextStyle(
            color: isSelected ? const Color(0xFFDC2626) : const Color(0xFF1E293B),
            fontSize: isSelected ? 10 : 8,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            shadows: const [
              Shadow(color: Colors.white, blurRadius: 3, offset: Offset(1, 1)),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(center.dx - textPainter.width / 2, center.dy + 8));
    }

    // Draw stairs transitions
    for (final transition in transitions) {
      final center = _project(transition.coordinate, size);
      
      // Draw stair icon border/glow
      final glowPaint = Paint()
        ..color = const Color(0xFF2563EB).withOpacity(0.2)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, 9, glowPaint);

      canvas.drawRect(
        Rect.fromCenter(center: center, width: 9, height: 9),
        transitionPaint,
      );

      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawRect(
        Rect.fromCenter(center: center, width: 9, height: 9),
        borderPaint,
      );

      // Text label for transition
      final textPainter = TextPainter(
        text: TextSpan(
          text: transition.label,
          style: const TextStyle(
            color: Color(0xFF1D4ED8),
            fontSize: 7.5,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(color: Colors.white, blurRadius: 2, offset: Offset(1, 1)),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(canvas, Offset(center.dx - textPainter.width / 2, center.dy - 13));
    }

    // Draw Entry Point highlight (green pulsing ring)
    if (entryPoint != null) {
      final center = _project(entryPoint!, size);

      // Outer pulsing ripple ring
      final outerPaint = Paint()
        ..color = const Color(0xFF10B981).withOpacity(0.15 + (1 - pulseValue) * 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, 10 + pulseValue * 8, outerPaint);

      // Inner solid circle
      final innerPaint = Paint()
        ..color = const Color(0xFF10B981)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, 6, innerPaint);

      // White ring border
      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, 6, borderPaint);

      // Text label above entrance
      final tp = TextPainter(
        text: const TextSpan(
          text: '▼ You are here',
          style: TextStyle(
            color: Color(0xFF047857),
            fontSize: 9,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(color: Colors.white, blurRadius: 4, offset: Offset(1, 1)),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - 20));
    }
  }

  @override
  bool shouldRepaint(covariant _FloorPlanPainter oldDelegate) {
    return oldDelegate.rooms != rooms ||
        oldDelegate.selectedRoom?.id != selectedRoom?.id ||
        oldDelegate.transitions.length != transitions.length ||
        !listEquals(oldDelegate.routePolyline, routePolyline) ||
        oldDelegate.graphLines.length != graphLines.length ||
        oldDelegate.showGraphAsRoute != showGraphAsRoute ||
        oldDelegate.entryPoint != entryPoint ||
        oldDelegate.pulseValue != pulseValue;
  }

  Offset _project(LatLng coordinate, Size size) {
    final safeWidth = (bounds.width).abs() < 1e-8 ? 1e-8 : bounds.width;
    final safeHeight = (bounds.height).abs() < 1e-8 ? 1e-8 : bounds.height;

    final x = (coordinate.longitude - bounds.left) / safeWidth;
    final y = 1 - ((coordinate.latitude - bounds.top) / safeHeight);

    const pad = 24.0;
    return Offset(
      pad + x * (size.width - (pad * 2)),
      pad + y * (size.height - (pad * 2)),
    );
  }
}
