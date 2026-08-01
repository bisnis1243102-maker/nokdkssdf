import UIKit
import SceneKit

/// A car the player isn't driving: traffic, police, or a mission target.
final class AICar {
    enum Role { case traffic, police, target }

    let node: SCNNode
    var x: Float
    var z: Float
    var heading: Float
    var speed: Float
    var role: Role
    /// Traffic drives along one axis of the grid until it reaches a junction.
    var vertical: Bool
    var direction: Float          // +1 or -1 along that axis
    /// Set while a car is wrecked/stopped, so it can be parked and entered.
    var parked: Bool = false
    var sirenPhase: Float = 0
    var sirenLights: [SCNNode] = []

    init(node: SCNNode, x: Float, z: Float, heading: Float,
         speed: Float, role: Role, vertical: Bool, direction: Float) {
        self.node = node
        self.x = x
        self.z = z
        self.heading = heading
        self.speed = speed
        self.role = role
        self.vertical = vertical
        self.direction = direction
    }
}

extension GameSceneView.Coordinator {

    // MARK: Car geometry
    //
    // One body builder shared by the player, traffic and police, so a single
    // material pass covers every car in the city.

    /// Returns the car root plus its four wheel nodes and the two steerable
    /// front pivots.
    func makeCar(paint: UIColor, police: Bool, seed: Int, beams: Bool = false)
        -> (root: SCNNode, wheels: [SCNNode], steer: [SCNNode],
            lights: [SCNNode], brakes: [SCNMaterial]) {

        let root = SCNNode()

        // Contact shadow: a soft dark ellipse that sits the car in the world
        // even when the sun is low and the cast shadow stretches away.
        let blob = SCNPlane(width: 2.6, height: 5.2)
        let blobMat = blob.firstMaterial!
        blobMat.lightingModel = .constant
        blobMat.diffuse.contents = TextureFactory.contactShadow(size: 64)
        blobMat.blendMode = .multiply
        blobMat.writesToDepthBuffer = false
        blobMat.readsFromDepthBuffer = true
        let blobNode = SCNNode(geometry: blob)
        blobNode.eulerAngles.x = -.pi / 2
        blobNode.position = SCNVector3(0, -0.36, 0)
        blobNode.castsShadow = false
        blobNode.renderingOrder = -5
        root.addChildNode(blobNode)

        // Lower body.
        let body = SCNBox(width: 2.0, height: 0.62, length: 4.4, chamferRadius: 0.28)
        let bm = body.firstMaterial!
        bm.lightingModel = .physicallyBased
        bm.diffuse.contents = paint
        bm.metalness.contents = 0.35
        bm.roughness.contents = 0.22
        ShaderModifiers.applyCarPaint(to: bm, flake: police ? 0.2 : 0.8)
        let bodyNode = SCNNode(geometry: body)
        bodyNode.position = SCNVector3(0, 0.52, 0)
        root.addChildNode(bodyNode)

        // Cabin, inset and shorter — reads as a roofline rather than a slab.
        let cabin = SCNBox(width: 1.78, height: 0.58, length: 2.1, chamferRadius: 0.30)
        let cm = cabin.firstMaterial!
        cm.lightingModel = .physicallyBased
        cm.diffuse.contents = paint
        cm.metalness.contents = 0.35
        cm.roughness.contents = 0.22
        ShaderModifiers.applyCarPaint(to: cm, flake: police ? 0.2 : 0.8)
        let cabinNode = SCNNode(geometry: cabin)
        cabinNode.position = SCNVector3(0, 1.06, -0.18)
        root.addChildNode(cabinNode)

        // Glasshouse.
        let glass = SCNBox(width: 1.80, height: 0.46, length: 1.9, chamferRadius: 0.22)
        let gm = glass.firstMaterial!
        gm.diffuse.contents = UIColor(red: 0.10, green: 0.13, blue: 0.18, alpha: 1)
        ShaderModifiers.applyGlass(to: gm)
        let glassNode = SCNNode(geometry: glass)
        glassNode.position = SCNVector3(0, 1.12, -0.18)
        root.addChildNode(glassNode)

        // Wheels on steerable pivots at the front.
        var wheels: [SCNNode] = []
        var steer: [SCNNode] = []
        let wheelGeo = SCNCylinder(radius: 0.42, height: 0.30)
        let wm = wheelGeo.firstMaterial!
        wm.lightingModel = .physicallyBased
        wm.diffuse.contents = UIColor(white: 0.045, alpha: 1)
        wm.roughness.contents = 0.85
        wm.metalness.contents = 0.0

        for (i, offset) in [SIMD3<Float>(-0.98, 0.42, 1.42),
                            SIMD3<Float>(0.98, 0.42, 1.42),
                            SIMD3<Float>(-0.98, 0.42, -1.42),
                            SIMD3<Float>(0.98, 0.42, -1.42)].enumerated() {
            let pivot = SCNNode()
            pivot.position = SCNVector3(offset.x, offset.y, offset.z)
            let wheel = SCNNode(geometry: wheelGeo)
            wheel.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
            pivot.addChildNode(wheel)
            root.addChildNode(pivot)
            wheels.append(wheel)
            if i < 2 { steer.append(pivot) }

            // Hub, so wheels aren't featureless black discs.
            let hub = SCNCylinder(radius: 0.20, height: 0.32)
            let hm = hub.firstMaterial!
            hm.lightingModel = .physicallyBased
            hm.diffuse.contents = UIColor(white: 0.62, alpha: 1)
            hm.metalness.contents = 0.95
            hm.roughness.contents = 0.18
            let hubNode = SCNNode(geometry: hub)
            hubNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
            pivot.addChildNode(hubNode)
        }

        // Headlights + tail lights.
        var lightNodes: [SCNNode] = []
        var brakes: [SCNMaterial] = []
        for side in [Float(-0.62), Float(0.62)] {
            let lens = SCNBox(width: 0.42, height: 0.18, length: 0.10, chamferRadius: 0.04)
            let lm = lens.firstMaterial!
            lm.lightingModel = .constant
            lm.diffuse.contents = UIColor.black
            lm.emission.contents = UIColor(red: 1.0, green: 0.96, blue: 0.86, alpha: 1)
            lm.emission.intensity = 1.6
            let ln = SCNNode(geometry: lens)
            ln.position = SCNVector3(side, 0.62, 2.22)
            root.addChildNode(ln)

            // A real spot light per side, streamed on after dark.
            let beam = SCNLight()
            beam.type = .spot
            beam.color = UIColor(red: 1.0, green: 0.95, blue: 0.85, alpha: 1)
            beam.intensity = 0
            beam.spotInnerAngle = 22
            beam.spotOuterAngle = 52
            beam.attenuationEndDistance = 55
            beam.castsShadow = false
            let bn = SCNNode()
            bn.light = beam
            bn.position = SCNVector3(side, 0.66, 2.3)
            bn.eulerAngles = SCNVector3(-0.06, Float.pi, 0)
            root.addChildNode(bn)
            lightNodes.append(bn)

            let tail = SCNBox(width: 0.40, height: 0.16, length: 0.08, chamferRadius: 0.03)
            let tm = tail.firstMaterial!
            tm.lightingModel = .constant
            tm.diffuse.contents = UIColor.black
            tm.emission.contents = UIColor(red: 1.0, green: 0.12, blue: 0.10, alpha: 1)
            tm.emission.intensity = 1.1
            let tn = SCNNode(geometry: tail)
            tn.position = SCNVector3(side, 0.62, -2.22)
            root.addChildNode(tn)
            brakes.append(tm)

            if beams {
                // A translucent cone standing in for the light shaft the beam
                // carves out of the night air. Additive, depth-read only, so it
                // never occludes what it is lighting.
                let cone = SCNCone(topRadius: 0.18, bottomRadius: 2.6, height: 13)
                let cmat = cone.firstMaterial!
                cmat.lightingModel = .constant
                cmat.diffuse.contents = UIColor(red: 1.0, green: 0.95, blue: 0.82, alpha: 1)
                cmat.blendMode = .add
                cmat.writesToDepthBuffer = false
                cmat.readsFromDepthBuffer = true
                cmat.isDoubleSided = true
                let cn = SCNNode(geometry: cone)
                // Lay the cone down the car's forward axis.
                cn.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
                cn.position = SCNVector3(side, 0.62, 8.6)
                cn.castsShadow = false
                cn.opacity = 0
                cn.renderingOrder = 20
                root.addChildNode(cn)
                headlightCones.append(cn)
            }
        }

        if police {
            // Light bar: two emissive pods the update loop strobes.
            for (i, side) in [Float(-0.42), Float(0.42)].enumerated() {
                let pod = SCNBox(width: 0.52, height: 0.16, length: 0.34, chamferRadius: 0.06)
                let pm = pod.firstMaterial!
                pm.lightingModel = .constant
                pm.diffuse.contents = UIColor.black
                pm.emission.contents = i == 0
                    ? UIColor(red: 0.2, green: 0.35, blue: 1.0, alpha: 1)
                    : UIColor(red: 1.0, green: 0.15, blue: 0.2, alpha: 1)
                let pn = SCNNode(geometry: pod)
                pn.position = SCNVector3(side, 1.44, -0.2)
                root.addChildNode(pn)
                lightNodes.append(pn)
            }
        }

        return (root, wheels, steer, lightNodes, brakes)
    }

