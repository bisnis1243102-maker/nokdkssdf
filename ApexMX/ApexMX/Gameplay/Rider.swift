import Foundation

/// One competitor in a race: a physics body, a source of input, and the
/// race-progress bookkeeping that goes with it.
public final class Rider: Identifiable, @unchecked Sendable {

    public let id: Int
    public let name: String
    public let isPlayer: Bool
    /// Livery accent, as a hue in `0...1`. Keeps the renderer free of per-rider
    /// asset lookups while still making the field readable at a glance.
    public let liveryHue: Double

    public var bike: BikePhysicsBody
    /// `nil` for the human player.
    public var brain: AIRiderBrain?

    /// Input applied on the most recent step, whatever its source.
    public private(set) var lastInput: RiderInput = .neutral

    // MARK: Race progress
    public private(set) var lap: Int = 1
    public private(set) var lapTimes: [Double] = []
    public private(set) var currentLapStartTime: Double = 0
    public private(set) var finishTime: Double?
    public private(set) var totalDistance: Double = 0

    /// Seconds remaining before an automatic recovery after a crash.
    public private(set) var recoveryCountdown: Double = 0
    public private(set) var crashCount: Int = 0
    /// Longest single jump, in seconds of air time. Shown in the results screen.
    public private(set) var bestAirTime: Double = 0
    /// Running tally of clean landings, which feeds the style bonus.
    public private(set) var cleanLandings: Int = 0

    public init(id: Int,
                name: String,
                isPlayer: Bool,
                liveryHue: Double,
                bike: BikePhysicsBody,
                brain: AIRiderBrain?) {
        self.id = id
        self.name = name
        self.isPlayer = isPlayer
        self.liveryHue = liveryHue
        self.bike = bike
        self.brain = brain
    }

    public var hasFinished: Bool { finishTime != nil }

    public var bestLapTime: Double? { lapTimes.min() }

    /// Advances one fixed step.
    ///
    /// - Parameter playerInput: Used only when `isPlayer` is true; AI riders
    ///   ask their brain for input instead.
    public func step(dt: Double, terrain: Terrain, playerInput: RiderInput, raceTime: Double) {
        let input: RiderInput
        if isPlayer {
            input = playerInput
        } else if brain != nil {
            input = brain!.update(dt: dt, bike: bike, terrain: terrain)
        } else {
            input = .neutral
        }
        lastInput = input

        bike.step(dt: dt, input: input, terrain: terrain)

        bestAirTime = max(bestAirTime, bike.airTime)
        if bike.didLandThisStep && !bike.hasCrashed && bike.lastLandingPitchError < 0.18 {
            cleanLandings += 1
        }

        updateRecovery(dt: dt, terrain: terrain)
    }

    /// Handles the post-crash pause and the automatic remount.
    private func updateRecovery(dt: Double, terrain: Terrain) {
        if bike.hasCrashed {
            if recoveryCountdown <= 0 {
                recoveryCountdown = Rider.recoveryDelay
                crashCount += 1
            } else {
                recoveryCountdown -= dt
                if recoveryCountdown <= 0 {
                    remount(on: terrain)
                }
            }
        }
    }

    /// Seconds a rider loses to a crash. Deliberately long enough to matter and
    /// short enough not to end the race outright.
    public static let recoveryDelay: Double = 1.7

    /// Puts the rider back on the bike, a little way back up the track so they
    /// are not dropped straight into whatever caught them out.
    public func remount(on terrain: Terrain) {
        let recoveryX = max(bike.position.x - 3.0, terrain.originX + 1)
        bike.recover(on: terrain, atX: recoveryX, carryingSpeed: 4.0)
        recoveryCountdown = 0
    }

    /// Resets to the grid for a race restart.
    public func reset(on terrain: Terrain, atX x: Double, raceTime: Double) {
        bike.settle(on: terrain, atX: x)
        lap = 1
        lapTimes.removeAll()
        currentLapStartTime = raceTime
        finishTime = nil
        totalDistance = 0
        recoveryCountdown = 0
        crashCount = 0
        bestAirTime = 0
        cleanLandings = 0
        lastInput = .neutral
    }

    // MARK: Progress bookkeeping

    /// Records the completion of a lap.
    public func completeLap(at raceTime: Double, totalLaps: Int) {
        lapTimes.append(raceTime - currentLapStartTime)
        currentLapStartTime = raceTime
        if lap >= totalLaps {
            finishTime = raceTime
        } else {
            lap += 1
        }
    }

    public func updateDistance(_ distance: Double) {
        totalDistance = max(totalDistance, distance)
    }
}
