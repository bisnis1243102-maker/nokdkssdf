import SceneKit
import UIKit

// MARK: - Cars

enum DriverKind {
    case parked, npc, player, cop
}

/// Body silhouette archetypes — each gets its own proportions.
enum CarBody {
    case compact, sedan, sports, muscle, van, pickup
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
    var bodyStyle: CarBody = .sedan
    var isPolice: Bool = false
    var isTaxi: Bool = false
}

enum CarCatalog {
    static let compact = CarKind(
        name: "Pico", length: 74, width: 40, maxSpeed: 360, accel: 300, turnRate: 3.1,
        maxHP: 70,
        colors: [UIColor(red: 0.85, green: 0.35, blue: 0.30, alpha: 1),
                 UIColor(red: 0.35, green: 0.60, blue: 0.85, alpha: 1),
                 UIColor(red: 0.90, green: 0.80, blue: 0.40, alpha: 1)],
        bodyStyle: .compact)

    static let sedan = CarKind(
        name: "Meridian", length: 92, width: 44, maxSpeed: 430, accel: 320, turnRate: 2.8,
        maxHP: 90,
        colors: [UIColor(white: 0.85, alpha: 1),
                 UIColor(white: 0.25, alpha: 1),
                 UIColor(red: 0.45, green: 0.30, blue: 0.55, alpha: 1),
                 UIColor(red: 0.25, green: 0.45, blue: 0.40, alpha: 1)],
        bodyStyle: .sedan)

    static let taxi = CarKind(
        name: "Leon Cab", length: 90, width: 44, maxSpeed: 420, accel: 330, turnRate: 2.9,
        maxHP: 85,
        colors: [UIColor(red: 0.95, green: 0.78, blue: 0.15, alpha: 1)],
        bodyStyle: .sedan,
        isTaxi: true)

    static let van = CarKind(
        name: "Boxer Van", length: 104, width: 50, maxSpeed: 340, accel: 240, turnRate: 2.3,
        maxHP: 120,
        colors: [UIColor(white: 0.9, alpha: 1),
                 UIColor(red: 0.55, green: 0.42, blue: 0.30, alpha: 1),
                 UIColor(red: 0.30, green: 0.42, blue: 0.55, alpha: 1)],
        bodyStyle: .van)

    static let muscle = CarKind(
        name: "Bandito", length: 96, width: 46, maxSpeed: 540, accel: 420, turnRate: 2.9,
        maxHP: 95,
        colors: [UIColor(red: 0.75, green: 0.15, blue: 0.20, alpha: 1),
                 UIColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1),
                 UIColor(red: 0.90, green: 0.50, blue: 0.15, alpha: 1)],
        bodyStyle: .muscle)

    static let sports = CarKind(
        name: "Vipera GT", length: 92, width: 44, maxSpeed: 640, accel: 500, turnRate: 3.4,
        maxHP: 80,
        colors: [UIColor(red: 0.95, green: 0.20, blue: 0.55, alpha: 1),
                 UIColor(red: 0.20, green: 0.85, blue: 0.75, alpha: 1)],
        bodyStyle: .sports)

    static let pickup = CarKind(
        name: "Burro", length: 98, width: 48, maxSpeed: 390, accel: 290, turnRate: 2.5,
        maxHP: 110,
        colors: [UIColor(red: 0.60, green: 0.32, blue: 0.20, alpha: 1),
                 UIColor(red: 0.35, green: 0.45, blue: 0.30, alpha: 1)],
        bodyStyle: .pickup)

    static let police = CarKind(
        name: "VCPD Interceptor", length: 94, width: 46, maxSpeed: 560, accel: 430,
        turnRate: 3.2, maxHP: 130,
        colors: [UIColor(white: 0.92, alpha: 1)],
        bodyStyle: .sedan,
        isPolice: true)

    /// Weighted mix that spawns as ambient traffic.
    static let traffic: [CarKind] = [compact, compact, sedan, sedan, sedan,
                                     taxi, taxi, van, muscle, pickup]
}

