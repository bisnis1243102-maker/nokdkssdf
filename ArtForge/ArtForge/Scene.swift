import Foundation
import UIKit

/// What the app understood from your prompt.
///
/// This is the whole "text to image" step: the words are read for subject,
/// time of day, and weather, and everything the renderer draws follows from
/// what was found here. Anything the prompt doesn't mention is filled in from
/// the seed, so a bare prompt still produces a complete picture.
struct SceneSpec {
    enum TimeOfDay { case dawn, day, sunset, night }
    enum Weather { case clear, cloudy, rain, snow, fog, storm }
    enum Subject { case mountains, ocean, forest, desert, city, plains }

    var time: TimeOfDay = .day
    var weather: Weather = .clear
    var subject: Subject = .mountains
    var hasWater = false
    var hasTrees = false
    var hasBirds = false
    var hasMoon = false
    var hasStars = false
    var understood: [String] = []

    /// Words the parser reacts to. Matching is on whole words where it matters
    /// (so "sunset" doesn't also trip "sun") and substrings where it doesn't.
    static func parse(prompt: String, rng: inout SeededRandom) -> SceneSpec {
        var spec = SceneSpec()
        let text = " " + prompt.lowercased()
            .replacingOccurrences(of: "[^a-z ]", with: " ", options: .regularExpression) + " "

        func has(_ words: [String]) -> String? {
            for w in words where text.contains(" \(w) ") || text.contains(" \(w)s ") { return w }
            return nil
        }

        // Time of day
        if let w = has(["night", "midnight", "nocturnal", "dark", "starry"]) {
            spec.time = .night; spec.understood.append(w)
        } else if let w = has(["sunset", "dusk", "evening", "twilight", "golden"]) {
            spec.time = .sunset; spec.understood.append(w)
        } else if let w = has(["sunrise", "dawn", "morning"]) {
            spec.time = .dawn; spec.understood.append(w)
        } else if let w = has(["day", "noon", "afternoon", "bright", "sunny"]) {
            spec.time = .day; spec.understood.append(w)
        } else {
            let times: [TimeOfDay] = [.dawn, .day, .sunset, .night]
            spec.time = times[rng.nextInt(0...3)]
        }

        // Weather
        if let w = has(["storm", "stormy", "thunder", "lightning"]) {
            spec.weather = .storm; spec.understood.append(w)
        } else if let w = has(["rain", "rainy", "drizzle", "monsoon"]) {
            spec.weather = .rain; spec.understood.append(w)
        } else if let w = has(["snow", "snowy", "winter", "blizzard", "frozen"]) {
            spec.weather = .snow; spec.understood.append(w)
        } else if let w = has(["fog", "foggy", "mist", "misty", "haze"]) {
            spec.weather = .fog; spec.understood.append(w)
        } else if let w = has(["cloud", "cloudy", "overcast"]) {
            spec.weather = .cloudy; spec.understood.append(w)
        } else {
            spec.weather = rng.chance(0.55) ? .clear : .cloudy
        }

        // Subject
        var subjectFound = false
        if let w = has(["city", "skyline", "town", "urban", "buildings", "downtown", "metropolis"]) {
            spec.subject = .city; spec.understood.append(w); subjectFound = true
        } else if let w = has(["desert", "dune", "sahara", "sand"]) {
            spec.subject = .desert; spec.understood.append(w); subjectFound = true
        } else if let w = has(["forest", "woods", "jungle", "pine", "tree", "woodland"]) {
            spec.subject = .forest; spec.understood.append(w); subjectFound = true
            spec.hasTrees = true
        } else if let w = has(["ocean", "sea", "beach", "coast", "island", "shore", "wave"]) {
            spec.subject = .ocean; spec.understood.append(w); subjectFound = true
            spec.hasWater = true
        } else if let w = has(["mountain", "peak", "alps", "himalaya", "summit", "valley", "canyon"]) {
            spec.subject = .mountains; spec.understood.append(w); subjectFound = true
        } else if let w = has(["field", "meadow", "plain", "prairie", "grassland"]) {
            spec.subject = .plains; spec.understood.append(w); subjectFound = true
        }
        if !subjectFound {
            let subjects: [Subject] = [.mountains, .ocean, .forest, .desert, .city, .plains]
            spec.subject = subjects[rng.nextInt(0...5)]
            spec.hasTrees = spec.subject == .forest
            spec.hasWater = spec.subject == .ocean
        }

        // Standalone details that can sit on top of any subject
        if let w = has(["lake", "river", "water", "reflection", "bay", "harbor", "harbour"]) {
            spec.hasWater = true; spec.understood.append(w)
        }
        if let w = has(["moon", "moonlight", "lunar"]) {
            spec.hasMoon = true; spec.time = spec.time == .day ? .night : spec.time
            spec.understood.append(w)
        }
        if let w = has(["star", "stars", "galaxy", "cosmic"]) {
            spec.hasStars = true; spec.understood.append(w)
        }
        if let w = has(["bird", "gull", "flock", "crow", "eagle"]) {
            spec.hasBirds = true; spec.understood.append(w)
        }
        if let w = has(["forest", "tree", "pine", "woods"]), !spec.hasTrees {
            spec.hasTrees = true; spec.understood.append(w)
        }

        // Sensible defaults for anything still unset
        if spec.time == .night { spec.hasStars = spec.hasStars || spec.weather == .clear }
        if spec.subject == .ocean { spec.hasWater = true }
        if !spec.hasBirds { spec.hasBirds = rng.chance(0.35) && spec.weather != .storm }
        if spec.time == .night && !spec.hasMoon { spec.hasMoon = rng.chance(0.6) }

        return spec
    }

