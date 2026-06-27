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
        District(name: "The Bayfront",   r: 0.42, g: 0.48, b: 0.55, tall: false),
        District(name: "Fuji View",      r: 0.90, g: 0.74, b: 0.80, tall: false),
        District(name: "Harbor",         r: 0.58, g: 0.63, b: 0.70, tall: false),
        District(name: "Akihabara",      r: 0.86, g: 0.38, b: 0.40, tall: true),
        District(name: "Neo Tokyo",      r: 0.52, g: 0.68, b: 0.96, tall: true),
        District(name: "Shinjuku",       r: 0.46, g: 0.86, b: 0.72, tall: true),
        District(name: "Festival Site",  r: 0.92, g: 0.66, b: 0.42, tall: false),
        District(name: "Sakura Hills",   r: 0.96, g: 0.72, b: 0.82, tall: false),
        District(name: "Rice Fields",    r: 0.58, g: 0.84, b: 0.54, tall: false),
    ]

    static func index(x: Float, z: Float) -> Int {
        let col = x < -regionSplit ? 0 : (x < regionSplit ? 1 : 2)
        let row = z < -regionSplit ? 0 : (z < regionSplit ? 1 : 2)
        return row * 3 + col
    }

    static func district(x: Float, z: Float) -> District { districts[index(x: x, z: z)] }
    static func name(x: Float, z: Float) -> String { district(x: x, z: z).name }
}