/// A 3D car with a proper silhouette: chassis, hood and trunk decks, a
/// glass greenhouse with a painted roof, arches, grille, plates, exhausts.
/// The sim runs on the ground plane: (x, y) renders as (x, 0, y).
final class Car3D: SCNNode {
    let kind: CarKind
    var hp: CGFloat
    var forwardSpeed: CGFloat = 0
    var velocity = CGVector.zero
    var heading: CGFloat = 0 {
        didSet { eulerAngles.y = Float(-heading) }
    }
    var driver: DriverKind = .npc
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

        // Proportions per silhouette.
        let baseH: CGFloat        // main body height above the sills
        let roofH: CGFloat        // greenhouse height
        let hoodLen: CGFloat
        let trunkLen: CGFloat
        let cabinLen: CGFloat
        switch kind.bodyStyle {
        case .compact: baseH = 9;  roofH = 11; hoodLen = L * 0.18; trunkLen = L * 0.06; cabinLen = L * 0.52
        case .sedan:   baseH = 9;  roofH = 10; hoodLen = L * 0.26; trunkLen = L * 0.20; cabinLen = L * 0.40
        case .sports:  baseH = 8;  roofH = 7;  hoodLen = L * 0.32; trunkLen = L * 0.14; cabinLen = L * 0.40
        case .muscle:  baseH = 9;  roofH = 9;  hoodLen = L * 0.32; trunkLen = L * 0.16; cabinLen = L * 0.38
        case .van:     baseH = 12; roofH = 16; hoodLen = L * 0.10; trunkLen = 0;        cabinLen = L * 0.76
        case .pickup:  baseH = 11; roofH = 11; hoodLen = L * 0.24; trunkLen = 0;        cabinLen = L * 0.28
        }
        let sillY: CGFloat = 7                    // bottom of the body, over the wheels
        let deckY = sillY + baseH                 // top of the main body

        // Two-layer automotive paint with a glossy clear coat.
        bodyMaterial.diffuse.contents = color
        bodyMaterial.lightingModel = .physicallyBased
        bodyMaterial.metalness.contents = 0.85
        bodyMaterial.roughness.contents = 0.35
        bodyMaterial.clearCoat.contents = 1.0
        bodyMaterial.clearCoatRoughness.contents = 0.08

        let trim = SCNMaterial()
        trim.diffuse.contents = UIColor(white: 0.10, alpha: 1)
        trim.lightingModel = .physicallyBased
        trim.roughness.contents = 0.6

        let glass = SCNMaterial()
        glass.diffuse.contents = UIColor(red: 0.10, green: 0.14, blue: 0.18, alpha: 1)
        glass.lightingModel = .physicallyBased
        glass.metalness.contents = 1.0
        glass.roughness.contents = 0.04

        func paintBox(_ w: CGFloat, _ h: CGFloat, _ l: CGFloat, _ x: CGFloat,
                      _ y: CGFloat, chamfer: CGFloat = 2.5,
                      material: SCNMaterial? = nil) -> SCNNode {
            let box = SCNBox(width: w, height: h, length: l, chamferRadius: chamfer)
            box.materials = [material ?? bodyMaterial]
            let node = SCNNode(geometry: box)
            node.position = SCNVector3(Float(x), Float(y), 0)
            addChildNode(node)
            return node
        }

        // Main body between the axles.
        _ = paintBox(L, baseH, W, 0, sillY + baseH / 2, chamfer: 3.5)

        // Hood and trunk decks sit slightly above the body line.
        if hoodLen > 4 {
            _ = paintBox(hoodLen, 3, W * 0.94, L / 2 - hoodLen / 2, deckY + 1.2)
        }
        if trunkLen > 4 {
            _ = paintBox(trunkLen, 3, W * 0.94, -L / 2 + trunkLen / 2, deckY + 1.2)
        }

