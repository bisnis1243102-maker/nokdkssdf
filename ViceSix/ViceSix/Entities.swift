import SpriteKit

// MARK: - Cars

enum DriverKind {
    case parked, npc, player, cop
}

/// A model of car. Arcade-tuned, but fed through a proper tyre model.
struct CarKind {
    let name: String
    let length: CGFloat
    let width: CGFloat
    let maxSpeed: CGFloat          // points / second
    let accel: CGFloat             // points / second²
    let turnRate: CGFloat          // radians / second at cruising speed
    let maxHP: CGFloat
    let colors: [SKColor]
    var isPolice: Bool = false
    var isTaxi: Bool = false
}

enum CarCatalog {
    static let compact = CarKind(
        name: "Pico", length: 74, width: 40, maxSpeed: 360, accel: 300, turnRate: 3.1,
        maxHP: 70,
        colors: [SKColor(red: 0.85, green: 0.35, blue: 0.30, alpha: 1),
                 SKColor(red: 0.35, green: 0.60, blue: 0.85, alpha: 1),
                 SKColor(red: 0.90, green: 0.80, blue: 0.40, alpha: 1)])

    static let sedan = CarKind(
        name: "Meridian", length: 92, width: 44, maxSpeed: 430, accel: 320, turnRate: 2.8,
        maxHP: 90,
        colors: [SKColor(white: 0.85, alpha: 1),
                 SKColor(white: 0.25, alpha: 1),
                 SKColor(red: 0.45, green: 0.30, blue: 0.55, alpha: 1),
                 SKColor(red: 0.25, green: 0.45, blue: 0.40, alpha: 1)])

    static let taxi = CarKind(
        name: "Leon Cab", length: 90, width: 44, maxSpeed: 420, accel: 330, turnRate: 2.9,
        maxHP: 85,
        colors: [SKColor(red: 0.95, green: 0.78, blue: 0.15, alpha: 1)],
        isTaxi: true)

    static let van = CarKind(
        name: "Boxer Van", length: 104, width: 50, maxSpeed: 340, accel: 240, turnRate: 2.3,
        maxHP: 120,
        colors: [SKColor(white: 0.9, alpha: 1),
                 SKColor(red: 0.55, green: 0.42, blue: 0.30, alpha: 1),
                 SKColor(red: 0.30, green: 0.42, blue: 0.55, alpha: 1)])

    static let muscle = CarKind(
        name: "Bandito", length: 96, width: 46, maxSpeed: 540, accel: 420, turnRate: 2.9,
        maxHP: 95,
        colors: [SKColor(red: 0.75, green: 0.15, blue: 0.20, alpha: 1),
                 SKColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1),
                 SKColor(red: 0.90, green: 0.50, blue: 0.15, alpha: 1)])

    static let sports = CarKind(
        name: "Vipera GT", length: 92, width: 44, maxSpeed: 640, accel: 500, turnRate: 3.4,
        maxHP: 80,
        colors: [SKColor(red: 0.95, green: 0.20, blue: 0.55, alpha: 1),
                 SKColor(red: 0.20, green: 0.85, blue: 0.75, alpha: 1)])

    static let pickup = CarKind(
        name: "Burro", length: 98, width: 48, maxSpeed: 390, accel: 290, turnRate: 2.5,
        maxHP: 110,
        colors: [SKColor(red: 0.60, green: 0.32, blue: 0.20, alpha: 1),
                 SKColor(red: 0.35, green: 0.45, blue: 0.30, alpha: 1)])

    static let police = CarKind(
        name: "VCPD Interceptor", length: 94, width: 46, maxSpeed: 560, accel: 430,
        turnRate: 3.2, maxHP: 130,
        colors: [SKColor(white: 0.92, alpha: 1)],
        isPolice: true)

    /// Weighted mix that spawns as ambient traffic.
    static let traffic: [CarKind] = [compact, compact, sedan, sedan, sedan,
                                     taxi, taxi, van, muscle, pickup]
}