    // MARK: Player car

    func buildPlayerCar() {
        let built = makeCar(paint: UIColor(red: 0.58, green: 0.10, blue: 0.14, alpha: 1),
                            police: false, seed: 1, beams: true)
        // Re-parent the built geometry under the persistent player node.
        for child in built.root.childNodes {
            child.removeFromParentNode()
            carNode.addChildNode(child)
        }
        wheelNodes = built.wheels
        steerPivots = built.steer
        headlightNodes = built.lights
        brakeMaterials = built.brakes
        carNode.position = SCNVector3(0, 0.42, 0)
        scene.rootNode.addChildNode(carNode)

        // Exhaust haze, thicker when accelerating hard.
        let exhaust = SCNParticleSystem()
        exhaust.particleColor = UIColor(white: 0.75, alpha: 0.18)
        exhaust.particleSize = 0.16
        exhaust.particleSizeVariation = 0.10
        exhaust.birthRate = 0
        exhaust.particleLifeSpan = 0.9
        exhaust.particleVelocity = 1.4
        exhaust.spreadingAngle = 25
        exhaust.blendMode = .alpha
        exhaust.isLightingEnabled = false
        let en = SCNNode()
        en.position = SCNVector3(0, 0.32, -2.3)
        en.addParticleSystem(exhaust)
        carNode.addChildNode(en)
        exhaustNode = en
    }

