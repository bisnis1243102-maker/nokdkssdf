import Foundation

/// Why a rider went down. Surfaced to the player so a crash is always legible.
public enum CrashReason: String, Sendable {
    case caseFromLanding = "Cased the landing"
    case nosedIn = "Nosed in"
    case loopedOut = "Looped out"
    case chassisImpact = "Hard impact"

    public var advice: String {
        switch self {
        case .caseFromLanding: return "Match the bike's angle to the slope before you touch down."
        case .nosedIn: return "Blip the throttle in the air to bring the front wheel up."
        case .loopedOut: return "Shift your weight forward or tap the rear brake to drop the nose."
        case .chassisImpact: return "Carry less speed into that section, or take the safer line."
        }
    }
}

/// The rigid-body simulation of one motorcycle and its rider.
///
/// ## Model
/// The bike is a single planar rigid body (chassis + rider as sprung mass)
/// carrying two suspension units. Each unit resolves its compression against
/// the terrain kinematically and then produces a spring/damper force, which is
/// applied to the body at the mount point — generating both the vertical
/// support and the pitch torque that makes weight transfer emerge naturally
/// rather than being scripted.
///
/// Each wheel has its own spin degree of freedom. Drive torque, brake torque
/// and tyre reaction all act on that spin, so wheelspin, lock-up and engine
/// braking fall out of the same equations instead of being special-cased.
///
/// ## Determinism
/// The solver contains no randomness, no wall-clock reads and no framework
/// calls. Given identical initial state, spec, terrain and input sequence it
/// produces identical output — the property that ghosts, replays and
/// server-side validation are built on.
///
/// ## Units
/// SI throughout: metres, seconds, kilograms, newtons, radians.
public struct BikePhysicsBody: Sendable {

    // MARK: - Constants

    private enum Constants {
        static let gravity: Double = -9.81
        static let airDensity: Double = 1.225
        /// Slip ratios are normalised against at least this speed, so the tyre
        /// model stays well-conditioned at a standstill.
        static let referenceSlipSpeed: Double = 2.5
        /// Drivetrain efficiency from crank to rear wheel.
        static let drivetrainEfficiency: Double = 0.92
        /// Minimum vertical component of the body's up-axis used when solving
        /// suspension length. Prevents a division blow-up near 90° of pitch.
        static let minimumUpProjection: Double = 0.35
        /// Fraction of travel after which the progressive bump stop engages.
        static let bumpStopThreshold: Double = 0.85
        /// Impact speed below which a badly angled landing is survivable.
        static let survivableImpactSpeed: Double = 4.0
        /// Pitch beyond which the bike is unrecoverable on the ground.
        static let maximumGroundedPitch: Double = 1.85
        /// Engine braking torque at the crank when the throttle is shut.
        static let engineBrakingTorque: Double = 7.5
    }

    // MARK: - Configuration

    public let spec: BikeSpec
    /// Global grip scale from weather. Applied on top of the surface material.
    public var environmentGrip: Double = 1.0

    // MARK: - Body state

    /// World position of the centre of mass, in metres.
    public private(set) var position: Vector2
    /// Linear velocity of the centre of mass, in m/s.
    public private(set) var velocity: Vector2 = .zero
    /// Chassis pitch in radians. Positive is nose-up.
    public private(set) var angle: Double = 0
    /// Pitch rate in rad/s.
    public private(set) var angularVelocity: Double = 0

    public private(set) var frontWheel = WheelState()
    public private(set) var rearWheel = WheelState()

    /// Throttle actually delivered by the engine, which lags rider demand.
    public private(set) var appliedThrottle: Double = 0
    /// Engine speed in RPM.
    public private(set) var engineRPM: Double = 0
    /// Smoothed rider body position, `-1` back to `+1` forward.
    public private(set) var riderShift: Double = 0

    public private(set) var isAirborne: Bool = false
    /// Seconds spent continuously airborne. Zero while in contact.
    public private(set) var airTime: Double = 0
    public private(set) var hasCrashed: Bool = false
    public private(set) var crashReason: CrashReason?
    /// Vertical speed at the moment of the most recent touchdown, m/s.
    public private(set) var lastLandingImpact: Double = 0
    /// Pitch error at the most recent touchdown, radians. Small is clean.
    public private(set) var lastLandingPitchError: Double = 0
    /// True only on the step where the bike touched down. Drives landing
    /// effects, camera kick and scoring without the presentation layer having
    /// to infer the event.
    public private(set) var didLandThisStep: Bool = false

