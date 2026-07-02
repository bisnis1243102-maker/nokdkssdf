import SceneKit
import UIKit

// MARK: - Cars

enum DriverKind {
    case parked, npc, player, cop
}

/// A model of car. Arcade-tuned, but fed through a proper tyre model.
/// Distances are world units (the sim runs on the ground plane).
struct CarKind {
    let name: String
    let length: CGFloat
    let width: CGFloat
    let maxSpeed: CGFloat          // units / second
    let accel: CGFloat             // units / second²
    let turnRate: CGFloat          // radians / second at cruising speed
    let maxHP: CGFloat
    let colors: [UIColor]
    var isPolice: Bool = false
    var isTaxi: Bool = false
}

enum CarCatalog {
    static let compact = CarKind(
        name: "Pico", length: 74, width: 40, maxSpeed: 360, accel: 300, turnRate: 3.1,
        maxHP: 70,
        colors: [UIColor(red: 0.85, green: 0.35, blue: 0.30, alpha: 1),
                 UIColor(red: 0.35, green: 0.60, blue: 0.85, alpha: 1),
                 UIColor(red: 0.90, green: 0.80, blue: 0.40, alpha: 1)])

    static let sedan = CarKind(
        name: "Meridian", length: 92, width: 44, maxSpeed: 430, accel: 320, turnRate: 2.8,
        maxHP: 90,
        colors: [UIColor(white: 0.85, alpha: 1),
                 UIColor(white: 0.25, alpha: 1),
                 UIColor(red: 0.45, green: 0.30, blue: 0.55, alpha: 1),
                 UIColor(red: 0.25, green: 0.45, blue: 0.40, alpha: 1)])

    static let taxi = CarKind(
        name: "Leon Cab", length: 90, width: 44, maxSpeed: 420, accel: 330, turnRate: 2.9,
        maxHP: 85,
        colors: [UIColor(red: 0.95, green: 0.78, blue: 0.15, alpha: 1)],
        isTaxi: true)

    static let van = CarKind(
        name: "Boxer Van", length: 104, width: 50, maxSpeed: 340, accel: 240, turnRate: 2.3,
        maxHP: 120,
        colors: [UIColor(white: 0.9, alpha: 1),
                 UIColor(red: 0.55, green: 0.42, blue: 0.30, alpha: 1),
                 UIColor(red: 0.30, green: 0.42, blue: 0.55, alpha: 1)])

    static let muscle = CarKind(
        name: "Bandito", length: 96, width: 46, maxSpeed: 540, accel: 420, turnRate: 2.9,
        maxHP: 95,
        colors: [UIColor(red: 0.75, green: 0.15, blue: 0.20, alpha: 1),
                 UIColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1),
                 UIColor(red: 0.90, green: 0.50, blue: 0.15, alpha: 1)])

    static let sports = CarKind(
        name: "Vipera GT", length: 92, width: 44, maxSpeed: 640, accel: 500, turnRate: 3.4,
        maxHP: 80,
        colors: [UIColor(red: 0.95, green: 0.20, blue: 0.55, alpha: 1),
                 UIColor(red: 0.20, green: 0.85, blue: 0.75, alpha: 1)])

    static let pickup = CarKind(
        name: "Burro", length: 98, width: 48, maxSpeed: 390, accel: 290, turnRate: 2.5,
        maxHP: 110,
        colors: [UIColor(red: 0.60, green: 0.32, blue: 0.20, alpha: 1),
                 UIColor(red: 0.35, green: 0.45, blue: 0.30, alpha: 1)])

    static let police = CarKind(
        name: "VCPD Interceptor", length: 94, width: 46, maxSpeed: 560, accel: 430,
        turnRate: 3.2, maxHP: 130,
        colors: [UIColor(white: 0.92, alpha: 1)],
        isPolice: true)

    /// Weighted mix that spawns as ambient traffic.
    static let traffic: [CarKind] = [compact, compact, sedan, sedan, sedan,
                                     taxi, taxi, van, muscle, pickup]
}

