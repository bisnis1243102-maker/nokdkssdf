import UIKit
import SceneKit

/// A background pedestrian. They walk a fixed leg of pavement and turn around
/// at the end — enough to make the streets feel occupied without pathfinding.
final class Pedestrian {
    let node: SCNNode
    var x: Float
    var z: Float
    var heading: Float
    var speed: Float
    var legRemaining: Float
    var bobPhase: Float = 0

    init(node: SCNNode, x: Float, z: Float, heading: Float, speed: Float, leg: Float) {
        self.node = node
        self.x = x
        self.z = z
        self.heading = heading
        self.speed = speed
        self.legRemaining = leg
    }
}

extension GameSceneView.Coordinator {

    // MARK: Player on foot

    func buildPlayerPed() {
        let body = makePerson(shirt: UIColor(red: 0.16, green: 0.20, blue: 0.30, alpha: 1),
                              trousers: UIColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1))
        for child in body.childNodes {
            child.removeFromParentNode()
            pedNode.addChildNode(child)
        }
        pedNode.isHidden = true
        scene.rootNode.addChildNode(pedNode)
    }

    /// A simple stylised figure: capsule torso, sphere head, two legs that the
    /// walk cycle swings.
    func makePerson(shirt: UIColor, trousers: UIColor) -> SCNNode {
        let root = SCNNode()

        let torso = SCNCapsule(capRadius: 0.24, height: 1.0)
        let tm = torso.firstMaterial!
        tm.lightingModel = .physicallyBased
        tm.diffuse.contents = shirt
        tm.roughness.contents = 0.85
        let torsoNode = SCNNode(geometry: torso)
        torsoNode.position = SCNVector3(0, 1.18, 0)
        root.addChildNode(torsoNode)

        let head = SCNSphere(radius: 0.19)
        head.segmentCount = 12
        let hm = head.firstMaterial!
        hm.lightingModel = .physicallyBased
        hm.diffuse.contents = UIColor(red: 0.60, green: 0.45, blue: 0.36, alpha: 1)
        hm.roughness.contents = 0.7
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 1.86, 0)
        root.addChildNode(headNode)

        for side in [Float(-0.11), Float(0.11)] {
            let leg = SCNCapsule(capRadius: 0.095, height: 0.78)
            let lm = leg.firstMaterial!
            lm.lightingModel = .physicallyBased
            lm.diffuse.contents = trousers
            lm.roughness.contents = 0.9
            let pivot = SCNNode()
            pivot.position = SCNVector3(side, 0.78, 0)
            let legNode = SCNNode(geometry: leg)
            legNode.position = SCNVector3(0, -0.34, 0)
            pivot.addChildNode(legNode)
            pivot.name = side < 0 ? "legL" : "legR"
            root.addChildNode(pivot)
        }

        return root
    }

    /// Swings the legs in time with movement.
    private func animateWalk(_ node: SCNNode, phase: Float, moving: Bool) {
        let swing = moving ? sinf(phase) * 0.55 : 0
        node.childNode(withName: "legL", recursively: false)?.eulerAngles.x = swing
        node.childNode(withName: "legR", recursively: false)?.eulerAngles.x = -swing
    }

    func updateOnFoot(dt: Float) {
        let m = model
        let inputLen = hypotf(m.walkX, m.walkZ)
        let moving = inputLen > 0.08

        if moving {
            // The stick is in camera space: forward is where the camera looks.
            let camYaw = footHeading
            let wantHeading = atan2f(m.walkX, m.walkZ) + camYaw
            var delta = wantHeading - footHeading
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            footHeading += max(-6 * dt, min(6 * dt, delta))

            let speed: Float = min(1, inputLen) * 5.4
            var nx = footX + sinf(footHeading) * speed * dt
            var nz = footZ + cosf(footHeading) * speed * dt

            // On foot you get a tighter collision radius, so alleys are passable.
            for b in buildings {
                let ex = b.2 + 0.5, ez = b.3 + 0.5
                let dx = nx - b.0, dz = nz - b.1
                if abs(dx) < ex && abs(dz) < ez {
                    if ex - abs(dx) < ez - abs(dz) { nx = b.0 + (dx < 0 ? -ex : ex) }
                    else { nz = b.1 + (dz < 0 ? -ez : ez) }
                }
            }
            footX = CityWorld.clamp(nx)
            footZ = CityWorld.clamp(nz)
            walkPhase += dt * 9
        }

        pedNode.position = SCNVector3(footX, 0, footZ)
        pedNode.eulerAngles.y = footHeading
        animateWalk(pedNode, phase: walkPhase, moving: moving)

        nearCar = hypotf(carX - footX, carZ - footZ) < 4.2
    }

    // MARK: Getting in and out

    func toggleVehicle() {
        if mode == .driving {
            // Step out beside the driver's door.
            let side = carHeading + .pi / 2
            footX = CityWorld.clamp(carX + sinf(side) * 2.2)
            footZ = CityWorld.clamp(carZ + cosf(side) * 2.2)
            footHeading = carHeading
            walkPhase = 0
            pedNode.isHidden = false
            pedNode.position = SCNVector3(footX, 0, footZ)
            carSpeed = 0
            model.throttle = 0
            model.steer = 0
            mode = .onFoot
        } else {
            guard nearCar else { return }
            pedNode.isHidden = true
            model.walkX = 0
            model.walkZ = 0
            mode = .driving
        }
    }

    // MARK: Pedestrians

    func spawnPedestrians() {
        let shirts: [UIColor] = [
            UIColor(red: 0.65, green: 0.25, blue: 0.30, alpha: 1),
            UIColor(red: 0.20, green: 0.42, blue: 0.45, alpha: 1),
            UIColor(red: 0.50, green: 0.48, blue: 0.22, alpha: 1),
            UIColor(red: 0.30, green: 0.30, blue: 0.38, alpha: 1),
        ]

        for i in 0..<34 {
            let avenue = CityWorld.avenues[(i * 5) % CityWorld.avenues.count]
            let along = (rnd(i, 11, 71) - 0.5) * CityWorld.half * 2
            let vertical = i % 2 == 0
            // Walk the pavement, just outside the road edge.
            let offset = CityWorld.roadHalfWidth + 1.6
            let x = vertical ? avenue + offset : along
            let z = vertical ? along : avenue + offset

            let node = makePerson(shirt: shirts[i % shirts.count],
                                  trousers: UIColor(white: 0.14, alpha: 1))
            node.position = SCNVector3(x, 0, z)
            scene.rootNode.addChildNode(node)

            let heading: Float = vertical ? (i % 4 < 2 ? 0 : .pi) : (i % 4 < 2 ? .pi / 2 : -.pi / 2)
            node.eulerAngles.y = heading

            pedestrians.append(Pedestrian(node: node, x: x, z: z, heading: heading,
                                          speed: 1.1 + rnd(i, 13, 73) * 0.8,
                                          leg: 20 + rnd(i, 17, 79) * 40))
        }
    }

    func updatePedestrians(dt: Float) {
        let px = mode == .driving ? carX : footX
        let pz = mode == .driving ? carZ : footZ

        for p in pedestrians {
            // Only simulate what the player could plausibly see.
            let far = hypotf(p.x - px, p.z - pz) > 140
            p.node.isHidden = far
            if far { continue }

            p.legRemaining -= p.speed * dt
            if p.legRemaining <= 0 {
                p.heading += .pi
                p.legRemaining = 24 + Float.random(in: 0...36)
            }

            // Step out of the way of a car bearing down on them.
            let dx = p.x - px, dz = p.z - pz
            let close = hypotf(dx, dz)
            var speed = p.speed
            if mode == .driving && close < 7 && abs(carSpeed) > 6 {
                speed = p.speed * 3.2
                p.heading = atan2f(dx, dz)
            }

            p.x = CityWorld.clamp(p.x + sinf(p.heading) * speed * dt)
            p.z = CityWorld.clamp(p.z + cosf(p.heading) * speed * dt)
            p.bobPhase += dt * 7

            p.node.position = SCNVector3(p.x, 0, p.z)
            p.node.eulerAngles.y = p.heading
            animateWalk(p.node, phase: p.bobPhase, moving: true)
        }
    }
}
