import SpriteKit

final class GameScene: SKScene, SKPhysicsContactDelegate {

    private var balls: [SKShapeNode] = []
    private var cueBall: SKShapeNode!
    private var pockets: [CGPoint] = []
    private var ballRadius: CGFloat = 14
    private var pocketRadius: CGFloat = 26

    private let aimLine = SKShapeNode()
    private var aiming = false
    private var aimVector = CGVector.zero

    private let pottedLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let messageLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private let rerackLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private var potted = 0

    private struct Cat {
        static let ball: UInt32 = 0x1
        static let cushion: UInt32 = 0x1 << 1
    }

    // Standard pool ball colors (1...15); 8 is black.
    private let ballColors: [SKColor] = [
        SKColor(red: 0.95, green: 0.80, blue: 0.20, alpha: 1), // 1 yellow
        SKColor(red: 0.20, green: 0.35, blue: 0.85, alpha: 1), // 2 blue
        SKColor(red: 0.85, green: 0.20, blue: 0.20, alpha: 1), // 3 red
        SKColor(red: 0.45, green: 0.25, blue: 0.65, alpha: 1), // 4 purple
        SKColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 1), // 5 orange
        SKColor(red: 0.20, green: 0.55, blue: 0.30, alpha: 1), // 6 green
        SKColor(red: 0.55, green: 0.15, blue: 0.20, alpha: 1), // 7 maroon
        SKColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1), // 8 black
        SKColor(red: 0.95, green: 0.80, blue: 0.20, alpha: 1),
        SKColor(red: 0.20, green: 0.35, blue: 0.85, alpha: 1),
        SKColor(red: 0.85, green: 0.20, blue: 0.20, alpha: 1),
        SKColor(red: 0.45, green: 0.25, blue: 0.65, alpha: 1),
        SKColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 1),
        SKColor(red: 0.20, green: 0.55, blue: 0.30, alpha: 1),
        SKColor(red: 0.55, green: 0.15, blue: 0.20, alpha: 1)
    ]

    override func didMove(to view: SKView) {
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self
        scaleMode = .resizeFill
        buildTable()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        if size.width > 0 { buildTable() }
    }

    // MARK: - Table

    private func buildTable() {
        removeAllChildren()
        balls.removeAll()

        backgroundColor = SKColor(red: 0.12, green: 0.10, blue: 0.08, alpha: 1)

        // Fit a 2:1 table inside the view with margins.
        let margin: CGFloat = 26
        let availW = size.width - margin * 2
        let availH = size.height - margin * 2
        var tableW = availW
        var tableH = tableW / 2
        if tableH > availH { tableH = availH; tableW = tableH * 2 }
        let rect = CGRect(x: (size.width - tableW) / 2,
                          y: (size.height - tableH) / 2,
                          width: tableW, height: tableH)

        ballRadius = tableH / 24
        pocketRadius = ballRadius * 1.9

        // Wooden frame
        let frame = SKShapeNode(rect: rect.insetBy(dx: -18, dy: -18), cornerRadius: 16)
        frame.fillColor = SKColor(red: 0.36, green: 0.22, blue: 0.12, alpha: 1)
        frame.strokeColor = SKColor(red: 0.22, green: 0.13, blue: 0.06, alpha: 1)
        frame.lineWidth = 4
        frame.zPosition = -2
        addChild(frame)

        // Felt
        let felt = SKShapeNode(rect: rect, cornerRadius: 6)
        felt.fillColor = SKColor(red: 0.10, green: 0.45, blue: 0.27, alpha: 1)
        felt.strokeColor = .clear
        felt.zPosition = -1
        addChild(felt)

        // Pockets (4 corners + 2 middle of long sides)
        pockets = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]
        for p in pockets {
            let hole = SKShapeNode(circleOfRadius: pocketRadius)
            hole.fillColor = .black
            hole.strokeColor = SKColor(white: 0, alpha: 0.6)
            hole.position = p
            hole.zPosition = 0
            addChild(hole)
        }

        addCushions(rect: rect)
        rackBalls(rect: rect)

        // HUD
        pottedLabel.fontSize = 18
        pottedLabel.fontColor = .white
        pottedLabel.horizontalAlignmentMode = .left
        pottedLabel.position = CGPoint(x: margin, y: size.height - margin - 6)
        pottedLabel.zPosition = 50
        addChild(pottedLabel)
        updatePottedLabel()

        rerackLabel.text = "RE-RACK"
        rerackLabel.name = "rerack"
        rerackLabel.fontSize = 16
        rerackLabel.fontColor = SKColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)
        rerackLabel.horizontalAlignmentMode = .right
        rerackLabel.position = CGPoint(x: size.width - margin, y: size.height - margin - 6)
        rerackLabel.zPosition = 50
        addChild(rerackLabel)

        messageLabel.fontSize = 30
        messageLabel.fontColor = .white
        messageLabel.position = CGPoint(x: size.width / 2, y: size.height / 2)
        messageLabel.zPosition = 60
        messageLabel.alpha = 0
        addChild(messageLabel)

        aimLine.strokeColor = SKColor(white: 1, alpha: 0.8)
        aimLine.lineWidth = 2
        aimLine.zPosition = 40
        addChild(aimLine)
    }

    private func addCushions(rect: CGRect) {
        let t: CGFloat = 10                     // cushion thickness
        let gap = pocketRadius * 1.2            // mouth around each pocket
        func cushion(_ r: CGRect) {
            let node = SKShapeNode(rect: r, cornerRadius: 3)
            node.fillColor = SKColor(red: 0.07, green: 0.34, blue: 0.20, alpha: 1)
            node.strokeColor = .clear
            let body = SKPhysicsBody(rectangleOf: r.size, center: CGPoint(x: r.midX, y: r.midY))
            body.isDynamic = false
            body.restitution = 0.92
            body.friction = 0.2
            body.categoryBitMask = Cat.cushion
            node.physicsBody = body
            addChild(node)
        }
        // Short rails (left/right)
        cushion(CGRect(x: rect.minX, y: rect.minY + gap, width: t, height: rect.height - gap * 2))
        cushion(CGRect(x: rect.maxX - t, y: rect.minY + gap, width: t, height: rect.height - gap * 2))
        // Long rails (top/bottom), each split by the middle pocket
        let half = (rect.width - gap * 2 - (2 * gap)) / 2
        cushion(CGRect(x: rect.minX + gap, y: rect.minY, width: half, height: t))
        cushion(CGRect(x: rect.midX + gap, y: rect.minY, width: half, height: t))
        cushion(CGRect(x: rect.minX + gap, y: rect.maxY - t, width: half, height: t))
        cushion(CGRect(x: rect.midX + gap, y: rect.maxY - t, width: half, height: t))
    }

    private func makeBall(color: SKColor, at p: CGPoint, isCue: Bool) -> SKShapeNode {
        let r = ballRadius
        let node = SKShapeNode(circleOfRadius: r)
        node.fillColor = isCue ? .white : color
        node.strokeColor = SKColor(white: 0, alpha: 0.25)
        node.lineWidth = 1
        node.position = p
        node.zPosition = 5
        // Shine highlight
        let shine = SKShapeNode(circleOfRadius: r * 0.35)
        shine.fillColor = SKColor(white: 1, alpha: 0.35)
        shine.strokeColor = .clear
        shine.position = CGPoint(x: -r * 0.3, y: r * 0.3)
        node.addChild(shine)

        let body = SKPhysicsBody(circleOfRadius: r)
        body.restitution = 0.95
        body.friction = 0.4
        body.linearDamping = 1.4          // felt rolling resistance
        body.angularDamping = 1.4
        body.mass = 0.16
        body.categoryBitMask = Cat.ball
        body.collisionBitMask = Cat.ball | Cat.cushion
        node.physicsBody = body
        addChild(node)
        return node
    }

    private func rackBalls(rect: CGRect) {
        // Cue ball on the head spot (left quarter)
        cueBall = makeBall(color: .white, at: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.midY), isCue: true)
        cueBall.name = "cue"

        // Triangle rack on the foot spot (right quarter), apex pointing left
        let apex = CGPoint(x: rect.minX + rect.width * 0.72, y: rect.midY)
        let dx = ballRadius * 1.75 * 0.866    // row spacing
        let dy = ballRadius * 2.02
        var order = Array(0..<15)
        order.shuffle()
        // keep the 8-ball (index 7 colour = black) roughly central — simplest: leave shuffle
        var idx = 0
        for row in 0..<5 {
            for i in 0...row {
                let x = apex.x + CGFloat(row) * dx
                let y = apex.y + (CGFloat(i) - CGFloat(row) / 2) * dy
                let b = makeBall(color: ballColors[order[idx] % ballColors.count], at: CGPoint(x: x, y: y), isCue: false)
                balls.append(b)
                idx += 1
            }
        }
    }

    private func updatePottedLabel() {
        pottedLabel.text = "Potted: \(potted) / 15"
    }

    // MARK: - Aiming & shooting

    private var ballsMoving: Bool {
        for b in balls + [cueBall] where b.parent != nil {
            if let v = b.physicsBody?.velocity, hypot(v.dx, v.dy) > 6 { return true }
        }
        return false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        if let node = atPoint(p) as? SKLabelNode, node.name == "rerack" {
            potted = 0; updatePottedLabel(); buildTable(); return
        }
        guard !ballsMoving, cueBall.parent != nil else { return }
        aiming = true
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard aiming, let t = touches.first else { return }
        let p = t.location(in: self)
        // Pull back from the cue ball to aim forward (slingshot).
        aimVector = CGVector(dx: cueBall.position.x - p.x, dy: cueBall.position.y - p.y)
        let mag = min(hypot(aimVector.dx, aimVector.dy), 160)
        let ang = atan2(aimVector.dy, aimVector.dx)
        let path = CGMutablePath()
        path.move(to: cueBall.position)
        path.addLine(to: CGPoint(x: cueBall.position.x + cos(ang) * (mag + 30),
                                 y: cueBall.position.y + sin(ang) * (mag + 30)))
        aimLine.path = path
        let power = mag / 160
        aimLine.strokeColor = SKColor(red: 1, green: 1 - power, blue: 0.2, alpha: 0.85)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer { aiming = false; aimLine.path = nil }
        guard aiming, cueBall.parent != nil else { return }
        let mag = min(hypot(aimVector.dx, aimVector.dy), 160)
        guard mag > 8 else { return }
        let ang = atan2(aimVector.dy, aimVector.dx)
        let impulse: CGFloat = mag * 0.014
        cueBall.physicsBody?.applyImpulse(CGVector(dx: cos(ang) * impulse, dy: sin(ang) * impulse))
    }

    // MARK: - Pocketing

    override func update(_ currentTime: TimeInterval) {
        for ball in balls + [cueBall] where ball.parent != nil {
            for pocket in pockets where hypot(ball.position.x - pocket.x, ball.position.y - pocket.y) < pocketRadius * 0.8 {
                pot(ball)
                break
            }
        }
    }

    private func pot(_ ball: SKShapeNode) {
        if ball === cueBall {
            // Scratch — respawn the cue ball.
            ball.physicsBody?.velocity = .zero
            let shrink = SKAction.scale(to: 0.1, duration: 0.12)
            ball.run(.sequence([shrink, .run { [weak self] in
                guard let self = self else { return }
                ball.position = CGPoint(x: self.frame.midX - self.size.width * 0.22, y: self.frame.midY)
                ball.setScale(1)
            }]))
            flash("SCRATCH!")
            return
        }
        ball.physicsBody = nil
        ball.run(.sequence([.scale(to: 0.05, duration: 0.14), .removeFromParent()]))
        balls.removeAll { $0 === ball }
        potted += 1
        updatePottedLabel()
        if balls.isEmpty { flash("YOU WIN! 🎉") }
    }

    private func flash(_ text: String) {
        messageLabel.text = text
        messageLabel.removeAllActions()
        messageLabel.alpha = 1
        messageLabel.run(.sequence([.wait(forDuration: 1.2), .fadeOut(withDuration: 0.6)]))
    }
}
