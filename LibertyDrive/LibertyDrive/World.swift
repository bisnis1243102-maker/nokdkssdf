import UIKit

/// One named area of the city.
struct District {
    let name: String
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
    let tall: Bool          // skyscraper district?
    var color: UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
}

/// Static description of the open world: size + the 3x3 grid of districts.
enum World {
    static let half: Float = 200          // map spans -200...200 on X and Z
    static let regionSplit: Float = 66    // boundary between the 3 bands

    /// Row-major 3x3 grid. Row 0 = low Z (north), Col 0 = low X (west).
    static let districts: [District] = [
        District(name: "The Docks",          r: 0.42, g: 0.48, b: 0.55, tall: false),
        District(name: "Sunset Beach",       r: 0.95, g: 0.80, b: 0.48, tall: false),
        District(name: "Vespucci Airfield",  r: 0.58, g: 0.63, b: 0.70, tall: false),
        District(name: "Chinatown",          r: 0.86, g: 0.38, b: 0.40, tall: true),
        District(name: "Downtown",           r: 0.52, g: 0.68, b: 0.96, tall: true),
        District(name: "Financial District", r: 0.46, g: 0.86, b: 0.72, tall: true),
        District(name: "Industrial Park",    r: 0.70, g: 0.58, b: 0.40, tall: false),
        District(name: "Old Town",           r: 0.82, g: 0.70, b: 0.52, tall: false),
        District(name: "Little Hills",       r: 0.58, g: 0.84, b: 0.54, tall: false),
    ]

    static func index(x: Float, z: Float) -> Int {
        let col = x < -regionSplit ? 0 : (x < regionSplit ? 1 : 2)
        let row = z < -regionSplit ? 0 : (z < regionSplit ? 1 : 2)
        return row * 3 + col
    }

    static func district(x: Float, z: Float) -> District { districts[index(x: x, z: z)] }
    static func name(x: Float, z: Float) -> String { district(x: x, z: z).name }
}
