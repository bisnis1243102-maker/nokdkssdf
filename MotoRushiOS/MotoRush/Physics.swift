import Foundation

// Bike physics — a Swift port of the same model the browser build uses.
//
// A rigid chassis carries two raycast suspension units. Each casts from its
// chassis anchor along the chassis-down axis, finds the terrain, and applies a
// spring/damper normal force plus a friction-limited longitudinal tyre force
// at the contact patch. Rider weight transfer moves the centre of mass, which
// is what actually produces wheelies, stoppies and nose-dive.
//
// Units: metres, kilograms, seconds. +Y is up.

let GRAV: Double = 9.81
// Bounds that keep the suspension solver from injecting energy. Neither binds
// during normal riding; they only cut off the numerical blow-ups.
let SHAFT_V_MAX: Double = 6    // m/s of shock shaft travel
let MAX_WHEEL_G: Double = 8    // peak normal force per wheel, in g

func wrapAngle(_ a: Double) -> Double {
    var v = a
    while v > .pi { v -= .pi * 2 }
    while v < -.pi { v += .pi * 2 }
    return v
}

struct RiderInput {
    var throttle: Double = 0
    var brake: Double = 0
    var lean: Double = 0
    var whip: Double = 0
}

struct Wheel {
    var ax: Double
    var ay: Double
    var len: Double
    var vel: Double = 0
    var grounded: Bool = false
    var load: Double = 0
    var spin: Double = 0
    var cx: Double = 0
    var cy: Double = 0
    var drive: Bool
}

enum BikeEvent {
    case landing(quality: String, x: Double, impact: Double, air: Double)
    case crash(reason: String, x: Double, speed: Double)
    case wheelspin(x: Double, y: Double)
}

struct RagdollPoint {
    var x: Double
    var y: Double
    var px: Double
    var py: Double
}

final class Bike {
    let spec: BikeSpec
    let track: Track
    var displayName: String
    var tintHex: String
    var number: Int = 21
    var isPlayer = false

    // Derived stats after upgrades.
    var mass: Double
    var power: Double
    var topSpeed: Double
    var brakeForce: Double
    var gripMul: Double
    var susDamp: Double
    var susStiff: Double

    let wheelR: Double = 0.33
    let wb: Double
    let inertia: Double
    let rest: Double

    var x: Double
    var y: Double
    var vx: Double = 0
    var vy: Double = 0
    var ang: Double
    var angVel: Double = 0

    var wheels: [Wheel]

    var lean: Double = 0
    var whip: Double = 0
    var whipVel: Double = 0
    var scrub: Double = 0

    var airborne = false
    var airTime: Double = 0
    var totalAirTime: Double = 0
    var groundTime: Double = 0
    var crashed = false
    var crashTimer: Double = 0
    var stuckTimer: Double = 0
    var ragdoll: [String: RagdollPoint] = [:]
    var ragdollLinks: [(String, String, Double)] = []

    var rpm: Double = 0.1
    var gear: Int = 1
    var wheelieTime: Double = 0
    var stoppieTime: Double = 0

    var finished = false
    var finishTime: Double = 0

    var perfects = 0
    var crashes = 0
    var whipDegrees: Double = 0
    var style: Double = 0
    var momentum: Double = 1

    var events: [BikeEvent] = []

    private var fx: Double = 0
    private var fy: Double = 0
    private var torque: Double = 0

    init(spec: BikeSpec, track: Track, upgrades: [String: Int] = [:],
         name: String = "Rider", tint: String? = nil) {
        self.spec = spec
        self.track = track
        self.displayName = name
        self.tintHex = tint ?? spec.color

        func lv(_ k: String) -> Double { Double(upgrades[k] ?? 0) }
        self.mass = spec.mass * (1 - 0.03 * lv("weight"))
        self.power = spec.power * (1 + 0.07 * lv("engine"))
        self.topSpeed = spec.topSpeed * (1 + 0.04 * lv("transmission"))
        self.brakeForce = spec.brake * (1 + 0.08 * lv("brakes"))
        self.gripMul = spec.grip * (1 + 0.05 * lv("tires"))
        self.susDamp = spec.susDamp * (1 + 0.06 * lv("suspension"))
        self.susStiff = spec.susStiff

        self.wb = spec.wheelbase
        self.inertia = self.mass * (spec.wheelbase * spec.wheelbase * 0.55 + 0.18)
        self.rest = 0.34 + spec.travel * 0.5

        self.x = track.startX
        self.y = track.height(at: track.startX) + 0.33 + spec.seatHeight
        self.ang = atan(track.slope(at: track.startX))

        self.wheels = [
            Wheel(ax: -spec.wheelbase * 0.5, ay: 0.02, len: 0.34 + spec.travel * 0.5, drive: true),
            Wheel(ax: spec.wheelbase * 0.5, ay: 0.02, len: 0.34 + spec.travel * 0.5, drive: false)
        ]
    }

