import SpriteKit

/// The visual representation of one rider.
///
/// The machine is assembled from vector primitives at runtime rather than from
/// bitmap art. That keeps the app small, makes every part recolourable per
/// rider livery for free, and means the silhouette stays crisp at any zoom on
/// any display scale.
///
/// The node hierarchy mirrors the physics: the chassis is one node, and each
/// wheel is positioned independently from its own suspension state, so what the
/// player sees is literally what the solver computed.
public final class BikeNode: SKNode {

    private let spec: BikeSpec
    private let liveryColor: SKColor

    private let chassis = SKNode()
    private let frontWheel = SKNode()
    private let rearWheel = SKNode()
    private let frontForkLeg = SKShapeNode()
    private let rearSwingarm = SKShapeNode()
    private let riderNode = SKNode()
    private let riderTorso = SKShapeNode()
    private var riderArm = SKShapeNode()
    private var riderLeg = SKShapeNode()

    public init(spec: BikeSpec, liveryHue: Double, isPlayer: Bool) {
        self.spec = spec
        self.liveryColor = SKColor(hue: CGFloat(liveryHue),
                                   saturation: isPlayer ? 0.92 : 0.68,
                                   brightness: isPlayer ? 1.0 : 0.86,
                                   alpha: 1.0)
        super.init()

        // Opponents are drawn slightly desaturated and behind the player so the
        // player's own machine always reads first in a tight pack.
        zPosition = isPlayer ? 60 : 55
        if !isPlayer { alpha = 0.94 }

        buildWheel(rearWheel, radius: spec.rearWheelRadius)
        buildWheel(frontWheel, radius: spec.frontWheelRadius)
        buildChassis()
        buildRider()

        addChild(rearSwingarm)
        addChild(frontForkLeg)
        addChild(chassis)
        addChild(rearWheel)
        addChild(frontWheel)
        chassis.addChild(riderNode)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("BikeNode is created in code only") }

    // MARK: - Construction

    private func buildWheel(_ container: SKNode, radius: Double) {
        let r = RenderScale.length(radius)

        let tyre = SKShapeNode(circleOfRadius: r)
        tyre.fillColor = SKColor(white: 0.11, alpha: 1)
        tyre.strokeColor = SKColor(white: 0.05, alpha: 1)
        tyre.lineWidth = 1
        container.addChild(tyre)

        // Knobbly tread, drawn as short radial ticks around the carcass.
        let tread = SKShapeNode()
        let treadPath = CGMutablePath()
        let knobCount = 18
        for i in 0..<knobCount {
            let angle = CGFloat(i) / CGFloat(knobCount) * 2 * .pi
            let inner = CGPoint(x: cos(angle) * r * 0.88, y: sin(angle) * r * 0.88)
            let outer = CGPoint(x: cos(angle) * r * 1.04, y: sin(angle) * r * 1.04)
            treadPath.move(to: inner)
            treadPath.addLine(to: outer)
        }
        tread.path = treadPath
        tread.strokeColor = SKColor(white: 0.18, alpha: 1)
        tread.lineWidth = max(1.5, r * 0.09)
        tread.lineCap = .square
        container.addChild(tread)

        // Rim and spokes rotate with the wheel and are what actually sells speed.
        let rim = SKShapeNode(circleOfRadius: r * 0.52)
        rim.fillColor = .clear
        rim.strokeColor = SKColor(white: 0.72, alpha: 1)
        rim.lineWidth = max(1.2, r * 0.05)
        container.addChild(rim)

        let spokes = SKShapeNode()
        let spokePath = CGMutablePath()
        for i in 0..<8 {
            let angle = CGFloat(i) / 8 * 2 * .pi
            spokePath.move(to: .zero)
            spokePath.addLine(to: CGPoint(x: cos(angle) * r * 0.52, y: sin(angle) * r * 0.52))
        }
        spokes.path = spokePath
        spokes.strokeColor = SKColor(white: 0.62, alpha: 0.9)
        spokes.lineWidth = 1
        container.addChild(spokes)

        let hub = SKShapeNode(circleOfRadius: r * 0.14)
        hub.fillColor = SKColor(white: 0.55, alpha: 1)
        hub.strokeColor = .clear
        container.addChild(hub)

        // Brake rotor, offset so it reads as a separate disc.
        let rotor = SKShapeNode(circleOfRadius: r * 0.34)
        rotor.fillColor = .clear
        rotor.strokeColor = SKColor(white: 0.48, alpha: 0.85)
        rotor.lineWidth = max(1, r * 0.035)
        container.addChild(rotor)
    }

