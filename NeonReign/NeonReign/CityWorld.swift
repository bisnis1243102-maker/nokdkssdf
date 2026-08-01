import UIKit
import SceneKit

/// A named area of the city. Each district gets its own palette, building
/// profile and neon character so the skyline reads differently as you drive.
struct District {
    let name: String
    let tint: UIColor
    let neon: UIColor
    /// 0 = low-rise, 1 = mid, 2 = towers.
    let height: Int
    /// Fraction of blocks that are parks/lots instead of buildings.
    let openness: CGFloat
}

/// Static description of the open world: extents, road grid and districts.
enum CityWorld {

    // MARK: Extents

    /// The map spans -half...half on both X and Z.
    static let half: Float = 260
    /// Distance between avenue centre lines.
    static let blockSize: Float = 52
    /// Half-width of the drivable road surface.
    static let roadHalfWidth: Float = 7.5
    /// Ground plane height.
    static let groundY: Float = 0

    /// Avenue centre lines, shared by both axes.
    static let avenues: [Float] = {
        var out: [Float] = []
        var v = -half + blockSize * 0.5
        while v <= half {
            out.append(v)
            v += blockSize
        }
        return out
    }()

    // MARK: Districts (3x3 grid)

    static let regionSplit: Float = half / 3

    /// Row-major 3x3 grid. Row 0 = low Z, Col 0 = low X.
    static let districts: [District] = [
        District(name: "Harbor Point",
                 tint: UIColor(red: 0.34, green: 0.40, blue: 0.48, alpha: 1),
                 neon: UIColor(red: 0.30, green: 0.80, blue: 1.00, alpha: 1),
                 height: 0, openness: 0.45),
        District(name: "Marrow Heights",
                 tint: UIColor(red: 0.46, green: 0.44, blue: 0.52, alpha: 1),
                 neon: UIColor(red: 0.95, green: 0.35, blue: 0.65, alpha: 1),
                 height: 1, openness: 0.22),
        District(name: "Saltworks",
                 tint: UIColor(red: 0.40, green: 0.38, blue: 0.34, alpha: 1),
                 neon: UIColor(red: 1.00, green: 0.62, blue: 0.20, alpha: 1),
                 height: 0, openness: 0.40),
        District(name: "Lantern Row",
                 tint: UIColor(red: 0.52, green: 0.30, blue: 0.36, alpha: 1),
                 neon: UIColor(red: 1.00, green: 0.24, blue: 0.32, alpha: 1),
                 height: 1, openness: 0.12),
        District(name: "The Spire",
                 tint: UIColor(red: 0.28, green: 0.32, blue: 0.44, alpha: 1),
                 neon: UIColor(red: 0.55, green: 0.70, blue: 1.00, alpha: 1),
                 height: 2, openness: 0.06),
        District(name: "Glasshouse",
                 tint: UIColor(red: 0.30, green: 0.44, blue: 0.46, alpha: 1),
                 neon: UIColor(red: 0.35, green: 1.00, blue: 0.78, alpha: 1),
                 height: 2, openness: 0.10),
        District(name: "Vermillion",
                 tint: UIColor(red: 0.50, green: 0.34, blue: 0.30, alpha: 1),
                 neon: UIColor(red: 1.00, green: 0.45, blue: 0.18, alpha: 1),
                 height: 1, openness: 0.20),
        District(name: "Cannery Flats",
                 tint: UIColor(red: 0.38, green: 0.40, blue: 0.36, alpha: 1),
                 neon: UIColor(red: 0.80, green: 0.95, blue: 0.35, alpha: 1),
                 height: 0, openness: 0.35),
        District(name: "Ridgewater",
                 tint: UIColor(red: 0.32, green: 0.42, blue: 0.34, alpha: 1),
                 neon: UIColor(red: 0.60, green: 0.90, blue: 0.60, alpha: 1),
                 height: 0, openness: 0.55),
    ]

    static func index(x: Float, z: Float) -> Int {
        let col = x < -regionSplit ? 0 : (x < regionSplit ? 1 : 2)
        let row = z < -regionSplit ? 0 : (z < regionSplit ? 1 : 2)
        return row * 3 + col
    }

    static func district(x: Float, z: Float) -> District { districts[index(x: x, z: z)] }
    static func name(x: Float, z: Float) -> String { district(x: x, z: z).name }

    // MARK: Road helpers

    /// Nearest avenue centre line to a coordinate on one axis.
    static func nearestAvenue(_ v: Float) -> Float {
        var best = avenues[0]
        for a in avenues where abs(a - v) < abs(best - v) { best = a }
        return best
    }

    /// True when the point lies on drivable tarmac (either axis' road strip).
    static func onRoad(x: Float, z: Float) -> Bool {
        abs(nearestAvenue(x) - x) < roadHalfWidth || abs(nearestAvenue(z) - z) < roadHalfWidth
    }

    /// Snaps a point to the middle of the closest road so spawns never land
    /// inside a building.
    static func snapToRoad(x: Float, z: Float) -> (Float, Float) {
        let ax = nearestAvenue(x), az = nearestAvenue(z)
        return abs(ax - x) < abs(az - z) ? (ax, z) : (x, az)
    }

    /// Clamps a point inside the playable area.
    static func clamp(_ v: Float) -> Float { min(half - 4, max(-half + 4, v)) }

    // MARK: Named landmarks (mission destinations)

    struct Landmark {
        let name: String
        let x: Float
        let z: Float
    }

    static let landmarks: [String: Landmark] = {
        let raw: [Landmark] = [
            Landmark(name: "Your lockup",       x: -104, z: 130),
            Landmark(name: "Pier 9",            x: -208, z: -26),
            Landmark(name: "Marrow Heights",    x: -104, z: -182),
            Landmark(name: "Spire Plaza",       x: 0,    z: 0),
            Landmark(name: "Glasshouse Mall",   x: 156,  z: 26),
            Landmark(name: "The Saltworks",     x: 182,  z: -156),
            Landmark(name: "Cannery Yard",      x: 26,   z: 182),
            Landmark(name: "Ridgewater Bridge", x: 182,  z: 208),
            Landmark(name: "Lantern Row",       x: -156, z: 52),
            Landmark(name: "Vermillion Depot",  x: -182, z: 208),
        ]
        var out: [String: Landmark] = [:]
        for l in raw {
            let (sx, sz) = snapToRoad(x: l.x, z: l.z)
            out[l.name] = Landmark(name: l.name, x: clamp(sx), z: clamp(sz))
        }
        return out
    }()

    static func point(_ name: String) -> SIMD2<Float> {
        guard let l = landmarks[name] else { return SIMD2<Float>(0, 0) }
        return SIMD2<Float>(l.x, l.z)
    }
}
