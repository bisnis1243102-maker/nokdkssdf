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

    // Garage / progression
    @Published var credits: Int
    @Published var ownedCarIDs: [String]
    @Published var selectedCarID: String
    @Published var paintR: Double
    @Published var paintG: Double
    @Published var paintB: Double
    /// Bumped whenever the player's car or paint changes, so the scene rebuilds it.
    @Published var carVersion: Int = 0

    init() {
        let d = UserDefaults.standard
        credits = d.object(forKey: "forsa.credits") as? Int ?? 30000
        ownedCarIDs = d.stringArray(forKey: "forsa.owned") ?? ["hatch"]
        selectedCarID = d.string(forKey: "forsa.selected") ?? "hatch"
        let spec = CarShop.spec(d.string(forKey: "forsa.selected") ?? "hatch")
        paintR = d.object(forKey: "forsa.paintR") as? Double ?? Double(spec.r)
        paintG = d.object(forKey: "forsa.paintG") as? Double ?? Double(spec.g)
        paintB = d.object(forKey: "forsa.paintB") as? Double ?? Double(spec.b)
    }

    var selectedSpec: CarSpec { CarShop.spec(selectedCarID) }

    private func persist() {
        let d = UserDefaults.standard
        d.set(credits, forKey: "forsa.credits")
        d.set(ownedCarIDs, forKey: "forsa.owned")
        d.set(selectedCarID, forKey: "forsa.selected")
        d.set(paintR, forKey: "forsa.paintR")
        d.set(paintG, forKey: "forsa.paintG")
        d.set(paintB, forKey: "forsa.paintB")
    }

    func addCredits(_ n: Int) { credits += n; persist() }

    func buyCar(_ spec: CarSpec) {
        guard !ownedCarIDs.contains(spec.id), credits >= spec.price else { return }
        credits -= spec.price
        ownedCarIDs.append(spec.id)
        selectCar(spec)
        persist()
    }

    func selectCar(_ spec: CarSpec) {
        selectedCarID = spec.id
        paintR = Double(spec.r); paintG = Double(spec.g); paintB = Double(spec.b)
        carVersion += 1
        persist()
    }

    func setPaint(_ r: Double, _ g: Double, _ b: Double) {
        paintR = r; paintG = g; paintB = b
        carVersion += 1
        persist()
    }

    // HUD (updated ~6x/sec from the scene)
    @Published var speedKmh: Int = 0
    @Published var area: String = "Festival"
    @Published var weather: String = "☀️ Sunny"
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
