import Foundation
import SwiftUI

// MARK: - Bikes

struct BikeSpec: Identifiable, Hashable {
    let id: String
    let name: String
    let cls: String
    let price: Int
    let unlockLevel: Int
    let mass: Double
    let power: Double
    let topSpeed: Double
    let torqueCurve: Double
    let susStiff: Double
    let susDamp: Double
    let travel: Double
    let grip: Double
    let brake: Double
    let wheelbase: Double
    let seatHeight: Double
    let color: String
    let electric: Bool
    let blurb: String

    /// The single number the career screen compares against a track's
    /// recommended power. Purely a rating — the physics uses the raw stats.
    var rating: Int {
        Int((power / 26 + topSpeed * 5.5 + grip * 60 + travel * 260 - mass * 0.7).rounded())
    }

    static let all: [BikeSpec] = [
        BikeSpec(id: "sprout50", name: "Sprout 50", cls: "50cc", price: 0, unlockLevel: 1,
                 mass: 92, power: 3400, topSpeed: 22, torqueCurve: 0.9, susStiff: 26000,
                 susDamp: 1500, travel: 0.22, grip: 1.15, brake: 900, wheelbase: 1.05,
                 seatHeight: 0.36, color: "#7FE08A", electric: false,
                 blurb: "Forgiving mini-bike. Great for learning rhythm sections."),
        BikeSpec(id: "cadet65", name: "Cadet 65", cls: "65cc", price: 2500, unlockLevel: 2,
                 mass: 98, power: 4600, topSpeed: 27, torqueCurve: 0.95, susStiff: 28000,
                 susDamp: 1650, travel: 0.24, grip: 1.12, brake: 1050, wheelbase: 1.12,
                 seatHeight: 0.38, color: "#63C7FF", electric: false,
                 blurb: "Snappier than the 50 with more punch out of berms."),
        BikeSpec(id: "ridge85", name: "Ridge 85", cls: "85cc", price: 7000, unlockLevel: 5,
                 mass: 106, power: 6200, topSpeed: 32, torqueCurve: 1.0, susStiff: 31000,
                 susDamp: 1800, travel: 0.27, grip: 1.08, brake: 1200, wheelbase: 1.2,
                 seatHeight: 0.42, color: "#FFD166", electric: false,
                 blurb: "The first bike that will bite you. Rewards clean throttle."),
        BikeSpec(id: "lance125", name: "Lance 125", cls: "125cc", price: 16000, unlockLevel: 9,
                 mass: 118, power: 8400, topSpeed: 38, torqueCurve: 1.15, susStiff: 34000,
                 susDamp: 1950, travel: 0.3, grip: 1.04, brake: 1350, wheelbase: 1.3,
                 seatHeight: 0.46, color: "#FF8F5C", electric: false,
                 blurb: "Two-stroke sting. Lives in the top half of the rev range."),
        BikeSpec(id: "vector250", name: "Vector 250F", cls: "250cc", price: 34000, unlockLevel: 14,
                 mass: 126, power: 10200, topSpeed: 43, torqueCurve: 1.05, susStiff: 36000,
                 susDamp: 2100, travel: 0.31, grip: 1.02, brake: 1500, wheelbase: 1.34,
                 seatHeight: 0.47, color: "#C17DFF", electric: false,
                 blurb: "Balanced four-stroke. The championship all-rounder."),
        BikeSpec(id: "apex450", name: "Apex 450", cls: "450cc", price: 62000, unlockLevel: 20,
                 mass: 138, power: 14500, topSpeed: 50, torqueCurve: 1.3, susStiff: 39000,
                 susDamp: 2300, travel: 0.32, grip: 0.96, brake: 1700, wheelbase: 1.38,
                 seatHeight: 0.48, color: "#FF5D73", electric: false,
                 blurb: "Brutal torque. Wheelies on command, punishes greedy hands."),
        BikeSpec(id: "volt", name: "Volt E1", cls: "Electric", price: 78000, unlockLevel: 24,
                 mass: 132, power: 13000, topSpeed: 46, torqueCurve: 1.6, susStiff: 37000,
                 susDamp: 2200, travel: 0.3, grip: 1.06, brake: 1600, wheelbase: 1.32,
                 seatHeight: 0.45, color: "#5EF2D6", electric: true,
                 blurb: "Instant torque, no shift dips, eerie silence off the gate."),
        BikeSpec(id: "relic71", name: "Relic 71", cls: "Vintage", price: 45000, unlockLevel: 18,
                 mass: 148, power: 7600, topSpeed: 36, torqueCurve: 0.85, susStiff: 19000,
                 susDamp: 1200, travel: 0.18, grip: 0.92, brake: 950, wheelbase: 1.42,
                 seatHeight: 0.5, color: "#D9C39A", electric: false,
                 blurb: "Twin shocks, drum brakes, zero forgiveness."),
        BikeSpec(id: "nova", name: "Nova X", cls: "Prototype", price: 120000, unlockLevel: 30,
                 mass: 110, power: 17000, topSpeed: 58, torqueCurve: 1.4, susStiff: 42000,
                 susDamp: 2600, travel: 0.36, grip: 1.2, brake: 2000, wheelbase: 1.3,
                 seatHeight: 0.44, color: "#8AB4FF", electric: false,
                 blurb: "Mag-lev damping and a powerband that never ends.")
    ]

