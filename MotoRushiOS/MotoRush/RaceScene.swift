import SpriteKit
import SwiftUI
import UIKit

// The race scene. Everything drawn here is procedural geometry — there are no
// image assets in the project.

let PPM: CGFloat = 40    // points per metre at camera scale 1

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

final class RaceScene: SKScene {

    // Configuration handed in by the SwiftUI layer.
    var track: Track!
    var playerSpec: BikeSpec = BikeSpec.all[0]
    var playerUpgrades: [String: Int] = [:]
    var playerName = "You"
    var playerNumber = 482
    var difficulty: Double = 0.5
    var aiCount = 5
    var assistLanding = false
    var soundOn = true
    var hud = RaceHUD()
    var controls = RaceControls()
    var onFinish: ((Int, Double, Int, Int, Double, Int, [(String, Double)]) -> Void)?

    private var player: Bike!
    private var field: [Bike] = []
    private var ais: [AIController] = []
    private var bikeNodes: [ObjectIdentifier: BikeNode] = [:]

    private let cam = SKCameraNode()
    private var terrainNode = SKShapeNode()
    private var terrainLine = SKShapeNode()
    private var parallax: [SKShapeNode] = []
    private var gateNode: SKNode?
    private var particles: [SKShapeNode] = []
    private var particleIndex = 0

    private var state = "countdown"
    private var countdown: Double = 3.4
    private var raceTime: Double = 0
    private var lastUpdate: TimeInterval = 0
    private var camX: CGFloat = 0
    private var camY: CGFloat = 0
    private var camScale: CGFloat = 1
    private var shake: CGFloat = 0
    private var messageTimer: Double = 0
    private var finishReported = false

