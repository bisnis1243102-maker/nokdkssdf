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

        // Car state
        private var carX: Float = 0
        private var carZ: Float = 170
        private var heading: Float = .pi
        private var speed: Float = 0
        private let carY: Float = 0.55
        private var driftScore: Float = 0

        // Lighting + weather
        private var sunNode = SCNNode()
        private var ambientNode = SCNNode()
        private var rainNode: SCNNode?
        private var weatherIndex = 0
        private var weatherTimer: Float = 0

        private var buildings: [(Float, Float, Float, Float)] = []

        // Traffic
        private struct Traffic {
            let node: SCNNode
            let axis: Int
            var pos: Float
            let fixed: Float
            let dir: Float
            let baseSpeed: Float
            var curSpeed: Float
        }
        private var traffic: [Traffic] = []

        // Race mode
        private var cpPositions: [(Float, Float)] = []
        private var cpNode = SCNNode()
        private var raceActive = false
        private var currentCP = 0
        private var raceTime: Float = 0
        private var arrowRel: Float = 0

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
            scene.fogColor = UIColor(red: 0.82, green: 0.84, blue: 0.88, alpha: 1)
            scene.fogStartDistance = 160
            scene.fogEndDistance = 700
            scene.fogDensityExponent = 1.1

            let groundSize = CGFloat(World.half) * 2 + 80
            let ground = SCNBox(width: groundSize, height: 2, length: groundSize, chamferRadius: 0)
            let gMat = SCNMaterial()
            gMat.lightingModel = .physicallyBased
            gMat.diffuse.contents = UIColor(red: 0.30, green: 0.40, blue: 0.26, alpha: 1)   // grassy
            gMat.roughness.contents = 0.95
            ground.materials = [gMat]
            let groundNode = SCNNode(geometry: ground)
            groundNode.position = SCNVector3(0, -1, 0)
            scene.rootNode.addChildNode(groundNode)

            addRoads()
            buildCity()
            addLandmarks()
            addMountFuji()
            addPagoda(at: SCNVector3(70, 0, 70))
            addScenery()
            spawnTraffic()

            ambientNode.light = SCNLight(); ambientNode.light?.type = .ambient
            ambientNode.light?.color = UIColor(white: 1, alpha: 1)
            scene.rootNode.addChildNode(ambientNode)

            sunNode.light = SCNLight(); sunNode.light?.type = .directional
            sunNode.light?.castsShadow = true
            sunNode.light?.shadowMode = .deferred
            sunNode.light?.shadowSampleCount = 8
            sunNode.light?.shadowRadius = 4
            sunNode.light?.shadowColor = UIColor(white: 0, alpha: 0.42)
            sunNode.eulerAngles = SCNVector3(-Float.pi / 3.0, Float.pi / 4, 0)
            scene.rootNode.addChildNode(sunNode)

            buildCar()
            scene.rootNode.addChildNode(carNode)
            applyWeather(0)

            let cam = SCNCamera()
            cam.fieldOfView = 62
            cam.zFar = 2000
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

        // MARK: Roads

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
            roadMat.diffuse.contents = UIColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1)
            roadMat.roughness.contents = 0.8
            let road = SCNBox(width: vertical ? 16 : length, height: 0.12,
                              length: vertical ? length : 16, chamferRadius: 0)
            road.materials = [roadMat]
            let n = SCNNode(geometry: road)
            n.position = vertical ? SCNVector3(coord, 0.07, 0) : SCNVector3(0, 0.07, coord)
            scene.rootNode.addChildNode(n)

            let lineMat = SCNMaterial()
            lineMat.diffuse.contents = UIColor(red: 0.95, green: 0.9, blue: 0.4, alpha: 1)
            lineMat.emission.contents = UIColor(red: 0.4, green: 0.36, blue: 0.12, alpha: 1)
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

            // Street lamps and roadside cherry trees along the avenue.
            var l: Float = -World.half + 22
            while l < World.half {
                addLamp(vertical ? SCNVector3(coord + 9, 0, l) : SCNVector3(l, 0, coord + 9))
                if Int(l) % 90 == 0 {
                    addCherryTree(vertical ? SCNVector3(coord - 11, 0, l) : SCNVector3(l, 0, coord - 11),
                                  blossom: true)
                }
                l += 45
            }
        }

        private func addLamp(_ p: SCNVector3) {
            let post = SCNCylinder(radius: 0.18, height: 6)
            post.firstMaterial?.diffuse.contents = UIColor(white: 0.25, alpha: 1)
            let pn = SCNNode(geometry: post)
            pn.position = SCNVector3(p.x, 3, p.z)
            scene.rootNode.addChildNode(pn)
            let bulb = SCNSphere(radius: 0.4)
            let bm = SCNMaterial()
            bm.diffuse.contents = UIColor(red: 1, green: 0.95, blue: 0.7, alpha: 1)
            bm.emission.contents = UIColor(red: 1, green: 0.92, blue: 0.6, alpha: 1)
            bulb.materials = [bm]
            let bn = SCNNode(geometry: bulb)
            bn.position = SCNVector3(p.x, 6, p.z)
            scene.rootNode.addChildNode(bn)
        }

        // MARK: City

        private func buildCity() {
            let windows = Self.windowTexture()
            let positions = stride(from: Float(-180), through: 180, by: 45).map { $0 }
            for px in positions {
                for pz in positions {
                    if abs(px) < 23 && abs(pz) < 23 { continue }
                    addSidewalk(px, pz)
                    if Int(abs(px) + abs(pz)) % 5 == 0 { addPark(px, pz); continue }

                    let d = World.district(x: px, z: pz)
                    let footprint: CGFloat = 26
                    let h = d.tall ? CGFloat.random(in: 34...88) : CGFloat.random(in: 12...34)
                    let b = SCNBox(width: footprint, height: h, length: footprint, chamferRadius: 0.8)
                    let mat = SCNMaterial()
                    mat.lightingModel = .physicallyBased
                    let jitter = CGFloat.random(in: -0.05...0.05)
                    mat.diffuse.contents = UIColor(red: d.r + jitter, green: d.g + jitter,
                                                   blue: d.b + jitter, alpha: 1)
                    mat.roughness.contents = 0.6
                    mat.metalness.contents = d.tall ? 0.35 : 0.05
                    mat.emission.contents = windows
                    mat.emission.wrapS = .repeat
                    mat.emission.wrapT = .repeat
                    mat.emission.intensity = 0.85
                    mat.emission.contentsTransform = SCNMatrix4MakeScale(Float(footprint / 6.5), Float(h / 6.5), 1)
                    b.materials = [mat]
                    let node = SCNNode(geometry: b)
                    node.position = SCNVector3(px, Float(h) / 2, pz)
                    scene.rootNode.addChildNode(node)
                    buildings.append((px, pz, Float(footprint / 2), Float(footprint / 2)))
                }
            }
        }

        private func addSidewalk(_ x: Float, _ z: Float) {
            let sw = SCNBox(width: 34, height: 0.3, length: 34, chamferRadius: 0)
            sw.firstMaterial?.diffuse.contents = UIColor(white: 0.46, alpha: 1)
            sw.firstMaterial?.roughness.contents = 0.9
            let n = SCNNode(geometry: sw)
            n.position = SCNVector3(x, 0.16, z)
            scene.rootNode.addChildNode(n)
        }

        private func addPark(_ x: Float, _ z: Float) {
            let park = SCNBox(width: 30, height: 0.25, length: 30, chamferRadius: 0)
            park.firstMaterial?.diffuse.contents = UIColor(red: 0.30, green: 0.55, blue: 0.28, alpha: 1)
            park.firstMaterial?.roughness.contents = 1.0
            let n = SCNNode(geometry: park)
            n.position = SCNVector3(x, 0.2, z)
            scene.rootNode.addChildNode(n)
            for _ in 0..<4 {
                let tx = x + Float.random(in: -11...11), tz = z + Float.random(in: -11...11)
                addCherryTree(SCNVector3(tx, 0, tz), blossom: Bool.random())
            }
        }

        /// A tree — cherry-blossom (pink) or green — to sell the Japan setting.
        private func addCherryTree(_ p: SCNVector3, blossom: Bool) {
            let trunk = SCNNode(geometry: SCNCylinder(radius: 0.35, height: 2.4))
            trunk.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.36, green: 0.24, blue: 0.16, alpha: 1)
            trunk.position = SCNVector3(p.x, 1.2, p.z)
            scene.rootNode.addChildNode(trunk)
            let crown = SCNNode(geometry: SCNSphere(radius: 1.9))
            let cm = SCNMaterial()
            cm.diffuse.contents = blossom
                ? UIColor(red: 1.0, green: 0.72, blue: 0.82, alpha: 1)
                : UIColor(red: 0.2, green: 0.5, blue: 0.22, alpha: 1)
            cm.roughness.contents = 1.0
            crown.geometry?.materials = [cm]
            crown.position = SCNVector3(p.x, 3.3, p.z)
            scene.rootNode.addChildNode(crown)
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

        /// Snow-capped Mt. Fuji backdrop beyond the bay.
        private func addMountFuji() {
            let base = SCNCone(topRadius: 14, bottomRadius: 150, height: 150)
            let bm = SCNMaterial()
            bm.diffuse.contents = UIColor(red: 0.40, green: 0.45, blue: 0.52, alpha: 1)
            bm.roughness.contents = 1.0
            base.materials = [bm]
            let baseNode = SCNNode(geometry: base)
            baseNode.position = SCNVector3(-40, 60, -World.half - 320)
            baseNode.castsShadow = false
            scene.rootNode.addChildNode(baseNode)

            let cap = SCNCone(topRadius: 0, bottomRadius: 34, height: 42)
            let cm = SCNMaterial()
            cm.diffuse.contents = UIColor.white
            cm.roughness.contents = 0.85
            cap.materials = [cm]
            let capNode = SCNNode(geometry: cap)
            capNode.position = SCNVector3(-40, 124, -World.half - 320)
            capNode.castsShadow = false
            scene.rootNode.addChildNode(capNode)
        }

        /// A simple multi-tier red-roof pagoda landmark.
        private func addPagoda(at p: SCNVector3) {
            let widths: [CGFloat] = [9, 7.5, 6]
            var y: Float = 0
            for (i, w) in widths.enumerated() {
                let body = SCNBox(width: w, height: 4, length: w, chamferRadius: 0.2)
                body.firstMaterial?.diffuse.contents = UIColor(red: 0.85, green: 0.82, blue: 0.74, alpha: 1)
                let bn = SCNNode(geometry: body)
                bn.position = SCNVector3(p.x, y + 2, p.z)
                scene.rootNode.addChildNode(bn)

                let roof = SCNPyramid(width: w + 4, height: 2.2, length: w + 4)
                roof.firstMaterial?.diffuse.contents = UIColor(red: 0.72, green: 0.16, blue: 0.18, alpha: 1)
                let rn = SCNNode(geometry: roof)
                rn.position = SCNVector3(p.x, y + 4.2, p.z)
                scene.rootNode.addChildNode(rn)
                y += 5.2
                _ = i
            }
            let spire = SCNNode(geometry: SCNCylinder(radius: 0.25, height: 3))
            spire.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.85, green: 0.7, blue: 0.3, alpha: 1)
            spire.position = SCNVector3(p.x, y + 1.5, p.z)
            scene.rootNode.addChildNode(spire)
        }

        /// A ring of mountains and rolling green hills beyond the playable
        /// boundary — the Forza-style horizon. They sit outside the drive area
        /// so the car never reaches (or clips) them.
        private func addScenery() {
            let count = 24
            for k in 0..<count {
                let a = Float(k) / Float(count) * 2 * .pi + Float.random(in: -0.1...0.1)
                let r = World.half + 140 + Float.random(in: 0...300)
                let x = cosf(a) * r, z = sinf(a) * r
                let h = Float.random(in: 70...190)
                let cone = SCNCone(topRadius: CGFloat(Float.random(in: 3...16)),
                                   bottomRadius: CGFloat(h * 0.8), height: CGFloat(h))
                let cm = SCNMaterial()
                cm.diffuse.contents = UIColor(red: 0.36, green: 0.42, blue: 0.5, alpha: 1)
                cm.roughness.contents = 1.0
                cone.materials = [cm]
                let n = SCNNode(geometry: cone)
                n.position = SCNVector3(x, h / 2 - 3, z)
                n.castsShadow = false
                scene.rootNode.addChildNode(n)
                if h > 120 {
                    let cap = SCNCone(topRadius: 0, bottomRadius: CGFloat(h * 0.3), height: CGFloat(h * 0.32))
                    cap.firstMaterial?.diffuse.contents = UIColor.white
                    let cn = SCNNode(geometry: cap)
                    cn.position = SCNVector3(x, h - h * 0.16 - 3, z)
                    cn.castsShadow = false
                    scene.rootNode.addChildNode(cn)
                }
            }
            // Lower rounded green hills just past the edge.
            for _ in 0..<20 {
                let a = Float.random(in: 0...(2 * .pi))
                let r = World.half + Float.random(in: 25...150)
                let x = cosf(a) * r, z = sinf(a) * r
                let rad = Float.random(in: 45...95)
                let hill = SCNSphere(radius: CGFloat(rad))
                let hm = SCNMaterial()
                hm.diffuse.contents = UIColor(red: 0.30, green: 0.5, blue: 0.27, alpha: 1)
                hm.roughness.contents = 1.0
                hill.materials = [hm]
                let n = SCNNode(geometry: hill)
                n.position = SCNVector3(x, -rad + Float.random(in: 12...28), z)   // top peeks above ground
                n.castsShadow = false
                scene.rootNode.addChildNode(n)
            }
        }

        // MARK: Weather

        private struct WeatherType {
            let name: String
            let top: (CGFloat, CGFloat, CGFloat)
            let horizon: (CGFloat, CGFloat, CGFloat)
            let ground: (CGFloat, CGFloat, CGFloat)
            let fog: UIColor
            let fogStart: CGFloat
            let fogEnd: CGFloat
            let sun: CGFloat
            let sunColor: UIColor
            let ambient: CGFloat
            let rain: Bool
        }

        private let weathers: [WeatherType] = [
            WeatherType(name: "☀️ Sunny",
                        top: (0.40, 0.58, 0.86), horizon: (0.70, 0.80, 0.92), ground: (0.40, 0.42, 0.44),
                        fog: UIColor(red: 0.82, green: 0.85, blue: 0.90, alpha: 1), fogStart: 180, fogEnd: 760,
                        sun: 1150, sunColor: UIColor(red: 1, green: 0.97, blue: 0.9, alpha: 1), ambient: 360, rain: false),
            WeatherType(name: "⛅ Cloudy",
                        top: (0.62, 0.66, 0.72), horizon: (0.78, 0.80, 0.84), ground: (0.40, 0.42, 0.44),
                        fog: UIColor(red: 0.74, green: 0.76, blue: 0.80, alpha: 1), fogStart: 130, fogEnd: 560,
                        sun: 600, sunColor: UIColor(red: 0.9, green: 0.92, blue: 0.95, alpha: 1), ambient: 430, rain: false),
            WeatherType(name: "🌧️ Rain",
                        top: (0.42, 0.45, 0.52), horizon: (0.55, 0.58, 0.63), ground: (0.30, 0.32, 0.35),
                        fog: UIColor(red: 0.52, green: 0.55, blue: 0.60, alpha: 1), fogStart: 90, fogEnd: 420,
                        sun: 380, sunColor: UIColor(red: 0.8, green: 0.84, blue: 0.9, alpha: 1), ambient: 400, rain: true),
            WeatherType(name: "🌇 Sunset",
                        top: (0.30, 0.26, 0.52), horizon: (0.98, 0.62, 0.40), ground: (0.32, 0.24, 0.28),
                        fog: UIColor(red: 0.92, green: 0.66, blue: 0.5, alpha: 1), fogStart: 150, fogEnd: 700,
                        sun: 820, sunColor: UIColor(red: 1.0, green: 0.7, blue: 0.45, alpha: 1), ambient: 320, rain: false),
        ]

        private func applyWeather(_ i: Int) {
            let w = weathers[i % weathers.count]
            let sky = Self.skyTexture(top: w.top, horizon: w.horizon, ground: w.ground)
            scene.background.contents = sky
            scene.lightingEnvironment.contents = sky
            scene.lightingEnvironment.intensity = w.rain ? 0.8 : 1.4
            scene.fogColor = w.fog
            scene.fogStartDistance = w.fogStart
            scene.fogEndDistance = w.fogEnd
            sunNode.light?.intensity = w.sun
            sunNode.light?.color = w.sunColor
            ambientNode.light?.intensity = w.ambient

            rainNode?.removeFromParentNode()
            rainNode = nil
            if w.rain { addRain() }

            let name = w.name
            DispatchQueue.main.async { self.parent.model.weather = name }
        }

        private func addRain() {
            let node = SCNNode()
            node.position = SCNVector3(0, 30, 0)
            let ps = SCNParticleSystem()
            ps.birthRate = 800
            ps.particleLifeSpan = 1.5
            ps.emitterShape = SCNBox(width: 95, height: 1, length: 95, chamferRadius: 0)
            ps.birthLocation = .volume
            ps.emittingDirection = SCNVector3(0, -1, 0)
            ps.spreadingAngle = 3
            ps.particleVelocity = 34
            ps.acceleration = SCNVector3(0, -14, 0)
            ps.particleSize = 0.04
            ps.particleColor = UIColor(white: 0.85, alpha: 0.6)
            node.addParticleSystem(ps)
            carNode.addChildNode(node)   // follows the player so rain is always visible
            rainNode = node
        }

        // MARK: Cars

        private func makeCarBody(paint: UIColor, detailed: Bool) -> (SCNNode, SCNNode, SCNNode) {
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

            if detailed {
                for sx in [-0.6, 0.6] {
                    let hl = SCNBox(width: 0.4, height: 0.2, length: 0.1, chamferRadius: 0.05)
                    let hm = SCNMaterial()
                    hm.diffuse.contents = UIColor.white
                    hm.emission.contents = UIColor(red: 1, green: 0.97, blue: 0.85, alpha: 1)
                    hl.materials = [hm]
                    let n = SCNNode(geometry: hl)
                    n.position = SCNVector3(Float(sx), 0.45, 2.15)
                    car.addChildNode(n)
                    let tl = SCNBox(width: 0.4, height: 0.18, length: 0.1, chamferRadius: 0.05)
                    let tm = SCNMaterial()
                    tm.diffuse.contents = UIColor.red
                    tm.emission.contents = UIColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1)
                    tl.materials = [tm]
                    let tn = SCNNode(geometry: tl)
                    tn.position = SCNVector3(Float(sx), 0.45, -2.15)
                    car.addChildNode(tn)
                }
            }

            var pivots: [SCNNode] = []
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
                    if sz > 0 { pivots.append(pivot) }
                }
            }
            return (car, pivots.first ?? SCNNode(), pivots.count > 1 ? pivots[1] : SCNNode())
        }

        private func buildCar() {
            let (car, fl, fr) = makeCarBody(paint: UIColor(red: 0.85, green: 0.13, blue: 0.16, alpha: 1), detailed: true)
            carNode.addChildNode(car)
            carNode.position = SCNVector3(carX, carY, carZ)
            frontLeftPivot = fl
            frontRightPivot = fr
        }

        private func spawnTraffic() {
            let colors = [UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1),
                          UIColor(red: 0.9, green: 0.8, blue: 0.2, alpha: 1),
                          UIColor(white: 0.9, alpha: 1),
                          UIColor(white: 0.15, alpha: 1),
                          UIColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1)]
            let lanes: [Float] = stride(from: Float(-180), through: 180, by: 45).map { $0 }
            for i in 0..<14 {
                let (car, _, _) = makeCarBody(paint: colors[i % colors.count], detailed: false)
                let axis = i % 2
                let lane = lanes[Int.random(in: 0..<lanes.count)] + (Bool.random() ? 4 : -4)
                let pos = Float.random(in: -World.half...World.half)
                let dir: Float = Bool.random() ? 1 : -1
                let base = Float.random(in: 9...17)
                car.position = axis == 0 ? SCNVector3(pos, carY, lane) : SCNVector3(lane, carY, pos)
                car.eulerAngles.y = axis == 0 ? (dir > 0 ? .pi / 2 : -.pi / 2) : (dir > 0 ? 0 : .pi)
                scene.rootNode.addChildNode(car)
                traffic.append(Traffic(node: car, axis: axis, pos: pos, fixed: lane,
                                       dir: dir, baseSpeed: base, curSpeed: base))
            }
        }

        private func updateTraffic(dt: Float, playerX: Float, playerZ: Float) {
            let lookAhead: Float = 17
            for i in traffic.indices {
                var c = traffic[i]
                let bx: Float = c.axis == 0 ? c.pos : c.fixed
                let bz: Float = c.axis == 0 ? c.fixed : c.pos
                var target = c.baseSpeed
                let pAlong: Float = c.axis == 0 ? (playerX - bx) * c.dir : (playerZ - bz) * c.dir
                let pLat: Float = c.axis == 0 ? (playerZ - bz) : (playerX - bx)
                if abs(pLat) < 5 && pAlong > 0 && pAlong < lookAhead {
                    target = min(target, pAlong < 7 ? 0 : c.baseSpeed * 0.3)
                }
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

        // MARK: Race mode

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
            cpPositions = (0..<6).map { _ in (Float.random(in: -165...165), Float.random(in: -165...165)) }
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
            var rel = atan2f(dx, dz) - heading
            while rel > .pi { rel -= 2 * .pi }
            while rel < -.pi { rel += 2 * .pi }
            arrowRel = rel
            if sqrtf(dx * dx + dz * dz) < 7 {
                currentCP += 1
                if currentCP >= cpPositions.count { finishRace() } else { positionCheckpoint() }
            }
        }

        // MARK: Per-frame update

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            let dt = lastTime == 0 ? 0 : Float(min(0.05, time - lastTime))
            lastTime = time
            guard dt > 0 else { return }
            let m = parent.model

            if m.startRaceRequested { m.startRaceRequested = false; startRace() }

            // Cycle the weather every ~35s.
            weatherTimer += dt
            if weatherTimer > 35 {
                weatherTimer = 0
                weatherIndex = (weatherIndex + 1) % weathers.count
                applyWeather(weatherIndex)
            }

            let power: Float = 32
            speed += m.throttle * power * dt
            let drag: Float = m.throttle == 0 ? 1.1 : 0.4
            speed -= speed * drag * dt
            speed = min(40, max(-12, speed))
            if abs(speed) < 0.05 { speed = 0 }

            if abs(speed) > 0.15 {
                let steerRate: Float = 2.8
                let dir: Float = speed >= 0 ? 1 : -1
                let responsiveness = min(1.0, 0.45 + abs(speed) / 11)
                heading += m.steer * steerRate * dt * dir * responsiveness
            }
            frontLeftPivot.eulerAngles.y = m.steer * 0.5
            frontRightPivot.eulerAngles.y = m.steer * 0.5

            // Drift scoring: hard steering at speed banks points.
            let drifting = abs(speed) > 14 && abs(m.steer) > 0.55
            if drifting { driftScore += abs(speed) * abs(m.steer) * dt * 3 }

            let fx = sinf(heading), fz = cosf(heading)
            var nx = carX + fx * speed * dt
            var nz = carZ + fz * speed * dt
            let lim = World.half - 3
            nx = min(lim, max(-lim, nx)); nz = min(lim, max(-lim, nz))

            let rad: Float = 2.3
            for b in buildings {
                let ex = b.2 + rad, ez = b.3 + rad
                let dx = nx - b.0, dz = nz - b.1
                if abs(dx) < ex && abs(dz) < ez {
                    if ex - abs(dx) < ez - abs(dz) { nx = b.0 + (dx < 0 ? -ex : ex) }
                    else { nz = b.1 + (dz < 0 ? -ez : ez) }
                    speed *= 0.25
                }
            }

            distance += abs(speed) * dt
            carX = nx; carZ = nz
            carNode.position = SCNVector3(nx, carY, nz)
            carNode.eulerAngles.y = heading

            updateTraffic(dt: dt, playerX: nx, playerZ: nz)
            updateRace(dt: dt)

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
                let racing = raceActive, cpi = currentCP, rt = Double(raceTime), arrow = arrowRel
                let ds = Int(driftScore), isDrift = drifting
                let hx = nx, hz = nz, hh = heading
                DispatchQueue.main.async {
                    m.speedKmh = kmh; m.distanceM = dist; m.area = name
                    m.carX = hx; m.carZ = hz; m.heading = hh
                    m.driftScore = ds; m.drifting = isDrift
                    m.racing = racing; m.cpIndex = cpi; m.raceTime = rt; m.arrowAngle = arrow
                }
            }
        }

        // MARK: Procedural textures

        static func skyTexture() -> UIImage {
            skyTexture(top: (0.40, 0.58, 0.86), horizon: (0.70, 0.80, 0.92), ground: (0.40, 0.42, 0.44))
        }

        static func skyTexture(top: (CGFloat, CGFloat, CGFloat),
                               horizon: (CGFloat, CGFloat, CGFloat),
                               ground: (CGFloat, CGFloat, CGFloat)) -> UIImage {
            let size = CGSize(width: 8, height: 256)
            let r = UIGraphicsImageRenderer(size: size)
            return r.image { ctx in
                let cg = ctx.cgContext
                let colors = [UIColor(red: top.0, green: top.1, blue: top.2, alpha: 1).cgColor,
                              UIColor(red: horizon.0, green: horizon.1, blue: horizon.2, alpha: 1).cgColor,
                              UIColor(red: horizon.0, green: horizon.1, blue: horizon.2, alpha: 1).cgColor,
                              UIColor(red: ground.0, green: ground.1, blue: ground.2, alpha: 1).cgColor]
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