    static func byId(_ id: String) -> BikeSpec { all.first(where: { $0.id == id }) ?? all[0] }
}

struct UpgradeLine: Identifiable {
    let id: String
    let name: String
    let maxLevel: Int
    let baseCost: Int
    let effect: String

    static let all: [UpgradeLine] = [
        UpgradeLine(id: "engine", name: "Engine", maxLevel: 5, baseCost: 1800, effect: "Power +7% / level"),
        UpgradeLine(id: "suspension", name: "Suspension", maxLevel: 5, baseCost: 1600, effect: "Damping +6% / level"),
        UpgradeLine(id: "tires", name: "Tires", maxLevel: 5, baseCost: 1200, effect: "Grip +5% / level"),
        UpgradeLine(id: "brakes", name: "Brakes", maxLevel: 5, baseCost: 1000, effect: "Braking +8% / level"),
        UpgradeLine(id: "transmission", name: "Transmission", maxLevel: 5, baseCost: 1500, effect: "Top speed +4% / level"),
        UpgradeLine(id: "weight", name: "Weight", maxLevel: 5, baseCost: 2200, effect: "Mass -3% / level")
    ]
}

// MARK: - Career structure

struct CareerTrack: Identifiable {
    let id: String
    let name: String
    let seed: UInt32
    let biome: String
    let difficulty: Double
    let recommendedPower: Int
    let index: Int
}

struct Region: Identifiable {
    let id: String
    let name: String
    let tint: String
    let tint2: String
    let tracks: [CareerTrack]

    /// Regions are generated once from a fixed seed so every install sees the
    /// same career, while the tracks themselves stay procedural.
    static let all: [Region] = buildRegions()

