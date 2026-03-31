# Campus Routing Setup Guide

## Problem: Routes Going Outside Campus

Your routing service was returning paths that went outside your campus boundary. This has been fixed with a **campus-constrained routing service** that keeps all routes within your defined campus bounds.

---

## Solution Implemented

✅ **New Features Added:**
1. **CampusRoutingService** - Constrains routes to stay within campus
2. **CampusConfig** - Centralized configuration management
3. **Updated OutdoorMapScreen** - Uses campus-constrained routing by default

---

## How to Configure Your Campus Boundaries

### Step 1: Get Your Campus Corners

Use Google Maps to find your campus's four corners:

1. Open **Google Maps**
2. Search for your campus
3. Zoom in to see the campus boundaries
4. Identify these corners:
   - **Northeast (NE)**: Top-right corner
   - **Northwest (NW)**: Top-left corner
   - **Southwest (SW)**: Bottom-left corner
   - **Southeast (SE)**: Bottom-right corner

### Step 2: Get Coordinates

For each corner, click on the map to see its coordinates:
- Right-click on each corner point
- Copy the latitude and longitude

Example coordinates:
```
Northeast:  23.190, 72.630
Northwest:  23.190, 72.627
Southwest:  23.186, 72.627
Southeast:  23.186, 72.630
```

### Step 3: Update Configuration

Edit `lib/config/campus_config.dart`:

```dart
static const List<LatLng> campusBoundary = [
  LatLng(23.190, 72.630),  // Northeast - YOUR_NE_LAT, YOUR_NE_LNG
  LatLng(23.190, 72.627),  // Northwest - YOUR_NW_LAT, YOUR_NW_LNG
  LatLng(23.186, 72.627),  // Southwest - YOUR_SW_LAT, YOUR_SW_LNG
  LatLng(23.186, 72.630),  // Southeast - YOUR_SE_LAT, YOUR_SE_LNG
];
```

### Step 4: Update Campus Center

Also update the campus center point:

```dart
static const LatLng campusCenter = LatLng(23.188, 72.6285);
// This should be roughly in the middle of your campus
```

---

## How It Works

### Before Fix:
```
User Location → OSRM calculates shortest path → Route may go outside campus ❌
```

### After Fix:
```
User Location → OSRM calculates path → Constrain waypoints to campus bounds → Route stays on campus ✅
```

### The Process:
1. **Fetch Route** - Get route from OSRM using actual road data
2. **Check Boundaries** - Verify each waypoint is within campus
3. **Snap to Campus** - If a waypoint is outside, snap it to nearest boundary
4. **Display Route** - Show the constrained route as a blue line

---

## Testing Your Configuration

After updating `campus_config.dart`:

1. **Run the app** - `flutter run`
2. **Get your location** - Click the location button
3. **Search for a place** - Type a building name
4. **Request route** - Click the directions icon
5. **Verify** - Check that the blue line stays within campus

### Expected Result:
- 🟢 Routes stay entirely within campus boundaries
- 🟢 No routes going outside campus to external roads
- 🟢 All waypoints align with campus paths

---

## Fine-Tuning

### If routes are still going outside:
- **Make campus boundary smaller** - Reduce the corner coordinates
- **Check boundary order** - Must be counterclockwise: NE → NW → SW → SE

### If routes are too constrained:
- **Make campus boundary larger** - Expand the corner coordinates
- **Add more boundary points** - If campus is not rectangular

### Example Rectangular Campus:
```
        NW -------- NE
        |           |
        |  CAMPUS   |
        |           |
        SW -------- SE
```

---

## Files Modified

- ✅ `lib/services/campus_routing_service.dart` - New service
- ✅ `lib/config/campus_config.dart` - Configuration file
- ✅ `lib/screens/outdoor_map_screen.dart` - Updated to use new service

---

## Debugging

To see what's happening:

1. **Check console logs** - Look for "Campus-Constrained Route" messages
2. **Print configuration** - In Dart:
   ```dart
   CampusConfig.printConfiguration();
   ```

3. **Check bounds** - In Dart:
   ```dart
   final bounds = CampusConfig.getBounds();
   print(bounds);
   ```

---

## Need Help?

If routes still don't work correctly:
1. Verify your campus boundary corners are correct
2. Ensure coordinates are in (Latitude, Longitude) format
3. Check that campus center is roughly in the middle
4. Try expanding the boundary if it's too small

---

## Next Steps (Optional)

For even better control:
- Use GeoJSON campus boundary instead of fixed corners
- Load boundary from your `campus_places.geojson`
- Create multiple route options (shortest, safest, etc.)
