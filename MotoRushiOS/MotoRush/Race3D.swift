import SwiftUI
import SceneKit
import UIKit

// The 3D race renderer.
//
// The simulation stays 2D — a side-on plane, which is what makes the handling
// readable — and this layer presents it in three dimensions: the terrain is
// extruded into a banked ribbon, the bike and rider are Blender-built meshes
// whose parts are driven by the solved suspension, and the camera sits slightly
// off-axis so the track has depth.

/// The anchors the Blender models were built around (see tools/blender_assets.py).
/// Keeping one copy of these numbers on each side is what makes the parts line
/// up: the fork model's origin is its axle, the swingarm's is its pivot.
enum Rig {
    static let wheelbase: Float = 1.34
    static let axleY: Float = -0.30
    static let rearAxle = SCNVector3(-0.67, -0.30, 0)
    static let frontAxle = SCNVector3(0.67, -0.30, 0)
    static let swingPivot = SCNVector3(-0.10, -0.16, 0)
    /// Angle of the swingarm as modelled, pivot → rear axle.
    static let swingRest: Float = atan2(-0.30 - (-0.16), -0.67 - (-0.10))
}

// MARK: - Model loading

enum Art {
    /// Loads one of the Blender-exported parts. Falls back to a primitive
    /// stand-in so a missing or unreadable asset degrades instead of crashing.
    static func part(_ name: String, fallback: () -> SCNNode) -> SCNNode {
        let url = Bundle.main.url(forResource: name, withExtension: "obj", subdirectory: "Art")
            ?? Bundle.main.url(forResource: name, withExtension: "obj")
        guard let u = url,
              let scene = try? SCNScene(url: u, options: [.createNormalsIfAbsent: true]) else {
            return fallback()
        }
        let holder = SCNNode()
        for child in scene.rootNode.childNodes {
            child.removeFromParentNode()
            holder.addChildNode(child)
        }
        return holder.childNodes.isEmpty ? fallback() : holder
    }

    /// Recolours the bodywork so every rider on the gate is distinguishable.
    static func tint(_ node: SCNNode, plastics: UIColor) {
        node.enumerateHierarchy { child, _ in
            guard let materials = child.geometry?.materials else { return }
            for m in materials {
                switch m.name {
                case "Plastic", "Jersey":
                    m.diffuse.contents = plastics
                case "Helmet":
                    m.diffuse.contents = plastics.blended(with: .white, fraction: 0.25)
                default:
                    break
                }
                m.lightingModel = .physicallyBased
            }
        }
    }

    static func setOpacity(_ node: SCNNode, _ value: CGFloat) {
        node.opacity = value
        node.enumerateHierarchy { child, _ in child.opacity = value }
    }

    static func softDot(_ color: UIColor, size: CGFloat = 24) -> UIImage {
        let r = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return r.image { ctx in
            let c = ctx.cgContext
            let comps = color.cgColor.components ?? [0.8, 0.7, 0.5, 1]
            let colors = [UIColor(red: comps[0], green: comps.count > 1 ? comps[1] : comps[0],
                                  blue: comps.count > 2 ? comps[2] : comps[0], alpha: 0.9).cgColor,
                          UIColor(white: 1, alpha: 0).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors, locations: [0, 1]) {
                c.drawRadialGradient(g,
                                     startCenter: CGPoint(x: size / 2, y: size / 2), startRadius: 0,
                                     endCenter: CGPoint(x: size / 2, y: size / 2), endRadius: size / 2,
                                     options: [])
            }
        }
    }
}

// MARK: - Terrain

enum TerrainBuilder {
    /// Cross-section of the track, as (z offset, height offset) pairs: a flat
    /// racing line with a raised lip either side and a skirt falling away to
    /// the scenery.
    private static let section: [(z: Float, dy: Float)] = [
        (-6.2, -2.6), (-3.6, 0.55), (-2.9, 0.0), (0, 0.0), (2.9, 0.0), (3.6, 0.55), (6.2, -2.6)
    ]

