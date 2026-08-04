import Foundation

/// What a race paid out, broken down so the results screen can show the player
/// exactly where every credit came from.
public struct RaceReward: Sendable {
    public var positionCredits: Int = 0
    public var lapTimeCredits: Int = 0
    public var styleCredits: Int = 0
    public var medalCredits: Int = 0
    public var experience: Int = 0
    public var newPersonalBest: Bool = false
    public var medal: Medal = .none
    public var unlockedTrackIDs: [String] = []

    public var totalCredits: Int {
        positionCredits + lapTimeCredits + styleCredits + medalCredits
    }
}

/// Turns race outcomes into progression.
///
/// Kept separate from `RaceSession` on purpose: the session decides who won,
/// this decides what that is worth. Rebalancing the economy therefore never
/// risks touching the simulation.
public enum CareerService {

    /// Medal points needed to unlock each track beyond the first.
    private static let unlockRequirements: [String: Int] = [
        TrackCatalog.copperFlats.id: 2,
        TrackCatalog.ironworks.id: 5,
        TrackCatalog.summitRidge.id: 9
    ]

    /// Applies a finished race to the profile and returns what was earned.
    @discardableResult
    public static func applyResult(_ result: RaceResult,
                                   track: TrackDefinition,
                                   fieldSize: Int,
                                   to profile: inout PlayerProfile) -> RaceReward {
        var reward = RaceReward()

        // Position pays on a curve: winning is worth far more than finishing,
        // but a midfield result is never worthless.
        let positionScore = Double(max(fieldSize - result.position + 1, 1)) / Double(max(fieldSize, 1))
        reward.positionCredits = Int(400 * pow(positionScore, 1.6)) + 60
        reward.positionCredits = Int(Double(reward.positionCredits) * difficultyMultiplier(track))

        // Pace pays independently of placing, so a fast lap in a hard field
        // still moves the player forward.
        if let bestLap = result.bestLap {
            let ratio = track.goldLapTime / max(bestLap, 0.1)
            reward.lapTimeCredits = Int(MathUtils.clamp(300 * (ratio - 0.75), 0, 400))
            reward.medal = medal(forLap: bestLap, track: track)
            reward.medalCredits = reward.medal.points * 150
        }

        // Style rewards technique rather than luck: clean landings and air time,
        // reduced by every crash.
        let style = Double(result.cleanLandings) * 12
            + result.bestAirTime * 40
            - Double(result.crashes) * 45
        reward.styleCredits = max(0, Int(style))

        reward.experience = Int(Double(reward.totalCredits) * 0.6) + 40

        // Records
        let existing = profile.records[track.id]
        let bestLap = min(result.bestLap ?? .greatestFiniteMagnitude,
                          existing?.bestLapTime ?? .greatestFiniteMagnitude)
        let bestTotal = min(result.totalTime ?? .greatestFiniteMagnitude,
                            existing?.bestTotalTime ?? .greatestFiniteMagnitude)
        reward.newPersonalBest = (result.bestLap ?? .greatestFiniteMagnitude)
            < (existing?.bestLapTime ?? .greatestFiniteMagnitude)

        profile.records[track.id] = TrackRecord(
            trackID: track.id,
            bestLapTime: bestLap,
            bestTotalTime: bestTotal,
            bestPosition: min(result.position, existing?.bestPosition ?? Int.max),
            timesRaced: (existing?.timesRaced ?? 0) + 1,
            bikeID: profile.selectedBikeID
        )

        // Statistics
        profile.statistics.racesEntered += 1
        if result.position == 1 { profile.statistics.racesWon += 1 }
        if result.position <= 3 { profile.statistics.podiums += 1 }
        profile.statistics.totalDistance += track.lapLength * Double(track.laps)
        profile.statistics.crashes += result.crashes
        profile.statistics.cleanLandings += result.cleanLandings
        profile.statistics.longestJump = max(profile.statistics.longestJump, result.bestAirTime)
        profile.statistics.totalAirTime += result.bestAirTime

        profile.credits += reward.totalCredits
        profile.experience += reward.experience

        reward.unlockedTrackIDs = unlockEligibleTracks(in: &profile)
        return reward
    }

