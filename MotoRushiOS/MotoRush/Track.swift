import Foundation

// MARK: - Deterministic RNG

/// mulberry32 — small, fast, and identical across runs for a given seed, which
/// is what lets every track in the game be reproduced from a single Int.
struct RNG {
    private var state: UInt32
    init(seed: UInt32) { state = seed }

    mutating func next() -> Double {
        state = state &+ 0x6D2B79F5
        var t = state
        t = (t ^ (t >> 15)) &* (1 | t)
        t = t ^ (t &+ ((t ^ (t >> 7)) &* (61 | t)))
        return Double((t ^ (t >> 14))) / 4294967296.0
    }

    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
    mutating func int(_ n: Int) -> Int { min(n - 1, Int(next() * Double(n))) }
}

func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
func clampd(_ v: Double, _ a: Double, _ b: Double) -> Double { v < a ? a : (v > b ? b : v) }

// MARK: - Biomes

struct Biome {
    let key: String
    let name: String
    let skyTop: String
    let skyBottom: String
    let ground: String
    let groundDeep: String
    let accent: String
    let dust: String
    let rolling: Double
    let jumpBias: Double
    let whoopBias: Double
    let grip: Double
    let rollDrag: Double
    let night: Bool
    let stadium: Bool
    let weather: String   // "", "rain", "snow", "embers"

    static let all: [Biome] = [
        Biome(key: "motocross", name: "Motocross", skyTop: "#7EC8FF", skyBottom: "#DFF1FF",
              ground: "#8A6244", groundDeep: "#5D4230", accent: "#C8A97A", dust: "#C9A97E",
              rolling: 1.0, jumpBias: 1.0, whoopBias: 0.8, grip: 1.0, rollDrag: 1.0,
              night: false, stadium: false, weather: ""),
        Biome(key: "supercross", name: "Supercross", skyTop: "#1B2340", skyBottom: "#38406B",
              ground: "#6B4C37", groundDeep: "#3D2B1F", accent: "#9C7A55", dust: "#B39A76",
              rolling: 0.4, jumpBias: 1.6, whoopBias: 1.6, grip: 1.05, rollDrag: 1.0,
              night: true, stadium: true, weather: ""),
        Biome(key: "sand", name: "Sand", skyTop: "#FFD79A", skyBottom: "#FFECCD",
              ground: "#E0C081", groundDeep: "#B3945C", accent: "#F0DCAE", dust: "#EFD9A8",
              rolling: 1.4, jumpBias: 0.7, whoopBias: 1.8, grip: 0.78, rollDrag: 2.1,
              night: false, stadium: false, weather: ""),
        Biome(key: "mud", name: "Mud", skyTop: "#7F8794", skyBottom: "#B9C0C9",
              ground: "#4F4034", groundDeep: "#332A22", accent: "#6A5646", dust: "#5A4A3B",
              rolling: 1.1, jumpBias: 0.9, whoopBias: 1.0, grip: 0.7, rollDrag: 1.7,
              night: false, stadium: false, weather: "rain"),
        Biome(key: "forest", name: "Forest", skyTop: "#8FD3A5", skyBottom: "#E6F7EA",
              ground: "#5C4A32", groundDeep: "#3A2F20", accent: "#6F8F4F", dust: "#8A7A58",
              rolling: 1.2, jumpBias: 0.9, whoopBias: 0.9, grip: 1.02, rollDrag: 1.0,
              night: false, stadium: false, weather: ""),
        Biome(key: "snow", name: "Snow", skyTop: "#C9DCEF", skyBottom: "#F6FBFF",
              ground: "#E8F0F7", groundDeep: "#A9BDD0", accent: "#FFFFFF", dust: "#FFFFFF",
              rolling: 1.0, jumpBias: 0.8, whoopBias: 0.9, grip: 0.62, rollDrag: 1.3,
              night: false, stadium: false, weather: "snow"),
        Biome(key: "desert", name: "Desert", skyTop: "#FFB27A", skyBottom: "#FFE3C2",
              ground: "#C98F5C", groundDeep: "#8E6039", accent: "#E6B98A", dust: "#E3C093",
              rolling: 1.5, jumpBias: 1.1, whoopBias: 0.7, grip: 0.9, rollDrag: 1.1,
              night: false, stadium: false, weather: ""),
        Biome(key: "night", name: "Night", skyTop: "#0B1026", skyBottom: "#1D2748",
              ground: "#3B3145", groundDeep: "#241E2C", accent: "#5A4C68", dust: "#6B5F78",
              rolling: 1.0, jumpBias: 1.2, whoopBias: 1.1, grip: 0.95, rollDrag: 1.0,
              night: true, stadium: false, weather: ""),
        Biome(key: "mountain", name: "Mountain", skyTop: "#6FA8DC", skyBottom: "#DBE9F7",
              ground: "#6D6A63", groundDeep: "#43413C", accent: "#8D8A80", dust: "#9C968A",
              rolling: 1.8, jumpBias: 1.2, whoopBias: 0.6, grip: 0.98, rollDrag: 1.0,
              night: false, stadium: false, weather: ""),
        Biome(key: "beach", name: "Beach", skyTop: "#5FC9FF", skyBottom: "#D8F3FF",
              ground: "#DCC394", groundDeep: "#A98F63", accent: "#F2E2BD", dust: "#EDDCB4",
              rolling: 0.9, jumpBias: 0.9, whoopBias: 1.2, grip: 0.85, rollDrag: 1.4,
              night: false, stadium: false, weather: ""),
        Biome(key: "volcano", name: "Volcano", skyTop: "#3A1020", skyBottom: "#7B2531",
              ground: "#3A2B2B", groundDeep: "#1D1414", accent: "#FF6A3D", dust: "#8C5A45",
              rolling: 1.3, jumpBias: 1.4, whoopBias: 1.0, grip: 0.92, rollDrag: 1.0,
              night: true, stadium: false, weather: "embers"),
        Biome(key: "arena", name: "Arena", skyTop: "#141A2E", skyBottom: "#2A3352",
              ground: "#71513A", groundDeep: "#3F2C20", accent: "#A78156", dust: "#B39A76",
              rolling: 0.3, jumpBias: 1.8, whoopBias: 1.5, grip: 1.06, rollDrag: 1.0,
              night: true, stadium: true, weather: "")
    ]

