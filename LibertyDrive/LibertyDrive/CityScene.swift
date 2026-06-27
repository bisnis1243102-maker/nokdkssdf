import SwiftUI
import SceneKit
import UIKit

struct CityScene: UIViewRepresentable {
    @ObservedObject var model: DriveModel

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.buildWorld()
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.delegate = context.coordinator
        view.rendersContinuously = true
        view.isPlaying = true
        view.pointOfView = context.coordinator.cameraNode
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.parent = self
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        var parent: CityScene
        let cameraNode = SCNNode()
        private let scene = SCNScene()
        private let carNode = SCNNode()
        private var frontLeftPivot = SCNNode()
        private var frontRightPivot = SCNNode()
        private var wheelNodes: [SCNNode] = []

        // Car state
        private var carX: Float = 0
        private var carZ: Float = 170
        private var heading: Float = .pi
        private var speed: Float = 0
        private let carY: Float = 0.55
        private var playerPaint: SCNMaterial?

        // Wanted system
        private var wanted: Float = 0          // 0...5
        private var bustTimer: Float = 0
        private var crashCooldown: Float = 0
        private var minPoliceDist: Float = 9999

        private var buildings: [(Float, Float, Float, Float)] = []

        // Race mode
        private var cpPositions: [(Float, Float)] = []
        private var cpNode = SCNNode()
        private var raceActive = false
        private var currentCP = 0
        private var raceTime: Float = 0
        private var arrowRel: Float = 0

        // Traffic
        private struct Traffic {
            let node: SCNNode
            let axis: Int          // 0 = travels along X, 1 = travels along Z
            var pos: Float
            let fixed: Float       // perpendicular lane coordinate
            let dir: Float         // +1 or -1
            let baseSpeed: Float
            var curSpeed: Float
            let color: UIColor
        }
        private var traffic: [Traffic] = []

        private struct Police {
            let node: SCNNode
            var x: Float
            var z: Float
            var heading: Float
            let red: SCNNode
            let blue: SCNNode
        }
        private var police: [Police] = []

        private var lastTime: TimeInterval = 0
        private var hudAccum: Float = 0
        private var distance: Float = 0

        init(_ parent: CityScene) { self.parent = parent }

        // MARK: World

        func buildWorld() -> SCNScene {
            let sky = Self.skyTexture()
            scene.background.contents = sky
            scene.lightingEnvironment.contents = sky
            scene.lightingEnvironment.intensity = 1.4

            // Atmospheric haze for depth.
            scene.fogColor = UIColor(red: 0.72, green: 0.80, blue: 0.88, alpha: 1)
            scene.fogStartDistance = 130
            scene.fogEndDistance = 620
            scene.fogDensityExponent = 1.1

            // Ground
            let groundSize = CGFloat(World.half) * 2 + 80
            let ground = SCNBox(width: groundSize, height: 2, length: groundSize, chamferRadius: 0)
            let gMat = SCNMaterial()
            gMat.lightingModel = .physicallyBased
            gMat.diffuse.contents = UIColor(red: 0.17, green: 0.18, blue: 0.20, alpha: 1)
            gMat.roughness.contents = 0.95
            ground.materials = [gMat]
            let groundNode = SCNNode(geometry: ground)
            groundNode.position = SCNVector3(0, -1, 0)
            scene.rootNode.addChildNode(groundNode)

            addRoads()
            buildCity()
            addLandmarks()
            spawnTraffic()

            // Lighting
            let ambient = SCNNode()
            ambient.light = SCNLight(); ambient.light?.type = .ambient
            ambient.light?.intensity = 300
            ambient.light?.color = UIColor(red: 0.7, green: 0.78, blue: 0.9, alpha: 1)
            scene.rootNode.addChildNode(ambient)

            let sun = SCNNode()
            sun.light = SCNLight(); sun.light?.type = .directional
            sun.light?.intensity = 1100
            sun.light?.color = UIColor(red: 1.0, green: 0.96, blue: 0.86, alpha: 1)
            sun.light?.castsShadow = true
            sun.light?.shadowMode = .deferred
            sun.light?.shadowSampleCount = 8
            sun.light?.shadowRadius = 4
            sun.light?.shadowColor = UIColor(white: 0, alpha: 0.45)
            sun.eulerAngles = SCNVector3(-Float.pi / 3.0, Float.pi / 4, 0)
            scene.rootNode.addChildNode(sun)

            buildCar()
            scene.rootNode.addChildNode(carNode)

            // Camera with HDR + bloom
            let cam = SCNCamera()
            cam.fieldOfView = 62
            cam.zFar = 1400
            cam.wantsHDR = true
            cam.bloomIntensity = 0.55
            cam.bloomThreshold = 0.82
            cam.bloomBlurRadius = 8
            cam.wantsExposureAdaptation = false
            cam.motionBlurIntensity = 0.25
            cameraNode.camera = cam
            cameraNode.position = SCNVector3(carX, 9, carZ + 16)
            scene.rootNode.addChildNode(cameraNode)

            return scene
        }

