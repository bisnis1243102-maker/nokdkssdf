import Foundation
import UIKit

/// The available render engines. Each one is a genuinely different algorithm,
/// not a filter over the same base image.
enum ArtStyle: String, CaseIterable, Identifiable, Codable {
    case scene
    case flowField
    case nebula
    case shards
    case strata
    case fractal
    case bloom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scene:     return "Scene"
        case .flowField: return "Flow"
        case .nebula:    return "Nebula"
        case .shards:    return "Shards"
        case .strata:    return "Strata"
        case .fractal:   return "Fractal"
        case .bloom:     return "Bloom"
        }
    }

    var symbol: String {
        switch self {
        case .scene:     return "photo"
        case .flowField: return "wind"
        case .nebula:    return "sparkles"
        case .shards:    return "diamond"
        case .strata:    return "water.waves"
        case .fractal:   return "camera.filters"
        case .bloom:     return "circle.hexagongrid"
        }
    }

    var blurb: String {
        switch self {
        case .scene:     return "A landscape painted from the words in your prompt"
        case .flowField: return "Thousands of particles drifting through a turbulent field"
        case .nebula:    return "Layered clouds of light, rendered pixel by pixel"
        case .shards:    return "Fractured planes of colour with hard, clean edges"
        case .strata:    return "Sediment ridges stacked into a topographic landscape"
        case .fractal:   return "A Julia set, coloured by escape time"
        case .bloom:     return "Circles packed until no space is left"
        }
    }
}

enum Renderers {

    // MARK: Flow field

    /// Particles are released across the canvas and pushed along the gradient of
    /// a noise field, leaving translucent trails. Overlapping strokes build up
    /// depth the way ink does on wet paper.
    static func flowField(ctx: CGContext, size: CGFloat, palette: Palette, rng: inout SeededRandom, noise: Noise) {
        let s = Double(size)
        let scale = rng.next(0.0012...0.0032)
        let octaves = rng.nextInt(2...5)
        let turbulence = rng.next(2.0...7.0)
        let particleCount = rng.nextInt(1400...2600)
        let steps = rng.nextInt(90...200)
        let stepLength = s * rng.next(0.0016...0.0038)
        let lineWidth = s * rng.next(0.0008...0.0034)
        let alpha = rng.next(0.05...0.16)
        let curl = rng.chance(0.5)

        ctx.setLineCap(.round)
        ctx.setLineWidth(CGFloat(lineWidth))
        ctx.setBlendMode(palette.isDark ? .plusLighter : .multiply)

        for _ in 0..<particleCount {
            var x = rng.next(-0.1...1.1) * s
            var y = rng.next(-0.1...1.1) * s
            let colorSeed = rng.next()
            let life = rng.nextInt(steps / 3...steps)

            var color = palette.color(at: colorSeed)
            if rng.chance(0.12) { color = color.lighten(0.45) }
            ctx.setStrokeColor(color.withAlpha(alpha * rng.next(0.6...1.4)))

            ctx.beginPath()
            ctx.move(to: CGPoint(x: x, y: y))
            var drew = false

            for _ in 0..<life {
                let n = noise.fbm(x * scale, y * scale, octaves: octaves)
                // A second, offset sample turns the field from a simple slope
                // into something that swirls back on itself.
                let m = curl ? noise.fbm((x + 1731) * scale, (y - 991) * scale, octaves: octaves) : 0
                let angle = (n * turbulence + m * turbulence * 0.6) * .pi

                x += cos(angle) * stepLength
                y += sin(angle) * stepLength

                if x < -s * 0.15 || x > s * 1.15 || y < -s * 0.15 || y > s * 1.15 { break }
                ctx.addLine(to: CGPoint(x: x, y: y))
                drew = true
            }
            if drew { ctx.strokePath() }
        }
        ctx.setBlendMode(.normal)
    }

    // MARK: Nebula