    static func named(_ key: String) -> Biome {
        return all.first(where: { $0.key == key }) ?? all[0]
    }
}

// MARK: - Track

struct TrackFeature {
    let kind: String
    let x: Double
    let len: Double
    let risk: Double
}

struct Prop {
    let x: Double
    let kind: String      // tree, bale, flag, banner
    let scale: Double
    let back: Bool
}

/// A track is a 1D heightfield in metres plus the feature metadata the AI and
/// the renderer need. Everything is derived from `seed`, so a track id is all
/// that has to be stored or sent over a wire.
final class Track {
    static let step: Double = 0.4

    // Geometry the generator is not allowed to exceed. The severity multiplier
    // used to scale features without any bound on the *slope* that resulted — a
    // "roller" could come out at 49 degrees, and terrain climbing under the
    // wheel that fast launches the bike far beyond anything a rider could do.
    static let maxFaceSlope: Double = 0.62    // ~32 degrees, whoops/rollers
    static let maxLaunchSlope: Double = 0.45  // ~24 degrees, steepest jump lip

    let seed: UInt32
    let biome: Biome
    let difficulty: Double
    private(set) var pts: [Double]
    let features: [TrackFeature]
    let props: [Prop]
    let length: Double
    let startX: Double
    let finishX: Double
    let name: String