    /// Short caption shown under the image, e.g. "night · snow · forest".
    var caption: String {
        let t: String
        switch time { case .dawn: t = "dawn"; case .day: t = "day"; case .sunset: t = "sunset"; case .night: t = "night" }
        let w: String
        switch weather {
        case .clear: w = "clear"; case .cloudy: w = "cloudy"; case .rain: w = "rain"
        case .snow: w = "snow"; case .fog: w = "fog"; case .storm: w = "storm"
        }
        let s: String
        switch subject {
        case .mountains: s = "mountains"; case .ocean: s = "ocean"; case .forest: s = "forest"
        case .desert: s = "desert"; case .city: s = "city"; case .plains: s = "plains"
        }
        return "\(t) · \(w) · \(s)"
    }
}

/// Paints the scene described by a SceneSpec, back to front, the way a
/// landscape painter would: sky, light source, clouds, distant ranges,
/// midground, water, foreground, then weather over the top.
enum SceneRenderer {

    static func render(ctx: CGContext, size: CGFloat, spec: SceneSpec, rng: inout SeededRandom, noise: Noise) {
        let s = Double(size)
        let horizon = s * (spec.hasWater ? rng.next(0.52...0.6) : rng.next(0.58...0.68))

        let sky = skyStops(for: spec)
        drawVerticalGradient(ctx: ctx, rect: CGRect(x: 0, y: 0, width: size, height: size), stops: sky)

        // Where the sun or moon sits. Kept above the horizon and away from the
        // very edge so its glow stays in frame.
        let lightX = s * rng.next(0.15...0.85)
        let lightY = horizon - s * rng.next(0.08...0.34)
        let lightColor = lightTint(for: spec)

        if spec.time == .night || spec.hasStars {
            drawStars(ctx: ctx, size: size, horizon: horizon, rng: &rng, density: spec.weather == .clear ? 1.0 : 0.45)
        }

        if spec.weather != .storm {
            if spec.hasMoon || spec.time == .night {
                drawMoon(ctx: ctx, x: lightX, y: lightY, radius: s * rng.next(0.035...0.07), rng: &rng)
            } else {
                drawSun(ctx: ctx, x: lightX, y: lightY, radius: s * rng.next(0.03...0.065), color: lightColor)
            }
        }

        if spec.weather == .cloudy || spec.weather == .rain || spec.weather == .storm || rng.chance(0.6) {
            let count = spec.weather == .clear ? rng.nextInt(2...4) : rng.nextInt(5...10)
            drawClouds(ctx: ctx, size: size, horizon: horizon, count: count,
                       tint: lightColor, dark: spec.weather == .storm || spec.weather == .rain,
                       rng: &rng, noise: noise)
        }

        // Distant ranges. Far layers are washed out toward the sky colour,
        // which is what actually sells the depth.
        let hazeColor = sky.last?.1 ?? RGB(r: 0.6, g: 0.7, b: 0.8)
        switch spec.subject {
        case .mountains:
            drawRanges(ctx: ctx, size: size, horizon: horizon, layers: rng.nextInt(3...5),
                       haze: hazeColor, base: terrainBase(for: spec), snowy: spec.weather == .snow,
                       rng: &rng, noise: noise)
        case .desert:
            drawDunes(ctx: ctx, size: size, horizon: horizon, haze: hazeColor,
                      base: terrainBase(for: spec), rng: &rng, noise: noise)
        case .city:
            drawSkyline(ctx: ctx, size: size, horizon: horizon, night: spec.time == .night,
                        haze: hazeColor, rng: &rng)
        case .forest, .plains, .ocean:
            if rng.chance(0.7) {
                drawRanges(ctx: ctx, size: size, horizon: horizon, layers: rng.nextInt(2...3),
                           haze: hazeColor, base: terrainBase(for: spec), snowy: spec.weather == .snow,
                           rng: &rng, noise: noise)
            }
        }

        if spec.hasWater {
            drawWater(ctx: ctx, size: size, horizon: horizon, sky: sky,
                      lightX: lightX, lightColor: lightColor, rng: &rng)
        } else {
            drawGround(ctx: ctx, size: size, horizon: horizon, spec: spec, rng: &rng, noise: noise)
        }

        if spec.hasTrees {
            drawTreeline(ctx: ctx, size: size, horizon: horizon, spec: spec, rng: &rng)
        }

        if spec.hasBirds {
            drawBirds(ctx: ctx, size: size, horizon: horizon, rng: &rng)
        }

        switch spec.weather {
        case .rain:  drawRain(ctx: ctx, size: size, rng: &rng)
        case .storm: drawRain(ctx: ctx, size: size, rng: &rng); drawLightning(ctx: ctx, size: size, horizon: horizon, rng: &rng)
        case .snow:  drawSnow(ctx: ctx, size: size, rng: &rng)
        case .fog:   drawFog(ctx: ctx, size: size, horizon: horizon, rng: &rng)
        default:     break
        }
    }

