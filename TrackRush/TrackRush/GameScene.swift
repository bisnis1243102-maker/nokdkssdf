import SpriteKit

/// Physics categories. Wheels collide with the ground; the rider does too, but
/// touching it at all ends the run.
private enum Category {
    static let ground: UInt32 = 1 << 0
    static let wheel: UInt32  = 1 << 1
    static let rider: UInt32  = 1 << 2
}

/// The race itself: terrain, a two-wheeled bike, and the rules that decide
/// whether you finished or landed on your head.
final class GameScene: SKScene, SKPhysicsContactDelegate {

    // Reported back to SwiftUI.
    var onCrash: (() -> Void)?
    var onFinish: ((TimeInterval) -> Void)?
    var onTick: ((_ progress: Double, _ elapsed: TimeInterval, _ speed: Double) -> Void)?

    // Held down by the on-screen controls.
    var throttle = false
    var brake = false
    var leanBack = false
    var leanForward = false

    private let track: Track
    private lazy var noise = TrackNoise(seed: track.seed)

    private var chassis: SKNode!
    private var rearWheel: SKNode!
    private var frontWheel: SKNode!
    private var riderNode: SKNode?
    private let cameraNode = SKCameraNode()

    private var startTime: TimeInterval = 0
    private var lastUpdate: TimeInterval = 0
    private var running = false
    private var settled = false

    /// Airborne frames in a row — a couple of frames of daylight under a wheel
    /// on a bumpy straight shouldn't count as a jump.
    private var airborneFrames = 0
    private var isAirborne: Bool { airborneFrames > 6 }

    init(track: Track, size: CGSize) {
        self.track = track
        super.init(size: size)
        scaleMode = .resizeFill
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) unused") }

