import Foundation

/// Racing AI. Drives the same physics through the same input struct as the
/// player — no extra grip, no rubber banding. Difficulty comes from how well
/// it reads the track and how often it makes mistakes.
final class AIController {
    let bike: Bike
    let personality: AIPersonality
    let skill: Double

    private var reaction: Double = 0
    private var mistakeKind: String?
    private var mistakeTime: Double = 0
    private var mistakeCooldown: Double = 0
    private var cached = RiderInput()

    init(bike: Bike, personality: AIPersonality, difficulty: Double) {
        self.bike = bike
        self.personality = personality
        self.skill = clampd(personality.skill * (0.65 + difficulty * 0.45), 0.3, 1.0)
    }

    /// Ballistic projection for where and on what slope we will touch down.
    private func predictLanding(_ track: Track) -> (x: Double, slope: Double, t: Double)? {
        var px = bike.x, py = bike.y
        var pvx = bike.vx, pvy = bike.vy
        let dt = 0.05
        for i in 0..<90 {
            pvy -= GRAV * dt
            px += pvx * dt
            py += pvy * dt
            if py <= track.height(at: px) + bike.wheelR + 0.3 {
                return (px, track.slope(at: px), Double(i) * dt)
            }
        }
        return nil
    }

    func update(dt: Double, track: Track) -> RiderInput {
        reaction -= dt
        if reaction > 0 { return cached }
        reaction = (1 - skill) * 0.16 + 0.02

        mistakeCooldown -= dt
        if mistakeKind == nil && mistakeCooldown <= 0 && Double.random(in: 0...1) < personality.mistake {
            mistakeKind = ["chop", "grab", "overlean", "late"].randomElement()
            mistakeTime = Double.random(in: 0.25...0.95)
            mistakeCooldown = 2.5
        }
        if mistakeKind != nil {
            mistakeTime -= dt
            if mistakeTime <= 0 { mistakeKind = nil }
        }

        if bike.crashed {
            cached = RiderInput()
            return cached
        }

        var throttle: Double = 0
        var brake: Double = 0
        var lean: Double = 0
        var whip: Double = 0
        let speed = max(0, bike.forwardSpeed)

        if bike.airborne {
            if let land = predictLanding(track) {
                let targetAng = atan(land.slope)
                let err = wrapAngle(targetAng - bike.ang)
                lean = clampd(-err * (2.2 + skill * 2.0) - bike.angVel * 0.28, -1, 1)
                throttle = err < -0.25 ? 0.15 : 0.55 + skill * 0.4
                if bike.airTime > 0.35 && land.t > 0.55 && personality.risk > 0.5 {
                    whip = clampd((personality.risk - 0.4) * (skill > 0.75 ? 1 : 0.4), -1, 1)
                } else if land.t < 0.5 {
                    whip = clampd(-bike.whip * 3, -1, 1)
                }
            } else {
                lean = clampd(-bike.angVel * 0.3, -1, 1)
                throttle = 0.6
            }
        } else {
            var steepUp: Double = 0
            var steepDown: Double = 0
            var roughness: Double = 0
            let ahead = 6 + speed * 0.9
            var prev = track.height(at: bike.x)
            var d: Double = 1
            while d < ahead {
                let h = track.height(at: bike.x + d)
                let s = (h - prev) / 1.5
                prev = h
                let w = 1 - d / ahead
                if s > 0.25 { steepUp = max(steepUp, s * w) }
                if s < -0.25 { steepDown = max(steepDown, -s * w) }
                roughness += abs(s) * w
                d += 1.5
            }

            throttle = 0.55 + skill * 0.45
            if let f = track.feature(at: bike.x + 4), f.risk > 0.6,
               personality.risk < f.risk, speed > 14 {
                throttle *= 0.7
                brake = 0.25 * (1 - personality.risk)
            }
            if roughness > 3.2 && skill < 0.85 { throttle *= 0.85 }

            if steepUp > 0.2 { lean = -0.5 - skill * 0.35 }
            else if steepDown > 0.25 { lean = 0.35 + skill * 0.3 }
            else { lean = clampd(-bike.angVel * 0.25 + (bike.wheelieTime > 0.35 ? 0.55 : 0), -1, 1) }

            if bike.wheelieTime > 0.5 { throttle *= 0.6; lean = 0.8 }
            if speed > bike.topSpeed * (0.85 + personality.aggression * 0.15) && roughness > 2.5 {
                brake = 0.2
            }
        }

        if let m = mistakeKind {
            switch m {
            case "chop": throttle *= 0.15
            case "grab": brake = 0.8; throttle = 0
            case "overlean": lean = clampd(lean + (Bool.random() ? -1.2 : 1.2), -1, 1)
            default: reaction = 0.25
            }
        }

        cached = RiderInput(throttle: clampd(throttle, 0, 1),
                            brake: clampd(brake, 0, 1),
                            lean: clampd(lean, -1, 1),
                            whip: clampd(whip, -1, 1))
        return cached
    }
}
