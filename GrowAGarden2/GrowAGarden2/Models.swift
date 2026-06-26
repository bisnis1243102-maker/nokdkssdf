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
    ]

    static func crop(_ id: String) -> Crop {
        all.first { $0.id == id } ?? all[0]
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

    /// Rolls a mutation for a freshly harvested crop, biased by weather.
    func rollMutation() -> Mutation {
        let r = Double.random(in: 0..<1)
        let luck = self == .windy ? 1.6 : 1.0
        if r < 0.01 * luck { return .rainbow }
        if r < 0.05 * luck { return .gold }
        switch self {
        case .rainy: if r < 0.40 { return .wet }
        case .snowy: if r < 0.35 { return .frozen }
        default: break
        }
        return .normal
    }
}

// MARK: - Persistence

struct PlotSave: Codable {
    var cropID: String?
    var plantedAt: Date?
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
}
