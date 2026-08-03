import Foundation
import UIKit

// MARK: - Deterministic randomness

/// SplitMix64 — small, fast, and reproducible across runs and devices.
/// Every image in ArtForge is a pure function of (prompt, style, seed), so the
/// same inputs always give back the exact same artwork.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E3779B97F4A7C15
    }

    mutating func nextBits() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<1
    mutating func next() -> Double {
        Double(nextBits() >> 11) * (1.0 / 9007199254740992.0)
    }

    mutating func next(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + next() * (range.upperBound - range.lowerBound)
    }

    mutating func nextInt(_ range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(nextBits() % span)
    }

    mutating func chance(_ p: Double) -> Bool { next() < p }

    mutating func pick<T>(_ items: [T]) -> T { items[nextInt(0...(items.count - 1))] }

    /// Roughly normal via central limit; handy for organic-looking spreads.
    mutating func gaussian(mean: Double = 0, sd: Double = 1) -> Double {
        let sum = next() + next() + next() + next() + next() + next()
        return mean + (sum - 3.0) / 1.0 * sd * 0.7071
    }
}

/// Stable 64-bit hash of a prompt, so typing the same words twice gives the
/// same picture but changing one letter gives a completely different one.
func stableHash(_ string: String) -> UInt64 {
    var hash: UInt64 = 0xCBF29CE484222325
    for byte in string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100000001B3
    }
    return hash
}

// MARK: - Noise

/// Value noise with fractal Brownian motion on top. Cheap enough to sample a
/// few million times per render, smooth enough to look hand-drawn.
struct Noise {
    private let seed: UInt64

    init(seed: UInt64) { self.seed = seed }

    private func hash(_ xi: Int, _ yi: Int) -> Double {
        var h = UInt64(bitPattern: Int64(xi)) &* 0x9E3779B97F4A7C15
        h ^= UInt64(bitPattern: Int64(yi)) &* 0xC2B2AE3D27D4EB4F
        h ^= seed
        h = (h ^ (h >> 29)) &* 0xBF58476D1CE4E5B9
        h = (h ^ (h >> 32))
        return Double(h >> 11) * (1.0 / 9007199254740992.0) * 2.0 - 1.0
    }

    private func smooth(_ t: Double) -> Double { t * t * (3.0 - 2.0 * t) }

    /// Single octave, output in -1...1
    func value(_ x: Double, _ y: Double) -> Double {
        let x0 = floor(x), y0 = floor(y)
        let xi = Int(x0), yi = Int(y0)
        let fx = smooth(x - x0), fy = smooth(y - y0)

        let a = hash(xi, yi)
        let b = hash(xi + 1, yi)
        let c = hash(xi, yi + 1)
        let d = hash(xi + 1, yi + 1)

        let top = a + (b - a) * fx
        let bottom = c + (d - c) * fx
        return top + (bottom - top) * fy
    }

    /// Layered noise. `octaves` detail levels, each half the amplitude and
    /// double the frequency of the last.
    func fbm(_ x: Double, _ y: Double, octaves: Int = 4, lacunarity: Double = 2.0, gain: Double = 0.5) -> Double {
        var sum = 0.0, amp = 1.0, freq = 1.0, norm = 0.0
        for _ in 0..<octaves {
            sum += value(x * freq, y * freq) * amp
            norm += amp
            amp *= gain
            freq *= lacunarity
        }
        return norm > 0 ? sum / norm : 0
    }

    /// Ridged variant — sharp creases, good for canyons and marbling.
    func ridged(_ x: Double, _ y: Double, octaves: Int = 4) -> Double {
        var sum = 0.0, amp = 1.0, freq = 1.0, norm = 0.0
        for _ in 0..<octaves {
            sum += (1.0 - abs(value(x * freq, y * freq))) * amp
            norm += amp
            amp *= 0.5
            freq *= 2.0
        }
        return norm > 0 ? (sum / norm) * 2.0 - 1.0 : 0
    }
}

// MARK: - Colour

struct RGB {
    var r: Double, g: Double, b: Double

    static func fromHSB(_ h: Double, _ s: Double, _ b: Double) -> RGB {
        let hue = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let c = b * s
        let x = c * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = b - c
        let (r1, g1, b1): (Double, Double, Double)
        switch hue {
        case ..<60:   (r1, g1, b1) = (c, x, 0)
        case ..<120:  (r1, g1, b1) = (x, c, 0)
        case ..<180:  (r1, g1, b1) = (0, c, x)
        case ..<240:  (r1, g1, b1) = (0, x, c)
        case ..<300:  (r1, g1, b1) = (x, 0, c)
        default:      (r1, g1, b1) = (c, 0, x)
        }
        return RGB(r: r1 + m, g: g1 + m, b: b1 + m)
    }

    func mix(_ other: RGB, _ t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t,
            g: g + (other.g - g) * t,
            b: b + (other.b - b) * t)
    }

    func lighten(_ amount: Double) -> RGB { mix(RGB(r: 1, g: 1, b: 1), amount) }
    func darken(_ amount: Double) -> RGB { mix(RGB(r: 0, g: 0, b: 0), amount) }

    var cg: CGColor {
        UIColor(red: CGFloat(min(max(r, 0), 1)),
                green: CGFloat(min(max(g, 0), 1)),
                blue: CGFloat(min(max(b, 0), 1)),
                alpha: 1).cgColor
    }

    var ui: UIColor {
        UIColor(red: CGFloat(min(max(r, 0), 1)),
                green: CGFloat(min(max(g, 0), 1)),
                blue: CGFloat(min(max(b, 0), 1)),
                alpha: 1)
    }

    func withAlpha(_ a: Double) -> CGColor {
        UIColor(red: CGFloat(min(max(r, 0), 1)),
                green: CGFloat(min(max(g, 0), 1)),
                blue: CGFloat(min(max(b, 0), 1)),
                alpha: CGFloat(min(max(a, 0), 1))).cgColor
    }
}

