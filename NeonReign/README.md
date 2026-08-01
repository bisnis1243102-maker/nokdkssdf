# Neon Reign — open-world mission game for iPhone

An **original** 3D open-world crime-story game for iOS, built with
**SwiftUI + SceneKit + Metal**, no third-party dependencies. Drive a rain-slick
neon city, run a nine-job campaign, get out on foot when the job needs it, and
lose the police when it goes wrong.

> This is not GTA. It shares no assets, map, characters, or branding with any
> Rockstar game, and it is not photorealistic — it is a stylised, hand-built
> phone game. What it *does* spend its effort on is the renderer.

## The renderer

Everything below is custom code in `NeonReign/Render/`, not SceneKit defaults:

- **Custom Metal post chain** (`Shaders.metal`, wired by `RenderPipeline.swift`
  as an `SCNTechnique`): bright pass → **two-tier bloom** (a tight half-res
  halo plus a wide quarter-res haze) → **screen-space reflections** raymarched
  against the depth buffer with 20 jittered steps, distance-based ray spread
  and a fresnel term → **light shafts** → composite with **ACES filmic
  tonemapping**, **split toning** (cold shadows, warm highlights), chromatic
  aberration, animated film grain, **rain droplets that refract the frame**,
  and vignette → **FXAA**.
- **16× anisotropic filtering** on every surface — the single biggest win on
  road texture, which otherwise turns to mush a few metres ahead of the car.
- **Procedural PBR textures** (`TextureFactory.swift`): albedo, tangent-space
  normal, roughness and AO maps generated at runtime for asphalt, sidewalk,
  facades, and painted metal. The app ships no binary art.
- **Shader modifiers** (`ShaderModifiers.swift`): a wet-road surface modifier
  that blends puddles into roughness and reflectivity and adds **animated rain
  ripples** during a downpour, animated neon flicker, fresnel car paint with
  metallic flake, glass, and wind-swayed foliage.
- **Cascaded sun shadows** that follow the player, so contact shadows under the
  wheels stay sharp while the block behind still casts.
- **Cars** carry contact-shadow blobs, tail lights that flare under braking,
  and volumetric headlight cones after dark. **Roofs** carry parapets, plant
  housings and pulsing aircraft warning lights.
- **Analytic sky + HDR environment** (`Sky.swift`) regenerated as the clock
  moves — stars, a sun/moon disc with a glow halo, and a cloud band lit warm
  near the sun — fed to `lightingEnvironment` so metal and wet tarmac reflect
  the actual time of day.
- **Day/night cycle** — a full 24 hours every 20 minutes of play. At dusk
  window emission, street lights, neon and headlights all come up.
- **Weather** (`Weather.swift`) that drives `wetness` into the road shader and
  the reflection pass, not just rain sprites.
- **Light streaming** — only the nearest N street/neon lights stay live, so the
  shadow pass stays affordable.

### Quality tiers

| Tier | What runs |
|---|---|
| **Balanced** | Bloom + grade. No SSR, no shafts, no FXAA. Default in the Simulator, which software-renders Metal. |
| **High** | Adds screen-space reflections, light shafts, motion blur, 2× MSAA. |
| **Ultra** | Adds FXAA, 4× MSAA, 4K shadow maps, 3 shadow cascades, 1024px textures, 18 live lights. |

Switch tiers any time from the ☰ menu. If SceneKit rejects the technique on a
given device, the game falls back to the camera's built-in HDR pipeline rather
than failing to render.

> One deviation from the original plan, called out honestly: the anti-aliasing
> pass is **FXAA**, not TAA. `SCNTechnique` gives no reliable way to persist a
> history buffer between frames, which temporal AA requires.

## The game

- **Nine-mission campaign** — from a first delivery to a citywide chase.
  Objective kinds: drive to, timed delivery, go in on foot, hold position, tail
  a courier, ram a target, lose the police.
- **On foot and behind the wheel.** Get out with the **Get out** button; some
  objectives can only be finished on foot. Walk back to your car to get in.
- **Police heat**, 0–3 stars. Stars come off when you break line of sight long
  enough. Get boxed in while stopped and you're busted — mission failed.
- **Free roam** between jobs, with the next job's start marker glowing in the
  world. Drive into it to begin, or pick a job from the menu.
- **Nine districts** — Harbor Point, Marrow Heights, Saltworks, Lantern Row,
  The Spire, Glasshouse, Vermillion, Cannery Flats, Ridgewater — each with its
  own palette, skyline height and neon colour.
- Traffic, pedestrians who step out of the way, cash and persisted progress.

## Controls

- **Left stick** — steer when driving, walk in any direction on foot.
- **Right side** — ▲ gas, ▼ brake/reverse, ✋ handbrake.
- **Get out / Get in** — swap between driving and on foot.
- **☰** — job list, graphics quality, abandon job, reset progress.

## Installing on your iPhone with KSign

Every push builds an **unsigned `.ipa`** and attaches it to the repo's `latest`
release. To install:

1. On your iPhone, open the release page:
   <https://github.com/bisnis1243102-maker/nokdkssdf/releases/tag/latest>
2. Tap **`NeonReign-unsigned.ipa`** to download it directly (it is a plain
   file, not a zip).
3. Open **KSign**, import the downloaded `.ipa`, and sign it with your
   certificate / Apple ID.
4. Install, then trust the profile under
   *Settings → General → VPN & Device Management*.

Direct link to the file:
<https://github.com/bisnis1243102-maker/nokdkssdf/releases/download/latest/NeonReign-unsigned.ipa>

The app's bundle identifier is `com.example.NeonReign` and it installs as
**Neon Reign**, so it will not collide with the other apps in this repo.

## Running it from source

1. Open `NeonReign.xcodeproj` in **Xcode 15+**.
2. Pick an iPhone simulator or your device and press **⌘R**.
   - On a physical device set your Apple ID **Team** under Signing &
     Capabilities.
   - Minimum deployment target: **iOS 16.0**.

CI also builds an unsigned `.ipa` on every push (see
`.github/workflows/build-ipa.yml`), attached to the `latest` release for
sideloading.

## Project layout

| File | Responsibility |
|---|---|
| `NeonReignApp.swift` | App entry |
| `ContentView.swift` | HUD, stick + pedals, minimap, job menu, result cards |
| `GameModel.swift` | Input/HUD bridge, progress, quality tiers |
| `CityWorld.swift` | Map extents, road grid, districts, landmarks |
| `Missions.swift` | Objective kinds + the campaign, as data |
| `MissionRunner.swift` | Objective state machine and world markers |
| `GameScene.swift` | Scene setup, per-frame tick, camera, light streaming |
| `SceneBuild.swift` | Ground, roads, blocks, parks, neon, landmarks |
| `Vehicles.swift` | Car geometry, driving physics, traffic, police, target |
| `Actors.swift` | On-foot player, enter/exit, pedestrians |
| `Render/` | The renderer described above |

Tune the city in `CityWorld.swift`, the driving feel in `Vehicles.swift`
(`updateDriving`), and the look in `Render/RenderPipeline.swift`.