    // MARK: - Setup

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(Color(hex: track.biome.skyBottom))
        camera = cam
        addChild(cam)
        buildSky()
        buildTerrain()
        buildProps()
        buildField()
        buildGate()
        buildParticlePool()
        hud.fieldSize = field.count
        hud.countdown = 3
    }

    private func buildSky() {
        let top = SKColor(Color(hex: track.biome.skyTop))
        let bottom = SKColor(Color(hex: track.biome.skyBottom))
        let sky = SKSpriteNode(texture: RaceScene.gradientTexture(top: top, bottom: bottom,
                                                                 size: CGSize(width: 8, height: 512)))
        sky.zPosition = -100
        sky.size = CGSize(width: 4000, height: 2600)
        sky.name = "sky"
        cam.addChild(sky)

        if track.biome.stadium {
            let stand = SKShapeNode(rectOf: CGSize(width: 4000, height: 420))
            stand.fillColor = SKColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 0.95)
            stand.strokeColor = .clear
            stand.position = CGPoint(x: 0, y: 520)
            stand.zPosition = -80
            cam.addChild(stand)
            for i in 0..<5 {
                let rig = SKShapeNode(rectOf: CGSize(width: 130, height: 22), cornerRadius: 6)
                rig.fillColor = SKColor(white: 0.93, alpha: 1)
                rig.strokeColor = .clear
                rig.position = CGPoint(x: CGFloat(i - 2) * 420, y: 720)
                rig.zPosition = -79
                rig.alpha = 0.95
                cam.addChild(rig)
            }
        }

        // Three parallax ridges, deterministic from the seed.
        for layer in 0..<3 {
            let node = SKShapeNode()
            node.zPosition = CGFloat(-70 + layer)
            node.strokeColor = .clear
            node.fillColor = SKColor(Color(hex: track.biome.ground)).blended(with: .white,
                                                                            fraction: CGFloat(0.55 - Double(layer) * 0.15))
            node.alpha = CGFloat(0.55 + Double(layer) * 0.15)
            cam.addChild(node)
            parallax.append(node)
        }
    }

    private func updateParallax() {
        for (layer, node) in parallax.enumerated() {
            let par = 0.05 + CGFloat(layer) * 0.08
            let amp = CGFloat(90 + layer * 55)
            let baseY = CGFloat(-40 - layer * 45)
            let path = CGMutablePath()
            let width: CGFloat = 2600
            path.move(to: CGPoint(x: -width / 2, y: -1400))
            var px: CGFloat = -width / 2
            let off = camX * par
            while px <= width / 2 {
                let w = Double((px + off) * 0.006) + Double(layer) * 3.1 + Double(track.seed % 1000) * 0.01
                let y = baseY + CGFloat(sin(w) * 0.6 + sin(w * 2.3 + 1.7) * 0.3 + sin(w * 0.6) * 0.5) * amp
                path.addLine(to: CGPoint(x: px, y: y))
                px += 26
            }
            path.addLine(to: CGPoint(x: width / 2, y: -1400))
            path.closeSubpath()
            node.path = path
        }
    }

    private func buildTerrain() {
        let path = CGMutablePath()
        let step = Track.step
        path.move(to: CGPoint(x: 0, y: -600))
        var x: Double = 0
        while x <= track.length {
            path.addLine(to: CGPoint(x: CGFloat(x) * PPM, y: CGFloat(track.height(at: x)) * PPM))
            x += step * 2
        }
        path.addLine(to: CGPoint(x: CGFloat(track.length) * PPM, y: -600))
        path.closeSubpath()

        terrainNode = SKShapeNode(path: path)
        terrainNode.fillColor = SKColor(Color(hex: track.biome.ground))
        terrainNode.strokeColor = .clear
        terrainNode.zPosition = 5
        addChild(terrainNode)

        let line = CGMutablePath()
        x = 0
        var first = true
        while x <= track.length {
            let p = CGPoint(x: CGFloat(x) * PPM, y: CGFloat(track.height(at: x)) * PPM)
            if first { line.move(to: p); first = false } else { line.addLine(to: p) }
            x += step * 2
        }
        terrainLine = SKShapeNode(path: line)
        terrainLine.strokeColor = SKColor(Color(hex: track.biome.accent))
        terrainLine.lineWidth = 5
        terrainLine.zPosition = 6
        addChild(terrainLine)
    }

    private func buildProps() {
        for prop in track.props {
            let gy = CGFloat(track.height(at: prop.x)) * PPM
            let gx = CGFloat(prop.x) * PPM
            let s = CGFloat(prop.scale) * PPM
            let node = SKNode()
            node.position = CGPoint(x: gx, y: gy)
            node.zPosition = prop.back ? 2 : 8
            node.alpha = prop.back ? 0.65 : 1

            switch prop.kind {
            case "tree":
                let trunk = SKShapeNode(rectOf: CGSize(width: s * 0.16, height: s * 1.5))
                trunk.fillColor = SKColor(red: 0.23, green: 0.16, blue: 0.11, alpha: 1)
                trunk.strokeColor = .clear
                trunk.position = CGPoint(x: 0, y: s * 0.75)
                node.addChild(trunk)
                for i in 0..<3 {
                    let f = CGFloat(i)
                    let p = CGMutablePath()
                    p.move(to: CGPoint(x: 0, y: s * (2.4 - f * 0.35)))
                    p.addLine(to: CGPoint(x: -s * (0.45 + f * 0.12), y: s * (1.4 - f * 0.32)))
                    p.addLine(to: CGPoint(x: s * (0.45 + f * 0.12), y: s * (1.4 - f * 0.32)))
                    p.closeSubpath()
                    let leaf = SKShapeNode(path: p)
                    leaf.fillColor = SKColor(red: 0.25, green: 0.48, blue: 0.27, alpha: 1)
                    leaf.strokeColor = .clear
                    node.addChild(leaf)
                }
            case "banner":
                let b = SKShapeNode(rectOf: CGSize(width: s * 1.6, height: s * 0.5), cornerRadius: 4)
                b.fillColor = SKColor(Color(hex: track.biome.accent))
                b.strokeColor = .clear
                b.position = CGPoint(x: 0, y: s * 1.5)
                node.addChild(b)
                let pole = SKShapeNode(rectOf: CGSize(width: s * 0.1, height: s * 1.5))
                pole.fillColor = SKColor(white: 0.15, alpha: 1)
                pole.strokeColor = .clear
                pole.position = CGPoint(x: 0, y: s * 0.75)
                node.addChild(pole)
            case "flag":
                let pole = SKShapeNode(rectOf: CGSize(width: max(2, s * 0.06), height: s * 1.1))
                pole.fillColor = SKColor(white: 0.9, alpha: 1)
                pole.strokeColor = .clear
                pole.position = CGPoint(x: 0, y: s * 0.55)
                node.addChild(pole)
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 0, y: s * 1.1))
                p.addLine(to: CGPoint(x: s * 0.5, y: s * 0.92))
                p.addLine(to: CGPoint(x: 0, y: s * 0.74))
                p.closeSubpath()
                let flag = SKShapeNode(path: p)
                flag.fillColor = prop.back ? SKColor.systemRed : SKColor.systemYellow
                flag.strokeColor = .clear
                node.addChild(flag)
            default:
                let bale = SKShapeNode(rectOf: CGSize(width: s * 0.7, height: s * 0.45), cornerRadius: 3)
                bale.fillColor = SKColor(Color(hex: track.biome.accent)).blended(with: .black, fraction: 0.15)
                bale.strokeColor = SKColor(white: 0, alpha: 0.25)
                bale.position = CGPoint(x: 0, y: s * 0.22)
                node.addChild(bale)
            }
            addChild(node)
        }

        // Finish banner.
        let fx = CGFloat(track.finishX) * PPM
        let fy = CGFloat(track.height(at: track.finishX)) * PPM
        let post = SKShapeNode(rectOf: CGSize(width: 8, height: 150))
        post.fillColor = SKColor(red: 1, green: 0.82, blue: 0.4, alpha: 1)
        post.strokeColor = .clear
        post.position = CGPoint(x: fx, y: fy + 75)
        post.zPosition = 8
        addChild(post)
        let sign = SKLabelNode(text: "FINISH")
        sign.fontName = "AvenirNext-Heavy"
        sign.fontSize = 26
        sign.fontColor = SKColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 1)
        let plate = SKShapeNode(rectOf: CGSize(width: 150, height: 40), cornerRadius: 6)
        plate.fillColor = SKColor(red: 1, green: 0.82, blue: 0.4, alpha: 1)
        plate.strokeColor = .clear
        plate.position = CGPoint(x: fx + 70, y: fy + 165)
        plate.zPosition = 8
        sign.position = CGPoint(x: 0, y: -9)
        plate.addChild(sign)
        addChild(plate)
    }

    private func buildField() {
        player = Bike(spec: playerSpec, track: track, upgrades: playerUpgrades,
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
            // Gate positions: staggered behind the line like a real start.
            bike.x = track.startX - 1.4 - Double(i) * 1.0
            bike.y = track.height(at: bike.x) + bike.wheelR + spec.seatHeight
            field.append(bike)
            ais.append(AIController(bike: bike, personality: personality, difficulty: difficulty))
        }

        for bike in field {
            let node = BikeNode(bike: bike, isPlayer: bike === player)
            node.zPosition = bike === player ? 20 : 15
            addChild(node)
            bikeNodes[ObjectIdentifier(bike)] = node
        }
    }

    private func buildGate() {
        // A drop gate in front of the pack, the way a real gate drop reads.
        let gate = SKNode()
        let x = CGFloat(track.startX + 1.0) * PPM
        let y = CGFloat(track.height(at: track.startX + 1.0)) * PPM
        for i in 0..<6 {
            let bar = SKShapeNode(rectOf: CGSize(width: 6, height: 60), cornerRadius: 2)
            bar.fillColor = SKColor(red: 0.85, green: 0.2, blue: 0.3, alpha: 1)
            bar.strokeColor = .clear
            bar.position = CGPoint(x: CGFloat(i) * 14 - 35, y: 30)
            gate.addChild(bar)
        }
        let rail = SKShapeNode(rectOf: CGSize(width: 100, height: 6))
        rail.fillColor = SKColor(white: 0.85, alpha: 1)
        rail.strokeColor = .clear
        rail.position = CGPoint(x: 0, y: 62)
        gate.addChild(rail)
        gate.position = CGPoint(x: x, y: y)
        gate.zPosition = 18
        addChild(gate)
        gateNode = gate
    }

    private func buildParticlePool() {
        for _ in 0..<140 {
            let p = SKShapeNode(circleOfRadius: 5)
            p.fillColor = SKColor(Color(hex: track.biome.dust))
            p.strokeColor = .clear
            p.alpha = 0
            p.zPosition = 12
            addChild(p)
            particles.append(p)
        }
    }

    private func emit(x: Double, y: Double, vx: CGFloat, vy: CGFloat, scale: CGFloat, life: Double) {
        let node = particles[particleIndex % particles.count]
        particleIndex += 1
        node.removeAllActions()
        node.position = CGPoint(x: CGFloat(x) * PPM, y: CGFloat(y) * PPM)
        node.setScale(scale)
        node.alpha = 0.75
        let move = SKAction.moveBy(x: vx, y: vy, duration: life)
        move.timingMode = .easeOut
        node.run(SKAction.group([move,
                                 SKAction.fadeOut(withDuration: life),
                                 SKAction.scale(to: scale * 2.2, duration: life)]))
    }

    private func burst(x: Double, y: Double, count: Int, power: CGFloat) {
        for _ in 0..<count {
            let a = CGFloat.random(in: 0...(.pi))
            emit(x: x, y: y,
                 vx: cos(a) * power * CGFloat.random(in: 0.4...1.2),
                 vy: abs(sin(a)) * power * CGFloat.random(in: 0.4...1.2),
                 scale: CGFloat.random(in: 0.5...1.3),
                 life: Double.random(in: 0.4...0.9))
        }
    }

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        if lastUpdate == 0 { lastUpdate = currentTime }
        var dt = currentTime - lastUpdate
        lastUpdate = currentTime
        dt = min(dt, 1.0 / 30.0)
        if dt <= 0 { return }

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
                showMessage("GO!", kind: "big")
                gateNode?.run(SKAction.sequence([
                    SKAction.moveBy(x: 0, y: -90, duration: 0.25),
                    SKAction.fadeOut(withDuration: 0.2),
                    SKAction.removeFromParent()
                ]))
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
            checkFinish()
        default:
            break
        }

        handleEvents()
        updateNodes(dt: dt)
        updateCamera(dt: dt)
        updateHUD(dt: dt)
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

    private func handleEvents() {
        for bike in field {
            for ev in bike.events {
                switch ev {
                case let .landing(quality, x, impact, _):
                    burst(x: x, y: track.height(at: x) + 0.1,
                          count: min(18, 5 + Int(impact)), power: 60 + CGFloat(impact) * 9)
                    if bike === player {
                        if quality == "perfect" {
                            showMessage("PERFECT LANDING", kind: "good")
                            shake += 4
                            Haptics.light()
                        } else if quality == "bad" {
                            showMessage("CASED", kind: "bad")
                            shake += 12
                        } else {
                            shake += 3
                        }
                    }
                case let .crash(_, x, _):
                    burst(x: x, y: track.height(at: x) + 0.2, count: 22, power: 150)
                    if bike === player {
                        showMessage("CRASH", kind: "bad")
                        shake += 26
                        Haptics.heavy()
                    }
                case let .wheelspin(x, y):
                    if Bool.random() {
                        emit(x: x, y: y - 0.2, vx: CGFloat.random(in: -110 ... -30),
                             vy: CGFloat.random(in: 20...90), scale: 0.7, life: 0.5)
                    }
                }
            }
            bike.events.removeAll(keepingCapacity: true)
        }
    }

    private func checkFinish() {
        for bike in field where !bike.finished && bike.x >= track.finishX {
            bike.finished = true
            bike.finishTime = raceTime
        }
        if player.finished && !finishReported {
            finishReported = true
            state = "finished"
            hud.finished = true
            let order = standingsList()
            let position = (order.firstIndex(where: { $0 === player }) ?? 0) + 1
            showMessage(position == 1 ? "WINNER" : "P\(position)", kind: "big")
            let summary = order.map { ($0 === self.player ? "You" : $0.displayName, $0.finished ? $0.finishTime : -1) }
            let finishBlock = onFinish
            let pos = position
            let t = player.finishTime
            let perfects = player.perfects
            let crashes = player.crashes
            let air = player.totalAirTime
            let style = Int(player.style)
            run(SKAction.sequence([
                SKAction.wait(forDuration: 1.6),
                SKAction.run { finishBlock?(pos, t, perfects, crashes, air, style, summary) }
            ]))
        }
    }

    private func standingsList() -> [Bike] {
        field.sorted { a, b in
            if a.finished && b.finished { return a.finishTime < b.finishTime }
            if a.finished { return true }
            if b.finished { return false }
            return a.x > b.x
        }
    }

    private func showMessage(_ text: String, kind: String) {
        hud.message = text
        hud.messageKind = kind
        messageTimer = kind == "big" ? 2.2 : 1.1
    }

    private func updateNodes(dt: Double) {
        for bike in field {
            bikeNodes[ObjectIdentifier(bike)]?.sync(showLabel: state == "countdown" || raceTime < 2.5)
        }
        // Roost off the driven wheel.
        let rear = player.wheels[0]
        if rear.grounded && player.forwardSpeed > 3 {
            emit(x: rear.cx, y: rear.cy - 0.18,
                 vx: CGFloat(-player.forwardSpeed) * CGFloat.random(in: 8...16),
                 vy: CGFloat.random(in: 20...90),
                 scale: CGFloat.random(in: 0.4...0.9), life: 0.5)
        }
        updateParallax()
    }

    private func updateCamera(dt: Double) {
        let lead = clampd(player.vx * 0.42, -6, 14)
        let tx = CGFloat(player.x + lead) * PPM
        let ty = CGFloat(player.y + 1.4) * PPM
        let k = CGFloat(clampd(dt * 6.5, 0, 1))
        camX += (tx - camX) * k
        camY += (ty - camY) * k

        let speedNorm = CGFloat(clampd(abs(player.vx) / 45, 0, 1))
        let targetScale = (size.width < 500 ? 1.55 : 1.25) * (1 + speedNorm * 0.22)
        camScale += (targetScale - camScale) * CGFloat(clampd(dt * 3, 0, 1))
        cam.setScale(camScale)

        shake *= CGFloat(pow(0.03, dt))
        cam.position = CGPoint(x: camX + CGFloat.random(in: -shake...max(shake, 0.001)),
                               y: camY + CGFloat.random(in: -shake...max(shake, 0.001)))
    }

    private func updateHUD(dt: Double) {
        hud.speedKmh = Int(max(0, player.forwardSpeed) * 3.6)
        hud.gear = player.gear
        hud.time = raceTime
        hud.style = Int(player.style)
        hud.progress = clampd(player.x / track.finishX, 0, 1)
        let order = standingsList()
        hud.position = (order.firstIndex(where: { $0 === player }) ?? 0) + 1
        hud.standings = order.prefix(6).map { ($0 === player ? "You" : $0.displayName, $0 === player) }
        if messageTimer > 0 {
            messageTimer -= dt
            if messageTimer <= 0 { hud.message = "" }
        }
    }

    // MARK: - Helpers

    static func gradientTexture(top: SKColor, bottom: SKColor, size: CGSize) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(gradient,
                                                 start: CGPoint(x: 0, y: 0),
                                                 end: CGPoint(x: 0, y: size.height),
                                                 options: [])
            }
        }
        return SKTexture(image: image)
    }
}