    private func buildChassis() {
        let scale = RenderScale.pointsPerMetre

        // Swingarm and forks live outside the chassis node so they can be
        // re-aimed at the wheels every frame as the suspension moves.
        rearSwingarm.strokeColor = SKColor(white: 0.42, alpha: 1)
        rearSwingarm.lineWidth = max(3, scale * 0.075)
        rearSwingarm.lineCap = .round
        rearSwingarm.zPosition = -1

        frontForkLeg.strokeColor = SKColor(white: 0.80, alpha: 1)
        frontForkLeg.lineWidth = max(3, scale * 0.065)
        frontForkLeg.lineCap = .round
        frontForkLeg.zPosition = -1

        // Frame spine.
        let frame = SKShapeNode()
        let framePath = CGMutablePath()
        framePath.move(to: CGPoint(x: -0.46 * scale, y: 0.30 * scale))
        framePath.addLine(to: CGPoint(x: -0.10 * scale, y: 0.46 * scale))
        framePath.addLine(to: CGPoint(x: 0.34 * scale, y: 0.52 * scale))
        framePath.addLine(to: CGPoint(x: 0.56 * scale, y: 0.40 * scale))
        frame.path = framePath
        frame.strokeColor = SKColor(white: 0.30, alpha: 1)
        frame.lineWidth = max(3, scale * 0.09)
        frame.lineJoin = .round
        frame.lineCap = .round
        chassis.addChild(frame)

        // Engine block.
        let engine = SKShapeNode(rect: CGRect(x: -0.16 * scale, y: 0.06 * scale,
                                              width: 0.40 * scale, height: 0.34 * scale),
                                 cornerRadius: 0.05 * scale)
        engine.fillColor = SKColor(white: 0.34, alpha: 1)
        engine.strokeColor = SKColor(white: 0.20, alpha: 1)
        engine.lineWidth = 1
        chassis.addChild(engine)

        // Exhaust, sweeping up and back from the head.
        let exhaust = SKShapeNode()
        let exhaustPath = CGMutablePath()
        exhaustPath.move(to: CGPoint(x: 0.22 * scale, y: 0.36 * scale))
        exhaustPath.addQuadCurve(to: CGPoint(x: -0.30 * scale, y: 0.44 * scale),
                                 control: CGPoint(x: -0.02 * scale, y: 0.58 * scale))
        exhaust.path = exhaustPath
        exhaust.strokeColor = SKColor(white: 0.66, alpha: 1)
        exhaust.lineWidth = max(2, scale * 0.055)
        exhaust.lineCap = .round
        chassis.addChild(exhaust)

        // Bodywork: tank, seat and number plate in the rider's livery.
        let body = SKShapeNode()
        let bodyPath = CGMutablePath()
        bodyPath.move(to: CGPoint(x: -0.52 * scale, y: 0.50 * scale))
        bodyPath.addLine(to: CGPoint(x: -0.18 * scale, y: 0.56 * scale))
        bodyPath.addLine(to: CGPoint(x: 0.16 * scale, y: 0.62 * scale))
        bodyPath.addQuadCurve(to: CGPoint(x: 0.54 * scale, y: 0.50 * scale),
                              control: CGPoint(x: 0.44 * scale, y: 0.66 * scale))
        bodyPath.addLine(to: CGPoint(x: 0.42 * scale, y: 0.40 * scale))
        bodyPath.addLine(to: CGPoint(x: -0.44 * scale, y: 0.38 * scale))
        bodyPath.closeSubpath()
        body.path = bodyPath
        body.fillColor = liveryColor
        body.strokeColor = liveryColor.withBrightness(0.55)
        body.lineWidth = 1.5
        body.lineJoin = .round
        chassis.addChild(body)

        // Front number plate.
        let plate = SKShapeNode(rect: CGRect(x: 0.50 * scale, y: 0.44 * scale,
                                             width: 0.16 * scale, height: 0.22 * scale),
                                cornerRadius: 0.04 * scale)
        plate.fillColor = SKColor(white: 0.94, alpha: 1)
        plate.strokeColor = SKColor(white: 0.3, alpha: 0.6)
        plate.lineWidth = 1
        plate.zRotation = -0.35
        chassis.addChild(plate)

        // Handlebars.
        let bars = SKShapeNode()
        let barsPath = CGMutablePath()
        barsPath.move(to: CGPoint(x: 0.54 * scale, y: 0.62 * scale))
        barsPath.addLine(to: CGPoint(x: 0.70 * scale, y: 0.78 * scale))
        bars.path = barsPath
        bars.strokeColor = SKColor(white: 0.25, alpha: 1)
        bars.lineWidth = max(2, scale * 0.05)
        bars.lineCap = .round
        chassis.addChild(bars)
    }

