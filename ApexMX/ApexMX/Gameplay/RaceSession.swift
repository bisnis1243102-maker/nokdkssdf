import Foundation

/// Where a race is in its lifecycle.
public enum RacePhase: Equatable, Sendable {
    case staging          // Riders settling on the gate.
    case countdown(Double) // Seconds remaining.
    case racing
    case finished
}

/// A rider's standing at a moment in the race.
public struct Standing: Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let isPlayer: Bool
    public let position: Int
    public let lap: Int
    public let distance: Double
    /// Gap to the leader in metres. Zero for the leader.
    public let gapToLeader: Double
    public let finishTime: Double?
    public let bestLap: Double?
}

/// Final classification for one rider.
public struct RaceResult: Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let isPlayer: Bool
    public let position: Int
    public let totalTime: Double?
    public let bestLap: Double?
    public let crashes: Int
    public let cleanLandings: Int
    public let bestAirTime: Double
}

/// Owns a running race: the terrain, the field, the clock and the rules.
///
/// The session is deliberately free of any UI or rendering dependency. It is
/// stepped by whatever is driving the frame loop and publishes plain value
/// types, which is what allows the same code to run a local race, a replay, or
/// a headless simulation for balance testing.
public final class RaceSession: @unchecked Sendable {

    public let track: TrackDefinition
    public let terrain: Terrain
    public private(set) var riders: [Rider]
    public private(set) var phase: RacePhase = .staging
    /// Seconds since the gate dropped. Negative during the countdown.
    public private(set) var raceTime: Double = 0

    /// Input the player is currently applying. Set by the input layer each frame.
    public var playerInput: RiderInput = .neutral

    private var timestep = FixedTimestepAccumulator(stepsPerSecond: 240)
    private let lapLength: Double
    private let startLineX: Double
    private var ghostRecorder: GhostRecorder?

    /// Called once when the player crosses the line, with the full classification.
    public var onRaceComplete: (([RaceResult]) -> Void)?

    public var player: Rider? { riders.first { $0.isPlayer } }

    // MARK: - Setup

    /// - Parameters:
    ///   - track: The course to race.
    ///   - playerSpec: The player's fully upgraded machine.
    ///   - opponents: Opponent name, machine and skill, in grid order.
    ///   - recordGhost: When true, the player's inputs are recorded for ghost
    ///     playback and time-trial validation.
    public init(track: TrackDefinition,
                playerSpec: BikeSpec,
                opponents: [(name: String, spec: BikeSpec, skill: Double)],
                recordGhost: Bool = true) {
        self.track = track
        self.terrain = TrackBuilder.build(track)
        self.lapLength = track.lapLength
        self.startLineX = TrackBuilder.startPadding

        let gripScale = track.weather.gripMultiplier

        // The grid is staggered backward from the line so nobody starts inside
        // anybody else. In a 2.5D racer the riders share a lane, so the offset
        // is purely longitudinal.
        var field: [Rider] = []
        var playerBike = BikePhysicsBody(spec: playerSpec, position: .zero)
        playerBike.environmentGrip = gripScale
        let player = Rider(id: 0,
                           name: "You",
                           isPlayer: true,
                           liveryHue: 0.08,
                           bike: playerBike,
                           brain: nil)
        field.append(player)

        for (index, opponent) in opponents.enumerated() {
            var bike = BikePhysicsBody(spec: opponent.spec, position: .zero)
            bike.environmentGrip = gripScale
            let personality = AIPersonality.forSkill(opponent.skill,
                                                     seed: track.seed &+ UInt64(index &+ 1) &* 0x9E37)
            let rider = Rider(id: index + 1,
                              name: opponent.name,
                              isPlayer: false,
                              liveryHue: Double(index + 1) / Double(max(opponents.count, 1)) * 0.85,
                              bike: bike,
                              brain: AIRiderBrain(personality: personality))
            field.append(rider)
        }
        self.riders = field

        if recordGhost {
            ghostRecorder = GhostRecorder(trackID: track.id, bikeID: playerSpec.id)
        }

        stageField()
    }

    /// Places every rider on the gate and starts the countdown.
    public func stageField() {
        for (index, rider) in riders.enumerated() {
            let x = startLineX - Double(index) * 1.9
            rider.reset(on: terrain, atX: x, raceTime: 0)
        }
        raceTime = -RaceSession.countdownDuration
        phase = .countdown(RaceSession.countdownDuration)
        timestep.reset()
        ghostRecorder?.reset()
    }

