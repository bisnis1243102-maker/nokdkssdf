# Billiard — iPhone Pool Game

A native iOS **8-ball-style pool/billiards** game built with **SwiftUI +
SpriteKit** physics. No third-party dependencies.

## How to play
- A full rack of 15 balls + the cue ball on a felt table with 6 pockets.
- **Aim:** touch and **drag back from the cue ball** (slingshot) — the line
  shows direction, its colour shows power.
- **Release** to shoot. Balls roll, bounce off the cushions, and drop into pockets.
- Sink all 15 to win. Potting the cue ball is a **scratch** (it respawns).
- Tap **RE-RACK** (top-right) to reset.

## Running it
1. Open `Billiard.xcodeproj` in **Xcode 15+**.
2. Pick an iPhone simulator (or device) and press **⌘R**.
- Minimum deployment target: **iOS 16.0**.

## Files
| File | Responsibility |
|------|----------------|
| `BilliardApp.swift` | App entry point |
| `ContentView.swift` | Hosts the SpriteKit scene |
| `GameScene.swift` | Table, balls, cue physics, aiming, pockets, scoring |
