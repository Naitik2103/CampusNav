# How to Add Campus Paths - Step by Step Guide

## 🗺️ Using OpenStreetMap to Extract Coordinates

### Method 1: Simple Straight Path (2 Points)

**Scenario:** Add path from Red Marker to Lotus Pond

#### Step 1: Open OpenStreetMap
```
1. Visit: https://www.openstreetmap.org/
2. Search for "Dhirubhai Ambani University" or your campus
3. Zoom in to see your locations
```

#### Step 2: Get Start Point (Red Marker)
```
1. RIGHT-CLICK on the red marker location
2. Look at address bar or coordinates display
3. Note: Latitude, Longitude format
   Example: 23.18456, 72.62341
4. CONVERT to GeoJSON: [72.62341, 23.18456]
   (Swap to [Longitude, Latitude])
```

#### Step 3: Get End Point (Lotus Pond)
```
1. RIGHT-CLICK on Lotus Pond location
2. Note coordinates shown
   Example: 23.18512, 72.62289
3. CONVERT: [72.62289, 23.18512]
```

#### Step 4: Create Path Feature
```json
{
  "type": "Feature",
  "id": "gate_to_lotus_pond",
  "geometry": {
    "type": "LineString",
    "coordinates": [
      [72.62341, 23.18456],
      [72.62289, 23.18512]
    ]
  },
  "properties": {
    "id": "gate_to_lotus_pond",
    "name": "Main Gate to Lotus Pond",
    "walkable": true,
    "pathType": "concrete",
    "difficulty": "easy",
    "wheelchair_accessible": true,
    "restrictions": null,
    "description": "Direct path from gate to Lotus Pond"
  }
}
```

---

### Method 2: Curved Path (Multiple Points)

**Scenario:** Path that curves around a building

#### Step 1-2: Get Start & End Points (Same as above)

#### Step 3: Get Intermediate Points
```
If path curves, get middle points:
1. Right-click at first curve point
2. Get coordinates
3. Right-click at next curve point
4. Get coordinates
5. Repeat for all curves
```

**Example trajectory:**
```
Start: Red Marker [72.62341, 23.18456]
    ↓ (curves around building)
Middle1: [72.62350, 23.18470]
    ↓ (continues curving)
Middle2: [72.62300, 23.18495]
    ↓ (final approach)
End: Lotus Pond [72.62289, 23.18512]
```

#### Step 4: Create Curved Path
```json
{
  "type": "Feature",
  "id": "gate_to_lotus_curved",
  "geometry": {
    "type": "LineString",
    "coordinates": [
      [72.62341, 23.18456],
      [72.62350, 23.18470],
      [72.62300, 23.18495],
      [72.62289, 23.18512]
    ]
  },
  "properties": {
    "id": "gate_to_lotus_curved",
    "name": "Gate to Lotus Pond (Main Route)",
    "walkable": true,
    "pathType": "concrete",
    "difficulty": "easy",
    "wheelchair_accessible": true,
    "restrictions": null,
    "description": "Main walking path around campus to Lotus Pond"
  }
}
```

---

## 📝 Path Properties Reference

### `pathType` Options
- `"concrete"` - Paved walkways, main paths
- `"asphalt"` - Roads, parking areas
- `"grass"` - Natural grass areas, gardens
- `"gravel"` - unpaved paths

### `difficulty` Options
- `"easy"` - Flat, accessible paths
- `"medium"` - Some slopes, secondary paths
- `"hard"` - Steep, hiking trails

### `restrictions` Options
- `null` - No restrictions (default)
- `"no_vehicles"` - Walking/biking only
- `"no_bikes"` - Walking only
- `"no_vehicles,no_bikes"` - Hiking trail only

### `wheelchair_accessible` Options
- `true` - Smooth, accessible path
- `false` - Not accessible (stairs, rough terrain)

---

## 🔧 How to Edit campus_paths.geojson

### Using VS Code:

1. **Open file:**
   ```
   File → Open File
   → assets/data/campus_paths.geojson
   ```

2. **Locate the last path feature** (scroll to bottom)

3. **Add comma after last }:**
   ```json
   {
     "type": "Feature",
     ...last feature...
   },  ← ADD THIS COMMA
   ```

4. **Paste your new path:**
   ```json
   {
     "type": "Feature",
     "id": "gate_to_lotus_pond",
     ...your new path...
   }
   ```

5. **Save:** `Ctrl+S`

6. **Hot reload in Flutter:** Press `r` in terminal

---

## 🎯 Example: Complete Addition

### Before (Last Feature):
```json
{
  "type": "Feature",
  "id": "path_hill_1",
  "geometry": {
    "type": "LineString",
    "coordinates": [......]
  },
  "properties": {...}
}  ← NO COMMA
```

### After (Add New Path):
```json
{
  "type": "Feature",
  "id": "path_hill_1",
  "geometry": {
    "type": "LineString",
    "coordinates": [......]
  },
  "properties": {...}
},  ← COMMA ADDED
{
  "type": "Feature",
  "id": "gate_to_lotus_pond",
  "geometry": {
    "type": "LineString",
    "coordinates": [
      [72.62341, 23.18456],
      [72.62289, 23.18512]
    ]
  },
  "properties": {
    "id": "gate_to_lotus_pond",
    "name": "Main Gate to Lotus Pond",
    "walkable": true,
    "pathType": "concrete",
    "difficulty": "easy",
    "wheelchair_accessible": true,
    "restrictions": null,
    "description": "Direct path from gate to Lotus Pond"
  }
}  ← NO COMMA (last feature)
```

---

## 🚨 Common Mistakes to Avoid

❌ **Wrong coordinate order**
```json
"coordinates": [23.18456, 72.62341]  // WRONG (lat, lon)
```
✅ **Correct coordinate order**
```json
"coordinates": [72.62341, 23.18456]  // RIGHT (lon, lat)
```

❌ **Missing comma between features**
```json
{...}
{...}  // ERROR
```
✅ **Correct comma placement**
```json
{...},
{...}  // RIGHT
```

❌ **Duplicate IDs**
```json
{"id": "path_1", ...}
{"id": "path_1", ...}  // ERROR - duplicate
```
✅ **Unique IDs**
```json
{"id": "path_1", ...}
{"id": "path_2", ...}  // RIGHT
```

---

## ✅ Validation Checklist

Before saving, verify:
- [ ] All coordinates in `[lon, lat]` order
- [ ] JSON syntax valid (no missing quotes/brackets)
- [ ] All paths have unique `id` values
- [ ] Required properties present: id, name, walkable, pathType, difficulty
- [ ] File ends properly (last feature has NO comma)
- [ ] Commas between features (all except last)

**Test online:** https://geojson.io/
- Paste your GeoJSON
- Should show lines on map
- No syntax errors displayed

---

## 📱 Quick Workflow

1. **Open OSM** → Find locations
2. **Get coordinates** → Note them down
3. **Create JSON** → Use template above
4. **Edit file** → Add to campus_paths.geojson
5. **Save** → `Ctrl+S`
6. **Hot reload** → Press `r` in Flutter terminal
7. **See on map** → New path appears!

---

## 🎓 Your First Path

**For your red marker → Lotus Pond scenario:**

1. Find coordinates on OSM for both locations
2. Replace these values:
   - `[START_LON, START_LAT]` 
   - `[END_LON, END_LAT]`
3. Give it a meaningful name
4. Choose `pathType`, `difficulty`, `wheelchair_accessible`
5. Add to GeoJSON file
6. See it on your map!

---

**Need help?** Check [GEOJSON_GUIDE.md](GEOJSON_GUIDE.md) for more examples.