    static func build(track: Track, step: Double = 0.8) -> (surface: SCNGeometry, verge: SCNGeometry) {
        var verts: [SCNVector3] = []
        var rows = 0
        var x = 0.0
        while x <= track.length {
            let h = Float(track.height(at: x))
            for s in section {
                verts.append(SCNVector3(Float(x), h + s.dy, s.z))
            }
            rows += 1
            x += step
        }

        let cols = section.count
        func quads(from a: Int, to b: Int) -> [Int32] {
            var idx: [Int32] = []
            for r in 0..<(rows - 1) {
                for c in a..<b {
                    let i0 = Int32(r * cols + c)
                    let i1 = Int32(r * cols + c + 1)
                    let i2 = Int32((r + 1) * cols + c)
                    let i3 = Int32((r + 1) * cols + c + 1)
                    idx.append(contentsOf: [i0, i2, i1, i1, i2, i3])
                }
            }
            return idx
        }

        // Columns 1…5 are the rideable surface; 0 and 5 are the outer skirt.
        let surfaceIdx = quads(from: 1, to: cols - 2)
        var vergeIdx = quads(from: 0, to: 1)
        vergeIdx.append(contentsOf: quads(from: cols - 2, to: cols - 1))

        return (geometry(verts, surfaceIdx), geometry(verts, vergeIdx))
    }

    private static func geometry(_ verts: [SCNVector3], _ indices: [Int32]) -> SCNGeometry {
        // Smooth per-vertex normals, accumulated from the face normals that
        // touch each vertex. Without these the terrain renders unlit.
        var normals = [SCNVector3](repeating: SCNVector3Zero, count: verts.count)
        var i = 0
        while i + 2 < indices.count {
            let a = Int(indices[i]), b = Int(indices[i + 1]), c = Int(indices[i + 2])
            let ux = verts[b].x - verts[a].x, uy = verts[b].y - verts[a].y, uz = verts[b].z - verts[a].z
            let vx = verts[c].x - verts[a].x, vy = verts[c].y - verts[a].y, vz = verts[c].z - verts[a].z
            let nx = uy * vz - uz * vy
            let ny = uz * vx - ux * vz
            let nz = ux * vy - uy * vx
            for idx in [a, b, c] {
                normals[idx].x += nx
                normals[idx].y += ny
                normals[idx].z += nz
            }
            i += 3
        }
        for j in 0..<normals.count {
            let n = normals[j]
            let len = max(1e-5, (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot())
            normals[j] = SCNVector3(n.x / len, n.y / len, n.z / len)
        }

        let source = SCNGeometrySource(vertices: verts)
        let normalSource = SCNGeometrySource(normals: normals)
        let data = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(data: data,
                                         primitiveType: .triangles,
                                         primitiveCount: indices.count / 3,
                                         bytesPerIndex: MemoryLayout<Int32>.size)
        return SCNGeometry(sources: [source, normalSource], elements: [element])
    }
}

// MARK: - Bike node

/// One rider's visual rig: frame, fork, swingarm, two wheels and a rider,
/// positioned every frame from the physics state.
final class BikeRig {
    let root = SCNNode()
    private let frame = SCNNode()
    private let fork = SCNNode()
    private let swingarm = SCNNode()
    private let wheelFront = SCNNode()
    private let wheelRear = SCNNode()
    private let rider = SCNNode()
    private let bike: Bike
    private var wheelSpin: Float = 0