/// A 3D car. The simulation runs on the ground plane: 2D sim coordinates
/// (x, y) render as (x, 0, y), and `heading` rotates about the Y axis.
final class Car3D: SCNNode {
    let kind: CarKind
    var hp: CGFloat
    var forwardSpeed: CGFloat = 0
    var velocity = CGVector.zero
    var heading: CGFloat = 0 {
        didSet { eulerAngles.y = Float(-heading) }
    }
    var driver: DriverKind = .npc
    /// Ground-plane position in sim coordinates.
    var planePos: CGPoint {
        get { CGPoint(x: CGFloat(position.x), y: CGFloat(position.z)) }
        set { position = SCNVector3(Float(newValue.x), 0, Float(newValue.y)) }
    }
    var steerVisual: CGFloat = 0 {
        didSet { for pivot in steerPivots { pivot.eulerAngles.y = Float(-steerVisual) } }
    }

    // Traffic brain: 0:+x 1:+y 2:-x 3:-y along the road grid (sim coords).
    var dirIndex: Int = 0
    var roadIndex: Int = 0
    var crossIndex: Int = 0
    var brakeTimer: TimeInterval = 0

    // Cop brain.
    var path: [CGPoint] = []
    var repathTimer: TimeInterval = 0
    var fireTimer: TimeInterval = 0
    var stuckTimer: TimeInterval = 0
    var reverseTimer: TimeInterval = 0

    private var steerPivots: [SCNNode] = []
    private var spinNodes: [SCNNode] = []
    private var wheelSpin: CGFloat = 0
    private var tailMaterial = SCNMaterial()
    private var coneNode: SCNNode?
    private var lightbar: SCNNode?
    private var bodyMaterial = SCNMaterial()
    private var isBraking = false
    private var sirenOn = false
    private var smoking = false
    private var nightAlpha: CGFloat = -1

    var disabled: Bool { hp <= 0 }
    var collisionRadius: CGFloat { kind.width * 0.55 }
    var rearAxleOffset: CGFloat { kind.length * 0.28 }

