# PeakLine: Smartphone AR Topo Map App — Implementation Plan

## Overview

A cross-platform mobile app that overlays real-time topographic horizon profiles
on the camera view, identifying and labeling mountain peaks and landmarks. Also
supports retroactive identification from existing photos (even without compass data).

**Your environment:** Windows with Git Bash. We'll set up all tooling for that.

---

## What This App Does (Plain English)

1. **Live AR Mode:** You point your phone at mountains. The app uses GPS (where you
   are) and the compass (which way you're looking) to figure out what mountains are
   in front of you. It draws a topo line over the camera view matching the ridgeline,
   and puts little flags on each peak with its name, elevation, and distance.

2. **Photo Mode:** You feed it a mountain photo you already took. If the photo has
   GPS and compass data embedded (most phones do this), it works like live mode but
   on the still image. If compass data is missing, the app figures out which direction
   you were facing by matching the shape of the mountains in the photo against what
   the terrain data says the mountains *should* look like from that GPS position.

3. **Togglable Layers:** Peaks, landmarks (huts, lakes, passes), and the topo line
   itself can each be turned on/off independently.

---

## Architecture & Technology Choices

| Decision | Choice | Why |
|----------|--------|-----|
| Framework | **Flutter** (Dart) + C core via FFI | Cross-platform (iOS + Android from one codebase). Flutter is beginner-friendly with great docs. C core keeps the math fast. |
| DEM source | **Copernicus GLO-30** (30m resolution) | Best free global elevation data available. ~30 meter grid squares. |
| DEM on-device | Int16 tiles in SQLite, LZ4 compressed | One file per region, fast to decompress, easy to manage. |
| Multi-resolution | 30m near, 90m mid, 250m far | You don't need fine detail for mountains 50km away. Saves ~10x storage. |
| AR approach | **Custom sensor fusion** (compass + gyro + accelerometer) | No heavy AR framework needed. We're overlaying on distant mountains, not close objects. |
| Peak database | OpenStreetMap peaks + GeoNames | Free, global, community-maintained. ~500K peaks worldwide. |
| Photo matching | Normalized cross-correlation (NCC) | Compares the shape of the skyline in your photo against computed profiles. Simple and effective. |
| State management | **Riverpod** | Modern Flutter state management. Clean, testable. |

### How the Layers Fit Together

```
┌──────────────────────────────────────────────────────────┐
│  FLUTTER UI  (what you see on screen)                    │
│  Camera preview with painted overlay: topo line,         │
│  peak flags, landmark pins, compass, toggle buttons      │
├──────────────────────────────────────────────────────────┤
│  DART LOGIC  (the "brains")                              │
│  Reads sensors, manages state, projects 3D world         │
│  coordinates onto 2D screen pixels                       │
├──────────────────────────────────────────────────────────┤
│  C CORE via FFI  (the "math engine" — runs at full speed)│
│  Loads elevation tiles, does ray-casting to compute      │
│  the horizon profile, matches skylines for photos        │
├──────────────────────────────────────────────────────────┤
│  DEVICE PLATFORM  (iOS / Android)                        │
│  Camera hardware, GPS, compass, gyroscope, file storage  │
└──────────────────────────────────────────────────────────┘
```

**Why a C core?** The horizon computation involves millions of elevation lookups per
frame. Dart is fine for UI but too slow for this math. C runs ~10-50x faster and
compiles natively on both iOS and Android through Flutter's FFI (Foreign Function
Interface). I'll write the C code and the FFI bindings — you won't need to learn C.

---

## Project Structure