    private static func buildRegions() -> [Region] {
        let defs: [(id: String, name: String, tint: String, tint2: String, series: String, biomes: [String])] = [
            ("copper", "Copper Basin", "#E8A13A", "#8A4B1E", "Rookie Circuit",
             ["motocross", "forest", "motocross", "sand", "motocross", "supercross", "mountain", "motocross"]),
            ("north", "Northlands", "#8FD9FF", "#2C5C8A", "Cold Series",
             ["snow", "forest", "snow", "mountain", "snow", "supercross", "night", "snow"]),
            ("dunes", "The Dunes", "#F5C86A", "#A5702A", "Sand Nationals",
             ["sand", "desert", "sand", "beach", "desert", "sand", "supercross", "desert"]),
            ("ridge", "Iron Ridge", "#B9C2CF", "#4A5364", "Mountain Series",
             ["mountain", "mud", "mountain", "forest", "mountain", "night", "mud", "mountain"]),
            ("ember", "Ember Fields", "#FF6A3D", "#7B2531", "Volcano Series",
             ["volcano", "desert", "volcano", "night", "volcano", "supercross", "desert", "volcano"]),
            ("arena", "World Arena", "#7AD1FF", "#2B3A6B", "World Tour",
             ["arena", "supercross", "arena", "supercross", "arena", "night", "arena", "supercross"])
        ]
        let trackNames = [
            "Rookie Road", "To The Woods", "Path Of The Ancient", "Rocking It",
            "Climb And Fall", "Flying Low", "Going Down", "Bumping Along"
        ]
        var out: [Region] = []
        var seedBase: UInt32 = 0xA17C3
        for (ri, def) in defs.enumerated() {
            var tracks: [CareerTrack] = []
            for (ti, biome) in def.biomes.enumerated() {
                let difficulty = clampd(0.18 + Double(ri) * 0.13 + Double(ti) * 0.045, 0.15, 0.98)
                let power = 480 + ri * 260 + ti * 55
                seedBase = seedBase &* 1664525 &+ 1013904223
                tracks.append(CareerTrack(
                    id: "\(def.id)-\(ti)",
                    name: trackNames[ti % trackNames.count],
                    seed: seedBase,
                    biome: biome,
                    difficulty: difficulty,
                    recommendedPower: power,
                    index: ti))
            }
            out.append(Region(id: def.id, name: def.name, tint: def.tint, tint2: def.tint2, tracks: tracks))
        }
        return out
    }
}

struct AIPersonality {
    let name: String
    let skill: Double
    let aggression: Double
    let risk: Double
    let mistake: Double

    static let all: [AIPersonality] = [
        AIPersonality(name: "Rookie", skill: 0.55, aggression: 0.3, risk: 0.25, mistake: 0.05),
        AIPersonality(name: "Steady", skill: 0.72, aggression: 0.35, risk: 0.3, mistake: 0.02),
        AIPersonality(name: "Technical", skill: 0.85, aggression: 0.5, risk: 0.45, mistake: 0.012),
        AIPersonality(name: "Aggressive", skill: 0.86, aggression: 0.9, risk: 0.75, mistake: 0.028),
        AIPersonality(name: "Sendy", skill: 0.8, aggression: 0.8, risk: 0.95, mistake: 0.045),
        AIPersonality(name: "Pro", skill: 0.96, aggression: 0.7, risk: 0.6, mistake: 0.008)
    ]
}

let riderNames = ["Mike Pallas", "Logan Depaty", "Colin Eberly", "Juan Pablo Schulze",
                  "Rhen Vance", "Aya Kestrel", "Brix Onyx", "Dane Falk", "Nyx Rooker",
                  "Sable Pike", "Trace Dune", "Karo Voss"]

// MARK: - Saved profile

struct Profile: Codable {
    var name = "You"
    var number = 482
    var level = 1
    var xp = 0
    var coins = 400
    var gems = 25
    var tokens = 0
    var bikes: [String] = ["sprout50"]
    var currentBike = "sprout50"
    var upgrades: [String: [String: Int]] = ["sprout50": [:]]
    var medals: [String: Int] = [:]        // trackId -> 0 none, 1 bronze, 2 silver, 3 gold
    var bestTimes: [String: Double] = [:]
    var dailyGoalDate = ""
    var dailyGoalKind = "winCareer"
    var dailyGoalProgress = 0
    var dailyGoalClaimed = false
    var races = 0
    var wins = 0
    var perfects = 0
    var crashes = 0
    var airtime: Double = 0
    var soundOn = true
    var hapticsOn = true
    var assistLanding = false
    var ghostsOn = true
    var lastRegion = "copper"
    var trophies = 0
    /// Best-run replays, keyed by track id. Flattened [x, y, angle, whip] at
    /// 10 Hz — about 4 KB for a two-minute lap.
    var ghosts: [String: [Double]] = [:]
    var jamWeek = ""
    var jamBest: Double = 0
    var jamRuns = 0