    init(kind: CarKind, color: UIColor) {
        self.kind = kind
        self.hp = kind.maxHP
        super.init()
        buildBody(color: color)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func buildBody(color: UIColor) {
        let L = CGFloat(kind.length), W = CGFloat(kind.width)

        bodyMaterial.diffuse.contents = color
        bodyMaterial.lightingModel = .physicallyBased
        bodyMaterial.metalness.contents = 0.75
        bodyMaterial.roughness.contents = 0.28

        let body = SCNBox(width: L, height: 13, length: W, chamferRadius: 4)
        body.materials = [bodyMaterial]
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 12.5, 0)
        addChildNode(bodyNode)

        let glass = SCNMaterial()
        glass.diffuse.contents = UIColor(red: 0.20, green: 0.28, blue: 0.34, alpha: 1)
        glass.lightingModel = .physicallyBased
        glass.metalness.contents = 0.9
        glass.roughness.contents = 0.1

        let cabin = SCNBox(width: L * 0.48, height: 11, length: W * 0.86, chamferRadius: 4)
        cabin.materials = [glass]
        let cabinNode = SCNNode(geometry: cabin)
        cabinNode.position = SCNVector3(Float(-L * 0.06), 23, 0)
        addChildNode(cabinNode)

        // Wheels: steer pivot (front pair) -> spin node -> cylinder.
        let tyre = SCNMaterial()
        tyre.diffuse.contents = UIColor(white: 0.06, alpha: 1)
        tyre.roughness.contents = 0.9
        tyre.lightingModel = .physicallyBased
        for fx: CGFloat in [-1, 1] {
            for side: CGFloat in [-1, 1] {
                let pivot = SCNNode()
                pivot.position = SCNVector3(Float(fx * L * 0.32), 9, Float(side * W / 2))
                addChildNode(pivot)

                let spin = SCNNode()
                pivot.addChildNode(spin)

                let wheel = SCNCylinder(radius: 9, height: 7)
                wheel.materials = [tyre]
                let wheelNode = SCNNode(geometry: wheel)
                wheelNode.eulerAngles.x = .pi / 2
                spin.addChildNode(wheelNode)

                if fx > 0 { steerPivots.append(pivot) }
                spinNodes.append(spin)
            }
        }

        // Headlights (emissive) + tail lights on a shared brake material.
        let headMat = SCNMaterial()
        headMat.diffuse.contents = UIColor(white: 0.9, alpha: 1)
        headMat.emission.contents = UIColor(red: 1, green: 0.95, blue: 0.8, alpha: 1)
        tailMaterial.diffuse.contents = UIColor(red: 0.5, green: 0.05, blue: 0.05, alpha: 1)
        tailMaterial.emission.contents = UIColor.red
        tailMaterial.emission.intensity = 0.25
        for side: Float in [-1, 1] {
            let head = SCNBox(width: 3, height: 4, length: 8, chamferRadius: 1)
            head.materials = [headMat]
            let headNode = SCNNode(geometry: head)
            headNode.position = SCNVector3(Float(L / 2), 13, side * Float(W / 2 - 7))
            addChildNode(headNode)

            let tail = SCNBox(width: 2.5, height: 4, length: 9, chamferRadius: 1)
            tail.materials = [tailMaterial]
            let tailNode = SCNNode(geometry: tail)
            tailNode.position = SCNVector3(Float(-L / 2), 13, side * Float(W / 2 - 8))
            addChildNode(tailNode)
        }

        // Headlight beam cones, visible at night.
        let cone = SCNNode()
        let beam = SCNCone(topRadius: 4, bottomRadius: 34, height: 170)
        let beamMat = SCNMaterial()
        beamMat.diffuse.contents = UIColor.clear
        beamMat.emission.contents = UIColor(red: 1, green: 0.93, blue: 0.7, alpha: 1)
        beamMat.transparency = 0.16
        beamMat.isDoubleSided = true
        beam.materials = [beamMat]
        for side: Float in [-1, 1] {
            let b = SCNNode(geometry: beam)
            b.position = SCNVector3(Float(L / 2) + 85, 10, side * Float(W / 2 - 8))
            b.eulerAngles.z = .pi / 2
            cone.addChildNode(b)
        }
        cone.opacity = 0
        addChildNode(cone)
        coneNode = cone

        if kind.isPolice {
            let bar = SCNNode()
            for (offset, color): (Float, UIColor) in [(-6, .red),
                                                      (6, UIColor(red: 0.2, green: 0.4, blue: 1, alpha: 1))] {
                let lamp = SCNBox(width: 9, height: 5, length: 10, chamferRadius: 1.5)
                let m = SCNMaterial()
                m.diffuse.contents = color
                m.emission.contents = color
                m.emission.intensity = 0.3
                lamp.materials = [m]
                let lampNode = SCNNode(geometry: lamp)
                lampNode.position = SCNVector3(0, 0, offset)
                bar.addChildNode(lampNode)
            }
            bar.position = SCNVector3(Float(-L * 0.06), 31, 0)
            addChildNode(bar)
            lightbar = bar
        }

        if kind.isTaxi {
            let sign = SCNBox(width: 16, height: 7, length: 8, chamferRadius: 2)
            let m = SCNMaterial()
            m.diffuse.contents = UIColor(red: 0.95, green: 0.85, blue: 0.3, alpha: 1)
            m.emission.contents = UIColor(red: 0.9, green: 0.8, blue: 0.2, alpha: 1)
            m.emission.intensity = 0.4
            sign.materials = [m]
            let signNode = SCNNode(geometry: sign)
            signNode.position = SCNVector3(Float(-L * 0.06), 31, 0)
            addChildNode(signNode)
        }
    }

    /// Roll the wheels to match ground speed.
    func spinWheels(_ dt: CGFloat) {
        guard abs(forwardSpeed) > 1 else { return }
        wheelSpin += forwardSpeed / 9 * dt
        for spin in spinNodes { spin.eulerAngles.z = Float(-wheelSpin) }
    }

    func setBraking(_ on: Bool) {
        guard on != isBraking else { return }
        isBraking = on
        tailMaterial.emission.intensity = on ? 1.0 : 0.25
    }

    func setNight(_ f: CGFloat) {
        let a = disabled ? 0 : f
        if abs(a - nightAlpha) > 0.03 {
            nightAlpha = a
            coneNode?.opacity = a
        }
    }