    // MARK: Driving

    func updateDriving(dt: Float) {
        let m = model

        // Arcade longitudinal model: power, drag, and a much stronger brake.
        let power: Float = 26
        let maxSpeed: Float = 46
        if m.throttle > 0 {
            carSpeed += m.throttle * power * dt
        } else if m.throttle < 0 {
            // Brake hard while moving forward, otherwise reverse.
            carSpeed += m.throttle * (carSpeed > 0 ? power * 1.7 : power * 0.6) * dt
        }
        let drag: Float = m.throttle == 0 ? 1.35 : 0.42
        carSpeed -= carSpeed * drag * dt
        if m.handbrake {
            carSpeed -= carSpeed * 3.4 * dt
        }
        carSpeed = min(maxSpeed, max(-14, carSpeed))
        if abs(carSpeed) < 0.05 { carSpeed = 0 }

        // Steering falls off at speed so the car doesn't spin on the spot.
        if abs(carSpeed) > 0.2 {
            let dir: Float = carSpeed >= 0 ? 1 : -1
            let grip: Float = m.handbrake ? 1.55 : 1.0
            let responsiveness = min(1.0, 0.40 + abs(carSpeed) / 26)
            carHeading += m.steer * 1.5 * dt * dir * responsiveness * grip
        }
        for p in steerPivots {
            p.eulerAngles.y = m.steer * 0.42
        }
        // Spin the wheels at road speed.
        for w in wheelNodes {
            w.eulerAngles.x += carSpeed * dt * 2.2
        }

        let fx = sinf(carHeading), fz = cosf(carHeading)
        var nx = carX + fx * carSpeed * dt
        var nz = carZ + fz * carSpeed * dt

        let lim = CityWorld.half - 3
        nx = min(lim, max(-lim, nx))
        nz = min(lim, max(-lim, nz))

        // Building collision: push out along the shallower axis of overlap.
        let radius: Float = 2.2
        var hitSomething = false
        for b in buildings {
            let ex = b.2 + radius, ez = b.3 + radius
            let dx = nx - b.0, dz = nz - b.1
            if abs(dx) < ex && abs(dz) < ez {
                if ex - abs(dx) < ez - abs(dz) {
                    nx = b.0 + (dx < 0 ? -ex : ex)
                } else {
                    nz = b.1 + (dz < 0 ? -ez : ez)
                }
                hitSomething = true
            }
        }
        if hitSomething {
            if abs(carSpeed) > 22 { spawnSparks(at: SCNVector3(nx, 0.6, nz)) }
            carSpeed *= 0.32
        }

        carX = nx
        carZ = nz
        carNode.position = SCNVector3(carX, 0.42, carZ)
        carNode.eulerAngles.y = carHeading

        // Body roll and squat, entirely cosmetic but sells the weight.
        let roll = -m.steer * min(1, abs(carSpeed) / 30) * 0.09
        let pitch = -m.throttle * 0.035
        carNode.eulerAngles.z = roll
        carNode.eulerAngles.x = pitch

        if let ex = exhaustNode?.particleSystems?.first {
            ex.birthRate = m.throttle > 0.2 ? 90 : 12
        }

        // Tail lights flare when braking — the clearest read the player has
        // that the brake actually bit.
        let braking = m.throttle < -0.1 || m.handbrake
        for bm in brakeMaterials {
            bm.emission.intensity = braking ? 4.5 : 1.0
        }
    }

