import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';
import 'dart:math' as math;
import '../models/path_model.dart';
import '../models/place_model.dart';
import '../models/route_model.dart' as route_model;
import '../services/path_based_routing_service.dart';
import '../services/routing_service.dart';

class NavigationScreen extends StatefulWidget {
  final LatLng startLocation;
  final LatLng endLocation;
  final String destinationName;
  final route_model.Route? initialRoute;
  final List<CampusPath>? campusPaths;
  final List<CampusPlace>? routePlaces;

  const NavigationScreen({
    Key? key,
    required this.startLocation,
    required this.endLocation,
    required this.destinationName,
    this.initialRoute,
    this.campusPaths,
    this.routePlaces,
  }) : super(key: key);

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  static const Color _brandColor = Color(0xFF0B5FFF);
  static const String _englishCode = 'en-IN';
  static const String _hindiCode = 'hi-IN';
  static const String _gujaratiCode = 'gu-IN';
  static const double _maxLiveAccuracyMeters = 45;
  static const int _maxFixAgeSeconds = 15;
  static const double _maxWalkingSpeedMps = 8;
  static const double _positionSmoothingFactor = 0.35;

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
  final FlutterTts _flutterTts = FlutterTts();
  String _voiceLanguage = _englishCode;
  bool _voiceReady = false;
  final Map<int, int> _turnAnnouncementLevels = <int, int>{};
  LatLng? _currentDisplayLocation;
  Position? _lastAcceptedPosition;
  DateTime? _lastAcceptedAt;
  bool _didShowRouteOverview = false;
  int _nextRouteStopIndex = 1;
  bool _finalArrivalAnnounced = false;
  final List<String> _arrivedStopMessages = <String>[];

  bool get _isLockedMultiStopRoute {
    final places = widget.routePlaces;
    return widget.initialRoute != null && places != null && places.length >= 2;
  }

  IconData _getPlaceIcon(CampusPlace place) {
    if (place.id == '__live_source__') {
      return Icons.my_location_rounded;
    }

    switch (place.placeType) {
      case 'building':
        return Icons.apartment;
      case 'parking':
        return Icons.local_parking;
      case 'restroom':
        return Icons.wc;
      case 'landmark':
        return Icons.place;
      default:
        return Icons.location_on;
    }
  }