        // Greenhouse: glass all round with a painted roof.
        let cabinX = L / 2 - hoodLen - cabinLen / 2
        let cabin = SCNBox(width: cabinLen, height: roofH, length: W * 0.84,
                           chamferRadius: 2.5)
        if kind.bodyStyle == .van {
            cabin.materials = [bodyMaterial]
        } else {
            cabin.materials = [glass, glass, glass, glass, bodyMaterial, bodyMaterial]
        }
        let cabinNode = SCNNode(geometry: cabin)
        cabinNode.position = SCNVector3(Float(cabinX), Float(deckY + roofH / 2), 0)
        addChildNode(cabinNode)
        if kind.bodyStyle == .van {
            // Van windshield: a glass panel on the cab front.
            let shield = SCNBox(width: 1.6, height: roofH * 0.6, length: W * 0.74,
                                chamferRadius: 1)
            shield.materials = [glass]
            let shieldNode = SCNNode(geometry: shield)
            shieldNode.position = SCNVector3(Float(cabinX + cabinLen / 2), Float(deckY + roofH * 0.55), 0)
            addChildNode(shieldNode)
        }

        // Pickup bed walls and tailgate.
        if kind.bodyStyle == .pickup {
            let bedLen = L - hoodLen - cabinLen - 6
            let bedX = -L / 2 + bedLen / 2
            for side: CGFloat in [-1, 1] {
                _ = {
                    let wall = paintBox(bedLen, 7, 3, bedX, deckY + 3)
                    wall.position.z = Float(side * (W / 2 - 2.5))
                    return wall
                }()
            }
            _ = paintBox(3, 7, W * 0.9, -L / 2 + 1.5, deckY + 3)
        }

        // Dark wheel arches over each wheel.
        for fx: CGFloat in [-1, 1] {
            for side: CGFloat in [-1, 1] {
                let arch = SCNBox(width: 23, height: 4.5, length: 5, chamferRadius: 2)
                arch.materials = [trim]
                let archNode = SCNNode(geometry: arch)
                archNode.position = SCNVector3(Float(fx * L * 0.32), Float(sillY + 8),
                                               Float(side * (W / 2 - 1)))
                addChildNode(archNode)
            }
        }

        // Bumpers, grille, plates, exhaust.
        for fx: CGFloat in [-1, 1] {
            let bumper = SCNBox(width: 6, height: 6, length: W * 0.96, chamferRadius: 2.5)
            bumper.materials = [trim]
            let bumperNode = SCNNode(geometry: bumper)
            bumperNode.position = SCNVector3(Float(fx * L / 2), 8, 0)
            addChildNode(bumperNode)

            let plate = SCNBox(width: 1.2, height: 4, length: 12, chamferRadius: 0.5)
            let plateMat = SCNMaterial()
            plateMat.diffuse.contents = UIColor(white: 0.92, alpha: 1)
            plate.materials = [plateMat]
            let plateNode = SCNNode(geometry: plate)
            plateNode.position = SCNVector3(Float(fx * (L / 2 + 3)), 8, 0)
            addChildNode(plateNode)
        }
        let grille = SCNBox(width: 1.6, height: 4.5, length: W * 0.5, chamferRadius: 1)
        grille.materials = [trim]
        let grilleNode = SCNNode(geometry: grille)
        grilleNode.position = SCNVector3(Float(L / 2 + 0.6), Float(deckY - 1), 0)
        addChildNode(grilleNode)

        let exhaustCount = kind.bodyStyle == .sports ? 2 : 1
        for e in 0..<exhaustCount {
            let pipe = SCNCylinder(radius: 1.5, height: 5)
            pipe.materials = [trim]
            let pipeNode = SCNNode(geometry: pipe)
            pipeNode.eulerAngles.z = .pi / 2
            pipeNode.position = SCNVector3(Float(-L / 2 - 1), 4.5,
                                           Float(W * 0.25 - CGFloat(e) * W * 0.5))
            addChildNode(pipeNode)
        }