    // MARK: - Init

    public init(spec: BikeSpec, position: Vector2, angle: Double = 0) {
        self.spec = spec
        self.position = position
        self.angle = angle
        self.engineRPM = spec.engine.idleRPM
    }

    /// Places the bike on the ground at `x` with the suspension pre-settled at
    /// static sag and the chassis aligned to the local slope, which is what a
    /// bike sitting on the start gate actually looks like.
    public mutating func settle(on terrain: Terrain, atX x: Double) {
        let slope = terrain.slopeAngle(at: x)
        angle = slope
        angularVelocity = 0
        velocity = .zero

        let sagFront = spec.frontSuspension.travel * spec.frontSuspension.preload
        let sagRear = spec.rearSuspension.travel * spec.rearSuspension.preload
        frontWheel.compression = sagFront
        rearWheel.compression = sagRear

        // Position the centre of mass so both wheels rest on the ground.
        let averageExtension = ((spec.frontSuspension.travel - sagFront)
                                + (spec.rearSuspension.travel - sagRear)) * 0.5
        let averageRadius = (spec.frontWheelRadius + spec.rearWheelRadius) * 0.5
        let comHeightAboveAxleMount = spec.centerOfMassOffset.y - spec.axleHeight
        position = Vector2(x, terrain.height(at: x)
                           + averageRadius
                           + averageExtension
                           + comHeightAboveAxleMount)

        isAirborne = false
        airTime = 0
        hasCrashed = false
        crashReason = nil
        appliedThrottle = 0
        engineRPM = spec.engine.idleRPM
        riderShift = 0
        frontWheel.spinVelocity = 0
        rearWheel.spinVelocity = 0
        updateWheelKinematics(terrain: terrain)
    }

    // MARK: - Derived quantities

    /// Unit vector along the chassis, pointing forward.
    public var forwardAxis: Vector2 { Vector2.angled(angle) }
    /// Unit vector perpendicular to the chassis, pointing up.
    public var upAxis: Vector2 { Vector2.angled(angle + .pi / 2) }
    /// Forward ground speed in m/s.
    public var forwardSpeed: Double { velocity.dot(forwardAxis) }
    /// Speed magnitude in m/s.
    public var speed: Double { velocity.length }
    public var speedKPH: Double { speed * 3.6 }

    /// Total mass, including the rider.
    public var mass: Double { spec.totalMass }

    /// Whether either tyre is touching the ground.
    public var hasGroundContact: Bool { frontWheel.isGrounded || rearWheel.isGrounded }

    /// True when the front wheel is up and the rear is driving.
    public var isWheelieing: Bool {
        rearWheel.isGrounded && !frontWheel.isGrounded && angle > 0.12
    }

    /// True when the rear wheel is up over the front — a stoppie.
    public var isEndoing: Bool {
        frontWheel.isGrounded && !rearWheel.isGrounded && angle < -0.12
    }

    // MARK: - Simulation

    /// Advances the simulation by exactly `dt` seconds.
    ///
    /// - Parameters:
    ///   - dt: Fixed timestep, in seconds. Callers must supply the same value
    ///     every step; the solver's stability guarantees assume it.
    ///   - input: Rider controls for this step.
    ///   - terrain: The ground being ridden.
    public mutating func step(dt: Double, input: RiderInput, terrain: Terrain) {
        guard dt > 0, dt.isFinite else { return }
        let controls = hasCrashed ? .neutral : input.sanitised

        didLandThisStep = false

        updateRiderShift(controls.lean, dt: dt)
        updateThrottle(demand: controls.throttle, dt: dt)

        var force = Vector2(0, Constants.gravity * mass)
        var torque: Double = 0

        applySuspensionAndTyres(dt: dt,
                                controls: controls,
                                terrain: terrain,
                                force: &force,
                                torque: &torque)

        applyAerodynamics(into: &force)
        applyAirControl(controls: controls, dt: dt, into: &torque)

        integrate(force: force, torque: torque, dt: dt)
        updateAirborneState(dt: dt, terrain: terrain)
        resolveChassisCollision(terrain: terrain)
        updateEngineSpeed()
        updateWheelKinematics(terrain: terrain)
    }

    // MARK: - Rider and engine