/// A car in the world. Artwork points along +x; `heading` drives rotation.
/// `velocity` is the true world-space velocity (the tyre model lives in
/// GameScene); `speed` mirrors its forward component for AI and the HUD.
final class Car: SKNode {
    let kind: CarKind
    var hp: CGFloat
    var speed: CGFloat = 0
    var velocity = CGVector.zero
    var heading: CGFloat = 0 { didSet { zRotation = heading } }
    var driver: DriverKind = .npc
    /// Visual steering angle for the front wheels, radians.
    var steerVisual: CGFloat = 0 {
        didSet { for wheel in frontWheels { wheel.zRotation = steerVisual } }
    }

    // Traffic brain: 0:+x 1:+y 2:-x 3:-y along the road grid.
    var dirIndex: Int = 0
    var roadIndex: Int = 0          // index of the road being travelled
    var crossIndex: Int = 0         // next intersection along the travel axis
    var brakeTimer: TimeInterval = 0

    // Cop brain.
    var path: [CGPoint] = []
    var repathTimer: TimeInterval = 0
    var arrestTimer: TimeInterval = 0
    var fireTimer: TimeInterval = 0
    var stuckTimer: TimeInterval = 0
    var reverseTimer: TimeInterval = 0

    private var smokeNode: SKNode?
    private var sirenOn = false
    private var frontWheels: [SKShapeNode] = []
    private var tailLights: [SKShapeNode] = []
    private var headlightCone: SKShapeNode?
    private var isBraking = false
    private var dentLevel = 0
    private var nightAlpha: CGFloat = 0

    var disabled: Bool { hp <= 0 }
    var collisionRadius: CGFloat { kind.width * 0.55 }
    /// Offset of the rear axle from the centre, along the car's axis.
    var rearAxleOffset: CGFloat { kind.length * 0.28 }

