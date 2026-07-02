import SwiftUI

/// High-level phases the app moves through.
enum AppPhase {
    case menu
    case playing
    case busted
    case wasted
    case finale
}

/// The two playable leads. Mia runs faster; Jax hits harder.
enum Protagonist: String {
    case mia = "Mia"
    case jax = "Jax"

    var other: Protagonist { self == .mia ? .jax : .mia }
}

/// Static minimap geometry, built once from the generated city.
struct MinimapModel {
    var worldSize: CGFloat = 1
    var blocks: [MinimapBlock] = []
}

struct MinimapBlock {
    let rect: CGRect
    let color: Color
}

/// Live minimap data, refreshed a few times per second by the scene.
struct MinimapSnapshot {
    var player: CGPoint = .zero
    var heading: CGFloat = 0
    var cops: [CGPoint] = []
    var target: CGPoint?
    var giver: CGPoint?
}

/// Shared, observable game state that drives the SwiftUI HUD and menus.
/// `GameScene` writes to it from SpriteKit's update loop (already on main),
/// throttled so SwiftUI isn't hammered every frame.
final class GameState: ObservableObject {
    @Published var phase: AppPhase = .menu
    @Published var cash: Int = UserDefaults.standard.integer(forKey: Keys.cash)
    @Published var health: CGFloat = 100
    @Published var wanted: Int = 0
    @Published var character: Protagonist = .mia
    @Published var inVehicle = false
    @Published var vehicleName: String?
    @Published var vehicleHealth: CGFloat = 1        // 0...1
    @Published var speedKMH: Int = 0
    @Published var districtName = ""
    @Published var canEnterVehicle = false
    @Published var missionTitle: String?
    @Published var objectiveText: String?
    @Published var objectiveSecondsLeft: Int?
    @Published var banner: String?
    @Published var minimapModel = MinimapModel()
    @Published var minimap = MinimapSnapshot()

    var missionsCompleted: Int {
        get { UserDefaults.standard.integer(forKey: Keys.mission) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.mission) }
    }

    var hasSave: Bool { missionsCompleted > 0 || cash > 0 }

    func persist() {
        UserDefaults.standard.set(cash, forKey: Keys.cash)
    }

    func wipeSave() {
        cash = 0
        missionsCompleted = 0
        persist()
    }

    private enum Keys {
        static let cash = "vicesix.cash"
        static let mission = "vicesix.mission"
    }
}

/// Tunable gameplay constants in one place.
enum GameConfig {
    static let maxHealth: CGFloat = 100
    static let runSpeedMia: CGFloat = 195
    static let runSpeedJax: CGFloat = 170
    static let playerRadius: CGFloat = 13
    static let punchRange: CGFloat = 58
    static let punchRangeJax: CGFloat = 74

    static let maxWanted = 6                        // it is VI, after all
    static let crimeCooldown: TimeInterval = 10     // no crimes for this long...
    static let starDecayInterval: TimeInterval = 8  // ...then lose a star this often
    static let copSafeDistance: CGFloat = 620       // decay only when cops are far

    static let trafficCount = 14
    static let pedCount = 24
    static let spawnRingMin: CGFloat = 750
    static let spawnRingMax: CGFloat = 1900
    static let despawnDistance: CGFloat = 2500

    static let arrestDistanceFoot: CGFloat = 200
    static let arrestDistanceCar: CGFloat = 150
    static let arrestTime: TimeInterval = 1.8
    static let copFireRange: CGFloat = 420
    static let bustedFine = 300
    static let wastedFee = 400
}
