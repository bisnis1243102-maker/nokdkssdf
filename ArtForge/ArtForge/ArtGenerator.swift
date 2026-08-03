import Foundation
import UIKit

/// Everything needed to reproduce a piece exactly.
struct ArtRecipe: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var prompt: String
    var style: ArtStyle
    var seed: UInt64
    var createdAt: Date = Date()

    /// Short human-readable fingerprint, shown under the image.
    var signature: String {
        String(format: "%@ · %04X", style.title.uppercased(), UInt16(truncatingIfNeeded: seed))
    }
}

enum ArtGenerator {

    /// Resolution of the exported image. 1600² keeps saves crisp on modern
    /// displays while staying fast enough to feel instant-ish on device.
    static let exportSize: CGFloat = 1600

    /// The prompt, style, and seed folded together so that changing any one of
    /// them changes everything downstream.
    private static func combinedSeed(_ recipe: ArtRecipe) -> UInt64 {
        stableHash(recipe.prompt) ^ (recipe.seed &* 0x9E3779B97F4A7C15) ^ stableHash(recipe.style.rawValue)
    }

    /// What the scene renderer read out of the prompt, for display under the
    /// image. Mirrors `render`'s use of the generator exactly so the summary
    /// always describes the picture actually on screen.
    static func sceneSummary(for recipe: ArtRecipe) -> String? {
        guard recipe.style == .scene else { return nil }
        var rng = SeededRandom(seed: combinedSeed(recipe))
        _ = Palette.generate(rng: &rng)
        return SceneSpec.parse(prompt: recipe.prompt, rng: &rng).caption
    }

    /// Renders a recipe into a finished image. Pure and thread-safe — call it
    /// off the main queue.
    static func render(_ recipe: ArtRecipe, size: CGFloat = exportSize) -> UIImage {
        let combined = combinedSeed(recipe)
        var rng = SeededRandom(seed: combined)
        let noise = Noise(seed: combined ^ 0xD1B54A32D192ED03)
        let palette = Palette.generate(rng: &rng)

        let pixels = Int(size)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)

        return renderer.image { context in
            let ctx = context.cgContext
            ctx.setFillColor(palette.background.withAlpha(1.0))
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

            switch recipe.style {
            case .scene:
                let spec = SceneSpec.parse(prompt: recipe.prompt, rng: &rng)
                SceneRenderer.render(ctx: ctx, size: size, spec: spec, rng: &rng, noise: noise)

            case .flowField:
                backdrop(ctx: ctx, size: size, palette: palette, rng: &rng)
                Renderers.flowField(ctx: ctx, size: size, palette: palette, rng: &rng, noise: noise)

            case .nebula:
                let canvas = PixelCanvas(width: pixels, height: pixels)
                Renderers.nebula(canvas: canvas, palette: palette, rng: &rng, noise: noise)
                draw(canvas: canvas, in: ctx, size: size)

            case .shards:
                Renderers.shards(ctx: ctx, size: size, palette: palette, rng: &rng, noise: noise)

            case .strata:
                backdrop(ctx: ctx, size: size, palette: palette, rng: &rng)
                Renderers.strata(ctx: ctx, size: size, palette: palette, rng: &rng, noise: noise)

            case .fractal:
                let canvas = PixelCanvas(width: pixels, height: pixels)
                Renderers.fractal(canvas: canvas, palette: palette, rng: &rng)
                draw(canvas: canvas, in: ctx, size: size)

            case .bloom:
                backdrop(ctx: ctx, size: size, palette: palette, rng: &rng)
                Renderers.bloom(ctx: ctx, size: size, palette: palette, rng: &rng, noise: noise)
            }

            // A shared finishing pass is what makes the engines look like they
            // came out of the same studio.
            let vignetteStrength = recipe.style == .scene ? rng.next(0.1...0.22) : rng.next(0.18...0.42)
            vignette(ctx: ctx, size: size, palette: palette, strength: vignetteStrength)
            grain(ctx: ctx, size: size, rng: &rng, amount: rng.next(0.03...0.075))
        }
    }

    // MARK: - Shared passes

    /// A soft gradient wash behind the vector styles so the background is never
    /// a dead flat colour.
    private static func backdrop(ctx: CGContext, size: CGFloat, palette: Palette, rng: inout SeededRandom) {
        let top = palette.background.mix(palette.color(at: rng.next()), 0.16)
        let bottom = palette.background.darken(palette.isDark ? 0.25 : -0.0)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(colorsSpace: space,
                                        colors: [top.cg, bottom.cg] as CFArray,
                                        locations: [0, 1]) else { return }
        let angle = rng.next(0...(2 * .pi))
        let r = Double(size)
        let start = CGPoint(x: size / 2 - CGFloat(cos(angle) * r * 0.6),
                            y: size / 2 - CGFloat(sin(angle) * r * 0.6))
        let end = CGPoint(x: size / 2 + CGFloat(cos(angle) * r * 0.6),
                          y: size / 2 + CGFloat(sin(angle) * r * 0.6))
        ctx.drawLinearGradient(gradient, start: start, end: end, options: [])
    }

    private static func draw(canvas: PixelCanvas, in ctx: CGContext, size: CGFloat) {
        guard let image = canvas.makeImage() else { return }
        ctx.saveGState()
        // Core Graphics has the origin at the bottom left; flip so the buffer
        // lands the right way up.
        ctx.translateBy(x: 0, y: size)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        ctx.restoreGState()
    }

    private static func vignette(ctx: CGContext, size: CGFloat, palette: Palette, strength: Double) {
        let space = CGColorSpaceCreateDeviceRGB()
        let edge = palette.isDark ? RGB(r: 0, g: 0, b: 0) : palette.background.darken(0.35)
        guard let gradient = CGGradient(colorsSpace: space,
                                        colors: [edge.withAlpha(0), edge.withAlpha(strength)] as CFArray,
                                        locations: [0.45, 1.0]) else { return }
        let center = CGPoint(x: size / 2, y: size / 2)
        ctx.drawRadialGradient(gradient,
                               startCenter: center, startRadius: 0,
                               endCenter: center, endRadius: size * 0.78,
                               options: [.drawsAfterEndLocation])
    }

    /// Film grain, built once as a small tile and stretched over the canvas.
    /// Cheaper than per-pixel noise and reads the same at viewing distance.
    private static func grain(ctx: CGContext, size: CGFloat, rng: inout SeededRandom, amount: Double) {
        let tile = 256
        let canvas = PixelCanvas(width: tile, height: tile)
        for y in 0..<tile {
            for x in 0..<tile {
                let v = rng.next()
                canvas.set(x, y, RGB(r: v, g: v, b: v))
            }
        }
        guard let image = canvas.makeImage() else { return }
        ctx.saveGState()
        ctx.setAlpha(CGFloat(amount))
        ctx.setBlendMode(.overlay)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size), byTiling: false)
        ctx.restoreGState()
    }
}
