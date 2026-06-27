# Forsa Horizon 6 — Android (APK)

An **Android** build of the open-world racer. Because the iOS game is written in
Swift/SceneKit (iOS-only), the Android version is a separate build: a **3D WebGL
game (Three.js)** wrapped in a lightweight Android **WebView** app, packaged as
an installable **APK**.

> Original, brand-free game for personal use. Not affiliated with Forza Horizon.

## Install the APK (no Play Store needed)

1. Download **`ForsaHorizon6.apk`** from the repo's
   [latest release](../../releases/latest).
2. On your Android phone, open it and allow **“Install unknown apps”** for your
   browser/Files app when prompted.
3. Install and launch — it runs full-screen in landscape.

The release APK is a **debug-signed** build (auto-signed with the standard debug
key), which is directly sideloadable. It is not a Play Store release.

## Controls
- **Left side:** ◀ / ▶ steer
- **Right side:** ▲ gas, ▼ brake/reverse

## How it's built
- `app/src/main/assets/index.html` — the Three.js 3D game (city, roads,
  buildings, mountains, drivable car, chase camera).
- `app/src/main/assets/three.min.js` — Three.js r128 (MIT), bundled for offline.
- `app/src/main/java/com/forsa/horizon/MainActivity.kt` — WebView host.
- CI (`.github/workflows/build-apk.yml`) builds `assembleDebug` on an Ubuntu
  runner and attaches the APK to the release.

Build locally: `cd AndroidGame && gradle assembleDebug` (or open in Android Studio).