    // MARK: - Palettes

    private static func skyStops(for spec: SceneSpec) -> [(Double, RGB)] {
        switch spec.time {
        case .day:
            let top = RGB(r: 0.16, g: 0.38, b: 0.72)
            let mid = RGB(r: 0.43, g: 0.66, b: 0.90)
            let low = RGB(r: 0.78, g: 0.88, b: 0.96)
            return spec.weather == .storm || spec.weather == .rain
                ? [(0, RGB(r: 0.26, g: 0.29, b: 0.34)), (0.6, RGB(r: 0.45, g: 0.48, b: 0.53)), (1, RGB(r: 0.62, g: 0.65, b: 0.68))]
                : [(0, top), (0.55, mid), (1, low)]
        case .sunset:
            return [(0, RGB(r: 0.18, g: 0.13, b: 0.35)),
                    (0.35, RGB(r: 0.55, g: 0.24, b: 0.42)),
                    (0.68, RGB(r: 0.90, g: 0.44, b: 0.30)),
                    (1, RGB(r: 0.99, g: 0.76, b: 0.42))]
        case .dawn:
            return [(0, RGB(r: 0.14, g: 0.20, b: 0.42)),
                    (0.4, RGB(r: 0.45, g: 0.42, b: 0.60)),
                    (0.72, RGB(r: 0.88, g: 0.60, b: 0.55)),
                    (1, RGB(r: 0.99, g: 0.86, b: 0.68))]
        case .night:
            return [(0, RGB(r: 0.02, g: 0.03, b: 0.10)),
                    (0.55, RGB(r: 0.05, g: 0.08, b: 0.20)),
                    (1, RGB(r: 0.12, g: 0.17, b: 0.32))]
        }
    }

    private static func lightTint(for spec: SceneSpec) -> RGB {
        switch spec.time {
        case .day:    return RGB(r: 1.0, g: 0.97, b: 0.85)
        case .sunset: return RGB(r: 1.0, g: 0.72, b: 0.36)
        case .dawn:   return RGB(r: 1.0, g: 0.84, b: 0.66)
        case .night:  return RGB(r: 0.85, g: 0.89, b: 1.0)
        }
    }

