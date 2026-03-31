# Advanced Routing & Navigation Implementation Guide

## Overview
This document describes the implementation of Features #1, #2, #3, and #7 from the Advanced Features list:
- **#1 Turn-by-Turn Navigation** - Step-by-step directions with real-time tracking
- **#2 Multiple Route Options** - Choose between shortest, fastest, and other routes
- **#3 Real-time GPS Tracking** - Live location during navigation
- **#7 Location Search** - Smart search with auto-complete and nearby places

## What Was Implemented

### 1. **RoutingService** 
**File:** `lib/services/routing_service.dart`

Handles all route calculation and API integration:
- `getRoute()` - Get a single route between two points
- `getMultipleRoutes()` - Get multiple route options
- `getRouteWithWaypoints()` - Route with multiple waypoints
- `isValidCampusRoute()` - Validate if route is within campus bounds
- `getDemoRoute()` - Demo route data (when API not available)

**API Used:** OpenRouteService (free tier: 2,500 requests/day)

### 2. **NavigationScreen**
**File:** `lib/screens/navigation_screen.dart`

Turn-by-turn navigation UI with:
- Real-time GPS tracking
- Current step highlighting with large text
- Upcoming steps preview list
- Distance and duration for each step
- Previous/Next step navigation buttons
- Auto-advance when reaching waypoint proximity
- Voice announcement support (when flutter_tts is ready)
- Map display with route polyline and markers
- Automatic arrival detection

**Key Features:**
- Shows turn-by-turn directions in a step-by-step format
- Displays next steps in upcoming steps list
- Color-coded markers (start=green, current=orange, end=red)
- Auto-advances to next step when within 15 meters
- Detects arrival when within 10 meters of destination

### 3. **RouteComparisonScreen**
**File:** `lib/screens/route_comparison_screen.dart`

Multiple route selection interface with:
- Route comparison cards (shortest, fastest, safest, scenic)
- Visual route preview on map
- Distance, duration, and step count for each route
- Quality rating system (1-5 stars)
- Wheelchair accessibility indicators
- Start Navigation button for selected route

**Route Types:**
- **Shortest** - Minimize distance (compress icon)
- **Fastest** - Minimize time (lightning icon)
- **Safest** - Well-lit, populated areas (shield icon)
- **Scenic** - Beautiful route with landmarks (landscape icon)

### 4. **LocationSearchService**
**File:** `lib/services/location_search_service.dart`

Smart location search with:
- `searchPlaces()` - Search by name, department, or type
- `getAutocompleteSuggestions()` - Auto-complete suggestions
- `findNearbyPlaces()` - Find places within radius
- `findNearbyPlacesWithDistance()` - Nearby places with distance data
- `searchByType()` - Filter by place type
- `searchByDepartment()` - Filter by department
- `rankResults()` - Sort results by relevance
- `getAllDepartments()` & `getAllPlaceTypes()` - Get filter options

**Search Quality:**
1. Exact name matches ranked first
2. Names starting with query ranked second
3. Names containing query ranked third
4. Department matches ranked last

### 5. **Updated OutdoorMapScreen**
**File:** `lib/screens/outdoor_map_screen.dart`

Enhanced with routing integration:
- "Get Route" button in place info sheet
- Integration with RouteComparisonScreen
- Enhanced search using LocationSearchService
- Result ranking by relevance
- Direct navigation to destination from place info

## How to Use

### Step 1: Set Up OpenRouteService API Key