    func spawnSparks(at position: SCNVector3) {
        let sparks = SCNParticleSystem()
        sparks.particleColor = UIColor(red: 1.0, green: 0.75, blue: 0.30, alpha: 1)
        sparks.particleSize = 0.05
        sparks.birthRate = 900
        sparks.emissionDuration = 0.12
        sparks.loops = false
        sparks.particleLifeSpan = 0.45
        sparks.particleVelocity = 9
        sparks.particleVelocityVariation = 5
        sparks.spreadingAngle = 90
        sparks.blendMode = .additive
        sparks.isAffectedByGravity = true
        sparks.isLightingEnabled = false

        let n = SCNNode()
        n.position = position
        n.addParticleSystem(sparks)
        scene.rootNode.addChildNode(n)
        n.runAction(.sequence([.wait(duration: 1.2), .removeFromParentNode()]))
    }

    // MARK: Traffic

    func spawnTraffic() {
        let palette: [UIColor] = [
            UIColor(red: 0.82, green: 0.82, blue: 0.85, alpha: 1),
            UIColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1),
            UIColor(red: 0.20, green: 0.36, blue: 0.62, alpha: 1),
            UIColor(red: 0.62, green: 0.58, blue: 0.20, alpha: 1),
            UIColor(red: 0.36, green: 0.16, blue: 0.20, alpha: 1),
        ]

