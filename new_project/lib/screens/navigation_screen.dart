import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:math' as math;
import '../models/path_model.dart';
import '../models/route_model.dart' as route_model;
import '../services/routing_service.dart';

class NavigationScreen extends StatefulWidget {
  final LatLng startLocation;
  final LatLng endLocation;
  final String destinationName;
  final route_model.Route? initialRoute;
  final List<CampusPath>? campusPaths;

  const NavigationScreen({
    Key? key,
    required this.startLocation,
    required this.endLocation,
    required this.destinationName,
    this.initialRoute,
    this.campusPaths,
  }) : super(key: key);

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  route_model.Route? currentRoute;
  int currentStepIndex = 0;
  Position? currentPosition;
  bool isNavigating = true;
  bool voiceEnabled = true;
  bool isLoading = true;
  final MapController mapController = MapController();
  StreamSubscription<Position>? _positionSubscription;
  bool _mapReady = false;
  double _currentZoom = 18;

  double _getNavigationHeadingRadians(route_model.NavigationStep? currentStep) {
    if (currentPosition != null && currentPosition!.heading >= 0) {
      return currentPosition!.heading * math.pi / 180;
    }

    if (currentStep != null && currentPosition != null) {
      final bearing = const Distance().bearing(
        LatLng(currentPosition!.latitude, currentPosition!.longitude),
        currentStep.location,
      );
      return bearing * math.pi / 180;
    }

    return 0;
  }

  @override
  void initState() {
    super.initState();
    _initializeRoute();
    _startLocationTracking();
    _initializeVoice();
  }

  Future<void> _initializeRoute() async {
    if (widget.initialRoute != null) {
      setState(() {
        currentRoute = widget.initialRoute;
        isLoading = false;
      });
      return;
    }

    // Get route from OSRM API first
    final route = await RoutingService.getRoute(
      widget.startLocation,
      widget.endLocation,
    );

    setState(() {
      // Use real route from OSRM, or fallback demo route
      currentRoute = route ?? RoutingService.getDemoRoute(
        widget.startLocation,
        widget.endLocation,
      );
      isLoading = false;
    });
  }

  Future<void> _initializeVoice() async {
    // Voice initialization - flutter_tts setup would go here
    // Placeholder for now
    try {
      // To enable voice, uncomment when flutter_tts is available
      // await flutterTts.setLanguage('en-US');
      // await flutterTts.setSpeechRate(0.5);
      // await flutterTts.setVolume(1.0);
    } catch (e) {
      print('Voice initialization: $e');
    }
  }

  Future<void> _speakInstruction(String instruction) async {
    if (voiceEnabled) {
      // To enable voice, uncomment when flutter_tts is available
      // await flutterTts.speak(instruction);
      print('Voice: $instruction');
    }
  }

