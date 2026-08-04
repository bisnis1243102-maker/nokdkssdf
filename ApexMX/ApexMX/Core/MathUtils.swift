import Foundation

/// Small numeric helpers shared by the simulation, AI and presentation layers.
public enum MathUtils {

    public static func clamp(_ value: Double, _ minimum: Double, _ maximum: Double) -> Double {
        min(max(value, minimum), maximum)
    }

    public static func clamp01(_ value: Double) -> Double { clamp(value, 0, 1) }

    /// Linear interpolation. `t` is not clamped, allowing deliberate extrapolation.
    public static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    /// Maps `value` from one range to another and clamps the result to `[outMin, outMax]`.
    public static func remap(_ value: Double,
                             _ inMin: Double, _ inMax: Double,
                             _ outMin: Double, _ outMax: Double) -> Double {
        guard abs(inMax - inMin) > 1e-12 else { return outMin }
        let t = clamp01((value - inMin) / (inMax - inMin))
        return lerp(outMin, outMax, t)
    }

    /// Smoothstep easing between two edges.
    public static func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
        let t = clamp01((value - edge0) / max(edge1 - edge0, 1e-12))
        return t * t * (3 - 2 * t)
    }

    /// Frame-rate independent exponential approach. `rate` is the fraction of the
    /// remaining distance covered per second, so behaviour is identical at 60 and 120 Hz.
    public static func damp(_ current: Double, _ target: Double, rate: Double, dt: Double) -> Double {
        let factor = 1 - exp(-max(rate, 0) * dt)
        return current + (target - current) * factor
    }

    public static func damp(_ current: Vector2, _ target: Vector2, rate: Double, dt: Double) -> Vector2 {
        let factor = 1 - exp(-max(rate, 0) * dt)
        return current + (target - current) * factor
    }

    /// Wraps an angle into `(-π, π]`, keeping rotation maths numerically stable.
    public static func wrapAngle(_ radians: Double) -> Double {
        var a = radians.truncatingRemainder(dividingBy: 2 * .pi)
        if a > .pi { a -= 2 * .pi }
        if a <= -.pi { a += 2 * .pi }
        return a
    }

    /// Signed shortest angular difference from `from` to `to`.
    public static func angleDelta(from: Double, to: Double) -> Double {
        wrapAngle(to - from)
    }

    /// Moves `current` toward `target` by at most `maxDelta`.
    public static func moveToward(_ current: Double, _ target: Double, maxDelta: Double) -> Double {
        let diff = target - current
        if abs(diff) <= maxDelta { return target }
        return current + (diff < 0 ? -maxDelta : maxDelta)
    }
}

/// Deterministic, portable pseudo-random source.
///
/// `SystemRandomNumberGenerator` is not reproducible, and `Swift`'s standard
/// library gives no stability guarantees across OS versions. Track generation,
/// AI personalities and replay validation all need bit-identical results on
/// every device, so the game uses this SplitMix64 generator everywhere.
public struct DeterministicRandom: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        // Avoid the all-zero state, which is a fixed point for the mixer.
        state = seed &+ 0x9E3779B97F4A7C15
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// A uniform value in `[0, 1)`.
    public mutating func unit() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0)
    }

    /// A uniform value in `[lower, upper)`.
    public mutating func range(_ lower: Double, _ upper: Double) -> Double {
        lower + unit() * (upper - lower)
    }

    public mutating func int(_ lower: Int, _ upper: Int) -> Int {
        guard upper > lower else { return lower }
        return lower + Int(next() % UInt64(upper - lower))
    }
}
