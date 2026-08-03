import Foundation
import UIKit

// The race simulation, with no rendering in it: field management, AI, ghost
// playback, scoring and finish detection. The SceneKit layer reads this every
// frame and moves nodes to match.

final class RaceHUD: ObservableObject {
    @Published var speedKmh: Int = 0
    @Published var gear: Int = 1
    @Published var position: Int = 1
    @Published var fieldSize: Int = 6
    @Published var time: Double = 0
    @Published var progress: Double = 0
    @Published var style: Int = 0
    @Published var countdown: Int = 3
    @Published var racing = false
    @Published var message: String = ""
    @Published var messageKind: String = ""
    @Published var standings: [(String, Bool)] = []
    @Published var finished = false
    /// Gap to the ghost in seconds: positive means the player is ahead.
    @Published var ghostGap: Double = 0
    @Published var hasGhost = false
}

/// Everything the SwiftUI layer needs once the player crosses the line.
struct RaceOutcome {
    var position: Int
    var time: Double
    var perfects: Int
    var crashes: Int
    var airTime: Double
    var style: Int
    var beatGhost: Bool
    var ghost: [GhostFrame]
    var order: [(String, Double)]
}

final class RaceControls {
    var throttle: Double = 0
    var brake: Double = 0
    var lean: Double = 0
    var whip: Double = 0

    var asInput: RiderInput {
        RiderInput(throttle: throttle, brake: brake, lean: lean, whip: whip)
    }
}

/// Visual events the renderer turns into particles, shake and sound.
enum RaceEffect {
    case dust(x: Double, y: Double, power: Double)
    case impact(x: Double, y: Double, power: Double)
    case shake(Double)
}

final class RaceEngine {
    let track: Track
    let playerSpec: BikeSpec
    private(set) var player: Bike!
    private(set) var field: [Bike] = []
    private var ais: [AIController] = []

    var hud: RaceHUD
    var controls = RaceControls()
    var assistLanding = false
    var onFinish: ((RaceOutcome) -> Void)?
    /// Drained by the renderer each frame.
    private(set) var effects: [RaceEffect] = []

    private(set) var state = "countdown"
    private var countdown: Double = 3.4
    private(set) var raceTime: Double = 0
    private var messageTimer: Double = 0
    private var finishReported = false

    // Ghost playback and this run's recording.
    let ghostFrames: [GhostFrame]?
    private(set) var ghostPose: GhostFrame?
    private var recording: [GhostFrame] = []
    private var recordTimer: Double = 0

    init(track: Track,
         playerSpec: BikeSpec,
         upgrades: [String: Int],
         playerName: String,
         playerNumber: Int,
         difficulty: Double,
         aiCount: Int,
         ghost: [GhostFrame]?,
         hud: RaceHUD) {
        self.track = track
        self.playerSpec = playerSpec
        self.ghostFrames = ghost
        self.hud = hud

        player = Bike(spec: playerSpec, track: track, upgrades: upgrades,
                      name: playerName, tint: playerSpec.color)
        player.isPlayer = true
        player.number = playerNumber
        field = [player]

        var names = riderNames.shuffled()
        for i in 0..<aiCount {
            let personality = AIPersonality.all[min(AIPersonality.all.count - 1,
                                                    Int(difficulty * Double(AIPersonality.all.count - 1)) + (i % 2))]
            let pool = BikeSpec.all.filter { $0.cls == playerSpec.cls }
            let spec = (pool.isEmpty ? BikeSpec.all : pool).randomElement() ?? BikeSpec.all[0]
            let hue = Double((i * 61 + 20) % 360) / 360
            let tint = UIColor(hue: CGFloat(hue), saturation: 0.7, brightness: 0.9, alpha: 1).hexString
            let name = names.isEmpty ? "Rider \(i)" : names.removeFirst()
            let bike = Bike(spec: spec, track: track, name: name, tint: tint)
            bike.number = 10 + i * 7
            // Staggered behind the line, like a real gate.
            bike.x = track.startX - 1.6 - Double(i) * 1.1
            bike.y = track.height(at: bike.x) + bike.wheelR + spec.seatHeight
            field.append(bike)
            ais.append(AIController(bike: bike, personality: personality, difficulty: difficulty))
        }

        hud.fieldSize = field.count
        hud.hasGhost = ghost != nil
        hud.countdown = 3
        if let g = ghost, let first = g.first { ghostPose = first }
    }

