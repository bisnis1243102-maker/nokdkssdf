import SpriteKit

final class GameScene: SKScene, SKPhysicsContactDelegate {

    // MARK: Types
    private enum Player { case you, ai }
    private enum Grp { case solids, stripes }

    private struct Cat {
        static let cue: UInt32 = 0x1 << 0
        static let object: UInt32 = 0x1 << 1
        static let cushion: UInt32 = 0x1 << 2
    }

    // MARK: State
    private var balls: [SKShapeNode] = []          // object balls on table (no cue)
    private var cueBall: SKShapeNode!
    private var pockets: [CGPoint] = []
    private var tableRect: CGRect = .zero
    private var ballRadius: CGFloat = 14
    private var pocketRadius: CGFloat = 26

    private var currentPlayer: Player = .you
    private var youGroup: Grp? = nil               // nil = open table
    private var gameOver = false

    private var shotInProgress = false
    private var timeSinceShot: Double = 0
    private var lastUpdate: TimeInterval = 0
    private var pottedThisShot: [Int] = []
    private var potted8 = false
    private var cueScratched = false
    private var firstHit: Int? = nil

    private var coins = UserDefaults.standard.object(forKey: "billiard.coins") as? Int ?? 100

    // Aiming
    private let aimLine = SKShapeNode()
    private var aiming = false
    private var aimVector = CGVector.zero

    // HUD
    private let coinsLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let turnLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let groupLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let overlay = SKNode()