    init(seed: UInt32, biomeKey: String, difficulty: Double, lengthOverride: Double? = nil) {
        self.seed = seed
        self.biome = Biome.named(biomeKey)
        self.difficulty = clampd(difficulty, 0, 1)
        var rnd = RNG(seed: seed)
        let d = self.difficulty
        let target = lengthOverride ?? (lerp(520, 1050, d) * rnd.range(0.85, 1.15))

        var pts: [Double] = [0]
        var features: [TrackFeature] = []
        var base: Double = 0

        func pushFlat(_ len: Double) {
            let n = max(1, Int((len / Track.step).rounded()))
            for _ in 0..<n { pts.append(base) }
        }
        func pushRamp(_ len: Double, _ rise: Double, _ shape: String) {
            // How steeply each shape exits at its top. `smooth` flattens out, so
            // it never launches; the other two do. Lengthen a takeoff rather
            // than shortening it, which is what a real track crew does: the jump
            // keeps its height, the lip just stops being a launcher.
            var len = len
            let factor: Double = shape == "kicker" ? 1.3 : (shape == "linear" ? 1.0 : 0)
            if rise > 0 && factor > 0 {
                len = max(len, (factor * rise) / Track.maxLaunchSlope)
            }
            let n = max(2, Int((len / Track.step).rounded()))
            for i in 1...n {
                let t = Double(i) / Double(n)
                let k: Double
                switch shape {
                case "kicker": k = pow(t, 1.3)
                case "linear": k = t
                default: k = t * t * (3 - 2 * t)
                }
                pts.append(base + rise * k)
            }
            base += rise
        }
        func pushWhoops(_ count: Int, _ amp: Double, _ spacing: Double) {
            // Peak slope of this profile is amp*pi/spacing; hold it to a face a
            // rider could actually ride rather than a wall.
            let amp = min(amp, (Track.maxFaceSlope * spacing) / .pi)
            let n = Int((Double(count) * spacing / Track.step).rounded())
            for i in 1...max(1, n) {
                let x = Double(i) * Track.step
                pts.append(base + amp * (1 - cos((x / spacing) * .pi * 2)) * 0.5)
            }
        }
        func pushRollers(_ count: Int, _ amp: Double, _ spacing: Double) {
            let amp = min(amp, (Track.maxFaceSlope * spacing) / .pi)
            let n = Int((Double(count) * spacing / Track.step).rounded())
            for i in 1...max(1, n) {
                let x = Double(i) * Track.step
                pts.append(base + amp * sin((x / spacing) * .pi * 2) * 0.5)
            }
        }
        func pushBerm(_ len: Double, _ depth: Double) {
            let n = max(2, Int((len / Track.step).rounded()))
            for i in 1...n {
                let t = Double(i) / Double(n)
                pts.append(base - depth * sin(t * .pi))
            }
        }
        func cursor() -> Double { Double(pts.count - 1) * Track.step }

        pushFlat(22)

        let jumpBias = biome.jumpBias * lerp(0.7, 1.35, d)
        let whoopBias = biome.whoopBias * lerp(0.6, 1.3, d)
        var lastKind = ""

        while cursor() < target {
            let table: [(String, Double)] = [
                ("tabletop", 1.0 * jumpBias),
                ("double", 0.85 * jumpBias),
                ("triple", 0.45 * jumpBias * d * 1.6),
                ("stepup", 0.6 * jumpBias),
                ("stepdown", 0.55 * jumpBias),
                ("whoops", 0.9 * whoopBias),
                ("rollers", 0.8),
                ("berm", 0.9),
                ("rhythm", 0.7 * jumpBias),
                ("straight", 0.5),
                ("hill", 0.7 * biome.rolling)
            ]
            func pick() -> String {
                let total = table.reduce(0.0) { $0 + $1.1 }
                var r = rnd.next() * total
                for (k, w) in table { r -= w; if r <= 0 { return k } }
                return "straight"
            }
            var kind = pick()
            if kind == lastKind && rnd.next() < 0.7 { kind = pick() }
            lastKind = kind

            let startX = cursor()
            let sev = lerp(0.7, 1.35, d) * rnd.range(0.85, 1.15)
            var risk = 0.2

            switch kind {
            case "tabletop":
                let h = rnd.range(1.1, 2.1) * sev
                let face = rnd.range(6.5, 9.5)
                pushRamp(face, h, "kicker")
                pushFlat(rnd.range(5, 12) * sev)
                pushRamp(face * 2.2, -h, "smooth")
                risk = 0.35
            case "double":
                let h = rnd.range(1.2, 2.0) * sev
                let gap = rnd.range(6, 10) * sev
                pushRamp(rnd.range(6, 8), h, "kicker")
                pushRamp(2.2, -h * 0.95, "linear")
                pushFlat(gap)
                pushRamp(rnd.range(4, 6), h * 0.95, "smooth")
                pushRamp(rnd.range(11, 15), -h, "smooth")
                risk = 0.65
            case "triple":
                let h = rnd.range(1.5, 2.4) * sev
                pushRamp(7.5, h, "kicker")
                pushRamp(2.4, -h, "linear")
                pushFlat(rnd.range(8, 11))
                pushRamp(4, h * 0.7, "smooth")
                pushRamp(6.5, -h * 0.7, "smooth")
                pushFlat(rnd.range(8, 11))
                pushRamp(4.5, h * 0.9, "smooth")
                pushRamp(14, -h * 0.9, "smooth")
                risk = 0.9
            case "stepup":
                let h = rnd.range(1.4, 2.6) * sev
                pushRamp(rnd.range(6.5, 8.5), h * 0.6, "kicker")
                pushRamp(2, -h * 0.15, "linear")
                pushFlat(rnd.range(5, 9))
                pushRamp(4, h * 0.55, "smooth")
                pushFlat(6)
                risk = 0.6
            case "stepdown":
                let h = rnd.range(1.3, 2.4) * sev
                pushRamp(7, h * 0.5, "kicker")
                pushRamp(1.6, -h * 0.1, "linear")
                pushFlat(rnd.range(6, 10))
                pushRamp(11, -h, "smooth")
                pushFlat(5)
                risk = 0.6
            case "whoops":
                let count = Int((rnd.range(5, 11) * lerp(0.8, 1.3, d)).rounded())
                pushWhoops(count, rnd.range(0.5, 1.0) * sev, rnd.range(3.4, 4.6))
                risk = 0.7
            case "rollers":
                pushRollers(Int(rnd.range(3, 6).rounded()), rnd.range(0.6, 1.4) * sev, rnd.range(6, 9))
                risk = 0.25
            case "berm":
                pushBerm(rnd.range(10, 18), rnd.range(0.8, 1.8) * sev)
                risk = 0.2
            case "rhythm":
                let n = Int(rnd.range(3, 5).rounded())
                let h = rnd.range(0.8, 1.5) * sev
                for _ in 0..<max(1, n) {
                    pushRamp(rnd.range(4.5, 6), h, "kicker")
                    pushRamp(rnd.range(7, 10), -h, "smooth")
                    pushFlat(rnd.range(1.5, 4))
                }
                risk = 0.8
            case "hill":
                let h = rnd.range(3, 9) * biome.rolling * 0.6
                pushRamp(rnd.range(14, 26), rnd.next() < 0.5 ? h : -h, "smooth")
                risk = 0.15
            default:
                pushFlat(rnd.range(10, 22))
                risk = 0.05
            }

            features.append(TrackFeature(kind: kind, x: startX, len: cursor() - startX, risk: risk))
            // Ramp the drift over the connector instead of stepping the base
            // and then running flat, which left a vertical curb at every
            // feature boundary.
            pushRamp(rnd.range(2, 6), (rnd.next() - 0.5) * 0.6 * biome.rolling, "smooth")
        }

        pushFlat(40)

        // Two light smoothing passes: raw sample joints read as invisible
        // curbs to the suspension solver.
        for _ in 0..<2 {
            if pts.count > 2 {
                for i in 1..<(pts.count - 1) {
                    pts[i] = pts[i] * 0.6 + (pts[i - 1] + pts[i + 1]) * 0.2
                }
            }
        }

        self.pts = pts
        self.features = features
        self.length = Double(pts.count - 1) * Track.step
        self.startX = 6
        self.finishX = self.length - 26

        var props: [Prop] = []
        var px: Double = 0
        while px < self.length {
            if rnd.next() < 0.35 {
                let kind: String
                if biome.key == "forest" { kind = "tree" }
                else if biome.stadium { kind = "banner" }
                else { kind = rnd.next() < 0.4 ? "flag" : "bale" }
                props.append(Prop(x: px + rnd.range(0, 4), kind: kind,
                                  scale: rnd.range(0.7, 1.4), back: rnd.next() < 0.5))
            }
            px += 6
        }
        self.props = props

        let prefix = ["Copper", "Iron", "Hollow", "Wild", "Broken", "Silver", "Red", "Black",
                      "High", "Thunder", "Dust", "Sky", "Storm", "Cinder", "Pine", "Salt"]
        let suffix = ["Ridge", "Basin", "Creek", "Flats", "Canyon", "Hollow", "Bowl", "Pass",
                      "Sands", "Bluff", "Gulch", "Park", "Valley", "Point", "Rise"]
        self.name = prefix[rnd.int(prefix.count)] + " " + suffix[rnd.int(suffix.count)]
    }

    func height(at x: Double) -> Double {
        let f = x / Track.step
        if f <= 0 { return pts[0] }
        if f >= Double(pts.count - 1) { return pts[pts.count - 1] }
        let i = Int(f)
        return lerp(pts[i], pts[i + 1], f - Double(i))
    }

    func slope(at x: Double) -> Double {
        return (height(at: x + Track.step) - height(at: x - Track.step)) / (2 * Track.step)
    }

    func feature(at x: Double) -> TrackFeature? {
        for f in features where x >= f.x && x < f.x + f.len { return f }
        return nil
    }

    /// Heavy landings dig a rut. Capped so a long session cannot erase a jump.
    func deform(at x: Double, depth: Double) {
        let i = Int((x / Track.step).rounded())
        for k in -3...3 {
            let j = i + k
            if j > 1 && j < pts.count - 1 {
                pts[j] -= depth * (1 - Double(abs(k)) / 4)
            }
        }
    }
}