    init(bike: Bike, tint: UIColor, isGhost: Bool = false) {
        self.bike = bike

        frame.addChildNode(Art.part("bike_frame") {
            SCNNode(geometry: SCNBox(width: 1.2, height: 0.34, length: 0.28, chamferRadius: 0.05))
        })
        fork.addChildNode(Art.part("bike_fork") {
            SCNNode(geometry: SCNCylinder(radius: 0.035, height: 0.62))
        })
        swingarm.addChildNode(Art.part("bike_swingarm") {
            SCNNode(geometry: SCNBox(width: 0.58, height: 0.07, length: 0.2, chamferRadius: 0.02))
        })
        for wheel in [wheelFront, wheelRear] {
            wheel.addChildNode(Art.part("bike_wheel") {
                let c = SCNCylinder(radius: 0.33, height: 0.11)
                let n = SCNNode(geometry: c)
                n.eulerAngles.x = .pi / 2
                return n
            })
        }
        rider.addChildNode(Art.part("rider") {
            SCNNode(geometry: SCNCapsule(capRadius: 0.16, height: 1.1))
        })

        for n in [frame, fork, swingarm, wheelFront, wheelRear, rider] { root.addChildNode(n) }

        Art.tint(root, plastics: tint)
        if isGhost {
            Art.setOpacity(root, 0.34)
            root.enumerateHierarchy { child, _ in
                child.geometry?.materials.forEach { $0.diffuse.contents = UIColor(white: 0.75, alpha: 1) }
            }
        }
        root.castsShadow = !isGhost
    }

    /// Local position of a world point, in the bike's own rotated frame.
    private func local(_ wx: Double, _ wy: Double) -> SCNVector3 {
        let c = cos(bike.ang), s = sin(bike.ang)
        let dx = wx - bike.x, dy = wy - bike.y
        return SCNVector3(Float(dx * c + dy * s), Float(-dx * s + dy * c), 0)
    }

    func sync(dt: Double) {
        root.position = SCNVector3(Float(bike.x), Float(bike.y), 0)
        // Pitch about Z is the chassis angle; roll about X is the whip; the
        // small yaw about Y is the scrub off a jump face.
        root.eulerAngles = SCNVector3(Float(bike.whip), Float(bike.scrub * 0.4), Float(bike.ang))

        let rear = local(bike.wheels[0].cx, bike.wheels[0].cy)
        let front = local(bike.wheels[1].cx, bike.wheels[1].cy)
        wheelRear.position = rear
        wheelFront.position = front

        wheelSpin -= Float(bike.forwardSpeed * dt / bike.wheelR)
        wheelRear.eulerAngles.z = wheelSpin
        wheelFront.eulerAngles.z = wheelSpin

        // The fork model's origin is the front axle, so it simply rides with
        // the wheel and the travel shows as the front end compressing.
        fork.position = front
        // The swingarm hinges at its pivot; rotate it by however far the rear
        // axle has moved from where it was modelled.
        swingarm.position = Rig.swingPivot
        let swingNow = atan2(rear.y - Rig.swingPivot.y, rear.x - Rig.swingPivot.x)
        swingarm.eulerAngles.z = swingNow - Rig.swingRest

        // Rider: weight transfer shifts them fore/aft and they stand up as
        // they move, which is most of the read on what the bike is doing.
        let lean = Float(bike.lean)
        let stand = Float(min(1, abs(bike.lean) * 0.6 + (bike.airborne ? 0.35 : 0.1)))
        rider.position = SCNVector3(-0.05 - lean * 0.30, 0.28 + stand * 0.10, 0)
        rider.eulerAngles.z = -lean * 0.35
        rider.isHidden = bike.crashed

        if bike.crashed {
            // Tumble the bike with the crash rather than freezing it.
            root.eulerAngles.x = Float(bike.crashTimer * 6)
        }
    }
}

// MARK: - Scene

final class Race3DController: NSObject, SCNSceneRendererDelegate {
    let scene = SCNScene()
    let engine: RaceEngine
    private let cameraNode = SCNNode()
    private var rigs: [ObjectIdentifier: BikeRig] = [:]
    private var ghostRig: BikeRig?
    private var ghostBike: Bike?
    private var gate: SCNNode?
    private var dustNode = SCNNode()
    private var dustSystem = SCNParticleSystem()
    private var burstSystem = SCNParticleSystem()
    private var lastTime: TimeInterval = 0
    private var camX: Float = 0
    private var camY: Float = 0
    private var shake: Float = 0

