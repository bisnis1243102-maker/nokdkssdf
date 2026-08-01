import UIKit
import SceneKit

/// World construction: ground, road grid, blocks, props and landmarks.
extension GameSceneView.Coordinator {

    // MARK: Deterministic randomness
    //
    // The city must be identical on every launch, because missions reference
    // landmarks by fixed coordinates. So: a seeded hash, never `random()`.

    func rnd(_ a: Int, _ b: Int, _ seed: Int) -> Float {
        Float(TextureFactory.fbm(CGFloat(a) * 0.37 + 0.11,
                                 CGFloat(b) * 0.53 + 0.29,
                                 seed))
    }

    // MARK: Ground

    func buildGround() {
        let size = CGFloat(CityWorld.half * 2 + 200)
        let plane = SCNPlane(width: size, height: size)
        let m = plane.firstMaterial!
        let set = TextureFactory.asphalt(size: model.quality.textureSize, laneMarking: false)
        TextureFactory.apply(set, to: m, repeatX: 90, repeatY: 90)
        // The ground between blocks reads as dark hardstanding, not tarmac.
        m.diffuse.intensity = 0.55
        m.roughness.contents = 0.92

        let node = SCNNode(geometry: plane)
        node.eulerAngles.x = -.pi / 2
        node.position = SCNVector3(0, CityWorld.groundY - 0.02, 0)
        node.castsShadow = false
        scene.rootNode.addChildNode(node)
    }

    // MARK: Roads

    func buildRoads() {
        let span = CGFloat(CityWorld.half * 2)
        let width = CGFloat(CityWorld.roadHalfWidth * 2)
        let set = TextureFactory.asphalt(size: model.quality.textureSize, laneMarking: true)

        for a in CityWorld.avenues {
            for vertical in [true, false] {
                let plane = SCNPlane(width: vertical ? width : span,
                                     height: vertical ? span : width)
                let m = plane.firstMaterial!
                TextureFactory.apply(set, to: m,
                                     repeatX: vertical ? 1 : 40,
                                     repeatY: vertical ? 40 : 1)
                // Wet-road modifier: this is the surface the reflections land on.
                ShaderModifiers.applyWetRoad(to: m)
                weather.register(wetMaterial: m)

                let node = SCNNode(geometry: plane)
                node.eulerAngles.x = -.pi / 2
                node.position = vertical ? SCNVector3(a, 0.01, 0) : SCNVector3(0, 0.012, a)
                node.castsShadow = false
                scene.rootNode.addChildNode(node)
            }
        }

        // Street lights down every avenue, alternating sides.
        var lampIndex = 0
        for a in CityWorld.avenues {
            var t = -CityWorld.half + 20
            while t < CityWorld.half {
                let side: Float = lampIndex % 2 == 0 ? 1 : -1
                addStreetLight(x: a + CityWorld.roadHalfWidth * 1.15 * side, z: t)
                addStreetLight(x: t, z: a + CityWorld.roadHalfWidth * 1.15 * side)
                t += 46
                lampIndex += 1
            }
        }
    }

    private func addStreetLight(x: Float, z: Float) {
        let pole = SCNCylinder(radius: 0.13, height: 6.4)
        let pm = pole.firstMaterial!
        pm.lightingModel = .physicallyBased
        pm.diffuse.contents = UIColor(white: 0.10, alpha: 1)
        pm.metalness.contents = 0.85
        pm.roughness.contents = 0.42

        let poleNode = SCNNode(geometry: pole)
        poleNode.position = SCNVector3(x, 3.2, z)

        // Lamp head.
        let head = SCNBox(width: 1.5, height: 0.22, length: 0.5, chamferRadius: 0.08)
        let hm = head.firstMaterial!
        hm.lightingModel = .physicallyBased
        hm.diffuse.contents = UIColor(white: 0.12, alpha: 1)
        hm.emission.contents = UIColor(red: 1.0, green: 0.80, blue: 0.52, alpha: 1)
        hm.emission.intensity = 1.4
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 3.3, 0)
        poleNode.addChildNode(headNode)

        // The actual light, streamed on/off by distance at night.
        let light = SCNLight()
        light.type = .omni
        light.color = UIColor(red: 1.0, green: 0.82, blue: 0.58, alpha: 1)
        light.intensity = 0
        light.attenuationEndDistance = 24
        light.attenuationStartDistance = 2
        let lightNode = SCNNode()
        lightNode.light = light
        lightNode.position = SCNVector3(x, 6.0, z)
        scene.rootNode.addChildNode(lightNode)
        streetLights.append(lightNode)