    /// The rider's body cannot teleport; it is a mass that has to be moved.
    /// Smoothing the shift is what gives weight transfer its characteristic
    /// delay and makes pre-loading a jump a timing skill.
    private mutating func updateRiderShift(_ demand: Double, dt: Double) {
        let responseRate = 7.5
        riderShift = MathUtils.damp(riderShift, demand, rate: responseRate, dt: dt)
    }

    private mutating func updateThrottle(demand: Double, dt: Double) {
        appliedThrottle = MathUtils.damp(appliedThrottle, demand,
                                         rate: spec.engine.throttleResponse, dt: dt)
    }

    private mutating func updateEngineSpeed() {
        // Direct drive: no clutch is modelled, so engine speed follows the rear
        // wheel through the overall ratio. In the air the wheel is free, which
        // is exactly why an airborne throttle blip spins the wheel up fast.
        let wheelRPM = rearWheel.spinVelocity * spec.engine.overallGearRatio * 60 / (2 * .pi)
        engineRPM = MathUtils.clamp(abs(wheelRPM),
                                    spec.engine.idleRPM,
                                    spec.engine.redlineRPM)
    }

    /// Centre of mass in world space, including the rider's fore/aft shift.
    private var shiftedCenterOfMass: Vector2 {
        position + forwardAxis * (riderShift * spec.riderShiftRange * riderMassFraction)
    }

    /// How much of the total mass the rider represents. Shifting the rider
    /// moves the combined centre of mass by this fraction of the shift distance.
    private var riderMassFraction: Double { spec.riderMass / mass }

    // MARK: - Suspension and tyres

    private mutating func applySuspensionAndTyres(dt: Double,
                                                  controls: RiderInput,
                                                  terrain: Terrain,
                                                  force: inout Vector2,
                                                  torque: inout Double) {
        // Each wheel is solved on a local copy and written back. Passing
        // `&self.rearWheel` into a method that also reads `self` would be an
        // exclusivity violation; working on a copy is both legal and clearer
        // about the fact that a wheel solve reads the whole body's state.
        var rear = rearWheel
        let rearTouchdown = solveWheel(&rear,
                                       isDriven: true,
                                       suspension: spec.rearSuspension,
                                       radius: spec.rearWheelRadius,
                                       mountLocalX: -spec.wheelbase / 2,
                                       brakeInput: controls.rearBrake,
                                       brakeTorque: spec.rearBrakeTorque,
                                       dt: dt,
                                       terrain: terrain,
                                       force: &force,
                                       torque: &torque)
        rearWheel = rear

        var front = frontWheel
        let frontTouchdown = solveWheel(&front,
                                        isDriven: false,
                                        suspension: spec.frontSuspension,
                                        radius: spec.frontWheelRadius,
                                        mountLocalX: spec.wheelbase / 2,
                                        brakeInput: controls.frontBrake,
                                        brakeTorque: spec.frontBrakeTorque,
                                        dt: dt,
                                        terrain: terrain,
                                        force: &force,
                                        torque: &torque)
        frontWheel = front

        // The first wheel to touch down defines the landing, so the rear is
        // evaluated first — which is also the order a rider wants to land in.
        if let contactX = rearTouchdown ?? frontTouchdown {
            registerTouchdown(terrain: terrain, at: contactX)
        }
    }

