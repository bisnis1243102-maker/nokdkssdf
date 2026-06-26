import SpriteKit

final class GameScene: SKScene, SKPhysicsContactDelegate {

    weak var gameState: GameState?

    private var player: Player!
    private let moveStick = Joystick()
    private let aimStick = Joystick()

    private var isRunning = false
    private var lastUpdate: TimeInterval = 0
    private var lastFire: TimeInterval = 0

    // Wave management
    private var wave = 0
    private var pendingSpawns = 0
    private var spawnAccumulator: TimeInterval = 0
    private var spawnInterval: TimeInterval = 1.0

    private var aimAngle: CGFloat = 0

    // MARK: - Setup

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.07, green: 0.08, blue: 0.12, alpha: 1.0)
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self
        scaleMode = .resizeFill
        buildArena()
        addChild(moveStick)
        addChild(aimStick)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        // Keep the boundary in sync with the live view size.
        buildArena()
    }

    private func buildArena() {
        childNode(withName: "arena")?.removeFromParent()

        let arena = SKNode()
        arena.name = "arena"
        arena.zPosition = -10
        addChild(arena)

        // Subtle grid for a sense of motion.
        let spacing: CGFloat = 60
        let grid = SKShapeNode()
        let path = CGMutablePath()
        var x: CGFloat = 0
        while x <= size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += spacing }
        var y: CGFloat = 0
        while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += spacing }
        grid.path = path
        grid.strokeColor = SKColor(white: 1.0, alpha: 0.05)
        grid.lineWidth = 1
        arena.addChild(grid)

        // Border that keeps the action on-screen.
        let border = SKShapeNode(rect: CGRect(origin: .zero, size: size))
        border.strokeColor = SKColor(red: 0.30, green: 0.66, blue: 1.0, alpha: 0.5)
        border.lineWidth = 3
        arena.addChild(border)

        let walls = SKPhysicsBody(edgeLoopFrom: CGRect(origin: .zero, size: size))
        walls.categoryBitMask = PhysicsCategory.wall
        walls.friction = 0
        physicsBody = walls
    }

    // MARK: - Game lifecycle

    func startGame() {
        // Clear any leftover entities.
        enumerateChildNodes(withName: "//enemy") { node, _ in node.removeFromParent() }
        enumerateChildNodes(withName: "//bullet") { node, _ in node.removeFromParent() }
        player?.removeFromParent()

        player = Player()
        player.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(player)

        wave = 0
        pendingSpawns = 0
        spawnAccumulator = 0
        lastFire = 0
        gameState?.reset()
        isRunning = true
        startNextWave()
    }

    private func startNextWave() {
        wave += 1
        gameState?.wave = wave
        pendingSpawns = 3 + wave * 2
        spawnInterval = max(0.35, 1.1 - Double(wave) * 0.06)
        spawnAccumulator = 0
    }

    private func spawnEnemy() {
        // Shooters become more common in later waves.
        let shooterChance = min(0.5, 0.12 + Double(wave) * 0.04)
        let kind: EnemyKind = Double.random(in: 0...1) < shooterChance ? .shooter : .chaser
        let enemy = Enemy(kind: kind)
        enemy.name = "enemy"
        enemy.position = randomEdgePosition()
        addChild(enemy)
    }

    private func randomEdgePosition() -> CGPoint {
        let m: CGFloat = 30
        switch Int.random(in: 0..<4) {
        case 0: return CGPoint(x: .random(in: m...size.width - m), y: size.height - m)
        case 1: return CGPoint(x: .random(in: m...size.width - m), y: m)
        case 2: return CGPoint(x: m, y: .random(in: m...size.height - m))
        default: return CGPoint(x: size.width - m, y: .random(in: m...size.height - m))
        }
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 0 : currentTime - lastUpdate
        lastUpdate = currentTime
        guard isRunning, let player = player else { return }

        // Movement
        player.physicsBody?.velocity = CGVector(
            dx: moveStick.vector.dx * GameConfig.playerSpeed,
            dy: moveStick.vector.dy * GameConfig.playerSpeed)

        // Aiming + firing
        if aimStick.isActive && aimStick.magnitude > 0.2 {
            aimAngle = aimStick.angle
            player.aim(angle: aimAngle)
            if currentTime - lastFire >= GameConfig.fireInterval {
                fireBullet(angle: aimAngle, from: player.position, fromPlayer: true)
                lastFire = currentTime
            }
        } else {
            player.aim(angle: aimAngle)
        }

        updateEnemies(dt: dt, now: currentTime)
        cullBullets(now: currentTime)
        handleSpawning(dt: dt)
    }

    private func handleSpawning(dt: TimeInterval) {
        if pendingSpawns > 0 {
            spawnAccumulator += dt
            if spawnAccumulator >= spawnInterval {
                spawnAccumulator = 0
                spawnEnemy()
                pendingSpawns -= 1
            }
        } else if !hasLivingEnemies() {
            startNextWave()
        }
    }

    private func hasLivingEnemies() -> Bool {
        var found = false
        enumerateChildNodes(withName: "//enemy") { _, stop in found = true; stop.pointee = true }
        return found
    }

    private func updateEnemies(dt: TimeInterval, now: TimeInterval) {
        guard let player = player else { return }
        enumerateChildNodes(withName: "//enemy") { [weak self] node, _ in
            guard let self = self, let enemy = node as? Enemy else { return }
            let dx = player.position.x - enemy.position.x
            let dy = player.position.y - enemy.position.y
            let dist = max(1, hypot(dx, dy))
            let ux = dx / dist, uy = dy / dist

            switch enemy.kind {
            case .chaser:
                enemy.physicsBody?.velocity = CGVector(dx: ux * GameConfig.chaserSpeed,
                                                       dy: uy * GameConfig.chaserSpeed)
            case .shooter:
                // Keep preferred range, strafe slightly, and shoot.
                let range = GameConfig.shooterPreferredRange
                let speed = GameConfig.shooterSpeed
                if dist > range + 20 {
                    enemy.physicsBody?.velocity = CGVector(dx: ux * speed, dy: uy * speed)
                } else if dist < range - 20 {
                    enemy.physicsBody?.velocity = CGVector(dx: -ux * speed, dy: -uy * speed)
                } else {
                    enemy.physicsBody?.velocity = CGVector(dx: -uy * speed * 0.6, dy: ux * speed * 0.6)
                }
                if now - enemy.lastShot >= GameConfig.shooterFireInterval {
                    enemy.lastShot = now
                    let angle = atan2(dy, dx)
                    self.fireBullet(angle: angle, from: enemy.position, fromPlayer: false)
                }
            }
        }
    }

    private func cullBullets(now: TimeInterval) {
        enumerateChildNodes(withName: "//bullet") { node, _ in
            if let b = node as? Bullet, now - b.spawnTime > GameConfig.bulletLifetime {
                node.removeFromParent()
            }
        }
    }

    private func fireBullet(angle: CGFloat, from origin: CGPoint, fromPlayer: Bool) {
        let bullet = Bullet(fromPlayer: fromPlayer, now: lastUpdate)
        bullet.name = "bullet"
        let offset = GameConfig.playerRadius + GameConfig.bulletRadius + 2
        bullet.position = CGPoint(x: origin.x + cos(angle) * offset,
                                  y: origin.y + sin(angle) * offset)
        let speed = fromPlayer ? GameConfig.bulletSpeed : GameConfig.enemyBulletSpeed
        bullet.physicsBody?.velocity = CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed)
        addChild(bullet)
    }

    // MARK: - Contacts

    func didBegin(_ contact: SKPhysicsContact) {
        let a = contact.bodyA
        let b = contact.bodyB
        let combined = a.categoryBitMask | b.categoryBitMask

        if combined == (PhysicsCategory.playerBullet | PhysicsCategory.enemy) {
            let bulletNode = (a.categoryBitMask == PhysicsCategory.playerBullet ? a.node : b.node)
            let enemyNode = (a.categoryBitMask == PhysicsCategory.enemy ? a.node : b.node)
            handlePlayerBulletHit(bullet: bulletNode as? Bullet, enemy: enemyNode as? Enemy)

        } else if combined == (PhysicsCategory.enemy | PhysicsCategory.player) {
            let enemyNode = (a.categoryBitMask == PhysicsCategory.enemy ? a.node : b.node)
            handleEnemyTouchedPlayer(enemy: enemyNode as? Enemy)

        } else if combined == (PhysicsCategory.enemyBullet | PhysicsCategory.player) {
            let bulletNode = (a.categoryBitMask == PhysicsCategory.enemyBullet ? a.node : b.node)
            applyDamageToPlayer(GameConfig.enemyBulletDamage)
            bulletNode?.removeFromParent()
        }
    }

    private func handlePlayerBulletHit(bullet: Bullet?, enemy: Enemy?) {
        guard let enemy = enemy else { return }
        bullet?.removeFromParent()
        if enemy.takeDamage(bullet?.damage ?? GameConfig.bulletDamage) {
            gameState?.score += enemy.pointValue
            spawnExplosion(at: enemy.position, color: .orange)
            enemy.removeFromParent()
        }
    }

    private func handleEnemyTouchedPlayer(enemy: Enemy?) {
        guard let enemy = enemy else { return }
        if enemy.kind == .chaser {
            applyDamageToPlayer(GameConfig.chaserContactDamage)
            spawnExplosion(at: enemy.position, color: .red)
            enemy.removeFromParent()
        }
    }

    private func applyDamageToPlayer(_ amount: Int) {
        guard isRunning, let player = player else { return }
        player.health -= amount
        player.flashHit()
        gameState?.health = max(0, player.health)
        if player.health <= 0 {
            endGame()
        }
    }

    private func endGame() {
        isRunning = false
        spawnExplosion(at: player.position, color: .cyan)
        player.removeFromParent()
        gameState?.commitBestScore()
        gameState?.phase = .gameOver
    }

    private func spawnExplosion(at point: CGPoint, color: SKColor) {
        let burst = SKShapeNode(circleOfRadius: 6)
        burst.position = point
        burst.fillColor = color
        burst.strokeColor = .clear
        burst.glowWidth = 6
        burst.zPosition = 20
        addChild(burst)
        burst.run(SKAction.sequence([
            SKAction.group([SKAction.scale(to: 4, duration: 0.25),
                            SKAction.fadeOut(withDuration: 0.25)]),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Touch handling (twin-stick)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isRunning else { return }
        for touch in touches {
            let location = touch.location(in: self)
            if location.x < size.width / 2 {
                if !moveStick.isActive { moveStick.begin(at: location, touch: touch) }
            } else {
                if !aimStick.isActive { aimStick.begin(at: location, touch: touch) }
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let location = touch.location(in: self)
            if touch == moveStick.trackedTouch { moveStick.update(to: location) }
            else if touch == aimStick.trackedTouch { aimStick.update(to: location) }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if touch == moveStick.trackedTouch { moveStick.end() }
            else if touch == aimStick.trackedTouch { aimStick.end() }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }
}