    var gateDropped: Bool { state != "countdown" }

    func drainEffects() -> [RaceEffect] {
        let out = effects
        effects.removeAll(keepingCapacity: true)
        return out
    }

    // MARK: - Step

    func update(_ dtIn: Double) {
        let dt = min(dtIn, 1.0 / 30.0)
        guard dt > 0 else { return }

        switch state {
        case "countdown":
            countdown -= dt
            hud.countdown = max(0, Int(ceil(countdown)))
            let held = RiderInput(throttle: controls.throttle * 0.25, brake: 1, lean: 0, whip: 0)
            for bike in field {
                bike.update(dt: dt, input: bike === player ? held
                            : RiderInput(throttle: 0, brake: 1, lean: 0, whip: 0))
            }
            if countdown <= 0 {
                state = "racing"
                hud.racing = true
                hud.countdown = 0
                show("GO!", kind: "big")
            }
        case "racing", "finished":
            raceTime += dt
            var input = controls.asInput
            if assistLanding && player.airborne { input = landingAssist(input) }
            player.update(dt: dt, input: player.finished
                          ? RiderInput(throttle: 0, brake: 0.4, lean: 0, whip: 0) : input)
            for ai in ais {
                let bike = ai.bike
                let ain = bike.finished ? RiderInput(throttle: 0, brake: 0.4, lean: 0, whip: 0)
                                        : ai.update(dt: dt, track: track)
                bike.update(dt: dt, input: ain)
                if bike.crashed && bike.crashTimer > 1.6 { bike.respawn() }
            }
            if player.crashed && player.crashTimer > 1.8 && !player.finished { player.respawn() }

            if !player.finished {
                recordTimer += dt
                if recordTimer >= 0.1 {
                    recordTimer -= 0.1
                    recording.append(GhostFrame(x: player.x, y: player.y,
                                                ang: player.ang, whip: player.whip))
                }
            }
            updateGhost()
            checkFinish()
        default:
            break
        }

        harvestEvents()
        emitRoost()
        updateHUD(dt)
    }

    private func landingAssist(_ input: RiderInput) -> RiderInput {
        var px = player.x, py = player.y, pvx = player.vx, pvy = player.vy
        for _ in 0..<60 {
            pvy -= GRAV * 0.05
            px += pvx * 0.05
            py += pvy * 0.05
            if py <= track.height(at: px) + player.wheelR + 0.3 { break }
        }
        let target = atan(track.slope(at: px))
        let auto = clampd(-(target - player.ang) * 1.4 - player.angVel * 0.2, -0.6, 0.6)
        var out = input
        out.lean = clampd(input.lean + auto * 0.7, -1, 1)
        return out
    }

    // MARK: - Ghost

    private func updateGhost() {
        guard let frames = ghostFrames, !frames.isEmpty else { return }
        let idx = Int(raceTime * 10)
        if idx >= frames.count {
            ghostPose = frames[frames.count - 1]
        } else {
            let f0 = frames[idx]
            let f1 = frames[min(frames.count - 1, idx + 1)]
            let t = raceTime * 10 - Double(idx)
            ghostPose = GhostFrame(x: lerp(f0.x, f1.x, t),
                                   y: lerp(f0.y, f1.y, t),
                                   ang: f0.ang + wrapAngle(f1.ang - f0.ang) * t,
                                   whip: lerp(f0.whip, f1.whip, t))
        }
        hud.ghostGap = ghostTime(atX: player.x) - raceTime
    }

    /// When the ghost passed this point — the basis for the live gap readout.
    private func ghostTime(atX x: Double) -> Double {
        guard let frames = ghostFrames, !frames.isEmpty else { return 0 }
        if x <= frames[0].x { return 0 }
        for (i, f) in frames.enumerated() where f.x >= x { return Double(i) * 0.1 }
        return Double(frames.count) * 0.1
    }