    /// Resolves one wheel: suspension geometry, spring/damper force, tyre
    /// longitudinal force and the wheel's own spin dynamics.
    ///
    /// - Returns: The world x at which the tyre touched down this step, or
    ///   `nil` if it did not transition from airborne to grounded.
    private func solveWheel(_ wheel: inout WheelState,
                            isDriven: Bool,
                            suspension: SuspensionSpec,
                            radius: Double,
                            mountLocalX: Double,
                            brakeInput: Double,
                            brakeTorque: Double,
                            dt: Double,
                            terrain: Terrain,
                            force: inout Vector2,
                            torque: inout Double) -> Double? {
        let up = upAxis
        let com = shiftedCenterOfMass
        let mount = mountPoint(localX: mountLocalX, com: com)

        // --- Suspension geometry -------------------------------------------
        // Solve for the compression that puts the tyre exactly on the ground,
        // then clamp it into the unit's legal stroke. Resolving the constraint
        // kinematically (rather than integrating a free wheel mass) is what
        // keeps the suspension stable at large timestep-to-stiffness ratios.
        let upProjection = max(up.y, Constants.minimumUpProjection)
        let probeX = mount.x - up.x * (suspension.travel * 0.5)
        let groundY = terrain.height(at: probeX)
        let targetCompression = suspension.travel - (mount.y - groundY - radius) / upProjection

        let previousCompression = wheel.compression
        let wasGrounded = wheel.isGrounded

        if targetCompression <= 0 {
            // Airborne: the spring extends at a rate the rebound damping allows,
            // rather than snapping straight, so the wheel visibly drops away.
            let reboundRate = suspension.travel * 3.5
            wheel.compression = max(0, previousCompression - reboundRate * dt)
            wheel.isGrounded = false
            wheel.normalLoad = 0
            wheel.isBottomedOut = false
        } else {
            wheel.compression = min(targetCompression, suspension.travel)
            wheel.isGrounded = true
            wheel.isBottomedOut = wheel.compression >= suspension.travel * 0.999
        }
        wheel.compressionVelocity = (wheel.compression - previousCompression) / dt

        wheel.center = mount - up * (suspension.travel - wheel.compression)
        wheel.surface = terrain.surface(at: wheel.center.x)

        // --- Spring and damper ---------------------------------------------
        var suspensionForce: Double = 0
        if wheel.isGrounded {
            let preloadOffset = suspension.travel * suspension.preload
            var springForce = suspension.stiffness * (wheel.compression + preloadOffset)

            // Progressive bump stop over the last of the stroke. This is what
            // turns a bottom-out into a firm thud instead of a rigid collision.
            let bumpStopStart = suspension.travel * Constants.bumpStopThreshold
            if wheel.compression > bumpStopStart {
                let overTravel = wheel.compression - bumpStopStart
                springForce += suspension.bumpStopStiffness * overTravel * overTravel
                    / max(suspension.travel - bumpStopStart, 1e-4)
            }

            // Damping is asymmetric: a real damper resists extension harder than
            // compression, which is what stops the bike bucking after an impact.
            let dampingCoefficient = wheel.compressionVelocity > 0
                ? suspension.compressionDamping
                : suspension.reboundDamping
            let dampingForce = dampingCoefficient * wheel.compressionVelocity

            // A suspension unit can push but never pull.
            suspensionForce = max(0, springForce + dampingForce)
        }
        wheel.normalLoad = suspensionForce

        if suspensionForce > 0 {
            let vector = up * suspensionForce
            force += vector
            torque += (wheel.center - com).cross(vector)
        }

        // --- Tyre longitudinal force ---------------------------------------
        let surfaceProperties = wheel.surface.properties
        let peakGrip = surfaceProperties.grip * spec.tyreGripMultiplier * environmentGrip
        let frictionLimit = peakGrip * suspensionForce

        let tangent = terrain.tangent(at: wheel.center.x)
        let contactArm = wheel.center - com
        let contactVelocity = velocity + Vector2(-contactArm.y, contactArm.x) * angularVelocity
        let groundSpeed = contactVelocity.dot(tangent)
        let tyreSpeed = wheel.spinVelocity * radius

        var tyreForce: Double = 0
        if wheel.isGrounded && frictionLimit > 0 {
            let normalisation = max(abs(groundSpeed), Constants.referenceSlipSpeed)
            let slip = (tyreSpeed - groundSpeed) / normalisation
            wheel.slipRatio = slip
            // Linear in slip up to the friction circle, then saturated. The
            // saturation is what makes traction loss progressive: the force
            // stops rising but never collapses to zero.
            tyreForce = MathUtils.clamp(spec.tyreStiffness * slip, -frictionLimit, frictionLimit)
            wheel.gripUtilisation = MathUtils.clamp01(abs(tyreForce) / frictionLimit)

            let vector = tangent * tyreForce
            force += vector
            torque += contactArm.cross(vector)

            // Rolling resistance always opposes motion.
            let rolling = surfaceProperties.rollingResistance * suspensionForce
            let resistance = tangent * (-rolling * sign(groundSpeed))
            force += resistance
            torque += contactArm.cross(resistance)
        } else {
            wheel.slipRatio = 0
            wheel.gripUtilisation = 0
        }

        // --- Wheel spin dynamics -------------------------------------------
        var spinTorque: Double = 0
        if isDriven {
            spinTorque += driveTorque(wheelSpinVelocity: wheel.spinVelocity)
        }
        // Tyre force reacts back on the wheel, slowing a spinning tyre down.
        spinTorque -= tyreForce * radius

        wheel.spinVelocity += spinTorque / spec.wheelInertia * dt

        // Brakes are applied as a velocity-limited torque so they can bring the
        // wheel to a stop but never drag it backwards within a single step.
        if brakeInput > 0 {
            let demand = brakeTorque * brakeInput
            let stoppingTorque = abs(wheel.spinVelocity) * spec.wheelInertia / dt
            let applied = min(demand, stoppingTorque)
            wheel.spinVelocity -= sign(wheel.spinVelocity) * applied / spec.wheelInertia * dt
        }

        wheel.spinAngle += wheel.spinVelocity * dt
        wheel.contactPoint = Vector2(wheel.center.x, terrain.height(at: wheel.center.x))

        return (wheel.isGrounded && !wasGrounded) ? wheel.center.x : nil
    }

