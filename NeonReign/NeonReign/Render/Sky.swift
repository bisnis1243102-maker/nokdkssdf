import UIKit
import SceneKit

/// The time-of-day model: one continuous clock that drives the sun, the sky
/// gradient, the HDR environment used for reflections, and the dusk switch that
/// turns the city's lights on.
struct SkyState {
    /// Hours, 0...24.
    var hour: Double = 21.0

    /// Sun elevation in radians. Negative means below the horizon.
    var sunElevation: Float {
        let t = Float((hour - 6) / 12) * .pi      // sunrise 6:00, sunset 18:00
        return sin(t) * 1.25
    }

    var sunAzimuth: Float {
        Float((hour / 24) * 2 * Double.pi)
    }

    /// 0 at full night, 1 at midday. Drives exposure and light intensity.
    var daylight: Float {
        max(0, min(1, (sunElevation + 0.12) / 1.0))
    }

    /// 1 while the sun is near the horizon — the golden/blue hour window.
    var duskFactor: Float {
        let e = sunElevation
        return max(0, 1 - abs(e) / 0.35)
    }

    var isNight: Bool { sunElevation < 0.06 }

    /// Warm at dawn/dusk, white at noon, cold blue at night.
    var sunColor: UIColor {
        let d = CGFloat(daylight)
        let dusk = CGFloat(duskFactor)
        let r = 1.0
        let g = 0.62 + d * 0.34 - dusk * 0.12
        let b = 0.34 + d * 0.62 - dusk * 0.24
        return UIColor(red: r, green: max(0, g), blue: max(0, b), alpha: 1)
    }

    var sunIntensity: CGFloat {
        CGFloat(daylight) * 2200 + 60
    }

    var ambientColor: UIColor {
        let d = CGFloat(daylight)
        return UIColor(red: 0.16 + d * 0.28,
                       green: 0.19 + d * 0.30,
                       blue: 0.30 + d * 0.32, alpha: 1)
    }

    var ambientIntensity: CGFloat { 180 + CGFloat(daylight) * 320 }

    /// Colours of the sky gradient, top to horizon.
    var zenith: (CGFloat, CGFloat, CGFloat) {
        let d = CGFloat(daylight)
        return (0.02 + d * 0.24, 0.03 + d * 0.42, 0.09 + d * 0.62)
    }

    var horizon: (CGFloat, CGFloat, CGFloat) {
        let d = CGFloat(daylight), k = CGFloat(duskFactor)
        return (0.10 + d * 0.60 + k * 0.55,
                0.09 + d * 0.60 + k * 0.22,
                0.18 + d * 0.66 - k * 0.05)
    }

    var clockText: String {
        let h = Int(hour) % 24
        let m = Int((hour - floor(hour)) * 60)
        return String(format: "%02d:%02d", h, m)
    }
}

enum Sky {

    /// Vertical gradient standing in for a captured sky. Fed both to
    /// `scene.background` and `scene.lightingEnvironment`, so metal and wet
    /// asphalt reflect the actual time of day rather than a fixed cube.
    static func gradient(_ state: SkyState, size: Int = 256) -> UIImage {
        let s = CGFloat(size)
        let r = UIGraphicsImageRenderer(size: CGSize(width: s, height: s))
        let (zr, zg, zb) = state.zenith
        let (hr, hg, hb) = state.horizon
        let ground = CGFloat(state.daylight) * 0.16 + 0.03

        return r.image { c in
            let ctx = c.cgContext
            let cs = CGColorSpaceCreateDeviceRGB()
            let colors = [
                UIColor(red: zr, green: zg, blue: zb, alpha: 1).cgColor,
                UIColor(red: (zr + hr) / 2, green: (zg + hg) / 2, blue: (zb + hb) / 2, alpha: 1).cgColor,
                UIColor(red: hr, green: hg, blue: hb, alpha: 1).cgColor,
                UIColor(red: ground * 1.1, green: ground, blue: ground * 0.95, alpha: 1).cgColor,
            ] as CFArray
            if let g = CGGradient(colorsSpace: cs, colors: colors,
                                  locations: [0, 0.42, 0.60, 0.62]) {
                ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: s), options: [])
            }

            // Stars fade in as the sun drops.
            let night = 1 - CGFloat(state.daylight)
            if night > 0.25 {
                for i in 0..<220 {
                    let x = TextureFactory.fbm(CGFloat(i) * 1.7, 0.3, 91) * s
                    let y = TextureFactory.fbm(0.9, CGFloat(i) * 1.3, 77) * s * 0.58
                    let a = TextureFactory.fbm(CGFloat(i), CGFloat(i), 55) * night * 0.9
                    ctx.setFillColor(UIColor(white: 1, alpha: a).cgColor)
                    ctx.fillEllipse(in: CGRect(x: x, y: y, width: 1.6, height: 1.6))
                }
            }

            // A soft sun/moon disc near the horizon band.
            let discY = s * (0.58 - CGFloat(state.sunElevation) * 0.34)
            let discColor = state.isNight
                ? UIColor(white: 0.92, alpha: 0.85)
                : state.sunColor.withAlphaComponent(0.95)
            ctx.setFillColor(discColor.cgColor)
            ctx.fillEllipse(in: CGRect(x: s * 0.46, y: discY - s * 0.02,
                                       width: s * 0.05, height: s * 0.05))
        }
    }
}
