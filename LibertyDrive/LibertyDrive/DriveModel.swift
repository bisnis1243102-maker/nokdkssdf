import SwiftUI

/// Bridges the SwiftUI controls/HUD and the SceneKit driving simulation.
/// Input fields are read by the scene every frame (kept un-published to avoid
/// per-frame view invalidation); HUD fields are published a few times a second.
final class DriveModel: ObservableObject {
    // Input (written by the on-screen controls)
    var throttle: Float = 0     // -1 (brake/reverse) ... 1 (gas)
    var steer: Float = 0        // -1 (left) ... 1 (right)

    // Momentary action (consumed by the scene next frame)
    var startRaceRequested: Bool = false

    // HUD (updated ~6x/sec from the scene)
    @Published var speedKmh: Int = 0
    @Published var area: String = "Festival"
    @Published var distanceM: Int = 0
    @Published var carX: Float = 0
    @Published var carZ: Float = 0
    @Published var heading: Float = 0

    // Drift (Forza-style)
    @Published var driftScore: Int = 0
    @Published var drifting: Bool = false

    // Race / festival mode
    @Published var racing: Bool = false
    @Published var cpIndex: Int = 0
    @Published var cpTotal: Int = 0
    @Published var raceTime: Double = 0
    @Published var arrowAngle: Float = 0        // radians, relative to car heading
    @Published var raceFinished: Bool = false
    @Published var lastTime: Double = 0
    @Published var bestTime: Double = UserDefaults.standard.double(forKey: "forsa.bestTime")

    func resetInput() { throttle = 0; steer = 0 }
}