    func setSiren(_ on: Bool) {
        guard kind.isPolice, on != sirenOn, let bar = lightbar else { return }
        sirenOn = on
        bar.removeAllActions()
        let lamps = bar.childNodes
        if on, lamps.count == 2 {
            let a = lamps[0], b = lamps[1]
            let flash = SCNAction.repeatForever(.sequence([
                .run { _ in
                    a.geometry?.firstMaterial?.emission.intensity = 1.6
                    b.geometry?.firstMaterial?.emission.intensity = 0.1
                },
                .wait(duration: 0.18),
                .run { _ in
                    a.geometry?.firstMaterial?.emission.intensity = 0.1
                    b.geometry?.firstMaterial?.emission.intensity = 1.6
                },
                .wait(duration: 0.18),
            ]))
            bar.runAction(flash)
        } else {
            for lamp in lamps {
                lamp.geometry?.firstMaterial?.emission.intensity = 0.3
            }
        }
    }

    func applyDamage(_ d: CGFloat) {
        guard !disabled else { return }
        hp = max(0, hp - d)
        if hp / kind.maxHP < 0.5 {
            bodyMaterial.roughness.contents = 0.7    // scuffed paint
        }
        if disabled { startSmoking() }
    }

    private func startSmoking() {
        guard !smoking else { return }
        smoking = true
        setBraking(false)
        bodyMaterial.diffuse.contents = UIColor(white: 0.2, alpha: 1)
        let smoke = SCNParticleSystem()
        smoke.birthRate = 30
        smoke.particleLifeSpan = 1.6
        smoke.particleVelocity = 40
        smoke.particleVelocityVariation = 15
        smoke.acceleration = SCNVector3(6, 45, 0)
        smoke.particleSize = 9
        smoke.particleSizeVariation = 5
        smoke.particleColor = UIColor(white: 0.35, alpha: 0.55)
        smoke.spreadingAngle = 24
        smoke.emittingDirection = SCNVector3(0, 1, 0)
        let vent = SCNNode()
        vent.position = SCNVector3(Float(kind.length * 0.34), 18, 0)
        vent.addParticleSystem(smoke)
        addChildNode(vent)
    }
}

// MARK: - People

/// A 3D person built from primitives, with a simple procedural walk cycle.
/// Used for pedestrians and (with brighter clothes) the player.
final class Ped3D: SCNNode {
    enum State { case walk, flee, down }

    var state: State = .walk
    var heading: CGFloat = 0 {
        didSet { eulerAngles.y = Float(-heading) }
    }
    var walkSpeed: CGFloat = 55
    var stateTimer: TimeInterval = 0
    var wallet: Int = 10
    var planePos: CGPoint {
        get { CGPoint(x: CGFloat(position.x), y: CGFloat(position.z)) }
        set { position = SCNVector3(Float(newValue.x), 0, Float(newValue.y)) }
    }

    private var legPivots: [SCNNode] = []
    private var armPivots: [SCNNode] = []
    private var walkPhase: CGFloat = 0
    private(set) var isDownVisually = false