1. Visit [OpenRouteService](https://openrouteservice.org/dev/#/login)
2. Create a free account
3. Generate an API key
4. Update `lib/services/routing_service.dart`:
   ```dart
   static const String apiKey = 'YOUR_ACTUAL_API_KEY_HERE';
   ```

### Step 2: Get Route from Map Screen

1. Open the app and locate your position
2. Click on any place/building
3. In the bottom sheet, click "Get Route"
4. The app navigates to RouteComparisonScreen

### Step 3: Select Route Option

1. Compare different routes on the map
2. Review distance, duration, and accessibility info
3. Click on a route card to select it (highlighted in blue)
4. Click "Start Navigation" button
5. Navigation screen opens

### Step 4: Follow Turn-by-Turn Directions

1. View current step in large text
2. See next steps in the list below
3. Map shows your location (blue dot) on route
4. Tap "Next" to manually advance step
5. App auto-advances when you get close
6. "Exit Navigation" button to cancel anytime

### Step 5: Search Locations

1. Use search bar at top of map
2. Type place name, department, or type
3. Results rank by relevance:
   - Exact name matches first
   - Starting with query second
   - Contains query third

## API Configuration

### Free Alternatives to OpenRouteService

If OpenRouteService doesn't work, try:

1. **GraphHopper**
   - URL: `https://graphhopper.com/api/1/route`
   - Free tier: 20,000 requests/month
   - Sign up: https://graphhopper.com/api/1/route

2. **OSRM (Open Source Routing Machine)**
   - Free public server: `http://router.project-osrm.org/route/v1/foot/`
   - No key required
   - Rate-limited (use carefully)

### To Switch APIs

Comment out the OpenRouteService methods and uncomment new API wrapper:

```dart
// In routing_service.dart
// static const String baseUrl = 'https://api.openrouteservice.org/v2/directions';
static const String baseUrl = 'https://graphhopper.com/api/1/route';
// Update parsing logic in Route.fromJson()
```

## Data Models

### NavigationStep
```dart
- index: int (step number)
- instruction: String (e.g., "Turn left")
- distance: double (in meters)
- duration: double (in seconds)
- location: LatLng (GPS coordinates)
- turnType: String? (left, right, straight, uturn)
- bearing: double? (compass direction)
```

### Route
```dart
- id: String (unique identifier)
- name: String (route name)
- steps: List<NavigationStep>
- totalDistance: double (meters)
- totalDuration: double (seconds)
- routeQuality: int (1-5 stars)
- routeType: String (shortest, fastest, safest, scenic)
- wheelchairAccessible: bool
- waypoints: List<LatLng> (all coordinates on route)
```

### RouteComparison
```dart
- shortestRoute: Route
- fastestRoute: Route
- safestRoute: Route?
- scenicRoute: Route?
```

## Key Features

### Real-Time Tracking
- Updates every 5 meters (adjustable in `locationSettings`)
- Auto-centers map on current position
- Calculates distance to next waypoint
- Auto-advances step when within 15m

### Voice Navigation (Future)
- flutter_tts is included in dependencies
- Uncomment TTS code in `navigation_screen.dart`
- Will speak instructions like: "In 50 meters, turn left"

### Offline Support (Future Phase)
- Save routes as GeoJSON for offline use
- Pre-download map tiles
- Store search cache locally

## Testing

### Test Scenarios

1. **Basic Routing**
   - Start: Your Location
   - End: Any campus place
   - Expected: Route displays on map

2. **Multiple Routes**
   - Should see 3-4 different route options
   - Each with different characteristics
   - Visual indication on map

3. **Turn-by-Turn**
   - Steps display in correct order
   - Auto-advance when moving
   - Correct distance calculations

4. **Search**
   - Type building name → appears in results
   - Type department → shows buildings
   - Results ranked by relevance

## Common Issues & Solutions

### Issue: "No routes found"
**Cause:** API key not set or route outside coverage
**Solution:** 
- Set API key in `routing_service.dart`
- Check if location is within expected area
- App falls back to demo route

### Issue: Voice not working
**Cause:** flutter_tts not installed or property disabled
**Solution:**
- Run `flutter pub get`
- Check iOS/Android permissions
- Uncomment TTS code in `navigation_screen.dart`

### Issue: GPS not updating
**Cause:** Permission not granted or location disabled
**Solution:**
- Grant location permission on first use
- Enable device location
- Restart app

### Issue: Map won't center on location
**Cause:** User cancelled permission request
**Solution:**
- Tap location button to request again
- Or manually enable in device settings

## Future Enhancements

1. **Voice Navigation**
   - Uncomment flutter_tts code
   - Announce steps while walking
   - Play arrival chime

2. **Offline Maps**
   - Cache downloaded tiles
   - Store routes locally
   - Work without internet

3. **ETA Improvements**
   - Factor in historical traffic
   - Adjust for terrain difficulty
   - Account for pedestrian speed

4. **Alternative Routes**
   - Add scenic options
   - Add wheel-friendly paths
   - Quiet/safe neighborhoods

5. **Route Customization**
   - Avoid certain areas
   - Prefer certain types of routes
   - Custom waypoints

## Code Structure

```
lib/
├── models/
│   ├── path_model.dart          (Campus paths)
│   ├── place_model.dart         (Buildings/POIs)
│   └── route_model.dart         (NEW: Routes & navigation)
├── services/
│   ├── geojson_loader.dart      (Load path/place data)
│   ├── routing_service.dart     (NEW: Route calculation)
│   └── location_search_service.dart (NEW: Place search)
└── screens/
    ├── outdoor_map_screen.dart      (Main map - integrated)
    ├── navigation_screen.dart       (NEW: Turn-by-turn)
    └── route_comparison_screen.dart (NEW: Route selection)
```

## Dependencies Added

```yaml
dio: ^5.3.0 - HTTP client for routing APIs
flutter_tts: ^0.14.0 - Text-to-speech for voice navigation
distance: ^0.0.7 - Distance calculations
```

## Files Modified/Created

### New Files (3)
- `lib/services/routing_service.dart`
- `lib/services/location_search_service.dart`
- `lib/screens/navigation_screen.dart`
- `lib/screens/route_comparison_screen.dart`

### Modified Files (1)
- `lib/screens/outdoor_map_screen.dart` - Added routing integration
- `pubspec.yaml` - Added new dependencies

## Performance Notes

- Route calculations are throttled (API key limits ~2,500/day)
- Location updates every 5 meters (adjustable)
- Map renders efficiently with flutter_map
- Search results ranked for instant feedback

## Troubleshooting

Run these commands if issues occur:

```bash
# Clean build
flutter clean
flutter pub get
flutter pub upgrade

# Check for errors
flutter analyze

# Run on device
flutter run
```

For more help, check the Flutter documentation or project logs.
