import SpriteKit

/// Deterministic pseudo-random generator so the city looks the same on every
/// launch (missions point at fixed places) without shipping map data.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = (seed &* 0x9E3779B97F4A7C15) | 1
    }

    /// Uniform value in [0, 1).
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) & 0xFFFFFF) / CGFloat(0x1000000)
    }

    mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + next() * (b - a) }
    mutating func int(_ a: Int, _ b: Int) -> Int { a + Int(next() * CGFloat(b - a + 1)) }
    mutating func chance(_ p: CGFloat) -> Bool { next() < p }
    mutating func pick<T>(_ items: [T]) -> T { items[int(0, items.count - 1)] }
}

extension SKColor {
    /// Small hue-preserving jitter so buildings in a district feel related
    /// but not copy-pasted.
    func varied(by rng: inout SeededRandom, amount: CGFloat = 0.07) -> SKColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return SKColor(hue: h,
                       saturation: min(1, max(0, s + rng.range(-amount, amount))),
                       brightness: min(1, max(0, b + rng.range(-amount, amount))),
                       alpha: a)
    }
}

/// One of the six named districts of Port Leon.
struct District {
    let name: String
    let buildingColor: SKColor
    let groundColor: SKColor
}

/// Axis-aligned building footprint in world coordinates, used for both
/// rendering and collision.
struct Building {
    let rect: CGRect
    let color: SKColor
}

/// The city of Port Leon: a 10×10 grid of blocks separated by roads, grouped
/// into six districts, with parks, plazas, a beach and a set of landmarks.
/// Generation is procedural but seeded, so it is identical every run.
struct City {
    static let blocksX = 10
    static let blocksY = 10
    static let cell: CGFloat = 460          // road-centre spacing
    static let roadHalf: CGFloat = 70       // half width of a road
    static let laneOffset: CGFloat = 32     // lane centre offset from road centre
    static let sidewalk: CGFloat = 40       // sidewalk band inside a block

    static var worldSize: CGFloat { CGFloat(blocksX) * cell + roadHalf * 2 }

    let districts: [District]
    let districtIndex: [[Int]]              // [i][j] -> index into districts
    let buildings: [[[Building]]]           // [i][j] -> footprints
    let parkBlocks: Set<Int>                // encoded i * 100 + j
    let plazaBlocks: Set<Int>

    // Landmarks (world coordinates).
    let missionGiver: CGPoint               // the V6 Club, Neon Mile
    let hospital: CGPoint                   // Mercy General
    let policeHQ: CGPoint                   // VCPD headquarters
    let garage: CGPoint                     // Rusty's garage, Ironside
    let bank: CGPoint                       // Leon Savings, Neon Mile
    let hideout: CGPoint                    // safehouse, Casa Vieja
    let airport: CGPoint                    // Port Leon airstrip
    let marina: CGPoint                     // Palm Shores marina

    // MARK: Geometry helpers

    /// World x/y of the centre line of road number `k` (0...blocks).
    static func roadCenter(_ k: Int) -> CGFloat { roadHalf + CGFloat(k) * cell }

    /// Full rect of block (i, j) between its four surrounding roads.
    static func blockRect(_ i: Int, _ j: Int) -> CGRect {
        CGRect(x: roadCenter(i) + roadHalf,
               y: roadCenter(j) + roadHalf,
               width: cell - roadHalf * 2,
               height: cell - roadHalf * 2)
    }

    static func blockCenter(_ i: Int, _ j: Int) -> CGPoint {
        let r = blockRect(i, j)
        return CGPoint(x: r.midX, y: r.midY)
    }

    /// Block indices containing (or nearest to) a world point.
    static func blockIndex(at p: CGPoint) -> (Int, Int) {
        let i = max(0, min(blocksX - 1, Int((p.x - roadHalf) / cell)))
        let j = max(0, min(blocksY - 1, Int((p.y - roadHalf) / cell)))
        return (i, j)
    }

    func districtName(at p: CGPoint) -> String {
        let (i, j) = City.blockIndex(at: p)
        return districts[districtIndex[i][j]].name
    }

    /// Building rects in the 3×3 block neighbourhood of a point — the only
    /// candidates that can collide with something near it.
    func collisionRects(near p: CGPoint) -> [CGRect] {
        let (ci, cj) = City.blockIndex(at: p)
        var rects: [CGRect] = []
        for i in max(0, ci - 1)...min(City.blocksX - 1, ci + 1) {
            for j in max(0, cj - 1)...min(City.blocksY - 1, cj + 1) {
                for b in buildings[i][j] { rects.append(b.rect) }
            }
        }
        return rects
    }

    // MARK: Generation

