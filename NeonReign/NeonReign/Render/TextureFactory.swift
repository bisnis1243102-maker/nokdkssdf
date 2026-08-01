import UIKit
import SceneKit

/// Generates every texture the game uses at runtime — albedo, tangent-space
/// normal, roughness and AO — so the app ships no binary art at all.
///
/// Maps are cached by key: the city reuses a handful of surface classes across
/// thousands of nodes, and regenerating them per node would stall the load.
enum TextureFactory {

    // MARK: Variant caps
    //
    // Textures vary by *style*, never by instance. Keying the cache on a
    // per-building seed is what made the city allocate ~300 map sets and get
    // the app killed on launch; every entry point below folds its seed into a
    // small fixed range so the cache size is bounded by construction.

    static let facadeVariants = 3
    static let neonVariants = 8
    static let metalVariants = 4

    /// Folds any seed into `0..<count`, negatives included.
    static func variant(_ seed: Int, _ count: Int) -> Int {
        ((seed % count) + count) % count
    }

    // MARK: Resolution caps
    //
    // Only the road really benefits from resolution and the 16x anisotropy —
    // it is the surface the camera looks straight down. Everything else is seen
    // at distance and is capped much lower.

    static func roadSize(_ tier: Int) -> Int { min(512, tier) }
    static func detailSize(_ tier: Int) -> Int { min(256, tier) }

    // MARK: Cache

    private static var cache: [String: UIImage] = [:]
    private static let lock = NSLock()
    /// Running total of generated pixel data, so a regression shows up as a
    /// number in the log rather than as a blank screen.
    private static var generatedBytes = 0

    /// Approximate size of everything generated so far, in megabytes.
    static var generatedTextureMB: Double {
        lock.lock(); defer { lock.unlock() }
        return Double(generatedBytes) / 1_000_000
    }

    static var cacheCount: Int {
        lock.lock(); defer { lock.unlock() }
        return cache.count
    }

    private static func cached(_ key: String, _ make: () -> UIImage) -> UIImage {
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        let img = make()
        cache[key] = img
        generatedBytes += Int(img.size.width * img.size.height * 4)
        return img
    }

    /// Dropped when the quality tier changes, since map resolution changes too.
    static func flush() {
        lock.lock()
        cache.removeAll()
        generatedBytes = 0
        lock.unlock()
    }

    // MARK: Low-level drawing

    private static func image(_ size: Int, _ draw: (CGContext, CGFloat) -> Void) -> UIImage {
        let s = CGFloat(size)
        let r = UIGraphicsImageRenderer(size: CGSize(width: s, height: s))
        return r.image { ctx in draw(ctx.cgContext, s) }
    }

    /// Builds a tangent-space normal map by taking the gradient of a height
    /// field. `height` returns 0...1 for a pixel.
    private static func normalMap(_ size: Int, strength: CGFloat,
                                  height: (Int, Int) -> CGFloat) -> UIImage {
        var px = [UInt8](repeating: 0, count: size * size * 4)
        func h(_ x: Int, _ y: Int) -> CGFloat {
            height((x + size) % size, (y + size) % size)
        }
        for y in 0..<size {
            for x in 0..<size {
                let dx = (h(x + 1, y) - h(x - 1, y)) * strength
                let dy = (h(x, y + 1) - h(x, y - 1)) * strength
                // Normalise (-dx, -dy, 1)
                let len = sqrt(dx * dx + dy * dy + 1)
                let nx = -dx / len, ny = -dy / len, nz = 1 / len
                let i = (y * size + x) * 4
                px[i]     = UInt8(max(0, min(255, (nx * 0.5 + 0.5) * 255)))
                px[i + 1] = UInt8(max(0, min(255, (ny * 0.5 + 0.5) * 255)))
                px[i + 2] = UInt8(max(0, min(255, (nz * 0.5 + 0.5) * 255)))
                px[i + 3] = 255
            }
        }
        return rgbaImage(px, size)
    }