    init(engine: RaceEngine) {
        self.engine = engine
        super.init()
        buildWorld()
    }

    private var biome: Biome { engine.track.biome }

    private func buildWorld() {
        let track = engine.track

        // Sky and depth fog.
        scene.background.contents = UIColor(Color(hex: biome.skyBottom))
        scene.fogColor = UIColor(Color(hex: biome.skyBottom))
        scene.fogStartDistance = 60
        scene.fogEndDistance = 320
        scene.fogDensityExponent = 1.4

        // Terrain.
        let (surface, verge) = TerrainBuilder.build(track: track)
        let dirt = SCNMaterial()
        dirt.diffuse.contents = UIColor(Color(hex: biome.ground))
        dirt.roughness.contents = 0.95
        dirt.lightingModel = .physicallyBased
        surface.materials = [dirt]

        let skirt = SCNMaterial()
        skirt.diffuse.contents = UIColor(Color(hex: biome.groundDeep))
        skirt.roughness.contents = 1.0
        skirt.lightingModel = .physicallyBased
        verge.materials = [skirt]

        let surfaceNode = SCNNode(geometry: surface)
        surfaceNode.castsShadow = false
        scene.rootNode.addChildNode(surfaceNode)
        let vergeNode = SCNNode(geometry: verge)
        vergeNode.castsShadow = false
        scene.rootNode.addChildNode(vergeNode)

        buildProps()
        buildGate()
        buildLighting()
        buildParticles()

        for bike in engine.field {
            let rig = BikeRig(bike: bike, tint: UIColor(Color(hex: bike.tintHex)))
            scene.rootNode.addChildNode(rig.root)
            rigs[ObjectIdentifier(bike)] = rig
        }

        if let first = engine.ghostPose {
            let gb = Bike(spec: engine.playerSpec, track: track, name: "Ghost")
            pose(gb, first)
            let rig = BikeRig(bike: gb, tint: UIColor(white: 0.8, alpha: 1), isGhost: true)
            scene.rootNode.addChildNode(rig.root)
            ghostBike = gb
            ghostRig = rig
        }

        camX = Float(engine.player.x)
        camY = Float(engine.player.y)
    }

    private func buildProps() {
        let track = engine.track
        let treeSide = biome.key == "forest"
        for prop in track.props {
            let name: String
            switch prop.kind {
            case "tree": name = treeSide ? "prop_tree" : "prop_flag"
            case "banner": name = "prop_gantry"
            case "flag": name = "prop_flag"
            default: name = "prop_bale"
            }
            let node = Art.part(name) {
                SCNNode(geometry: SCNBox(width: 0.8, height: 0.6, length: 0.8, chamferRadius: 0.05))
            }
            let z: Float = prop.back ? -9.5 : 8.2
            node.position = SCNVector3(Float(prop.x), Float(track.height(at: prop.x)) - 1.2, z)
            let sc = Float(prop.scale)
            node.scale = SCNVector3(sc, sc, sc)
            node.eulerAngles.y = Float.random(in: -0.4...0.4)
            node.castsShadow = true
            scene.rootNode.addChildNode(node)
        }

        // Start and finish gantries straddle the track.
        for (x, tint) in [(track.startX, UIColor.systemGreen), (track.finishX, UIColor.systemYellow)] {
            let node = Art.part("prop_gantry") {
                SCNNode(geometry: SCNBox(width: 0.3, height: 5, length: 9, chamferRadius: 0))
            }
            node.position = SCNVector3(Float(x), Float(track.height(at: x)), 0)
            node.enumerateHierarchy { child, _ in
                child.geometry?.materials.forEach { m in
                    if m.name == "Cloth" { m.diffuse.contents = tint }
                }
            }
            scene.rootNode.addChildNode(node)
        }
    }