    init(kind: CarKind, color: SKColor) {
        self.kind = kind
        self.hp = kind.maxHP
        super.init()
        zPosition = 9
        buildArtwork(color: color)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildArtwork(color: SKColor) {
        let L = kind.length, W = kind.width

        // Soft drop shadow under the chassis.
        let shadow = SKShapeNode(ellipseOf: CGSize(width: L + 8, height: W + 8))
        shadow.fillColor = SKColor(white: 0, alpha: 0.25)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 2, y: -3)
        shadow.zPosition = -1
        addChild(shadow)

        // Headlight cones, visible only at night (scene drives alpha).
        let cone = SKShapeNode()
        let conePath = CGMutablePath()
        for side: CGFloat in [-1, 1] {
            let ox = L / 2 - 2
            let oy = side * (W / 2 - 7)
            conePath.move(to: CGPoint(x: ox, y: oy))
            conePath.addLine(to: CGPoint(x: ox + 165, y: oy - 26))
            conePath.addLine(to: CGPoint(x: ox + 165, y: oy + 26))
            conePath.closeSubpath()
        }
        cone.path = conePath
        cone.fillColor = SKColor(red: 1, green: 0.93, blue: 0.70, alpha: 0.55)
        cone.strokeColor = .clear
        cone.blendMode = .add
        cone.zPosition = -0.8
        cone.alpha = 0
        addChild(cone)
        headlightCone = cone

        // Wheels poking out under the body; the front pair steers.
        for fx: CGFloat in [-1, 1] {
            for side: CGFloat in [-1, 1] {
                let wheel = SKShapeNode(rectOf: CGSize(width: 13, height: 6), cornerRadius: 2.5)
                wheel.fillColor = SKColor(white: 0.08, alpha: 1)
                wheel.strokeColor = .clear
                wheel.position = CGPoint(x: fx * L * 0.30, y: side * (W / 2))
                wheel.zPosition = -0.3
                addChild(wheel)
                if fx > 0 { frontWheels.append(wheel) }
            }
        }

        let body = SKShapeNode(rectOf: CGSize(width: L, height: W), cornerRadius: W * 0.22)
        body.fillColor = color
        body.strokeColor = SKColor(white: 0, alpha: 0.35)
        body.lineWidth = 2
        addChild(body)

        // Hood/roof sheen for a hint of curvature.
        let sheen = SKShapeNode(rectOf: CGSize(width: L * 0.86, height: W * 0.34),
                                cornerRadius: 6)
        sheen.fillColor = SKColor(white: 1, alpha: 0.10)
        sheen.strokeColor = .clear
        sheen.position = CGPoint(x: 0, y: W * 0.16)
        addChild(sheen)

        let cabin = SKShapeNode(rectOf: CGSize(width: L * 0.42, height: W * 0.78),
                                cornerRadius: 6)
        cabin.fillColor = SKColor(white: 0.12, alpha: 1)
        cabin.strokeColor = .clear
        cabin.position = CGPoint(x: -L * 0.04, y: 0)
        addChild(cabin)

        let windshield = SKShapeNode(rectOf: CGSize(width: L * 0.10, height: W * 0.68))
        windshield.fillColor = SKColor(red: 0.45, green: 0.62, blue: 0.72, alpha: 1)
        windshield.strokeColor = .clear
        windshield.position = CGPoint(x: L * 0.20, y: 0)
        addChild(windshield)

        // Side mirrors.
        for side: CGFloat in [-1, 1] {
            let mirror = SKShapeNode(rectOf: CGSize(width: 5, height: 4), cornerRadius: 1.5)
            mirror.fillColor = SKColor(white: 0.15, alpha: 1)
            mirror.strokeColor = .clear
            mirror.position = CGPoint(x: L * 0.16, y: side * (W / 2 + 2))
            addChild(mirror)
        }

        for side: CGFloat in [-1, 1] {
            let head = SKShapeNode(circleOfRadius: 3.5)
            head.fillColor = SKColor(red: 1, green: 0.95, blue: 0.7, alpha: 1)
            head.strokeColor = .clear
            head.position = CGPoint(x: L / 2 - 4, y: side * (W / 2 - 7))
            addChild(head)

            let tail = SKShapeNode(rectOf: CGSize(width: 4, height: 8))
            tail.fillColor = SKColor(red: 0.9, green: 0.15, blue: 0.15, alpha: 1)
            tail.strokeColor = .clear
            tail.alpha = 0.55
            tail.position = CGPoint(x: -L / 2 + 3, y: side * (W / 2 - 8))
            addChild(tail)
            tailLights.append(tail)
        }

        if kind.isPolice {
            let stripe = SKShapeNode(rectOf: CGSize(width: L * 0.9, height: W * 0.18))
            stripe.fillColor = SKColor(red: 0.10, green: 0.25, blue: 0.60, alpha: 1)
            stripe.strokeColor = .clear
            addChild(stripe)

            let bar = SKNode()
            let red = SKShapeNode(rectOf: CGSize(width: 8, height: W * 0.30))
            red.fillColor = .red; red.strokeColor = .clear
            red.position = CGPoint(x: 0, y: W * 0.18)
            let blue = SKShapeNode(rectOf: CGSize(width: 8, height: W * 0.30))
            blue.fillColor = SKColor(red: 0.2, green: 0.4, blue: 1, alpha: 1)
            blue.strokeColor = .clear
            blue.position = CGPoint(x: 0, y: -W * 0.18)
            bar.addChild(red); bar.addChild(blue)
            bar.position = CGPoint(x: L * 0.06, y: 0)
            bar.name = "lightbar"
            addChild(bar)
        }

        if kind.isTaxi {
            let sign = SKShapeNode(rectOf: CGSize(width: 14, height: 10), cornerRadius: 2)
            sign.fillColor = SKColor(white: 0.1, alpha: 1)
            sign.strokeColor = .clear
            addChild(sign)
        }
    }

    /// Brake lights flare while slowing or holding at a light.
    func setBraking(_ on: Bool) {
        guard on != isBraking else { return }
        isBraking = on
        for tail in tailLights {
            tail.alpha = on ? 1 : 0.55
            tail.setScale(on ? 1.4 : 1)
        }
    }

    /// Headlights come on with the dark (0 = day ... 1 = deep night).
    func setNight(_ f: CGFloat) {
        let a = disabled ? 0 : f * 0.34
        if abs(a - nightAlpha) > 0.02 {
            nightAlpha = a
            headlightCone?.alpha = a
        }
    }

    func setSiren(_ on: Bool) {
        guard kind.isPolice, on != sirenOn, let bar = childNode(withName: "lightbar") else { return }
        sirenOn = on
        bar.removeAllActions()
        if on {
            let flash = SKAction.repeatForever(.sequence([
                .run { bar.children.first?.alpha = 1; bar.children.last?.alpha = 0.2 },
                .wait(forDuration: 0.18),
                .run { bar.children.first?.alpha = 0.2; bar.children.last?.alpha = 1 },
                .wait(forDuration: 0.18),
            ]))
            bar.run(flash)
        } else {
            bar.children.forEach { $0.alpha = 1 }
        }
    }

