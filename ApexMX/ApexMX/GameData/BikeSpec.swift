import Foundation

/// Tuning for a single suspension unit.
///
/// Values are in SI units so they can be reasoned about physically: `stiffness`
/// is N/m, `compressionDamping` and `reboundDamping` are N·s/m, `travel` is metres.
public struct SuspensionSpec: Codable, Sendable {
    /// Maximum stroke from full extension to full compression, in metres.
    public var travel: Double
    /// Spring rate in newtons per metre.
    public var stiffness: Double
    /// Damping while the spring is compressing (absorbing an impact).
    public var compressionDamping: Double
    /// Damping while the spring is extending. Higher than compression damping on
    /// a real bike, which is what stops the machine from bucking after a hit.
    public var reboundDamping: Double
    /// Extra spring rate applied over the last 15% of travel, modelling the
    /// progressive bump stop that prevents a harsh metal-on-metal bottom-out.
    public var bumpStopStiffness: Double
    /// Static sag as a fraction of travel; the suspension settles here at rest.
    public var preload: Double

    public init(travel: Double,
                stiffness: Double,
                compressionDamping: Double,
                reboundDamping: Double,
                bumpStopStiffness: Double,
                preload: Double) {
        self.travel = travel
        self.stiffness = stiffness
        self.compressionDamping = compressionDamping
        self.reboundDamping = reboundDamping
        self.bumpStopStiffness = bumpStopStiffness
        self.preload = preload
    }
}

/// Engine and drivetrain tuning.
public struct EngineSpec: Codable, Sendable {
    /// Peak crank torque in newton-metres.
    public var peakTorque: Double
    /// Engine speed at peak torque, in revolutions per minute.
    public var peakTorqueRPM: Double
    /// Engine speed at which the rev limiter cuts in.
    public var redlineRPM: Double
    /// Engine speed the motor idles at.
    public var idleRPM: Double
    /// Combined gearbox and final-drive ratio, mapping wheel rad/s to engine rad/s.
    public var overallGearRatio: Double
    /// Rotational inertia of the crank assembly, kg·m². Drives throttle response
    /// and how strongly a mid-air throttle blip rotates the bike.
    public var flywheelInertia: Double
    /// How quickly the throttle plate follows rider input, in units per second.
    public var throttleResponse: Double

    public init(peakTorque: Double,
                peakTorqueRPM: Double,
                redlineRPM: Double,
                idleRPM: Double,
                overallGearRatio: Double,
                flywheelInertia: Double,
                throttleResponse: Double) {
        self.peakTorque = peakTorque
        self.peakTorqueRPM = peakTorqueRPM
        self.redlineRPM = redlineRPM
        self.idleRPM = idleRPM
        self.overallGearRatio = overallGearRatio
        self.flywheelInertia = flywheelInertia
        self.throttleResponse = throttleResponse
    }

    /// Normalised torque curve: rises to 1.0 at peak, then falls away toward the
    /// limiter. Returns a multiplier on `peakTorque`.
    public func torqueFraction(atRPM rpm: Double) -> Double {
        guard rpm > 0 else { return 0.55 }
        if rpm <= peakTorqueRPM {
            // Strong low-end that builds smoothly; never drops below idle pull.
            let t = MathUtils.clamp01(rpm / peakTorqueRPM)
            return MathUtils.lerp(0.55, 1.0, MathUtils.smoothstep(0, 1, t))
        }
        // Above peak the curve tapers, then the limiter cuts hard.
        if rpm >= redlineRPM { return 0 }
        let t = (rpm - peakTorqueRPM) / max(redlineRPM - peakTorqueRPM, 1)
        return MathUtils.lerp(1.0, 0.62, MathUtils.clamp01(t))
    }
}