/// Colour relationships the palette generator can build a scheme around.
enum Harmony: CaseIterable {
    case analogous, complementary, triadic, splitComplement, monochrome
}

/// A generated colour scheme: a background plus an ordered ramp of accents that
/// renderers sample from. Built from a harmony rule rather than a fixed list so
/// the space of possible palettes is effectively unbounded.
struct Palette {
    var background: RGB
    var ramp: [RGB]
    var isDark: Bool
    var name: String

    /// Sample the ramp continuously, `t` in 0...1, with smooth interpolation.
    func color(at t: Double) -> RGB {
        guard ramp.count > 1 else { return ramp.first ?? RGB(r: 1, g: 1, b: 1) }
        let clamped = min(max(t, 0), 0.9999)
        let scaled = clamped * Double(ramp.count - 1)
        let index = Int(scaled)
        return ramp[index].mix(ramp[index + 1], scaled - Double(index))
    }

    static func generate(rng: inout SeededRandom) -> Palette {
        let baseHue = rng.next(0...360)
        let dark = rng.chance(0.72)

        let harmony = rng.pick(Harmony.allCases)

        var hues: [Double]
        var name: String
        switch harmony {
        case .analogous:
            let spread = rng.next(18...44)
            hues = [-2, -1, 0, 1, 2].map { baseHue + $0 * spread }
            name = "Analogous"
        case .complementary:
            let jitter = rng.next(6...20)
            hues = [baseHue - jitter, baseHue, baseHue + jitter,
                    baseHue + 180 - jitter, baseHue + 180, baseHue + 180 + jitter]
            name = "Complementary"
        case .triadic:
            hues = [baseHue, baseHue + 14, baseHue + 120, baseHue + 134, baseHue + 240, baseHue + 254]
            name = "Triadic"
        case .splitComplement:
            hues = [baseHue, baseHue + 20, baseHue + 150, baseHue + 175, baseHue + 210]
            name = "Split"
        case .monochrome:
            hues = [baseHue, baseHue + 6, baseHue - 6, baseHue + 12, baseHue - 12]
            name = "Monochrome"
        }

        // Saturation and brightness curves give the ramp a sense of light
        // travelling through it rather than a flat set of swatches.
        let satBase = rng.next(0.45...0.95)
        let satSwing = rng.next(0.05...0.3)
        let brightLow = dark ? rng.next(0.35...0.6) : rng.next(0.55...0.75)
        let brightHigh = dark ? rng.next(0.85...1.0) : rng.next(0.92...1.0)

        var ramp: [RGB] = []
        let count = hues.count
        for (i, hue) in hues.enumerated() {
            let t = count > 1 ? Double(i) / Double(count - 1) : 0
            let s = min(max(satBase + sin(t * .pi) * satSwing, 0.08), 1.0)
            let b = brightLow + (brightHigh - brightLow) * t
            ramp.append(RGB.fromHSB(hue, s, min(b, 1.0)))
        }

        // Sprinkle in a near-neutral so compositions have somewhere to breathe.
        if rng.chance(0.4) {
            let neutral = RGB.fromHSB(baseHue + rng.next(-30...30), rng.next(0.04...0.14), dark ? 0.92 : 0.25)
            ramp.insert(neutral, at: rng.nextInt(0...(ramp.count - 1)))
        }

        let bgHue = baseHue + rng.next(-25...25)
        let background: RGB
        if dark {
            background = RGB.fromHSB(bgHue, rng.next(0.25...0.7), rng.next(0.05...0.14))
        } else {
            background = RGB.fromHSB(bgHue, rng.next(0.04...0.16), rng.next(0.9...0.98))
        }

        return Palette(background: background, ramp: ramp, isDark: dark, name: name)
    }
}

// MARK: - Pixel buffer

/// A plain RGBA8 buffer for the renderers that work per-pixel. Much faster than
/// stroking millions of tiny Core Graphics paths.
final class PixelCanvas {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.pixels = [UInt8](repeating: 0, count: width * height * 4)
    }

    @inline(__always)
    func set(_ x: Int, _ y: Int, _ color: RGB) {
        guard x >= 0, x < width, y >= 0, y < height else { return }
        let i = (y * width + x) * 4
        pixels[i] = UInt8(min(max(color.r, 0), 1) * 255)
        pixels[i + 1] = UInt8(min(max(color.g, 0), 1) * 255)
        pixels[i + 2] = UInt8(min(max(color.b, 0), 1) * 255)
        pixels[i + 3] = 255
    }

    func makeImage() -> CGImage? {
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        var data = pixels
        return data.withUnsafeMutableBytes { raw -> CGImage? in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(data: base,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: width * 4,
                                      space: space,
                                      bitmapInfo: info.rawValue) else { return nil }
            return ctx.makeImage()
        }
    }
}
