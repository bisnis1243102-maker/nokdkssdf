import Foundation

/// The behavioural traits that make one AI opponent different from another.
///
/// Note what is *not* here: no speed multiplier, no grip bonus, no catch-up
/// assistance. Every opponent runs the same `BikePhysicsBody` on the same
/// terrain and can only express skill through the quality and timing of the
/// `RiderInput` it produces — the same currency the player spends.
public struct AIPersonality: Sendable {
    /// Seconds between the brain noticing something and acting on it.
    public var reactionTime: Double
    /// How accurately the intended input is delivered, `0...1`. Below 1 the
    /// rider is imprecise, applying slightly wrong values.
    public var inputPrecision: Double
    /// Willingness to carry speed into a hazard, `0...1`.
    public var riskTolerance: Double
    /// Quality of jump preparation, `0...1`. Drives preload and air correction.
    public var jumpTiming: Double
    /// Ability to save a bad landing, `0...1`.
    public var recoverySkill: Double
    /// Multiplier on the target speed the rider is willing to run.
    public var paceFactor: Double
    /// Seed for this rider's own deterministic noise.
    public var seed: UInt64

    public init(reactionTime: Double,
                inputPrecision: Double,
                riskTolerance: Double,
                jumpTiming: Double,
                recoverySkill: Double,
                paceFactor: Double,
                seed: UInt64) {
        self.reactionTime = reactionTime
        self.inputPrecision = inputPrecision
        self.riskTolerance = riskTolerance
        self.jumpTiming = jumpTiming
        self.recoverySkill = recoverySkill
        self.paceFactor = paceFactor
        self.seed = seed
    }

    /// Builds a personality from a single 0–1 skill value, interpolating every
    /// trait. Career difficulty and multiplayer bot fill both use this so that
    /// opponent strength is one tunable number.
    public static func forSkill(_ skill: Double, seed: UInt64) -> AIPersonality {
        let s = MathUtils.clamp01(skill)
        return AIPersonality(
            reactionTime: MathUtils.lerp(0.34, 0.10, s),
            inputPrecision: MathUtils.lerp(0.68, 0.98, s),
            riskTolerance: MathUtils.lerp(0.35, 0.88, s),
            jumpTiming: MathUtils.lerp(0.45, 0.96, s),
            recoverySkill: MathUtils.lerp(0.30, 0.92, s),
            paceFactor: MathUtils.lerp(0.80, 1.02, s),
            seed: seed
        )
    }

    public static let rookie = AIPersonality.forSkill(0.15, seed: 0xA1_0001)
    public static let privateer = AIPersonality.forSkill(0.45, seed: 0xA1_0002)
    public static let factory = AIPersonality.forSkill(0.75, seed: 0xA1_0003)
    public static let champion = AIPersonality.forSkill(0.95, seed: 0xA1_0004)
}

/// Produces rider input for a computer-controlled competitor.
///
/// The brain plans by looking ahead along the terrain — exactly the information
/// a human gets from the screen — and converts that into a target speed and a
/// target chassis attitude, then drives the controls toward those targets.
public struct AIRiderBrain: Sendable {

    public let personality: AIPersonality
    private var random: DeterministicRandom

    /// The input the brain has committed to. Reaction time is modelled by only
    /// refreshing this on an interval rather than every step.
    private var committedInput: RiderInput = .neutral
    private var timeSinceDecision: Double = 0
    /// Slowly drifting noise that makes a rider's pace feel human rather than
    /// metronomic, without being unfair in either direction.
    private var paceNoise: Double = 0

    public init(personality: AIPersonality) {
        self.personality = personality
        self.random = DeterministicRandom(seed: personality.seed)
    }

    /// Produces the input for this step.
    public mutating func update(dt: Double, bike: BikePhysicsBody, terrain: Terrain) -> RiderInput {
        timeSinceDecision += dt
        if timeSinceDecision >= personality.reactionTime {
            timeSinceDecision = 0
            paceNoise = MathUtils.damp(paceNoise, random.range(-0.05, 0.05), rate: 1.5, dt: dt)
            committedInput = decide(bike: bike, terrain: terrain)
        }
        return committedInput
    }

    // MARK: - Decision making

    private mutating func decide(bike: BikePhysicsBody, terrain: Terrain) -> RiderInput {
        if bike.hasCrashed { return .neutral }
        return bike.isAirborne
            ? airborneInput(bike: bike, terrain: terrain)
            : groundedInput(bike: bike, terrain: terrain)
    }

    /// On the ground the rider manages speed against what is coming and keeps
    /// the chassis balanced.
    private mutating func groundedInput(bike: BikePhysicsBody, terrain: Terrain) -> RiderInput {
        let speed = max(bike.forwardSpeed, 0)
        let target = targetSpeed(bike: bike, terrain: terrain, currentSpeed: speed)

        var throttle: Double
        var frontBrake: Double = 0
        var rearBrake: Double = 0

        let error = target - speed
        if error > 0.5 {
            throttle = MathUtils.clamp01(error / 6.0)
        } else if error < -1.5 {
            throttle = 0
            let braking = MathUtils.clamp01(-error / 8.0) * personality.inputPrecision
            frontBrake = braking * 0.8
            rearBrake = braking * 0.5
        } else {
            throttle = MathUtils.clamp01(0.45 + error * 0.2)
        }

        // A wheelie is slow and unstable; a good rider shuts it down early.
        if bike.isWheelieing && bike.angle > 0.30 {
            throttle *= MathUtils.lerp(0.85, 0.35, personality.inputPrecision)
        }
        // Wheelspin wastes drive; back off proportionally to skill.
        if bike.rearWheel.slipRatio > 0.35 {
            throttle *= MathUtils.lerp(0.95, 0.62, personality.inputPrecision)
        }

        // Weight is shifted back over a jump face to help the front wheel lift,
        // and forward on a descent to keep the front planted.
        let lookaheadSlope = terrain.slopeAngle(at: bike.position.x + max(speed * 0.35, 3))
        var lean = MathUtils.clamp(-lookaheadSlope * 1.4, -1, 1)

        // Preload before a launch: the better the rider's timing, the closer to
        // the lip they load the suspension.
        if let jump = upcomingLaunch(bike: bike, terrain: terrain, speed: speed) {
            let window = MathUtils.lerp(1.4, 0.7, personality.jumpTiming)
            if jump.distance < window * max(speed, 4) * 0.35 {
                lean = MathUtils.lerp(lean, -0.85, personality.jumpTiming)
                throttle = max(throttle, 0.75 * personality.riskTolerance + 0.2)
            }
        }

        return apply(precision: RiderInput(throttle: throttle,
                                           frontBrake: frontBrake,
                                           rearBrake: rearBrake,
                                           lean: lean))
    }