/// A complete, tunable bike definition.
///
/// Everything gameplay-facing lives here rather than in the physics code, so
/// designers can retune handling — or ship a new machine — without touching
/// `BikePhysicsBody`.
public struct BikeSpec: Codable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var className: String
    public var flavorText: String

    // MARK: Mass properties
    /// Dry mass of the machine in kilograms.
    public var chassisMass: Double
    /// Rider mass in kilograms, carried as part of the sprung mass.
    public var riderMass: Double
    /// Centre-of-mass offset from the chassis origin, in body-local metres.
    public var centerOfMassOffset: Vector2Data
    /// Rotational inertia about the centre of mass, kg·m².
    public var momentOfInertia: Double

    // MARK: Geometry
    /// Distance between the wheel spindles, in metres.
    public var wheelbase: Double
    /// Height of the wheel mounting points above the chassis origin.
    public var axleHeight: Double
    public var frontWheelRadius: Double
    public var rearWheelRadius: Double
    /// Rotational inertia of each wheel, kg·m².
    public var wheelInertia: Double

    // MARK: Subsystems
    public var frontSuspension: SuspensionSpec
    public var rearSuspension: SuspensionSpec
    public var engine: EngineSpec

    // MARK: Handling
    /// Peak braking torque available at the front wheel, N·m.
    public var frontBrakeTorque: Double
    /// Peak braking torque at the rear wheel. Deliberately weaker than the front,
    /// which is what makes the rear brake usable as an air-control tool.
    public var rearBrakeTorque: Double
    /// Tyre longitudinal stiffness — the slope of force against slip ratio.
    public var tyreStiffness: Double
    /// Base grip multiplier applied on top of the surface's own coefficient.
    public var tyreGripMultiplier: Double
    /// Angular acceleration the rider can generate in the air, rad/s².
    public var airRotationTorque: Double
    /// How strongly airborne rotation bleeds off, per second.
    public var airRotationDamping: Double
    /// Aerodynamic drag coefficient times frontal area, m².
    public var dragArea: Double
    /// How far the rider can shift their mass fore and aft, in metres.
    public var riderShiftRange: Double
    /// Landing pitch error, in radians, that the bike can absorb before crashing.
    public var landingForgiveness: Double

    /// Total sprung mass carried by the suspension.
    public var totalMass: Double { chassisMass + riderMass }

    public init(id: String,
                displayName: String,
                className: String,
                flavorText: String,
                chassisMass: Double,
                riderMass: Double,
                centerOfMassOffset: Vector2Data,
                momentOfInertia: Double,
                wheelbase: Double,
                axleHeight: Double,
                frontWheelRadius: Double,
                rearWheelRadius: Double,
                wheelInertia: Double,
                frontSuspension: SuspensionSpec,
                rearSuspension: SuspensionSpec,
                engine: EngineSpec,
                frontBrakeTorque: Double,
                rearBrakeTorque: Double,
                tyreStiffness: Double,
                tyreGripMultiplier: Double,
                airRotationTorque: Double,
                airRotationDamping: Double,
                dragArea: Double,
                riderShiftRange: Double,
                landingForgiveness: Double) {
        self.id = id
        self.displayName = displayName
        self.className = className
        self.flavorText = flavorText
        self.chassisMass = chassisMass
        self.riderMass = riderMass
        self.centerOfMassOffset = centerOfMassOffset
        self.momentOfInertia = momentOfInertia
        self.wheelbase = wheelbase
        self.axleHeight = axleHeight
        self.frontWheelRadius = frontWheelRadius
        self.rearWheelRadius = rearWheelRadius
        self.wheelInertia = wheelInertia
        self.frontSuspension = frontSuspension
        self.rearSuspension = rearSuspension
        self.engine = engine
        self.frontBrakeTorque = frontBrakeTorque
        self.rearBrakeTorque = rearBrakeTorque
        self.tyreStiffness = tyreStiffness
        self.tyreGripMultiplier = tyreGripMultiplier
        self.airRotationTorque = airRotationTorque
        self.airRotationDamping = airRotationDamping
        self.dragArea = dragArea
        self.riderShiftRange = riderShiftRange
        self.landingForgiveness = landingForgiveness
    }
}

/// `Codable` companion for `Vector2`, keeping the physics type free of
/// serialisation concerns.
public struct Vector2Data: Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public var vector: Vector2 { Vector2(x, y) }
}