        // MARK: Roads + sidewalks

        private func addRoads() {
            let step: Float = 45
            var x = -World.half
            while x <= World.half {
                addAvenue(coord: x, vertical: true)
                addAvenue(coord: x, vertical: false)
                x += step
            }
        }

        private func addAvenue(coord: Float, vertical: Bool) {
            let length = CGFloat(World.half) * 2 + 80
            let roadMat = SCNMaterial()
            roadMat.lightingModel = .physicallyBased
            roadMat.diffuse.contents = UIColor(red: 0.12, green: 0.13, blue: 0.14, alpha: 1)
            roadMat.roughness.contents = 0.8

            let road = SCNBox(width: vertical ? 16 : length, height: 0.12,
                              length: vertical ? length : 16, chamferRadius: 0)
            road.materials = [roadMat]
            let n = SCNNode(geometry: road)
            n.position = vertical ? SCNVector3(coord, 0.07, 0) : SCNVector3(0, 0.07, coord)
            scene.rootNode.addChildNode(n)

            // Dashed centre line.
            let lineMat = SCNMaterial()
            lineMat.diffuse.contents = UIColor(red: 0.95, green: 0.85, blue: 0.3, alpha: 1)
            lineMat.emission.contents = UIColor(red: 0.4, green: 0.35, blue: 0.1, alpha: 1)
            var t: Float = -World.half
            while t <= World.half {
                let dash = SCNBox(width: vertical ? 0.4 : 4, height: 0.05,
                                  length: vertical ? 4 : 0.4, chamferRadius: 0)
                dash.materials = [lineMat]
                let dn = SCNNode(geometry: dash)
                dn.position = vertical ? SCNVector3(coord, 0.14, t) : SCNVector3(t, 0.14, coord)
                scene.rootNode.addChildNode(dn)
                t += 12
            }

            // Street lamps every 45 units along the avenue.
            var l: Float = -World.half + 22
            while l < World.half {
                addLamp(vertical ? SCNVector3(coord + 9, 0, l) : SCNVector3(l, 0, coord + 9))
                l += 45
            }
        }