        scene.rootNode.addChildNode(poleNode)
    }

    // MARK: City blocks

    func buildCity() {
        let avenues = CityWorld.avenues
        // Each pair of neighbouring avenues bounds one block.
        for (ci, cx) in avenues.enumerated() {
            for (ri, cz) in avenues.enumerated() {
                let blockX = cx + CityWorld.blockSize / 2
                let blockZ = cz + CityWorld.blockSize / 2
                if abs(blockX) > CityWorld.half || abs(blockZ) > CityWorld.half { continue }

                let district = CityWorld.district(x: blockX, z: blockZ)
                addSidewalk(x: blockX, z: blockZ)

                if rnd(ci, ri, 5) < Float(district.openness) {
                    addPark(x: blockX, z: blockZ, district: district)
                } else {
                    addBuildings(blockX: blockX, blockZ: blockZ,
                                 district: district, ci: ci, ri: ri)
                }
            }
        }
    }

    private func addSidewalk(x: Float, z: Float) {
        let inner = CGFloat(CityWorld.blockSize - CityWorld.roadHalfWidth * 2)
        let plane = SCNPlane(width: inner, height: inner)
        let m = plane.firstMaterial!
        TextureFactory.apply(TextureFactory.sidewalk(size: model.quality.textureSize),
                             to: m, repeatX: 6, repeatY: 6)
        ShaderModifiers.applyWetRoad(to: m)
        weather.register(wetMaterial: m)

        let node = SCNNode(geometry: plane)
        node.eulerAngles.x = -.pi / 2
        node.position = SCNVector3(x, 0.16, z)
        node.castsShadow = false
        scene.rootNode.addChildNode(node)

        // Kerb.
        let kerb = SCNBox(width: inner + 1.2, height: 0.34, length: inner + 1.2, chamferRadius: 0.05)
        let km = kerb.firstMaterial!
        km.lightingModel = .physicallyBased
        km.diffuse.contents = UIColor(white: 0.24, alpha: 1)
        km.roughness.contents = 0.8
        let kn = SCNNode(geometry: kerb)
        kn.position = SCNVector3(x, 0.02, z)
        scene.rootNode.addChildNode(kn)
    }

    private func addBuildings(blockX: Float, blockZ: Float,
                              district: District, ci: Int, ri: Int) {
        // Two to four towers per block, laid out on a small internal grid.
        let count = 2 + Int(rnd(ci, ri, 9) * 3)
        let usable = CityWorld.blockSize - CityWorld.roadHalfWidth * 2 - 4

        for i in 0..<count {
            let ox = (rnd(ci * 7 + i, ri, 13) - 0.5) * usable * 0.55
            let oz = (rnd(ci, ri * 7 + i, 17) - 0.5) * usable * 0.55
            let w = CGFloat(9 + rnd(ci + i, ri, 21) * 12)
            let d = CGFloat(9 + rnd(ci, ri + i, 23) * 12)

            let base: Float
            switch district.height {
            case 2: base = 34 + rnd(ci + i, ri + i, 27) * 66
            case 1: base = 16 + rnd(ci + i, ri + i, 29) * 26
            default: base = 7 + rnd(ci + i, ri + i, 31) * 12
            }
            let h = CGFloat(base)

            let box = SCNBox(width: w, height: h, length: d, chamferRadius: 0.25)
            let seed = ci * 131 + ri * 17 + i
            let m = box.firstMaterial!
            TextureFactory.apply(TextureFactory.facade(size: model.quality.textureSize,
                                                       tint: district.tint, seed: seed),
                                 to: m,
                                 repeatX: max(1, w / 9),
                                 repeatY: max(1, h / 9))
            m.emission.contents = TextureFactory.facadeEmission(
                size: model.quality.textureSize, seed: seed,
                warm: UIColor(red: 1.0, green: 0.84, blue: 0.58, alpha: 1))
            m.emission.wrapS = .repeat
            m.emission.wrapT = .repeat
            m.emission.contentsTransform = SCNMatrix4MakeScale(Float(max(1, w / 9)),
                                                               Float(max(1, h / 9)), 1)
            m.emission.intensity = 0.0     // raised at night by applySky

            let node = SCNNode(geometry: box)
            let bx = blockX + ox, bz = blockZ + oz
            node.position = SCNVector3(bx, Float(h) / 2 + 0.16, bz)
            node.castsShadow = true
            scene.rootNode.addChildNode(node)

            buildings.append((bx, bz, Float(w) / 2, Float(d) / 2))
            emissiveFacades.append(m)

            // A neon sign on roughly half the buildings, facing the street.
            if rnd(ci + i, ri, 37) > 0.5 {
                addNeonSign(on: node, size: SIMD3<Float>(Float(w), Float(h), Float(d)),
                            color: district.neon, seed: seed)
            }
        }
    }

    /// Mounts a glowing sign flat against the building's -Z face, plus a small
    /// coloured light so it spills onto the street below.
    private func addNeonSign(on building: SCNNode, size: SIMD3<Float>,
                             color: UIColor, seed: Int) {
        let w = CGFloat(min(size.x * 0.7, 8))
        let h = w * 0.75
        let panel = SCNPlane(width: w, height: h)
        let m = panel.firstMaterial!
        m.lightingModel = .constant
        m.diffuse.contents = UIColor.black
        m.emission.contents = TextureFactory.neonSign(size: 128, color: color, seed: seed)
        m.isDoubleSided = true
        ShaderModifiers.applyNeon(to: m, seed: Float(seed % 97) / 97)
        neonMaterials.append(m)

        // The box's local origin is its centre, so the front face sits at -depth/2.
        let faceZ = -size.z / 2 - 0.12
        let signY = size.y * 0.18

        let node = SCNNode(geometry: panel)
        node.position = SCNVector3(0, signY, faceZ)
        node.castsShadow = false
        building.addChildNode(node)

        let light = SCNLight()
        light.type = .omni
        light.color = color
        light.intensity = 0
        light.attenuationEndDistance = 22
        let ln = SCNNode()
        ln.light = light
        ln.position = SCNVector3(0, signY, faceZ - 2)
        building.addChildNode(ln)
        streetLights.append(ln)
    }

    // MARK: Parks and lots

    private func addPark(x: Float, z: Float, district: District) {
        let side = CGFloat(CityWorld.blockSize - CityWorld.roadHalfWidth * 2 - 2)
        let plane = SCNPlane(width: side, height: side)
        let m = plane.firstMaterial!
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(red: 0.10, green: 0.20, blue: 0.12, alpha: 1)
        m.roughness.contents = 0.95
        let node = SCNNode(geometry: plane)
        node.eulerAngles.x = -.pi / 2
        node.position = SCNVector3(x, 0.18, z)
        scene.rootNode.addChildNode(node)

        for i in 0..<6 {
            let ox = (rnd(Int(x) + i, Int(z), 43) - 0.5) * Float(side) * 0.8
            let oz = (rnd(Int(x), Int(z) + i, 47) - 0.5) * Float(side) * 0.8
            addTree(x: x + ox, z: z + oz, seed: i)
        }
    }

    private func addTree(x: Float, z: Float, seed: Int) {
        let trunk = SCNCylinder(radius: 0.22, height: 2.6)
        let tm = trunk.firstMaterial!
        tm.lightingModel = .physicallyBased
        tm.diffuse.contents = UIColor(red: 0.20, green: 0.14, blue: 0.10, alpha: 1)
        tm.roughness.contents = 0.9
        let tn = SCNNode(geometry: trunk)
        tn.position = SCNVector3(x, 1.5, z)
        scene.rootNode.addChildNode(tn)

        let canopy = SCNSphere(radius: CGFloat(1.6 + rnd(seed, 1, 53) * 0.9))
        canopy.segmentCount = 10
        let cm = canopy.firstMaterial!
        cm.lightingModel = .physicallyBased
        cm.diffuse.contents = UIColor(red: 0.10, green: 0.28, blue: 0.14, alpha: 1)
        cm.roughness.contents = 0.85
        ShaderModifiers.applyFoliage(to: cm)
        let cn = SCNNode(geometry: canopy)
        cn.position = SCNVector3(x, 3.4, z)
        scene.rootNode.addChildNode(cn)
    }

    // MARK: Landmarks

    /// A tall marker at every mission destination, so places are findable by
    /// eye and not only by the HUD arrow.
    func buildLandmarks() {
        for (_, l) in CityWorld.landmarks {
            let tower = SCNCylinder(radius: 0.6, height: 26)
            let m = tower.firstMaterial!
            m.lightingModel = .constant
            m.diffuse.contents = UIColor.black
            m.emission.contents = UIColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 1)
            m.emission.intensity = 0.35
            m.transparency = 0.30

            let n = SCNNode(geometry: tower)
            n.position = SCNVector3(l.x, 13, l.z)
            n.castsShadow = false
            scene.rootNode.addChildNode(n)
        }
    }

    // MARK: Markers

    func buildMarkers() {
        // Objective marker: a rotating ring of light.
        let ring = SCNTorus(ringRadius: 2.6, pipeRadius: 0.22)
        let rm = ring.firstMaterial!
        rm.lightingModel = .constant
        rm.diffuse.contents = UIColor.black
        rm.emission.contents = UIColor(red: 1.0, green: 0.85, blue: 0.25, alpha: 1)
        rm.emission.intensity = 2.2
        waypointNode.geometry = ring
        waypointNode.isHidden = true
        waypointNode.castsShadow = false
        waypointNode.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 4)))
        scene.rootNode.addChildNode(waypointNode)

        // Mission start marker: a pillar you drive into.
        let pillar = SCNCylinder(radius: 2.2, height: 7)
        let pm = pillar.firstMaterial!
        pm.lightingModel = .constant
        pm.diffuse.contents = UIColor.black
        pm.emission.contents = UIColor(red: 0.35, green: 1.0, blue: 0.72, alpha: 1)
        pm.emission.intensity = 1.8
        pm.transparency = 0.42
        startMarkerNode.geometry = pillar
        startMarkerNode.isHidden = true
        startMarkerNode.castsShadow = false
        scene.rootNode.addChildNode(startMarkerNode)
    }
}
