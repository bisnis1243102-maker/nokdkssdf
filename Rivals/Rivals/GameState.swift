import SwiftUI

/// High-level phases the app moves through.
enum GamePhase {
    case menu
    case playing
    case gameOver
}

/// Shared, observable game state that drives the SwiftUI HUD / menus.
/// `GameScene` writes to this on the main thread (SpriteKit's update loop
/// already runs on main) so the UI stays in sync without extra plumbing.
final class GameState: ObservableObject {
    @Published var phase: GamePhase = .menu
    @Published var score: Int = 0
    @Published var wave: Int = 1
    @Published var health: Int = GameConfig.playerMaxHealth
    @Published private(set) var bestScore: Int =
        UserDefaults.standard.integer(forKey: "rivals.bestScore")

    var healthFraction: CGFloat {
        max(0, min(1, CGFloat(health) / CGFloat(GameConfig.playerMaxHealth)))
    }

    func reset() {
        score = 0
        wave = 1
        health = GameConfig.playerMaxHealth
    }

    func commitBestScore() {
        if score > bestScore {
            bestScore = score
            UserDefaults.standard.set(bestScore, forKey: "rivals.bestScore")
        }
    }
}

/// Tunable gameplay constants in one place.
enum GameConfig {
    static let playerMaxHealth = 100
    static let playerSpeed: CGFloat = 270           // points / second
    static let playerRadius: CGFloat = 20

    static let bulletSpeed: CGFloat = 640
    static let bulletRadius: CGFloat = 5
    static let bulletLifetime: TimeInterval = 1.1
    static let fireInterval: TimeInterval = 0.15
    static let bulletDamage = 25

    static let enemyRadius: CGFloat = 18
    static let chaserSpeed: CGFloat = 120
    static let chaserHealth = 50
    static let chaserContactDamage = 12

    static let shooterSpeed: CGFloat = 70
    static let shooterHealth = 40
    static let shooterPreferredRange: CGFloat = 240
    static let shooterFireInterval: TimeInterval = 1.6
    static let enemyBulletSpeed: CGFloat = 320
    static let enemyBulletDamage = 8

    static let pointsPerChaser = 10
    static let pointsPerShooter = 15
}

/// Physics collision categories (bit masks).
enum PhysicsCategory {
    static let none: UInt32        = 0
    static let player: UInt32      = 1 << 0
    static let enemy: UInt32       = 1 << 1
    static let playerBullet: UInt32 = 1 << 2
    static let enemyBullet: UInt32  = 1 << 3
    static let wall: UInt32        = 1 << 4
}
