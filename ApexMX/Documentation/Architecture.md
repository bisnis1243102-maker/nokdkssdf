# Architecture

## Layers

Dependencies run strictly downward. Nothing below `UI` imports SwiftUI, and
nothing below `Rendering` imports SpriteKit.

```
        UI  ──────────────┐
         │                │
    Rendering  ───────────┤
         │                │
     Gameplay  ───────────┤
         │                │
      Physics  ───────────┤
         │                │
      GameData  ──────────┤
         │                │
        Core  ────────────┘
```

| Layer | Owns | Knows nothing about |
|---|---|---|
| `Core` | Vector maths, fixed timestep, deterministic RNG, logging | Everything else |
| `GameData` | Bike specs, tracks, surfaces, upgrades | How any of it is simulated |
| `Physics` | Terrain, track building, the bike solver | Races, rendering, players |
| `Gameplay` | Race rules, riders, AI, ghosts, career | How anything is drawn |
| `Rendering` | SpriteKit presentation of a session | Game rules |
| `UI` | Screens, design system, input | The solver's internals |

The practical payoff: `RaceSession` can be stepped in a loop with no view
attached — for headless balance testing, replay validation, or a future
authoritative server — because it has no rendering dependency to satisfy.

## Key types

| Type | Responsibility |
|---|---|
| `BikePhysicsBody` | The rigid-body solver. Deterministic, pure, no framework calls |
| `Terrain` | Sampled ground profile with O(1) height/slope/surface queries |
| `TrackBuilder` | Deterministically turns a `TrackDefinition` into a `Terrain` |
| `RiderInput` | The *only* channel by which anything influences a bike |
| `AIRiderBrain` | Produces `RiderInput` from look-ahead planning |
| `RaceSession` | Owns the field, the clock, lap counting and standings |
| `CareerService` | Turns results into credits, medals, records and unlocks |
| `GameCoordinator` | App state and screen routing — and nothing else |
| `RaceScene` | Mirrors a session onto SpriteKit nodes. Never writes back |

## The frame loop

```
CADisplayLink (SpriteKit)
   └─ RaceScene.update(currentTime)
        ├─ session.update(deltaTime:)
        │    └─ FixedTimestepAccumulator → N × simulateStep(1/240 s)
        │         └─ per rider: brain → RiderInput → BikePhysicsBody.step
        ├─ syncRiders()      nodes read physics state
        ├─ emitEffects()     particles driven by slip, load, impact
        └─ updateCamera()
```

SwiftUI is deliberately *not* in this loop. It writes `session.playerInput` on
a 120 Hz timer and samples a `HUDSnapshot` value type at 20 Hz. Rebuilding a
view tree at simulation rate would cost far more than it buys — no human reads
a number changing 240 times a second.

## Data-driven content

`BikeCatalog.load()` and `TrackCatalog.load()` prefer `Bikes.json` /
`Tracks.json` from the app bundle and fall back to compiled-in defaults. A
missing or malformed file is not fatal: the game logs and uses the built-ins,
so a bad content drop can never brick the app.

This is the seam along which live balance changes, seasonal content and new
courses ship without a binary update.

## Persistence

`PlayerProfile` is one `Codable` value holding progress, records, statistics and
settings. `ProfileStore` writes it atomically — a crash mid-write leaves the
previous save intact rather than a truncated one — and an unreadable save is
quarantined under `.corrupt` for diagnosis rather than silently discarded.

The stored `version` field plus the migration step in `ProfileStore.migrate`
means future format changes upgrade old saves instead of resetting players.
Invariants (owning at least one bike, having at least one track) are repaired on
load, so a hand-edited or partially written file cannot produce an unplayable
state.

## Ghosts and replays

A `GhostRun` stores *inputs*, not positions — timestamped keyframes emitted only
when a control changes by more than 2%. Because the solver is deterministic,
replaying that stream reproduces the run.

Three consequences:

1. A three-minute run is a few kilobytes rather than a few megabytes.
2. A ghost is a full physics body during playback — it collides, compresses its
   suspension and crashes exactly where the original did.
3. A run is **verifiable**: any authority holding the same solver can
   re-simulate the inputs and confirm the claimed time is achievable. This is
   the foundation a server-authoritative leaderboard would be built on.

`GhostRun.physicsVersion` guards the whole scheme. A run recorded against a
different solver is retired rather than replayed incorrectly.

## Performance

- **No allocation during play.** Particles come from a fixed pool of 220
  sprites, recycled on expiry and hidden when idle. Peak count is a hard budget.
- **Terrain geometry is windowed.** Only the visible strip plus a margin is
  built, and only when the camera has moved more than 6 m. A 900 m track costs
  the same as a 90 m one.
- **Backdrop layers tile and wrap.** Three tiles per parallax layer cover an
  unbounded track.
- **The sky is a texture, not a per-frame gradient.** Regenerated only on resize.
- **Quality tiers touch rendering only.** Battery Saver drops particles;
  the simulation is untouched, so a low-power run is not an easier race.

## Extension points

| To add | Change |
|---|---|
| A bike | `BikeCatalog` or bundled `Bikes.json` |
| A track | `TrackCatalog` or bundled `Tracks.json` |
| A surface | A `SurfaceType` case and its properties |
| A weather preset | A `WeatherPreset` case; grip and palette follow |
| A game mode | A new session configuration; `RaceSession` is mode-agnostic |
| Multiplayer | Replace the local input source; the input-stream + deterministic-solver design is already the shape server reconciliation needs |

## Testing

`ApexMXTests` pins the guarantees the rest of the design rests on:
determinism (solver, terrain, RNG), frame-rate independence, stability under
abusive and malformed input, suspension staying within travel, a parked bike not
sinking or creeping, terrain continuity, ghost reproduction, upgrade
monotonicity, economy rules, unlock gating, and profile round-tripping.

These are the tests that fail loudly when something quietly breaks — not
coverage for its own sake.