    var speed: Double { (vx * vx + vy * vy).squareRoot() }
    var forwardSpeed: Double { vx * cos(ang) + vy * sin(ang) }

    func worldPoint(_ lx: Double, _ ly: Double) -> (Double, Double) {
        let c = cos(ang), s = sin(ang)
        return (x + lx * c - ly * s, y + lx * s + ly * c)
    }

    /// The height the tyre actually rides at over `px`.
    ///
    /// A tyre is not a point. Sampling the terrain at a single x lets the wheel
    /// drop into the notch between two whoops and then get slammed by the next
    /// face, which is where the solver was finding the energy to throw the bike
    /// twenty metres into the air. Taking the highest ground across the contact
    /// patch makes the wheel ride the crests, as a real front wheel does.
    private func groundUnder(_ px: Double) -> Double {
        let r = wheelR * 0.75
        return max(track.height(at: px - r),
                   max(track.height(at: px), track.height(at: px + r)))
    }

    private func applyForce(_ fxv: Double, _ fyv: Double, _ px: Double, _ py: Double) {
        fx += fxv; fy += fyv
        torque += (px - x) * fyv - (py - y) * fxv
    }

    func update(dt: Double, input: RiderInput) {
        if finished {
            step(dt: dt, input: RiderInput(throttle: 0, brake: 0.35, lean: 0, whip: 0))
            return
        }
        let sub = 4
        let h = dt / Double(sub)
        for _ in 0..<sub { step(dt: h, input: input) }
    }