    /// Torque delivered to the rear wheel, including engine braking.
    ///
    /// - Parameter wheelSpinVelocity: Current rear wheel speed, passed in
    ///   rather than read from `self` so the value is the one being solved.
    private func driveTorque(wheelSpinVelocity: Double) -> Double {
        let curve = spec.engine.torqueFraction(atRPM: engineRPM)
        let crankTorque = spec.engine.peakTorque * curve * appliedThrottle
        // With the throttle shut a running engine drags on the drivetrain.
        let braking = (1 - appliedThrottle) * Constants.engineBrakingTorque
            * MathUtils.clamp01(engineRPM / max(spec.engine.peakTorqueRPM, 1))
        let net = crankTorque - braking * sign(wheelSpinVelocity)
        return net * spec.engine.overallGearRatio * Constants.drivetrainEfficiency
    }

    private func mountPoint(localX: Double, com: Vector2) -> Vector2 {
        // Axle mounts are defined relative to the chassis origin; convert to an
        // offset from the (rider-shifted) centre of mass, then rotate into world.
        let local = Vector2(localX - spec.centerOfMassOffset.x,
                            spec.axleHeight - spec.centerOfMassOffset.y)
        return com + local.rotated(by: angle)
    }

    // MARK: - Aerodynamics and air control

    private func applyAerodynamics(into force: inout Vector2) {
        let v = velocity
        let speed = v.length
        guard speed > 0.1 else { return }
        let magnitude = 0.5 * Constants.airDensity * spec.dragArea * speed * speed
        force += -v.normalized * magnitude
    }

    /// In the air the rider steers the bike's rotation with their body, the
    /// throttle and the rear brake — the three tools a real rider uses.
    private mutating func applyAirControl(controls: RiderInput, dt: Double, into torque: inout Double) {
        guard !hasGroundContact, !hasCrashed else { return }

        // Body position: leaning forward pitches the nose down.
        torque -= controls.lean * spec.airRotationTorque

        // Throttle spins the rear wheel up; conservation of angular momentum
        // pitches the chassis nose-up in reaction.
        torque += driveTorque(wheelSpinVelocity: rearWheel.spinVelocity) * 0.55

        // Braking the spinning rear wheel does the opposite, dropping the nose.
        // This is the classic mid-air correction, and it costs wheel speed on
        // landing — a genuine trade-off rather than a free ability.
        torque -= controls.rearBrake * spec.rearBrakeTorque * 0.45

        // Rotation bleeds off so the bike does not spin indefinitely.
        torque -= angularVelocity * spec.airRotationDamping * spec.momentOfInertia
    }

    // MARK: - Integration

    private mutating func integrate(force: Vector2, torque: Double, dt: Double) {
        // Semi-implicit Euler: velocity first, then position. It is one order
        // cheaper than RK4 and, unlike explicit Euler, does not inject energy
        // into spring systems — the property that matters most here.
        velocity += force / mass * dt
        angularVelocity += torque / spec.momentOfInertia * dt

        // Guard against a pathological state — a corrupt replay, an extreme
        // upgrade combination — turning into NaNs that would poison the session.
        guard velocity.x.isFinite, velocity.y.isFinite, angularVelocity.isFinite else {
            velocity = .zero
            angularVelocity = 0
            return
        }

        position += velocity * dt
        angle = MathUtils.wrapAngle(angle + angularVelocity * dt)
    }