    private func buildGate() {
        let track = engine.track
        let x = track.startX + 1.0
        let node = SCNNode()
        for i in 0..<7 {
            let bar = SCNNode(geometry: SCNBox(width: 0.06, height: 0.75, length: 0.5, chamferRadius: 0.01))
            bar.geometry?.firstMaterial?.diffuse.contents = UIColor.systemRed
            bar.position = SCNVector3(0, 0.38, Float(i - 3) * 0.75)
            node.addChildNode(bar)
        }
        node.position = SCNVector3(Float(x), Float(track.height(at: x)), 0)
        scene.rootNode.addChildNode(node)
        gate = node
    }

    private func buildLighting() {
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = biome.night ? 420 : 1250
        sun.light?.color = biome.night ? UIColor(white: 0.75, alpha: 1)
                                       : UIColor(red: 1.0, green: 0.97, blue: 0.9, alpha: 1)
        sun.light?.castsShadow = true
        sun.light?.shadowMode = .deferred
        sun.light?.shadowRadius = 4
        sun.light?.shadowSampleCount = 8
        sun.light?.shadowColor = UIColor(white: 0, alpha: 0.42)
        sun.light?.orthographicScale = 14
        sun.light?.zFar = 220
        sun.eulerAngles = SCNVector3(-1.05, 0.6, 0)
        cameraNode.addChildNode(sun)   // rides with the camera so shadows stay in range

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = biome.night ? 260 : 520
        ambient.light?.color = UIColor(Color(hex: biome.skyTop))
        scene.rootNode.addChildNode(ambient)

        let camera = SCNCamera()
        camera.fieldOfView = 42
        camera.zNear = 0.4
        camera.zFar = 400
        camera.wantsHDR = true
        camera.bloomIntensity = biome.night ? 0.5 : 0.18
        camera.bloomThreshold = 0.85
        camera.motionBlurIntensity = 0.35
        cameraNode.camera = camera
        // Slightly off-axis so the track reads as a solid 3D ribbon rather
        // than a flat cut-out, but close enough to side-on to stay readable.
        cameraNode.eulerAngles = SCNVector3(-0.085, 0.16, 0)
        scene.rootNode.addChildNode(cameraNode)
    }

    private func buildParticles() {
        let dustColor = UIColor(Color(hex: biome.dust))

        dustSystem.particleImage = Art.softDot(dustColor)
        dustSystem.birthRate = 0
        dustSystem.particleLifeSpan = 1.1
        dustSystem.particleLifeSpanVariation = 0.5
        dustSystem.particleSize = 0.26
        dustSystem.particleSizeVariation = 0.16
        dustSystem.particleVelocity = 2.2
        dustSystem.particleVelocityVariation = 2.0
        dustSystem.spreadingAngle = 55
        dustSystem.particleColor = dustColor
        dustSystem.particleColorVariation = SCNVector4(0.02, 0.02, 0.05, 0.2)
        dustSystem.blendMode = .alpha
        dustSystem.isAffectedByGravity = true
        dustSystem.acceleration = SCNVector3(0, 0.9, 0)
        dustSystem.emissionDuration = 1
        dustSystem.loops = true
        dustSystem.particleSizeVariation = 0.2
        dustNode.addParticleSystem(dustSystem)
        scene.rootNode.addChildNode(dustNode)

        burstSystem.particleImage = Art.softDot(dustColor)
        burstSystem.birthRate = 900
        burstSystem.emissionDuration = 0.06
        burstSystem.loops = false
        burstSystem.particleLifeSpan = 1.0
        burstSystem.particleLifeSpanVariation = 0.5
        burstSystem.particleSize = 0.3
        burstSystem.particleVelocity = 5
        burstSystem.particleVelocityVariation = 4
        burstSystem.spreadingAngle = 80
        burstSystem.particleColor = dustColor
        burstSystem.isAffectedByGravity = true
        burstSystem.blendMode = .alpha
    }

