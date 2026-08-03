import Foundation
import CoreGraphics

/// Deterministic value noise. Same track number always builds the same track,
/// so times are comparable and a track you learn stays learnable.
struct TrackNoise {
    private let seed: UInt64

    init(seed: UInt64) { self.seed = seed }

    private func hash(_ i: Int) -> Double {
        var h = UInt64(bitPattern: Int64(i)) &* 0x9E3779B97F4A7C15
        h ^= seed
        h = (h ^ (h >> 29)) &* 0xBF58476D1CE4E5B9
        h ^= (h >> 32)
        return Double(h >> 11) * (1.0 / 9007199254740992.0) * 2.0 - 1.0
    }

    private func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }

    func value(_ x: Double) -> Double {
        let x0 = floor(x)
        let i = Int(x0)
        let t = smooth(x - x0)
        let a = hash(i), b = hash(i + 1)
        return a + (b - a) * t
    }

    func fbm(_ x: Double, octaves: Int = 4) -> Double {
        var sum = 0.0, amp = 1.0, freq = 1.0, norm = 0.0
        for _ in 0..<octaves {
            sum += value(x * freq) * amp
            norm += amp
            amp *= 0.5
            freq *= 2
        }
        return norm > 0 ? sum / norm : 0
    }
}

/// One race. Difficulty is expressed as terrain roughness and length rather
/// than as an artificial timer, so a hard track is hard to *ride*.
struct Track: Identifiable, Hashable {
    let id: Int
    let name: String
    let seed: UInt64
    let length: Double
    /// Vertical scale of the hills, in points.
    let amplitude: Double
    /// Horizontal frequency: higher means tighter, choppier bumps.
    let frequency: Double
    let octaves: Int
    /// How many big ramps get carved into the terrain.
    let jumps: Int

    /// Target times, derived from length rather than hand-set: a gold demands
    /// keeping the throttle pinned through most of the track, bronze allows a
    /// cautious ride. Tunable once real times exist to compare against.
    var goldTime: TimeInterval { length / 380 }
    var silverTime: TimeInterval { length / 300 }
    var bronzeTime: TimeInterval { length / 220 }

    func medal(for time: TimeInterval) -> Medal {
        if time <= goldTime { return .gold }
        if time <= silverTime { return .silver }
        if time <= bronzeTime { return .bronze }
        return .none
    }

    /// Restart points, so a crash costs seconds rather than the whole run.
    var checkpoints: [Double] {
        var points: [Double] = [0]
        var x = 1500.0
        while x < length - 600 {
            points.append(x)
            x += 1500
        }
        return points
    }

    var difficultyStars: Int {
        switch id {
        case 0...1: return 1
        case 2...3: return 2
        case 4...5: return 3
        case 6...7: return 4
        default: return 5
        }
    }

    static let all: [Track] = [
        Track(id: 0, name: "Warm-Up", seed: 0x51ED270B, length: 5200, amplitude: 46, frequency: 0.0042, octaves: 2, jumps: 3),
        Track(id: 1, name: "Rolling Fields", seed: 0xA13F77C1, length: 6000, amplitude: 66, frequency: 0.0047, octaves: 3, jumps: 4),
        Track(id: 2, name: "Dust Bowl", seed: 0x7C90EE31, length: 6800, amplitude: 84, frequency: 0.0052, octaves: 3, jumps: 5),
        Track(id: 3, name: "Ridgeline", seed: 0x2B44A9F7, length: 7400, amplitude: 104, frequency: 0.0055, octaves: 3, jumps: 6),
        Track(id: 4, name: "Whoops", seed: 0xD3A1B08D, length: 7800, amplitude: 92, frequency: 0.0090, octaves: 4, jumps: 5),
        Track(id: 5, name: "Canyon Run", seed: 0x66C2E415, length: 8600, amplitude: 128, frequency: 0.0050, octaves: 4, jumps: 7),
        Track(id: 6, name: "Big Air", seed: 0x0F5E9A23, length: 9200, amplitude: 116, frequency: 0.0044, octaves: 3, jumps: 9),
        Track(id: 7, name: "Broken Spine", seed: 0x9911CC57, length: 9800, amplitude: 150, frequency: 0.0075, octaves: 4, jumps: 8),
        Track(id: 8, name: "The Wall", seed: 0x4D7B2E90, length: 10600, amplitude: 172, frequency: 0.0068, octaves: 5, jumps: 10),
        Track(id: 9, name: "Final Lap", seed: 0xBEEF1234, length: 12000, amplitude: 190, frequency: 0.0080, octaves: 5, jumps: 12)
    ]

    /// Ground height at a given horizontal position.
    func height(at x: Double, noise: TrackNoise) -> Double {
        // Flat launch pad, so the bike never starts inside a hill.
        if x < 260 { return 0 }
        let ease = min((x - 260) / 420, 1)

        var y = noise.fbm(x * frequency, octaves: octaves) * amplitude * ease

        // Ramps: smooth bumps placed at regular intervals, each one a raised
        // cosine so the lip is a clean take-off rather than a cliff.
        if jumps > 0 {
            let spacing = (length - 700) / Double(jumps)
            for j in 0..<jumps {
                let centre = 620 + spacing * (Double(j) + 0.5)
                let width = 150.0 + Double((Int(seed) &+ j) % 90)
                let d = abs(x - centre)
                if d < width {
                    let shape = (cos(d / width * .pi) + 1) * 0.5
                    let peak = 60.0 + Double((Int(seed >> 8) &+ j * 37) % 90)
                    // Front side steeper than the back: a launch, not a lump.
                    let bias = x < centre ? 1.0 : 0.78
                    y += shape * shape * peak * bias * ease
                }
            }
        }

        // Flatten the finish so the run ends on wheels, not mid-somersault.
        let toEnd = length - x
        if toEnd < 420 {
            y *= max(toEnd / 420, 0)
        }
        return y
    }

    /// Samples the whole track once. Used for both the physics edge chain and
    /// the drawn ground, so what you see is exactly what you hit.
    func profile(noise: TrackNoise, step: Double = 11) -> [CGPoint] {
        var points: [CGPoint] = []
        var x = -400.0
        while x <= length + 600 {
            points.append(CGPoint(x: x, y: height(at: x, noise: noise)))
            x += step
        }
        return points
    }
}