    private func buildRider() {
        let scale = RenderScale.pointsPerMetre
        let gear = liveryColor.withBrightness(0.9)

        riderTorso.path = CGPath(roundedRect: CGRect(x: -0.13 * scale, y: 0.62 * scale,
                                                     width: 0.30 * scale, height: 0.42 * scale),
                                 cornerWidth: 0.09 * scale, cornerHeight: 0.09 * scale,
                                 transform: nil)
        riderTorso.fillColor = gear
        riderTorso.strokeColor = gear.withBrightness(0.6)
        riderTorso.lineWidth = 1
        riderNode.addChild(riderTorso)

        let helmet = SKShapeNode(circleOfRadius: 0.13 * scale)
        helmet.position = CGPoint(x: 0.10 * scale, y: 1.12 * scale)
        helmet.fillColor = SKColor(white: 0.95, alpha: 1)
        helmet.strokeColor = SKColor(white: 0.4, alpha: 1)
        helmet.lineWidth = 1.5
        riderNode.addChild(helmet)

        // Visor, angled forward — a small detail that gives the rider a
        // direction of travel at a glance.
        let visor = SKShapeNode(rect: CGRect(x: 0.16 * scale, y: 1.08 * scale,
                                             width: 0.10 * scale, height: 0.07 * scale),
                                cornerRadius: 0.02 * scale)
        visor.fillColor = SKColor(red: 0.15, green: 0.22, blue: 0.30, alpha: 1)
        visor.strokeColor = .clear
        riderNode.addChild(visor)

        let armPath = CGMutablePath()
        armPath.move(to: CGPoint(x: 0.08 * scale, y: 0.95 * scale))
        armPath.addLine(to: CGPoint(x: 0.44 * scale, y: 0.86 * scale))
        armPath.addLine(to: CGPoint(x: 0.70 * scale, y: 0.80 * scale))
        riderArm.path = armPath
        riderArm.strokeColor = gear
        riderArm.lineWidth = max(3, scale * 0.085)
        riderArm.lineCap = .round
        riderArm.lineJoin = .round
        riderNode.addChild(riderArm)

        let legPath = CGMutablePath()
        legPath.move(to: CGPoint(x: -0.02 * scale, y: 0.66 * scale))
        legPath.addLine(to: CGPoint(x: 0.06 * scale, y: 0.36 * scale))
        legPath.addLine(to: CGPoint(x: 0.26 * scale, y: 0.24 * scale))
        riderLeg.path = legPath
        riderLeg.strokeColor = SKColor(white: 0.22, alpha: 1)
        riderLeg.lineWidth = max(3, scale * 0.095)
        riderLeg.lineCap = .round
        riderLeg.lineJoin = .round
        riderNode.addChild(riderLeg)
    }