    private func pose(_ bike: Bike, _ frame: GhostFrame) {
        bike.x = frame.x
        bike.y = frame.y
        bike.ang = frame.ang
        bike.whip = frame.whip
        let c = cos(bike.ang), s = sin(bike.ang)
        for i in 0..<bike.wheels.count {
            let w = bike.wheels[i]
            let ax = bike.x + w.ax * c - w.ay * s
            let ay = bike.y + w.ax * s + w.ay * c
            bike.wheels[i].cx = ax + s * bike.rest
            bike.wheels[i].cy = ay - c * bike.rest
        }
    }

    // MARK: Frame

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if lastTime == 0 { lastTime = time }
        let dt = min(1.0 / 30.0, time - lastTime)
        lastTime = time
        guard dt > 0 else { return }

        engine.update(dt)

        for bike in engine.field {
            rigs[ObjectIdentifier(bike)]?.sync(dt: dt)
        }
        if let gb = ghostBike, let pose = engine.ghostPose {
            self.pose(gb, pose)
            ghostRig?.sync(dt: dt)
        }

        if engine.gateDropped, let g = gate, g.parent != nil {
            g.runAction(.sequence([.move(by: SCNVector3(0, -1.1, 0), duration: 0.25),
                                   .fadeOut(duration: 0.2),
                                   .removeFromParentNode()]))
        }

        applyEffects()
        updateCamera(dt: dt)
    }

    private func applyEffects() {
        let player = engine.player!
        var dustRate: CGFloat = 0
        for effect in engine.drainEffects() {
            switch effect {
            case let .dust(x, y, power):
                dustNode.position = SCNVector3(Float(x), Float(y), 0)
                dustRate = max(dustRate, CGFloat(power) * 110)
            case let .impact(x, y, power):
                let t = SCNMatrix4MakeTranslation(Float(x), Float(y), 0)
                burstSystem.particleVelocity = CGFloat(min(9, 2 + power * 0.4))
                scene.addParticleSystem(burstSystem, transform: t)
            case let .shake(amount):
                shake = min(0.55, shake + Float(amount) * 0.35)
            }
        }
        // Roost only while the rear wheel is actually driving.
        dustSystem.birthRate = player.wheels[0].grounded ? dustRate : 0
    }

    private func updateCamera(dt: Double) {
        let player = engine.player!
        let lead = Float(clampd(player.vx * 0.38, -5, 12))
        let tx = Float(player.x) + lead
        let ty = Float(player.y) + 1.9
        let k = Float(clampd(dt * 5.5, 0, 1))
        camX += (tx - camX) * k
        camY += (ty - camY) * k

        // Pull back as speed rises so fast sections still read ahead.
        let speedNorm = Float(clampd(abs(player.vx) / 45, 0, 1))
        let dist: Float = 15.5 + speedNorm * 4.5

        shake *= Float(pow(0.02, dt))
        let jitterX = Float.random(in: -shake...max(shake, 0.0001))
        let jitterY = Float.random(in: -shake...max(shake, 0.0001))
        cameraNode.position = SCNVector3(camX + jitterX, camY + jitterY, dist)
    }
}

// MARK: - SwiftUI bridge

struct Race3DView: UIViewRepresentable {
    let controller: Race3DController

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = controller.scene
        view.delegate = controller
        view.isPlaying = true
        view.rendersContinuously = true
        view.preferredFramesPerSecond = 120
        view.antialiasingMode = .multisampling2X
        view.backgroundColor = UIColor(Color(hex: controller.engine.track.biome.skyBottom))
        view.pointOfView = controller.scene.rootNode.childNodes.first { $0.camera != nil }
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}