    private static func terrainBase(for spec: SceneSpec) -> RGB {
        switch spec.subject {
        case .desert: return RGB(r: 0.78, g: 0.60, b: 0.36)
        case .forest: return RGB(r: 0.13, g: 0.26, b: 0.20)
        case .ocean:  return RGB(r: 0.22, g: 0.30, b: 0.34)
        case .plains: return RGB(r: 0.32, g: 0.42, b: 0.24)
        default:      return RGB(r: 0.24, g: 0.26, b: 0.34)
        }
    }

    // MARK: - Sky furniture

    private static func drawSun(ctx: CGContext, x: Double, y: Double, radius: Double, color: RGB) {
        let space = CGColorSpaceCreateDeviceRGB()
        // Wide soft halo first, then the disc itself.
        if let glow = CGGradient(colorsSpace: space,
                                 colors: [color.withAlpha(0.55), color.withAlpha(0.0)] as CFArray,
                                 locations: [0, 1]) {
            ctx.drawRadialGradient(glow,
                                   startCenter: CGPoint(x: x, y: y), startRadius: CGFloat(radius * 0.6),
                                   endCenter: CGPoint(x: x, y: y), endRadius: CGFloat(radius * 6),
                                   options: [])
        }
        ctx.setFillColor(color.lighten(0.35).withAlpha(1.0))
        ctx.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
    }