    /// Single-channel data written as grey RGBA — SceneKit reads roughness and
    /// AO from the red channel, and grey keeps the maps readable when debugging.
    private static func greyMap(_ size: Int, value: (Int, Int) -> CGFloat) -> UIImage {
        var px = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let v = UInt8(max(0, min(255, value(x, y) * 255)))
                let i = (y * size + x) * 4
                px[i] = v; px[i + 1] = v; px[i + 2] = v; px[i + 3] = 255
            }
        }
        return rgbaImage(px, size)
    }

    private static func rgbaImage(_ px: [UInt8], _ size: Int) -> UIImage {
        var data = px
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx = CGContext(data: &data, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: cs, bitmapInfo: info.rawValue),
              let cg = ctx.makeImage() else {
            return UIImage()
        }
        return UIImage(cgImage: cg)
    }

    // MARK: Deterministic value noise
    //
    // A seeded hash keeps the city identical between launches, which matters
    // because mission markers are placed against baked-in landmarks.

    private static func hash(_ x: Int, _ y: Int, _ seed: Int) -> CGFloat {
        var h = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263 &+ seed &* 2_147_483_647)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h = h ^ (h >> 16)
        return CGFloat(h % 10_000) / 10_000
    }

    private static func smoothNoise(_ x: CGFloat, _ y: CGFloat, _ seed: Int) -> CGFloat {
        let xi = Int(floor(x)), yi = Int(floor(y))
        let xf = x - floor(x), yf = y - floor(y)
        let u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf)
        let a = hash(xi, yi, seed), b = hash(xi + 1, yi, seed)
        let c = hash(xi, yi + 1, seed), d = hash(xi + 1, yi + 1, seed)
        return (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v
    }

    /// Fractal noise, 4 octaves.
    static func fbm(_ x: CGFloat, _ y: CGFloat, _ seed: Int) -> CGFloat {
        var sum: CGFloat = 0, amp: CGFloat = 0.5, freq: CGFloat = 1, norm: CGFloat = 0
        for _ in 0..<4 {
            sum += smoothNoise(x * freq, y * freq, seed) * amp
            norm += amp
            amp *= 0.5; freq *= 2
        }
        return sum / norm
    }

    // MARK: - Surface classes

    /// A full PBR map set for one surface.
    struct MapSet {
        let albedo: UIImage
        let normal: UIImage
        let roughness: UIImage
        let ao: UIImage
    }

    // MARK: Asphalt

    static func asphalt(size: Int, laneMarking: Bool) -> MapSet {
        let key = "asphalt-\(size)-\(laneMarking)"
        let albedo = cached(key + "-a") {
            image(size) { ctx, s in
                ctx.setFillColor(UIColor(white: 0.085, alpha: 1).cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
                // Aggregate speckle.
                let step = max(1, size / 128)
                for y in stride(from: 0, to: size, by: step) {
                    for x in stride(from: 0, to: size, by: step) {
                        let n = fbm(CGFloat(x) / 9, CGFloat(y) / 9, 11)
                        let g = 0.055 + n * 0.10
                        ctx.setFillColor(UIColor(white: g, alpha: 1).cgColor)
                        ctx.fill(CGRect(x: CGFloat(x), y: CGFloat(y),
                                        width: CGFloat(step), height: CGFloat(step)))
                    }
                }
                // Old tarmac patches.
                for i in 0..<7 {
                    let n = fbm(CGFloat(i) * 3.1, 0.5, 23)
                    ctx.setFillColor(UIColor(white: 0.10 + n * 0.05, alpha: 0.5).cgColor)
                    ctx.fillEllipse(in: CGRect(x: n * s, y: fbm(0.7, CGFloat(i), 5) * s,
                                               width: s * 0.28, height: s * 0.18))
                }
                if laneMarking {
                    ctx.setFillColor(UIColor(white: 0.78, alpha: 0.85).cgColor)
                    let w = s * 0.045
                    // Dashed centre line running down the tile.
                    var y: CGFloat = 0
                    while y < s {
                        ctx.fill(CGRect(x: s / 2 - w / 2, y: y, width: w, height: s * 0.16))
                        y += s * 0.32
                    }
                }
            }
        }
        let normal = cached(key + "-n") {
            normalMap(size, strength: 2.4) { x, y in
                let base = fbm(CGFloat(x) / 7, CGFloat(y) / 7, 11)
                // A few cracks scored across the surface.
                let crack = abs(fbm(CGFloat(x) / 26, CGFloat(y) / 26, 41) - 0.5) < 0.02 ? -0.5 : 0
                return base + crack
            }
        }
        let rough = cached(key + "-r") {
            greyMap(size) { x, y in 0.62 + fbm(CGFloat(x) / 11, CGFloat(y) / 11, 17) * 0.3 }
        }
        let ao = cached(key + "-o") {
            greyMap(size) { x, y in 0.80 + fbm(CGFloat(x) / 15, CGFloat(y) / 15, 29) * 0.2 }
        }
        return MapSet(albedo: albedo, normal: normal, roughness: rough, ao: ao)
    }

    // MARK: Sidewalk

    static func sidewalk(size: Int) -> MapSet {
        let key = "sidewalk-\(size)"
        let albedo = cached(key + "-a") {
            image(size) { ctx, s in
                ctx.setFillColor(UIColor(white: 0.30, alpha: 1).cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
                let cells = 4
                let c = s / CGFloat(cells)
                for gy in 0..<cells {
                    for gx in 0..<cells {
                        let n = hash(gx, gy, 7)
                        ctx.setFillColor(UIColor(white: 0.26 + n * 0.10, alpha: 1).cgColor)
                        ctx.fill(CGRect(x: CGFloat(gx) * c + 1, y: CGFloat(gy) * c + 1,
                                        width: c - 2, height: c - 2))
                    }
                }
            }
        }
        let normal = cached(key + "-n") {
            normalMap(size, strength: 5) { x, y in
                let c = size / 4
                let ex = min(x % c, c - 1 - x % c), ey = min(y % c, c - 1 - y % c)
                let edge = CGFloat(min(ex, ey))
                return min(1, edge / 3) * 0.8 + fbm(CGFloat(x) / 5, CGFloat(y) / 5, 3) * 0.2
            }
        }
        let rough = cached(key + "-r") {
            greyMap(size) { x, y in 0.70 + fbm(CGFloat(x) / 9, CGFloat(y) / 9, 13) * 0.2 }
        }
        let ao = cached(key + "-o") {
            greyMap(size) { x, y in
                let c = size / 4
                let ex = min(x % c, c - 1 - x % c), ey = min(y % c, c - 1 - y % c)
                return 0.6 + min(1, CGFloat(min(ex, ey)) / 3) * 0.4
            }
        }
        return MapSet(albedo: albedo, normal: normal, roughness: rough, ao: ao)
    }

    // MARK: Facades
    //
    // One tile per district tint, with lit/unlit window cells baked into the
    // albedo and an emission mask returned separately for night.

    static func facade(size: Int, tint: UIColor, seed: Int) -> MapSet {
        // One of a handful of styles per district, never one per building.
        let seed = variant(seed, facadeVariants)
        let key = "facade-\(size)-\(tint.hashValue)-\(seed)"
        let albedo = cached(key + "-a") {
            image(size) { ctx, s in
                ctx.setFillColor(tint.cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
                // Concrete grain.
                let step = max(1, size / 96)
                for y in stride(from: 0, to: size, by: step) {
                    for x in stride(from: 0, to: size, by: step) {
                        let n = fbm(CGFloat(x) / 8, CGFloat(y) / 8, seed)
                        ctx.setFillColor(UIColor(white: 0, alpha: (0.5 - n) * 0.22).cgColor)
                        ctx.fill(CGRect(x: CGFloat(x), y: CGFloat(y),
                                        width: CGFloat(step), height: CGFloat(step)))
                    }
                }
                // Window grid.
                let cols = 6, rows = 8
                let cw = s / CGFloat(cols), ch = s / CGFloat(rows)
                for r in 0..<rows {
                    for c in 0..<cols {
                        let lit = hash(c, r, seed) > 0.55
                        let col = lit
                            ? UIColor(red: 1.0, green: 0.86, blue: 0.62, alpha: 1)
                            : UIColor(red: 0.05, green: 0.07, blue: 0.11, alpha: 1)
                        ctx.setFillColor(col.cgColor)
                        ctx.fill(CGRect(x: CGFloat(c) * cw + cw * 0.20,
                                        y: CGFloat(r) * ch + ch * 0.18,
                                        width: cw * 0.60, height: ch * 0.52))
                    }
                }
            }
        }
        let normal = cached(key + "-n") {
            normalMap(size, strength: 6) { x, y in
                let cols = 6, rows = 8
                let cw = size / cols, ch = size / rows
                let ix = x % cw, iy = y % ch
                let inWindow = CGFloat(ix) > CGFloat(cw) * 0.20 && CGFloat(ix) < CGFloat(cw) * 0.80
                    && CGFloat(iy) > CGFloat(ch) * 0.18 && CGFloat(iy) < CGFloat(ch) * 0.70
                return inWindow ? 0.25 : 1.0
            }
        }
        let rough = cached(key + "-r") {
            greyMap(size) { x, y in
                let cols = 6, rows = 8
                let cw = size / cols, ch = size / rows
                let ix = x % cw, iy = y % ch
                let inWindow = CGFloat(ix) > CGFloat(cw) * 0.20 && CGFloat(ix) < CGFloat(cw) * 0.80
                    && CGFloat(iy) > CGFloat(ch) * 0.18 && CGFloat(iy) < CGFloat(ch) * 0.70
                // Glass is smooth, concrete is not.
                return inWindow ? 0.12 : (0.72 + fbm(CGFloat(x) / 10, CGFloat(y) / 10, seed) * 0.2)
            }
        }
        let ao = cached(key + "-o") {
            greyMap(size) { x, y in
                let ch = size / 8
                let iy = y % ch
                // Darken just under each window ledge.
                return CGFloat(iy) > CGFloat(ch) * 0.70 && CGFloat(iy) < CGFloat(ch) * 0.82 ? 0.55 : 1.0
            }
        }
        return MapSet(albedo: albedo, normal: normal, roughness: rough, ao: ao)
    }

    /// Emission mask for a facade: lit window cells glow at night.
    static func facadeEmission(size: Int, seed: Int, warm: UIColor) -> UIImage {
        let seed = variant(seed, facadeVariants)
        return cached("facade-e-\(size)-\(seed)-\(warm.hashValue)") {
            image(size) { ctx, s in
                ctx.setFillColor(UIColor.black.cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
                let cols = 6, rows = 8
                let cw = s / CGFloat(cols), ch = s / CGFloat(rows)
                for r in 0..<rows {
                    for c in 0..<cols where hash(c, r, seed) > 0.55 {
                        ctx.setFillColor(warm.cgColor)
                        ctx.fill(CGRect(x: CGFloat(c) * cw + cw * 0.20,
                                        y: CGFloat(r) * ch + ch * 0.18,
                                        width: cw * 0.60, height: ch * 0.52))
                    }
                }
            }
        }
    }

    // MARK: Neon signage

    /// A glowing sign panel: bold bars of colour on black, used as emission.
    static func neonSign(size: Int, color: UIColor, seed: Int) -> UIImage {
        let seed = variant(seed, neonVariants)
        return cached("neon-\(size)-\(color.hashValue)-\(seed)") {
            image(size) { ctx, s in
                ctx.setFillColor(UIColor.black.cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
                ctx.setFillColor(color.cgColor)
                let bars = 3 + Int(hash(seed, 1, 3) * 3)
                for i in 0..<bars {
                    let n = hash(seed, i, 9)
                    let h = s * (0.06 + n * 0.05)
                    let y = s * (0.12 + CGFloat(i) * 0.22)
                    let w = s * (0.35 + hash(seed, i, 21) * 0.5)
                    ctx.fill(CGRect(x: s * 0.08, y: y, width: w, height: h))
                }
                // A vertical stroke, like a hanging sign.
                ctx.fill(CGRect(x: s * 0.80, y: s * 0.10, width: s * 0.08, height: s * 0.78))
            }
        }
    }

    // MARK: Metal / grime for props

    static func paintedMetal(size: Int, tint: UIColor, seed: Int) -> MapSet {
        let seed = variant(seed, metalVariants)
        let key = "metal-\(size)-\(tint.hashValue)-\(seed)"
        let albedo = cached(key + "-a") {
            image(size) { ctx, s in
                ctx.setFillColor(tint.cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
                let step = max(1, size / 64)
                for y in stride(from: 0, to: size, by: step) {
                    for x in stride(from: 0, to: size, by: step) {
                        let n = fbm(CGFloat(x) / 6, CGFloat(y) / 6, seed)
                        if n > 0.66 {
                            ctx.setFillColor(UIColor(red: 0.35, green: 0.18, blue: 0.10,
                                                     alpha: (n - 0.66) * 1.6).cgColor)
                            ctx.fill(CGRect(x: CGFloat(x), y: CGFloat(y),
                                            width: CGFloat(step), height: CGFloat(step)))
                        }
                    }
                }
            }
        }
        let normal = cached(key + "-n") {
            normalMap(size, strength: 1.6) { x, y in fbm(CGFloat(x) / 6, CGFloat(y) / 6, seed) }
        }
        let rough = cached(key + "-r") {
            greyMap(size) { x, y in 0.35 + fbm(CGFloat(x) / 6, CGFloat(y) / 6, seed) * 0.45 }
        }
        let ao = cached(key + "-o") { greyMap(size) { _, _ in 1.0 } }
        return MapSet(albedo: albedo, normal: normal, roughness: rough, ao: ao)
    }

    // MARK: Contact shadow

    /// A soft radial darkening used as a multiply blob under vehicles, so they
    /// sit on the road even when the sun's cast shadow is stretched away.
    static func contactShadow(size: Int = 64) -> UIImage {
        cached("contact-\(size)") {
            image(size) { ctx, s in
                ctx.setFillColor(UIColor.white.cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
                let cs = CGColorSpaceCreateDeviceRGB()
                let centre = CGPoint(x: s / 2, y: s / 2)
                if let g = CGGradient(colorsSpace: cs,
                                      colors: [UIColor(white: 0.30, alpha: 1).cgColor,
                                               UIColor.white.cgColor] as CFArray,
                                      locations: [0, 1]) {
                    ctx.drawRadialGradient(g, startCenter: centre, startRadius: 0,
                                           endCenter: centre, endRadius: s * 0.5,
                                           options: [])
                }
            }
        }
    }

    // MARK: Applying a map set

    /// Wires a map set onto a material as physically based, with tiling.
    static func apply(_ set: MapSet, to m: SCNMaterial, repeatX: CGFloat = 1, repeatY: CGFloat = 1) {
        m.lightingModel = .physicallyBased
        m.diffuse.contents = set.albedo
        m.normal.contents = set.normal
        m.roughness.contents = set.roughness
        m.ambientOcclusion.contents = set.ao
        m.metalness.contents = 0.0
        for p in [m.diffuse, m.normal, m.roughness, m.ambientOcclusion] {
            p.wrapS = .repeat
            p.wrapT = .repeat
            p.mipFilter = .linear
            p.minificationFilter = .linear
            p.magnificationFilter = .linear
            // Anisotropy is the single biggest win on road surfaces: without
            // it the tarmac turns to mush a few metres ahead of the car.
            p.maxAnisotropy = 16
            p.contentsTransform = SCNMatrix4MakeScale(Float(repeatX), Float(repeatY), 1)
        }
    }
}