    // MARK: - Setup

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.53, green: 0.72, blue: 0.88, alpha: 1)
        physicsWorld.gravity = CGVector(dx: 0, dy: -270)
        physicsWorld.contactDelegate = self

        camera = cameraNode
        addChild(cameraNode)

        buildSky()
        buildTerrain()
        buildFinish()
        buildBike(at: CGPoint(x: 120, y: 150))

        startTime = 0
        running = true
    }

    private func buildSky() {
        // Parallax hills, drawn once and parented to the camera so they follow
        // it cheaply while sliding at a fraction of the world speed.
        for layer in 0..<3 {
            let depth = Double(layer)
            let path = CGMutablePath()
            let width = size.width * 3
            path.move(to: CGPoint(x: -width / 2, y: -size.height))
            var x = -width / 2
            while x <= width / 2 {
                let n = noise.fbm(Double(x) * 0.0012 * (1 + depth * 0.6) + depth * 40, octaves: 2)
                let y = CGFloat(n * (60 + depth * 34)) - size.height * 0.05 - CGFloat(depth * 26)
                path.addLine(to: CGPoint(x: x, y: y))
                x += 24
            }
            path.addLine(to: CGPoint(x: width / 2, y: -size.height))
            path.closeSubpath()

            let hill = SKShapeNode(path: path)
            let shade = 0.62 - depth * 0.12
            hill.fillColor = SKColor(red: CGFloat(shade * 0.62), green: CGFloat(shade * 0.78), blue: CGFloat(shade), alpha: 1)
            hill.strokeColor = .clear
            hill.zPosition = -100 + CGFloat(layer)
            hill.name = "parallax\(layer)"
            cameraNode.addChild(hill)
        }
    }

    private func buildTerrain() {
        let points = track.profile(noise: noise)

        let surface = CGMutablePath()
        surface.move(to: points[0])
        for point in points.dropFirst() { surface.addLine(to: point) }

        // Filled dirt: the surface line closed off well below the lowest point.
        let body = CGMutablePath()
        body.addPath(surface)
        body.addLine(to: CGPoint(x: points.last!.x, y: -2400))
        body.addLine(to: CGPoint(x: points.first!.x, y: -2400))
        body.closeSubpath()

        let dirt = SKShapeNode(path: body)
        dirt.fillColor = SKColor(red: 0.45, green: 0.33, blue: 0.22, alpha: 1)
        dirt.strokeColor = .clear
        dirt.zPosition = 1
        addChild(dirt)

        let grass = SKShapeNode(path: surface)
        grass.strokeColor = SKColor(red: 0.36, green: 0.62, blue: 0.28, alpha: 1)
        grass.lineWidth = 9
        grass.lineCap = .round
        grass.lineJoin = .round
        grass.zPosition = 2
        addChild(grass)

        // The collision surface is the exact same sample set as the drawing.
        let collider = SKNode()
        collider.physicsBody = SKPhysicsBody(edgeChainFrom: surface)
        collider.physicsBody?.categoryBitMask = Category.ground
        collider.physicsBody?.friction = 0.98
        collider.physicsBody?.restitution = 0.05
        addChild(collider)
    }

    private func buildFinish() {
        let x = CGFloat(track.length)
        let y = CGFloat(track.height(at: track.length, noise: noise))

        let post = SKShapeNode(rectOf: CGSize(width: 6, height: 190))
        post.fillColor = .white
        post.strokeColor = .clear
        post.position = CGPoint(x: x, y: y + 95)
        post.zPosition = 3
        addChild(post)

        let flag = SKShapeNode(rectOf: CGSize(width: 78, height: 46))
        flag.fillColor = SKColor(white: 0.95, alpha: 1)
        flag.strokeColor = SKColor(white: 0.15, alpha: 1)
        flag.lineWidth = 3
        flag.position = CGPoint(x: x + 42, y: y + 168)
        flag.zPosition = 3
        addChild(flag)

        for row in 0..<3 {
            for column in 0..<5 where (row + column) % 2 == 0 {
                let square = SKShapeNode(rectOf: CGSize(width: 15.6, height: 15.3))
                square.fillColor = SKColor(white: 0.12, alpha: 1)
                square.strokeColor = .clear
                square.position = CGPoint(x: x + 42 - 31.2 + CGFloat(column) * 15.6,
                                          y: y + 168 - 15.3 + CGFloat(row) * 15.3)
                square.zPosition = 4
                addChild(square)
            }
        }
    }

    private func buildBike(at position: CGPoint) {
        let wheelRadius: CGFloat = 17
        let wheelBase: CGFloat = 66
        let axleDrop: CGFloat = -14

        // The visible machine hangs off the chassis body, drawn to line up with
        // where the wheels physically are.
        let frame = SKNode()
        frame.addChild(BikeArt.body(rearAxle: CGPoint(x: -wheelBase / 2, y: axleDrop),
                                    frontAxle: CGPoint(x: wheelBase / 2, y: axleDrop)))

        let rider = BikeArt.rider()
        rider.position = CGPoint(x: -6, y: 6)
        frame.addChild(rider)
        riderNode = rider

        frame.position = position
        frame.zPosition = 10
        addChild(frame)

        // The collision shape is a plain box around the machine — the rider's
        // head sticking out of it is deliberate, so a scraped helmet is a
        // crash but a low-slung frame is not.
        let body = SKPhysicsBody(rectangleOf: CGSize(width: 58, height: 26),
                                 center: CGPoint(x: 0, y: 8))
        body.mass = 1.4
        body.categoryBitMask = Category.rider
        body.collisionBitMask = Category.ground
        body.contactTestBitMask = Category.ground
        body.allowsRotation = true
        body.angularDamping = 0.55
        body.restitution = 0
        frame.physicsBody = body
        chassis = frame

        func makeWheel(at offset: CGFloat, drive: Bool) -> SKNode {
            let wheel = BikeArt.wheel(radius: wheelRadius)
            wheel.position = CGPoint(x: position.x + offset, y: position.y + axleDrop)
            wheel.zPosition = 11

            let physics = SKPhysicsBody(circleOfRadius: wheelRadius)
            physics.mass = drive ? 0.55 : 0.4
            physics.friction = 1.0
            physics.restitution = 0.02
            physics.angularDamping = drive ? 0.06 : 0.12
            physics.categoryBitMask = Category.wheel
            physics.collisionBitMask = Category.ground
            wheel.physicsBody = physics
            addChild(wheel)
            return wheel
        }

        rearWheel = makeWheel(at: -wheelBase / 2, drive: true)
        frontWheel = makeWheel(at: wheelBase / 2, drive: false)

        // Rigid axles. Real suspension needs spring joints plus limits, which
        // wobble badly at this scale; rigid axles with a springy chassis mass
        // give a predictable arcade feel.
        for wheel in [rearWheel!, frontWheel!] {
            let pin = SKPhysicsJointPin.joint(withBodyA: chassis.physicsBody!,
                                              bodyB: wheel.physicsBody!,
                                              anchor: wheel.position)
            pin.frictionTorque = 0.0
            physicsWorld.add(pin)
        }

        cameraNode.position = CGPoint(x: position.x + 120, y: position.y + 60)
    }

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        guard running else { return }
        if startTime == 0 { startTime = currentTime }
        let delta = lastUpdate == 0 ? 1.0 / 60 : min(currentTime - lastUpdate, 1.0 / 20)
        lastUpdate = currentTime

        drive(delta: delta)
        updateRiderPose(delta: delta)
        updateAirborne()
        updateCamera(delta: delta)

        let elapsed = currentTime - startTime
        let progress = min(max(Double(chassis.position.x) / track.length, 0), 1)
        let speed = Double(chassis.physicsBody?.velocity.dx ?? 0)
        onTick?(progress, elapsed, speed)

        if chassis.position.x >= CGFloat(track.length) {
            finish(elapsed: elapsed)
        }
        // Off the side or fallen through the world.
        if chassis.position.y < -1200 { crash() }
    }

    private func drive(delta: TimeInterval) {
        guard let rear = rearWheel.physicsBody, let body = chassis.physicsBody else { return }

        // Torque is sized against the wheel's moment of inertia (about 79 at
        // this radius and mass) and against gravity, so the bike can actually
        // climb rather than politely rolling backwards down every hill.
        let step = CGFloat(delta * 60)
        let maxSpin: CGFloat = 34
        let grounded = airborneFrames == 0
        if throttle {
            // Torque rather than a velocity assignment, so wheelspin, hills and
            // landings all affect acceleration naturally.
            if rear.angularVelocity > -maxSpin {
                rear.applyAngularImpulse(-300 * step)
            }
            // Plus a direct shove while a wheel is down. Torque alone depends
            // on grip and on the joint solver agreeing with us; this guarantees
            // the throttle always does something the rider can feel.
            if grounded && body.velocity.dx < 620 {
                body.applyForce(CGVector(dx: 620, dy: 0))
            }
        }
        if brake {
            // Brake first, reverse only once nearly stopped.
            if body.velocity.dx > 20 {
                rear.angularVelocity *= 0.88
                body.velocity.dx *= 0.96
            } else if rear.angularVelocity < maxSpin * 0.4 {
                rear.applyAngularImpulse(120 * step)
            }
        }
        if !throttle && !brake {
            rear.angularVelocity *= 0.99
        }

        // Leaning: strong in the air for rotation control, gentler on the
        // ground where it mostly shifts weight over a wheel.
        let leanPower: CGFloat = isAirborne ? 45 : 20
        if leanBack { body.applyAngularImpulse(leanPower * step) }
        if leanForward { body.applyAngularImpulse(-leanPower * step) }

        // Air drag keeps top speed finite and landings sane.
        body.velocity.dx *= 0.9995
    }

    /// Shifts the rider's weight with the lean controls. Purely cosmetic, but
    /// without it the lean buttons feel like they do nothing at low speed.
    private func updateRiderPose(delta: TimeInterval) {
        guard let rider = riderNode else { return }
        var targetX: CGFloat = -6
        var targetRotation: CGFloat = 0
        if leanBack {
            targetX = -13
            targetRotation = 0.20
        } else if leanForward {
            targetX = 1
            targetRotation = -0.20
        }
        let ease = CGFloat(min(delta * 9, 1))
        rider.position.x += (targetX - rider.position.x) * ease
        rider.zRotation += (targetRotation - rider.zRotation) * ease
    }

    private func updateAirborne() {
        let rearContact = wheelTouchingGround(rearWheel)
        let frontContact = wheelTouchingGround(frontWheel)
        if rearContact || frontContact {
            airborneFrames = 0
        } else {
            airborneFrames += 1
        }
    }

    private func wheelTouchingGround(_ wheel: SKNode) -> Bool {
        // A short ray under the wheel is cheaper and steadier than tracking
        // contact callbacks for something checked every frame.
        let from = wheel.position
        let to = CGPoint(x: from.x, y: from.y - 26)
        var touching = false
        physicsWorld.enumerateBodies(alongRayStart: from, end: to) { body, _, _, stop in
            if body.categoryBitMask == Category.ground {
                touching = true
                stop.pointee = true
            }
        }
        return touching
    }

    private func updateCamera(delta: TimeInterval) {
        let speed = abs(Double(chassis.physicsBody?.velocity.dx ?? 0))
        // Ease the camera ahead of the bike as it goes faster, so fast sections
        // show more of what is coming.
        let lead = CGFloat(min(speed * 0.34, 210))
        let target = CGPoint(x: chassis.position.x + lead, y: chassis.position.y + 70)
        let smoothing = CGFloat(min(delta * 6.5, 1))
        cameraNode.position.x += (target.x - cameraNode.position.x) * smoothing
        cameraNode.position.y += (target.y - cameraNode.position.y) * smoothing * 0.7

        for layer in 0..<3 {
            guard let hill = cameraNode.childNode(withName: "parallax\(layer)") else { continue }
            let factor = 0.55 - Double(layer) * 0.16
            hill.position.x = -cameraNode.position.x * CGFloat(factor)
            hill.position.y = -cameraNode.position.y * CGFloat(factor * 0.35)
        }
    }

    // MARK: - Outcomes

    func didBegin(_ contact: SKPhysicsContact) {
        let mask = contact.bodyA.categoryBitMask | contact.bodyB.categoryBitMask
        guard mask == (Category.rider | Category.ground) else { return }
        // Ignore the settling frame at the very start of a run.
        guard settled else { return }
        crash()
    }

    private func crash() {
        guard running else { return }
        running = false
        chassis.physicsBody?.angularDamping = 3
        onCrash?()
    }

    private func finish(elapsed: TimeInterval) {
        guard running else { return }
        running = false
        onFinish?(elapsed)
    }

    override func didSimulatePhysics() {
        // One physics step of grace so spawning on the ground isn't a crash.
        if !settled { settled = true }
    }
}
