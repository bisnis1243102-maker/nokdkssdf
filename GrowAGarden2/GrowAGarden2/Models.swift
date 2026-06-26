import SwiftUI

// MARK: - Crops

struct Crop: Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
    let seedCost: Int
    let growSeconds: Double
    let baseValue: Int
}

enum CropCatalog {
    static let all: [Crop] = [
        Crop(id: "carrot",     name: "Carrot",      emoji: "🥕", seedCost: 10,     growSeconds: 20,   baseValue: 18),
        Crop(id: "strawberry", name: "Strawberry",  emoji: "🍓", seedCost: 35,     growSeconds: 45,   baseValue: 60),
        Crop(id: "blueberry",  name: "Blueberry",   emoji: "🫐", seedCost: 90,     growSeconds: 90,   baseValue: 165),
        Crop(id: "tomato",     name: "Tomato",      emoji: "🍅", seedCost: 220,    growSeconds: 150,  baseValue: 420),
        Crop(id: "corn",       name: "Corn",        emoji: "🌽", seedCost: 550,    growSeconds: 240,  baseValue: 1050),
        Crop(id: "pepper",     name: "Pepper",      emoji: "🌶️", seedCost: 1300,   growSeconds: 360,  baseValue: 2700),
        Crop(id: "watermelon", name: "Watermelon",  emoji: "🍉", seedCost: 3200,   growSeconds: 540,  baseValue: 7200),
        Crop(id: "pumpkin",    name: "Pumpkin",     emoji: "🎃", seedCost: 8000,   growSeconds: 780,  baseValue: 19000),
        Crop(id: "mango",      name: "Mango",       emoji: "🥭", seedCost: 21000,  growSeconds: 1200, baseValue: 52000),
        Crop(id: "dragon",     name: "Dragon Fruit",emoji: "🐲", seedCost: 60000,  growSeconds: 1800, baseValue: 160000),
        Crop(id: "goldapple",  name: "Golden Apple",emoji: "🍎", seedCost: 175000, growSeconds: 2700, baseValue: 520000),
        Crop(id: "starfruit",  name: "Starfruit",   emoji: "⭐️", seedCost: 500000, growSeconds: 3600, baseValue: 1600000),
    ]

    static func crop(_ id: String) -> Crop {
        all.first { $0.id == id } ?? all[0]
    }

    /// RGB used to tint the 3D fruit for this crop.
    static func rgb(_ id: String) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        switch id {
        case "carrot":     return (0.95, 0.52, 0.16)
        case "strawberry": return (0.92, 0.20, 0.28)
        case "blueberry":  return (0.27, 0.40, 0.85)
        case "tomato":     return (0.91, 0.28, 0.20)
        case "corn":       return (0.97, 0.83, 0.27)
        case "pepper":     return (0.86, 0.18, 0.16)
        case "watermelon": return (0.30, 0.62, 0.30)
        case "pumpkin":    return (0.95, 0.55, 0.16)
        case "mango":      return (0.98, 0.70, 0.18)
        case "dragon":     return (0.86, 0.24, 0.55)
        case "goldapple":  return (0.96, 0.78, 0.22)
        case "starfruit":  return (0.85, 0.90, 0.30)
        default:           return (0.6, 0.8, 0.4)
        }
    }
}

// MARK: - Mutations

enum Mutation: String, Codable, CaseIterable {
    case normal, wet, frozen, gold, rainbow

    var multiplier: Int {
        switch self {
        case .normal:  return 1
        case .wet:     return 2
        case .frozen:  return 3
        case .gold:    return 5
        case .rainbow: return 25
        }
    }

    var name: String {
        switch self {
        case .normal:  return "Normal"
        case .wet:     return "Wet"
        case .frozen:  return "Frozen"
        case .gold:    return "Gold"
        case .rainbow: return "Rainbow"
        }
    }

    var badge: String {
        switch self {
        case .normal:  return ""
        case .wet:     return "💧"
        case .frozen:  return "❄️"
        case .gold:    return "✨"
        case .rainbow: return "🌈"
        }
    }

    var tint: Color {
        switch self {
        case .normal:  return .white
        case .wet:     return .blue
        case .frozen:  return .cyan
        case .gold:    return .yellow
        case .rainbow: return .pink
        }
    }
}

// MARK: - Weather

enum Weather: String, CaseIterable {
    case sunny, rainy, snowy, windy

    /// Deterministic, storage-free cycle: changes every 4 minutes.
    static var current: Weather {
        let slot = Int(Date().timeIntervalSince1970 / 240) % allCases.count
        return allCases[(slot + allCases.count) % allCases.count]
    }

    static var secondsUntilChange: Int {
        let period = 240.0
        let into = Date().timeIntervalSince1970.truncatingRemainder(dividingBy: period)
        return Int(period - into)
    }

    var emoji: String {
        switch self {
        case .sunny: return "☀️"
        case .rainy: return "🌧️"
        case .snowy: return "❄️"
        case .windy: return "🌬️"
        }
    }

    var name: String { rawValue.capitalized }

    var blurb: String {
        switch self {
        case .sunny: return "Clear skies."
        case .rainy: return "Rain boosts Wet mutations."
        case .snowy: return "Snow boosts Frozen mutations."
        case .windy: return "Breezy. Slightly luckier crops."
        }
    }

    /// Rolls a mutation for a harvested crop, biased by weather and fertilizer.
    func rollMutation(fertilized: Bool) -> Mutation {
        let r = Double.random(in: 0..<1)
        let windLuck = self == .windy ? 1.6 : 1.0
        let fertLuck = fertilized ? 6.0 : 1.0
        let luck = windLuck * fertLuck
        if r < 0.01 * luck { return .rainbow }
        if r < 0.05 * luck { return .gold }
        switch self {
        case .rainy: if r < (fertilized ? 0.60 : 0.40) { return .wet }
        case .snowy: if r < (fertilized ? 0.55 : 0.35) { return .frozen }
        default: break
        }
        return .normal
    }
}

// MARK: - Upgrades

enum UpgradeKind {
    case sprinkler
    case fertilizer
    case autoHarvester
}

// MARK: - Player level

enum Level {
    /// Sheckles needed to reach each successive level (cumulative thresholds grow ~2.2x).
    static func level(forEarned earned: Int) -> Int {
        var lvl = 1
        var need = 100.0
        var total = 0.0
        while Double(earned) >= total + need {
            total += need
            need *= 2.2
            lvl += 1
        }
        return lvl
    }

    static func progress(forEarned earned: Int) -> (current: Int, into: Int, needed: Int) {
        var lvl = 1
        var need = 100.0
        var total = 0.0
        while Double(earned) >= total + need {
            total += need
            need *= 2.2
            lvl += 1
        }
        return (lvl, earned - Int(total), Int(need))
    }
}

// MARK: - Persistence (v2)

struct PlotSave: Codable {
    var cropID: String?
    var plantedAt: Date?
    var fertilized: Bool = false
}

struct HarvestStack: Codable, Identifiable {
    var id = UUID()
    var cropID: String
    var mutation: Mutation
    var count: Int
    var unitValue: Int

    var totalValue: Int { count * unitValue }
    var crop: Crop { CropCatalog.crop(cropID) }
}

struct GardenSave: Codable {
    var money: Int
    var seeds: [String: Int]
    var unlockedPlots: Int
    var plots: [PlotSave]
    var backpack: [HarvestStack]
    var lifetimeEarned: Int
    var sprinklerLevel: Int = 0
    var fertilizer: Int = 0
    var autoHarvesterUnlocked: Bool = false
    var autoHarvestEnabled: Bool = false
}
