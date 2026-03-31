# GeoJSON Data Format Guide

## Quick Reference

### Coordinate System
- Format: `[longitude, latitude]` (NOT latitude first!)
- Example: `[77.0500, 28.5355]` means: 77.05°E, 28.53°N
- Get coordinates from [OpenStreetMap](https://www.openstreetmap.org/)

## Path Types & Attributes

### Path Difficulty Colors
| Difficulty | Color | Use Case |
|------------|-------|----------|
| easy | Blue 🔵 | Main walkways, accessible paths |
| medium | Orange 🟠 | Secondary paths, some terrain |
| hard | Dark Red 🔴 | Hiking trails, steep slopes |

### Path Types
| Type | Example | Wheelchair Accessible |
|------|---------|----------------------|
| concrete | Paved walkways | ✅ Yes |
| asphalt | Roads, parking lots | ✅ Yes |
| grass | Gardens, fields | ⚠️ Sometimes |

### Path Restrictions
- `null` - No restrictions
- `"no_vehicles"` - Walking/biking only
- `"no_bikes"` - Walking only
- `"no_vehicles,no_bikes"` - Hiking trail only

## Complete Examples

### Example 1: Main Campus Walkway
```json
{
  "type": "Feature",
  "id": "path_main_entrance_1",
  "geometry": {
    "type": "LineString",
    "coordinates": [
      [77.0495, 28.5355],
      [77.0500, 28.5358],
      [77.0505, 28.5360]
    ]
  },
  "properties": {
    "id": "path_main_entrance_1",
    "name": "Main Entrance to Administration",
    "walkable": true,
    "pathType": "concrete",
    "difficulty": "easy",
    "wheelchair_accessible": true,
    "restrictions": null,
    "description": "Well-lit main pathway connecting entrance to admin building"
  }
}
```

### Example 2: Garden Trail
```json
{
  "type": "Feature",
  "id": "path_garden_trail_1",
  "geometry": {
    "type": "LineString",
    "coordinates": [
      [77.0485, 28.5350],
      [77.0480, 28.5345],
      [77.0475, 28.5340],
      [77.0470, 28.5335]
    ]
  },
  "properties": {
    "id": "path_garden_trail_1",
    "name": "Botanical Garden Path",
    "walkable": true,
    "pathType": "grass",
    "difficulty": "easy",
    "wheelchair_accessible": false,
    "restrictions": "no_vehicles",
    "description": "Scenic natural path through campus gardens"
  }
}
```

### Example 3: Hiking Trail
```json
{
  "type": "Feature",
  "id": "path_hiking_north_1",
  "geometry": {
    "type": "LineString",
    "coordinates": [
      [77.0525, 28.5375],
      [77.0530, 28.5380],
      [77.0535, 28.5385],
      [77.0540, 28.5390]
    ]
  },
  "properties": {
    "id": "path_hiking_north_1",
    "name": "North Hill Hiking Trail",
    "walkable": true,
    "pathType": "grass",
    "difficulty": "hard",
    "wheelchair_accessible": false,
    "restrictions": "no_vehicles,no_bikes",
    "description": "Challenging hiking trail with elevation. Contains stairs and steep sections."
  }
}
```

## Place Types & Icons

| Type | Icon | Examples | Has Floors |
|------|------|----------|-----------|
| building | Apartment | Library, Office, Lab | Yes |
| parking | P | Parking lots | No |
| restroom | WC | Toilets | No |
| landmark | Pin | Cafeteria, Garden | No |

## Complete Place Examples

### Example 1: Academic Building
```json
{
  "type": "Feature",
  "id": "place_science_building_1",
  "geometry": {
    "type": "Point",
    "coordinates": [77.0515, 28.5370]
  },
  "properties": {
    "id": "place_science_building_1",
    "name": "Science & Technology Building",
    "placeType": "building",
    "department": "Engineering & Science",
    "description": "Modern research facility with labs and classrooms. Located between Library and Sports Complex.",
    "imageUrl": null,
    "floors": 4,
    "hasIndoorMap": true
  }
}
```

### Example 2: Parking Lot
```json
{
  "type": "Feature",
  "id": "place_parking_north_1",
  "geometry": {
    "type": "Point",
    "coordinates": [77.0475, 28.5340]
  },
  "properties": {
    "id": "place_parking_north_1",
    "name": "North Parking Lot",
    "placeType": "parking",
    "department": null,
    "description": "Large parking area with 500+ spaces. Near main entrance.",
    "imageUrl": null,
    "floors": null,
    "hasIndoorMap": false
  }
}
```

### Example 3: Cafeteria
```json
{
  "type": "Feature",
  "id": "place_cafeteria_main_1",
  "geometry": {
    "type": "Point",
    "coordinates": [77.0495, 28.5355]
  },
  "properties": {
    "id": "place_cafeteria_main_1",
    "name": "Main Student Cafeteria",
    "placeType": "landmark",
    "department": null,
    "description": "Multi-outlet cafeteria with snacks, meals, and beverages. Open 7 AM - 8 PM daily.",
    "imageUrl": null,
    "floors": null,
    "hasIndoorMap": false
  }
}
```

### Example 4: Public Restrooms
```json
{
  "type": "Feature",
  "id": "place_restroom_central_1",
  "geometry": {
    "type": "Point",
    "coordinates": [77.0505, 28.5352]
  },
  "properties": {
    "id": "place_restroom_central_1",
    "name": "Central Restrooms",
    "placeType": "restroom",
    "department": null,
    "description": "Public restrooms with accessible facilities. Available 24/7.",
    "imageUrl": null,
    "floors": null,
    "hasIndoorMap": false
  }
}
```

## How to Collect Campus Data

### Option 1: Using OpenStreetMap
1. Visit [OpenStreetMap.org](https://www.openstreetmap.org/)
2. Search for your campus
3. Right-click any location to copy coordinates
4. Record coordinates in `[lon, lat]` format

### Option 2: Using Google Maps
1. Go to [Google Maps](https://maps.google.com/)
2. Right-click on location → Copy coordinates
3. Google gives: `lat,lon` format
4. **Reverse it for GeoJSON!** Use: `[lon, lat]`

### Option 3: Using Your Phone's GPS
1. Open Maps app
2. Long-press point → See coordinates
3. Manually record and format as `[lon, lat]`

## Editing Tips

### Bulk Add Multiple Points as a Path
Create a path between related locations:
```json
{
  "type": "LineString",
  "coordinates": [
    [77.0495, 28.5355],  // Start: Gate
    [77.0500, 28.5360],  // Middle: Main path
    [77.0505, 28.5365],  // Middle: Near library
    [77.0510, 28.5370]   // End: Library
  ]
}
```

### Add Intermediate Points for Curved Paths
More points = smoother curve:
```json
// Two points (straight line)
"coordinates": [[77.0495, 28.5355], [77.0510, 28.5370]]

// More points (curved line)
"coordinates": [
  [77.0495, 28.5355],
  [77.0500, 28.5360],
  [77.0505, 28.5365],
  [77.0510, 28.5370]
]
```

## File Structure Template

```json
{
  "type": "FeatureCollection",
  "features": [
    {
      "type": "Feature",
      "id": "path_1",
      "geometry": {
        "type": "LineString",
        "coordinates": [...]
      },
      "properties": {...}
    },
    {
      "type": "Feature",
      "id": "path_2",
      "geometry": {
        "type": "LineString",
        "coordinates": [...]
      },
      "properties": {...}
    }
  ]
}
```

## Common Mistakes to Avoid

❌ **Wrong:** `"coordinates": [28.5355, 77.0495]` (lat first)
✅ **Correct:** `"coordinates": [77.0495, 28.5355]` (lon first)

❌ **Wrong:** Missing commas between array elements
✅ **Correct:** `[77.0495, 28.5355], [77.0500, 28.5360]`

❌ **Wrong:** Using `"building"` for a parking lot
✅ **Correct:** Use `"placeType": "parking"`

❌ **Wrong:** Leaving required fields empty
✅ **Correct:** Provide id, name, and location for all features

## Testing Your GeoJSON

### Option 1: Online Validator
Visit [geojson.io](https://geojson.io/) and paste your GeoJSON to visualize it

### Option 2: VS Code
Install "GeoJSON" extension by RandomFractalsIO for syntax highlighting

### Option 3: JSON Validator
Any JSON validator will catch syntax errors - use [jsonlint.com](https://www.jsonlint.com/)

---

**Pro Tip:** Keep your GeoJSON files properly formatted. Use an online formatter if needed: [jsoncrack.com](https://jsoncrack.com/)
