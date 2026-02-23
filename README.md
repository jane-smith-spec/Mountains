# PeakLine

An AR smartphone app that identifies mountain peaks by overlaying topographic
horizon profiles on your camera view.

Point your phone at mountains → see their names, elevations, and distances.
Also works on existing photos, even without compass data.

## Project Structure

```
Mountains/
├── peakline_app/     Flutter mobile app (Dart)
├── native_core/      C computation library (DEM, ray-casting, matching)
├── tools/            Python data preparation scripts
└── docs/             Algorithm documentation
```

## Prerequisites

You'll need these installed on your Windows machine. Open **Git Bash** for all
terminal commands.

### 1. Flutter SDK

1. Download from https://docs.flutter.dev/get-started/install/windows/mobile
2. Extract to `C:\flutter` (or wherever you prefer)
3. Add `C:\flutter\bin` to your Windows PATH:
   - Windows search → "Environment Variables" → Path → Edit → New → `C:\flutter\bin`
4. Restart Git Bash, then verify:
   ```bash
   flutter --version
   ```

### 2. Android Studio

1. Download from https://developer.android.com/studio
2. During install, ensure these are checked:
   - Android SDK
   - Android SDK Command-line Tools
   - Android SDK Build-Tools
3. After install, open Android Studio → **Tools → SDK Manager**:
   - **SDK Platforms** tab: install Android 14 (API 34) or newer
   - **SDK Tools** tab: check **NDK (Side by side)** and **CMake** → Apply
4. Accept Android licenses:
   ```bash
   flutter doctor --android-licenses
   ```
5. Set up a device:
   - **Emulator**: Android Studio → Tools → Device Manager → Create Device
   - **Physical phone**: Enable Developer Options + USB Debugging on your phone,
     connect via USB

### 3. Python 3

1. Download from https://www.python.org/downloads/
2. During install, check **"Add Python to PATH"**
3. Verify:
   ```bash
   python --version
   ```

### 4. Verify Everything

Run Flutter's built-in diagnostic:
```bash
flutter doctor
```

You should see green checkmarks for:
- Flutter (the SDK itself)
- Android toolchain (Android Studio + SDK)
- Connected device (emulator or USB phone)

Don't worry about Chrome/Visual Studio/Xcode — we don't need those right now.

## Quick Start

### Run the Flutter app
```bash
cd peakline_app
flutter pub get          # Download dependencies
flutter run              # Build and run on connected device/emulator
```

### Build and test the C core
```bash
cd native_core
mkdir build && cd build
cmake ..
cmake --build .
./run_tests              # Should show all tests passing
```

On Windows with Git Bash, you may need:
```bash
cmake .. -G "MinGW Makefiles"
cmake --build .
./run_tests.exe
```

## Current Status

**Step 1: Project Scaffold** — Complete. The app shows a "Hello PeakLine"
welcome screen and the C core builds with passing tests.

See `PLAN.md` for the full 20-step implementation plan.
