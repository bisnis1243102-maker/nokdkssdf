import Foundation

/// A recorded run, stored as the rider's inputs rather than their trajectory.
///
/// Because the simulation is deterministic, replaying the input stream against
/// the same track and machine reproduces the run exactly. That makes a ghost
/// roughly two orders of magnitude smaller than a position trace, and — more
/// importantly — makes it verifiable: a server can re-simulate the inputs and
/// confirm the claimed time really is achievable.
public struct GhostRun: Codable, Sendable, Identifiable {

    /// One input change, timestamped from the gate drop.
    public struct Keyframe: Codable, Sendable {
        public let time: Double
        public let input: RiderInput

        public init(time: Double, input: RiderInput) {
            self.time = time
            self.input = input
        }
    }

    public var id: String { "\(trackID)_\(bikeID)_\(Int(totalTime * 1000))" }

    public let trackID: String
    public let bikeID: String
    public let totalTime: Double
    public let recordedAt: Date
    public let keyframes: [Keyframe]
    /// Version of the physics the run was recorded against. A ghost from an
    /// older physics build cannot be trusted to reproduce, so it is retired
    /// rather than replayed incorrectly.
    public let physicsVersion: Int

    public init(trackID: String,
                bikeID: String,
                totalTime: Double,
                recordedAt: Date,
                keyframes: [Keyframe],
                physicsVersion: Int = GhostRun.currentPhysicsVersion) {
        self.trackID = trackID
        self.bikeID = bikeID
        self.totalTime = totalTime
        self.recordedAt = recordedAt
        self.keyframes = keyframes
        self.physicsVersion = physicsVersion
    }

    /// Bumped whenever a change to the solver would alter recorded outcomes.
    public static let currentPhysicsVersion = 1

    public var isReplayable: Bool { physicsVersion == GhostRun.currentPhysicsVersion }

    /// The input active at a given race time.
    public func input(at time: Double) -> RiderInput {
        guard !keyframes.isEmpty else { return .neutral }
        // Binary search for the last keyframe at or before `time`.
        var low = 0
        var high = keyframes.count - 1
        var found = -1
        while low <= high {
            let mid = (low + high) / 2
            if keyframes[mid].time <= time {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found >= 0 ? keyframes[found].input : .neutral
    }
}

/// Captures a run as it happens.
///
/// Inputs are only written when they change by a meaningful amount, which keeps
/// a three-minute run to a few kilobytes without losing any control nuance the
/// player could actually feel.
public final class GhostRecorder {

    /// Smallest input change worth recording, per channel.
    private static let quantum: Double = 0.02

    private let trackID: String
    private let bikeID: String
    private var keyframes: [GhostRun.Keyframe] = []
    private var lastRecorded: RiderInput = .neutral
    private var hasRecordedAny = false

    public private(set) var completedRun: GhostRun?

    public init(trackID: String, bikeID: String) {
        self.trackID = trackID
        self.bikeID = bikeID
    }

    public func reset() {
        keyframes.removeAll(keepingCapacity: true)
        lastRecorded = .neutral
        hasRecordedAny = false
        completedRun = nil
    }

    public func record(input: RiderInput, at time: Double) {
        guard time >= 0 else { return }
        if hasRecordedAny && !isSignificantChange(from: lastRecorded, to: input) { return }
        keyframes.append(GhostRun.Keyframe(time: time, input: input))
        lastRecorded = input
        hasRecordedAny = true
    }

    private func isSignificantChange(from a: RiderInput, to b: RiderInput) -> Bool {
        abs(a.throttle - b.throttle) >= GhostRecorder.quantum
            || abs(a.frontBrake - b.frontBrake) >= GhostRecorder.quantum
            || abs(a.rearBrake - b.rearBrake) >= GhostRecorder.quantum
            || abs(a.lean - b.lean) >= GhostRecorder.quantum
    }

    public func finalise(totalTime: Double) {
        completedRun = GhostRun(trackID: trackID,
                                bikeID: bikeID,
                                totalTime: totalTime,
                                recordedAt: Date(),
                                keyframes: keyframes)
    }
}

/// Replays a `GhostRun` alongside a live race.
///
/// The ghost is a full physics body, not an interpolated path, so it collides
/// with the same terrain, compresses the same suspension and crashes in the
/// same places the original run did.
public final class GhostPlayer {

    public let run: GhostRun
    public private(set) var bike: BikePhysicsBody
    private var elapsed: Double = 0

    public init?(run: GhostRun, spec: BikeSpec, terrain: Terrain, startX: Double) {
        guard run.isReplayable else { return nil }
        self.run = run
        var body = BikePhysicsBody(spec: spec, position: .zero)
        body.settle(on: terrain, atX: startX)
        self.bike = body
    }

    public func step(dt: Double, terrain: Terrain) {
        elapsed += dt
        bike.step(dt: dt, input: run.input(at: elapsed), terrain: terrain)
    }

    public func reset(on terrain: Terrain, atX x: Double) {
        elapsed = 0
        bike.settle(on: terrain, atX: x)
    }

    /// True once the ghost has run past the end of its recording.
    public var hasFinished: Bool { elapsed >= run.totalTime }
}