    /// Evaluated per pixel: domain-warped noise drives both the colour ramp and
    /// the brightness, with a soft glow where the field peaks.
    static func nebula(canvas: PixelCanvas, palette: Palette, rng: inout SeededRandom, noise: Noise) {
        let scale = rng.next(0.0014...0.0045)
        let warpStrength = rng.next(40...260)
        let octaves = rng.nextInt(4...7)
        let contrast = rng.next(1.0...2.6)
        let ridgeMix = rng.chance(0.45) ? rng.next(0.3...0.9) : 0.0
        let glow = rng.next(0.15...0.6)
        let offsetX = rng.next(-4000...4000)
        let offsetY = rng.next(-4000...4000)

        for py in 0..<canvas.height {
            let y = Double(py) + offsetY
            for px in 0..<canvas.width {
                let x = Double(px) + offsetX

                // Domain warping: sample noise, then use that to move where we
                // sample again. This is what gives the smoke-like filaments.
                let wx = noise.fbm(x * scale, y * scale, octaves: 3) * warpStrength
                let wy = noise.fbm((x + 5237) * scale, (y + 1471) * scale, octaves: 3) * warpStrength

                var v = noise.fbm((x + wx) * scale, (y + wy) * scale, octaves: octaves)
                if ridgeMix > 0 {
                    let r = noise.ridged((x + wx) * scale * 1.7, (y + wy) * scale * 1.7, octaves: 4)
                    v = v * (1 - ridgeMix) + r * ridgeMix
                }

                var t = (v + 1) * 0.5
                t = min(max((t - 0.5) * contrast + 0.5, 0), 1)

                var color = palette.color(at: t)
                let intensity = pow(t, 2.4) * glow
                color = palette.background.mix(color, min(0.15 + t * 1.1, 1.0)).lighten(intensity * 0.55)
                canvas.set(px, py, color)
            }
        }
    }

    // MARK: Shards