    private func step(dt: Double, input: RiderInput) {
        fx = 0; fy = -mass * GRAV; torque = 0

        let throttle = crashed ? 0 : clampd(input.throttle, 0, 1)
        let brake = crashed ? 0.85 : clampd(input.brake, 0, 1)
        let leanIn = crashed ? 0 : clampd(input.lean, -1, 1)
        let whipIn = crashed ? 0 : clampd(input.whip, -1, 1)

        lean += (leanIn - lean) * clampd(dt * 9, 0, 1)
        let comShift = lean * 0.30

        let c = cos(ang), s = sin(ang)
        let downX = s, downY = -c
        var anyGround = false
        let maxLen = rest + spec.travel * 0.5

        for i in 0..<wheels.count {
            var w = wheels[i]
            let ax = x + w.ax * c - w.ay * s
            let ay = y + w.ax * s + w.ay * c

            // Raycast from the anchor along chassis-down for the surface.
            var hit: Double = -1
            let N = 12
            for j in 1...N {
                let t = maxLen * Double(j) / Double(N)
                let py = ay + downY * t
                let px = ax + downX * t
                if py - wheelR <= groundUnder(px) {
                    var lo = maxLen * Double(j - 1) / Double(N)
                    var hi = t
                    for _ in 0..<8 {
                        let m = (lo + hi) * 0.5
                        if (ay + downY * m) - wheelR <= groundUnder(ax + downX * m) { hi = m } else { lo = m }
                    }
                    hit = hi
                    break
                }
            }

            let prevLen = w.len
            if hit < 0 {
                w.len = min(maxLen, w.len + rest * 3 * dt)
                w.vel = 0
                w.grounded = false
                w.load = 0
                w.cx = ax + downX * w.len
                w.cy = ay + downY * w.len
                w.spin *= pow(0.6, dt)
                if w.drive { w.spin += (throttle * 40 - w.spin) * clampd(dt * 3, 0, 1) }
                wheels[i] = w
                continue
            }

            let wasGrounded = w.grounded
            anyGround = true
            w.grounded = true
            w.len = hit
            // Differencing the length is correct while the wheel stays planted,
            // but on the first frame of contact `prevLen` is the free-droop
            // length, so the difference is a fictitious hundred metres per
            // second of compression straight into the damper. On touchdown use
            // the chassis's actual closing speed along the suspension axis.
            let closing = -(vx * downX + vy * downY)
            w.vel = clampd(wasGrounded ? (w.len - prevLen) / dt : closing,
                           -SHAFT_V_MAX, SHAFT_V_MAX)
            w.cx = ax + downX * w.len
            w.cy = ay + downY * w.len

            let compression = clampd(rest - w.len, -spec.travel, spec.travel * 1.2)
            let bottomOut = compression > spec.travel * 0.95 ? (compression - spec.travel * 0.95) * 90000 : 0
            let damp = w.vel > 0 ? susDamp * 0.7 : susDamp * 1.25
            // Ceiling expressed in g rather than as a flat newton figure: 60 kN
            // on a ~100 kg bike is 60 g through one wheel, and a few substeps
            // of that is an ejection, not a landing.
            var normalF = clampd(susStiff * compression - damp * w.vel + bottomOut,
                                 0, mass * GRAV * MAX_WHEEL_G)
            w.load = normalF

            let bias = w.drive ? 1 - lean * 0.55 : 1 + lean * 0.55
            normalF *= clampd(bias, 0.15, 1.9)

            let slope = track.slope(at: w.cx)
            let tl = (1 + slope * slope).squareRoot()
            let tx = 1 / tl, ty = slope / tl

            // The spring force goes along the *ground's* normal, not the
            // chassis's own down-axis. Ground can only push away from itself.
            // Using the chassis axis meant that once the bike pitched past
            // vertical that axis was nearly horizontal, the ray fired into the
            // hillside ahead, and the spring catapulted a looped-out bike
            // backwards uphill.
            applyForce(-ty * normalF, tx * normalF, w.cx, w.cy)

            let rx = w.cx - x, ry = w.cy - y
            let pvx = vx - angVel * ry
            let pvy = vy + angVel * rx
            let vT = pvx * tx + pvy * ty

            let mu = gripMul * track.biome.grip
            // The friction circle uses a load capped at a sane multiple of
            // static weight: a single suspension spike must not hand the tyre
            // several g of grip for one frame.
            let maxTraction = mu * min(normalF, mass * GRAV * 1.6)

            var longF: Double = 0
            if w.drive {
                let sp = max(0, vT)
                let fade = clampd(1 - sp / topSpeed, 0, 1)
                let curve = pow(fade, 1 / spec.torqueCurve)
                let target = throttle * power * curve * momentum
                if target > maxTraction {
                    w.spin += (target - maxTraction) / (mass * 0.4) * dt
                    longF = maxTraction * 0.92
                    if throttle > 0.4 && sp > 1 {
                        events.append(.wheelspin(x: w.cx, y: w.cy))
                    }
                } else {
                    longF = target
                    w.spin += (vT / wheelR - w.spin) * clampd(dt * 12, 0, 1)
                }
            } else {
                w.spin += (vT / wheelR - w.spin) * clampd(dt * 14, 0, 1)
            }

            if brake > 0.01 {
                let bf = brakeForce * brake * (w.drive ? 0.45 : 1.0)
                longF -= (vT >= 0 ? 1.0 : -1.0) * min(bf, maxTraction)
            }

            let roll = normalF * 0.012 * track.biome.rollDrag + 0.32 * vT * abs(vT) / 2
            longF -= (vT > 0 ? 1.0 : (vT < 0 ? -1.0 : 0)) * abs(roll)

            longF = clampd(longF, -maxTraction, maxTraction)
            applyForce(tx * longF, ty * longF, w.cx, w.cy)
            wheels[i] = w
        }

        let wasAir = airborne
        airborne = !anyGround

        if airborne {
            airTime += dt
            totalAirTime += dt
            torque += -lean * 620 - angVel * 90
            whipVel += (whipIn * 7.0 - whipVel * 3.2) * dt * 6
            whip = clampd(whip + whipVel * dt, -1.5, 1.5)
            if abs(whipIn) < 0.05 {
                whip -= whip * clampd(dt * 2.2, 0, 1)
                whipVel *= pow(0.2, dt)
            }
            whipDegrees += abs(whipVel) * dt * (180 / .pi)
            if airTime < 0.45 {
                scrub = lerp(scrub, (1 - throttle) * max(0, lean) * -0.5, dt * 8)
            } else {
                scrub = lerp(scrub, 0, dt * 2)
            }
            fx -= vx * abs(vx) * 0.32
            fy -= vy * abs(vy) * 0.22
        } else {
            groundTime += dt
            if wasAir { onLanding() }
            airTime = 0
            whip -= whip * clampd(dt * 9, 0, 1)
            whipVel *= pow(0.01, dt)
            scrub = lerp(scrub, 0, dt * 6)
        }

        if !airborne {
            let shiftF = mass * GRAV * 0.55
            torque += -comShift * shiftF * cos(ang)
            // The rider's passive balance: a wheelie has to be provoked
            // rather than being the default state under power.
            let groundAng = atan(track.slope(at: x))
            torque -= wrapAngle(ang - groundAng) * mass * 4.5
            torque -= angVel * 26
        }

        vx += (fx / mass) * dt
        vy += (fy / mass) * dt
        angVel = clampd(angVel + (torque / inertia) * dt, -12, 12)
        x += vx * dt
        y += vy * dt
        ang = wrapAngle(ang + angVel * dt)

        let gh = track.height(at: x)
        if y < gh + 0.08 {
            y = gh + 0.08
            if vy < 0 { vy *= -0.05 }
            if !crashed && speed > 4 { registerCrash("chassis") }
        }

        let spd = max(0, forwardSpeed)
        let norm = clampd(spd / topSpeed, 0, 1.2)
        gear = spec.electric ? 1 : Int(clampd(1 + (norm * 4.2).rounded(.down), 1, 5))
        let gearBand = spec.electric ? norm : (norm * 4.2).truncatingRemainder(dividingBy: 1)
        let target = airborne ? clampd(0.15 + throttle * 0.95, 0, 1.1)
                              : clampd(0.12 + gearBand * 0.85 + throttle * 0.2, 0, 1.1)
        rpm += (target - rpm) * clampd(dt * 7, 0, 1)

        let rearDown = wheels[0].grounded, frontDown = wheels[1].grounded
        wheelieTime = (rearDown && !frontDown) ? wheelieTime + dt : 0
        stoppieTime = (frontDown && !rearDown && brake > 0.3) ? stoppieTime + dt : 0
        if wheelieTime > 0.6 { style += dt * 12 }
        if stoppieTime > 0.4 { style += dt * 10 }

        if !crashed {
            let groundAng = atan(track.slope(at: x))
            let rel = wrapAngle(ang - groundAng)
            if !airborne && abs(rel) > 1.6 && groundTime > 0.15 { registerCrash("pitch") }
            if abs(angVel) > 11 && airborne && airTime > 1.0 { registerCrash("tumble") }
        }

        if crashed {
            crashTimer += dt
            updateRagdoll(dt)
        }

        if !finished && !crashed && abs(forwardSpeed) < 1.2 { stuckTimer += dt }
        else if !crashed { stuckTimer = 0 }
        if stuckTimer > 2.5 { stuckTimer = 0; respawn() }

        momentum += (1 - momentum) * clampd(dt * 0.6, 0, 1)
    }

