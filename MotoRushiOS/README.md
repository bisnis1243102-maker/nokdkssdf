# MotoRush (iOS)

Native SwiftUI + SpriteKit motocross game. Landscape, iOS 16+, no third-party
frameworks and no image assets — every bike, rider, track and effect is drawn
from procedural geometry at runtime.

## Build

Open `MotoRush.xcodeproj` in Xcode and run, or let CI do it: every push to this
branch runs `.github/workflows/build-ipa.yml`, which builds with
`CODE_SIGNING_ALLOWED=NO` and publishes **`MotoRush-unsigned.ipa`** to the
repo's `latest` release. Download it and sign on-device with your sideloading
tool of choice.

## Screens

- **Career** — region qualifiers (Copper Basin → World Arena), each with eight
  track cards. A card unlocks when every earlier card in the region has a
  medal; a region opens when the previous one is half cleared. Cards show the
  recommended power against your bike's current rating, medals earned, and the
  daily goal sits in the corner.
- **Race** — gate drop with rider name labels over the pack, then a physics
  race with speedo, live standings, style score and touch controls
  (throttle, brake, lean back/forward, whip left/right).
- **Podium** — top three on the blocks, run stats, coins and XP, with the
  daily goal ticking over.
- **Garage / Rider / Settings** — bikes, six upgrade lines, name and number,
  haptics and landing assist.

## Code

| File | What it is |
| --- | --- |
| `Track.swift` | Seeded procedural generator: tabletops, doubles, triples, step-ups/downs, whoops, rollers, rhythm sections, berms, across 12 biomes |
| `Physics.swift` | Rigid chassis + two raycast suspension units, friction-circle tyres, rider weight transfer, air control, whip/scrub, landing quality, verlet ragdoll |
| `AI.swift` | Six personalities with ballistic landing prediction, skill-scaled reaction delay and real mistakes — same physics, same inputs as the player |
| `RaceScene.swift` | SpriteKit renderer, gate drop, parallax, particles, dynamic camera |
| `Model.swift` | Bikes, upgrades, regions, medals, daily goal, persistence |
| `CareerView` / `PodiumView` / `GarageView` / `Theme` | SwiftUI menus |

Physics and track generation are ports of the browser build in `../MotoRush`,
so tuning notes there apply here: units are metres/kilograms/seconds, thrust
falls off as `(1 − v/topSpeed)`, and `onLanding()` owns the whole risk/reward
loop.

## Not implemented

Single-player only — no networking, matchmaking or leaderboards. Races are
one-lap sprints. There is no audio in this build (the browser version has the
full procedural sound engine).

All content is original. No third-party assets, track layouts, logos or
branding are used anywhere in this project.