    // MARK: - Events

    private mutating func updateAirborneState(dt: Double, terrain: Terrain) {
        let airborne = !hasGroundContact
        if airborne {
            airTime += dt
            isAirborne = true
        } else {
            isAirborne = false
            airTime = 0
        }

        // Looping out or nosing in while on the ground is a crash regardless of
        // how the bike got there.
        if !airborne && !hasCrashed && abs(angle) > Constants.maximumGroundedPitch {
            crash(angle > 0 ? .loopedOut : .nosedIn)
        }
    }

    /// Evaluates a touchdown. A landing is judged on two things: how hard the
    /// bike hit, and how well its angle matched the ground it hit.
    private mutating func registerTouchdown(terrain: Terrain, at x: Double) {
        guard airTime > 0.08 else { return }   // Ignore suspension chatter.
        didLandThisStep = true

        let surface = terrain.surface(at: x)
        let slope = terrain.slopeAngle(at: x)
        let pitchError = abs(MathUtils.angleDelta(from: slope, to: angle))
        let impact = max(0, -velocity.dot(terrain.normal(at: x)))

        lastLandingImpact = impact
        lastLandingPitchError = pitchError

        let forgiveness = spec.landingForgiveness * surface.properties.landingForgiveness
        guard impact > Constants.survivableImpactSpeed else { return }

        // The faster the impact, the less angular error the bike tolerates.
        let severity = MathUtils.remap(impact, Constants.survivableImpactSpeed, 16, 1.0, 0.45)
        if pitchError > forgiveness / severity {
            crash(angle < slope ? .nosedIn : .caseFromLanding)
        }
    }

    /// Stops the chassis passing through the ground when the suspension has run
    /// out of answers — a huge flat landing, or riding into a jump face.
    private mutating func resolveChassisCollision(terrain: Terrain) {
        let clearance = 0.30   // Underside of the chassis below the CoM, metres.
        let groundY = terrain.height(at: position.x)
        let penetration = (groundY + clearance) - position.y
        guard penetration > 0 else { return }

        position.y += penetration
        let normal = terrain.normal(at: position.x)
        let normalSpeed = velocity.dot(normal)
        if normalSpeed < 0 {
            // Inelastic: the frame does not bounce, it absorbs.
            velocity -= normal * normalSpeed
            if normalSpeed < -6 { crash(.chassisImpact) }
        }
        angularVelocity *= 0.4
    }

    private mutating func crash(_ reason: CrashReason) {
        guard !hasCrashed else { return }
        hasCrashed = true
        crashReason = reason
        // The rider is no longer holding the bike up: kill drive and let it
        // tumble under gravity and friction alone.
        appliedThrottle = 0
        angularVelocity += sign(velocity.x) * 2.5
    }

    private mutating func updateWheelKinematics(terrain: Terrain) {
        frontWheel.contactPoint = Vector2(frontWheel.center.x, terrain.height(at: frontWheel.center.x))
        rearWheel.contactPoint = Vector2(rearWheel.center.x, terrain.height(at: rearWheel.center.x))
    }

    private func sign(_ value: Double) -> Double {
        value > 0 ? 1 : (value < 0 ? -1 : 0)
    }

    // MARK: - External control

    /// Restores the bike to a rideable state on the ground, after a crash or a
    /// player-requested reset.
    public mutating func recover(on terrain: Terrain, atX x: Double, carryingSpeed speed: Double = 0) {
        settle(on: terrain, atX: x)
        let tangent = terrain.tangent(at: x)
        velocity = tangent * speed
        rearWheel.spinVelocity = speed / spec.rearWheelRadius
        frontWheel.spinVelocity = speed / spec.frontWheelRadius
        updateEngineSpeed()
    }

    /// Moves the body without disturbing its dynamics.
    ///
    /// Used only for the lap wrap, where the rider's momentum, attitude and
    /// suspension state must survive the seam exactly — anything else would
    /// hand out or take away speed at the start/finish line.
    public mutating func translate(by offset: Vector2) {
        position += offset
        frontWheel.center += offset
        rearWheel.center += offset
        frontWheel.contactPoint += offset
        rearWheel.contactPoint += offset
    }

    /// Applies a launch impulse at the start of a race.
    public mutating func applyStartImpulse(_ impulse: Vector2) {
        velocity += impulse / mass
    }
}
