# Outdoor Navigation Setup Guide

## Overview
This Flutter project implements outdoor campus navigation using OpenStreetMap (OSM) tiles with custom GeoJSON data for paths and places.

## Architecture

### Core Components

#### 1. **Data Models** (`lib/models/`)
- **`path_model.dart`**: Represents walking/cycling paths with attributes
  - `id`: Unique identifier
  - `walkable`: Boolean for pedestrian accessibility
  - `pathType`: concrete, grass, asphalt, etc.
  - `difficulty`: easy, medium, hard
  - `wheelchairAccessible`: Accessibility flag
  - `restrictions`: vehicle/bike restrictions
  
- **`place_model.dart`**: Represents campus locations
  - `placeType`: building, parking, landmark, restroom
  - `hasIndoorMap`: Flag for indoor navigation availability
  - `floors`: Number of floors (for buildings)

#### 2. **Services** (`lib/services/`)
- **`geojson_loader.dart`**: Loads and parses GeoJSON files
  - Converts GeoJSON features to model objects
  - Exports models back to GeoJSON format

#### 3. **Screens** (`lib/screens/`)
- **`outdoor_map_screen.dart`**: Main map UI
  - OSM tile layer rendering
  - Dynamic path visualization with color-coded difficulty
  - Place markers with categorized colors
  - Layer toggle functionality
  - Bottom sheet info panels

#### 4. **Data Files** (`assets/data/`)
- **`campus_paths.geojson`**: LineString features for paths
- **`campus_places.geojson`**: Point features for locations

## Features Implemented

✅ **Map Rendering**
- OpenStreetMap tiles via flutter_map
- Custom path overlays with difficulty colors
- Place markers with context-specific icons

✅ **Data Management**
- GeoJSON-based data storage
- Easy-to-edit JSON structure
- Extensible properties system

✅ **User Interaction**
- Click on places to view details
- Toggle layers on/off
- Center on campus button
- Path difficulty legend

## How to Add Custom Data

### Step 1: Edit GeoJSON Files

#### Adding a New Path
Open `assets/data/campus_paths.geojson` and add a new feature:

```json
{
  "type": "Feature",
  "id": "path_custom_1",
  "geometry": {
    "type": "LineString",
    "coordinates": [
      [77.0495, 28.5355],
      [77.0500, 28.5360],
      [77.0505, 28.5365]
    ]
  },
  "properties": {
    "id": "path_custom_1",
    "name": "Custom Path Name",
    "walkable": true,
    "pathType": "concrete",        // Options: concrete, grass, asphalt
    "difficulty": "easy",           // Options: easy, medium, hard
    "wheelchair_accessible": true,
    "restrictions": null,           // Options: null, "no_vehicles", "no_bikes", "no_vehicles,no_bikes"
    "description": "Path description"
  }
}
```

#### Adding a New Place
Open `assets/data/campus_places.geojson` and add a new feature:

```json
{
  "type": "Feature",
  "id": "place_custom_1",
  "geometry": {
    "type": "Point",
    "coordinates": [77.0510, 28.5365]
  },
  "properties": {
    "id": "place_custom_1",
    "name": "Place Name",
    "placeType": "building",        // Options: building, parking, landmark, restroom
    "department": "Department Name",
    "description": "Description of the place",
    "imageUrl": null,
    "floors": 3,
    "hasIndoorMap": false
  }
}
```

### Step 2: Update Coordinates

**Getting GPS Coordinates:**
1. Go to [OpenStreetMap](https://www.openstreetmap.org/)
2. Right-click on the location
3. Copy latitude and longitude
4. Use format: `[longitude, latitude]` (note the order!)

### Step 3: Customize Appearance

#### Path Colors by Difficulty
- **Easy**: Blue
- **Medium**: Orange
- **Hard**: Dark Red

#### Place Icons by Type
- **Building**: Apartment icon
- **Parking**: Parking icon
- **Landmark**: Pin icon
- **Restroom**: WC icon

## Usage

### Run the App
```bash
flutter pub get
flutter run
```

### Map Controls
- **Zoom**: Pinch or scroll
- **Pan**: Drag the map
- **Center**: Tap the blue location button
- **Info**: Tap any place marker
- **Layers**: Tap the layers icon to toggle paths/places

## Extending the System

### Add Custom Path Attributes
Edit `lib/models/path_model.dart` to add new properties:
```dart
final String? newAttribute;
```

### Add New Place Types
Update `_getPlaceIcon()` and `_getPlaceColor()` in `outdoor_map_screen.dart`

### Connect to Database
Replace GeoJSON loading with API calls in `geojson_loader.dart`:
```dart
static Future<List<CampusPath>> loadPathsFromAPI() async {
  final response = await http.get(Uri.parse('your-api-url'));
  // Parse response and return paths
}
```

## Next Steps

1. **Replace Sample Data**: Update coordinates and places to match your campus
2. **Update Default Location**: Change `defaultLocation` in `outdoor_map_screen.dart`
3. **Add More Attributes**: Extend models for specific campus needs
4. **Implement Indoor Navigation**: Create indoor map screens for buildings with `hasIndoorMap: true`
5. **Add Route Finding**: Implement pathfinding algorithm for turn-by-turn navigation

## Dependencies

- `flutter_map`: Map rendering
- `latlong2`: Coordinate handling
- `geolocator`: Location services (prepared for future use)
- `http`: API calls (prepared for future use)

## File Structure
```
lib/
├── main.dart
├── models/
│   ├── path_model.dart
│   └── place_model.dart
├── services/
│   └── geojson_loader.dart
└── screens/
    └── outdoor_map_screen.dart

assets/data/
├── campus_paths.geojson
└── campus_places.geojson
```

---

**Note**: All coordinates in this example are sample data for a location in Delhi. Replace with your actual campus coordinates.
