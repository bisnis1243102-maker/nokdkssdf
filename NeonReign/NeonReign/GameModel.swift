import SwiftUI
import SceneKit

/// Render quality. `ultra` runs every custom post pass; each step down drops
/// the most expensive passes first so older devices still hold frame rate.
enum GraphicsQuality: Int, CaseIterable, Identifiable {
    case balanced = 0, high = 1, ultra = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .balanced: return "Balanced"
        case .high:     return "High"
        case .ultra:    return "Ultra"
        }
    }

    var blurb: String {
        switch self {
        case .balanced: return "Bloom + tonemap. Smoothest."
        case .high:     return "Adds reflections and light shafts."
        case .ultra:    return "Everything, plus FXAA."
        }
    }

    var wantsReflections: Bool { self != .balanced }
    var wantsGodRays: Bool { self != .balanced }
    var wantsTAA: Bool { self == .ultra }
    var wantsMotionBlur: Bool { self != .balanced }
    var shadowMapSize: CGFloat {
        switch self {
        case .balanced: return 1024
        case .high:     return 2048
        case .ultra:    return 4096
        }
    }
    /// Requested map resolution. `TextureFactory` caps this per surface class:
    /// roads get the full size, everything else is held at 256, because a
    /// facade seen from the street gains nothing from more pixels and the
    /// memory cost is multiplied by every style in the city.
    var textureSize: Int {
        switch self {
        case .balanced: return 256
        case .high:     return 512
        case .ultra:    return 512
        }
    }

    /// Cascades for the sun's shadow map. More cascades keep contact shadows
    /// sharp near the car without blurring the ones across the block.
    var shadowCascades: Int {
        switch self {
        case .balanced: return 1
        case .high:     return 2
        case .ultra:    return 3
        }
    }
    /// How many street/neon lights may be live around the player at once.
    var liveLights: Int {
        switch self {
        case .balanced: return 6
        case .high:     return 12
        case .ultra:    return 18
        }
    }
    var antialiasing: SCNAntialiasingMode {
        switch self {
        case .balanced: return .none
        case .high:     return .multisampling2X
        case .ultra:    return .multisampling4X
        }
    }

    /// First launch always starts on the cheapest tier — a run that works
    /// beats a run that looks marginally better and gets killed. High and Ultra
    /// are one tap away in the ☰ menu, and the choice is remembered.
    static var deviceDefault: GraphicsQuality { .balanced }
}

/// Which layers of the render path are active.
///
/// This exists because the first build that reached a phone rendered a black
/// frame at a healthy 60fps — the simulation was running, nothing was visible.
/// Splitting the path into three selectable layers turns "it's black" into
/// "it's black at *this* layer", which is the difference between fixing it and
/// guessing.
enum RenderMode: Int, CaseIterable, Identifiable {
    /// Plain SceneKit. No HDR, no camera effects, no custom passes.
    case plain = 0
    /// SceneKit's own HDR camera effects, but none of the custom Metal passes.
    case cameraFX = 1
    /// Everything, including the SCNTechnique post chain.
    case full = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .plain:    return "Plain"
        case .cameraFX: return "Camera FX"
        case .full:     return "Full"
        }
    }

    var blurb: String {
        switch self {
        case .plain:    return "No effects at all. If the city is visible here, the world is fine."
        case .cameraFX: return "SceneKit HDR, bloom and SSAO. No custom Metal passes."
        case .full:     return "Adds the custom post chain: bloom tiers, reflections, shafts, grade."
        }
    }

    var wantsCameraEffects: Bool { self != .plain }
    var wantsTechnique: Bool { self == .full }
}

/// Whether the player is behind the wheel or on the pavement.
enum PlayerMode {
    case driving, onFoot
}

/// Bridges SwiftUI (controls + HUD) and the SceneKit simulation.
///
/// Input fields are deliberately *not* `@Published`: the scene reads them every
/// frame and republishing them would invalidate the view 60 times a second.
/// HUD fields are published, but only pushed from the scene ~6x/sec.
final class GameModel: ObservableObject {

    // MARK: Input (written by the on-screen controls, read by the scene)

    var throttle: Float = 0      // -1 brake/reverse ... 1 gas
    var steer: Float = 0         // -1 left ... 1 right
    var handbrake: Bool = false
    var walkX: Float = 0         // on-foot strafe
    var walkZ: Float = 0         // on-foot forward

    // MARK: Momentary actions (consumed by the scene on the next frame)

    var enterExitRequested = false
    var startMissionRequested: Int? = nil
    var abandonMissionRequested = false

    // MARK: Persisted progress

    @Published var cash: Int
    @Published var missionsCompleted: Set<Int>
    @Published var quality: GraphicsQuality {
        didSet { UserDefaults.standard.set(quality.rawValue, forKey: Keys.quality); qualityVersion += 1 }
    }
    /// Bumped when the renderer must be rebuilt for a new quality tier.
    @Published var qualityVersion = 0

    /// Which layers of the render path run. Changing it rebuilds the renderer.
    @Published var renderMode: RenderMode {
        didSet {
            UserDefaults.standard.set(renderMode.rawValue, forKey: Keys.renderMode)
            qualityVersion += 1
        }
    }

    private enum Keys {
        static let cash = "neonreign.cash"
        static let done = "neonreign.missionsDone"
        static let quality = "neonreign.quality"
        static let diagnostics = "neonreign.showDiagnostics"
        static let renderMode = "neonreign.renderMode"
    }

