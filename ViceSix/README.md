# Vice Six — top-down open-world action (iPhone)

An original, top-down open-world crime game for iOS in the spirit of the
classic GTA games, built **from scratch** with **SwiftUI + SpriteKit** — no
third-party dependencies, no asset files (every sprite is drawn in code, and
the city is generated procedurally from a fixed seed).

> "Vice Six" is an original parody title for personal use. It is **not** GTA
> or GTA VI, is not affiliated with Rockstar Games, and uses no Rockstar
> assets, maps, characters, or branding. Everything here — the city of Port
> Leon, its districts, cars, and characters — is invented for this project.

## Features

- **Two playable leads** — Mia (runs faster) and Jax (longer punch reach).
  Swap between them any time on foot; missions hand you the right one.
- **Open city: Port Leon** — a 10×10-block island grid with **six districts**
  (Neon Mile, Port Leon Docks, Palm Shores, Casa Vieja, Grove Heights,
  Ironside), parks, plazas, a beach ring, and landmark spots: hospital,
  police HQ, garage, bank, safehouse, airstrip, and marina.
- **On foot & behind the wheel** — walk, run, punch, and carjack anything in
  traffic: 8 original car models (from the Pico compact to the Vipera GT)
  with arcade physics, damage, and a wrecked-engine state. Repair at the
  garage, heal at the hospital.
- **Living streets** — ambient traffic that follows lanes, stops for
  obstacles and picks turns at intersections; pedestrians who wander, flee,
  and dive out of your way.
- **Wanted system, up to ★★★★★★ (VI stars)** — carjackings, hit-and-runs and
  assaults raise heat. VCPD cruisers path through the real road grid (BFS),
  box you in to bust you, and open fire at 3+ stars. Lay low to let the heat
  decay. Get **BUSTED** or **WASTED** and you respawn lighter in the wallet.
- **VI story missions** — deliveries, a timed checkpoint run, a car heist,
  a bank job with a getaway, and a final dash to the airstrip, alternating
  between Mia and Jax. Cash and progress persist between launches.
- **The details** — day/night cycle, chase camera with speed zoom, minimap
  with district colours and cop/objective blips, off-screen objective arrow,
  floating cash pickups, sirens, horn that scatters crowds.

## Realism layer

- **Tyre-model driving physics** — every powered car integrates a real
  velocity vector with engine power curves, braking, aero drag, and lateral
  grip: momentum carries through corners, the tail steps out under hard
  cornering, and sliding tyres leave fading **skid marks** and screech.
- **Working traffic signals** — every intersection runs a staggered
  green/yellow/red cycle (a rough green wave). Traffic holds at the stop
  line with **brake lights** flaring; you're free to run reds.
- **Weather** — rain fronts roll through: rain streaks, a wet sheen,
  drivers slow down, and road grip genuinely drops (drifts get long).
- **Night** — headlight cones on every car and warm street-lamp pools fade
  in with the 7-minute day/night cycle.
- **Damage you can see** — dents appear as a car wears down, the windshield
  cracks near the end, then the engine smokes and dies.
- **Street texture** — crosswalks, curb lines, side mirrors, steering front
  wheels, rooftop AC units and vents, and pedestrians with striding feet
  who mostly keep to the street grid.
- **Fully synthesized audio, zero assets** — engine note that rises with
  revs, tyre screech, doppler-ish siren wail, rain bed, horn, gunshots and
  crash thumps are all rendered sample-by-sample by one `AVAudioSourceNode`
  (`SoundEngine.swift`).

## Controls

- **Left half of the screen:** floating joystick — walk on foot; in a car it
  steers and accelerates (pull opposite your nose at low speed to reverse).
- **Bottom-right buttons:** ENTER/EXIT car · PUNCH (on foot) / HORN (in car)
  · SWAP character (on foot).
- Walk or drive into the cyan **VI** marker on the Neon Mile to start the
  next mission.

## Running it

1. Open `ViceSix.xcodeproj` in **Xcode 15+**.
2. Pick an iPhone simulator (or device) and press **⌘R**.
   - On a physical device, set your Apple ID **Team** under Signing &
     Capabilities.
- Landscape only. Minimum deployment target: **iOS 16.0**.

## Project layout

| File | Responsibility |
|------|----------------|
| `ViceSixApp.swift` | App entry point |
| `ContentView.swift` | SwiftUI HUD, minimap, menus, BUSTED/WASTED cards |
| `GameScene.swift` | The whole simulation: player, driving, traffic, peds, police, wanted, missions, camera |
| `GameState.swift` | Observable HUD state + gameplay constants |
| `City.swift` | Seeded procedural city: districts, blocks, buildings, landmarks |
| `Entities.swift` | Car catalog & car/ped/avatar/marker node factories |
| `Missions.swift` | The VI-mission story definitions |
| `Joystick.swift` | Floating touch joystick |
| `SoundEngine.swift` | Sample-level synthesized audio (engine, siren, rain, impacts) |

Tune the city in `City.swift` (grid size, districts), the driving feel in
`CarCatalog` (`Entities.swift`), and the police pressure in `GameConfig`
(`GameState.swift`).