    private func onLanding() {
        let groundAng = atan(track.slope(at: x))
        let rel = wrapAngle(ang - groundAng)
        // Impact is closing speed along the surface normal, not raw vertical
        // speed: touching down on a steep face at a matched angle is fine.
        let nx = -sin(groundAng), ny = cos(groundAng)
        let impact = max(0, -(vx * nx + vy * ny))
        let crossed = abs(whip)
        let air = airTime

        let hardCrash = impact > 16 || (abs(rel) > 1.45 && impact > 7) || (crossed > 1.3 && impact > 10)
        if hardCrash && air > 0.25 {
            registerCrash("landing")
            return
        }
        guard air > 0.22 else { return }

        let angleScore = clampd(1 - abs(rel) / 0.55, 0, 1)
        let whipScore = clampd(1 - crossed / 0.7, 0, 1)
        let impactScore = clampd(1 - max(0, impact - 4) / 10, 0, 1)
        let quality = angleScore * 0.5 + whipScore * 0.2 + impactScore * 0.3

        if quality > 0.86 {
            perfects += 1
            momentum = 1.14
            vx *= 1.03
            style += 40 + air * 25
            events.append(.landing(quality: "perfect", x: x, impact: impact, air: air))
        } else if quality > 0.55 {
            momentum = 1.0
            vx *= lerp(0.93, 1.0, (quality - 0.55) / 0.31)
            style += 12
            events.append(.landing(quality: "good", x: x, impact: impact, air: air))
        } else {
            momentum = 0.86
            vx *= lerp(0.62, 0.9, quality / 0.55)
            angVel *= 0.4
            events.append(.landing(quality: "bad", x: x, impact: impact, air: air))
        }

        if impact > 9 {
            track.deform(at: x, depth: min(0.09, (impact - 9) * 0.006))
        }
    }