    private static func difficultyMultiplier(_ track: TrackDefinition) -> Double {
        1.0 + Double(track.difficulty - 1) * 0.22
    }

    public static func medal(forLap lapTime: Double, track: TrackDefinition) -> Medal {
        if lapTime <= track.goldLapTime { return .gold }
        if lapTime <= track.goldLapTime * 1.08 { return .silver }
        if lapTime <= track.goldLapTime * 1.18 { return .bronze }
        return .none
    }

    /// Unlocks any track whose medal-point requirement is now met.
    @discardableResult
    public static func unlockEligibleTracks(in profile: inout PlayerProfile,
                                            tracks: [TrackDefinition] = TrackCatalog.builtIn) -> [String] {
        let points = profile.medalPoints(tracks: tracks)
        var newlyUnlocked: [String] = []
        for track in tracks where !profile.hasUnlocked(track.id) {
            let required = unlockRequirements[track.id] ?? 0
            if points >= required {
                profile.unlockedTrackIDs.append(track.id)
                newlyUnlocked.append(track.id)
            }
        }
        return newlyUnlocked
    }

    /// Medal points still needed before a track opens up.
    public static func pointsRequired(for trackID: String) -> Int {
        unlockRequirements[trackID] ?? 0
    }

    /// Buys a machine, if the player can afford it and does not already own it.
    @discardableResult
    public static func purchaseBike(_ bikeID: String, in profile: inout PlayerProfile) -> Bool {
        guard !profile.owns(bikeID) else { return false }
        let price = BikeCatalog.price(for: bikeID)
        guard profile.credits >= price else { return false }
        profile.credits -= price
        profile.ownedBikeIDs.append(bikeID)
        return true
    }

    /// Fits the next level of a part, if affordable.
    @discardableResult
    public static func purchaseUpgrade(_ category: UpgradeCategory,
                                       bikeID: String,
                                       in profile: inout PlayerProfile) -> Bool {
        var loadout = profile.loadout(for: bikeID)
        guard let cost = loadout.upgradeCost(for: category), profile.credits >= cost else {
            return false
        }
        profile.credits -= cost
        loadout.setLevel(loadout.level(category) + 1, for: category)
        profile.loadouts[bikeID] = loadout
        return true
    }

    /// Builds an opponent field scaled to the track's difficulty and the
    /// player's own machine, so races stay competitive without rubber-banding.
    public static func buildField(for track: TrackDefinition,
                                  playerLevel: Int,
                                  roster: [BikeSpec] = BikeCatalog.builtIn,
                                  size: Int = 5) -> [(name: String, spec: BikeSpec, skill: Double)] {
        let names = ["R. Vasquez", "T. Okafor", "M. Lindqvist", "J. Brennan",
                     "K. Sato", "D. Moreau", "A. Petrov", "N. Halvorsen"]
        // Opponent strength comes from the difficulty of the course plus a
        // gentle nod to player level — and is fixed before the gate drops, so
        // it can never react to how the player is doing mid-race.
        let baseSkill = MathUtils.clamp(0.22 + Double(track.difficulty - 1) * 0.16
                                        + Double(playerLevel) * 0.012, 0.1, 0.95)
        let bikeIndex = min(track.difficulty / 2, roster.count - 1)
        let spec = roster[bikeIndex]

        return (0..<size).map { index in
            // Spread the field so there is someone to chase and someone to hold off.
            let spread = (Double(index) / Double(max(size - 1, 1)) - 0.5) * 0.30
            return (name: names[index % names.count],
                    spec: spec,
                    skill: MathUtils.clamp(baseSkill + spread, 0.05, 0.99))
        }
    }
}