```
Mountains/
├── PLAN.md                          # This file
├── README.md                        # Project overview and setup instructions
│
├── peakline_app/                    # The Flutter application
│   ├── pubspec.yaml                 # Dependencies and project metadata
│   ├── lib/
│   │   ├── main.dart                # App entry point
│   │   ├── app.dart                 # MaterialApp setup, routing
│   │   ├── core/                    # Shared utilities
│   │   │   ├── constants.dart       # Max range, angular resolution, etc.
│   │   │   ├── coordinate_utils.dart# Lat/lon math (haversine, bearing, etc.)
│   │   │   └── projection.dart      # World coords → screen pixel coords
│   │   ├── data/                    # Data access layer
│   │   │   ├── dem_repository.dart  # DEM tile loading via FFI
│   │   │   ├── peak_repository.dart # Peak/landmark DB queries
│   │   │   ├── tile_manager.dart    # Multi-resolution tile selection
│   │   │   └── photo_repository.dart# Photo import + EXIF extraction
│   │   ├── models/                  # Data classes
│   │   │   ├── horizon_profile.dart # Array of (azimuth, elevation_angle) points
│   │   │   ├── peak.dart            # Peak: name, lat, lon, elevation
│   │   │   ├── landmark.dart        # Landmark: name, type, lat, lon
│   │   │   ├── observer_state.dart  # Your position + which way you're looking
│   │   │   └── tile_index.dart      # Which DEM tile to load
│   │   ├── services/                # Business logic
│   │   │   ├── sensor_service.dart  # Fuses compass/gyro/accelerometer
│   │   │   ├── location_service.dart# GPS position stream
│   │   │   ├── horizon_service.dart # Orchestrates profile computation
│   │   │   ├── skyline_matcher.dart # Photo → heading matching
│   │   │   └── camera_service.dart  # Camera stream management
│   │   ├── ui/
│   │   │   ├── screens/             # Full-page views
│   │   │   │   ├── live_view_screen.dart     # Main AR camera view
│   │   │   │   ├── photo_view_screen.dart    # Analyze an existing photo
│   │   │   │   ├── settings_screen.dart      # Preferences
│   │   │   │   └── region_download_screen.dart# Download elevation data
│   │   │   ├── widgets/             # Reusable UI components
│   │   │   │   ├── horizon_overlay.dart      # The topo line drawn over camera
│   │   │   │   ├── peak_flag.dart            # Flag + label for a peak
│   │   │   │   ├── landmark_pin.dart         # Togglable landmark marker
│   │   │   │   ├── compass_indicator.dart    # Shows current heading
│   │   │   │   ├── elevation_readout.dart    # Shows your altitude
│   │   │   │   └── toggle_panel.dart         # On/off switches for layers
│   │   │   └── painters/            # Custom drawing code
│   │   │       ├── horizon_painter.dart      # Draws the topo polyline
│   │   │       └── grid_painter.dart         # Optional bearing/elevation grid
│   │   └── ffi/
│   │       ├── native_bridge.dart   # Dart ↔ C bindings
│   │       └── ffi_types.dart       # FFI struct definitions
│   ├── assets/
│   │   └── peak_database/           # Bundled peak DB (SQLite)
│   ├── android/
│   ├── ios/
│   └── test/                        # Dart/Flutter tests
│       ├── core/
│       │   ├── coordinate_utils_test.dart
│       │   └── projection_test.dart
│       ├── models/
│       │   └── horizon_profile_test.dart
│       ├── services/
│       │   ├── horizon_service_test.dart
│       │   └── skyline_matcher_test.dart
│       └── widgets/
│           └── horizon_overlay_test.dart
│
├── native_core/                     # C computation library
│   ├── CMakeLists.txt               # Build configuration
│   ├── include/                     # Header files (API declarations)
│   │   ├── peakline.h
│   │   ├── dem_io.h
│   │   ├── raycaster.h
│   │   ├── interpolation.h
│   │   ├── curvature.h
│   │   └── skyline_match.h
│   ├── src/                         # Implementation files
│   │   ├── dem_io.c
│   │   ├── raycaster.c
│   │   ├── interpolation.c
│   │   ├── curvature.c
│   │   ├── skyline_match.c
│   │   └── peakline_api.c           # The functions Dart calls
│   └── test/                        # C unit tests
│       ├── test_raycaster.c
│       ├── test_interpolation.c
│       └── test_skyline_match.c
│
├── tools/                           # Data preparation scripts (Python)
│   ├── prepare_dem_tiles.py         # Downloads & converts elevation data
│   ├── extract_peaks_osm.py        # Extracts peak database from OSM
│   └── generate_test_fixtures.py    # Creates fake DEM data for testing
│
└── docs/
    └── algorithms.md                # Detailed algorithm explanations
```

---

## Core Algorithms (How It Works)

### 1. Horizon Profile Generation — "What mountains can I see?"

This is the heart of the app. We "cast rays" outward from your position across the
elevation data to figure out the horizon shape.

**Analogy:** Imagine standing on a hilltop and slowly spinning 360°. At each angle,
you note the highest point you can see on the horizon. That's the horizon profile.

