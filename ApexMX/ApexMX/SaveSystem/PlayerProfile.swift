import Foundation

/// A recorded personal best on one track.
public struct TrackRecord: Codable, Sendable {
    public var trackID: String
    public var bestLapTime: Double
    public var bestTotalTime: Double
    public var bestPosition: Int
    public var timesRaced: Int
    public var bikeID: String

    public init(trackID: String,
                bestLapTime: Double,
                bestTotalTime: Double,
                bestPosition: Int,
                timesRaced: Int,
                bikeID: String) {
        self.trackID = trackID
        self.bestLapTime = bestLapTime
        self.bestTotalTime = bestTotalTime
        self.bestPosition = bestPosition
        self.timesRaced = timesRaced
        self.bikeID = bikeID
    }

    /// Medal earned against the track's target time.
    public func medal(goldLapTime: Double) -> Medal {
        if bestLapTime <= goldLapTime { return .gold }
        if bestLapTime <= goldLapTime * 1.08 { return .silver }
        if bestLapTime <= goldLapTime * 1.18 { return .bronze }
        return .none
    }
}

public enum Medal: String, Codable, Sendable {
    case none, bronze, silver, gold

    public var displayName: String {
        switch self {
        case .none: return "—"
        case .bronze: return "Bronze"
        case .silver: return "Silver"
        case .gold: return "Gold"
        }
    }

    /// Career points awarded for holding this medal.
    public var points: Int {
        switch self {
        case .none: return 0
        case .bronze: return 1
        case .silver: return 2
        case .gold: return 3
        }
    }
}

/// Lifetime statistics. Cheap to keep, and the backbone of both the profile
/// screen and the achievement system.
public struct CareerStatistics: Codable, Sendable {
    public var racesEntered: Int = 0
    public var racesWon: Int = 0
    public var podiums: Int = 0
    public var totalDistance: Double = 0
    public var totalAirTime: Double = 0
    public var crashes: Int = 0
    public var cleanLandings: Int = 0
    public var longestJump: Double = 0

    public init() {}

    public var winRate: Double {
        racesEntered > 0 ? Double(racesWon) / Double(racesEntered) : 0
    }
}

/// Everything about a player that survives between sessions.
public struct PlayerProfile: Codable, Sendable {

    /// Incremented whenever the on-disk shape changes, so old saves can be
    /// migrated rather than discarded.
    public static let currentVersion = 1

    public var version: Int
    public var displayName: String
    public var credits: Int
    public var experience: Int
    /// Bike IDs the player owns.
    public var ownedBikeIDs: [String]
    public var selectedBikeID: String
    /// Fitted parts, keyed by bike ID.
    public var loadouts: [String: UpgradeLoadout]
    public var records: [String: TrackRecord]
    public var statistics: CareerStatistics
    public var unlockedTrackIDs: [String]
    public var settings: GameSettings

    public init(version: Int = PlayerProfile.currentVersion,
                displayName: String = "Rider",
                credits: Int = 2_500,
                experience: Int = 0,
                ownedBikeIDs: [String] = [BikeCatalog.scoutFX250.id],
                selectedBikeID: String = BikeCatalog.scoutFX250.id,
                loadouts: [String: UpgradeLoadout] = [:],
                records: [String: TrackRecord] = [:],
                statistics: CareerStatistics = CareerStatistics(),
                unlockedTrackIDs: [String] = [TrackCatalog.ridgelinePark.id],
                settings: GameSettings = GameSettings()) {
        self.version = version
        self.displayName = displayName
        self.credits = credits
        self.experience = experience
        self.ownedBikeIDs = ownedBikeIDs
        self.selectedBikeID = selectedBikeID
        self.loadouts = loadouts
        self.records = records
        self.statistics = statistics
        self.unlockedTrackIDs = unlockedTrackIDs
        self.settings = settings
    }

    /// Rider level, derived from experience on a widening curve.
    public var level: Int {
        max(1, Int((Double(experience) / 750.0).squareRoot()) + 1)
    }

    /// Experience needed to reach the next level.
    public var experienceForNextLevel: Int {
        let next = level
        return Int(pow(Double(next), 2) * 750)
    }

    public func loadout(for bikeID: String) -> UpgradeLoadout {
        loadouts[bikeID] ?? UpgradeLoadout()
    }

    /// The player's current machine with all fitted parts applied.
    public func activeSpec(roster: [BikeSpec] = BikeCatalog.builtIn) -> BikeSpec {
        let base = BikeCatalog.spec(withID: selectedBikeID, in: roster)
        return UpgradeSystem.apply(loadout(for: selectedBikeID), to: base)
    }

    public func owns(_ bikeID: String) -> Bool { ownedBikeIDs.contains(bikeID) }
    public func hasUnlocked(_ trackID: String) -> Bool { unlockedTrackIDs.contains(trackID) }

    /// Total medal points across every track, which gates track unlocks.
    public func medalPoints(tracks: [TrackDefinition] = TrackCatalog.builtIn) -> Int {
        tracks.reduce(0) { total, track in
            guard let record = records[track.id] else { return total }
            return total + record.medal(goldLapTime: track.goldLapTime).points
        }
    }
}

/// Player-facing options. Stored inside the profile so they sync with progress.
public struct GameSettings: Codable, Sendable {
    public var masterVolume: Double = 0.8
    public var musicVolume: Double = 0.55
    public var effectsVolume: Double = 0.9
    public var hapticsEnabled: Bool = true
    public var hapticStrength: Double = 0.7
    public var hudScale: Double = 1.0
    public var showSpeedometer: Bool = true
    public var showMiniMap: Bool = true
    public var reduceMotion: Bool = false
    public var highContrastHUD: Bool = false
    public var colorblindMode: ColorblindMode = .none
    public var frameRateCap: FrameRateCap = .automatic
    public var graphicsQuality: GraphicsQuality = .automatic
    public var developerOverlay: Bool = false
    public var invertLeanControls: Bool = false
    /// Left/right placement of the throttle. Accessibility and handedness.
    public var throttleOnRight: Bool = true

    public init() {}
}

public enum ColorblindMode: String, Codable, CaseIterable, Sendable {
    case none, protanopia, deuteranopia, tritanopia

    public var displayName: String {
        switch self {
        case .none: return "Off"
        case .protanopia: return "Protanopia"
        case .deuteranopia: return "Deuteranopia"
        case .tritanopia: return "Tritanopia"
        }
    }
}

public enum FrameRateCap: String, Codable, CaseIterable, Sendable {
    case automatic, thirty, sixty, oneTwenty

    public var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .thirty: return "30 FPS"
        case .sixty: return "60 FPS"
        case .oneTwenty: return "120 FPS"
        }
    }

    /// Preferred frames per second, or `nil` to let the system decide.
    public var preferredFPS: Int? {
        switch self {
        case .automatic: return nil
        case .thirty: return 30
        case .sixty: return 60
        case .oneTwenty: return 120
        }
    }
}

public enum GraphicsQuality: String, Codable, CaseIterable, Sendable {
    case automatic, battery, balanced, quality

    public var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .battery: return "Battery Saver"
        case .balanced: return "Balanced"
        case .quality: return "Quality"
        }
    }
}