    /// In the air the only job is to arrive at the landing matched to its slope.
    private mutating func airborneInput(bike: BikePhysicsBody, terrain: Terrain) -> RiderInput {
        let landing = predictLanding(bike: bike, terrain: terrain)
        let targetPitch = terrain.slopeAngle(at: landing.x)
        let pitchError = MathUtils.angleDelta(from: bike.angle, to: targetPitch)

        // Anticipate: correcting for where the rotation is heading, not just
        // where it is, is the difference between a save and an over-correction.
        let anticipation = MathUtils.lerp(0.05, 0.28, personality.recoverySkill)
        let correction = pitchError - bike.angularVelocity * anticipation

        var throttle: Double = 0
        var rearBrake: Double = 0
        // Nose needs to come up: throttle. Nose needs to drop: rear brake.
        if correction > 0.03 {
            throttle = MathUtils.clamp01(correction * 2.2) * personality.recoverySkill
        } else if correction < -0.03 {
            rearBrake = MathUtils.clamp01(-correction * 2.4) * personality.recoverySkill
        }

        let lean = MathUtils.clamp(-correction * 2.0, -1, 1) * personality.recoverySkill

        return apply(precision: RiderInput(throttle: throttle,
                                           frontBrake: 0,
                                           rearBrake: rearBrake,
                                           lean: lean))
    }

    // MARK: - Planning helpers

    /// Chooses a speed for the terrain ahead. Rougher and steeper ground lowers
    /// the target; a bold rider lowers it less.
    private func targetSpeed(bike: BikePhysicsBody, terrain: Terrain, currentSpeed: Double) -> Double {
        // Look further ahead the faster the rider is going — roughly two
        // seconds of travel, which is about what a human reads off the screen.
        let horizon = MathUtils.clamp(currentSpeed * 2.0, 8, 45)
        var roughness: Double = 0
        var steepestDrop: Double = 0

        var distance: Double = 2
        while distance < horizon {
            let x = bike.position.x + distance
            let curvature = abs(terrain.curvature(at: x))
            // Near hazards matter more than distant ones.
            let weight = 1 - distance / horizon
            roughness += curvature * weight
            steepestDrop = min(steepestDrop, terrain.gradient(at: x))
            distance += 1.5
        }
        roughness /= Double(max(Int(horizon / 1.5), 1))

        let base = 26.0
        let caution = MathUtils.lerp(1.0, 0.35, MathUtils.clamp01(roughness * 4.5))
        let boldness = MathUtils.lerp(0.82, 1.12, personality.riskTolerance)
        let dropPenalty = MathUtils.lerp(1.0, 0.88, MathUtils.clamp01(-steepestDrop))

        return base * caution * boldness * dropPenalty
            * personality.paceFactor * (1 + paceNoise)
    }

    /// Finds the next convex lip within the look-ahead window, if any.
    private func upcomingLaunch(bike: BikePhysicsBody,
                                terrain: Terrain,
                                speed: Double) -> (distance: Double, x: Double)? {
        let horizon = MathUtils.clamp(speed * 1.2, 6, 30)
        var distance: Double = 1
        while distance < horizon {
            let x = bike.position.x + distance
            // A launch is rising ground that is about to stop rising.
            if terrain.gradient(at: x) > 0.22 && terrain.curvature(at: x) < -0.03 {
                return (distance, x)
            }
            distance += 0.5
        }
        return nil
    }

    /// Integrates a simple ballistic arc forward to find where the bike will
    /// meet the ground. Drag is ignored, which is accurate enough over the
    /// fraction of a second the brain is planning for.
    private func predictLanding(bike: BikePhysicsBody, terrain: Terrain) -> Vector2 {
        var position = bike.position
        var velocity = bike.velocity
        let dt = 1.0 / 30.0
        for _ in 0..<90 {   // Up to three seconds of flight.
            velocity.y += -9.81 * dt
            position += velocity * dt
            if position.y <= terrain.height(at: position.x) + 0.5 {
                return position
            }
        }
        return position
    }

    /// Degrades an ideal input toward what this rider can actually deliver.
    private mutating func apply(precision input: RiderInput) -> RiderInput {
        let error = 1 - personality.inputPrecision
        guard error > 0.001 else { return input }
        return RiderInput(
            throttle: input.throttle + random.range(-error, error) * 0.22,
            frontBrake: input.frontBrake + random.range(-error, error) * 0.14,
            rearBrake: input.rearBrake + random.range(-error, error) * 0.14,
            lean: input.lean + random.range(-error, error) * 0.30
        )
    }
}