    public static let countdownDuration: Double = 3.0

    // MARK: - Frame driving

    /// Advances the race by a frame's worth of real time.
    ///
    /// Internally this runs zero or more fixed physics steps, so gameplay is
    /// identical whether the device is presenting at 30, 60 or 120 Hz.
    public func update(deltaTime: Double) {
        guard phase != .finished else { return }
        let steps = timestep.advance(by: deltaTime)
        guard steps > 0 else { return }
        for _ in 0..<steps {
            simulateStep(dt: timestep.step)
        }
    }

    private func simulateStep(dt: Double) {
        raceTime += dt

        switch phase {
        case .staging:
            return
        case .countdown:
            if raceTime >= 0 {
                phase = .racing
            } else {
                phase = .countdown(-raceTime)
                // Riders can hold the throttle against the gate, but nothing
                // moves until it drops. Jumping the start is simply impossible
                // rather than penalised, which keeps the rule unambiguous.
                return
            }
        case .racing, .finished:
            break
        }

        for rider in riders where !rider.hasFinished {
            let input = rider.isPlayer ? playerInput : .neutral
            rider.step(dt: dt, terrain: terrain, playerInput: input, raceTime: raceTime)
            updateProgress(for: rider)
        }

        if let player = self.player, phase == .racing {
            ghostRecorder?.record(input: player.lastInput, at: raceTime)
        }

        if riders.allSatisfy({ $0.hasFinished }) || (player?.hasFinished ?? false) {
            finish()
        }
    }

    /// Tracks lap completion and wraps riders back to the start of the lap.
    ///
    /// The course loops by translating the rider backward by exactly one lap
    /// length. The start pad and run-out are both flat and at the same
    /// elevation, so the transition is invisible and, crucially, costs no speed.
    private func updateProgress(for rider: Rider) {
        let finishLineX = startLineX + lapLength
        let lapProgress = rider.bike.position.x - startLineX
        rider.updateDistance(Double(rider.lap - 1) * lapLength + lapProgress)

        guard rider.bike.position.x >= finishLineX else { return }
        let wasOnFinalLap = rider.lap >= track.laps
        rider.completeLap(at: raceTime, totalLaps: track.laps)
        if !wasOnFinalLap {
            rider.bike.translate(by: Vector2(-lapLength, 0))
        }
    }

    private func finish() {
        guard phase != .finished else { return }
        phase = .finished
        onRaceComplete?(results())
        if let player = self.player, player.hasFinished {
            ghostRecorder?.finalise(totalTime: player.finishTime ?? raceTime)
        }
    }

    // MARK: - Standings

    /// Live order of the field, leader first.
    public func standings() -> [Standing] {
        let ordered = riders.sorted { a, b in
            switch (a.finishTime, b.finishTime) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.totalDistance > b.totalDistance
            }
        }
        let leaderDistance = ordered.first?.totalDistance ?? 0
        return ordered.enumerated().map { index, rider in
            Standing(id: rider.id,
                     name: rider.name,
                     isPlayer: rider.isPlayer,
                     position: index + 1,
                     lap: min(rider.lap, track.laps),
                     distance: rider.totalDistance,
                     gapToLeader: max(0, leaderDistance - rider.totalDistance),
                     finishTime: rider.finishTime,
                     bestLap: rider.bestLapTime)
        }
    }

    public func results() -> [RaceResult] {
        standings().map { standing in
            let rider = riders.first { $0.id == standing.id }
            return RaceResult(id: standing.id,
                              name: standing.name,
                              isPlayer: standing.isPlayer,
                              position: standing.position,
                              totalTime: standing.finishTime,
                              bestLap: standing.bestLap,
                              crashes: rider?.crashCount ?? 0,
                              cleanLandings: rider?.cleanLandings ?? 0,
                              bestAirTime: rider?.bestAirTime ?? 0)
        }
    }

    /// The player's current position in the field, 1-based.
    public var playerPosition: Int {
        standings().first { $0.isPlayer }?.position ?? riders.count
    }

    /// The recorded ghost for this run, once the player has finished.
    public var recordedGhost: GhostRun? { ghostRecorder?.completedRun }

    // MARK: - Player actions

    /// Immediately remounts the player after a crash, skipping the wait.
    public func requestPlayerRecovery() {
        guard let player = self.player, player.bike.hasCrashed else { return }
        player.remount(on: terrain)
    }

    /// Restarts the race from the gate, keeping the same field and machines.
    public func restart() {
        stageField()
    }
}
