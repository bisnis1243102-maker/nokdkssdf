import SwiftUI
import SceneKit

struct CityScene: UIViewRepresentable {
    @ObservedObject var model: DriveModel

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = context.coordinator.buildWorld()
        view.backgroundColor = UIColor(red: 0.55, green: 0.74, blue: 0.92, alpha: 1)
        view.antialiasingMode = .multisampling2X
        view.delegate = context.coordinator
        view.rendersContinuously = true
        view.isPlaying = true
        view.pointOfView = context.coordinator.cameraNode
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.parent = self
    }

    // MARK: - Coordinator (driving sim + camera)

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        var parent: CityScene
        let cameraNode = SCNNode()
        private let scene = SCNScene()
        private let carNode = SCNNode()

        // Car state
        private var carX: Float = 0
        private var carZ: Float = 170     // start near the south edge
        private var heading: Float = .pi  // facing toward the city centre
        private var speed: Float = 0
        private let carY: Float = 0.55

        // Building axis-aligned boxes for collision: (cx, cz, halfW, halfD)
        private var buildings: [(Float, Float, Float, Float)] = []

        private var lastTime: TimeInterval = 0
        private var hudAccum: Float = 0
        private var distance: Float = 0

        init(_ parent: CityScene) { self.parent = parent }

        // MARK: World construction

        func buildWorld() -> SCNScene {
            scene.background.contents = UIColor(red: 0.55, green: 0.74, blue: 0.92, alpha: 1)
            scene.physicsWorld.gravity = SCNVector3(0, -9.8, 0)

            // Ground (asphalt slab)
            let groundSize = CGFloat(World.half) * 2 + 40
            let ground = SCNBox(width: groundSize, height: 2, length: groundSize, chamferRadius: 0)
            ground.firstMaterial?.diffuse.contents = UIColor(red: 0.22, green: 0.23, blue: 0.25, alpha: 1)
            let groundNode = SCNNode(geometry: ground)
            groundNode.position = SCNVector3(0, -1, 0)
            scene.rootNode.addChildNode(groundNode)

            addRoadGrid()
            buildCity()
            addLandmarks()

            // Lighting
            let ambient = SCNNode()
            ambient.light = SCNLight(); ambient.light?.type = .ambient
            ambient.light?.intensity = 550
            scene.rootNode.addChildNode(ambient)

            let sun = SCNNode()
            sun.light = SCNLight(); sun.light?.type = .directional
            sun.light?.intensity = 900
            sun.light?.castsShadow = true
            sun.eulerAngles = SCNVector3(-Float.pi / 3.2, Float.pi / 4, 0)
            scene.rootNode.addChildNode(sun)

            buildCar()
            scene.rootNode.addChildNode(carNode)

            // Camera
            let cam = SCNCamera()
            cam.fieldOfView = 62
            cam.zFar = 1200
            cameraNode.camera = cam
            cameraNode.position = SCNVector3(carX, 9, carZ + 16)
            scene.rootNode.addChildNode(cameraNode)

            return scene
        }

        private func addRoadGrid() {
            // Lighter strips suggesting avenues between blocks.
            let step: Float = 45
            var x = -World.half
            while x <= World.half {
                let road = SCNBox(width: 14, height: 0.1, length: CGFloat(World.half) * 2, chamferRadius: 0)
                road.firstMaterial?.diffuse.contents = UIColor(red: 0.28, green: 0.29, blue: 0.31, alpha: 1)
                let n = SCNNode(geometry: road)
                n.position = SCNVector3(x, 0.06, 0)
                scene.rootNode.addChildNode(n)

                let road2 = SCNBox(width: CGFloat(World.half) * 2, height: 0.1, length: 14, chamferRadius: 0)
                road2.firstMaterial?.diffuse.contents = UIColor(red: 0.28, green: 0.29, blue: 0.31, alpha: 1)
                let n2 = SCNNode(geometry: road2)
                n2.position = SCNVector3(0, 0.06, x)
                scene.rootNode.addChildNode(n2)
                x += step
            }
        }

        private func buildCity() {
            let positions = stride(from: Float(-180), through: 180, by: 45).map { $0 }
            for px in positions {
                for pz in positions {
                    // Leave the very centre of downtown open as a plaza.
                    if abs(px) < 23 && abs(pz) < 23 { continue }
                    // Skip a few cells for variety (parks / empty lots).
                    if Int(abs(px) + abs(pz)) % 7 == 0 { addPark(px, pz); continue }

                    let d = World.district(x: px, z: pz)
                    let footprint: CGFloat = 28
                    let h = d.tall
                        ? CGFloat.random(in: 35...95)
                        : CGFloat.random(in: 10...34)
                    let b = SCNBox(width: footprint, height: h, length: footprint, chamferRadius: 1)
                    let mat = SCNMaterial()
                    let jitter = CGFloat.random(in: -0.06...0.06)
                    mat.diffuse.contents = UIColor(red: d.r + jitter, green: d.g + jitter,
                                                   blue: d.b + jitter, alpha: 1)
                    b.materials = [mat]
                    let node = SCNNode(geometry: b)
                    node.position = SCNVector3(px, Float(h) / 2, pz)
                    scene.rootNode.addChildNode(node)

                    buildings.append((px, pz, Float(footprint / 2), Float(footprint / 2)))
                }
            }
        }

        private func addPark(_ x: Float, _ z: Float) {
            let park = SCNBox(width: 30, height: 0.2, length: 30, chamferRadius: 0)
            park.firstMaterial?.diffuse.contents = UIColor(red: 0.30, green: 0.55, blue: 0.28, alpha: 1)
            let n = SCNNode(geometry: park)
            n.position = SCNVector3(x, 0.12, z)
            scene.rootNode.addChildNode(n)
            // A couple of trees.
            for _ in 0..<3 {
                let tx = x + Float.random(in: -10...10), tz = z + Float.random(in: -10...10)
                let trunk = SCNNode(geometry: SCNCylinder(radius: 0.4, height: 2))
                trunk.geometry?.firstMaterial?.diffuse.contents = UIColor.brown
                trunk.position = SCNVector3(tx, 1, tz)
                scene.rootNode.addChildNode(trunk)
                let crown = SCNNode(geometry: SCNSphere(radius: 1.6))
                crown.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.2, green: 0.5, blue: 0.2, alpha: 1)
                crown.position = SCNVector3(tx, 2.8, tz)
                scene.rootNode.addChildNode(crown)
            }
        }

        private func addLandmarks() {
            // Water along the northern docks edge.
            let water = SCNBox(width: CGFloat(World.half) * 2, height: 0.4, length: 60, chamferRadius: 0)
            water.firstMaterial?.diffuse.contents = UIColor(red: 0.20, green: 0.45, blue: 0.75, alpha: 1)
            let wn = SCNNode(geometry: water)
            wn.position = SCNVector3(0, 0.05, -World.half - 28)
            scene.rootNode.addChildNode(wn)

            // Sand strip along the southern beach edge.
            let sand = SCNBox(width: CGFloat(World.half) * 2, height: 0.3, length: 50, chamferRadius: 0)
            sand.firstMaterial?.diffuse.contents = UIColor(red: 0.92, green: 0.84, blue: 0.6, alpha: 1)
            let sn = SCNNode(geometry: sand)
            sn.position = SCNVector3(0, 0.08, World.half + 22)
            scene.rootNode.addChildNode(sn)
        }

        private func buildCar() {
            carNode.position = SCNVector3(carX, carY, carZ)

            let body = SCNBox(width: 2.0, height: 0.7, length: 4.2, chamferRadius: 0.3)
            body.firstMaterial?.diffuse.contents = UIColor(red: 0.85, green: 0.15, blue: 0.18, alpha: 1)
            let bodyNode = SCNNode(geometry: body)
            bodyNode.position = SCNVector3(0, 0.35, 0)
            carNode.addChildNode(bodyNode)

            let cabin = SCNBox(width: 1.7, height: 0.6, length: 1.9, chamferRadius: 0.25)
            cabin.firstMaterial?.diffuse.contents = UIColor(red: 0.15, green: 0.18, blue: 0.22, alpha: 1)
            let cabinNode = SCNNode(geometry: cabin)
            cabinNode.position = SCNVector3(0, 0.85, -0.2)
            carNode.addChildNode(cabinNode)

            for sx in [-0.95, 0.95] {
                for sz in [-1.4, 1.4] {
                    let wheel = SCNCylinder(radius: 0.42, height: 0.3)
                    wheel.firstMaterial?.diffuse.contents = UIColor(white: 0.08, alpha: 1)
                    let wn = SCNNode(geometry: wheel)
                    wn.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
                    wn.position = SCNVector3(Float(sx), 0.0, Float(sz))
                    carNode.addChildNode(wn)
                }
            }
        }

        // MARK: Per-frame driving update

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            let dt = lastTime == 0 ? 0 : Float(min(0.05, time - lastTime))
            lastTime = time
            guard dt > 0 else { return }
            let m = parent.model

            // Acceleration + drag.
            let power: Float = 30
            speed += m.throttle * power * dt
            let drag: Float = m.throttle == 0 ? 1.1 : 0.4
            speed -= speed * drag * dt
            speed = min(36, max(-11, speed))
            if abs(speed) < 0.05 { speed = 0 }

            // Steering scales with speed and reverses when backing up.
            if abs(speed) > 0.3 {
                let steerRate: Float = 1.7
                let dir: Float = speed >= 0 ? 1 : -1
                heading += m.steer * steerRate * dt * dir * min(1, abs(speed) / 9)
            }

            let fx = sinf(heading), fz = cosf(heading)
            var nx = carX + fx * speed * dt
            var nz = carZ + fz * speed * dt

            // Keep inside the map.
            let lim = World.half - 3
            nx = min(lim, max(-lim, nx))
            nz = min(lim, max(-lim, nz))

            // Resolve building collisions.
            let rad: Float = 2.3
            for b in buildings {
                let ex = b.2 + rad, ez = b.3 + rad
                let dx = nx - b.0, dz = nz - b.1
                if abs(dx) < ex && abs(dz) < ez {
                    let px = ex - abs(dx), pz = ez - abs(dz)
                    if px < pz {
                        nx = b.0 + (dx < 0 ? -ex : ex)
                    } else {
                        nz = b.1 + (dz < 0 ? -ez : ez)
                    }
                    speed *= 0.25
                }
            }

            distance += abs(speed) * dt
            carX = nx; carZ = nz
            carNode.position = SCNVector3(nx, carY, nz)
            carNode.eulerAngles.y = heading

            // Chase camera (smoothed).
            let desired = SCNVector3(nx - fx * 14, 8.5, nz - fz * 14)
            let lerp = min(1, dt * 4.5)
            cameraNode.position = SCNVector3(
                cameraNode.position.x + (desired.x - cameraNode.position.x) * lerp,
                cameraNode.position.y + (desired.y - cameraNode.position.y) * lerp,
                cameraNode.position.z + (desired.z - cameraNode.position.z) * lerp)
            cameraNode.look(at: SCNVector3(nx + fx * 6, 1.6, nz + fz * 6),
                            up: SCNVector3(0, 1, 0),
                            localFront: SCNVector3(0, 0, -1))

            // Push HUD ~6x/sec.
            hudAccum += dt
            if hudAccum >= 0.16 {
                hudAccum = 0
                let kmh = Int(abs(speed) * 7.5)
                let dist = Int(distance)
                let name = World.name(x: nx, z: nz)
                let hx = nx, hz = nz, hh = heading
                DispatchQueue.main.async {
                    m.speedKmh = kmh
                    m.distanceM = dist
                    m.district = name
                    m.carX = hx; m.carZ = hz; m.heading = hh
                }
            }
        }
    }
}