    init() {
        let d = UserDefaults.standard
        cash = d.object(forKey: Keys.cash) as? Int ?? 250
        missionsCompleted = Set(d.array(forKey: Keys.done) as? [Int] ?? [])

        // If the previous launch never reached a rendered frame, it was killed
        // mid-startup. Come back in safe mode rather than repeating whatever
        // did it, and remember the stage so the panel can show it.
        let failed = Diagnostics.consumePreviousFailure()

        if failed != nil {
            quality = .balanced
        } else if let raw = d.object(forKey: Keys.quality) as? Int,
                  let q = GraphicsQuality(rawValue: raw) {
            quality = q
        } else {
            quality = GraphicsQuality.deviceDefault
        }

        // On by default while we are still proving this build runs at all.
        showDiagnostics = d.object(forKey: Keys.diagnostics) as? Bool ?? true

        // Default to Camera FX, not Full: the custom post chain is the prime
        // suspect for the black frame, and a visible city beats an invisible
        // one with better grading.
        if let raw = d.object(forKey: Keys.renderMode) as? Int,
           let m = RenderMode(rawValue: raw) {
            renderMode = m
        } else {
            renderMode = .cameraFX
        }

        // Everything without a default is initialised by this point, so `self`
        // is usable — these two must not be assigned any earlier.
        lastFailedStage = failed
        safeMode = failed != nil

        Diagnostics.stamp(.started)
    }

    private func persist() {
        let d = UserDefaults.standard
        d.set(cash, forKey: Keys.cash)
        d.set(Array(missionsCompleted), forKey: Keys.done)
    }

    // MARK: Diagnostics
    //
    // This build has to report on itself: nobody can attach a debugger to a
    // sideloaded app, so the numbers that decide whether it survives are put
    // on screen where they can be read off and sent back.

    @Published var showDiagnostics: Bool {
        didSet { UserDefaults.standard.set(showDiagnostics, forKey: Keys.diagnostics) }
    }
    /// Physical footprint, MB — the figure iOS judges for jetsam.
    @Published var footprintMB: Double = 0
    /// Bytes left before the app is killed, MB.
    @Published var availableMB: Double = 0
    @Published var fps: Double = 0
    @Published var textureMB: Double = 0
    @Published var textureCount = 0
    @Published var buildingCount = 0
    /// Set when the memory guard pulled the quality tier down on its own.
    @Published var autoDowngraded = false
    /// Stage the *previous* launch died at, if it died.
    @Published var lastFailedStage: Diagnostics.Stage? = nil
    /// True when this launch started on Balanced because the last one failed.
    @Published var safeMode = false

    // MARK: HUD state (pushed from the scene)

    @Published var mode: PlayerMode = .driving
    @Published var speedKmh = 0
    @Published var area = "Harbor Point"
    @Published var clockText = "21:40"
    @Published var weatherText = "Clear"
    @Published var heat = 0                 // 0...3 stars
    @Published var playerX: Float = 0
    @Published var playerZ: Float = 0
    @Published var heading: Float = 0
    /// True when the player is standing close enough to a car to get in.
    @Published var canEnterCar = false

    // MARK: Mission state

    @Published var activeMission: Mission? = nil
    @Published var objectiveIndex = 0
    @Published var objectiveText = ""
    @Published var objectiveTimer: Double? = nil
    /// Waypoint direction relative to the player's heading, in radians.
    @Published var waypointAngle: Float = 0
    @Published var waypointDistance: Float = 0
    @Published var hasWaypoint = false
    /// Set when a mission ends; drives the result sheet.
    @Published var result: MissionResult? = nil
    /// The mission whose start marker is currently glowing in the world.
    @Published var offeredMissionID: Int? = nil
    @Published var nearMissionStart = false

    struct MissionResult: Identifiable {
        let id = UUID()
        let title: String
        let success: Bool
        let payout: Int
        let reason: String
    }

    var nextMission: Mission? {
        Campaign.missions.first { !missionsCompleted.contains($0.id) }
    }

    var campaignComplete: Bool {
        missionsCompleted.count >= Campaign.missions.count
    }

    // MARK: Mission transitions (called from the scene, on the main queue)

    func beginMission(_ m: Mission) {
        activeMission = m
        objectiveIndex = 0
        objectiveText = m.objectives.first?.hint ?? ""
        result = nil
    }

    func completeMission(_ m: Mission) {
        let firstClear = !missionsCompleted.contains(m.id)
        missionsCompleted.insert(m.id)
        if firstClear { cash += m.payout }
        persist()
        result = MissionResult(title: m.title, success: true,
                               payout: firstClear ? m.payout : 0,
                               reason: firstClear ? "Paid out" : "Replayed — no second payout")
        activeMission = nil
        objectiveTimer = nil
        objectiveText = ""
    }

    func failMission(_ m: Mission, reason: String) {
        result = MissionResult(title: m.title, success: false, payout: 0, reason: reason)
        activeMission = nil
        objectiveTimer = nil
        objectiveText = ""
    }

    func resetInput() {
        throttle = 0; steer = 0; walkX = 0; walkZ = 0; handbrake = false
    }

    func resetProgress() {
        missionsCompleted = []
        cash = 250
        persist()
    }
}