    var xpForNext: Int { Int(75 * pow(Double(level), 1.25)) }
}

/// Trophy ladder. Winning a career track or beating your ghost pays trophies;
/// a bad result costs a few, so a division has to be held rather than banked.
enum Division {
    static let names = ["Dirt", "Clay", "Loam", "Sand", "Shale", "Granite", "Chrome", "Factory"]
    static let steps = [0, 250, 600, 1100, 1800, 2700, 3900, 5400]

    static func index(for trophies: Int) -> Int {
        var idx = 0
        for (i, s) in steps.enumerated() where trophies >= s { idx = i }
        return idx
    }
    static func name(for trophies: Int) -> String { names[index(for: trophies)] }
    static func floor(for trophies: Int) -> Int { steps[index(for: trophies)] }
    static func ceiling(for trophies: Int) -> Int {
        let i = index(for: trophies)
        return i + 1 < steps.count ? steps[i + 1] : steps[i] + 1200
    }
    static func progress(for trophies: Int) -> Double {
        let lo = floor(for: trophies), hi = ceiling(for: trophies)
        return clampd(Double(trophies - lo) / Double(max(1, hi - lo)), 0, 1)
    }
}

/// The weekly Jam: one shared track for everyone, rotating every Monday, run
/// solo against your own best time.
enum Jam {
    static func weekKey(_ date: Date = Date()) -> String {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return "\(c.yearForWeekOfYear ?? 0)-W\(c.weekOfYear ?? 0)"
    }

    static func seed(_ key: String = weekKey()) -> UInt32 {
        var h: UInt32 = 2166136261
        for b in key.utf8 {
            h = (h ^ UInt32(b)) &* 16777619
        }
        return h
    }

    static func track(_ key: String = weekKey()) -> CareerTrack {
        var rnd = RNG(seed: seed(key))
        let biomes = Biome.all.map { $0.key }
        let biome = biomes[rnd.int(biomes.count)]
        return CareerTrack(id: "jam-\(key)", name: "Weekly Jam", seed: seed(key) ^ 0x5EED,
                           biome: biome, difficulty: 0.55 + rnd.next() * 0.35,
                           recommendedPower: 700, index: 0)
    }
}

enum DailyGoal {
    static func text(_ kind: String) -> String {
        switch kind {
        case "winCareer": return "Win a Career race"
        case "perfect6": return "Land 6 perfect landings"
        case "race3": return "Finish 3 races"
        case "air15": return "Log 15s of air time"
        default: return "Race"
        }
    }
    static func goal(_ kind: String) -> Int {
        switch kind {
        case "winCareer": return 1
        case "perfect6": return 6
        case "race3": return 3
        case "air15": return 15
        default: return 1
        }
    }
    static let kinds = ["winCareer", "perfect6", "race3", "air15"]
}

// MARK: - Game state

final class GameState: ObservableObject {
    @Published var profile: Profile
    @Published var screen: Screen = .career
    @Published var pendingResult: RaceResult?
    /// Surfaced on the podium; set by `apply(result:)`.
    var lastTrophyDelta = 0

    enum Screen: Equatable {
        case career
        case garage
        case rider
        case settings
        case race(CareerTrackRef)
        case podium
    }

    struct CareerTrackRef: Equatable {
        let regionId: String
        let trackId: String
    }

