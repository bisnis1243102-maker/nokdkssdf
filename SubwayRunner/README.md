# Subway Dash (Android APK)

A Subway Surfers-style endless runner, built as a Three.js WebGL game wrapped
in a tiny Android WebView app.

## Gameplay

- Endless level structure: **2 levels, then a BOSS — forever**, with the
  scenery cycling day → sunset → night → dawn after each boss
- Boss fights: a flying mech telegraphs lane bombs (switch lanes!), low
  lasers (jump!) and high lasers (roll!) — survive all waves to blow it up
  and earn a +50 coin bonus; each boss gets more waves and faster attacks
- 3-lane subway track — **swipe left / right** to change lanes
- **Swipe up** to jump over hurdles, **swipe down** to roll under signs
- Dodge parked **and oncoming** trains
- Grab coins; find **Magnet** (pulls coins in for 8s) and **Jetpack**
  (fly over everything for 6s) power-ups
- Speed ramps up the farther you run; best distance is saved on-device

Keyboard also works (arrows / WASD, Enter to start) for desktop testing —
just open `app/src/main/assets/index.html` in a browser.

## Getting the APK

Every push that touches `SubwayRunner/` runs the **Build APK (Android)**
workflow, which attaches `SubwayDash.apk` to the repo's **latest** GitHub
Release. It is a debug-signed build: download it on your phone, allow
"install unknown apps", and install.

## Building locally

Requires JDK 17, the Android SDK, and Gradle 8.x:

```bash
cd SubwayRunner
gradle assembleDebug
# -> app/build/outputs/apk/debug/app-debug.apk
```