    /// Recursive subdivision: split a rectangle along a random line, again and
    /// again, then fill each cell. Occasionally a cell is rotated into a
    /// triangle so the composition doesn't read as a plain grid.
    static func shards(ctx: CGContext, size: CGFloat, palette: Palette, rng: inout SeededRandom, noise: Noise) {
        let depth = rng.nextInt(6...9)
        let gap = Double(size) * rng.next(0.0...0.006)
        let strokeEdges = rng.chance(0.5)
        let triangleChance = rng.next(0.1...0.4)
        let edgeColor = palette.isDark ? palette.background.darken(0.4) : palette.background.darken(0.85)

        func fill(_ rect: CGRect, _ level: Int, _ rng: inout SeededRandom) {
            let inset = rect.insetBy(dx: CGFloat(gap), dy: CGFloat(gap))
            guard inset.width > 1, inset.height > 1 else { return }

            // Colour by position in the field so neighbouring shards relate to
            // one another instead of being independently random.
            let nx = Double(inset.midX) * 0.0022
            let ny = Double(inset.midY) * 0.0022
            var t = (noise.fbm(nx, ny, octaves: 3) + 1) * 0.5
            t = min(max(t + rng.next(-0.12...0.12), 0), 1)
            let color = palette.color(at: t)

            ctx.setFillColor(color.withAlpha(rng.next(0.82...1.0)))

            if rng.chance(triangleChance) {
                let corners = [
                    CGPoint(x: inset.minX, y: inset.minY), CGPoint(x: inset.maxX, y: inset.minY),
                    CGPoint(x: inset.maxX, y: inset.maxY), CGPoint(x: inset.minX, y: inset.maxY)
                ]
                let drop = rng.nextInt(0...3)
                ctx.beginPath()
                var first = true
                for (i, c) in corners.enumerated() where i != drop {
                    if first { ctx.move(to: c); first = false } else { ctx.addLine(to: c) }
                }
                ctx.closePath()
                ctx.fillPath()
            } else {
                ctx.fill(inset)
            }

            if strokeEdges {
                ctx.setStrokeColor(edgeColor.withAlpha(0.5))
                ctx.setLineWidth(max(1, size * 0.0012))
                ctx.stroke(inset)
            }

            // A few cells get a contrasting accent bar — the visual equivalent
            // of a rest in music.
            if level > 2 && rng.chance(0.1) {
                let accent = palette.color(at: rng.next()).lighten(palette.isDark ? 0.5 : 0.0).darken(palette.isDark ? 0.0 : 0.4)
                ctx.setFillColor(accent.withAlpha(0.9))
                let horizontal = rng.chance(0.5)
                let thickness = CGFloat(rng.next(0.06...0.22))
                let bar = horizontal
                    ? CGRect(x: inset.minX, y: inset.midY - inset.height * thickness / 2, width: inset.width, height: inset.height * thickness)
                    : CGRect(x: inset.midX - inset.width * thickness / 2, y: inset.minY, width: inset.width * thickness, height: inset.height)
                ctx.fill(bar)
            }
        }

        func split(_ rect: CGRect, _ level: Int, _ rng: inout SeededRandom) {
            // Stop early sometimes so the piece has both dense and open areas.
            if level <= 0 || (level < depth - 2 && rng.chance(0.18)) || rect.width < size * 0.02 || rect.height < size * 0.02 {
                fill(rect, level, &rng)
                return
            }
            let horizontal = rect.width > rect.height ? rng.chance(0.78) : rng.chance(0.22)
            let ratio = CGFloat(rng.next(0.28...0.72))
            if horizontal {
                let w = rect.width * ratio
                split(CGRect(x: rect.minX, y: rect.minY, width: w, height: rect.height), level - 1, &rng)
                split(CGRect(x: rect.minX + w, y: rect.minY, width: rect.width - w, height: rect.height), level - 1, &rng)
            } else {
                let h = rect.height * ratio
                split(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h), level - 1, &rng)
                split(CGRect(x: rect.minX, y: rect.minY + h, width: rect.width, height: rect.height - h), level - 1, &rng)
            }
        }