    func applyDamage(_ d: CGFloat) {
        guard !disabled else { return }
        hp = max(0, hp - d)
        refreshDamageDecals()
        if disabled { startSmoking() }
    }

    /// Dents appear as the body wears down; the glass cracks near the end.
    private func refreshDamageDecals() {
        let frac = hp / kind.maxHP
        if frac < 0.55 && dentLevel < 1 {
            dentLevel = 1
            addDent()
        }
        if frac < 0.28 && dentLevel < 2 {
            dentLevel = 2
            addDent()
            addDent()
            addWindshieldCrack()
        }
    }

    private func addDent() {
        let dent = SKShapeNode(circleOfRadius: CGFloat.random(in: 5...9))
        dent.fillColor = SKColor(white: 0.05, alpha: 0.35)
        dent.strokeColor = SKColor(white: 0, alpha: 0.25)
        dent.lineWidth = 1
        dent.position = CGPoint(x: CGFloat.random(in: -kind.length * 0.42...kind.length * 0.42),
                                y: CGFloat.random(in: -kind.width * 0.35...kind.width * 0.35))
        dent.zPosition = 0.6
        addChild(dent)
    }

    private func addWindshieldCrack() {
        let path = CGMutablePath()
        let cx = kind.length * 0.20
        path.move(to: CGPoint(x: cx - 4, y: -8))
        path.addLine(to: CGPoint(x: cx + 2, y: 0))
        path.addLine(to: CGPoint(x: cx - 3, y: 9))
        path.move(to: CGPoint(x: cx + 2, y: 0))
        path.addLine(to: CGPoint(x: cx + 5, y: 6))
        let crack = SKShapeNode(path: path)
        crack.strokeColor = SKColor(white: 1, alpha: 0.6)
        crack.lineWidth = 1
        crack.zPosition = 0.7
        addChild(crack)
    }

    private func startSmoking() {
        guard smokeNode == nil else { return }
        setBraking(false)
        let smoke = SKNode()
        smoke.position = CGPoint(x: kind.length * 0.32, y: 0)
        smoke.zPosition = 3
        for k in 0..<3 {
            let puff = SKShapeNode(circleOfRadius: 7)
            puff.fillColor = SKColor(white: 0.35, alpha: 0.7)
            puff.strokeColor = .clear
            let cycle = SKAction.sequence([
                .group([.scale(to: 2.2, duration: 1.2),
                        .fadeAlpha(to: 0, duration: 1.2),
                        .moveBy(x: 16, y: 12, duration: 1.2)]),
                .run { puff.setScale(1); puff.alpha = 0.7; puff.position = .zero },
            ])
            puff.run(.sequence([.wait(forDuration: Double(k) * 0.4),
                                .repeatForever(cycle)]))
            smoke.addChild(puff)
        }
        addChild(smoke)
        smokeNode = smoke
    }
}

// MARK: - Pedestrians

/// A citizen of Port Leon. Artwork faces +x; the feet stride while walking.
final class Ped: SKNode {
    enum State { case walk, flee, down }

    var state: State = .walk
    var heading: CGFloat = 0 { didSet { zRotation = heading } }
    var walkSpeed: CGFloat = 55
    var stateTimer: TimeInterval = 0
    var wallet: Int = 10