```
FUNCTION compute_horizon_profile(observer, dem, azimuth_start, azimuth_end, step):
    // For each compass direction in the camera's field of view...
    FOR azimuth = azimuth_start TO azimuth_end STEP step:
        max_angle = -90°  (looking straight down — nothing blocks that)

        // March outward from 100m to 100km, checking terrain height
        FOR distance = 100m TO 100km:
            (lat, lon) = point_at_distance(observer, azimuth, distance)
            terrain_height = lookup_elevation(dem, lat, lon)

            // Earth curves away — distant ground is lower than you'd think
            curvature_drop = distance² / (2 × 6,371,000m × 1.13)
            effective_height = terrain_height - curvature_drop

            // What angle do I look up (or down) to see this point?
            angle = atan2(effective_height - my_altitude, distance)

            // Only keep the HIGHEST angle (closest ridgeline blocks what's behind)
            IF angle > max_angle:
                max_angle = angle

        SAVE (azimuth, max_angle) to profile

    RETURN profile   // A series of (direction, angle) pairs = the ridgeline shape
```

### 2. Screen Projection — "Where on my screen is that mountain?"

Converts each point in the horizon profile to a pixel position on the camera view.

```
FUNCTION project_to_screen(azimuth, elevation_angle, camera_heading, camera_pitch,
                           field_of_view_h, field_of_view_v, screen_w, screen_h):
    // How far left/right of center is this point?
    relative_azimuth = azimuth - camera_heading

    // How far up/down from center?
    relative_elevation = elevation_angle - camera_pitch

    // Map to pixels
    x = (relative_azimuth / half_fov_h) × half_screen_w + half_screen_w
    y = half_screen_h - (relative_elevation / half_fov_v) × half_screen_h

    RETURN (x, y)
```

### 3. Peak Identification — "Which mountains have names?"

Cross-references the horizon profile with a database of known peaks.

```
FOR each known peak within 100km:
    1. Compute the compass bearing from me to the peak
    2. Compute the elevation angle to the peak's summit (accounting for curvature)
    3. Check if the peak is actually visible (not hidden behind a closer ridge)
    4. If visible → add a flag at the correct screen position
```

### 4. Skyline Matching — "Which way was I facing in this old photo?"

For photos without compass data: extract the mountain silhouette from the photo,
then slide it along the 360° horizon profile looking for the best match.

```
1. Segment the sky from the terrain in the photo (ML model)
2. Extract the sky/terrain boundary as a 1D curve
3. Compute the full 360° horizon profile from the photo's GPS position
4. Slide the photo's curve along the 360° profile
5. At each position, compute a similarity score (normalized cross-correlation)
6. The position with the highest score = the direction you were facing
```

---

## Implementation Phases (Detailed)

Each phase ends with a testable deliverable. We build incrementally so you can see
progress and catch problems early.

---

### Phase 1: Foundation & Core Computation

**What we build:** Camera preview with a live horizon line overlay.

