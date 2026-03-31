# Quick Start Guide: Campus Outdoor Navigation

## 🚀 Get Started in 3 Steps

### Step 1: Install Dependencies
```bash
cd new_project
flutter pub get
```

### Step 2: Run the App
```bash
flutter run
```

### Step 3: Customize for Your Campus
Replace sample campus coordinates with your actual campus data

---

## 📍 What's Already Set Up

✅ **Working Features:**
- Map displays OSM (OpenStreetMap) tiles
- Sample campus paths with color-coded difficulty
- Sample places/buildings with clickable markers
- Layer toggle (show/hide paths and places)
- Info panels when tapping places
- Center on campus button

✅ **Data Files Ready:**
- `assets/data/campus_paths.geojson` - Paths with attributes
- `assets/data/campus_places.geojson` - Buildings and locations

✅ **Code Structure:**
```
lib/
├── main.dart                           # Entry point
├── models/                             # Data models
│   ├── path_model.dart                # Path data structure
│   └── place_model.dart               # Place data structure
├── services/
│   └── geojson_loader.dart            # GeoJSON parser
├── screens/
│   └── outdoor_map_screen.dart        # Main map UI
└── utils/
    └── campus_data_helper.dart        # Helper for adding data
```

---

## 🎯 Next: Customize for Your Campus

### 1. Find Your Campus Coordinates
- Open [OpenStreetMap](https://www.openstreetmap.org/)
- Search for your campus
- Right-click any spot → note the coordinates
- Format: `[longitude, latitude]`

### 2. Update Default Location
Open [lib/screens/outdoor_map_screen.dart](lib/screens/outdoor_map_screen.dart):
```dart
// Line: static const LatLng defaultLocation = LatLng(28.5355, 77.0500);
// Change to your campus center:
static const LatLng defaultLocation = LatLng(YOUR_LAT, YOUR_LON);
```

### 3. Map Your Campus Paths
Edit `assets/data/campus_paths.geojson`:

**Add simple walkway:**
```bash
# Or copy the template from GEOJSON_GUIDE.md and modify coordinates
```

**Add hiking trail:**
```bash
# Mark as difficulty: "hard" with appropriate coordinates
```

**Add accessible paths:**
```bash
# Set wheelchairAccessible: true for main paths
```

See [GEOJSON_GUIDE.md](GEOJSON_GUIDE.md) for complete examples

### 4. Mark Your Campus Places
Edit `assets/data/campus_places.geojson`:

**Add buildings:**
```bash
# Set placeType: "building" with floor count
```

**Add parking:**
```bash
# Set placeType: "parking"
```

**Add landmarks:**
```bash
# Set placeType: "landmark" for cafes, gardens, etc.
```

---

## 🗺️ Path Difficulty Reference

| Color | Difficulty | Use Case |
|-------|-----------|----------|
| 🔵 Blue | Easy | Main walkways, accessible paths |
| 🟠 Orange | Medium | Secondary paths, terrain |
| 🔴 Red | Hard | Hiking trails, steep slopes |

---

## 📍 Place Icons

| Icon | Type | Examples |
|------|------|----------|
| 🏢 | Building | Library, Classrooms, Labs |
| 🅿️ | Parking | Parking lots |
| 🚻 | Restroom | Public facilities |
| 📍 | Landmark | Cafeteria, Garden, Monument |

---

## 🔧 How to Add New Data

### Quick Method: Use Helpers
```dart
import 'lib/utils/campus_data_helper.dart';

// Create a path
final myPath = CampusPathHelper.createMainPath(
  'path_new',
  'My Path',
  [LatLng(28.535, 77.050), LatLng(28.536, 77.051)]
);

// Create a building
final myBuilding = CampusPlaceHelper.createBuilding(
  'place_new',
  'My Building',
  LatLng(28.537, 77.052),
  'Department Name',
  floors: 3,
);
```

### Manual Method: Edit GeoJSON
1. Open `assets/data/campus_paths.geojson` or `campus_places.geojson`
2. Add new feature in the "features" array
3. Follow examples in [GEOJSON_GUIDE.md](GEOJSON_GUIDE.md)
4. Save and run `flutter run` - changes appear immediately

---

## 🐛 Troubleshooting

### Map doesn't show or appears blank
- Check your default location coordinates
- Ensure internet connection (OSM tiles are online)
- Verify `lat,lon` order is correct

### Custom paths don't appear
- Verify coordinates in GeoJSON are in `[lon, lat]` format
- Check JSON syntax is valid (no missing commas)
- Ensure file is saved before running

### Places don't show
- Check coordinates are within your map viewport
- Verify `placeType` is one of: building, parking, landmark, restroom
- Ensure required properties (id, name, location) are present

---

## 📚 Documentation Files

- **[OUTDOOR_NAVIGATION_SETUP.md](OUTDOOR_NAVIGATION_SETUP.md)** - Full architecture guide
- **[GEOJSON_GUIDE.md](GEOJSON_GUIDE.md)** - Data format with examples
- **[lib/utils/campus_data_helper.dart](lib/utils/campus_data_helper.dart)** - Helper code

---

## 🎨 Customization Ideas

Once basic setup works, try adding:

1. **Indoor Maps** - Switch to indoor floor plan for buildings with `hasIndoorMap: true`
2. **Route Finding** - Add pathfinding algorithm
3. **Real Location** - Enable GPS to show user position
4. **Search** - Search for buildings, places
5. **Favorites** - Save favorite locations
6. **Navigation** - Turn-by-turn directions
7. **Events** - Mark events at locations
8. **Accessibility** - Highlight wheelchair routes

---

## 💡 Tips

- **No internet?** Pre-cache maps or use offline tiles
- **Large campus?** Split into multiple GeoJSON files by zone
- **Frequent updates?** Move data to a backend API
- **Social features?** Add user-submitted paths and reviews
- **Offline indoor maps?** Use floor plan images at each building marker

---

## 📞 Need Help?

Check these resources:
- [flutter_map documentation](https://pub.dev/packages/flutter_map)
- [GeoJSON specification](https://geojson.org/)
- [OpenStreetMap wiki](https://wiki.openstreetmap.org/)

---

**Ready to run?** 
```bash
flutter pub get
flutter run
```

Tap places to view info. Use layer button to toggle paths/places. 🗺️