    // MARK: - Per-frame update

    /// Mirrors the current physics state onto the node hierarchy.
    public func sync(with bike: BikePhysicsBody) {
        position = RenderScale.point(bike.position)
        chassis.zRotation = CGFloat(bike.angle)

        // Wheels are placed from their own solved centres, not from a fixed
        // offset, so suspension travel is visible exactly as simulated.
        frontWheel.position = RenderScale.point(bike.frontWheel.center - bike.position)
        rearWheel.position = RenderScale.point(bike.rearWheel.center - bike.position)
        // Spin is negated because a wheel rolling in +x turns clockwise.
        frontWheel.zRotation = CGFloat(-bike.frontWheel.spinAngle)
        rearWheel.zRotation = CGFloat(-bike.rearWheel.spinAngle)

        updateLinkages(bike: bike)
        updateRiderPose(bike: bike)
    }

    /// Re-aims the forks and swingarm between the chassis and the wheels.
    private func updateLinkages(bike: BikePhysicsBody) {
        let scale = RenderScale.pointsPerMetre
        let angle = CGFloat(bike.angle)

        let frontMountLocal = CGPoint(x: 0.62 * scale, y: 0.66 * scale).rotated(by: angle)
        let rearMountLocal = CGPoint(x: -0.34 * scale, y: 0.30 * scale).rotated(by: angle)

        let forkPath = CGMutablePath()
        forkPath.move(to: frontMountLocal)
        forkPath.addLine(to: frontWheel.position)
        frontForkLeg.path = forkPath

        let swingarmPath = CGMutablePath()
        swingarmPath.move(to: rearMountLocal)
        swingarmPath.addLine(to: rearWheel.position)
        rearSwingarm.path = swingarmPath
    }

    /// Poses the rider from the physics state. The rider is not animated on a
    /// timeline — the pose is a direct function of what the bike is doing,
    /// which is why it always agrees with the simulation.
    private func updateRiderPose(bike: BikePhysicsBody) {
        let scale = RenderScale.pointsPerMetre

        // Body shift: the rider moves fore and aft on the machine.
        let shift = CGFloat(bike.riderShift) * 0.22 * scale
        riderNode.position = CGPoint(x: shift, y: 0)

        // Crouch: the rider absorbs suspension load with their legs, standing
        // tall over jumps and compressing under landing forces.
        let load = CGFloat(bike.suspensionLoadFraction)
        riderNode.yScale = 1 - load * 0.18
        riderNode.zRotation = CGFloat(-bike.riderShift) * 0.16

        if bike.hasCrashed {
            // Crashed riders slump and let go of the bars.
            riderNode.zRotation = 0.9
            riderNode.position = CGPoint(x: -0.1 * scale, y: -0.15 * scale)
            alpha = 0.85
        } else {
            alpha = 1
        }
    }
}

// MARK: - Helpers

private extension CGPoint {
    func rotated(by radians: CGFloat) -> CGPoint {
        let c = cos(radians), s = sin(radians)
        return CGPoint(x: x * c - y * s, y: x * s + y * c)
    }
}

extension SKColor {
    /// Returns the same hue at a different brightness. Used for outlines and
    /// shadow tones so a livery only ever needs one authored colour.
    func withBrightness(_ scale: CGFloat) -> SKColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return self
        }
        return SKColor(hue: hue, saturation: saturation,
                       brightness: min(brightness * scale, 1), alpha: alpha)
    }
}

extension BikePhysicsBody {
    /// How loaded the suspension is overall, `0...1`. Drives the rider crouch
    /// and the camera's landing kick.
    var suspensionLoadFraction: Double {
        let front = frontWheel.compressionFraction(travel: spec.frontSuspension.travel)
        let rear = rearWheel.compressionFraction(travel: spec.rearSuspension.travel)
        return MathUtils.clamp01((front + rear) * 0.5)
    }
}