    private func colorFor(_ n: Int) -> SKColor {
        switch (n - 1) % 7 {
        case 0: return SKColor(red: 0.95, green: 0.78, blue: 0.18, alpha: 1) // yellow
        case 1: return SKColor(red: 0.20, green: 0.35, blue: 0.85, alpha: 1) // blue
        case 2: return SKColor(red: 0.85, green: 0.20, blue: 0.20, alpha: 1) // red
        case 3: return SKColor(red: 0.45, green: 0.25, blue: 0.65, alpha: 1) // purple
        case 4: return SKColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 1) // orange
        case 5: return SKColor(red: 0.18, green: 0.55, blue: 0.30, alpha: 1) // green
        default: return SKColor(red: 0.55, green: 0.15, blue: 0.20, alpha: 1) // maroon
        }
    }
    private func grp(_ n: Int) -> Grp? { (1...7).contains(n) ? .solids : ((9...15).contains(n) ? .stripes : nil) }
    private var aiGroup: Grp? { youGroup == nil ? nil : (youGroup == .solids ? .stripes : .solids) }
    private func shooterGroup(_ p: Player) -> Grp? { p == .you ? youGroup : aiGroup }
    private func number(of node: SKShapeNode) -> Int { Int(node.name?.replacingOccurrences(of: "ball_", with: "") ?? "") ?? 0 }
    private func remaining(_ g: Grp) -> Int { balls.filter { grp(number(of: $0)) == g }.count }

    // MARK: Lifecycle

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

    // MARK: Table

    private func buildTable() {
        removeAllChildren()
        balls.removeAll()
        gameOver = false
        youGroup = nil
        currentPlayer = .you
        shotInProgress = false
        backgroundColor = SKColor(red: 0.12, green: 0.10, blue: 0.08, alpha: 1)

        let margin: CGFloat = 26
        var tableW = size.width - margin * 2
        var tableH = tableW / 2
        if tableH > size.height - margin * 2 { tableH = size.height - margin * 2; tableW = tableH * 2 }
        let rect = CGRect(x: (size.width - tableW) / 2, y: (size.height - tableH) / 2, width: tableW, height: tableH)
        tableRect = rect
        ballRadius = tableH / 24
        pocketRadius = ballRadius * 1.9

        let frame = SKShapeNode(rect: rect.insetBy(dx: -18, dy: -18), cornerRadius: 16)
        frame.fillColor = SKColor(red: 0.36, green: 0.22, blue: 0.12, alpha: 1)
        frame.strokeColor = SKColor(red: 0.22, green: 0.13, blue: 0.06, alpha: 1)
        frame.lineWidth = 4; frame.zPosition = -2
        addChild(frame)

        let felt = SKShapeNode(rect: rect, cornerRadius: 6)
        felt.fillColor = SKColor(red: 0.10, green: 0.45, blue: 0.27, alpha: 1)
        felt.strokeColor = .clear; felt.zPosition = -1
        addChild(felt)

        pockets = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)
        ]
        for p in pockets {
            let hole = SKShapeNode(circleOfRadius: pocketRadius)
            hole.fillColor = .black; hole.strokeColor = SKColor(white: 0, alpha: 0.6)
            hole.position = p
            addChild(hole)
        }

        addCushions(rect: rect)
        rackBalls(rect: rect)

        // HUD
        coinsLabel.fontSize = 18; coinsLabel.fontColor = SKColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)
        coinsLabel.horizontalAlignmentMode = .left
        coinsLabel.position = CGPoint(x: margin, y: size.height - margin - 4); coinsLabel.zPosition = 50
        addChild(coinsLabel)

        turnLabel.fontSize = 18; turnLabel.fontColor = .white
        turnLabel.horizontalAlignmentMode = .center
        turnLabel.position = CGPoint(x: size.width / 2, y: size.height - margin - 4); turnLabel.zPosition = 50
        addChild(turnLabel)

        groupLabel.fontSize = 14; groupLabel.fontColor = SKColor(white: 1, alpha: 0.85)
        groupLabel.horizontalAlignmentMode = .right
        groupLabel.position = CGPoint(x: size.width - margin, y: size.height - margin - 4); groupLabel.zPosition = 50
        addChild(groupLabel)

        aimLine.strokeColor = SKColor(white: 1, alpha: 0.8); aimLine.lineWidth = 2; aimLine.zPosition = 40
        addChild(aimLine)

        overlay.zPosition = 100
        addChild(overlay)
        updateHUD()
    }

    private func addCushions(rect: CGRect) {
        let t: CGFloat = 10
        let gap = pocketRadius * 1.2
        func cushion(_ r: CGRect) {
            let node = SKShapeNode(rect: r, cornerRadius: 3)
            node.fillColor = SKColor(red: 0.07, green: 0.34, blue: 0.20, alpha: 1); node.strokeColor = .clear
            let body = SKPhysicsBody(rectangleOf: r.size, center: CGPoint(x: r.midX, y: r.midY))
            body.isDynamic = false; body.restitution = 0.92; body.friction = 0.1
            body.categoryBitMask = Cat.cushion
            node.physicsBody = body
            addChild(node)
        }
        cushion(CGRect(x: rect.minX, y: rect.minY + gap, width: t, height: rect.height - gap * 2))
        cushion(CGRect(x: rect.maxX - t, y: rect.minY + gap, width: t, height: rect.height - gap * 2))
        let half = (rect.width - gap * 4) / 2
        cushion(CGRect(x: rect.minX + gap, y: rect.minY, width: half, height: t))
        cushion(CGRect(x: rect.midX + gap, y: rect.minY, width: half, height: t))
        cushion(CGRect(x: rect.minX + gap, y: rect.maxY - t, width: half, height: t))
        cushion(CGRect(x: rect.midX + gap, y: rect.maxY - t, width: half, height: t))
    }

    private func makeBall(number n: Int, at p: CGPoint) -> SKShapeNode {
        let r = ballRadius
        let isCue = n == 0
        let node = SKShapeNode(circleOfRadius: r)
        node.position = p; node.zPosition = 5
        node.strokeColor = SKColor(white: 0, alpha: 0.25); node.lineWidth = 1
        node.name = isCue ? "cue" : "ball_\(n)"
        if isCue { node.fillColor = .white }
        else if n == 8 { node.fillColor = SKColor(white: 0.08, alpha: 1) }
        else if grp(n) == .solids { node.fillColor = colorFor(n) }
        else { // stripe: white ball with a colored band
            node.fillColor = .white
            let band = SKShapeNode(rectOf: CGSize(width: r * 1.9, height: r * 0.95), cornerRadius: 2)
            band.fillColor = colorFor(n); band.strokeColor = .clear; band.zPosition = 1
            node.addChild(band)
        }
        if !isCue {
            let disc = SKShapeNode(circleOfRadius: r * 0.5)
            disc.fillColor = .white; disc.strokeColor = .clear; disc.zPosition = 2
            node.addChild(disc)
            let num = SKLabelNode(fontNamed: "AvenirNext-Bold")
            num.text = "\(n)"; num.fontSize = r * 0.7; num.fontColor = .black
            num.verticalAlignmentMode = .center; num.zPosition = 3
            node.addChild(num)
        }
        let shine = SKShapeNode(circleOfRadius: r * 0.32)
        shine.fillColor = SKColor(white: 1, alpha: 0.3); shine.strokeColor = .clear
        shine.position = CGPoint(x: -r * 0.32, y: r * 0.32); shine.zPosition = 4
        node.addChild(shine)

        let body = SKPhysicsBody(circleOfRadius: r)
        body.restitution = 0.95; body.friction = 0.2
        body.linearDamping = 0.7; body.angularDamping = 0.7; body.mass = 0.16
        body.categoryBitMask = isCue ? Cat.cue : Cat.object
        body.collisionBitMask = Cat.cue | Cat.object | Cat.cushion
        body.contactTestBitMask = isCue ? Cat.object : 0
        node.physicsBody = body
        addChild(node)
        return node
    }

    private func rackBalls(rect: CGRect) {
        cueBall = makeBall(number: 0, at: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.midY))

        // Triangle rack with the 8 in the centre, others shuffled.
        var nums = Array(1...15).filter { $0 != 8 }
        nums.shuffle()
        var layout: [Int] = []
        // positions index 0..14; index 4 is the centre of the triangle
        var fill = nums
        for i in 0..<15 { layout.append(i == 4 ? 8 : fill.removeFirst()) }

        let apex = CGPoint(x: rect.minX + rect.width * 0.72, y: rect.midY)
        let dx = ballRadius * 1.75 * 0.9
        let dy = ballRadius * 2.05
        var idx = 0
        for row in 0..<5 {
            for i in 0...row {
                let x = apex.x + CGFloat(row) * dx
                let y = apex.y + (CGFloat(i) - CGFloat(row) / 2) * dy
                let b = makeBall(number: layout[idx], at: CGPoint(x: x, y: y))
                balls.append(b)
                idx += 1
            }
        }
    }

    // MARK: HUD

    private func updateHUD() {
        coinsLabel.text = "🪙 \(coins)"
        turnLabel.text = gameOver ? "" : (currentPlayer == .you ? "YOUR TURN" : "OPPONENT…")
        turnLabel.fontColor = currentPlayer == .you ? SKColor(red: 0.5, green: 1, blue: 0.6, alpha: 1) : SKColor(white: 0.8, alpha: 1)
        if let g = youGroup {
            groupLabel.text = "You: " + (g == .solids ? "SOLIDS" : "STRIPES")
        } else {
            groupLabel.text = "Open table"
        }
    }

    // MARK: Shooting

    private var ballsMoving: Bool {
        for b in allBalls where b.parent != nil {
            if let v = b.physicsBody?.velocity, hypot(v.dx, v.dy) > 6 { return true }
        }
        return false
    }
    private var allBalls: [SKShapeNode] {
        var a = balls; if let c = cueBall { a.append(c) }; return a
    }

    private func performShot(angle: CGFloat, power: CGFloat) {
        guard !shotInProgress, !gameOver, cueBall.parent != nil else { return }
        pottedThisShot = []; potted8 = false; cueScratched = false; firstHit = nil
        shotInProgress = true; timeSinceShot = 0
        let impulse = max(0.06, min(1, power)) * 13.5
        cueBall.physicsBody?.velocity = .zero
        cueBall.physicsBody?.applyImpulse(CGVector(dx: cos(angle) * impulse, dy: sin(angle) * impulse))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        let p = t.location(in: self)
        if let n = atPoint(p) as? SKLabelNode, n.name == "playagain" { buildTable(); return }
        guard !gameOver, currentPlayer == .you, !shotInProgress, !ballsMoving, cueBall.parent != nil else { return }
        aiming = true
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard aiming, let t = touches.first else { return }
        let p = t.location(in: self)
        aimVector = CGVector(dx: cueBall.position.x - p.x, dy: cueBall.position.y - p.y)
        let mag = min(hypot(aimVector.dx, aimVector.dy), 220)
        let ang = atan2(aimVector.dy, aimVector.dx)
        let path = CGMutablePath()
        path.move(to: cueBall.position)
        path.addLine(to: CGPoint(x: cueBall.position.x + cos(ang) * (mag + 40), y: cueBall.position.y + sin(ang) * (mag + 40)))
        aimLine.path = path
        let power = mag / 220
        aimLine.strokeColor = SKColor(red: 1, green: 1 - power, blue: 0.2, alpha: 0.85)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer { aiming = false; aimLine.path = nil }
        guard aiming else { return }
        let mag = min(hypot(aimVector.dx, aimVector.dy), 220)
        guard mag > 4 else { return }
        performShot(angle: atan2(aimVector.dy, aimVector.dx), power: mag / 220)
    }

    // MARK: Contacts (first ball hit)

    func didBegin(_ contact: SKPhysicsContact) {
        guard shotInProgress, firstHit == nil else { return }
        let nodes = [contact.bodyA.node, contact.bodyB.node].compactMap { $0 as? SKShapeNode }
        guard nodes.contains(where: { $0.name == "cue" }) else { return }
        if let obj = nodes.first(where: { $0.name?.hasPrefix("ball_") == true }) {
            firstHit = number(of: obj)
        }
    }

    // MARK: Update / pocketing

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 0 : currentTime - lastUpdate
        lastUpdate = currentTime
        if shotInProgress { timeSinceShot += dt }

        for ball in allBalls where ball.parent != nil {
            for pocket in pockets where hypot(ball.position.x - pocket.x, ball.position.y - pocket.y) < pocketRadius * 0.8 {
                pot(ball); break
            }
        }

        if shotInProgress, timeSinceShot > 0.35, !ballsMoving {
            resolveShot()
        }
    }

    private func pot(_ ball: SKShapeNode) {
        if ball === cueBall {
            cueScratched = true
            ball.physicsBody?.velocity = .zero
            ball.position = CGPoint(x: tableRect.minX + tableRect.width * 0.25, y: tableRect.midY)
            return
        }
        let n = number(of: ball)
        pottedThisShot.append(n)
        if n == 8 { potted8 = true }
        ball.physicsBody = nil
        ball.run(.sequence([.scale(to: 0.05, duration: 0.12), .removeFromParent()]))
        balls.removeAll { $0 === ball }
    }

    // MARK: Rules resolution

    private func resolveShot() {
        shotInProgress = false
        let shooter = currentPlayer

        // Assign groups on a legal pot while the table is open.
        if youGroup == nil && !potted8 && !cueScratched {
            let s = pottedThisShot.filter { grp($0) == .solids }.count
            let st = pottedThisShot.filter { grp($0) == .stripes }.count
            if s > 0 && st == 0 { youGroup = (shooter == .you) ? .solids : .stripes }
            else if st > 0 && s == 0 { youGroup = (shooter == .you) ? .stripes : .solids }
        }

        let myGroup = shooterGroup(shooter)

        // 8-ball potted → win/lose decision.
        if potted8 {
            let clearedGroup = (myGroup != nil) && remaining(myGroup!) == 0
            if clearedGroup && !cueScratched { endGame(winner: shooter) }
            else { endGame(winner: shooter == .you ? .ai : .you) }
            return
        }

        // Fouls
        var foul = cueScratched
        if let mg = myGroup, let fh = firstHit, grp(fh) != mg { foul = true }   // hit wrong group first
        if firstHit == nil && pottedThisShot.isEmpty { foul = true }            // no contact

        let pottedOwn: Bool
        if let mg = myGroup { pottedOwn = pottedThisShot.contains { grp($0) == mg } }
        else { pottedOwn = !pottedThisShot.isEmpty }   // open table: any pot continues

        let keepTurn = !foul && pottedOwn
        if !keepTurn { currentPlayer = (shooter == .you) ? .ai : .you }
        updateHUD()

        if currentPlayer == .ai && !gameOver {
            run(.sequence([.wait(forDuration: 0.8), .run { [weak self] in self?.aiShoot() }]))
        }
    }

    // MARK: AI

    private func aiShoot() {
        guard currentPlayer == .ai, !gameOver, !shotInProgress, cueBall.parent != nil else { return }
        let mg = aiGroup
        var targets = balls
        if let g = mg {
            let own = balls.filter { grp(number(of: $0)) == g }
            targets = own.isEmpty ? balls.filter { number(of: $0) == 8 } : own
        } else {
            targets = balls.filter { number(of: $0) != 8 }
        }
        if targets.isEmpty { targets = balls }

        // Choose the (ball, pocket) with the straightest line.
        var bestAngle = CGFloat.random(in: 0...(2 * .pi))
        var bestScore = -2.0 as CGFloat
        var bestDist: CGFloat = 200
        let cp = cueBall.position
        for ball in targets {
            let bp = ball.position
            let cueToBall = CGVector(dx: bp.x - cp.x, dy: bp.y - cp.y)
            let cbLen = max(1, hypot(cueToBall.dx, cueToBall.dy))
            for pocket in pockets {
                let ballToPocket = CGVector(dx: pocket.x - bp.x, dy: pocket.y - bp.y)
                let bpLen = max(1, hypot(ballToPocket.dx, ballToPocket.dy))
                let dot = (cueToBall.dx * ballToPocket.dx + cueToBall.dy * ballToPocket.dy) / (cbLen * bpLen)
                if dot > bestScore {
                    bestScore = dot
                    let ghost = CGPoint(x: bp.x - ballToPocket.dx / bpLen * ballRadius * 2,
                                        y: bp.y - ballToPocket.dy / bpLen * ballRadius * 2)
                    bestAngle = atan2(ghost.y - cp.y, ghost.x - cp.x)
                    bestDist = cbLen + bpLen
                }
            }
        }
        // Imperfect aim so the AI is beatable.
        let jitter = CGFloat.random(in: -0.05...0.05)
        let power = min(1, 0.45 + bestDist / 700 + CGFloat.random(in: -0.05...0.1))
        performShot(angle: bestAngle + jitter, power: power)
    }

    // MARK: End

    private func endGame(winner: Player) {
        gameOver = true
        shotInProgress = false
        var reward = 0
        if winner == .you { reward = 50; coins += reward }
        UserDefaults.standard.set(coins, forKey: "billiard.coins")
        updateHUD()

        overlay.removeAllChildren()
        let dim = SKShapeNode(rect: CGRect(origin: .zero, size: size))
        dim.fillColor = SKColor(white: 0, alpha: 0.55); dim.strokeColor = .clear
        overlay.addChild(dim)

        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = winner == .you ? "YOU WIN!" : "YOU LOSE"
        title.fontSize = 40; title.fontColor = winner == .you ? SKColor(red: 0.5, green: 1, blue: 0.6, alpha: 1) : SKColor(red: 1, green: 0.5, blue: 0.5, alpha: 1)
        title.position = CGPoint(x: size.width / 2, y: size.height / 2 + 30)
        overlay.addChild(title)

        if reward > 0 {
            let r = SKLabelNode(fontNamed: "AvenirNext-Bold")
            r.text = "+\(reward) 🪙"; r.fontSize = 24; r.fontColor = SKColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)
            r.position = CGPoint(x: size.width / 2, y: size.height / 2 - 8)
            overlay.addChild(r)
        }

        let again = SKLabelNode(fontNamed: "AvenirNext-Bold")
        again.text = "▶  PLAY AGAIN"; again.name = "playagain"
        again.fontSize = 22; again.fontColor = .white
        again.position = CGPoint(x: size.width / 2, y: size.height / 2 - 56)
        overlay.addChild(again)
    }
}