        // Wheels: steer pivot (front pair) -> spin node -> tyre + hub.
        let tyre = SCNMaterial()
        tyre.diffuse.contents = UIColor(white: 0.06, alpha: 1)
        tyre.roughness.contents = 0.9
        tyre.lightingModel = .physicallyBased
        let hub = SCNMaterial()
        hub.diffuse.contents = UIColor(white: 0.7, alpha: 1)
        hub.lightingModel = .physicallyBased
        hub.metalness.contents = 0.9
        hub.roughness.contents = 0.25
        for fx: CGFloat in [-1, 1] {
            for side: CGFloat in [-1, 1] {
                let pivot = SCNNode()
                pivot.position = SCNVector3(Float(fx * L * 0.32), 9, Float(side * W / 2))
                addChildNode(pivot)

                let spin = SCNNode()
                pivot.addChildNode(spin)

                let wheel = SCNCylinder(radius: 9, height: 6.5)
                wheel.materials = [tyre]
                let wheelNode = SCNNode(geometry: wheel)
                wheelNode.eulerAngles.x = .pi / 2
                spin.addChildNode(wheelNode)

                let cap = SCNCylinder(radius: 5, height: 7.3)
                cap.materials = [hub]
                let capNode = SCNNode(geometry: cap)
                capNode.eulerAngles.x = .pi / 2
                spin.addChildNode(capNode)

                if fx > 0 { steerPivots.append(pivot) }
                spinNodes.append(spin)
            }
        }