    // MARK: - Events

    private func harvestEvents() {
        for bike in field {
            for ev in bike.events {
                switch ev {
                case let .landing(quality, x, impact, _):
                    effects.append(.impact(x: x, y: track.height(at: x) + 0.1, power: impact))
                    if bike === player {
                        if quality == "perfect" {
                            show("PERFECT LANDING", kind: "good")
                            effects.append(.shake(0.25))
                            Haptics.light()
                        } else if quality == "bad" {
                            show("CASED", kind: "bad")
                            effects.append(.shake(0.7))
                        } else {
                            effects.append(.shake(0.18))
                        }
                    }
                case let .crash(_, x, _):
                    effects.append(.impact(x: x, y: track.height(at: x) + 0.2, power: 22))
                    if bike === player {
                        show("CRASH", kind: "bad")
                        effects.append(.shake(1.4))
                        Haptics.heavy()
                    }
                case let .wheelspin(x, y):
                    if Bool.random() { effects.append(.dust(x: x, y: y, power: 1.4)) }
                }
            }
            bike.events.removeAll(keepingCapacity: true)
        }
    }

    private func emitRoost() {
        let rear = player.wheels[0]
        if rear.grounded && player.forwardSpeed > 3 {
            effects.append(.dust(x: rear.cx, y: rear.cy - 0.15,
                                 power: min(3, player.forwardSpeed / 12)))
        }
    }

    // MARK: - Finish

    private func checkFinish() {
        for bike in field where !bike.finished && bike.x >= track.finishX {
            bike.finished = true
            bike.finishTime = raceTime
        }
        guard player.finished, !finishReported else { return }
        finishReported = true
        state = "finished"
        hud.finished = true

        let order = standings()
        let position = (order.firstIndex(where: { $0 === player }) ?? 0) + 1
        show(position == 1 ? "WINNER" : "P\(position)", kind: "big")

        let ghostTotal = ghostFrames.map { Double($0.count) * 0.1 } ?? 0
        let beatGhost = ghostTotal > 0 && player.finishTime < ghostTotal
        if beatGhost { show("GHOST BEATEN", kind: "good") }

        let summary = order.map { ($0 === player ? "You" : $0.displayName,
                                  $0.finished ? $0.finishTime : -1) }
        let outcome = RaceOutcome(position: position,
                                  time: player.finishTime,
                                  perfects: player.perfects,
                                  crashes: player.crashes,
                                  airTime: player.totalAirTime,
                                  style: Int(player.style),
                                  beatGhost: beatGhost,
                                  ghost: recording,
                                  order: summary)
        let block = onFinish
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { block?(outcome) }
    }

    func standings() -> [Bike] {
        field.sorted { a, b in
            if a.finished && b.finished { return a.finishTime < b.finishTime }
            if a.finished { return true }
            if b.finished { return false }
            return a.x > b.x
        }
    }

    private func show(_ text: String, kind: String) {
        hud.message = text
        hud.messageKind = kind
        messageTimer = kind == "big" ? 2.2 : 1.1
    }

    private func updateHUD(_ dt: Double) {
        hud.speedKmh = Int(max(0, player.forwardSpeed) * 3.6)
        hud.gear = player.gear
        hud.time = raceTime
        hud.style = Int(player.style)
        hud.progress = clampd(player.x / track.finishX, 0, 1)
        let order = standings()
        hud.position = (order.firstIndex(where: { $0 === player }) ?? 0) + 1
        hud.standings = order.prefix(6).map { ($0 === player ? "You" : $0.displayName, $0 === player) }
        if messageTimer > 0 {
            messageTimer -= dt
            if messageTimer <= 0 { hud.message = "" }
        }
    }
}

// MARK: - Small helpers

enum Haptics {
    static var enabled = true
    static func light() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func heavy() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }
    static func select() {
        guard enabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

extension UIColor {
    func blended(with other: UIColor, fraction: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let f = max(0, min(1, fraction))
        return UIColor(red: r1 + (r2 - r1) * f, green: g1 + (g2 - g1) * f,
                       blue: b1 + (b2 - b1) * f, alpha: a1)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