// MARK: - Bike node

/// Draws one bike: wheels sit at their solved suspension positions, so the
/// fork and swingarm visibly work over every bump.
final class BikeNode: SKNode {
    private let bike: Bike
    private let isPlayer: Bool

    private let rearWheel = SKNode()
    private let frontWheel = SKNode()
    private let body = SKShapeNode()
    private let rider = SKShapeNode()
    private let swingarm = SKShapeNode()
    private let fork = SKShapeNode()
    private let shadow = SKShapeNode(ellipseOf: CGSize(width: 70, height: 16))
    private let label = SKLabelNode()
    private let numberLabel = SKLabelNode()
    private let ragdollNode = SKShapeNode()

    init(bike: Bike, isPlayer: Bool) {
        self.bike = bike
        self.isPlayer = isPlayer
        super.init()

        let tint = SKColor(Color(hex: bike.tintHex))

        shadow.fillColor = SKColor(white: 0, alpha: 0.3)
        shadow.strokeColor = .clear
        shadow.zPosition = -2
        addChild(shadow)

        for wheelNode in [rearWheel, frontWheel] {
            let wheelRadius = CGFloat(bike.wheelR) * PPM
            let tyre = SKShapeNode(circleOfRadius: wheelRadius)
            tyre.fillColor = SKColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1)
            tyre.strokeColor = .clear
            wheelNode.addChild(tyre)
            let rim = SKShapeNode(circleOfRadius: wheelRadius * 0.62)
            rim.fillColor = .clear
            rim.strokeColor = SKColor(white: 0.82, alpha: 1)
            rim.lineWidth = 2.5
            wheelNode.addChild(rim)
            let spokes = SKShapeNode()
            let p = CGMutablePath()
            for i in 0..<6 {
                let a = CGFloat(i) / 6 * .pi * 2
                p.move(to: .zero)
                p.addLine(to: CGPoint(x: cos(a) * wheelRadius * 0.6,
                                      y: sin(a) * wheelRadius * 0.6))
            }
            spokes.path = p
            spokes.strokeColor = SKColor(white: 0.7, alpha: 0.9)
            spokes.lineWidth = 1.2
            spokes.name = "spokes"
            wheelNode.addChild(spokes)
            addChild(wheelNode)
        }