        // Lights.
        let headMat = SCNMaterial()
        headMat.diffuse.contents = UIColor(white: 0.9, alpha: 1)
        headMat.emission.contents = UIColor(red: 1, green: 0.95, blue: 0.8, alpha: 1)
        tailMaterial.diffuse.contents = UIColor(red: 0.5, green: 0.05, blue: 0.05, alpha: 1)
        tailMaterial.emission.contents = UIColor.red
        tailMaterial.emission.intensity = 0.25
        for side: Float in [-1, 1] {
            let head = SCNBox(width: 2.5, height: 3.5, length: 8, chamferRadius: 1)
            head.materials = [headMat]
            let headNode = SCNNode(geometry: head)
            headNode.position = SCNVector3(Float(L / 2), Float(deckY), side * Float(W / 2 - 7))
            addChildNode(headNode)

            let tail = SCNBox(width: 2.2, height: 3.5, length: 9, chamferRadius: 1)
            tail.materials = [tailMaterial]
            let tailNode = SCNNode(geometry: tail)
            tailNode.position = SCNVector3(Float(-L / 2), Float(deckY), side * Float(W / 2 - 8))
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

        let roofTop = deckY + roofH
        if kind.isPolice {
            let bar = SCNNode()
            for (offset, lampColor): (Float, UIColor) in [(-6, .red),
                                                          (6, UIColor(red: 0.2, green: 0.4, blue: 1, alpha: 1))] {
                let lamp = SCNBox(width: 9, height: 5, length: 10, chamferRadius: 1.5)
                let m = SCNMaterial()
                m.diffuse.contents = lampColor
                m.emission.contents = lampColor
                m.emission.intensity = 0.3
                lamp.materials = [m]
                let lampNode = SCNNode(geometry: lamp)
                lampNode.position = SCNVector3(0, 0, offset)
                bar.addChildNode(lampNode)
            }
            bar.position = SCNVector3(Float(cabinX), Float(roofTop + 2.5), 0)
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
            signNode.position = SCNVector3(Float(cabinX), Float(roofTop + 3.5), 0)
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
            bodyMaterial.roughness.contents = 0.7
            bodyMaterial.clearCoat.contents = 0.2
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

/// A 3D person: pelvis, tapered torso, articulated limbs with hands and
/// feet, and hair — driven by a procedural walk cycle.
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

    init(shirt: UIColor, trousers: UIColor, skin: UIColor, hair: UIColor) {
        super.init()
        build(shirt: shirt, trousers: trousers, skin: skin, hair: hair)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build(shirt: UIColor, trousers: UIColor, skin: UIColor, hair: UIColor) {
        func mat(_ c: UIColor, rough: CGFloat = 0.85) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = c
            m.lightingModel = .physicallyBased
            m.roughness.contents = rough
            return m
        }
        let skinMat = mat(skin, rough: 0.6)
        let shirtMat = mat(shirt)
        let trouserMat = mat(trousers)
        let shoeMat = mat(UIColor(white: 0.12, alpha: 1), rough: 0.5)

        // Legs with feet: pivot at the hip so the whole leg swings.
        for side: Float in [-1, 1] {
            let pivot = SCNNode()
            pivot.position = SCNVector3(0, 17, side * 3.2)
            let leg = SCNCapsule(capRadius: 2.3, height: 17)
            leg.materials = [trouserMat]
            let legNode = SCNNode(geometry: leg)
            legNode.position = SCNVector3(0, -8.5, 0)
            pivot.addChildNode(legNode)

            let foot = SCNBox(width: 6.5, height: 2.4, length: 3.4, chamferRadius: 1)
            foot.materials = [shoeMat]
            let footNode = SCNNode(geometry: foot)
            footNode.position = SCNVector3(1.6, -16.4, 0)
            pivot.addChildNode(footNode)

            addChildNode(pivot)
            legPivots.append(pivot)
        }

        // Pelvis and a tapered torso with shoulders.
        let pelvis = SCNBox(width: 7.5, height: 5.5, length: 9.5, chamferRadius: 2.5)
        pelvis.materials = [trouserMat]
        let pelvisNode = SCNNode(geometry: pelvis)
        pelvisNode.position = SCNVector3(0, 19, 0)
        addChildNode(pelvisNode)

        let torso = SCNCapsule(capRadius: 5.2, height: 15)
        torso.materials = [shirtMat]
        let torsoNode = SCNNode(geometry: torso)
        torsoNode.position = SCNVector3(0, 26, 0)
        addChildNode(torsoNode)

        let shoulders = SCNBox(width: 7, height: 4, length: 13.5, chamferRadius: 2)
        shoulders.materials = [shirtMat]
        let shouldersNode = SCNNode(geometry: shoulders)
        shouldersNode.position = SCNVector3(0, 30.5, 0)
        addChildNode(shouldersNode)

        // Arms with hands.
        for side: Float in [-1, 1] {
            let pivot = SCNNode()
            pivot.position = SCNVector3(0, 30, side * 7.2)
            let arm = SCNCapsule(capRadius: 1.8, height: 13)
            arm.materials = [shirtMat]
            let armNode = SCNNode(geometry: arm)
            armNode.position = SCNVector3(0, -6.5, 0)
            pivot.addChildNode(armNode)

            let hand = SCNSphere(radius: 1.9)
            hand.materials = [skinMat]
            let handNode = SCNNode(geometry: hand)
            handNode.position = SCNVector3(0, -13.4, 0)
            pivot.addChildNode(handNode)

            addChildNode(pivot)
            armPivots.append(pivot)
        }

        // Neck, head, hair.
        let neck = SCNCylinder(radius: 1.8, height: 2.5)
        neck.materials = [skinMat]
        let neckNode = SCNNode(geometry: neck)
        neckNode.position = SCNVector3(0, 33.5, 0)
        addChildNode(neckNode)

        let head = SCNSphere(radius: 4.3)
        head.materials = [skinMat]
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0.4, 38, 0)
        addChildNode(headNode)

        let hairCap = SCNSphere(radius: 4.4)
        hairCap.materials = [mat(hair, rough: 0.9)]
        let hairNode = SCNNode(geometry: hairCap)
        hairNode.position = SCNVector3(-0.9, 39.1, 0)
        addChildNode(hairNode)
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
        let hair: UIColor = (p == .mia)
            ? UIColor(red: 0.30, green: 0.18, blue: 0.10, alpha: 1)
            : UIColor(white: 0.10, alpha: 1)
        let ped = Ped3D(shirt: jacket,
                        trousers: UIColor(white: 0.15, alpha: 1),
                        skin: UIColor(red: 0.87, green: 0.68, blue: 0.55, alpha: 1),
                        hair: hair)
        ped.wallet = 0
        return ped
    }
}

// MARK: - Markers

enum Markers3D {
    /// Glowing ground ring with a light beam, arcade-clear against the city.
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