    private let key = "motorush.profile.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(Profile.self, from: data) {
            profile = decoded
        } else {
            profile = Profile()
        }
        rollDailyGoal()
        rollJam()
    }

    /// A new week means a new Jam track and a fresh personal best.
    func rollJam() {
        let key = Jam.weekKey()
        if profile.jamWeek != key {
            profile.jamWeek = key
            profile.jamBest = 0
            profile.jamRuns = 0
            profile.ghosts.removeValue(forKey: Jam.track(key).id)
            save()
        }
    }

    var jamTrack: CareerTrack { Jam.track(profile.jamWeek.isEmpty ? Jam.weekKey() : profile.jamWeek) }

    /// Career tracks live in a region; the Jam track does not.
    func trackFor(_ ref: CareerTrackRef) -> CareerTrack {
        ref.regionId == "jam" ? jamTrack : track(ref)
    }

    func ghost(for trackId: String) -> [GhostFrame]? {
        guard profile.ghostsOn, let flat = profile.ghosts[trackId], flat.count >= 4 else { return nil }
        var out: [GhostFrame] = []
        out.reserveCapacity(flat.count / 4)
        var i = 0
        while i + 3 < flat.count {
            out.append(GhostFrame(x: flat[i], y: flat[i + 1], ang: flat[i + 2], whip: flat[i + 3]))
            i += 4
        }
        return out
    }

    func storeGhost(_ frames: [GhostFrame], for trackId: String) {
        var flat: [Double] = []
        flat.reserveCapacity(frames.count * 4)
        for f in frames {
            flat.append((f.x * 100).rounded() / 100)
            flat.append((f.y * 100).rounded() / 100)
            flat.append((f.ang * 1000).rounded() / 1000)
            flat.append((f.whip * 1000).rounded() / 1000)
        }
        profile.ghosts[trackId] = flat
        save()
    }

    func save() {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: Career access

    func region(_ id: String) -> Region {
        Region.all.first(where: { $0.id == id }) ?? Region.all[0]
    }

    func track(_ ref: CareerTrackRef) -> CareerTrack {
        let r = region(ref.regionId)
        return r.tracks.first(where: { $0.id == ref.trackId }) ?? r.tracks[0]
    }

    /// A track is playable once every earlier track in the region has a medal,
    /// and a region opens when the previous one is at least half cleared.
    func isUnlocked(_ track: CareerTrack, in region: Region) -> Bool {
        guard isRegionUnlocked(region) else { return false }
        if track.index == 0 { return true }
        for t in region.tracks where t.index < track.index {
            if (profile.medals[t.id] ?? 0) == 0 { return false }
        }
        return true
    }

    func isRegionUnlocked(_ region: Region) -> Bool {
        guard let idx = Region.all.firstIndex(where: { $0.id == region.id }) else { return false }
        if idx == 0 { return true }
        let prev = Region.all[idx - 1]
        let cleared = prev.tracks.filter { (profile.medals[$0.id] ?? 0) > 0 }.count
        return cleared >= (prev.tracks.count + 1) / 2
    }

    func regionProgress(_ region: Region) -> Double {
        let earned = region.tracks.reduce(0) { $0 + (profile.medals[$1.id] ?? 0) }
        return Double(earned) / Double(max(1, region.tracks.count * 3))
    }

    // MARK: Bike / power

    var currentSpec: BikeSpec { BikeSpec.byId(profile.currentBike) }
    var currentUpgrades: [String: Int] { profile.upgrades[profile.currentBike] ?? [:] }

    var currentPower: Int {
        let spec = currentSpec
        let u = currentUpgrades
        var bonus = 0
        for line in UpgradeLine.all { bonus += (u[line.id] ?? 0) * 18 }
        return spec.rating + bonus
    }

    func upgradeCost(_ line: UpgradeLine) -> Int {
        let lvl = currentUpgrades[line.id] ?? 0
        return Int(Double(line.baseCost) * pow(1.55, Double(lvl)))
    }

    func buyUpgrade(_ line: UpgradeLine) -> Bool {
        var u = profile.upgrades[profile.currentBike] ?? [:]
        let lvl = u[line.id] ?? 0
        guard lvl < line.maxLevel else { return false }
        let cost = upgradeCost(line)
        guard profile.coins >= cost else { return false }
        profile.coins -= cost
        u[line.id] = lvl + 1
        profile.upgrades[profile.currentBike] = u
        save()
        return true
    }

    func buyBike(_ spec: BikeSpec) -> Bool {
        guard !profile.bikes.contains(spec.id) else { return false }
        guard profile.level >= spec.unlockLevel, profile.coins >= spec.price else { return false }
        profile.coins -= spec.price
        profile.bikes.append(spec.id)
        profile.upgrades[spec.id] = [:]
        save()
        return true
    }

    func selectBike(_ spec: BikeSpec) {
        guard profile.bikes.contains(spec.id) else { return }
        profile.currentBike = spec.id
        save()
    }

    // MARK: Daily goal

    func rollDailyGoal() {
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        if profile.dailyGoalDate != String(today) {
            profile.dailyGoalDate = String(today)
            profile.dailyGoalKind = DailyGoal.kinds.randomElement() ?? "winCareer"
            profile.dailyGoalProgress = 0
            profile.dailyGoalClaimed = false
            save()
        }
    }

    var dailyGoalTarget: Int { DailyGoal.goal(profile.dailyGoalKind) }
    var dailyGoalDone: Bool { profile.dailyGoalProgress >= dailyGoalTarget }

    // MARK: Results

    func apply(result: RaceResult) {
        let p = result
        profile.races += 1
        profile.perfects += p.perfects
        profile.crashes += p.crashes
        profile.airtime += p.airTime
        if p.position == 1 { profile.wins += 1 }

        let isJam = p.regionId == "jam"
        let medal = p.position == 1 ? 3 : (p.position == 2 ? 2 : (p.position == 3 ? 1 : 0))
        if !isJam, medal > (profile.medals[p.trackId] ?? 0) { profile.medals[p.trackId] = medal }

        // Trophies: a podium pays, the back of the pack costs, and beating
        // your own ghost is worth as much as a win.
        var trophyDelta = [30, 18, 10, -4, -8, -12][max(0, min(5, p.position - 1))]
        if p.beatGhost { trophyDelta += 12 }
        if isJam { trophyDelta = p.beatGhost ? 25 : 6 }
        profile.trophies = max(0, profile.trophies + trophyDelta)

        if isJam {
            profile.jamRuns += 1
            if profile.jamBest == 0 || p.time < profile.jamBest { profile.jamBest = p.time }
        }
        if let best = profile.bestTimes[p.trackId] {
            if p.time < best { profile.bestTimes[p.trackId] = p.time }
        } else {
            profile.bestTimes[p.trackId] = p.time
        }

        profile.coins += p.coins
        profile.xp += p.xp
        lastTrophyDelta = trophyDelta
        while profile.xp >= profile.xpForNext {
            profile.xp -= profile.xpForNext
            profile.level += 1
            profile.coins += 250 + profile.level * 60
            profile.gems += 2
        }

        // Daily goal.
        if !profile.dailyGoalClaimed {
            switch profile.dailyGoalKind {
            case "winCareer": if p.position == 1 { profile.dailyGoalProgress += 1 }
            case "perfect6": profile.dailyGoalProgress += p.perfects
            case "race3": profile.dailyGoalProgress += 1
            case "air15": profile.dailyGoalProgress += Int(p.airTime.rounded())
            default: break
            }
            if profile.dailyGoalProgress >= dailyGoalTarget {
                profile.dailyGoalProgress = dailyGoalTarget
                profile.dailyGoalClaimed = true
                profile.coins += 500
                profile.gems += 5
            }
        }
        save()
    }
}

struct RaceResult: Equatable {
    var trackId: String
    var regionId: String
    var trackName: String
    var position: Int
    var fieldSize: Int
    var time: Double
    var perfects: Int
    var crashes: Int
    var airTime: Double
    var style: Int
    var coins: Int
    var xp: Int
    var beatGhost: Bool
    var order: [(String, Double)]

    static func == (a: RaceResult, b: RaceResult) -> Bool {
        a.trackId == b.trackId && a.position == b.position && a.time == b.time
    }
}

struct GhostFrame {
    var x: Double
    var y: Double
    var ang: Double
    var whip: Double
}

// MARK: - Colors

extension Color {
    init(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