    func registerCrash(_ reason: String) {
        guard !crashed else { return }
        crashed = true
        crashes += 1
        crashTimer = 0
        momentum = 0.8
        style = max(0, style - 60)
        spawnRagdoll()
        events.append(.crash(reason: reason, x: x, speed: speed))
    }

    private func spawnRagdoll() {
        func p(_ lx: Double, _ ly: Double) -> RagdollPoint {
            let w = worldPoint(lx, ly)
            return RagdollPoint(x: w.0, y: w.1, px: w.0 - vx * 0.016, py: w.1 - vy * 0.016)
        }
        ragdoll = [
            "head": p(0.05, 1.05), "chest": p(0.02, 0.72), "hip": p(-0.05, 0.38),
            "hand": p(0.42, 0.85), "footR": p(-0.2, 0.05), "footF": p(0.18, 0.05)
        ]
        func link(_ a: String, _ b: String) -> (String, String, Double) {
            let pa = ragdoll[a]!, pb = ragdoll[b]!
            return (a, b, ((pa.x - pb.x) * (pa.x - pb.x) + (pa.y - pb.y) * (pa.y - pb.y)).squareRoot())
        }
        ragdollLinks = [link("head", "chest"), link("chest", "hip"), link("chest", "hand"),
                        link("hip", "footR"), link("hip", "footF"), link("head", "hip")]
    }

    private func updateRagdoll(_ dt: Double) {
        guard !ragdoll.isEmpty else { return }
        for k in ragdoll.keys {
            guard var p = ragdoll[k] else { continue }
            let vxp = (p.x - p.px) * 0.985
            let vyp = (p.y - p.py) * 0.985
            p.px = p.x; p.py = p.y
            p.x += vxp
            p.y += vyp - GRAV * dt * dt
            let g = track.height(at: p.x) + 0.08
            if p.y < g {
                p.y = g
                p.px = p.x + (p.x - p.px) * 0.4
            }
            ragdoll[k] = p
        }
        for _ in 0..<4 {
            for (ka, kb, len) in ragdollLinks {
                guard var a = ragdoll[ka], var b = ragdoll[kb] else { continue }
                let dx = b.x - a.x, dy = b.y - a.y
                let d = max(1e-4, (dx * dx + dy * dy).squareRoot())
                let diff = (d - len) / d * 0.5
                a.x += dx * diff; a.y += dy * diff
                b.x -= dx * diff; b.y -= dy * diff
                ragdoll[ka] = a; ragdoll[kb] = b
            }
        }
    }

    func respawn() {
        let back = max(track.startX, x - 10)
        x = back
        y = track.height(at: back) + wheelR + spec.seatHeight + 0.2
        vx = max(4, forwardSpeed * 0.35)
        vy = 0
        ang = atan(track.slope(at: back))
        angVel = 0
        whip = 0; whipVel = 0; lean = 0
        crashed = false
        crashTimer = 0
        ragdoll = [:]
        momentum = 0.9
        for i in 0..<wheels.count { wheels[i].len = rest; wheels[i].vel = 0 }
    }
}
