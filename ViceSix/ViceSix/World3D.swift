import SceneKit
import UIKit

/// Handles the game controller needs after the static city is built:
/// materials whose look tracks the night and the weather.
struct WorldHandles {
    var facadeMaterials: [SCNMaterial] = []
    var signalMatsV: [SCNMaterial] = []     // indexed by intersection parity
    var signalMatsH: [SCNMaterial] = []
    var lampMaterials: [SCNMaterial] = []
    var lampGlowMaterial = SCNMaterial()    // additive pools under the lamps
    var skyMaterial = SCNMaterial()         // dome; tinted through the cycle
    var asphaltMaterial = SCNMaterial()     // roughness drops when it rains
}

/// Builds the whole static 3D city of Port Leon into a scene: textured
/// ground and roads, block slabs, window-textured buildings with lit
/// windows at night, palms, water, street lights and traffic signals.
enum World3D {

    // MARK: Procedural textures (no image assets anywhere)

    private static func image(_ size: CGSize, _ draw: (CGContext, inout SeededRandom) -> Void) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        var rng = SeededRandom(seed: 4242)
        return renderer.image { ctx in
            draw(ctx.cgContext, &rng)
        }
    }

    private static func noise(_ ctx: CGContext, _ rng: inout SeededRandom,
                              size: CGSize, count: Int, alpha: CGFloat) {
        for _ in 0..<count {
            let w = rng.range(1, 3)
            let shade = rng.range(0, 1)
            ctx.setFillColor(UIColor(white: shade, alpha: alpha).cgColor)
            ctx.fill(CGRect(x: rng.range(0, size.width), y: rng.range(0, size.height),
                            width: w, height: w))
        }
    }

    static func asphaltTexture() -> UIImage {
        let size = CGSize(width: 128, height: 128)
        return image(size) { ctx, rng in
            ctx.setFillColor(UIColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            noise(ctx, &rng, size: size, count: 500, alpha: 0.10)
        }
    }

    static func concreteTexture(_ base: UIColor) -> UIImage {
        let size = CGSize(width: 128, height: 128)
        return image(size) { ctx, rng in
            ctx.setFillColor(base.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            noise(ctx, &rng, size: size, count: 350, alpha: 0.08)
            // Expansion joints.
            ctx.setFillColor(UIColor(white: 0, alpha: 0.15).cgColor)
            ctx.fill(CGRect(x: 0, y: 62, width: 128, height: 2))
            ctx.fill(CGRect(x: 62, y: 0, width: 2, height: 128))
        }
    }

    /// Facade with a window grid; `lit` renders warm windows on black,
    /// used as the emission map so towers light up at night.
    static func facadeTexture(base: UIColor, lit: Bool, seed: UInt64) -> UIImage {
        let size = CGSize(width: 128, height: 192)
        let renderer = UIGraphicsImageRenderer(size: size)
        var rng = SeededRandom(seed: seed)
        return renderer.image { ctx in
            let g = ctx.cgContext
            g.setFillColor(lit ? UIColor.black.cgColor : base.cgColor)
            g.fill(CGRect(origin: .zero, size: size))
            let cols = 6, rows = 8
            let cellW = size.width / CGFloat(cols)
            let cellH = size.height / CGFloat(rows)
            for r in 0..<rows {
                for c in 0..<cols {
                    let inset: CGFloat = 4
                    let rect = CGRect(x: CGFloat(c) * cellW + inset,
                                      y: CGFloat(r) * cellH + inset,
                                      width: cellW - inset * 2,
                                      height: cellH - inset * 2 - 3)
                    if lit {
                        if rng.chance(0.38) {
                            g.setFillColor(UIColor(red: 1, green: rng.range(0.75, 0.9),
                                                   blue: 0.55, alpha: 1).cgColor)
                            g.fill(rect)
                        }
                    } else {
                        let shade = rng.range(0.18, 0.34)
                        g.setFillColor(UIColor(red: shade * 0.8, green: shade,
                                               blue: shade * 1.25, alpha: 1).cgColor)
                        g.fill(rect)
                        // Sky reflection on the top edge of the glass.
                        g.setFillColor(UIColor(white: 1, alpha: 0.18).cgColor)
                        g.fill(CGRect(x: rect.minX, y: rect.minY,
                                      width: rect.width, height: 3))
                    }
                }
            }
        }
    }

    static func grassTexture() -> UIImage {
        let size = CGSize(width: 128, height: 128)
        return image(size) { ctx, rng in
            ctx.setFillColor(UIColor(red: 0.28, green: 0.46, blue: 0.24, alpha: 1).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            for _ in 0..<400 {
                ctx.setFillColor(UIColor(red: rng.range(0.2, 0.35), green: rng.range(0.4, 0.55),
                                         blue: 0.2, alpha: 0.5).cgColor)
                ctx.fill(CGRect(x: rng.range(0, 128), y: rng.range(0, 128), width: 2, height: 3))
            }
        }
    }

    static func sandTexture() -> UIImage {
        let size = CGSize(width: 128, height: 128)
        return image(size) { ctx, rng in
            ctx.setFillColor(UIColor(red: 0.84, green: 0.76, blue: 0.56, alpha: 1).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            noise(ctx, &rng, size: size, count: 500, alpha: 0.07)
        }
    }

    /// The sky: vertical gradient with a baked sun glow and soft clouds.
    /// Rendered on a dome and also used as the image-based light source,
    /// which is what gives the car paint its reflections.
    static func skyTexture() -> UIImage {
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        var rng = SeededRandom(seed: 777)
        return renderer.image { ctx in
            let g = ctx.cgContext
            // Gradient bands, deep zenith to bright horizon to sea below.
            let bands: [(CGFloat, UIColor)] = [
                (0.00, UIColor(red: 0.16, green: 0.32, blue: 0.65, alpha: 1)),
                (0.30, UIColor(red: 0.36, green: 0.58, blue: 0.85, alpha: 1)),
                (0.48, UIColor(red: 0.70, green: 0.83, blue: 0.94, alpha: 1)),
                (0.56, UIColor(red: 0.98, green: 0.90, blue: 0.78, alpha: 1)),
                (0.62, UIColor(red: 0.55, green: 0.70, blue: 0.85, alpha: 1)),
                (1.00, UIColor(red: 0.10, green: 0.26, blue: 0.40, alpha: 1)),
            ]
            for y in 0..<Int(size.height) {
                let t = CGFloat(y) / size.height
                var lower = bands[0], upper = bands[bands.count - 1]
                for k in 0..<bands.count - 1 where t >= bands[k].0 && t <= bands[k + 1].0 {
                    lower = bands[k]; upper = bands[k + 1]
                }
                let f = (t - lower.0) / max(0.001, upper.0 - lower.0)
                var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
                var ur: CGFloat = 0, ug: CGFloat = 0, ub: CGFloat = 0, ua: CGFloat = 0
                lower.1.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
                upper.1.getRed(&ur, green: &ug, blue: &ub, alpha: &ua)
                g.setFillColor(UIColor(red: lr + (ur - lr) * f, green: lg + (ug - lg) * f,
                                       blue: lb + (ub - lb) * f, alpha: 1).cgColor)
                g.fill(CGRect(x: 0, y: CGFloat(y), width: size.width, height: 1))
            }
            // Sun glow, big and soft.
            for r in stride(from: 90.0, to: 8.0, by: -8.0) {
                let a = 0.05 + (90 - r) / 90 * 0.5
                g.setFillColor(UIColor(red: 1, green: 0.97, blue: 0.85, alpha: a).cgColor)
                g.fillEllipse(in: CGRect(x: 350 - r, y: 150 - r, width: r * 2, height: r * 2))
            }
            // A few soft clouds.
            for _ in 0..<10 {
                let cx = rng.range(0, 512)
                let cy = rng.range(60, 260)
                for _ in 0..<5 {
                    let w = rng.range(30, 80)
                    g.setFillColor(UIColor(white: 1, alpha: 0.10).cgColor)
                    g.fillEllipse(in: CGRect(x: cx + rng.range(-40, 40),
                                             y: cy + rng.range(-8, 8),
                                             width: w, height: w * 0.32))
                }
            }
        }
    }

    /// Street-level shopfronts: glass, awnings, doorways. Wrapped around
    /// the podium of every tower so sidewalks feel inhabited.
    static func storefrontTexture() -> UIImage {
        let size = CGSize(width: 256, height: 64)
        let renderer = UIGraphicsImageRenderer(size: size)
        var rng = SeededRandom(seed: 31337)
        return renderer.image { ctx in
            let g = ctx.cgContext
            g.setFillColor(UIColor(white: 0.30, alpha: 1).cgColor)
            g.fill(CGRect(origin: .zero, size: size))
            let awnings: [UIColor] = [
                UIColor(red: 0.75, green: 0.25, blue: 0.30, alpha: 1),
                UIColor(red: 0.20, green: 0.45, blue: 0.60, alpha: 1),
                UIColor(red: 0.80, green: 0.60, blue: 0.20, alpha: 1),
                UIColor(red: 0.30, green: 0.55, blue: 0.35, alpha: 1),
            ]
            var x: CGFloat = 0
            while x < size.width {
                let w = rng.range(34, 60)
                // Glass.
                g.setFillColor(UIColor(red: 0.16, green: 0.22, blue: 0.28, alpha: 1).cgColor)
                g.fill(CGRect(x: x + 4, y: 16, width: w - 8, height: 42))
                g.setFillColor(UIColor(white: 1, alpha: 0.14).cgColor)
                g.fill(CGRect(x: x + 6, y: 18, width: (w - 12) * 0.4, height: 38))
                // Awning.
                g.setFillColor(rng.pick(awnings).cgColor)
                g.fill(CGRect(x: x + 2, y: 8, width: w - 4, height: 9))
                x += w
            }
        }
    }

    /// Soft radial pool of light for under the street lamps.
    static func lampGlowTexture() -> UIImage {
        let size = CGSize(width: 128, height: 128)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let g = ctx.cgContext
            for r in stride(from: 62.0, to: 4.0, by: -6.0) {
                let a = (62 - r) / 62 * 0.16
                g.setFillColor(UIColor(red: 1, green: 0.85, blue: 0.55, alpha: a).cgColor)
                g.fillEllipse(in: CGRect(x: 64 - r, y: 64 - r, width: r * 2, height: r * 2))
            }
        }
    }

    static func rainStreak() -> UIImage {
        let size = CGSize(width: 4, height: 20)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            ctx.cgContext.setFillColor(UIColor(white: 1, alpha: 0.85).cgColor)
            ctx.cgContext.fill(CGRect(x: 1.4, y: 0, width: 1.2, height: 20))
        }
    }

    // MARK: City construction

    static func build(city: City, into scene: SCNScene) -> WorldHandles {
        var handles = WorldHandles()
        var rng = SeededRandom(seed: 90210)
        let sceneRoot = scene.rootNode
        // Everything static goes into this container and is flattened into
        // a handful of draw calls at the end — the difference between a
        // stuttering city and a smooth one.
        let root = SCNNode()
        let world = City.worldSize

        func repeatingMaterial(_ img: UIImage, tiles: CGFloat) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = img
            m.diffuse.wrapS = .repeat
            m.diffuse.wrapT = .repeat
            m.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(tiles), Float(tiles), 1)
            m.lightingModel = .physicallyBased
            m.roughness.contents = 0.9
            return m
        }

        // Sky dome: the same image lights the whole scene (IBL), which is
        // where the reflections on car paint and glass come from.
        let skyImage = skyTexture()
        let dome = SCNSphere(radius: 9200)
        handles.skyMaterial.diffuse.contents = skyImage
        handles.skyMaterial.lightingModel = .constant
        handles.skyMaterial.isDoubleSided = true
        handles.skyMaterial.writesToDepthBuffer = false
        dome.materials = [handles.skyMaterial]
        let domeNode = SCNNode(geometry: dome)
        domeNode.position = SCNVector3(Float(world / 2), 0, Float(world / 2))
        domeNode.renderingOrder = -1000
        sceneRoot.addChildNode(domeNode)
        scene.lightingEnvironment.contents = skyImage
        scene.lightingEnvironment.intensity = 1.2

        // Ocean: a glossy base with a slowly drifting shimmer layer on top.
        let ocean = SCNPlane(width: 17000, height: 17000)
        let oceanMat = SCNMaterial()
        oceanMat.diffuse.contents = UIColor(red: 0.07, green: 0.28, blue: 0.43, alpha: 1)
        oceanMat.lightingModel = .physicallyBased
        oceanMat.metalness.contents = 0.55
        oceanMat.roughness.contents = 0.08
        ocean.materials = [oceanMat]
        let oceanNode = SCNNode(geometry: ocean)
        oceanNode.eulerAngles.x = -.pi / 2
        oceanNode.position = SCNVector3(Float(world / 2), -6, Float(world / 2))
        sceneRoot.addChildNode(oceanNode)

        let shimmer = SCNPlane(width: 17000, height: 17000)
        let shimmerMat = SCNMaterial()
        shimmerMat.diffuse.contents = concreteTexture(UIColor(red: 0.14, green: 0.38, blue: 0.52, alpha: 1))
        shimmerMat.diffuse.wrapS = .repeat
        shimmerMat.diffuse.wrapT = .repeat
        shimmerMat.diffuse.contentsTransform = SCNMatrix4MakeScale(90, 90, 1)
        shimmerMat.transparency = 0.35
        shimmerMat.lightingModel = .physicallyBased
        shimmerMat.roughness.contents = 0.1
        shimmer.materials = [shimmerMat]
        let shimmerNode = SCNNode(geometry: shimmer)
        shimmerNode.eulerAngles.x = -.pi / 2
        shimmerNode.position = SCNVector3(Float(world / 2), -4.5, Float(world / 2))
        shimmerNode.runAction(.repeatForever(.sequence([
            .moveBy(x: 60, y: 0, z: 40, duration: 7),
            .moveBy(x: -60, y: 0, z: -40, duration: 7),
        ])))
        sceneRoot.addChildNode(shimmerNode)

        // Beach ring under the whole island — its top sits clearly below
        // the asphalt so the two surfaces never fight over a pixel.
        let beach = SCNBox(width: world + 500, height: 6, length: world + 500, chamferRadius: 40)
        beach.materials = [repeatingMaterial(sandTexture(), tiles: 30)]
        let beachNode = SCNNode(geometry: beach)
        beachNode.position = SCNVector3(Float(world / 2), -4.2, Float(world / 2))
        root.addChildNode(beachNode)

        // Asphalt sheet: the roads are simply where blocks aren't. The
        // controller lowers this material's roughness when it rains, which
        // turns the streets into mirrors for the lights.
        handles.asphaltMaterial = repeatingMaterial(asphaltTexture(), tiles: 46)
        let ground = SCNBox(width: world, height: 4, length: world, chamferRadius: 0)
        ground.materials = [handles.asphaltMaterial]
        let groundNode = SCNNode(geometry: ground)
        groundNode.position = SCNVector3(Float(world / 2), -2, Float(world / 2))
        root.addChildNode(groundNode)

        // Lane markings.
        let paint = SCNMaterial()
        paint.diffuse.contents = UIColor(red: 0.85, green: 0.75, blue: 0.35, alpha: 1)
        paint.emission.contents = UIColor(red: 0.4, green: 0.35, blue: 0.15, alpha: 1)
        paint.emission.intensity = 0.15
        for k in 0...City.blocksX {
            let c = Float(City.roadCenter(k))
            for vertical in [true, false] {
                let stripe = SCNBox(width: vertical ? 2.4 : world - 200,
                                    height: 0.8,
                                    length: vertical ? world - 200 : 2.4,
                                    chamferRadius: 0)
                stripe.materials = [paint]
                let node = SCNNode(geometry: stripe)
                node.position = vertical
                    ? SCNVector3(c, 0.6, Float(world / 2))
                    : SCNVector3(Float(world / 2), 0.6, c)
                root.addChildNode(node)
            }
        }

        // District materials, shared where possible. Two facade variants
        // per district keep street walls from looking copy-pasted.
        let sidewalkMats = city.districts.map {
            repeatingMaterial(concreteTexture($0.groundColor), tiles: 4)
        }
        let grassMat = repeatingMaterial(grassTexture(), tiles: 4)
        let plazaMat = repeatingMaterial(concreteTexture(UIColor(white: 0.62, alpha: 1)), tiles: 4)
        var facadeImages: [[(day: UIImage, night: UIImage)]] = []
        for (i, d) in city.districts.enumerated() {
            var variants: [(day: UIImage, night: UIImage)] = []
            for v in 0..<2 {
                let seed = UInt64(100 + i * 10 + v)
                variants.append(
                    (day: facadeTexture(base: d.buildingColor, lit: false, seed: seed),
                     night: facadeTexture(base: d.buildingColor, lit: true, seed: seed)))
            }
            facadeImages.append(variants)
        }
        let roofMat = SCNMaterial()
        roofMat.diffuse.contents = UIColor(white: 0.24, alpha: 1)
        roofMat.lightingModel = .physicallyBased
        roofMat.roughness.contents = 0.95

        let storefrontMat = SCNMaterial()
        storefrontMat.diffuse.contents = storefrontTexture()
        storefrontMat.diffuse.wrapS = .repeat
        storefrontMat.lightingModel = .physicallyBased
        storefrontMat.roughness.contents = 0.55

        let antennaMat = SCNMaterial()
        antennaMat.diffuse.contents = UIColor(white: 0.35, alpha: 1)
        antennaMat.lightingModel = .physicallyBased
        antennaMat.metalness.contents = 0.8
        antennaMat.roughness.contents = 0.35

        for i in 0..<City.blocksX {
            for j in 0..<City.blocksY {
                let key = i * 100 + j
                let rect = City.blockRect(i, j)
                let dIndex = city.districtIndex[i][j]

                // The block slab: a curb-height platform.
                let slab = SCNBox(width: rect.width, height: 5, length: rect.height,
                                  chamferRadius: 2)
                let topMat: SCNMaterial
                if city.parkBlocks.contains(key) {
                    topMat = grassMat
                } else if city.plazaBlocks.contains(key) {
                    topMat = plazaMat
                } else {
                    topMat = sidewalkMats[dIndex]
                }
                slab.materials = [topMat]
                let slabNode = SCNNode(geometry: slab)
                slabNode.position = SCNVector3(Float(rect.midX), 2.5, Float(rect.midY))
                root.addChildNode(slabNode)

                // Trees in parks and along the shore.
                if city.parkBlocks.contains(key) {
                    for _ in 0..<6 {
                        addTree(to: root, at: CGPoint(x: rng.range(rect.minX + 40, rect.maxX - 40),
                                                      y: rng.range(rect.minY + 40, rect.maxY - 40)),
                                palm: false, rng: &rng)
                    }
                } else if dIndex == 2 && city.buildings[i][j].count <= 1 {
                    for _ in 0..<3 {
                        addTree(to: root, at: CGPoint(x: rng.range(rect.minX + 40, rect.maxX - 40),
                                                      y: rng.range(rect.minY + 40, rect.maxY - 40)),
                                palm: true, rng: &rng)
                    }
                }

                // Buildings: window towers with district-appropriate heights,
                // occasional two-tier setbacks, antennas, and street-level
                // storefront podiums.
                for b in city.buildings[i][j] {
                    let height: CGFloat
                    switch dIndex {
                    case 0:  height = rng.range(160, 420)      // downtown towers
                    case 2:  height = rng.range(60, 140)       // beach hotels
                    case 4:  height = rng.range(40, 90)        // hillside homes
                    default: height = rng.range(50, 150)
                    }
                    let variant = rng.int(0, 1)
                    let images = facadeImages[dIndex][variant]

                    func facadeMaterial(width: CGFloat, height h: CGFloat) -> SCNMaterial {
                        let facade = SCNMaterial()
                        facade.diffuse.contents = images.day
                        facade.emission.contents = images.night
                        facade.emission.intensity = 0
                        facade.lightingModel = .physicallyBased
                        facade.roughness.contents = 0.55
                        facade.metalness.contents = 0.15
                        facade.diffuse.wrapS = .repeat
                        facade.diffuse.wrapT = .repeat
                        facade.emission.wrapS = .repeat
                        facade.emission.wrapT = .repeat
                        let tilesX = Float(max(1, (width / 110).rounded()))
                        let tilesY = Float(max(1, (h / 130).rounded()))
                        let tf = SCNMatrix4MakeScale(tilesX, tilesY, 1)
                        facade.diffuse.contentsTransform = tf
                        facade.emission.contentsTransform = tf
                        handles.facadeMaterials.append(facade)
                        return facade
                    }

                    func addTower(rect: CGRect, height h: CGFloat, baseY: CGFloat) {
                        let box = SCNBox(width: rect.width, height: h,
                                         length: rect.height, chamferRadius: 1)
                        let facade = facadeMaterial(width: rect.width, height: h)
                        box.materials = [facade, facade, facade, facade, roofMat, roofMat]
                        let node = SCNNode(geometry: box)
                        node.position = SCNVector3(Float(rect.midX), Float(baseY + h / 2),
                                                   Float(rect.midY))
                        node.castsShadow = true
                        root.addChildNode(node)
                    }

                    let setback = dIndex == 0 && height > 240 && rng.chance(0.45)
                    if setback {
                        let lower = height * 0.6
                        let upper = height * 0.4
                        addTower(rect: b.rect, height: lower, baseY: 5)
                        addTower(rect: b.rect.insetBy(dx: b.rect.width * 0.18,
                                                      dy: b.rect.height * 0.18),
                                 height: upper, baseY: 5 + lower)
                    } else {
                        addTower(rect: b.rect, height: height, baseY: 5)
                    }

                    // Antenna on the tallest towers.
                    if height > 300 {
                        let mast = SCNCylinder(radius: 1.6, height: 70)
                        mast.materials = [antennaMat]
                        let mastNode = SCNNode(geometry: mast)
                        mastNode.position = SCNVector3(Float(b.rect.midX),
                                                       Float(height + 40),
                                                       Float(b.rect.midY))
                        root.addChildNode(mastNode)
                    }

                    // Storefront podium wrapping the street level.
                    if !city.parkBlocks.contains(key) {
                        let podRect = b.rect.insetBy(dx: -6, dy: -6)
                        let podium = SCNBox(width: podRect.width, height: 26,
                                            length: podRect.height, chamferRadius: 1)
                        podium.materials = [storefrontMat, storefrontMat, storefrontMat,
                                            storefrontMat, roofMat, roofMat]
                        let podiumNode = SCNNode(geometry: podium)
                        podiumNode.position = SCNVector3(Float(podRect.midX), 18,
                                                         Float(podRect.midY))
                        root.addChildNode(podiumNode)
                    }

                    // Rooftop clutter on the bigger towers.
                    if b.rect.width > 90 && b.rect.height > 90 {
                        let unit = SCNBox(width: rng.range(16, 30), height: 10,
                                          length: rng.range(16, 30), chamferRadius: 1)
                        unit.materials = [roofMat]
                        let unitNode = SCNNode(geometry: unit)
                        unitNode.position = SCNVector3(
                            Float(rng.range(b.rect.minX + 24, b.rect.maxX - 24)),
                            Float(height + 10),
                            Float(rng.range(b.rect.minY + 24, b.rect.maxY - 24)))
                        root.addChildNode(unitNode)
                    }
                }
            }
        }

        buildIntersections(city: city, root: root, handles: &handles)
        buildLandmarkMarkers(city: city, root: root)

        // Collapse thousands of static nodes into one merged mesh per
        // material — the frame rate fix. Shared materials keep working, so
        // night windows, lamps and signal bulbs still animate.
        let flattened = root.flattenedClone()
        flattened.name = "staticCity"
        sceneRoot.addChildNode(flattened)
        return handles
    }

    private static func addTree(to root: SCNNode, at p: CGPoint, palm: Bool,
                                rng: inout SeededRandom) {
        let node = SCNNode()
        let trunkHeight = palm ? rng.range(34, 55) : rng.range(18, 28)
        let trunk = SCNCylinder(radius: 2.4, height: trunkHeight)
        let trunkMat = SCNMaterial()
        trunkMat.diffuse.contents = UIColor(red: 0.45, green: 0.33, blue: 0.22, alpha: 1)
        trunk.materials = [trunkMat]
        let trunkNode = SCNNode(geometry: trunk)
        trunkNode.position = SCNVector3(0, Float(trunkHeight / 2), 0)
        node.addChildNode(trunkNode)

        let crownMat = SCNMaterial()
        crownMat.diffuse.contents = palm
            ? UIColor(red: 0.25, green: 0.55, blue: 0.28, alpha: 1)
            : UIColor(red: 0.18, green: 0.40, blue: 0.18, alpha: 1)
        crownMat.roughness.contents = 0.95
        crownMat.lightingModel = .physicallyBased
        if palm {
            for k in 0..<5 {
                let frond = SCNBox(width: 26, height: 1.5, length: 6, chamferRadius: 1)
                frond.materials = [crownMat]
                let f = SCNNode(geometry: frond)
                f.position = SCNVector3(0, Float(trunkHeight), 0)
                f.eulerAngles = SCNVector3(0, Float(k) * .pi * 2 / 5, 0.5)
                f.pivot = SCNMatrix4MakeTranslation(-13, 0, 0)
                node.addChildNode(f)
            }
        } else {
            let crown = SCNSphere(radius: rng.range(12, 20))
            crown.materials = [crownMat]
            let c = SCNNode(geometry: crown)
            c.position = SCNVector3(0, Float(trunkHeight + 8), 0)
            node.addChildNode(c)
        }
        node.position = SCNVector3(Float(p.x), 5, Float(p.y))
        root.addChildNode(node)
    }

    /// One signal pole per intersection with a bulb per axis (materials are
    /// shared by parity so the controller updates just four of them), plus a
    /// street light that glows at night.
    private static func buildIntersections(city: City, root: SCNNode,
                                           handles: inout WorldHandles) {
        func signalMaterial() -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = UIColor.red
            m.emission.contents = UIColor.red
            m.emission.intensity = 0.9
            return m
        }
        handles.signalMatsV = [signalMaterial(), signalMaterial()]
        handles.signalMatsH = [signalMaterial(), signalMaterial()]

        let poleMat = SCNMaterial()
        poleMat.diffuse.contents = UIColor(white: 0.2, alpha: 1)
        poleMat.lightingModel = .physicallyBased
        poleMat.metalness.contents = 0.6
        poleMat.roughness.contents = 0.5

        let lampMat = SCNMaterial()
        lampMat.diffuse.contents = UIColor(red: 1, green: 0.9, blue: 0.7, alpha: 1)
        lampMat.emission.contents = UIColor(red: 1, green: 0.85, blue: 0.55, alpha: 1)
        lampMat.emission.intensity = 0
        handles.lampMaterials.append(lampMat)

        // Warm additive pools of light under the lamps, faded in at night.
        handles.lampGlowMaterial.diffuse.contents = UIColor.black
        handles.lampGlowMaterial.emission.contents = lampGlowTexture()
        handles.lampGlowMaterial.emission.intensity = 0
        handles.lampGlowMaterial.lightingModel = .constant
        handles.lampGlowMaterial.blendMode = .add
        handles.lampGlowMaterial.writesToDepthBuffer = false

        let crosswalkMat = SCNMaterial()
        crosswalkMat.diffuse.contents = UIColor(white: 0.85, alpha: 1)
        crosswalkMat.transparency = 0.30
        crosswalkMat.lightingModel = .physicallyBased
        crosswalkMat.roughness.contents = 0.8

        for i in 0...City.blocksX {
            for j in 0...City.blocksY {
                let cx = Float(City.roadCenter(i))
                let cz = Float(City.roadCenter(j))
                let parity = (i + j) % 2

                let pole = SCNCylinder(radius: 1.6, height: 60)
                pole.materials = [poleMat]
                let poleNode = SCNNode(geometry: pole)
                poleNode.position = SCNVector3(cx + Float(City.roadHalf) + 8, 30,
                                               cz + Float(City.roadHalf) + 8)
                root.addChildNode(poleNode)

                let bulbV = SCNSphere(radius: 3.4)
                bulbV.materials = [handles.signalMatsV[parity]]
                let bulbVNode = SCNNode(geometry: bulbV)
                bulbVNode.position = SCNVector3(0, 26, 0)
                poleNode.addChildNode(bulbVNode)

                let bulbH = SCNSphere(radius: 3.4)
                bulbH.materials = [handles.signalMatsH[parity]]
                let bulbHNode = SCNNode(geometry: bulbH)
                bulbHNode.position = SCNVector3(0, 18, 0)
                poleNode.addChildNode(bulbHNode)

                // Street lamp head and its pool of light on the ground.
                let lamp = SCNSphere(radius: 3)
                lamp.materials = [lampMat]
                let lampNode = SCNNode(geometry: lamp)
                lampNode.position = SCNVector3(0, 31, 0)
                poleNode.addChildNode(lampNode)

                let glow = SCNPlane(width: 190, height: 190)
                glow.materials = [handles.lampGlowMaterial]
                let glowNode = SCNNode(geometry: glow)
                glowNode.eulerAngles.x = -.pi / 2
                glowNode.position = SCNVector3(cx, 1.6, cz)
                root.addChildNode(glowNode)

                // Crosswalk paint across each approach, raised well clear
                // of the asphalt so the depth buffer never flickers.
                for s: Float in [-1, 1] {
                    let across = SCNBox(width: CGFloat(City.roadHalf * 2 - 18),
                                        height: 0.7, length: 10, chamferRadius: 0)
                    across.materials = [crosswalkMat]
                    let acrossNode = SCNNode(geometry: across)
                    acrossNode.position = SCNVector3(cx, 0.9,
                                                     cz + s * Float(City.roadHalf + 8))
                    root.addChildNode(acrossNode)

                    let down = SCNBox(width: 10, height: 0.7,
                                      length: CGFloat(City.roadHalf * 2 - 18),
                                      chamferRadius: 0)
                    down.materials = [crosswalkMat]
                    let downNode = SCNNode(geometry: down)
                    downNode.position = SCNVector3(cx + s * Float(City.roadHalf + 8),
                                                   0.9, cz)
                    root.addChildNode(downNode)
                }
            }
        }
    }

    private static func buildLandmarkMarkers(city: City, root: SCNNode) {
        let spots: [(CGPoint, UIColor)] = [
            (city.hospital, UIColor(red: 0.85, green: 0.2, blue: 0.25, alpha: 1)),
            (city.policeHQ, UIColor(red: 0.15, green: 0.3, blue: 0.65, alpha: 1)),
            (city.garage, UIColor(red: 0.5, green: 0.35, blue: 0.2, alpha: 1)),
            (city.bank, UIColor(red: 0.2, green: 0.5, blue: 0.35, alpha: 1)),
            (city.hideout, UIColor(red: 0.4, green: 0.3, blue: 0.5, alpha: 1)),
            (city.airport, UIColor(red: 0.35, green: 0.4, blue: 0.45, alpha: 1)),
            (city.marina, UIColor(red: 0.2, green: 0.45, blue: 0.6, alpha: 1)),
        ]
        for (p, color) in spots {
            let disc = SCNCylinder(radius: 54, height: 1.5)
            let m = SCNMaterial()
            m.diffuse.contents = color
            m.emission.contents = color
            m.emission.intensity = 0.35
            disc.materials = [m]
            let node = SCNNode(geometry: disc)
            node.position = SCNVector3(Float(p.x), 5.6, Float(p.y))
            root.addChildNode(node)
        }
    }
}
