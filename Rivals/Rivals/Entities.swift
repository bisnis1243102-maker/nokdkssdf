import SpriteKit

/// The player-controlled fighter.
final class Player: SKNode {
    var health = GameConfig.playerMaxHealth
    private let body = SKShapeNode(circleOfRadius: GameConfig.playerRadius)
    private let barrel = SKShapeNode(rectOf: CGSize(width: 22, height: 6), cornerRadius: 3)

    override init() {
        super.init()
        body.fillColor = SKColor(red: 0.30, green: 0.66, blue: 1.0, alpha: 1.0)
        body.strokeColor = .white
        body.lineWidth = 2
        body.glowWidth = 4
        addChild(body)

        barrel.fillColor = .white
        barrel.strokeColor = .clear
        barrel.position = CGPoint(x: GameConfig.playerRadius - 2, y: 0)
        addChild(barrel)

        let pb = SKPhysicsBody(circleOfRadius: GameConfig.playerRadius)
        pb.affectedByGravity = false
        pb.allowsRotation = false
        pb.linearDamping = 0
        pb.categoryBitMask = PhysicsCategory.player
        pb.contactTestBitMask = PhysicsCategory.enemy | PhysicsCategory.enemyBullet
        pb.collisionBitMask = PhysicsCategory.wall
        physicsBody = pb
        zPosition = 10
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Aim the barrel toward a direction without rotating the physics body.
    func aim(angle: CGFloat) {
        barrel.zRotation = angle
        barrel.position = CGPoint(x: cos(angle) * (GameConfig.playerRadius - 2),
                                  y: sin(angle) * (GameConfig.playerRadius - 2))
    }

    func flashHit() {
        let flash = SKAction.sequence([
            SKAction.run { [weak self] in self?.body.fillColor = .white },
            SKAction.wait(forDuration: 0.06),
            SKAction.run { [weak self] in
                self?.body.fillColor = SKColor(red: 0.30, green: 0.66, blue: 1.0, alpha: 1.0)
            }
        ])
        run(flash)
    }
}

enum EnemyKind {
    case chaser   // rushes the player and explodes on contact
    case shooter  // keeps its distance and fires projectiles
}

/// An AI opponent.
final class Enemy: SKNode {
    let kind: EnemyKind
    var health: Int
    var lastShot: TimeInterval = 0
    private let body: SKShapeNode

    init(kind: EnemyKind) {
        self.kind = kind
        switch kind {
        case .chaser:
            health = GameConfig.chaserHealth
            body = SKShapeNode(circleOfRadius: GameConfig.enemyRadius)
            body.fillColor = SKColor(red: 1.0, green: 0.32, blue: 0.32, alpha: 1.0)
        case .shooter:
            health = GameConfig.shooterHealth
            let path = CGMutablePath()
            let r = GameConfig.enemyRadius
            path.move(to: CGPoint(x: 0, y: r))
            path.addLine(to: CGPoint(x: r, y: -r))
            path.addLine(to: CGPoint(x: -r, y: -r))
            path.closeSubpath()
            body = SKShapeNode(path: path)
            body.fillColor = SKColor(red: 1.0, green: 0.74, blue: 0.20, alpha: 1.0)
        }
        super.init()
        body.strokeColor = .white
        body.lineWidth = 1.5
        body.glowWidth = 2
        addChild(body)

        let pb = SKPhysicsBody(circleOfRadius: GameConfig.enemyRadius)
        pb.affectedByGravity = false
        pb.allowsRotation = false
        pb.linearDamping = 0
        pb.categoryBitMask = PhysicsCategory.enemy
        pb.contactTestBitMask = PhysicsCategory.player | PhysicsCategory.playerBullet
        pb.collisionBitMask = PhysicsCategory.wall | PhysicsCategory.enemy
        physicsBody = pb
        zPosition = 8
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var pointValue: Int {
        kind == .chaser ? GameConfig.pointsPerChaser : GameConfig.pointsPerShooter
    }

    /// Returns true if the enemy was killed.
    func takeDamage(_ amount: Int) -> Bool {
        health -= amount
        let flash = SKAction.sequence([
            SKAction.scale(to: 1.25, duration: 0.05),
            SKAction.scale(to: 1.0, duration: 0.05)
        ])
        body.run(flash)
        return health <= 0
    }
}

/// A projectile fired by the player or an enemy.
final class Bullet: SKNode {
    let fromPlayer: Bool
    let damage: Int
    let spawnTime: TimeInterval

    init(fromPlayer: Bool, now: TimeInterval) {
        self.fromPlayer = fromPlayer
        self.damage = fromPlayer ? GameConfig.bulletDamage : GameConfig.enemyBulletDamage
        self.spawnTime = now
        super.init()

        let dot = SKShapeNode(circleOfRadius: GameConfig.bulletRadius)
        dot.fillColor = fromPlayer
            ? SKColor(red: 1.0, green: 0.95, blue: 0.4, alpha: 1.0)
            : SKColor(red: 1.0, green: 0.45, blue: 0.45, alpha: 1.0)
        dot.strokeColor = .clear
        dot.glowWidth = 3
        addChild(dot)

        let pb = SKPhysicsBody(circleOfRadius: GameConfig.bulletRadius)
        pb.affectedByGravity = false
        pb.linearDamping = 0
        pb.categoryBitMask = fromPlayer ? PhysicsCategory.playerBullet : PhysicsCategory.enemyBullet
        pb.contactTestBitMask = fromPlayer ? PhysicsCategory.enemy : PhysicsCategory.player
        pb.collisionBitMask = PhysicsCategory.none
        physicsBody = pb
        zPosition = 9
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