        private func addLamp(_ p: SCNVector3) {
            let post = SCNCylinder(radius: 0.18, height: 6)
            post.firstMaterial?.diffuse.contents = UIColor(white: 0.25, alpha: 1)
            let postNode = SCNNode(geometry: post)
            postNode.position = SCNVector3(p.x, 3, p.z)
            scene.rootNode.addChildNode(postNode)

            let bulb = SCNSphere(radius: 0.45)
            let bm = SCNMaterial()
            bm.diffuse.contents = UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 1)
            bm.emission.contents = UIColor(red: 1, green: 0.92, blue: 0.6, alpha: 1)
            bulb.materials = [bm]
            let bulbNode = SCNNode(geometry: bulb)
            bulbNode.position = SCNVector3(p.x, 6, p.z)
            scene.rootNode.addChildNode(bulbNode)
        }

        // MARK: City blocks

        private func buildCity() {
            let windows = Self.windowTexture()
            let positions = stride(from: Float(-180), through: 180, by: 45).map { $0 }
            for px in positions {
                for pz in positions {
                    if abs(px) < 23 && abs(pz) < 23 { continue }            // central plaza
                    addSidewalk(px, pz)
                    if Int(abs(px) + abs(pz)) % 7 == 0 { addPark(px, pz); continue }

                    let d = World.district(x: px, z: pz)
                    let footprint: CGFloat = 26
                    let h = d.tall ? CGFloat.random(in: 38...100) : CGFloat.random(in: 12...36)

                    let b = SCNBox(width: footprint, height: h, length: footprint, chamferRadius: 0.8)
                    let mat = SCNMaterial()
                    mat.lightingModel = .physicallyBased
                    let jitter = CGFloat.random(in: -0.05...0.05)
                    mat.diffuse.contents = UIColor(red: d.r + jitter, green: d.g + jitter,
                                                   blue: d.b + jitter, alpha: 1)
                    mat.roughness.contents = 0.6
                    mat.metalness.contents = d.tall ? 0.35 : 0.05
                    // Glowing windows via an emissive tiled texture.
                    mat.emission.contents = windows
                    mat.emission.wrapS = .repeat
                    mat.emission.wrapT = .repeat
                    mat.emission.intensity = 0.9
                    let tilesX = Float(footprint / 6.5)
                    let tilesY = Float(h / 6.5)
                    mat.emission.contentsTransform = SCNMatrix4MakeScale(tilesX, tilesY, 1)
                    b.materials = [mat]

                    let node = SCNNode(geometry: b)
                    node.position = SCNVector3(px, Float(h) / 2, pz)
                    node.castsShadow = true
                    scene.rootNode.addChildNode(node)

                    // Rooftop detail box.
                    let roof = SCNBox(width: footprint * 0.35, height: 3, length: footprint * 0.35, chamferRadius: 0.3)
                    roof.firstMaterial?.diffuse.contents = UIColor(white: 0.3, alpha: 1)
                    let roofNode = SCNNode(geometry: roof)
                    roofNode.position = SCNVector3(px, Float(h) + 1.5, pz)
                    scene.rootNode.addChildNode(roofNode)

                    buildings.append((px, pz, Float(footprint / 2), Float(footprint / 2)))
                }
            }
        }

        private func addSidewalk(_ x: Float, _ z: Float) {
            let sw = SCNBox(width: 34, height: 0.3, length: 34, chamferRadius: 0)
            sw.firstMaterial?.diffuse.contents = UIColor(white: 0.42, alpha: 1)
            sw.firstMaterial?.roughness.contents = 0.9
            let n = SCNNode(geometry: sw)
            n.position = SCNVector3(x, 0.16, z)
            scene.rootNode.addChildNode(n)
        }

        private func addPark(_ x: Float, _ z: Float) {
            let park = SCNBox(width: 30, height: 0.25, length: 30, chamferRadius: 0)
            park.firstMaterial?.diffuse.contents = UIColor(red: 0.28, green: 0.52, blue: 0.26, alpha: 1)
            park.firstMaterial?.roughness.contents = 1.0
            let n = SCNNode(geometry: park)
            n.position = SCNVector3(x, 0.2, z)
            scene.rootNode.addChildNode(n)
            for _ in 0..<4 {
                let tx = x + Float.random(in: -11...11), tz = z + Float.random(in: -11...11)
                let trunk = SCNNode(geometry: SCNCylinder(radius: 0.35, height: 2.4))
                trunk.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.4, green: 0.27, blue: 0.16, alpha: 1)
                trunk.position = SCNVector3(tx, 1.2, tz)
                scene.rootNode.addChildNode(trunk)
                let crown = SCNNode(geometry: SCNSphere(radius: 1.8))
                let cm = SCNMaterial()
                cm.diffuse.contents = UIColor(red: 0.2, green: 0.5 + .random(in: -0.05...0.08), blue: 0.2, alpha: 1)
                cm.roughness.contents = 1.0
                crown.geometry?.materials = [cm]
                crown.position = SCNVector3(tx, 3.2, tz)
                scene.rootNode.addChildNode(crown)
            }
        }

        private func addLandmarks() {
            let water = SCNBox(width: CGFloat(World.half) * 2 + 80, height: 0.4, length: 70, chamferRadius: 0)
            let wm = SCNMaterial()
            wm.lightingModel = .physicallyBased
            wm.diffuse.contents = UIColor(red: 0.17, green: 0.40, blue: 0.66, alpha: 1)
            wm.metalness.contents = 0.6
            wm.roughness.contents = 0.1
            water.materials = [wm]
            let wn = SCNNode(geometry: water)
            wn.position = SCNVector3(0, 0.05, -World.half - 30)
            scene.rootNode.addChildNode(wn)

            let sand = SCNBox(width: CGFloat(World.half) * 2 + 80, height: 0.3, length: 55, chamferRadius: 0)
            sand.firstMaterial?.diffuse.contents = UIColor(red: 0.90, green: 0.82, blue: 0.58, alpha: 1)
            sand.firstMaterial?.roughness.contents = 1.0
            let sn = SCNNode(geometry: sand)
            sn.position = SCNVector3(0, 0.1, World.half + 26)
            scene.rootNode.addChildNode(sn)
        }

        // MARK: Cars

        private func makeCarBody(paint: UIColor, detailed: Bool) -> (SCNNode, SCNNode, SCNNode, SCNMaterial) {
            let car = SCNNode()

            let body = SCNBox(width: 2.0, height: 0.6, length: 4.3, chamferRadius: 0.25)
            let pm = SCNMaterial()
            pm.lightingModel = .physicallyBased
            pm.diffuse.contents = paint
            pm.metalness.contents = 0.9
            pm.roughness.contents = 0.32
            body.materials = [pm]
            let bodyNode = SCNNode(geometry: body)
            bodyNode.position = SCNVector3(0, 0.42, 0)
            car.addChildNode(bodyNode)

            // Cabin / greenhouse with glass
            let cabin = SCNBox(width: 1.7, height: 0.62, length: 2.0, chamferRadius: 0.3)
            let glass = SCNMaterial()
            glass.lightingModel = .physicallyBased
            glass.diffuse.contents = UIColor(red: 0.10, green: 0.13, blue: 0.18, alpha: 1)
            glass.metalness.contents = 0.2
            glass.roughness.contents = 0.05
            cabin.materials = [glass]
            let cabinNode = SCNNode(geometry: cabin)
            cabinNode.position = SCNVector3(0, 0.95, -0.15)
            car.addChildNode(cabinNode)

            var pivots: [SCNNode] = []
            if detailed {
                // Headlights
                for sx in [-0.6, 0.6] {
                    let hl = SCNBox(width: 0.4, height: 0.2, length: 0.1, chamferRadius: 0.05)
                    let hm = SCNMaterial()
                    hm.diffuse.contents = UIColor.white
                    hm.emission.contents = UIColor(red: 1, green: 0.97, blue: 0.85, alpha: 1)
                    hl.materials = [hm]
                    let n = SCNNode(geometry: hl)
                    n.position = SCNVector3(Float(sx), 0.45, 2.15)
                    car.addChildNode(n)
                }
                // Taillights
                for sx in [-0.6, 0.6] {
                    let tl = SCNBox(width: 0.4, height: 0.18, length: 0.1, chamferRadius: 0.05)
                    let tm = SCNMaterial()
                    tm.diffuse.contents = UIColor.red
                    tm.emission.contents = UIColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1)
                    tl.materials = [tm]
                    let n = SCNNode(geometry: tl)
                    n.position = SCNVector3(Float(sx), 0.45, -2.15)
                    car.addChildNode(n)
                }
            }

            // Wheels (front two in steering pivots)
            for sx in [-0.95, 0.95] {
                for sz in [-1.45, 1.45] {
                    let pivot = SCNNode()
                    pivot.position = SCNVector3(Float(sx), 0.05, Float(sz))
                    let wheel = SCNCylinder(radius: 0.45, height: 0.32)
                    let wm = SCNMaterial()
                    wm.diffuse.contents = UIColor(white: 0.07, alpha: 1)
                    wm.roughness.contents = 0.8
                    wheel.materials = [wm]
                    let wn = SCNNode(geometry: wheel)
                    wn.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
                    if detailed {
                        let rim = SCNCylinder(radius: 0.22, height: 0.34)
                        rim.firstMaterial?.diffuse.contents = UIColor(white: 0.75, alpha: 1)
                        rim.firstMaterial?.metalness.contents = 1.0
                        rim.firstMaterial?.roughness.contents = 0.25
                        let rimNode = SCNNode(geometry: rim)
                        rimNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
                        pivot.addChildNode(rimNode)
                    }
                    pivot.addChildNode(wn)
                    car.addChildNode(pivot)
                    if sz > 0 { pivots.append(pivot) }   // front wheels
                }
            }
            let fl = pivots.first ?? SCNNode()
            let fr = pivots.count > 1 ? pivots[1] : SCNNode()
            return (car, fl, fr, pm)
        }

        private func buildCar() {
            let (car, fl, fr, mat) = makeCarBody(paint: UIColor(red: 0.85, green: 0.13, blue: 0.16, alpha: 1), detailed: true)
            carNode.addChildNode(car)
            carNode.position = SCNVector3(carX, carY, carZ)
            frontLeftPivot = fl
            frontRightPivot = fr
            playerPaint = mat
        }

        private func spawnTraffic() {
            let colors = [UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1),
                          UIColor(red: 0.9, green: 0.8, blue: 0.2, alpha: 1),
                          UIColor(white: 0.9, alpha: 1),
                          UIColor(white: 0.15, alpha: 1),
                          UIColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1)]
            let lanes: [Float] = stride(from: Float(-180), through: 180, by: 45).map { $0 }
            for i in 0..<14 {
                let color = colors[i % colors.count]
                let (car, _, _, _) = makeCarBody(paint: color, detailed: false)
                let axis = i % 2
                let lane = lanes[Int.random(in: 0..<lanes.count)] + (Bool.random() ? 4 : -4)
                let pos = Float.random(in: -World.half...World.half)
                let dir: Float = Bool.random() ? 1 : -1
                let base = Float.random(in: 9...17)
                car.position = axis == 0 ? SCNVector3(pos, carY, lane) : SCNVector3(lane, carY, pos)
                car.eulerAngles.y = axis == 0 ? (dir > 0 ? .pi / 2 : -.pi / 2) : (dir > 0 ? 0 : .pi)
                scene.rootNode.addChildNode(car)
                traffic.append(Traffic(node: car, axis: axis, pos: pos, fixed: lane,
                                       dir: dir, baseSpeed: base, curSpeed: base, color: color))
            }
            spawnPolice()
        }

        private func makePoliceCar() -> (SCNNode, SCNNode, SCNNode) {
            let (car, _, _, _) = makeCarBody(paint: UIColor(white: 0.95, alpha: 1), detailed: true)
            // Black door panels.
            let stripe = SCNBox(width: 2.06, height: 0.5, length: 1.7, chamferRadius: 0.2)
            stripe.firstMaterial?.diffuse.contents = UIColor(white: 0.08, alpha: 1)
            let sn = SCNNode(geometry: stripe)
            sn.position = SCNVector3(0, 0.42, 0)
            car.addChildNode(sn)
            // Roof light bar.
            let red = SCNBox(width: 0.5, height: 0.18, length: 0.5, chamferRadius: 0.05)
            let rm = SCNMaterial(); rm.diffuse.contents = UIColor.red; rm.emission.contents = UIColor.red
            red.materials = [rm]
            let rn = SCNNode(geometry: red); rn.position = SCNVector3(-0.35, 1.34, -0.1)
            car.addChildNode(rn)
            let blue = SCNBox(width: 0.5, height: 0.18, length: 0.5, chamferRadius: 0.05)
            let bm = SCNMaterial(); bm.diffuse.contents = UIColor.blue; bm.emission.contents = UIColor.blue
            blue.materials = [bm]
            let bn = SCNNode(geometry: blue); bn.position = SCNVector3(0.35, 1.34, -0.1)
            car.addChildNode(bn)
            return (car, rn, bn)
        }

        private func spawnPolice() {
            for _ in 0..<3 {
                let (car, red, blue) = makePoliceCar()
                let x = Float.random(in: -World.half...World.half)
                let z = Float.random(in: -World.half...World.half)
                car.position = SCNVector3(x, carY, z)
                scene.rootNode.addChildNode(car)
                police.append(Police(node: car, x: x, z: z, heading: 0, red: red, blue: blue))
            }
        }

        /// Traffic with simple collision-avoidance: cars slow/stop for the player
        /// and for other cars ahead in their lane, then accelerate back up.
        private func updateTraffic(dt: Float, playerX: Float, playerZ: Float) {
            let lookAhead: Float = 17
            for i in traffic.indices {
                var c = traffic[i]
                let bx: Float = c.axis == 0 ? c.pos : c.fixed
                let bz: Float = c.axis == 0 ? c.fixed : c.pos
                var target = c.baseSpeed

                // Player ahead?
                let pAlong: Float = c.axis == 0 ? (playerX - bx) * c.dir : (playerZ - bz) * c.dir
                let pLat: Float = c.axis == 0 ? (playerZ - bz) : (playerX - bx)
                if abs(pLat) < 5 && pAlong > 0 && pAlong < lookAhead {
                    target = min(target, pAlong < 7 ? 0 : c.baseSpeed * 0.3)
                }
                // Another car ahead in the same lane?
                for j in traffic.indices where j != i {
                    let o = traffic[j]
                    if o.axis != c.axis || abs(o.fixed - c.fixed) > 3 { continue }
                    let ox: Float = o.axis == 0 ? o.pos : o.fixed
                    let oz: Float = o.axis == 0 ? o.fixed : o.pos
                    let oAlong: Float = c.axis == 0 ? (ox - bx) * c.dir : (oz - bz) * c.dir
                    let oLat: Float = c.axis == 0 ? (oz - bz) : (ox - bx)
                    if abs(oLat) < 4 && oAlong > 0 && oAlong < lookAhead {
                        target = min(target, oAlong < 7 ? 0 : c.baseSpeed * 0.25)
                    }
                }

                let accel: Float = target > c.curSpeed ? 8 : 24
                c.curSpeed += max(-accel * dt, min(accel * dt, target - c.curSpeed))
                c.pos += c.dir * c.curSpeed * dt
                if c.pos > World.half { c.pos = -World.half }
                if c.pos < -World.half { c.pos = World.half }
                let fx: Float = c.axis == 0 ? c.pos : c.fixed
                let fz: Float = c.axis == 0 ? c.fixed : c.pos
                c.node.position = SCNVector3(fx, carY, fz)
                traffic[i] = c
            }
        }

        /// Police pursue only when the player is wanted; otherwise they cruise
        /// slowly and their lights are off. Tracks the nearest cop for busts.
        private func updatePolice(dt: Float, playerX: Float, playerZ: Float, time: Float) {
            let flashRed = sinf(time * 9) > 0
            let chasing = wanted >= 1
            var nearest: Float = 9999
            for i in police.indices {
                var p = police[i]
                let dx = playerX - p.x, dz = playerZ - p.z
                let dist = max(0.001, sqrtf(dx * dx + dz * dz))
                nearest = min(nearest, dist)

                let targetHeading: Float
                let spd: Float
                if chasing {
                    targetHeading = atan2f(dx, dz)             // seek the player
                    spd = dist < 8 ? 5 : 24
                } else {
                    targetHeading = p.heading + 0.3            // gentle patrol wander
                    spd = 8
                }
                var diff = targetHeading - p.heading
                while diff > .pi { diff -= 2 * .pi }
                while diff < -.pi { diff += 2 * .pi }
                p.heading += max(-2.4 * dt, min(2.4 * dt, diff))

                let fxn = sinf(p.heading), fzn = cosf(p.heading)
                var nx = p.x + fxn * spd * dt
                var nz = p.z + fzn * spd * dt
                let lim = World.half - 3
                nx = min(lim, max(-lim, nx)); nz = min(lim, max(-lim, nz))

                let rad: Float = 2.3
                for b in buildings {
                    let ex = b.2 + rad, ez = b.3 + rad
                    let ddx = nx - b.0, ddz = nz - b.1
                    if abs(ddx) < ex && abs(ddz) < ez {
                        if ex - abs(ddx) < ez - abs(ddz) { nx = b.0 + (ddx < 0 ? -ex : ex) }
                        else { nz = b.1 + (ddz < 0 ? -ez : ez) }
                    }
                }
                p.x = nx; p.z = nz
                p.node.position = SCNVector3(nx, carY, nz)
                p.node.eulerAngles.y = p.heading

                let off = UIColor(white: 0.05, alpha: 1)
                if chasing {
                    p.red.geometry?.firstMaterial?.emission.contents =
                        flashRed ? UIColor.red : UIColor(red: 0.25, green: 0, blue: 0, alpha: 1)
                    p.blue.geometry?.firstMaterial?.emission.contents =
                        flashRed ? UIColor(red: 0, green: 0, blue: 0.25, alpha: 1) : UIColor.blue
                } else {
                    p.red.geometry?.firstMaterial?.emission.contents = off
                    p.blue.geometry?.firstMaterial?.emission.contents = off
                }
                police[i] = p
            }
            minPoliceDist = nearest
        }

        /// Carjack: take over the nearest civilian car within reach.
        private func attemptSteal() {
            guard let idx = traffic.indices.min(by: { a, b in
                let pa = traffic[a], pb = traffic[b]
                let ax: Float = pa.axis == 0 ? pa.pos : pa.fixed
                let az: Float = pa.axis == 0 ? pa.fixed : pa.pos
                let bx: Float = pb.axis == 0 ? pb.pos : pb.fixed
                let bz: Float = pb.axis == 0 ? pb.fixed : pb.pos
                let da = (ax - carX) * (ax - carX) + (az - carZ) * (az - carZ)
                let db = (bx - carX) * (bx - carX) + (bz - carZ) * (bz - carZ)
                return da < db
            }) else { return }
            let t = traffic[idx]
            let tx: Float = t.axis == 0 ? t.pos : t.fixed
            let tz: Float = t.axis == 0 ? t.fixed : t.pos
            let d = sqrtf((tx - carX) * (tx - carX) + (tz - carZ) * (tz - carZ))
            guard d < 14 else { return }      // must be close enough
            // Repaint our car to the stolen one's colour and remove that car.
            playerPaint?.diffuse.contents = t.color
            t.node.removeFromParentNode()
            traffic.remove(at: idx)
            // Stealing a car is a crime.
            wanted = min(5, max(wanted, 1) + 1.5)
        }

        /// Wanted-level decay, escaping, and busts.
        private func updateWanted(dt: Float) {
            guard wanted > 0 else { bustTimer = 0; return }
            // Decay: much faster once you've shaken the nearest cop.
            let escaping = minPoliceDist > 55
            wanted = max(0, wanted - (escaping ? 0.35 : 0.05) * dt)

            // Bust: a cop pins you (very close) while you're nearly stopped.
            if minPoliceDist < 4.2 && abs(speed) < 3 {
                bustTimer += dt
            } else {
                bustTimer = max(0, bustTimer - dt * 0.5)
            }
            if bustTimer > 2.5 {
                bustTimer = 0
                wanted = 0
                speed = 0
                let m = parent.model
                DispatchQueue.main.async {
                    m.busted = true
                    m.stars = 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { m.busted = false }
                }
            }
        }

        // MARK: Race / festival mode

        private func makeCheckpoint() -> SCNNode {
            let node = SCNNode()
            let ring = SCNTorus(ringRadius: 6, pipeRadius: 0.55)
            let rm = SCNMaterial()
            rm.diffuse.contents = UIColor(red: 1, green: 0.2, blue: 0.9, alpha: 1)
            rm.emission.contents = UIColor(red: 1, green: 0.2, blue: 0.9, alpha: 1)
            ring.materials = [rm]
            let rn = SCNNode(geometry: ring)
            rn.position.y = 0.5
            rn.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 4)))
            node.addChildNode(rn)

            // Tall light beam so the next gate is visible from afar.
            let beam = SCNCylinder(radius: 1.1, height: 36)
            let bm = SCNMaterial()
            bm.diffuse.contents = UIColor(red: 1, green: 0.3, blue: 0.95, alpha: 0.22)
            bm.emission.contents = UIColor(red: 1, green: 0.3, blue: 0.95, alpha: 0.5)
            bm.blendMode = .add
            bm.writesToDepthBuffer = false
            beam.materials = [bm]
            let bn = SCNNode(geometry: beam)
            bn.position.y = 18
            node.addChildNode(bn)
            return node
        }

        private func positionCheckpoint() {
            guard currentCP < cpPositions.count else { return }
            let (x, z) = cpPositions[currentCP]
            cpNode.position = SCNVector3(x, 0, z)
        }

        private func startRace() {
            cpNode.removeFromParentNode()
            cpPositions = (0..<6).map { _ in
                (Float.random(in: -165...165), Float.random(in: -165...165))
            }
            cpNode = makeCheckpoint()
            scene.rootNode.addChildNode(cpNode)
            currentCP = 0
            raceTime = 0
            raceActive = true
            positionCheckpoint()
            let m = parent.model
            let total = cpPositions.count
            DispatchQueue.main.async {
                m.racing = true; m.raceFinished = false
                m.cpTotal = total; m.cpIndex = 0; m.raceTime = 0
            }
        }

        private func finishRace() {
            raceActive = false
            cpNode.removeFromParentNode()
            let t = Double(raceTime)
            let m = parent.model
            DispatchQueue.main.async {
                m.racing = false
                m.raceFinished = true
                m.lastTime = t
                if m.bestTime == 0 || t < m.bestTime {
                    m.bestTime = t
                    UserDefaults.standard.set(t, forKey: "forsa.bestTime")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { m.raceFinished = false }
            }
        }

        private func updateRace(dt: Float) {
            guard raceActive, currentCP < cpPositions.count else { return }
            raceTime += dt
            let (cx, cz) = cpPositions[currentCP]
            let dx = cx - carX, dz = cz - carZ
            // Arrow direction relative to where the car is pointing.
            var rel = atan2f(dx, dz) - heading
            while rel > .pi { rel -= 2 * .pi }
            while rel < -.pi { rel += 2 * .pi }
            arrowRel = rel
            if sqrtf(dx * dx + dz * dz) < 7 {
                currentCP += 1
                if currentCP >= cpPositions.count { finishRace() }
                else { positionCheckpoint() }
            }
        }

        // MARK: Per-frame update

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            let dt = lastTime == 0 ? 0 : Float(min(0.05, time - lastTime))
            lastTime = time
            guard dt > 0 else { return }
            let m = parent.model

            let power: Float = 32
            speed += m.throttle * power * dt
            let drag: Float = m.throttle == 0 ? 1.1 : 0.4
            speed -= speed * drag * dt
            speed = min(38, max(-12, speed))
            if abs(speed) < 0.05 { speed = 0 }

            if abs(speed) > 0.15 {
                let steerRate: Float = 2.8
                let dir: Float = speed >= 0 ? 1 : -1
                // More responsive, with a solid base turn-rate even at low speed.
                let responsiveness = min(1.0, 0.45 + abs(speed) / 11)
                heading += m.steer * steerRate * dt * dir * responsiveness
            }
            // Visually turn the front wheels.
            frontLeftPivot.eulerAngles.y = m.steer * 0.5
            frontRightPivot.eulerAngles.y = m.steer * 0.5

            // On-screen button actions.
            if m.stealRequested { m.stealRequested = false; attemptSteal() }
            if m.startRaceRequested { m.startRaceRequested = false; startRace() }

            let fx = sinf(heading), fz = cosf(heading)
            var nx = carX + fx * speed * dt
            var nz = carZ + fz * speed * dt
            let lim = World.half - 3
            nx = min(lim, max(-lim, nx)); nz = min(lim, max(-lim, nz))

            let preSpeed = abs(speed)
            var crashed = false
            let rad: Float = 2.3
            for b in buildings {
                let ex = b.2 + rad, ez = b.3 + rad
                let dx = nx - b.0, dz = nz - b.1
                if abs(dx) < ex && abs(dz) < ez {
                    if ex - abs(dx) < ez - abs(dz) { nx = b.0 + (dx < 0 ? -ex : ex) }
                    else { nz = b.1 + (dz < 0 ? -ez : ez) }
                    speed *= 0.25
                    crashed = true
                }
            }

            // Crime: crashing hard, or sustained speeding, raises the wanted level.
            crashCooldown = max(0, crashCooldown - dt)
            if crashed && preSpeed > 12 && crashCooldown <= 0 {
                wanted = min(5, wanted + 0.8); crashCooldown = 1.0
            }
            if abs(speed) > 30 { wanted = min(5, wanted + 0.25 * dt) }

            distance += abs(speed) * dt
            carX = nx; carZ = nz
            carNode.position = SCNVector3(nx, carY, nz)
            carNode.eulerAngles.y = heading

            // Smarter traffic + pursuing police + wanted bookkeeping
            updateTraffic(dt: dt, playerX: nx, playerZ: nz)
            updatePolice(dt: dt, playerX: nx, playerZ: nz, time: Float(time))
            updateWanted(dt: dt)
            updateRace(dt: dt)

            // Chase camera
            let desired = SCNVector3(nx - fx * 14, 8.5, nz - fz * 14)
            let lerp = min(1, dt * 4.5)
            cameraNode.position = SCNVector3(
                cameraNode.position.x + (desired.x - cameraNode.position.x) * lerp,
                cameraNode.position.y + (desired.y - cameraNode.position.y) * lerp,
                cameraNode.position.z + (desired.z - cameraNode.position.z) * lerp)
            cameraNode.look(at: SCNVector3(nx + fx * 6, 1.6, nz + fz * 6),
                            up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))

            hudAccum += dt
            if hudAccum >= 0.16 {
                hudAccum = 0
                let kmh = Int(abs(speed) * 7.5), dist = Int(distance)
                let name = World.name(x: nx, z: nz)
                let stars = wanted > 0 ? min(5, Int(wanted.rounded(.up))) : 0
                let hx = nx, hz = nz, hh = heading
                let racing = raceActive, cpi = currentCP, rt = Double(raceTime), arrow = arrowRel
                DispatchQueue.main.async {
                    m.speedKmh = kmh; m.distanceM = dist; m.district = name
                    m.stars = stars
                    m.carX = hx; m.carZ = hz; m.heading = hh
                    m.racing = racing; m.cpIndex = cpi; m.raceTime = rt; m.arrowAngle = arrow
                }
            }
        }

        // MARK: Procedural textures

        static func skyTexture() -> UIImage {
            let size = CGSize(width: 8, height: 256)
            let r = UIGraphicsImageRenderer(size: size)
            return r.image { ctx in
                let cg = ctx.cgContext
                let colors = [UIColor(red: 0.36, green: 0.56, blue: 0.86, alpha: 1).cgColor,
                              UIColor(red: 0.62, green: 0.76, blue: 0.92, alpha: 1).cgColor,
                              UIColor(red: 0.82, green: 0.86, blue: 0.90, alpha: 1).cgColor,
                              UIColor(red: 0.30, green: 0.32, blue: 0.34, alpha: 1).cgColor]
                let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors as CFArray, locations: [0, 0.45, 0.5, 1])!
                cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0),
                                      end: CGPoint(x: 0, y: size.height), options: [])
            }
        }

        static func windowTexture() -> UIImage {
            let size = CGSize(width: 128, height: 128)
            let r = UIGraphicsImageRenderer(size: size)
            return r.image { ctx in
                UIColor.black.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                let cols = 4, rows = 4
                let pad: CGFloat = 5
                let cw = (size.width - CGFloat(cols + 1) * pad) / CGFloat(cols)
                let ch = (size.height - CGFloat(rows + 1) * pad) / CGFloat(rows)
                for row in 0..<rows {
                    for col in 0..<cols {
                        let lit = Double.random(in: 0...1) < 0.55
                        let c: UIColor = lit
                            ? UIColor(red: 1.0, green: 0.86, blue: 0.55, alpha: 1)
                            : UIColor(white: 0.06, alpha: 1)
                        c.setFill()
                        let x = pad + CGFloat(col) * (cw + pad)
                        let y = pad + CGFloat(row) * (ch + pad)
                        ctx.fill(CGRect(x: x, y: y, width: cw, height: ch))
                    }
                }
            }
        }
    }
}