    static func generate() -> City {
        var rng = SeededRandom(seed: 60613)

        let districts = [
            District(name: "Neon Mile",                                     // 0 downtown
                     buildingColor: SKColor(red: 0.42, green: 0.44, blue: 0.58, alpha: 1),
                     groundColor: SKColor(white: 0.52, alpha: 1)),
            District(name: "Port Leon Docks",                               // 1 south docks
                     buildingColor: SKColor(red: 0.48, green: 0.42, blue: 0.36, alpha: 1),
                     groundColor: SKColor(red: 0.47, green: 0.46, blue: 0.44, alpha: 1)),
            District(name: "Palm Shores",                                   // 2 east beach
                     buildingColor: SKColor(red: 0.80, green: 0.62, blue: 0.62, alpha: 1),
                     groundColor: SKColor(red: 0.82, green: 0.74, blue: 0.55, alpha: 1)),
            District(name: "Casa Vieja",                                    // 3 west old town
                     buildingColor: SKColor(red: 0.72, green: 0.56, blue: 0.42, alpha: 1),
                     groundColor: SKColor(red: 0.58, green: 0.54, blue: 0.48, alpha: 1)),
            District(name: "Grove Heights",                                 // 4 north hills
                     buildingColor: SKColor(red: 0.56, green: 0.62, blue: 0.50, alpha: 1),
                     groundColor: SKColor(red: 0.50, green: 0.56, blue: 0.45, alpha: 1)),
            District(name: "Ironside",                                      // 5 industrial
                     buildingColor: SKColor(red: 0.46, green: 0.48, blue: 0.50, alpha: 1),
                     groundColor: SKColor(white: 0.47, alpha: 1)),
        ]

        func districtFor(_ i: Int, _ j: Int) -> Int {
            if j <= 1 { return 1 }                                  // docks along the south
            if i >= 8 { return 2 }                                  // beach along the east
            if j >= 8 { return 4 }                                  // hills along the north
            if i <= 1 { return 3 }                                  // old town on the west
            if (3...6).contains(i) && (3...6).contains(j) { return 0 } // downtown core
            return 5                                                // industrial ring
        }

        // Blocks kept free of buildings so landmarks sit on open plazas.
        let plazaList: [(Int, Int)] = [
            (4, 4),   // mission giver — the V6 Club
            (2, 4),   // hospital
            (5, 2),   // police HQ
            (2, 6),   // garage
            (5, 5),   // bank
            (1, 3),   // hideout
            (6, 0),   // airstrip
            (9, 4),   // marina
        ]
        let plazas = Set(plazaList.map { $0.0 * 100 + $0.1 })

        var dIndex = Array(repeating: Array(repeating: 0, count: blocksY), count: blocksX)
        var buildings = Array(repeating: Array(repeating: [Building](), count: blocksY),
                              count: blocksX)
        var parks = Set<Int>()

        for i in 0..<blocksX {
            for j in 0..<blocksY {
                let d = districtFor(i, j)
                dIndex[i][j] = d
                let key = i * 100 + j
                if plazas.contains(key) { continue }
                if rng.chance(0.09) {
                    parks.insert(key)
                    continue
                }

                let inner = blockRect(i, j).insetBy(dx: sidewalk, dy: sidewalk)
                var lots: [CGRect] = []
                if rng.chance(0.16) {
                    lots = [inner]                                   // one large slab
                } else if rng.chance(0.35) {
                    let h = inner.height / 2                         // two wide slabs
                    lots = [CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: h),
                            CGRect(x: inner.minX, y: inner.minY + h, width: inner.width, height: h)]
                } else if rng.chance(0.5) {
                    let w = inner.width / 2                          // two tall slabs
                    lots = [CGRect(x: inner.minX, y: inner.minY, width: w, height: inner.height),
                            CGRect(x: inner.minX + w, y: inner.minY, width: w, height: inner.height)]
                } else {
                    let w = inner.width / 2, h = inner.height / 2    // four quadrants
                    lots = [CGRect(x: inner.minX, y: inner.minY, width: w, height: h),
                            CGRect(x: inner.minX + w, y: inner.minY, width: w, height: h),
                            CGRect(x: inner.minX, y: inner.minY + h, width: w, height: h),
                            CGRect(x: inner.minX + w, y: inner.minY + h, width: w, height: h)]
                }

                let density: CGFloat = (d == 2) ? 0.55 : 0.9         // the beach breathes
                let base = districts[d].buildingColor
                for lot in lots where rng.chance(density) {
                    let inset = rng.range(6, 20)
                    let rect = lot.insetBy(dx: inset, dy: inset)
                    if rect.width > 30 && rect.height > 30 {
                        buildings[i][j].append(Building(rect: rect,
                                                        color: base.varied(by: &rng)))
                    }
                }
            }
        }

        return City(districts: districts,
                    districtIndex: dIndex,
                    buildings: buildings,
                    parkBlocks: parks,
                    plazaBlocks: plazas,
                    missionGiver: blockCenter(4, 4),
                    hospital: blockCenter(2, 4),
                    policeHQ: blockCenter(5, 2),
                    garage: blockCenter(2, 6),
                    bank: blockCenter(5, 5),
                    hideout: blockCenter(1, 3),
                    airport: blockCenter(6, 0),
                    marina: blockCenter(9, 4))
    }
}