        split(CGRect(x: 0, y: 0, width: size, height: size), depth, &rng)
    }

    // MARK: Strata

    /// Stacked ridge lines, each one clipping everything behind it, so the rows
    /// occlude each other and read as depth rather than as flat stripes.
    static func strata(ctx: CGContext, size: CGFloat, palette: Palette, rng: inout SeededRandom, noise: Noise) {
        let s = Double(size)
        let rows = rng.nextInt(30...90)
        let amplitude = s * rng.next(0.03...0.13)
        let scale = rng.next(0.0018...0.0055)
        let octaves = rng.nextInt(2...5)
        let strokeWidth = s * rng.next(0.0012...0.0035)
        let filled = rng.chance(0.75)
        let topMargin = s * rng.next(0.05...0.2)
        let usableHeight = s - topMargin - s * 0.05
        let drift = rng.next(-0.35...0.35)

        for row in 0..<rows {
            let progress = Double(row) / Double(rows - 1)
            let baseY = topMargin + usableHeight * progress
            // Ridges peak in the middle of the canvas and flatten at the edges.
            let envelope = sin(progress * .pi) * 0.7 + 0.3
            let rowAmp = amplitude * envelope * (1.0 + drift * progress)

            var points: [CGPoint] = []
            let sampleCount = 220
            for i in 0...sampleCount {
                let x = s * Double(i) / Double(sampleCount)
                let n = noise.fbm(x * scale, baseY * scale * 2.4, octaves: octaves)
                let y = baseY - n * rowAmp
                points.append(CGPoint(x: x, y: y))
            }

            let t = progress
            let color = palette.color(at: 1.0 - t)

            ctx.beginPath()
            ctx.move(to: CGPoint(x: 0, y: points[0].y))
            for p in points.dropFirst() { ctx.addLine(to: p) }

            if filled {
                // Close the path below the ridge and fill it with the background
                // so lower rows are hidden behind this one.
                ctx.addLine(to: CGPoint(x: size, y: size))
                ctx.addLine(to: CGPoint(x: 0, y: size))
                ctx.closePath()
                let fillColor = palette.background.mix(color, 0.16 + t * 0.2)
                ctx.setFillColor(fillColor.withAlpha(1.0))
                ctx.fillPath()

                ctx.beginPath()
                ctx.move(to: CGPoint(x: 0, y: points[0].y))
                for p in points.dropFirst() { ctx.addLine(to: p) }
            }

            ctx.setLineWidth(CGFloat(strokeWidth))
            ctx.setLineJoin(.round)
            ctx.setStrokeColor(color.withAlpha(0.9))
            ctx.strokePath()
        }
    }

    // MARK: Fractal

    /// Julia set, escape-time coloured with a smooth (continuous) iteration
    /// count so there are no visible banding rings.
    static func fractal(canvas: PixelCanvas, palette: Palette, rng: inout SeededRandom) {
        // Constants picked near the boundary of the Mandelbrot set, where Julia
        // sets are the most intricate.
        let interesting: [(Double, Double)] = [
            (-0.7269, 0.1889), (-0.8, 0.156), (0.285, 0.01), (-0.4, 0.6),
            (0.37, 0.1), (-0.70176, -0.3842), (-0.835, -0.2321), (0.35, 0.35),
            (-0.162, 1.04), (-0.79, 0.15)
        ]
        var (cx, cy) = rng.pick(interesting)
        cx += rng.next(-0.02...0.02)
        cy += rng.next(-0.02...0.02)

        let maxIter = rng.nextInt(180...400)
        let zoom = rng.next(0.7...1.9)
        let panX = rng.next(-0.35...0.35)
        let panY = rng.next(-0.35...0.35)
        let rotation = rng.next(0...(2 * .pi))
        let cosR = cos(rotation), sinR = sin(rotation)
        let cycles = rng.next(1.0...3.5)
        let phase = rng.next(0...1)

        let w = Double(canvas.width), h = Double(canvas.height)
        let escape = 256.0

        for py in 0..<canvas.height {
            let v = (Double(py) / h - 0.5) * 3.0 / zoom + panY
            for px in 0..<canvas.width {
                let u = (Double(px) / w - 0.5) * 3.0 / zoom + panX

                var zx = u * cosR - v * sinR
                var zy = u * sinR + v * cosR

                var i = 0
                var magSquared = 0.0
                while i < maxIter {
                    let xx = zx * zx
                    let yy = zy * zy
                    magSquared = xx + yy
                    if magSquared > escape { break }
                    zy = 2 * zx * zy + cy
                    zx = xx - yy + cx
                    i += 1
                }

                if i >= maxIter {
                    // Interior: keep it quiet so the filaments stand out.
                    canvas.set(px, py, palette.background.darken(0.25))
                } else {
                    // Smooth iteration count removes the stair-step contours.
                    let smooth = Double(i) + 1.0 - (log(log(max(sqrt(magSquared), 1.0001))) / log(2.0))
                    var t = smooth / Double(maxIter)
                    t = pow(min(max(t, 0), 1), 0.42)
                    let cycled = (t * cycles + phase).truncatingRemainder(dividingBy: 1.0)
                    // Ping-pong the ramp so the colour cycles seamlessly.
                    let folded = cycled < 0.5 ? cycled * 2 : (1 - cycled) * 2
                    canvas.set(px, py, palette.color(at: folded))
                }
            }
        }
    }

    // MARK: Bloom

    /// Circle packing by dart throwing: try a random spot, grow the circle until
    /// it touches a neighbour, keep it if it ended up big enough.
    static func bloom(ctx: CGContext, size: CGFloat, palette: Palette, rng: inout SeededRandom, noise: Noise) {
        let s = Double(size)
        let attempts = rng.nextInt(9000...20000)
        let minRadius = s * rng.next(0.0022...0.006)
        let maxRadius = s * rng.next(0.05...0.16)
        let padding = s * rng.next(0.0004...0.004)
        let ringed = rng.chance(0.45)
        let noiseScale = rng.next(0.0015...0.004)
        let radial = rng.chance(0.4)
        let centerX = s * rng.next(0.3...0.7)
        let centerY = s * rng.next(0.3...0.7)

        var placed: [(x: Double, y: Double, r: Double)] = []
        // A uniform grid over the canvas keeps the collision test local rather
        // than checking against every circle placed so far.
        let cellSize = maxRadius
        let cols = max(1, Int(s / cellSize) + 1)
        var grid = [[Int]](repeating: [], count: cols * cols)

        @inline(__always)
        func cellIndex(_ x: Double, _ y: Double) -> (Int, Int) {
            (min(max(Int(x / cellSize), 0), cols - 1), min(max(Int(y / cellSize), 0), cols - 1))
        }

        for _ in 0..<attempts {
            let x = rng.next(0...1) * s
            let y = rng.next(0...1) * s

            // Local density: bigger circles where the noise field is high.
            let density = (noise.fbm(x * noiseScale, y * noiseScale, octaves: 3) + 1) * 0.5
            var ceiling = minRadius + (maxRadius - minRadius) * pow(density, 1.6)
            if radial {
                let d = sqrt(pow(x - centerX, 2) + pow(y - centerY, 2)) / (s * 0.7)
                ceiling *= min(max(1.0 - d * 0.75, 0.12), 1.0)
            }
            if ceiling < minRadius { continue }

            var r = ceiling
            let (gx, gy) = cellIndex(x, y)
            var blocked = false
            for dy in -1...1 {
                for dx in -1...1 {
                    let nx = gx + dx, ny = gy + dy
                    guard nx >= 0, nx < cols, ny >= 0, ny < cols else { continue }
                    for idx in grid[ny * cols + nx] {
                        let other = placed[idx]
                        let dist = sqrt(pow(x - other.x, 2) + pow(y - other.y, 2)) - other.r - padding
                        if dist < minRadius { blocked = true; break }
                        r = min(r, dist)
                    }
                    if blocked { break }
                }
                if blocked { break }
            }
            if blocked { continue }

            // Keep it inside the canvas edges too.
            r = min(r, x, y, s - x, s - y)
            if r < minRadius { continue }

            placed.append((x, y, r))
            grid[gy * cols + gx].append(placed.count - 1)
        }

        for circle in placed {
            let t = (noise.fbm(circle.x * noiseScale * 1.4, circle.y * noiseScale * 1.4, octaves: 2) + 1) * 0.5
            let color = palette.color(at: min(max(t + rng.next(-0.1...0.1), 0), 1))
            let rect = CGRect(x: circle.x - circle.r, y: circle.y - circle.r,
                              width: circle.r * 2, height: circle.r * 2)

            ctx.setFillColor(color.withAlpha(rng.next(0.75...1.0)))
            ctx.fillEllipse(in: rect)

            if ringed && circle.r > minRadius * 3 && rng.chance(0.55) {
                // Concentric rings inside the larger circles.
                let rings = rng.nextInt(1...4)
                for k in 1...rings {
                    let rr = circle.r * (1.0 - Double(k) / Double(rings + 1))
                    let ringColor = palette.color(at: min(max(t + Double(k) * 0.13, 0), 1))
                        .mix(palette.background, 0.15)
                    ctx.setFillColor(ringColor.withAlpha(0.9))
                    ctx.fillEllipse(in: CGRect(x: circle.x - rr, y: circle.y - rr, width: rr * 2, height: rr * 2))
                }
            }
        }
    }
}
