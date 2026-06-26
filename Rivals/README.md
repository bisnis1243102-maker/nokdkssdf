# Rivals — iPhone Arena Shooter

A native iOS twin-stick arena shooter inspired by the Roblox game **Rivals**.
Built with **SwiftUI** + **SpriteKit**, no third-party dependencies.

## Gameplay

- **Move:** touch and drag anywhere on the **left** half of the screen (floating joystick).
- **Aim & fire:** touch and drag on the **right** half — your fighter aims that way and auto-fires.
- **Survive waves** of enemies. Each wave gets bigger and faster.
- **Enemy types:**
  - 🔴 **Chasers** rush you and explode on contact.
  - 🔺 **Shooters** keep their distance and fire back.
- Score points per kill. Your **best score** is saved between runs.

## Running it

1. Open `Rivals.xcodeproj` in **Xcode 15** or newer.
2. Select an **iPhone simulator** (or your own device) as the run destination.
3. Press **⌘R**.

> Running on a physical iPhone requires signing: select the **Rivals** target →
> **Signing & Capabilities** → pick your Apple ID **Team**. The simulator needs no signing.

- Minimum deployment target: **iOS 16.0**
- Orientation: portrait (iPhone), all orientations on iPad

## Project layout

| File | Responsibility |
|------|----------------|
| `RivalsApp.swift` | App entry point |
| `ContentView.swift` | SwiftUI shell: menu, HUD, game-over overlays |
| `GameScene.swift` | SpriteKit scene — game loop, waves, spawning, contacts |
| `Entities.swift` | `Player`, `Enemy`, `Bullet` nodes |
| `Joystick.swift` | Floating on-demand virtual joystick |
| `GameState.swift` | Shared observable state + tunable `GameConfig` |

Tweak difficulty, speeds, and damage in `GameConfig` (in `GameState.swift`).
