# Campus Outdoor Navigation

A Flutter application for outdoor campus navigation using OpenStreetMap and GeoJSON data.

## Features

- 🗺️ **Interactive OSM Map**: Browse your campus with OpenStreetMap tiles
- 🛤️ **Custom Paths**: Add walking trails, sidewalks, and specialized paths
- 📍 **Location Markers**: Mark buildings, parking lots, cafeterias, and landmarks
- 🎨 **Color-Coded Difficulty**: Paths color-coded by difficulty level (easy/medium/hard)
- 🔖 **Place Information**: Tap on locations to see detailed information
- 🔄 **Layer Toggle**: Show/hide paths and places as needed
- ♿ **Accessibility Info**: Mark wheelchair-accessible routes
- 🏢 **Indoor Map Ready**: Prepared for indoor navigation in buildings

## Getting Started

### Installation
```bash
cd new_project
flutter pub get
flutter run
```

### Quick Test
Run the app to see a sample campus with example paths and places.

### Customize for Your Campus

1. **Update Campus Location**
   - Edit [lib/screens/outdoor_map_screen.dart](lib/screens/outdoor_map_screen.dart)
   - Change `defaultLocation` to your campus center GPS coordinates

2. **Map Paths**
   - Edit [assets/data/campus_paths.geojson](assets/data/campus_paths.geojson)
   - Add/update walking routes, trails, shortcuts
   - See [GEOJSON_GUIDE.md](GEOJSON_GUIDE.md) for format

3. **Add Places**
   - Edit [assets/data/campus_places.geojson](assets/data/campus_places.geojson)
   - Add buildings, parking, landmarks
   - Include department info and floor counts

## Documentation

- **[QUICKSTART.md](QUICKSTART.md)** - 3-step setup guide ⭐ *Start here*
- **[OUTDOOR_NAVIGATION_SETUP.md](OUTDOOR_NAVIGATION_SETUP.md)** - Full architecture
- **[GEOJSON_GUIDE.md](GEOJSON_GUIDE.md)** - Data format with examples
- **[PROJECT_STATUS.md](PROJECT_STATUS.md)** - Implementation status
- **[IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)** - What's included & next steps

## Project Structure

```
lib/
├── main.dart                      # App entry point
├── models/
│   ├── path_model.dart           # Path data model
│   └── place_model.dart          # Place data model
├── services/
│   └── geojson_loader.dart       # GeoJSON parser
├── screens/
│   └── outdoor_map_screen.dart   # Main map UI
└── utils/
    └── campus_data_helper.dart   # Helper utilities

assets/data/
├── campus_paths.geojson          # Walking paths data
└── campus_places.geojson         # Places/buildings data
```

## Path Attributes

Each path can have:
- **Name**: Path identifier
- **Walkable**: Is pedestrian access allowed?
- **Path Type**: concrete, asphalt, grass, etc.
- **Difficulty**: easy, medium, hard
- **Wheelchair Accessible**: True/false
- **Restrictions**: null, "no_vehicles", "no_bikes", etc.
- **Description**: Additional information

Colors on map:
- 🔵 **Blue** = Easy paths
- 🟠 **Orange** = Medium difficulty
- 🔴 **Red** = Hard/hiking trails

## Place Types

Supported place types with icons:
- **Building** (🏢 Apartment): Academic buildings, offices, labs
- **Parking** (🅿️): Parking areas
- **Landmark** (📍): Cafeteria, gardens, monuments
- **Restroom** (🚻): Public facilities

## Adding Custom Data

### Simple Method: Binary Choose
Start with [QUICKSTART.md](QUICKSTART.md) and follow the 3-step guide.

### GeoJSON Method: Manual Entry
Use [GEOJSON_GUIDE.md](GEOJSON_GUIDE.md) with complete examples.

### Programmatic Method: Code Helpers
Use [lib/utils/campus_data_helper.dart](lib/utils/campus_data_helper.dart):

```dart
import 'lib/utils/campus_data_helper.dart';

final path = CampusPathHelper.createMainPath(
  'path_1',
  'Main Walkway',
  [LatLng(28.5355, 77.0495), LatLng(28.5360, 77.0500)],
);

final place = CampusPlaceHelper.createBuilding(
  'place_1',
  'Library',
  LatLng(28.5365, 77.0505),
  'Academic Affairs',
  floors: 5,
);
```

## Getting Coordinates

Use [OpenStreetMap](https://www.openstreetmap.org/):
1. Right-click on location
2. Copy coordinates
3. **Remember**: GeoJSON uses `[longitude, latitude]` not `[lat, lon]`

## Dependencies

- **flutter_map** (6.0.0) - Map rendering
- **latlong2** (0.9.0) - GPS coordinate handling
- **geolocator** (9.0.0) - Location services
- **http** (1.1.0) - API calls

## Future Enhancements

- [ ] Real-time user location
- [ ] Route finding/pathfinding
- [ ] Turn-by-turn navigation
- [ ] Indoor floor maps
- [ ] Search functionality
- [ ] Favorites/bookmarks
- [ ] Accessibility routing
- [ ] Offline map caching

## Architecture

- **Models**: GeoJSON serializable data structures
- **Services**: Handles data loading and parsing
- **Screens**: UI components
- **Utils**: Helper functions for data creation
- **Assets**: GeoJSON data files

All models support full GeoJSON conversion for easy persistence.

## Testing

```bash
# Run tests
flutter test

# Build production
flutter build apk
flutter build ios

# Check for issues
flutter analyze
```

## Troubleshooting

### Map shows blank?
- Check internet connection (OSM tiles require online access)
- Verify coordinates are valid
- Try zooming in/out

### Custom data not showing?
- Verify JSON syntax is valid
- Check coordinates are in `[lon, lat]` order
- Ensure required fields are present
- Clear app cache and restart

### Want to go offline?
- Pre-cache map tiles
- Store GeoJSON locally
- Remove internet dependency from network requests

## Resources

- [OpenStreetMap](https://www.openstreetmap.org/)
- [GeoJSON Specification](https://geojson.org/)
- [flutter_map Documentation](https://pub.dev/packages/flutter_map)
- [GeoJSON Validator](https://geojson.io/)

## License

This project is licensed under the MIT License.

---

**Ready to map your campus?** 🗺️

1. Read [QUICKSTART.md](QUICKSTART.md)
2. Run `flutter run`
3. Customize with your campus data
4. Share with your community!