  Color _getPlaceColor(CampusPlace place) {
    if (place.id == '__live_source__') {
      return Colors.blue;
    }

    switch (place.placeType) {
      case 'building':
        return Colors.purple;
      case 'parking':
        return Colors.blue;
      case 'restroom':
        return Colors.green;
      case 'landmark':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  void _showPlaceNamePopup(CampusPlace place) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(place.name),
        content: Text(place.placeType.toUpperCase()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  LatLng _projectPointOnSegment(LatLng p, LatLng a, LatLng b) {
    final latRef = (a.latitude + b.latitude + p.latitude) / 3.0;
    final cosLat = math.cos(latRef * (math.pi / 180.0));

    final ax = a.longitude * cosLat;
    final ay = a.latitude;
    final bx = b.longitude * cosLat;
    final by = b.latitude;
    final px = p.longitude * cosLat;
    final py = p.latitude;

    final abx = bx - ax;
    final aby = by - ay;
    final apx = px - ax;
    final apy = py - ay;
    final ab2 = (abx * abx) + (aby * aby);

    final rawT = ab2 == 0 ? 0.0 : ((apx * abx) + (apy * aby)) / ab2;
    final t = rawT.clamp(0.0, 1.0);

    final projX = ax + (abx * t);
    final projY = ay + (aby * t);

    return LatLng(projY, projX / cosLat);
  }

  List<LatLng> _buildRemainingRoutePath(
    List<LatLng> routePoints,
    LatLng current,
  ) {
    if (routePoints.length < 2) return routePoints;

    const distanceCalc = Distance();
    double minDistance = double.infinity;
    int nearestSegmentStartIndex = 0;
    LatLng nearestProjected = routePoints.first;

    for (int i = 0; i < routePoints.length - 1; i++) {
      final projected = _projectPointOnSegment(
        current,
        routePoints[i],
        routePoints[i + 1],
      );
      final d = distanceCalc(current, projected);

      if (d < minDistance) {
        minDistance = d;
        nearestSegmentStartIndex = i;
        nearestProjected = projected;
      }
    }

    final remaining = <LatLng>[nearestProjected];

    for (int i = nearestSegmentStartIndex + 1; i < routePoints.length; i++) {
      remaining.add(routePoints[i]);
    }

    if (remaining.length == 1) {
      remaining.add(routePoints.last);
    }

    return remaining;
  }

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
      final resolvedRoute = _isLockedMultiStopRoute
          ? widget.initialRoute!
          : await _resolveInitialRoute(widget.initialRoute!);
      setState(() {
        currentRoute = resolvedRoute;
        isLoading = false;
      });
      _showInitialRouteOverview();
      _speakCurrentStep();
      return;
    }

    // Get route from OSRM API first
    final route = await RoutingService.getRoute(
      widget.startLocation,
      widget.endLocation,
    );

    setState(() {
      // Use real route from OSRM, or fallback demo route
      currentRoute =
          route ??
          RoutingService.getDemoRoute(widget.startLocation, widget.endLocation);
      isLoading = false;
    });
    _showInitialRouteOverview();
    _speakCurrentStep();
  }

  void _checkMultiStopArrivals(LatLng currentLocation) {
    final routePlaces = widget.routePlaces;
    if (routePlaces == null || routePlaces.length < 2) return;
    if (_nextRouteStopIndex >= routePlaces.length) return;

    final nextStop = routePlaces[_nextRouteStopIndex];
    final distance = const Distance()(currentLocation, nextStop.location);
    if (distance > 12) return;

    final isFinalStop = _nextRouteStopIndex == routePlaces.length - 1;

    if (!isFinalStop) {
      final arrivalMessage = 'You have arrived at ${nextStop.name}.';
      _speakInstruction(arrivalMessage);

      final upcomingStop = routePlaces[_nextRouteStopIndex + 1];
      _speakInstruction('Continuing to ${upcomingStop.name}.');

      setState(() {
        _arrivedStopMessages.add(arrivalMessage);
        _nextRouteStopIndex++;
      });
      return;
    }

    if (_finalArrivalAnnounced) return;
    _finalArrivalAnnounced = true;
    _showArrivalDialog();
  }

  void _showInitialRouteOverview() {
    if (_didShowRouteOverview || currentRoute == null) return;

    final waypoints = currentRoute!.waypoints;
    if (waypoints.length < 2) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_mapReady || _didShowRouteOverview) return;

      double minLat = waypoints.first.latitude;
      double maxLat = waypoints.first.latitude;
      double minLng = waypoints.first.longitude;
      double maxLng = waypoints.first.longitude;

      for (final p in waypoints) {
        minLat = math.min(minLat, p.latitude);
        maxLat = math.max(maxLat, p.latitude);
        minLng = math.min(minLng, p.longitude);
        maxLng = math.max(maxLng, p.longitude);
      }

      final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
      final span = math.max(maxLat - minLat, maxLng - minLng);

      double targetZoom;
      if (span > 0.02) {
        targetZoom = 13.0;
      } else if (span > 0.01) {
        targetZoom = 14.0;
      } else if (span > 0.005) {
        targetZoom = 15.0;
      } else if (span > 0.002) {
        targetZoom = 16.0;
      } else {
        targetZoom = 17.0;
      }

      mapController.move(center, targetZoom);
      _currentZoom = targetZoom;
      _didShowRouteOverview = true;
    });
  }

  Future<route_model.Route> _resolveInitialRoute(
    route_model.Route candidate,
  ) async {
    if (!_isLikelyStraightFallback(candidate)) {
      return candidate;
    }

    final paths = widget.campusPaths;
    if (paths == null || paths.isEmpty) {
      return candidate;
    }

    final upgradedRoute = await PathBasedRoutingService.getPathBasedRoute(
      widget.startLocation,
      widget.endLocation,
      paths,
    );

    if (upgradedRoute == null) {
      return candidate;
    }

    if (_isLikelyStraightFallback(upgradedRoute)) {
      return candidate;
    }

    return upgradedRoute;
  }

  bool _isLikelyStraightFallback(route_model.Route route) {
    final points = route.waypoints;
    if (points.length <= 2) {
      return true;
    }

    if (route.steps.length <= 2) {
      const distanceCalc = Distance();
      final directDistance = distanceCalc(points.first, points.last);
      final traveledDistance = route.totalDistance;

      if (directDistance <= 0) {
        return false;
      }

      // If path distance is almost the same as straight-line distance and
      // turn instructions are minimal, treat as fallback straight routing.
      final straightnessRatio = traveledDistance / directDistance;
      return straightnessRatio < 1.03;
    }

    return false;
  }

  Future<void> _initializeVoice() async {
    try {
      await _flutterTts.awaitSpeakCompletion(true);
      await _flutterTts.setSpeechRate(0.46);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      await _flutterTts.setLanguage(_voiceLanguage);
      _voiceReady = true;
    } catch (e) {
      print('Voice initialization: $e');
    }
  }

  Future<void> _setVoiceLanguage(String languageCode) async {
    var appliedLanguage = languageCode;

    if (_voiceReady) {
      try {
        await _flutterTts.stop();
        await _flutterTts.setLanguage(languageCode);
      } catch (e) {
        print('Error changing voice language: $e');
        appliedLanguage = _englishCode;
        await _flutterTts.setLanguage(_englishCode);
      }
    }

    setState(() {
      _voiceLanguage = appliedLanguage;
    });

    final switchedMessage = appliedLanguage == _hindiCode
        ? 'वॉइस गाइड हिंदी में चालू है।'
        : appliedLanguage == _gujaratiCode
        ? 'વોઇસ માર્ગદર્શન ગુજરાતી માં ચાલુ છે.'
        : 'Voice guidance switched to English.';

    await _speakInstructionWithOptions(
      switchedMessage,
      bypassLocalization: true,
    );
    _speakCurrentStep();
  }

  String _localizeInstruction(String instruction) {
    if (_voiceLanguage == _englishCode) {
      return instruction;
    }

    var localized = instruction;
    final hindiReplacements = <String, String>{
      'Head straight': 'सीधे चलें',
      'Turn left': 'बाएँ मुड़ें',
      'Turn right': 'दाएँ मुड़ें',
      'Slight left': 'थोड़ा बाएँ मुड़ें',
      'Slight right': 'थोड़ा दाएँ मुड़ें',
      'Take a sharp left': 'तेज़ बाएँ मोड़ लें',
      'Take a sharp right': 'तेज़ दाएँ मोड़ लें',
      'Make a U-turn': 'यू-टर्न लें',
      'Continue straight': 'सीधे चलते रहें',
      'Continue on ': 'पर आगे बढ़ें ',
      'Continue': 'आगे बढ़ें',
      'Head north': 'उत्तर दिशा में चलें',
      'Head south': 'दक्षिण दिशा में चलें',
      'Head east': 'पूर्व दिशा में चलें',
      'Head west': 'पश्चिम दिशा में चलें',
      'Destination': 'गंतव्य',
      'Arrive at destination': 'गंतव्य पर पहुँचें',
      'arrived': 'पहुँच गए हैं',
      'Keep left': 'बाएँ तरफ रहें',
      'Keep right': 'दाएँ तरफ रहें',
      'Take the path': 'रास्ता लें',
      'Go to': 'जाएँ',
    };

    final gujaratiReplacements = <String, String>{
      'Head straight': 'સીધા આગળ વધો',
      'Turn left': 'ડાબે વળો',
      'Turn right': 'જમણે વળો',
      'Slight left': 'થોડું ડાબે વળો',
      'Slight right': 'થોડું જમણે વળો',
      'Take a sharp left': 'તીક્ષ્ણ ડાબું વાળો',
      'Take a sharp right': 'તીક્ષ્ણ જમણું વાળો',
      'Make a U-turn': 'યુ-ટર્ન લો',
      'Continue straight': 'સીધા ચાલતા રહો',
      'Continue on ': 'પર આગળ વધો ',
      'Continue': 'આગળ વધો',
      'Head north': 'ઉત્તર દિશામાં ચાલો',
      'Head south': 'દક્ષિણ દિશામાં ચાલો',
      'Head east': 'પૂર્વ દિશામાં ચાલો',
      'Head west': 'પશ્ચિમ દિશામાં ચાલો',
      'Destination': 'ગંતવ્ય',
      'Arrive at destination': 'ગંતવ્ય પર પહોંચો',
      'arrived': 'પહોંચી ગયા છો',
      'Keep left': 'ડાબી બાજુ રાખો',
      'Keep right': 'જમણી બાજુ રાખો',
      'Take the path': 'રસ્તો લો',
      'Go to': 'જાઓ',
    };

    final replacements = _voiceLanguage == _hindiCode
        ? hindiReplacements
        : _voiceLanguage == _gujaratiCode
        ? gujaratiReplacements
        : <String, String>{};

    replacements.forEach((from, to) {
      localized = localized.replaceAll(from, to);
    });
    return localized;
  }

  Future<void> _speakInstruction(String instruction) async {
    await _speakInstructionWithOptions(instruction, bypassLocalization: false);
  }

  Future<void> _speakInstructionWithOptions(
    String instruction, {
    required bool bypassLocalization,
  }) async {
    if (!voiceEnabled || !_voiceReady) {
      return;
    }

    final textToSpeak = bypassLocalization
        ? instruction
        : _localizeInstruction(instruction);

    try {
      await _flutterTts.stop();
      await _flutterTts.speak(textToSpeak);
      print('Voice: $textToSpeak');
    } catch (e) {
      print('Voice speak error: $e');
    }
  }

  Future<void> _speakCurrentStep() async {
    if (currentRoute == null || currentRoute!.steps.isEmpty) {
      return;
    }

    final step = currentRoute!.steps[currentStepIndex];
    await _speakInstruction(step.instruction);
  }

  bool _isTurnStep(route_model.NavigationStep step) {
    final turnType = (step.turnType ?? 'straight').toLowerCase();
    return turnType != 'straight';
  }

  String _turnActionText(route_model.NavigationStep step) {
    switch ((step.turnType ?? '').toLowerCase()) {
      case 'left':
        return 'Turn left';
      case 'right':
        return 'Turn right';
      case 'slight_left':
        return 'Slight left';
      case 'slight_right':
        return 'Slight right';
      case 'sharp_left':
        return 'Take a sharp left';
      case 'sharp_right':
        return 'Take a sharp right';
      case 'uturn':
        return 'Make a U-turn';
      default:
        return step.instruction;
    }
  }

  String _buildTurnAnnouncement(route_model.NavigationStep step, int meters) {
    final action = _turnActionText(step);

    if (_voiceLanguage == _hindiCode) {
      final localizedAction = _localizeInstruction(action);
      if (meters <= 10) {
        return 'अभी $localizedAction';
      }
      return '${meters} मीटर बाद $localizedAction';
    }

    if (_voiceLanguage == _gujaratiCode) {
      final localizedAction = _localizeInstruction(action);
      if (meters <= 10) {
        return 'હવે $localizedAction';
      }
      return '${meters} મીટર પછી $localizedAction';
    }

    if (meters <= 10) {
      return '$action now';
    }
    return '$action after $meters meters';
  }

  void _announceTurnGuidance(
    route_model.NavigationStep step,
    double distanceToStep,
  ) {
    if (!_isTurnStep(step)) return;

    final meters = distanceToStep.round();
    final currentLevel = _turnAnnouncementLevels[currentStepIndex] ?? 0;

    // Level 1: early heads-up (for example: turn right after 100m)
    if (distanceToStep <= 120 && currentLevel < 1) {
      _turnAnnouncementLevels[currentStepIndex] = 1;
      _speakInstruction(_buildTurnAnnouncement(step, meters));
      return;
    }

    // Level 2: immediate instruction at turn point (for example: turn right now)
    if (distanceToStep <= 10 && currentLevel < 2) {
      _turnAnnouncementLevels[currentStepIndex] = 2;
      _speakInstruction(_buildTurnAnnouncement(step, meters));
    }
  }

  void _startLocationTracking() {
    _positionSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 5, // Update every 5 meters
          ),
        ).listen((Position position) {
          if (!_isReliableFix(
            position,
            allowInitialRelaxation: currentPosition == null,
          )) {
            return;
          }

          final smoothed = _smoothedLocation(
            LatLng(position.latitude, position.longitude),
          );

          setState(() {
            currentPosition = position;
            _currentDisplayLocation = smoothed;
          });

          _lastAcceptedPosition = position;
          _lastAcceptedAt = DateTime.now();

          // Auto-advance step if close to waypoint
          if (currentRoute != null) {
            _checkMultiStopArrivals(smoothed);
            _checkStepProximity(smoothed);
          }

          // Center map on user only after map controller is attached.
          if (_mapReady && _didShowRouteOverview) {
            mapController.move(smoothed, _currentZoom);
          }
        });
  }

  bool _isReliableFix(
    Position position, {
    bool allowInitialRelaxation = false,
  }) {
    final now = DateTime.now();
    final fixTime = position.timestamp ?? now;
    final ageSeconds = now.difference(fixTime).inSeconds;

    final maxAllowedAccuracy = allowInitialRelaxation
        ? 70.0
        : _maxLiveAccuracyMeters;
    if (position.accuracy <= 0 || position.accuracy > maxAllowedAccuracy) {
      return false;
    }

    if (ageSeconds > _maxFixAgeSeconds) {
      return false;
    }

    if (_lastAcceptedPosition != null) {
      const distanceCalc = Distance();
      final previousPoint = LatLng(
        _lastAcceptedPosition!.latitude,
        _lastAcceptedPosition!.longitude,
      );
      final currentPoint = LatLng(position.latitude, position.longitude);
      final deltaMeters = distanceCalc(previousPoint, currentPoint);

      final previousTime =
          _lastAcceptedPosition!.timestamp ?? _lastAcceptedAt ?? now;
      final dtMillis =
          (fixTime.millisecondsSinceEpoch - previousTime.millisecondsSinceEpoch)
              .abs();

      if (dtMillis > 0) {
        final speedMps = deltaMeters / (dtMillis / 1000.0);
        if (speedMps > _maxWalkingSpeedMps && position.accuracy > 18) {
          return false;
        }
      }
    }

    return true;
  }

  LatLng _smoothedLocation(LatLng raw) {
    if (_currentDisplayLocation == null) return raw;

    final lat =
        _currentDisplayLocation!.latitude +
        (raw.latitude - _currentDisplayLocation!.latitude) *
            _positionSmoothingFactor;
    final lng =
        _currentDisplayLocation!.longitude +
        (raw.longitude - _currentDisplayLocation!.longitude) *
            _positionSmoothingFactor;

    return LatLng(lat, lng);
  }

  void _checkStepProximity(LatLng currentLocation) {
    if (currentRoute == null ||
        currentStepIndex >= currentRoute!.steps.length) {
      return;
    }

    final currentStep = currentRoute!.steps[currentStepIndex];

    // Calculate distance using latlong2
    final distance = const Distance();
    final distanceToStep = distance(currentLocation, currentStep.location);

    _announceTurnGuidance(currentStep, distanceToStep);

    // If within 15 meters of waypoint, advance
    if (distanceToStep < 15 &&
        currentStepIndex < currentRoute!.steps.length - 1) {
      _advanceStep();
    }

    if (!_isTurnStep(currentStep) &&
        distanceToStep <= 35 &&
        (_turnAnnouncementLevels[currentStepIndex] ?? 0) < 1) {
      _turnAnnouncementLevels[currentStepIndex] = 1;
      _speakInstruction(
        _voiceLanguage == _hindiCode
            ? 'लगभग ${(distanceToStep).round()} मीटर में ${_localizeInstruction(currentStep.instruction)}'
            : _voiceLanguage == _gujaratiCode
            ? 'લગભગ ${distanceToStep.round()} મીટરમાં ${_localizeInstruction(currentStep.instruction)}'
            : 'In about ${distanceToStep.round()} meters, ${currentStep.instruction}',
      );
    }

    // Arrival message
    if (!_isLockedMultiStopRoute &&
        distanceToStep < 10 &&
        currentStepIndex == currentRoute!.steps.length - 1) {
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

  void _repeatCurrentInstruction() {
    _speakCurrentStep();
  }

  void _showArrivalDialog() {
    if (!isNavigating) return;

    _finalArrivalAnnounced = true;

    setState(() {
      isNavigating = false;
    });

    _speakInstruction(
      _voiceLanguage == _hindiCode
          ? 'आप अपने गंतव्य पर पहुँच गए हैं।'
          : _voiceLanguage == _gujaratiCode
          ? 'તમે તમારા ગંતવ્ય પર પહોંચી ગયા છો.'
          : 'You have arrived at your destination.',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Arrived'),
        content: const Text('You have arrived at your destination.'),
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
    _flutterTts.stop();
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
    final displayedRoutePoints =
      _isLockedMultiStopRoute
      ? currentRoute!.waypoints
      : _currentDisplayLocation != null
        ? _buildRemainingRoutePath(
            currentRoute!.waypoints,
            _currentDisplayLocation!,
          )
        : currentRoute!.waypoints;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Navigation'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Voice language',
            icon: const Icon(Icons.translate_rounded),
            onSelected: _setVoiceLanguage,
            itemBuilder: (context) => [
              CheckedPopupMenuItem<String>(
                value: _englishCode,
                checked: _voiceLanguage == _englishCode,
                child: const Text('English'),
              ),
              CheckedPopupMenuItem<String>(
                value: _hindiCode,
                checked: _voiceLanguage == _hindiCode,
                child: const Text('Hindi (हिंदी)'),
              ),
              CheckedPopupMenuItem<String>(
                value: _gujaratiCode,
                checked: _voiceLanguage == _gujaratiCode,
                child: const Text('Gujarati (ગુજરાતી)'),
              ),
            ],
          ),
          IconButton(
            icon: Icon(voiceEnabled ? Icons.volume_up : Icons.volume_off),
            onPressed: () {
              setState(() {
                voiceEnabled = !voiceEnabled;
              });
              if (voiceEnabled) {
                _speakCurrentStep();
              } else {
                _flutterTts.stop();
              }
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
                  _showInitialRouteOverview();
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
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: displayedRoutePoints,
                      color: Colors.blue.shade400,
                      strokeWidth: 5,
                      borderColor: Colors.blue.shade900,
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),
                if (widget.routePlaces != null && widget.routePlaces!.length > 1)
                  MarkerLayer(
                    markers: widget.routePlaces!.asMap().entries
                        .where((entry) {
                          final isFirst = entry.key == 0;
                          final isLiveSource =
                              entry.value.id == '__live_source__';
                          // For live source, keep only the existing live marker.
                          return !(isFirst && isLiveSource);
                        })
                        .map((entry) {
                          final index = entry.key;
                          final place = entry.value;
                          final isFirst = index == 0;
                          final isLast =
                              index == widget.routePlaces!.length - 1;
                          final isLiveSource = place.id == '__live_source__';
                          final showGreenSourcePin = isFirst && !isLiveSource;
                          final showRedDestinationPin = isLast;

                      return Marker(
                        width: (showGreenSourcePin || showRedDestinationPin)
                            ? 44
                            : 36,
                        height: (showGreenSourcePin || showRedDestinationPin)
                            ? 44
                            : 36,
                        point: place.location,
                        child: GestureDetector(
                          onTap: () => _showPlaceNamePopup(place),
                          child: showGreenSourcePin
                              ? const Icon(
                                  Icons.location_pin,
                                  color: Colors.green,
                                  size: 42,
                                )
                              : showRedDestinationPin
                              ? const Icon(
                                  Icons.location_pin,
                                  color: Colors.red,
                                  size: 42,
                                )
                              : Container(
                                  decoration: BoxDecoration(
                                    color: _getPlaceColor(place),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1.8,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 3,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    _getPlaceIcon(place),
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                        ),
                      );
                    }).toList(),
                  ),
                MarkerLayer(
                  markers: [
                    // End marker
                    if (widget.routePlaces == null || widget.routePlaces!.isEmpty)
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
                        point:
                            _currentDisplayLocation ??
                            LatLng(
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
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFEFF4FF), Color(0xFFFFFFFF)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Step ${currentStepIndex + 1} of ${currentRoute!.steps.length}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
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
                  currentStep != null
                      ? _localizeInstruction(currentStep.instruction)
                      : 'Loading instruction...',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
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
                          color: _brandColor,
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
                            color: const Color(0xFFF59E0B),
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
            flex: 1,
            child: Container(
              color: const Color(0xFFF8FAFD),
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
                    child: Builder(
                      builder: (context) {
                        final panelItems = <Map<String, dynamic>>[];

                        for (final message in _arrivedStopMessages) {
                          panelItems.add({
                            'type': 'arrival',
                            'message': message,
                          });
                        }

                        final remainingCount =
                            currentRoute!.steps.length - currentStepIndex - 1;
                        for (int i = 0; i < remainingCount; i++) {
                          final step = currentRoute!.steps[currentStepIndex + 1 + i];
                          panelItems.add({
                            'type': 'step',
                            'step': step,
                            'label': currentStepIndex + 2 + i,
                          });
                        }

                        return ListView.builder(
                          itemCount: panelItems.length,
                          itemBuilder: (context, index) {
                            final item = panelItems[index];

                            if (item['type'] == 'arrival') {
                              return ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: Color(0xFFD1FAE5),
                                  foregroundColor: Color(0xFF047857),
                                  child: Icon(Icons.check_rounded),
                                ),
                                title: Text(
                                  item['message'] as String,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF065F46),
                                  ),
                                ),
                                subtitle: const Text('Intermediate stop reached'),
                              );
                            }

                            final step = item['step'] as route_model.NavigationStep;
                            final label = item['label'] as int;
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFFE5EDFF),
                                foregroundColor: _brandColor,
                                child: Text('$label'),
                              ),
                              title: Text(_localizeInstruction(step.instruction)),
                              subtitle: Text(
                                '${step.getFormattedDistance()} • ${step.getFormattedDuration()}',
                              ),
                            );
                          },
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
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _previousStep,
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Previous'),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: _brandColor,
                          backgroundColor: Colors.white,
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
                          backgroundColor: _brandColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _repeatCurrentInstruction,
                        icon: const Icon(Icons.replay_rounded),
                        label: const Text('Repeat Voice'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEAF1FF),
                          foregroundColor: _brandColor,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