  void _startLocationTracking() {
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5, // Update every 5 meters
      ),
    ).listen((Position position) {
      setState(() {
        currentPosition = position;
      });

      // Auto-advance step if close to waypoint
      if (currentRoute != null) {
        _checkStepProximity(position);
      }

      // Center map on user only after map controller is attached.
      if (_mapReady) {
        mapController.move(
          LatLng(position.latitude, position.longitude),
          _currentZoom,
        );
      }
    });
  }

  void _checkStepProximity(Position position) {
    if (currentRoute == null || currentStepIndex >= currentRoute!.steps.length) {
      return;
    }

    final currentStep = currentRoute!.steps[currentStepIndex];
    
    // Calculate distance using latlong2
    final distance = const Distance();
    final distanceToStep = distance(
      LatLng(position.latitude, position.longitude),
      currentStep.location,
    );

    // If within 15 meters of waypoint, advance
    if (distanceToStep < 15 && currentStepIndex < currentRoute!.steps.length - 1) {
      _advanceStep();
    }

    // Arrival message
    if (distanceToStep < 10 && currentStepIndex == currentRoute!.steps.length - 1) {
      _showArrivalDialog();
    }
  }

  void _advanceStep() {
    if (currentStepIndex < (currentRoute?.steps.length ?? 0) - 1) {
      setState(() {
        currentStepIndex++;
      });
      
      final nextStep = currentRoute!.steps[currentStepIndex];
      _speakInstruction(nextStep.instruction);
    }
  }

  void _previousStep() {
    if (currentStepIndex > 0) {
      setState(() {
        currentStepIndex--;
      });
    }
  }

  void _showArrivalDialog() {
    if (!isNavigating) return;

    setState(() {
      isNavigating = false;
    });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Arrived'),
        content: Text('You have arrived at ${widget.destinationName}'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Exit Navigation'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    // Voice cleanup would go here
    // flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading || currentRoute == null) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading route...'),
            ],
          ),
        ),
      );
    }

    final currentStep = currentRoute!.steps.isNotEmpty 
        ? currentRoute!.steps[currentStepIndex] 
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Turn-by-Turn Navigation'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(voiceEnabled ? Icons.volume_up : Icons.volume_off),
            onPressed: () {
              setState(() {
                voiceEnabled = !voiceEnabled;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Map
          Expanded(
            flex: 2,
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: widget.startLocation,
                initialZoom: 18,
                onMapReady: () {
                  _mapReady = true;
                },
                onPositionChanged: (position, _) {
                  _currentZoom = position.zoom ?? _currentZoom;
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.new_project',
                ),
                if ((widget.campusPaths ?? const <CampusPath>[]).isNotEmpty)
                  PolylineLayer(
                    polylines: (widget.campusPaths ?? const <CampusPath>[])
                        .map(
                          (path) => Polyline(
                            points: path.coordinates,
                            color: Colors.blue.withOpacity(0.35),
                            strokeWidth: 3,
                          ),
                        )
                        .toList(),
                  ),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: currentRoute!.waypoints,
                      color: Colors.blue.shade400,
                      strokeWidth: 5,
                      borderColor: Colors.blue.shade900,
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    // Source marker fallback before live GPS is available
                    if (currentPosition == null)
                      Marker(
                        width: 40,
                        height: 40,
                        point: widget.startLocation,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.blue,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.navigation,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    // End marker
                    Marker(
                      width: 40,
                      height: 40,
                      point: widget.endLocation,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                    // Live current position marker (single blue arrow)
                    if (currentPosition != null)
                      Marker(
                        width: 40,
                        height: 40,
                        point: LatLng(
                          currentPosition!.latitude,
                          currentPosition!.longitude,
                        ),
                        child: Transform.rotate(
                          angle: _getNavigationHeadingRadians(currentStep),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.blue,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.withOpacity(0.5),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.navigation,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Step Information Card
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Step ${currentStepIndex + 1} of ${currentRoute!.steps.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                    Text(
                      '${currentRoute!.getFormattedTotalDistance()} • ${currentRoute!.getFormattedTotalDuration()}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Current instruction - Large
                Text(
                  currentStep?.instruction ?? 'Loading instruction...',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                // Distance and turn info
                if (currentStep != null)
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          currentStep.getFormattedDistance(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (currentStep.turnType != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Turn ${currentStep.turnType}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          // Next Steps Preview
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.grey.shade100,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Upcoming Steps',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: currentRoute!.steps.length - currentStepIndex - 1,
                      itemBuilder: (context, index) {
                        final step = currentRoute!.steps[currentStepIndex + 1 + index];
                        return ListTile(
                          leading: CircleAvatar(
                            child: Text('${currentStepIndex + 2 + index}'),
                          ),
                          title: Text(step.instruction),
                          subtitle: Text(
                            '${step.getFormattedDistance()} • ${step.getFormattedDuration()}',
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Navigation Buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _previousStep,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Previous'),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.blue,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _advanceStep,
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Next'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    label: const Text('Exit'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