        swingarm.strokeColor = tint.blended(with: .black, fraction: 0.45)
        swingarm.lineWidth = 5
        swingarm.lineCap = .round
        addChild(swingarm)

        fork.strokeColor = SKColor(white: 0.75, alpha: 1)
        fork.lineWidth = 4
        fork.lineCap = .round
        addChild(fork)

        body.fillColor = tint
        body.strokeColor = SKColor(white: 0, alpha: 0.35)
        body.lineWidth = 1.5
        body.zPosition = 1
        addChild(body)

        rider.strokeColor = .clear
        rider.zPosition = 2
        addChild(rider)

        ragdollNode.strokeColor = SKColor(white: 0.95, alpha: 1)
        ragdollNode.lineWidth = 5
        ragdollNode.lineCap = .round
        ragdollNode.zPosition = 3
        addChild(ragdollNode)

        numberLabel.text = "\(bike.number)"
        numberLabel.fontName = "AvenirNext-Heavy"
        numberLabel.fontSize = 11
        numberLabel.fontColor = SKColor(white: 0.1, alpha: 1)
        numberLabel.zPosition = 3
        addChild(numberLabel)

        label.text = isPlayer ? "You" : bike.displayName
        label.fontName = "AvenirNext-Bold"
        label.fontSize = 15
        label.fontColor = isPlayer ? SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1) : .white
        label.zPosition = 30
        addChild(label)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("not supported") }

    func sync(showLabel: Bool) {
        position = CGPoint(x: CGFloat(bike.x) * PPM, y: CGFloat(bike.y) * PPM)
        zRotation = CGFloat(bike.ang + bike.scrub * 0.3)

        // Whip is a fake-3D yaw: squash the silhouette horizontally.
        let whipSquash = CGFloat(0.35 + 0.65 * abs(cos(bike.whip)))
        xScale = whipSquash

        let c = cos(bike.ang), s = sin(bike.ang)
        func localOf(_ wx: Double, _ wy: Double) -> CGPoint {
            let dx = wx - bike.x, dy = wy - bike.y
            return CGPoint(x: CGFloat(dx * c + dy * s) * PPM / max(whipSquash, 0.01),
                           y: CGFloat(-dx * s + dy * c) * PPM)
        }

        // Ground shadow, projected under the bike and softened with height.
        let groundY = bike.track.height(at: bike.x)
        shadow.position = localOf(bike.x, groundY)
        shadow.zRotation = -zRotation
        let airH = CGFloat(max(0, bike.y - groundY))
        shadow.alpha = max(0.08, 0.32 - airH / 22)
        shadow.setScale(1 + airH / 16)

        let rp = localOf(bike.wheels[0].cx, bike.wheels[0].cy)
        let fp = localOf(bike.wheels[1].cx, bike.wheels[1].cy)
        rearWheel.position = rp
        frontWheel.position = fp
        rearWheel.zRotation = CGFloat(-bike.wheels[0].spin * 0.5)
        frontWheel.zRotation = CGFloat(-bike.wheels[1].spin * 0.5)

        let arm = CGMutablePath()
        arm.move(to: CGPoint(x: -5, y: 2))
        arm.addLine(to: rp)
        swingarm.path = arm

        let f = CGMutablePath()
        f.move(to: CGPoint(x: fp.x * 0.55, y: 12))
        f.addLine(to: fp)
        f.move(to: CGPoint(x: fp.x * 0.55, y: 12))
        f.addLine(to: CGPoint(x: fp.x * 0.5, y: 28))
        f.move(to: CGPoint(x: fp.x * 0.5 - 7, y: 30))
        f.addLine(to: CGPoint(x: fp.x * 0.5 + 7, y: 26))
        fork.path = f

        let bp = CGMutablePath()
        bp.move(to: CGPoint(x: -22, y: 0))
        bp.addLine(to: CGPoint(x: -12, y: 12))
        bp.addLine(to: CGPoint(x: 7, y: 14))
        bp.addLine(to: CGPoint(x: 21, y: 6))
        bp.addLine(to: CGPoint(x: 16, y: -1))
        bp.addLine(to: CGPoint(x: -7, y: -4))
        bp.closeSubpath()
        body.path = bp
        numberLabel.position = CGPoint(x: 17, y: 4)

        ragdollNode.isHidden = !bike.crashed
        rider.isHidden = bike.crashed
        if bike.crashed {
            let path = CGMutablePath()
            for (a, b, _) in bike.ragdollLinks {
                guard let pa = bike.ragdoll[a], let pb = bike.ragdoll[b] else { continue }
                path.move(to: localOf(pa.x, pa.y))
                path.addLine(to: localOf(pb.x, pb.y))
            }
            ragdollNode.path = path
        } else {
            drawRider()
        }

        label.isHidden = !showLabel
        if showLabel {
            label.position = CGPoint(x: 0, y: 66)
            label.zRotation = -zRotation
            label.xScale = 1 / max(whipSquash, 0.01)
        }
    }

    private func drawRider() {
        let lean = CGFloat(bike.lean)
        let stand = min(1, abs(lean) * 0.6 + (bike.airborne ? 0.35 : 0.15))
        let hip = CGPoint(x: (-0.12 - lean * 0.34) * PPM, y: (0.46 + stand * 0.16) * PPM)
        let chest = CGPoint(x: hip.x + (0.16 + lean * 0.24) * PPM, y: hip.y + (0.36 + stand * 0.1) * PPM)
        let head = CGPoint(x: chest.x + (0.06 + lean * 0.12) * PPM, y: chest.y + 0.30 * PPM)
        let hand = CGPoint(x: 0.48 * PPM, y: (0.72 + stand * 0.05) * PPM)
        let foot = CGPoint(x: -0.14 * PPM, y: 0.06 * PPM)

        let p = CGMutablePath()
        // Legs.
        p.move(to: hip); p.addLine(to: foot)
        // Torso.
        p.move(to: hip); p.addLine(to: chest)
        // Arms.
        p.move(to: chest); p.addLine(to: hand)
        rider.path = p
        rider.strokeColor = SKColor(white: 0.95, alpha: 1)
        rider.lineWidth = 7
        rider.lineCap = .round
        rider.fillColor = .clear

        if rider.children.isEmpty {
            let helmet = SKShapeNode(circleOfRadius: 8)
            helmet.fillColor = SKColor(red: 0.16, green: 0.4, blue: 0.95, alpha: 1)
            helmet.strokeColor = .clear
            helmet.name = "helmet"
            rider.addChild(helmet)
            let visor = SKShapeNode(ellipseOf: CGSize(width: 9, height: 5))
            visor.fillColor = SKColor(red: 0.5, green: 0.95, blue: 0.7, alpha: 1)
            visor.strokeColor = .clear
            visor.name = "visor"
            rider.addChild(visor)
        }
        rider.childNode(withName: "helmet")?.position = head
        rider.childNode(withName: "visor")?.position = CGPoint(x: head.x + 4, y: head.y)
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

extension SKColor {
    func blended(with other: SKColor, fraction: CGFloat) -> SKColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let f = max(0, min(1, fraction))
        return SKColor(red: r1 + (r2 - r1) * f, green: g1 + (g2 - g1) * f,
                       blue: b1 + (b2 - b1) * f, alpha: a1)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
