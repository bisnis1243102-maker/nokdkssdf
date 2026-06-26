# Bloom Tycoon — 3D iPhone Farming / Idle Game

A native iOS farming-idle game inspired by the Roblox hit **Grow a Garden**,
rendered in **3D with SceneKit**. (Home-screen name: **Bloom Tycoon**.) Built with **SwiftUI + SceneKit**, no
third-party dependencies. Orbit your garden, plant seeds, watch crops grow in
real time (even while the app is closed), harvest for **Sheckles** 🪙, chase rare
**mutations**, ride the **weather**, and grow an automated farming empire.

## What's 3D / new

- **Real 3D garden** — soil plots, growing crops, leaves, and a sky you can
  **orbit, pan and pinch-zoom** (turntable camera).
- **Animated growth** — crops scale up smoothly as they mature and **bob + glow**
  when ready to harvest; harvests pop a colored burst tinted by the mutation.
- **Day/night lighting** that follows the real clock, plus **rain and snow
  particle weather**.
- **Sprinkler** upgrade (10 levels) — each level grows crops ~8% faster.
- **Fertilizer** — apply at planting for dramatically better mutation odds.
- **Auto-Harvester** — unlock to auto-collect ready crops.
- **Player levels** with an XP bar, a new **Starfruit** crop, and an expanded
  Shop split into **Seeds / Upgrades**.

## How to play

1. **Shop** 🛒 — buy seeds (11 crops, from Carrots to the Golden Apple).
2. Tap an empty **plot** → pick a seed to plant it.
3. Crops grow on a real-time timer — a progress bar and countdown show on each plot.
   Growth continues offline, so come back later to a ready harvest.
4. Tap a glowing plot (or **Harvest All** 🌿) to collect crops into your **Backpack** 🎒.
5. Open the Backpack and **Sell** for Sheckles, then reinvest in pricier, more
   valuable seeds — and buy more plots (up to 24).

### Mutations (rolled at harvest)
| Mutation | Value | Boosted by |
|----------|-------|------------|
| 💧 Wet | ×2 | Rainy weather |
| ❄️ Frozen | ×3 | Snowy weather |
| ✨ Gold | ×5 | always ~5% |
| 🌈 Rainbow | ×25 | always ~1% |

### Weather
Cycles every few minutes (☀️ Sunny, 🌧️ Rainy, ❄️ Snowy, 🌬️ Windy). Rain makes
Wet crops more likely, snow makes Frozen more likely, and wind nudges your luck up.

Progress auto-saves to `UserDefaults` and persists between launches.

## Running it

1. Open `GrowAGarden2.xcodeproj` in **Xcode 15+**.
2. Pick an iPhone simulator (or your device) and press **⌘R**.
   - Physical device: set your Apple ID **Team** under Signing & Capabilities.
- Minimum deployment target: **iOS 16.0**

## Project layout

| File | Responsibility |
|------|----------------|
| `GrowAGarden2App.swift` | App entry point |
| `ContentView.swift` | SwiftUI HUD overlays: header/level, weather, shop, backpack, plant picker |
| `GardenSceneView.swift` | **3D SceneKit garden** — plots, crops, lighting, weather, tap handling |
| `GardenModel.swift` | Game logic, real-time growth, upgrades, save/load |
| `Models.swift` | Crop catalog, mutations, weather, levels, Codable save types |

Tune crops/economy in `CropCatalog`, mutation odds in `Weather.rollMutation(fertilized:)`,
and upgrade pricing in `GardenModel`.