**Steps (I will code, you'll do the manual setup steps marked with YOU):**

1. **YOU: Install Flutter SDK on Windows**
   - Download Flutter SDK from flutter.dev
   - Extract to a folder (e.g., `C:\flutter`)
   - Add `C:\flutter\bin` to your Windows PATH environment variable
   - Open Git Bash and run: `flutter doctor`
   - This will tell you what else you need (Android Studio, etc.)
   - Follow its instructions to resolve any issues

2. **YOU: Install Android Studio**
   - Download from developer.android.com
   - During install, make sure "Android SDK" and "Android SDK Command-line Tools" are checked
   - Open Android Studio → Tools → SDK Manager → install Android SDK 34+
   - Accept licenses: run `flutter doctor --android-licenses` in Git Bash
   - Set up an Android emulator OR connect a physical Android device via USB

3. **YOU: Install a C compiler toolchain**
   - Android NDK (comes with Android Studio: SDK Manager → SDK Tools → NDK)
   - For desktop testing: install MinGW-w64 or use the GCC that comes with Git Bash
   - We'll also need CMake (Android Studio includes it, or install separately)

4. **YOU: Install Python 3.x** (for data preparation tools later)
   - Download from python.org, check "Add to PATH" during install
   - Verify in Git Bash: `python --version`

5. **I create the Flutter project** (`flutter create peakline_app`)

6. **I build the native C core:**
   - `native_core/src/interpolation.c` — bilinear interpolation on elevation grids
   - `native_core/src/curvature.c` — Earth curvature + refraction math
   - `native_core/src/dem_io.c` — loads raw .hgt elevation tile files
   - `native_core/src/raycaster.c` — the ray-casting horizon profile engine
   - `native_core/src/peakline_api.c` — clean API that Dart calls

7. **I write C tests** and a desktop test harness so we can verify the math works
   before ever running on a phone

8. **I build the Dart FFI bridge** connecting Flutter to the C core

9. **I build the sensor service** (compass + gyro + GPS readings)

10. **I build the camera preview screen** with CustomPainter horizon overlay

11. **I write the screen projection math** (world coords → screen pixels)

**Tests for Phase 1:**
- C unit tests: interpolation accuracy, curvature formula, ray-cast against known DEM
- Dart unit tests: coordinate math (haversine, bearing), projection math
- Integration test: load a sample .hgt file, compute profile, verify output shape
- Manual test: run on phone/emulator, see horizon line over camera

**Deliverable:** Point your phone at mountains → see a topo line drawn over them.

---

### Phase 2: Peak Identification & Labels

**What we build:** Peak name flags and landmark pins on the overlay.

**Steps:**

1. **I create the peak database** extraction tool (`tools/extract_peaks_osm.py`)
   - **YOU: Download an OSM data extract** for a test region (I'll give you the URL)
   - Run the script to generate the SQLite peak database

2. **I build the peak visibility algorithm** (is this peak hidden behind a closer ridge?)

3. **I build the peak flag widget** — shows peak name, elevation in meters, distance

4. **I build the landmark system** — same concept but for huts, lakes, passes, etc.

5. **I build the toggle panel** — floating buttons to turn layers on/off

6. **I add compass indicator and elevation readout widgets**

**Tests for Phase 2:**
- Unit test: peak visibility algorithm with mock profile data
- Unit test: peak flag positioning for known observer/peak pairs
- Widget test: toggle panel state management
- Manual test: point at known peaks, verify labels are correct and positioned right

**Deliverable:** Live view with named peak flags and togglable landmarks.

---

### Phase 3: DEM Data Pipeline & Region Management

**What we build:** Downloadable elevation data packs, offline support.

**Steps:**

1. **I build the DEM preparation tool** (`tools/prepare_dem_tiles.py`)
   - Downloads Copernicus GLO-30 tiles for a region
   - Converts to multi-resolution tiles
   - Packs into a single compressed SQLite file

2. **YOU: Register for a free Copernicus account** (I'll provide the URL)
   - This gives API access to download elevation data

3. **I build the tile manager** — picks the right resolution based on distance

4. **I build the region download screen** — map where you select an area to download

5. **I wire up offline support** — all computation works without internet

**Tests for Phase 3:**
- Unit test: tile manager selects correct resolution at various distances
- Integration test: full pipeline from raw Copernicus → app tile format → profile
- Manual test: turn airplane mode on, app still works with cached data

**Deliverable:** Download regional data packs, app works fully offline.

---

### Phase 4: Photo Analysis Mode

**What we build:** Import a mountain photo, get peaks identified.

**Steps:**

1. **I build the photo import flow** — pick from gallery, read EXIF metadata

2. **I build the "with compass data" path** — straightforward overlay on the image

3. **I build the sky segmentation model integration** (TensorFlow Lite on-device)
   - Uses a pre-trained model to separate sky from terrain in the photo

4. **I build the skyline extraction** — finds the sky/terrain boundary

5. **I build the NCC matching algorithm** — slides the extracted skyline along
   the computed 360° profile to find the best match

6. **I build the manual adjustment fallback** — drag the overlay left/right
   to fine-tune alignment if auto-matching isn't perfect

**Tests for Phase 4:**
- Unit test: NCC matching with synthetic skyline data (known correct heading)
- Unit test: EXIF extraction for various photo formats
- Integration test: end-to-end with a real mountain photo + DEM data
- Manual test: import photos from various phones, verify peak identification

**Deliverable:** Import any mountain photo → get peaks labeled.

---

### Phase 5: Polish & Advanced Features

**What we build:** Smooth, production-quality experience.

- Kalman filter for smooth heading/pitch (reduces jitter)
- Gyro-stabilized overlay (compass is noisy; gyro smooths short-term)
- Visual skyline lock (snap the topo line to actual mountain edges)
- Share annotated photos
- Distance/elevation ruler tool
- Bookmarked viewpoints
- Dark mode / night hiking mode
- Performance optimization if needed

---

## Data Requirements

### DEM Data (Copernicus GLO-30)
- **Source:** ESA Copernicus (free, requires registration)
- **Resolution:** 1 arc-second (~30m)
- **Storage per region:** ~15–60 MB compressed (depends on area size)
- **Not bundled** — downloaded per-region by the user

### Peak Database
- **Source:** OpenStreetMap `natural=peak` nodes + GeoNames
- **Contents:** name, latitude, longitude, elevation, prominence
- **Global size:** ~20 MB SQLite (all ~500K peaks)
- **Bundled** with the app

### Landmark Database
- **Source:** OpenStreetMap (huts, shelters, lakes, passes, glaciers, towns)
- **Togglable categories** so the view doesn't get cluttered
- **Storage:** ~5 MB per region

---

## Testing Strategy

We test at every layer. You'll be able to run all of these from Git Bash.

| Layer | Tool | What It Tests | How to Run |
|-------|------|---------------|------------|
| C core math | Custom C test harness + assertions | Interpolation, curvature, ray-casting, NCC matching | `cd native_core && cmake --build build && ./build/run_tests` |
| Dart logic | `flutter test` (built-in) | Coordinate math, projection, peak visibility, state management | `cd peakline_app && flutter test` |
| Flutter widgets | `flutter test` (widget tests) | UI components render correctly, toggles work, flags position right | `cd peakline_app && flutter test` |
| Integration | `flutter test integration_test/` | Full pipeline: load DEM → compute profile → render overlay | `cd peakline_app && flutter test integration_test/` |
| On-device | Manual + `flutter drive` | Camera, sensors, GPS, real-world accuracy | Deploy to phone, point at known peaks |

**Key test fixtures we'll create:**
- A small synthetic DEM (simple cone-shaped "mountain") with a known correct horizon profile
- A set of known peak coordinates with expected visibility from a test observer position
- Synthetic skyline images with known headings for matching tests

---

## Key Technical Risks & How We Handle Them

| Risk | What Goes Wrong | Our Mitigation |
|------|----------------|----------------|
| Compass is noisy (5–10° off) | Overlay doesn't line up with real mountains | Gyro smoothing + optional visual lock to real edges |
| DEM downloads are large | Bad first-run experience | Multi-resolution (saves 10x), progress bars, start with small test region |
| Ray-casting is slow | Laggy, jittery overlay | C core (not Dart), only compute visible FOV, variable step sizes |
| Sky segmentation fails | Photo matching gives wrong heading | Manual drag-to-align fallback |
| Camera FOV unknown (old photos) | Overlay too wide or narrow | Estimate from EXIF focal length, or let user adjust a slider |

---

## Dependencies (Flutter Packages)

| Package | What It Does |
|---------|-------------|
| `camera` | Access the phone camera for live preview |
| `sensors_plus` | Read compass, gyroscope, accelerometer |
| `geolocator` | Get GPS position |
| `sqflite` | SQLite database (for DEM tiles and peak DB) |
| `ffi` / `ffigen` | Connect Dart to our C code |
| `image_picker` | Let user pick a photo from their gallery |
| `exif` | Read GPS/compass/focal length from photo metadata |
| `flutter_map` | Map view for selecting download regions |
| `path_provider` | Find the right folder to store data on the device |
| `riverpod` | State management (clean way to share data between widgets) |
| `dio` | HTTP client for downloading DEM tiles |
| `tflite_flutter` | Run ML model for sky segmentation (Phase 4) |

---

## Glossary

Terms you'll encounter throughout the project:

| Term | Meaning |
|------|---------|
| **DEM** | Digital Elevation Model — a grid of elevation values covering the Earth's surface |
| **Copernicus GLO-30** | A specific DEM dataset from ESA at ~30m resolution |
| **SRTM** | Shuttle Radar Topography Mission — older DEM dataset, similar concept |
| **.hgt file** | Raw elevation data file format: a grid of 16-bit integers (heights in meters) |
| **Ray-casting** | Shooting an imaginary line outward from your position to see what it hits |
| **Horizon profile** | The "ridgeline shape" — for each compass direction, how high above horizontal the terrain appears |
| **Azimuth** | Compass direction in degrees (0°=North, 90°=East, 180°=South, 270°=West) |
| **Elevation angle** | How far above (positive) or below (negative) the horizontal a point appears |
| **FOV** | Field of View — how wide an angle the camera sees (typically ~60–70° horizontal) |
| **Bilinear interpolation** | Estimating a value between four known grid points (like reading between the lines on graph paper) |
| **NCC** | Normalized Cross-Correlation — a way to measure how similar two signals (skyline shapes) are |
| **FFI** | Foreign Function Interface — how Dart calls C functions |
| **EXIF** | Metadata embedded in photos (GPS position, compass heading, camera model, focal length, etc.) |
| **CustomPainter** | Flutter's way to draw custom graphics (lines, shapes) on screen |
| **Riverpod** | A state management library for Flutter — how different parts of the app share data |
| **SQLite** | A lightweight database stored as a single file — great for mobile |
| **Curvature correction** | Adjusting for the fact that the Earth is round — distant ground drops away |
| **Atmospheric refraction** | Light bends slightly in the atmosphere, making distant mountains appear ~13% taller than pure geometry predicts |