    init(shirt: UIColor, trousers: UIColor, skin: UIColor) {
        super.init()
        build(shirt: shirt, trousers: trousers, skin: skin)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build(shirt: UIColor, trousers: UIColor, skin: UIColor) {
        func mat(_ c: UIColor) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = c
            m.lightingModel = .physicallyBased
            m.roughness.contents = 0.85
            return m
        }

        // Legs: pivot at the hip, cylinder hanging below.
        for side: Float in [-1, 1] {
            let pivot = SCNNode()
            pivot.position = SCNVector3(0, 16, side * 3.2)
            let leg = SCNCylinder(radius: 2.4, height: 16)
            leg.materials = [mat(trousers)]
            let legNode = SCNNode(geometry: leg)
            legNode.position = SCNVector3(0, -8, 0)
            pivot.addChildNode(legNode)
            addChildNode(pivot)
            legPivots.append(pivot)
        }

        let torso = SCNCapsule(capRadius: 5, height: 16)
        torso.materials = [mat(shirt)]
        let torsoNode = SCNNode(geometry: torso)
        torsoNode.position = SCNVector3(0, 23, 0)
        addChildNode(torsoNode)

        for side: Float in [-1, 1] {
            let pivot = SCNNode()
            pivot.position = SCNVector3(0, 28, side * 6.4)
            let arm = SCNCylinder(radius: 1.7, height: 13)
            arm.materials = [mat(shirt)]
            let armNode = SCNNode(geometry: arm)
            armNode.position = SCNVector3(0, -6.5, 0)
            pivot.addChildNode(armNode)
            addChildNode(pivot)
            armPivots.append(pivot)
        }

        let head = SCNSphere(radius: 4.4)
        head.materials = [mat(skin)]
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 35, 0)
        addChildNode(headNode)
    }

    /// Swing limbs while moving; settle to neutral when still.
    func animateWalk(_ dt: CGFloat, moving: Bool, speed: CGFloat) {
        if moving {
            walkPhase += dt * (4 + speed * 0.045)
            let swing = Float(sin(walkPhase)) * 0.55
            legPivots[0].eulerAngles.z = swing
            legPivots[1].eulerAngles.z = -swing
            armPivots[0].eulerAngles.z = -swing * 0.7
            armPivots[1].eulerAngles.z = swing * 0.7
        } else {
            for pivot in legPivots + armPivots {
                pivot.eulerAngles.z *= Float(max(0, 1 - 8 * dt))
            }
        }
    }

    func knockDown() {
        guard state != .down else { return }
        state = .down
        stateTimer = 9
        isDownVisually = true
        removeAllActions()
        runAction(.rotateTo(x: .pi / 2, y: CGFloat(eulerAngles.y), z: 0, duration: 0.2))
    }
}

enum Avatar3D {
    /// The playable leads, dressed to stand out from the crowd.
    static func make(for p: Protagonist) -> Ped3D {
        let jacket: UIColor = (p == .mia)
            ? UIColor(red: 0.95, green: 0.25, blue: 0.60, alpha: 1)
            : UIColor(red: 0.15, green: 0.70, blue: 0.65, alpha: 1)
        let ped = Ped3D(shirt: jacket,
                        trousers: UIColor(white: 0.15, alpha: 1),
                        skin: UIColor(red: 0.87, green: 0.68, blue: 0.55, alpha: 1))
        ped.wallet = 0
        return ped
    }
}

// MARK: - Markers

enum Markers3D {
    /// Glowing ground ring with a light beam, GTA-style.
    static func waypoint(color: UIColor, beamHeight: CGFloat = 320) -> SCNNode {
        let node = SCNNode()

        let ring = SCNTorus(ringRadius: 46, pipeRadius: 4)
        let ringMat = SCNMaterial()
        ringMat.diffuse.contents = color
        ringMat.emission.contents = color
        ringMat.emission.intensity = 1.2
        ring.materials = [ringMat]
        let ringNode = SCNNode(geometry: ring)
        ringNode.position = SCNVector3(0, 4, 0)
        ringNode.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 4)))
        node.addChildNode(ringNode)

        let beam = SCNCylinder(radius: 26, height: beamHeight)
        let beamMat = SCNMaterial()
        beamMat.diffuse.contents = UIColor.clear
        beamMat.emission.contents = color
        beamMat.transparency = 0.18
        beamMat.isDoubleSided = true
        beam.materials = [beamMat]
        let beamNode = SCNNode(geometry: beam)
        beamNode.position = SCNVector3(0, Float(beamHeight / 2), 0)
        node.addChildNode(beamNode)

        return node
    }

    static func giver() -> SCNNode {
        waypoint(color: UIColor(red: 0.3, green: 0.9, blue: 1, alpha: 1), beamHeight: 420)
    }

    /// Spinning cash pickup.
    static func cash() -> SCNNode {
        let coin = SCNCylinder(radius: 10, height: 3)
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(red: 0.2, green: 0.75, blue: 0.35, alpha: 1)
        m.emission.contents = UIColor(red: 0.2, green: 0.9, blue: 0.4, alpha: 1)
        m.emission.intensity = 0.8
        coin.materials = [m]
        let node = SCNNode(geometry: coin)
        node.position = SCNVector3(0, 14, 0)
        node.eulerAngles.x = .pi / 2
        let holder = SCNNode()
        holder.addChildNode(node)
        holder.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 1.6)))
        return holder
    }
}