    private static func drawMoon(ctx: CGContext, x: Double, y: Double, radius: Double, rng: inout SeededRandom) {
        let pale = RGB(r: 0.93, g: 0.94, b: 0.88)
        let space = CGColorSpaceCreateDeviceRGB()
        if let glow = CGGradient(colorsSpace: space,
                                 colors: [pale.withAlpha(0.35), pale.withAlpha(0.0)] as CFArray,
                                 locations: [0, 1]) {
            ctx.drawRadialGradient(glow,
                                   startCenter: CGPoint(x: x, y: y), startRadius: CGFloat(radius),
                                   endCenter: CGPoint(x: x, y: y), endRadius: CGFloat(radius * 5),
                                   options: [])
        }
        ctx.setFillColor(pale.withAlpha(1.0))
        ctx.fillEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))

        // A few craters so it isn't a flat white circle.
        for _ in 0..<rng.nextInt(3...6) {
            let angle = rng.next(0...(2 * .pi))
            let dist = rng.next(0...0.65) * radius
            let cr = radius * rng.next(0.08...0.2)
            ctx.setFillColor(pale.darken(rng.next(0.06...0.14)).withAlpha(1.0))
            ctx.fillEllipse(in: CGRect(x: x + cos(angle) * dist - cr, y: y + sin(angle) * dist - cr,
                                       width: cr * 2, height: cr * 2))
        }
    }

    private static func drawStars(ctx: CGContext, size: CGFloat, horizon: Double, rng: inout SeededRandom, density: Double) {
        let s = Double(size)
        let count = Int(Double(rng.nextInt(260...620)) * density)
        for _ in 0..<count {
            let x = rng.next(0...1) * s
            // Thin out toward the horizon, the way atmosphere actually does it.
            let y = rng.next(0...1) * horizon * rng.next(0.5...1.0)
            let fade = 1.0 - (y / horizon) * 0.7
            let r = s * rng.next(0.0004...0.0016)
            ctx.setFillColor(RGB(r: 1, g: 1, b: 0.95).withAlpha(rng.next(0.25...0.95) * fade))
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
    }

    private static func drawClouds(ctx: CGContext, size: CGFloat, horizon: Double, count: Int,
                                   tint: RGB, dark: Bool, rng: inout SeededRandom, noise: Noise) {
        let s = Double(size)
        for _ in 0..<count {
            let cx = rng.next(-0.1...1.1) * s
            let cy = rng.next(0.05...0.85) * horizon
            let width = s * rng.next(0.12...0.4)
            let height = width * rng.next(0.18...0.35)
            let puffs = rng.nextInt(9...20)
            let body = dark ? RGB(r: 0.34, g: 0.35, b: 0.40) : tint.mix(RGB(r: 1, g: 1, b: 1), 0.55)
            let shade = body.darken(dark ? 0.18 : 0.12)

            for i in 0..<puffs {
                let t = Double(i) / Double(puffs)
                let px = cx + (t - 0.5) * width + rng.gaussian(sd: width * 0.08)
                let py = cy + rng.gaussian(sd: height * 0.32)
                // Puffs bulge in the middle of the cloud and taper at the ends.
                let r = height * (0.45 + sin(t * .pi) * 0.85) * rng.next(0.7...1.2)
                let lower = py > cy
                ctx.setFillColor((lower ? shade : body).withAlpha(rng.next(0.35...0.7)))
                ctx.fillEllipse(in: CGRect(x: px - r, y: py - r * 0.85, width: r * 2, height: r * 1.7))
            }
        }
    }

    // MARK: - Land

    /// One silhouette ridge, filled from the ridgeline down to the bottom edge.
    private static func fillRidge(ctx: CGContext, size: CGFloat, baseY: Double, amp: Double,
                                  scale: Double, offset: Double, roughness: Int,
                                  color: RGB, noise: Noise) {
        let s = Double(size)
        let samples = 260
        ctx.beginPath()
        ctx.move(to: CGPoint(x: 0, y: size))
        for i in 0...samples {
            let x = s * Double(i) / Double(samples)
            let n = noise.ridged((x + offset) * scale, offset * 0.37, octaves: roughness)
            let y = baseY - (n * 0.5 + 0.5) * amp
            ctx.addLine(to: CGPoint(x: x, y: y))
        }
        ctx.addLine(to: CGPoint(x: size, y: size))
        ctx.closePath()
        ctx.setFillColor(color.withAlpha(1.0))
        ctx.fillPath()
    }

    private static func drawRanges(ctx: CGContext, size: CGFloat, horizon: Double, layers: Int,
                                   haze: RGB, base: RGB, snowy: Bool,
                                   rng: inout SeededRandom, noise: Noise) {
        let s = Double(size)
        for layer in 0..<layers {
            let depth = Double(layers - layer - 1) / Double(max(layers - 1, 1))  // 1 = farthest
            let baseY = horizon - s * 0.02 + Double(layer) * s * rng.next(0.03...0.07)
            let amp = s * (0.10 + depth * 0.16) * rng.next(0.8...1.25)
            let color = base.mix(haze, depth * 0.72).darken(depth * 0.05)

            fillRidge(ctx: ctx, size: size, baseY: baseY, amp: amp,
                      scale: rng.next(0.0018...0.004), offset: rng.next(0...9000),
                      roughness: rng.nextInt(3...5), color: color, noise: noise)

            // Snow caps on the nearer, taller ranges.
            if snowy && depth < 0.5 {
                let samples = 260
                ctx.beginPath()
                var started = false
                let snowLine = baseY - amp * 0.55
                for i in 0...samples {
                    let x = s * Double(i) / Double(samples)
                    let n = noise.ridged(x * 0.0026, 3.0, octaves: 4)
                    let y = baseY - (n * 0.5 + 0.5) * amp
                    if y < snowLine {
                        if !started { ctx.move(to: CGPoint(x: x, y: y)); started = true }
                        else { ctx.addLine(to: CGPoint(x: x, y: y)) }
                    } else if started {
                        ctx.addLine(to: CGPoint(x: x, y: snowLine))
                        started = false
                    }
                }
                ctx.setStrokeColor(RGB(r: 0.95, g: 0.96, b: 0.98).withAlpha(0.75))
                ctx.setLineWidth(CGFloat(s * 0.008))
                ctx.strokePath()
            }
        }
    }

    private static func drawDunes(ctx: CGContext, size: CGFloat, horizon: Double, haze: RGB,
                                  base: RGB, rng: inout SeededRandom, noise: Noise) {
        let s = Double(size)
        let layers = rng.nextInt(4...6)
        for layer in 0..<layers {
            let depth = Double(layers - layer - 1) / Double(max(layers - 1, 1))
            let baseY = horizon + Double(layer) * (s - horizon) / Double(layers) * rng.next(0.7...1.1)
            let amp = s * (0.02 + depth * 0.05)
            let color = base.mix(haze, depth * 0.55).darken(Double(layer) * 0.04)

            let samples = 240
            ctx.beginPath()
            ctx.move(to: CGPoint(x: 0, y: size))
            for i in 0...samples {
                let x = s * Double(i) / Double(samples)
                // Dunes are smoother than rock: plain fBm, few octaves.
                let n = noise.fbm(x * 0.0022 + Double(layer) * 13.0, Double(layer) * 7.0, octaves: 2)
                ctx.addLine(to: CGPoint(x: x, y: baseY - n * amp))
            }
            ctx.addLine(to: CGPoint(x: size, y: size))
            ctx.closePath()
            ctx.setFillColor(color.withAlpha(1.0))
            ctx.fillPath()
        }
    }

    private static func drawSkyline(ctx: CGContext, size: CGFloat, horizon: Double, night: Bool,
                                    haze: RGB, rng: inout SeededRandom) {
        let s = Double(size)
        let rows = rng.nextInt(2...3)
        for row in 0..<rows {
            let depth = Double(rows - row - 1) / Double(max(rows - 1, 1))
            let baseY = horizon + Double(row) * s * 0.035
            let silhouette = RGB(r: 0.10, g: 0.11, b: 0.16).mix(haze, depth * 0.6)
            var x = -s * 0.05
            while x < s * 1.05 {
                let w = s * rng.next(0.03...0.09)
                let h = s * rng.next(0.05...0.26) * (1.0 - depth * 0.35)
                let rect = CGRect(x: x, y: baseY - h, width: w, height: h)
                ctx.setFillColor(silhouette.withAlpha(1.0))
                ctx.fill(rect)

                // Lit windows — only worth drawing on the nearest row at night.
                if night && depth < 0.4 {
                    let cols = max(1, Int(w / (s * 0.012)))
                    let levels = max(1, Int(h / (s * 0.02)))
                    for c in 0..<cols {
                        for l in 0..<levels {
                            guard rng.chance(0.35) else { continue }
                            let wx = rect.minX + CGFloat(Double(c) * (w / Double(cols))) + CGFloat(s * 0.003)
                            let wy = rect.minY + CGFloat(Double(l) * (h / Double(levels))) + CGFloat(s * 0.005)
                            ctx.setFillColor(RGB(r: 1.0, g: 0.85, b: 0.5).withAlpha(rng.next(0.5...0.95)))
                            ctx.fill(CGRect(x: wx, y: wy, width: CGFloat(s * 0.005), height: CGFloat(s * 0.008)))
                        }
                    }
                }
                x += w + s * rng.next(0.002...0.012)
            }
        }
    }

    private static func drawGround(ctx: CGContext, size: CGFloat, horizon: Double, spec: SceneSpec,
                                   rng: inout SeededRandom, noise: Noise) {
        guard spec.subject != .desert, spec.subject != .mountains else { return }
        let s = Double(size)
        var base = terrainBase(for: spec)
        if spec.weather == .snow { base = RGB(r: 0.86, g: 0.89, b: 0.93) }
        if spec.time == .night { base = base.darken(0.55) }

        drawVerticalGradient(ctx: ctx,
                             rect: CGRect(x: 0, y: horizon, width: size, height: size - CGFloat(horizon)),
                             stops: [(0, base.mix(RGB(r: 1, g: 1, b: 1), 0.12)), (1, base.darken(0.35))])

        // Gentle undulation so the ground plane isn't a flat band.
        for i in 0..<rng.nextInt(2...4) {
            let baseY = horizon + (s - horizon) * rng.next(0.2...0.85)
            let samples = 200
            ctx.beginPath()
            ctx.move(to: CGPoint(x: 0, y: size))
            for j in 0...samples {
                let x = s * Double(j) / Double(samples)
                let n = noise.fbm(x * 0.003 + Double(i) * 21.0, Double(i) * 5.0, octaves: 2)
                ctx.addLine(to: CGPoint(x: x, y: baseY - n * s * 0.03))
            }
            ctx.addLine(to: CGPoint(x: size, y: size))
            ctx.closePath()
            ctx.setFillColor(base.darken(0.12 + Double(i) * 0.09).withAlpha(0.9))
            ctx.fillPath()
        }
    }

    private static func drawWater(ctx: CGContext, size: CGFloat, horizon: Double, sky: [(Double, RGB)],
                                  lightX: Double, lightColor: RGB, rng: inout SeededRandom) {
        let s = Double(size)
        let near = (sky.first?.1 ?? RGB(r: 0.1, g: 0.1, b: 0.2)).darken(0.25)
        let far = (sky.last?.1 ?? RGB(r: 0.5, g: 0.6, b: 0.7)).darken(0.15)

        // Water mirrors the sky, so its gradient runs the opposite way.
        drawVerticalGradient(ctx: ctx,
                             rect: CGRect(x: 0, y: horizon, width: size, height: size - CGFloat(horizon)),
                             stops: [(0, far), (1, near)])

        // Sun/moon column: short highlights under the light source, spreading
        // and fading as they come toward the viewer.
        var y = horizon
        while y < s {
            let progress = (y - horizon) / (s - horizon)
            let spread = s * (0.02 + progress * 0.16)
            let count = rng.nextInt(1...3)
            for _ in 0..<count {
                let w = s * rng.next(0.01...0.06) * (1 + progress * 2)
                let x = lightX + rng.gaussian(sd: spread)
                let h = s * 0.004 * (1 + progress * 2)
                ctx.setFillColor(lightColor.withAlpha(rng.next(0.06...0.3) * (1 - progress * 0.55)))
                ctx.fill(CGRect(x: x - w / 2, y: y, width: w, height: h))
            }
            y += s * (0.004 + progress * 0.014)
        }

        // Ripple lines across the whole surface, spaced by perspective.
        var ry = horizon + s * 0.005
        while ry < s {
            let progress = (ry - horizon) / (s - horizon)
            let segments = rng.nextInt(2...6)
            for _ in 0..<segments {
                let w = s * rng.next(0.02...0.14) * (1 + progress)
                let x = rng.next(0...1) * s
                ctx.setFillColor(RGB(r: 1, g: 1, b: 1).withAlpha(rng.next(0.02...0.09)))
                ctx.fill(CGRect(x: x, y: ry, width: w, height: s * 0.0025 * (1 + progress)))
            }
            ry += s * (0.006 + progress * 0.02)
        }
    }

    // MARK: - Foreground

    private static func drawTreeline(ctx: CGContext, size: CGFloat, horizon: Double, spec: SceneSpec,
                                     rng: inout SeededRandom) {
        let s = Double(size)
        let rows = rng.nextInt(2...3)
        for row in 0..<rows {
            let depth = Double(rows - row - 1) / Double(max(rows - 1, 1))
            let baseY = horizon + (s - horizon) * (0.15 + Double(row) * 0.32)
            var green = RGB(r: 0.10, g: 0.24, b: 0.17)
            if spec.time == .night { green = green.darken(0.5) }
            if spec.time == .sunset { green = green.mix(RGB(r: 0.35, g: 0.15, b: 0.10), 0.3) }
            let color = green.mix(RGB(r: 0.55, g: 0.62, b: 0.68), depth * 0.5).darken(-Double(row) * 0.05)

            var x = -s * 0.03
            while x < s * 1.03 {
                let h = s * rng.next(0.05...0.13) * (1.0 + Double(row) * 0.55)
                let w = h * rng.next(0.28...0.42)
                conifer(ctx: ctx, x: x, baseY: baseY, height: h, width: w, color: color,
                        snowy: spec.weather == .snow, rng: &rng)
                x += w * rng.next(0.55...1.1)
            }
        }
    }

    /// A pine drawn as stacked tapering triangles over a short trunk.
    private static func conifer(ctx: CGContext, x: Double, baseY: Double, height: Double, width: Double,
                                color: RGB, snowy: Bool, rng: inout SeededRandom) {
        let tiers = rng.nextInt(3...5)
        ctx.setFillColor(color.darken(0.35).withAlpha(1.0))
        ctx.fill(CGRect(x: x - width * 0.06, y: baseY - height * 0.12, width: width * 0.12, height: height * 0.14))

        for tier in 0..<tiers {
            let t = Double(tier) / Double(tiers)
            let tierTop = baseY - height * (0.18 + 0.82 * (t + 1.0 / Double(tiers)))
            let tierBottom = baseY - height * (0.12 + 0.82 * t)
            let halfWidth = width * (1.0 - t * 0.62) * 0.5
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x, y: tierTop))
            ctx.addLine(to: CGPoint(x: x + halfWidth, y: tierBottom))
            ctx.addLine(to: CGPoint(x: x - halfWidth, y: tierBottom))
            ctx.closePath()
            ctx.setFillColor(color.lighten(t * 0.12).withAlpha(1.0))
            ctx.fillPath()

            if snowy {
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x, y: tierTop))
                ctx.addLine(to: CGPoint(x: x + halfWidth * 0.55, y: tierBottom - (tierBottom - tierTop) * 0.45))
                ctx.addLine(to: CGPoint(x: x - halfWidth * 0.55, y: tierBottom - (tierBottom - tierTop) * 0.45))
                ctx.closePath()
                ctx.setFillColor(RGB(r: 0.94, g: 0.96, b: 0.98).withAlpha(0.8))
                ctx.fillPath()
            }
        }
    }

    private static func drawBirds(ctx: CGContext, size: CGFloat, horizon: Double, rng: inout SeededRandom) {
        let s = Double(size)
        let flock = rng.nextInt(4...11)
        let cx = rng.next(0.2...0.8) * s
        let cy = rng.next(0.12...0.45) * horizon
        ctx.setStrokeColor(RGB(r: 0.12, g: 0.12, b: 0.14).withAlpha(0.75))
        ctx.setLineCap(.round)
        for _ in 0..<flock {
            let x = cx + rng.gaussian(sd: s * 0.09)
            let y = cy + rng.gaussian(sd: s * 0.05)
            let w = s * rng.next(0.008...0.022)
            ctx.setLineWidth(CGFloat(max(w * 0.12, s * 0.0012)))
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x - w, y: y))
            ctx.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x - w * 0.5, y: y - w * 0.55))
            ctx.addQuadCurve(to: CGPoint(x: x + w, y: y), control: CGPoint(x: x + w * 0.5, y: y - w * 0.55))
            ctx.strokePath()
        }
    }

    // MARK: - Weather

    private static func drawRain(ctx: CGContext, size: CGFloat, rng: inout SeededRandom) {
        let s = Double(size)
        let slant = rng.next(-0.35...0.15)
        ctx.setLineCap(.round)
        for _ in 0..<rng.nextInt(400...900) {
            let x = rng.next(-0.1...1.1) * s
            let y = rng.next(0...1) * s
            let len = s * rng.next(0.012...0.045)
            ctx.setStrokeColor(RGB(r: 0.85, g: 0.9, b: 1.0).withAlpha(rng.next(0.08...0.28)))
            ctx.setLineWidth(CGFloat(s * rng.next(0.0006...0.0016)))
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x, y: y))
            ctx.addLine(to: CGPoint(x: x + len * slant, y: y + len))
            ctx.strokePath()
        }
    }

    private static func drawSnow(ctx: CGContext, size: CGFloat, rng: inout SeededRandom) {
        let s = Double(size)
        for _ in 0..<rng.nextInt(500...1100) {
            let x = rng.next(0...1) * s
            let y = rng.next(0...1) * s
            let r = s * rng.next(0.0012...0.0045)
            ctx.setFillColor(RGB(r: 1, g: 1, b: 1).withAlpha(rng.next(0.25...0.85)))
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
    }

    private static func drawFog(ctx: CGContext, size: CGFloat, horizon: Double, rng: inout SeededRandom) {
        let s = Double(size)
        for _ in 0..<rng.nextInt(5...10) {
            let y = rng.next(0.5...1.15) * horizon
            let h = s * rng.next(0.02...0.09)
            ctx.setFillColor(RGB(r: 0.85, g: 0.87, b: 0.9).withAlpha(rng.next(0.06...0.2)))
            ctx.fill(CGRect(x: 0, y: y, width: Double(size), height: h))
        }
    }

    private static func drawLightning(ctx: CGContext, size: CGFloat, horizon: Double, rng: inout SeededRandom) {
        guard rng.chance(0.75) else { return }
        let s = Double(size)
        var x = rng.next(0.2...0.8) * s
        var y = 0.0
        let target = horizon * rng.next(0.75...1.0)
        ctx.setStrokeColor(RGB(r: 1, g: 0.98, b: 0.85).withAlpha(0.9))
        ctx.setLineWidth(CGFloat(s * 0.0035))
        ctx.setLineJoin(.round)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: x, y: y))
        while y < target {
            y += s * rng.next(0.02...0.06)
            x += rng.gaussian(sd: s * 0.02)
            ctx.addLine(to: CGPoint(x: x, y: y))
        }
        ctx.strokePath()
    }

    // MARK: - Helpers

    private static func drawVerticalGradient(ctx: CGContext, rect: CGRect, stops: [(Double, RGB)]) {
        let colors = stops.map { $0.1.cg } as CFArray
        let locations = stops.map { CGFloat($0.0) }
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors, locations: locations) else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: rect.midX, y: rect.minY),
                               end: CGPoint(x: rect.midX, y: rect.maxY),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }
}