        for i in 0..<26 {
            let vertical = i % 2 == 0
            let lane = CityWorld.avenues[(i * 3) % CityWorld.avenues.count]
            let along = (rnd(i, 3, 61) - 0.5) * CityWorld.half * 2
            let dir: Float = i % 4 < 2 ? 1 : -1
            // Keep to the correct side of the centre line.
            let offset = CityWorld.roadHalfWidth * 0.45 * dir

            let car = makeCar(paint: palette[i % palette.count], police: false, seed: i)
            let x = vertical ? lane + offset : along
            let z = vertical ? along : lane - offset
            car.root.position = SCNVector3(x, 0.42, z)
            scene.rootNode.addChildNode(car.root)

            let heading: Float = vertical ? (dir > 0 ? 0 : .pi) : (dir > 0 ? .pi / 2 : -.pi / 2)
            car.root.eulerAngles.y = heading

            let ai = AICar(node: car.root, x: x, z: z, heading: heading,
                           speed: 9 + rnd(i, 7, 67) * 8,
                           role: .traffic, vertical: vertical, direction: dir)
            traffic.append(ai)
        }
    }

    func updateTraffic(dt: Float) {
        let px = mode == .driving ? carX : footX
        let pz = mode == .driving ? carZ : footZ

        for car in traffic {
            if car.parked {
                continue
            }
            car.x += sinf(car.heading) * car.speed * dt
            car.z += cosf(car.heading) * car.speed * dt

            // Wrap around the map rather than despawning, so traffic density
            // stays constant wherever the player drives.
            if abs(car.x) > CityWorld.half { car.x = -car.x * 0.96 }
            if abs(car.z) > CityWorld.half { car.z = -car.z * 0.96 }

            car.node.position = SCNVector3(car.x, 0.42, car.z)
            car.node.eulerAngles.y = car.heading

            // Slow down when the player's car is right in front.
            let dx = px - car.x, dz = pz - car.z
            if dx * dx + dz * dz < 90 {
                car.speed = max(3, car.speed - 12 * dt)
            } else {
                car.speed = min(17, car.speed + 4 * dt)
            }
        }
    }

    // MARK: Police

    func updateHeat(dt: Float) {
        // Ramming and mission objectives raise heat; distance and time drop it.
        if heat > 0 {
            var nearest: Float = .greatestFiniteMagnitude
            let px = mode == .driving ? carX : footX
            let pz = mode == .driving ? carZ : footZ
            for c in cops {
                let d = hypotf(c.x - px, c.z - pz)
                nearest = min(nearest, d)
            }
            // Out of sight for long enough and the heat comes off a star at a time.
            if nearest > 65 {
                heatCooldown += dt
                if heatCooldown > 7 {
                    heatCooldown = 0
                    heat = max(0, heat - 1)
                    if heat == 0 { clearCops() }
                }
            } else {
                heatCooldown = max(0, heatCooldown - dt * 0.5)
            }

            // Keep a cop count proportional to the heat level.
            copSpawnTimer += dt
            if copSpawnTimer > 2.4 && cops.count < heat * 2 {
                copSpawnTimer = 0
                spawnCop()
            }
        } else if !cops.isEmpty {
            clearCops()
        }
    }

    func raiseHeat(to level: Int) {
        heat = max(heat, min(3, level))
        heatCooldown = 0
    }

    private func spawnCop() {
        let px = mode == .driving ? carX : footX
        let pz = mode == .driving ? carZ : footZ
        // Drop them in on a road a little way off, never on top of the player.
        let angle = Float.random(in: 0..<(2 * .pi))
        let dist: Float = 70
        let raw = (CityWorld.clamp(px + sinf(angle) * dist),
                   CityWorld.clamp(pz + cosf(angle) * dist))
        let snapped = CityWorld.snapToRoad(x: raw.0, z: raw.1)

        let built = makeCar(paint: UIColor(white: 0.92, alpha: 1), police: true,
                            seed: cops.count, beams: true)
        built.root.position = SCNVector3(snapped.0, 0.42, snapped.1)
        scene.rootNode.addChildNode(built.root)

        let cop = AICar(node: built.root, x: snapped.0, z: snapped.1,
                        heading: 0, speed: 0, role: .police,
                        vertical: true, direction: 1)
        cop.sirenLights = Array(built.lights.suffix(2))
        cops.append(cop)
    }

    func clearCops() {
        for c in cops { c.node.removeFromParentNode() }
        cops.removeAll()
    }

    func updateCops(dt: Float) {
        let px = mode == .driving ? carX : footX
        let pz = mode == .driving ? carZ : footZ

        for cop in cops {
            let dx = px - cop.x, dz = pz - cop.z
            let dist = max(0.001, hypotf(dx, dz))
            let want = atan2f(dx, dz)

            // Turn toward the player, capped so they can be out-driven.
            var delta = want - cop.heading
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            cop.heading += max(-1.9 * dt, min(1.9 * dt, delta))

            // They accelerate hard but top out below the player's car.
            let target: Float = dist > 12 ? 38 : 14
            cop.speed += (target - cop.speed) * min(1, dt * 1.6)

            var nx = cop.x + sinf(cop.heading) * cop.speed * dt
            var nz = cop.z + cosf(cop.heading) * cop.speed * dt

            // Same building pushout as the player, so they don't drive through walls.
            for b in buildings {
                let ex = b.2 + 2.2, ez = b.3 + 2.2
                let bx = nx - b.0, bz = nz - b.1
                if abs(bx) < ex && abs(bz) < ez {
                    if ex - abs(bx) < ez - abs(bz) { nx = b.0 + (bx < 0 ? -ex : ex) }
                    else { nz = b.1 + (bz < 0 ? -ez : ez) }
                    cop.speed *= 0.5
                }
            }

            cop.x = CityWorld.clamp(nx)
            cop.z = CityWorld.clamp(nz)
            cop.node.position = SCNVector3(cop.x, 0.42, cop.z)
            cop.node.eulerAngles.y = cop.heading

            // Strobe the light bar.
            cop.sirenPhase += dt * 8
            let on = sinf(cop.sirenPhase) > 0
            for (i, pod) in cop.sirenLights.enumerated() {
                let lit = (i == 0) == on
                pod.geometry?.firstMaterial?.emission.intensity = lit ? 3.2 : 0.05
            }

            // Busted: caught while stationary and boxed in.
            if dist < 3.6 && abs(carSpeed) < 4 && mode == .driving {
                bustedTimer += dt
            }
        }

        if cops.isEmpty { bustedTimer = 0 }
        if bustedTimer > 2.5 {
            bustedTimer = 0
            onBusted()
        }
    }

    // MARK: Mission target car

    /// Spawns the courier the player tails or rams.
    func spawnMissionTarget(near place: String) {
        removeMissionTarget()
        let p = CityWorld.point(place)
        let snapped = CityWorld.snapToRoad(x: p.x + 24, z: p.y + 24)

        let built = makeCar(paint: UIColor(red: 0.92, green: 0.72, blue: 0.10, alpha: 1),
                            police: false, seed: 99, beams: true)
        built.root.position = SCNVector3(snapped.0, 0.42, snapped.1)
        scene.rootNode.addChildNode(built.root)

        // A beacon so the target reads at distance.
        let beacon = SCNCylinder(radius: 0.35, height: 18)
        let bm = beacon.firstMaterial!
        bm.lightingModel = .constant
        bm.diffuse.contents = UIColor.black
        bm.emission.contents = UIColor(red: 1.0, green: 0.75, blue: 0.1, alpha: 1)
        bm.emission.intensity = 2.0
        bm.transparency = 0.4
        let bn = SCNNode(geometry: beacon)
        bn.position = SCNVector3(0, 9, 0)
        bn.castsShadow = false
        built.root.addChildNode(bn)

        missionTarget = AICar(node: built.root, x: snapped.0, z: snapped.1,
                              heading: 0, speed: 20, role: .target,
                              vertical: true, direction: 1)
    }

    func removeMissionTarget() {
        missionTarget?.node.removeFromParentNode()
        missionTarget = nil
    }

    /// The target runs a loop of the road grid, and runs harder once rammed at.
    func updateMissionTargetCar(dt: Float) {
        guard let t = missionTarget else { return }
        let px = mode == .driving ? carX : footX
        let pz = mode == .driving ? carZ : footZ

        // Steer along the grid, turning at junctions, biased away from the player.
        let awayX = t.x - px, awayZ = t.z - pz
        let wantHeading = atan2f(awayX, awayZ)
        var delta = wantHeading - t.heading
        while delta > .pi { delta -= 2 * .pi }
        while delta < -.pi { delta += 2 * .pi }
        t.heading += max(-1.1 * dt, min(1.1 * dt, delta))

        t.speed += (30 - t.speed) * min(1, dt * 1.1)

        var nx = t.x + sinf(t.heading) * t.speed * dt
        var nz = t.z + cosf(t.heading) * t.speed * dt
        for b in buildings {
            let ex = b.2 + 2.2, ez = b.3 + 2.2
            let dx = nx - b.0, dz = nz - b.1
            if abs(dx) < ex && abs(dz) < ez {
                if ex - abs(dx) < ez - abs(dz) { nx = b.0 + (dx < 0 ? -ex : ex) }
                else { nz = b.1 + (dz < 0 ? -ez : ez) }
                t.speed *= 0.55
            }
        }
        t.x = CityWorld.clamp(nx)
        t.z = CityWorld.clamp(nz)
        t.node.position = SCNVector3(t.x, 0.42, t.z)
        t.node.eulerAngles.y = t.heading
    }

    /// Distance from the player to the mission target, or nil when there isn't one.
    func distanceToTarget() -> Float? {
        guard let t = missionTarget else { return nil }
        let px = mode == .driving ? carX : footX
        let pz = mode == .driving ? carZ : footZ
        return hypotf(t.x - px, t.z - pz)
    }
}