    init(shirt: SKColor, skin: SKColor) {
        super.init()
        zPosition = 8

        Self.addFeet(to: self, radius: 2.6, spread: 5.5)

        let shoulders = SKShapeNode(rectOf: CGSize(width: 10, height: 19), cornerRadius: 5)
        shoulders.fillColor = shirt
        shoulders.strokeColor = SKColor(white: 0, alpha: 0.3)
        shoulders.lineWidth = 1
        addChild(shoulders)

        let head = SKShapeNode(circleOfRadius: 5)
        head.fillColor = skin
        head.strokeColor = SKColor(white: 0, alpha: 0.3)
        head.lineWidth = 1
        head.position = CGPoint(x: 2, y: 0)
        addChild(head)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Two feet on alternating stride cycles — reads as a walk from above.
    static func addFeet(to node: SKNode, radius: CGFloat, spread: CGFloat) {
        for side: CGFloat in [-1, 1] {
            let foot = SKShapeNode(circleOfRadius: radius)
            foot.fillColor = SKColor(white: 0.15, alpha: 1)
            foot.strokeColor = .clear
            foot.position = CGPoint(x: 0, y: side * spread)
            foot.zPosition = -0.5
            foot.name = "foot"
            let forward = SKAction.moveTo(x: radius * 2.2, duration: 0.17)
            forward.timingMode = .easeInEaseOut
            let back = SKAction.moveTo(x: -radius * 1.6, duration: 0.17)
            back.timingMode = .easeInEaseOut
            let cycle = side < 0 ? SKAction.sequence([forward, back])
                                 : SKAction.sequence([back, forward])
            foot.run(.repeatForever(cycle), withKey: "walk")
            node.addChild(foot)
        }
    }

    func knockDown() {
        guard state != .down else { return }
        state = .down
        stateTimer = 9
        removeAllActions()
        children.forEach { $0.removeAllActions() }
        run(.group([.rotate(byAngle: .pi / 2, duration: 0.15),
                    .fadeAlpha(to: 0.7, duration: 0.15)]))
        zPosition = 7
    }

    func getUp() {
        state = .flee
        stateTimer = 3
        alpha = 1
        zPosition = 8
    }
}

// MARK: - Player avatars & markers

enum Avatar {
    /// Builds the on-foot player node for the given protagonist.
    static func make(for p: Protagonist) -> SKNode {
        let node = SKNode()
        node.zPosition = 10

        let jacket: SKColor = (p == .mia)
            ? SKColor(red: 0.95, green: 0.25, blue: 0.60, alpha: 1)
            : SKColor(red: 0.15, green: 0.70, blue: 0.65, alpha: 1)
        let hair: SKColor = (p == .mia)
            ? SKColor(red: 0.25, green: 0.15, blue: 0.10, alpha: 1)
            : SKColor(white: 0.12, alpha: 1)

        Ped.addFeet(to: node, radius: 3, spread: 6.5)

        let shoulders = SKShapeNode(rectOf: CGSize(width: 12, height: 22), cornerRadius: 6)
        shoulders.fillColor = jacket
        shoulders.strokeColor = SKColor(white: 0, alpha: 0.4)
        shoulders.lineWidth = 1.5
        node.addChild(shoulders)

        let head = SKShapeNode(circleOfRadius: 6)
        head.fillColor = SKColor(red: 0.87, green: 0.68, blue: 0.55, alpha: 1)
        head.strokeColor = .clear
        head.position = CGPoint(x: 2, y: 0)
        node.addChild(head)

        let cap = SKShapeNode(circleOfRadius: 4.5)
        cap.fillColor = hair
        cap.strokeColor = .clear
        cap.position = CGPoint(x: 0.5, y: 0)
        node.addChild(cap)

        return node
    }
}

enum Markers {
    /// Pulsing ground ring used for mission objectives.
    static func waypoint(color: SKColor) -> SKNode {
        let node = SKNode()
        node.zPosition = 4

        let disc = SKShapeNode(circleOfRadius: 46)
        disc.fillColor = color.withAlphaComponent(0.22)
        disc.strokeColor = .clear
        node.addChild(disc)

        let ring = SKShapeNode(circleOfRadius: 46)
        ring.fillColor = .clear
        ring.strokeColor = color
        ring.lineWidth = 5
        ring.run(.repeatForever(.sequence([
            .group([.scale(to: 1.35, duration: 0.8), .fadeAlpha(to: 0.15, duration: 0.8)]),
            .group([.scale(to: 1.0, duration: 0.0), .fadeAlpha(to: 1.0, duration: 0.0)]),
        ])))
        node.addChild(ring)
        return node
    }

    /// Neon "VI" marker outside the mission giver's club.
    static func giver() -> SKNode {
        let node = waypoint(color: SKColor(red: 0.3, green: 0.9, blue: 1, alpha: 1))
        let label = SKLabelNode(text: "VI")
        label.fontName = "AvenirNext-Heavy"
        label.fontSize = 40
        label.fontColor = SKColor(red: 0.3, green: 0.9, blue: 1, alpha: 1)
        label.verticalAlignmentMode = .center
        label.zPosition = 1
        node.addChild(label)
        return node
    }
}
