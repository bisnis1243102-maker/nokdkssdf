# Apex MX

A 2.5D side-scrolling motocross racer for iOS, built in Swift with SwiftUI and
SpriteKit on top of an original, deterministic vehicle-physics core.

Everything in this project is original: the physics model, the track
generator, the bike and rider artwork (assembled from vector primitives at
runtime), the interface, the machines and the courses.

---

## Requirements

| | |
|---|---|
| Xcode | 15.0 or newer |
| iOS deployment target | 16.0 |
| Devices | iPhone and iPad, landscape only |
| Language | Swift 5, no third-party dependencies |

## Building

```bash
open ApexMX/ApexMX.xcodeproj
```

Select the **ApexMX** scheme and a device or simulator, then ⌘R.

The project has no package dependencies and no code-signing requirements for
simulator builds. For a device build, set your team under
**Target ▸ Signing & Capabilities**; `DEVELOPMENT_TEAM` is intentionally left
empty in the checked-in configuration.

### Running the tests

⌘U, or:

```bash
xcodebuild test -project ApexMX/ApexMX.xcodeproj -scheme ApexMX \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Archiving an unsigned IPA

```bash
xcodebuild archive -project ApexMX/ApexMX.xcodeproj -scheme ApexMX \
  -configuration Release -archivePath build/ApexMX.xcarchive \
  CODE_SIGNING_ALLOWED=NO
```

Then package `build/ApexMX.xcarchive/Products/Applications/ApexMX.app` into a
`Payload/` directory and zip it as `ApexMX.ipa`.

---

## How it plays

Hold **throttle** to accelerate, **front** and **rear brake** to slow down, and
**lean back / lean forward** to shift the rider's weight. Weight transfer is
the core skill: it loads the suspension before a jump, sets the bike's attitude
in the air, and decides whether a landing carries speed or scrubs it.

In the air you have three tools:

- **Throttle** spins the rear wheel up and pitches the nose *up*.
- **Rear brake** slows it and pitches the nose *down*.
- **Lean** rotates the bike directly.

Land with the bike's angle matched to the slope you are landing on and you keep
your momentum. Land badly and you lose speed, or crash. The crash overlay always
names the reason and tells you what to do differently — you should never lose
without understanding why.

---

## Architecture at a glance

```
ApexMX/
├── App/            GameCoordinator, app entry point and routing
├── Core/           Vector maths, fixed timestep, deterministic RNG, logging
├── GameData/       Bike specs, tracks, surfaces, upgrades — pure data
├── Physics/        Terrain, track builder, rigid-body bike simulation
├── Gameplay/       Race session, riders, AI, ghosts, career progression
├── Rendering/      SpriteKit scene, bike/terrain/backdrop nodes, particles
├── Input/          Touch controls, haptics
├── UI/             Design system and every screen
├── SaveSystem/     Player profile, persistence, ghost storage
└── DeveloperTools/ Live physics telemetry overlay
```

The dependency direction is strictly one way: `Physics` knows nothing about
`Gameplay`, `Gameplay` knows nothing about `Rendering` or `UI`, and no layer
below `UI` imports SwiftUI. A `RaceSession` can therefore be stepped headlessly
— for balance testing, replay validation, or a future server — with no
rendering involved.

Full details are in [`Documentation/Architecture.md`](Documentation/Architecture.md)
and [`Documentation/Physics.md`](Documentation/Physics.md).

---

## What makes it fair

Three properties are enforced by construction, not by convention:

**The simulation is deterministic.** No wall-clock reads, no system randomness,
no framework calls inside the solver. `DeterministicRandom` (SplitMix64) drives
every generated value. Identical inputs against identical state produce
identical output on every device, every run.

**Physics is frame-rate independent.** Everything advances in fixed 1/240 s
steps via `FixedTimestepAccumulator`, whatever the display is doing. A 120 Hz
iPhone and a 60 Hz iPad simulate exactly the same race.

**AI has no hidden advantages.** Opponents run the same `BikePhysicsBody`, on
the same terrain, and can only act by filling in a `RiderInput` — the same
structure the touch controls produce. Difficulty is expressed entirely through
reaction time, input precision, risk tolerance, jump timing and recovery skill.
There is no rubber-banding and no catch-up assistance; opponent strength is
fixed before the gate drops.

All three are pinned by tests in `ApexMXTests/`.

---

## Content

**Machines** — Scout FX250 (250 class, light and forgiving), Vantage R450
(450 class, torque and mass), Apex Prototype (open class, fastest and least
forgiving). Five upgrade categories, five levels each; a fully built machine is
roughly 20% quicker, deliberately not enough to outweigh skill.

**Tracks** — Ridgeline Park, Copper Flats, Ironworks and Summit Ridge, each
authored as an ordered list of features (tabletops, gaps, whoops, rhythm
sections, berms, rock gardens, elevation changes) and unlocked with medal
points earned by beating target lap times.

Both are data. `Bikes.json` or `Tracks.json` placed in the app bundle override
the built-in definitions, so balance changes and new content ship without a new
binary. A malformed file falls back to the built-ins rather than failing.

---

## Accessibility

Reduce motion (removes camera shake, softens zoom and disables transitions),
adjustable HUD scale, colourblind palettes, high-contrast HUD, left/right
control mirroring, invertible lean, adjustable haptic strength, VoiceOver
labels throughout, and 44 pt minimum touch targets.

---

## Developer overlay

Enable **Settings ▸ Developer ▸ Physics overlay** to see live telemetry during
a race: suspension travel and load per wheel, tyre slip ratio and grip
utilisation, engine speed, applied throttle, chassis pitch and pitch rate,
current surface, and frame timing. Every value is read straight from the
solver, so the overlay is a true readout rather than a parallel estimate.
