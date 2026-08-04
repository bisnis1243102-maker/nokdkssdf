import Combine
import SwiftUI

/// Which screen the app is showing.
public enum AppRoute: Equatable {
    case mainMenu
    case trackSelect
    case garage
    case settings
    case profile
    case race
    case results
}

/// Owns application-level state and the transitions between screens.
///
/// Deliberately thin: it holds the profile, the current route and the live race
/// session, and nothing else. Game rules live in `RaceSession`, progression
/// lives in `CareerService`, persistence lives in `ProfileStore`. This object
/// only wires them together, which keeps every one of them independently
/// testable.
@MainActor
public final class GameCoordinator: ObservableObject {

    @Published public private(set) var route: AppRoute = .mainMenu
    @Published public var profile: PlayerProfile
    @Published public private(set) var session: RaceSession?
    @Published public private(set) var lastResults: [RaceResult] = []
    @Published public private(set) var lastReward: RaceReward?
    @Published public private(set) var selectedTrackID: String

    /// Transient banner text, e.g. an unlock notification.
    @Published public var notice: String?

    public let bikes: [BikeSpec]
    public let tracks: [TrackDefinition]

    private let profileStore: ProfileStore
    private let ghostStore: GhostStore

    public init(profileStore: ProfileStore = ProfileStore(),
                ghostStore: GhostStore = GhostStore()) {
        self.profileStore = profileStore
        self.ghostStore = ghostStore
        self.bikes = BikeCatalog.load()
        self.tracks = TrackCatalog.load()

        var loaded = profileStore.load()
        // Re-evaluate unlocks on launch so a data-driven balance change to the
        // requirements takes effect without the player racing again.
        CareerService.unlockEligibleTracks(in: &loaded, tracks: tracks)
        self.profile = loaded
        self.selectedTrackID = loaded.unlockedTrackIDs.last ?? TrackCatalog.ridgelinePark.id

        Log.info("Profile loaded: level \(loaded.level), \(loaded.credits) credits")
    }

    // MARK: - Navigation

    public func navigate(to route: AppRoute) {
        self.route = route
    }

    public func selectTrack(_ trackID: String) {
        guard profile.hasUnlocked(trackID) else { return }
        selectedTrackID = trackID
    }

    public var selectedTrack: TrackDefinition {
        TrackCatalog.track(withID: selectedTrackID, in: tracks)
    }

    // MARK: - Persistence

    public func save() {
        profileStore.save(profile)
    }

    /// Called when the app is heading to the background, where an async write
    /// might not complete before the process is suspended.
    public func saveImmediately() {
        do {
            try profileStore.saveSynchronously(profile)
        } catch {
            Log.error("Immediate save failed: \(error.localizedDescription)", category: .save)
        }
    }

    // MARK: - Racing

    /// Builds and starts a race on the selected track.
    ///
    /// - Parameter raceGhost: When true and a personal best exists for the
    ///   track, the player's own best run is replayed alongside them.
    public func startRace(againstGhost raceGhost: Bool = true) {
        let track = selectedTrack
        let spec = profile.activeSpec(roster: bikes)
        let field = CareerService.buildField(for: track,
                                             playerLevel: profile.level,
                                             roster: bikes)

        let session = RaceSession(track: track,
                                  playerSpec: spec,
                                  opponents: field,
                                  recordGhost: true)
        session.onRaceComplete = { [weak self] results in
            Task { @MainActor in self?.completeRace(results) }
        }
        self.session = session
        self.pendingGhost = raceGhost ? ghostStore.bestRun(forTrack: track.id) : nil
        self.route = .race
        Log.info("Race started on \(track.displayName)", category: .gameplay)
    }

    /// The ghost to attach to the next scene presentation, if any.
    public private(set) var pendingGhost: GhostRun?

    /// Builds a playable ghost against the live session's terrain.
    public func makeGhostPlayer() -> GhostPlayer? {
        guard let run = pendingGhost, let session = session else { return nil }
        let spec = BikeCatalog.spec(withID: run.bikeID, in: bikes)
        return GhostPlayer(run: run,
                           spec: spec,
                           terrain: session.terrain,
                           startX: TrackBuilder.startPadding)
    }

    public func restartRace() {
        session?.restart()
    }

    public func abandonRace() {
        session = nil
        pendingGhost = nil
        route = .mainMenu
    }

    /// Applies the outcome of a finished race to the player's career.
    private func completeRace(_ results: [RaceResult]) {
        lastResults = results
        guard let playerResult = results.first(where: { $0.isPlayer }) else {
            route = .results
            return
        }

        let track = selectedTrack
        let reward = CareerService.applyResult(playerResult,
                                               track: track,
                                               fieldSize: results.count,
                                               to: &profile)
        lastReward = reward

        if let ghost = session?.recordedGhost, ghostStore.storeIfFaster(ghost) {
            Log.info("New personal best ghost stored for \(track.displayName)", category: .gameplay)
        }

        if let unlocked = reward.unlockedTrackIDs.first {
            let name = TrackCatalog.track(withID: unlocked, in: tracks).displayName
            notice = "\(name) unlocked"
        }

        save()
        route = .results
    }

    // MARK: - Garage actions

    @discardableResult
    public func purchaseBike(_ bikeID: String) -> Bool {
        let success = CareerService.purchaseBike(bikeID, in: &profile)
        if success {
            profile.selectedBikeID = bikeID
            save()
        }
        return success
    }

    @discardableResult
    public func purchaseUpgrade(_ category: UpgradeCategory) -> Bool {
        let success = CareerService.purchaseUpgrade(category,
                                                    bikeID: profile.selectedBikeID,
                                                    in: &profile)
        if success { save() }
        return success
    }

    public func selectBike(_ bikeID: String) {
        guard profile.owns(bikeID) else { return }
        profile.selectedBikeID = bikeID
        save()
    }

    /// The player's machine as it will actually be raced.
    public var activeSpec: BikeSpec {
        profile.activeSpec(roster: bikes)
    }
}
