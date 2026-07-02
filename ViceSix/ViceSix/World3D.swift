import SceneKit
import UIKit

/// Handles the game controller needs after the static city is built:
/// materials whose emission tracks the night, and the signal bulbs.
struct WorldHandles {
    var facadeMaterials: [SCNMaterial] = []
    var signalMatsV: [SCNMaterial] = []     // indexed by intersection parity
    var signalMatsH: [SCNMaterial] = []
    var lampMaterials: [SCNMaterial] = []
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
        let root = scene.rootNode
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

        // Ocean, out to the horizon.
        let ocean = SCNPlane(width: 30000, height: 30000)
        let oceanMat = SCNMaterial()
        oceanMat.diffuse.contents = UIColor(red: 0.09, green: 0.30, blue: 0.45, alpha: 1)
        oceanMat.lightingModel = .physicallyBased
        oceanMat.metalness.contents = 0.1
        oceanMat.roughness.contents = 0.15
        ocean.materials = [oceanMat]
        let oceanNode = SCNNode(geometry: ocean)
        oceanNode.eulerAngles.x = -.pi / 2
        oceanNode.position = SCNVector3(Float(world / 2), -4, Float(world / 2))
        root.addChildNode(oceanNode)

        // Beach ring under the whole island.
        let beach = SCNBox(width: world + 500, height: 6, length: world + 500, chamferRadius: 40)
        beach.materials = [repeatingMaterial(sandTexture(), tiles: 30)]
        let beachNode = SCNNode(geometry: beach)
        beachNode.position = SCNVector3(Float(world / 2), -3, Float(world / 2))
        root.addChildNode(beachNode)

        // Asphalt sheet: the roads are simply where blocks aren't.
        let ground = SCNBox(width: world, height: 4, length: world, chamferRadius: 0)
        ground.materials = [repeatingMaterial(asphaltTexture(), tiles: 46)]
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
                                    height: 0.5,
                                    length: vertical ? world - 200 : 2.4,
                                    chamferRadius: 0)
                stripe.materials = [paint]
                let node = SCNNode(geometry: stripe)
                node.position = vertical
                    ? SCNVector3(c, 0.3, Float(world / 2))
                    : SCNVector3(Float(world / 2), 0.3, c)
                root.addChildNode(node)
            }
        }

        // District materials, shared where possible.
        let sidewalkMats = city.districts.map {
            repeatingMaterial(concreteTexture($0.groundColor), tiles: 4)
        }
        let grassMat = repeatingMaterial(grassTexture(), tiles: 4)
        let plazaMat = repeatingMaterial(concreteTexture(UIColor(white: 0.62, alpha: 1)), tiles: 4)
        let facadeImages = city.districts.enumerated().map { (i, d) in
            (day: facadeTexture(base: d.buildingColor, lit: false, seed: UInt64(100 + i)),
             night: facadeTexture(base: d.buildingColor, lit: true, seed: UInt64(100 + i)))
        }
        let roofMat = SCNMaterial()
        roofMat.diffuse.contents = UIColor(white: 0.24, alpha: 1)
        roofMat.lightingModel = .physicallyBased
        roofMat.roughness.contents = 0.95

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

                // Buildings: window towers with district-appropriate heights.
                for b in city.buildings[i][j] {
                    let height: CGFloat
                    switch dIndex {
                    case 0:  height = rng.range(160, 420)      // downtown towers
                    case 2:  height = rng.range(60, 140)       // beach hotels
                    case 4:  height = rng.range(40, 90)        // hillside homes
                    default: height = rng.range(50, 150)
                    }

                    let box = SCNBox(width: b.rect.width, height: height,
                                     length: b.rect.height, chamferRadius: 1)
                    let facade = SCNMaterial()
                    let images = facadeImages[dIndex]
                    facade.diffuse.contents = images.day
                    facade.emission.contents = images.night
                    facade.emission.intensity = 0
                    facade.lightingModel = .physicallyBased
                    facade.roughness.contents = 0.6
                    facade.diffuse.wrapS = .repeat
                    facade.diffuse.wrapT = .repeat
                    facade.emission.wrapS = .repeat
                    facade.emission.wrapT = .repeat
                    let tilesX = Float(max(1, (b.rect.width / 110).rounded()))
                    let tilesY = Float(max(1, (height / 130).rounded()))
                    let tf = SCNMatrix4MakeScale(tilesX, tilesY, 1)
                    facade.diffuse.contentsTransform = tf
                    facade.emission.contentsTransform = tf
                    box.materials = [facade, facade, facade, facade, roofMat, roofMat]

                    let node = SCNNode(geometry: box)
                    node.position = SCNVector3(Float(b.rect.midX), Float(height / 2 + 5),
                                               Float(b.rect.midY))
                    node.castsShadow = true
                    root.addChildNode(node)
                    handles.facadeMaterials.append(facade)

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

                // Street lamp head.
                let lamp = SCNSphere(radius: 3)
                lamp.materials = [lampMat]
                let lampNode = SCNNode(geometry: lamp)
                lampNode.position = SCNVector3(0, 31, 0)
                poleNode.addChildNode(lampNode)
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
