# Liberty Drive — 3D open-world driving sandbox (iPhone)

An original, stylized 3D open-world driving game for iOS, built with
**SwiftUI + SceneKit**, no third-party dependencies. Drive freely around a city
of named districts.

> This is an **original** game inspired by the open-world driving genre — it is
> **not** GTA and does not use any Rockstar assets, maps, or branding. The
> visuals are deliberately stylized/low-poly (a phone game built in one pass),
> not photorealistic.

## Features

- **Drivable car** with arcade physics (acceleration, braking, reverse,
  speed-sensitive steering) and a smooth chase camera.
- **Open city** you can roam, with **9 named districts**: Downtown, Financial
  District, Chinatown, The Docks, Sunset Beach, Vespucci Airfield, Industrial
  Park, Old Town, Little Hills — each with its own colour and skyline.
- **Buildings you can't drive through** (collision), parks with trees, a road
  grid, plus waterfront and beach edges.
- **HUD**: live speedometer (km/h), current district name, distance driven, and
  a **minimap** with your position.

## Controls

- **Left side:** ◀ / ▶ steer
- **Right side:** ▲ gas, ▼ brake / reverse

## Running it

1. Open `LibertyDrive.xcodeproj` in **Xcode 15+**.
2. Pick an iPhone simulator (or your device) and press **⌘R**.
   - On a physical device, set your Apple ID **Team** under Signing & Capabilities.
- Minimum deployment target: **iOS 16.0**

## Project layout

| File | Responsibility |
|------|----------------|
| `LibertyDriveApp.swift` | App entry point |
| `ContentView.swift` | SwiftUI HUD, controls, minimap |
| `CityScene.swift` | SceneKit world, car, driving physics, chase camera |
| `DriveModel.swift` | Shared input/HUD state |
| `World.swift` | District grid + map dimensions |

Tweak the map size and districts in `World.swift`, and the driving feel
(power, drag, steering) in `CityScene.swift`.
