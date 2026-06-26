# Grow a Garden 2 — iPhone Farming / Idle Game

A native iOS farming-idle game inspired by the Roblox hit **Grow a Garden**.
Built with **SwiftUI**, no third-party dependencies. Plant seeds, let them grow
in real time (even while the app is closed), harvest for **Sheckles** 🪙, chase
rare **mutations**, ride the **weather**, and expand your plot.

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
| `ContentView.swift` | All SwiftUI views: garden grid, shop, backpack, plant picker |
| `GardenModel.swift` | Game logic, real-time growth, save/load |
| `Models.swift` | Crop catalog, mutations, weather, Codable save types |

Tune crops/economy in `CropCatalog` and mutation odds in `Weather.rollMutation()`.
