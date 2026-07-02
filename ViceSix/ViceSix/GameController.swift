import SceneKit
import SwiftUI

/// Runs all of Port Leon in 3D. The simulation is the same ground-plane
/// model as ever — CGPoint positions and headings — and SceneKit renders
/// it: (x, y) on the plane becomes (x, 0, z) in the world. The game loop
/// lives in the SceneKit renderer delegate; SwiftUI talks to it through an
/// input queue and a throttled HUD sync on the main thread.
final class GameController: NSObject, SCNSceneRendererDelegate {

    // MARK: Scene

    let scene = SCNScene()
    let cameraNode = SCNNode()
    let controls = TouchControls()
    weak var gameState: GameState?

    private let city = City.generate()
    private var handles = WorldHandles()
    private let sunNode = SCNNode()
    private let ambientNode = SCNNode()
    private let headlight = SCNNode()
    private var rainNode: SCNNode?
    private var rng = SeededRandom(seed: 20251117)

    // MARK: Input queue (main thread writes, render thread drains)

    enum PlayerAction {
        case start(newGame: Bool)
        case respawnArrest, respawnWasted, keepRoaming
        case toggleVehicle, primary, swap
    }
    private var pendingActions: [PlayerAction] = []
    private let actionLock = NSLock()

    // MARK: Player

    private var playerNode: Ped3D!
    private var playerPos = CGPoint.zero
    private var playerHeading: CGFloat = .pi / 2
    private var playerVelocity = CGVector.zero
    private var playerMoving = false
    private var character: Protagonist = .mia
    private var health: CGFloat = GameConfig.maxHealth
    private var cash = 0
    private var lastDamageTime: TimeInterval = 0
    private var playerCar: Car3D?
    private var phase: AppPhase = .menu

    // MARK: Population

    private var traffic: [Car3D] = []
    private var parked: [Car3D] = []
    private var cops: [Car3D] = []
    private var peds: [Ped3D] = []
    private var moneyDrops: [(node: SCNNode, pos: CGPoint, amount: Int)] = []
    private var trafficSpawnCooldown: TimeInterval = 0
    private var pedSpawnCooldown: TimeInterval = 0
    private var copSpawnCooldown: TimeInterval = 0

    // MARK: Wanted

    private var wanted = 0
    private var lastCrimeTime: TimeInterval = -100
    private var starDecayClock: TimeInterval = 0
    private var arrestProgress: TimeInterval = 0

    // MARK: Missions

    private var missions: [Mission] = []
    private var missionsCompleted = 0
    private var activeMission: Mission?
    private var objectiveIndex = 0
    private var timedRemaining: TimeInterval = 0
    private var timedWaypointIndex = 0
    private var surviveRemaining: TimeInterval = 0
    private var missionCar: Car3D?
    private var targetMarker: SCNNode?
    private var giverMarker: SCNNode?
    private var currentTargetPoint: CGPoint?
    private var missionTitleText: String?
    private var objectiveText: String?

    // MARK: Time & atmosphere

    private var lastUpdateTime: TimeInterval = 0
    private var clock: TimeInterval = 0
    private var dayClock: TimeInterval = 60
    private var nightFactor: CGFloat = 0
    private var atmosphereCooldown: TimeInterval = 0
    private var raining = false
    private var roadWetness: CGFloat = 0.9
    private var weatherTimer: TimeInterval = 75
    private var hudCooldown: TimeInterval = 0
    private var bannerText: String?
    private var bannerRemaining: TimeInterval = 0
    private var frozen = false
    private var playerSlip: CGFloat = 0
    private var camYaw: CGFloat = .pi / 2
    private var shakeRemaining: TimeInterval = 0
    private var shakeStrength: CGFloat = 0
    private var minimapPublished = false

    // MARK: - Setup

    override init() {
        super.init()
        handles = World3D.build(city: city, into: scene)
        missions = Story.missions(in: city)
        missionsCompleted = UserDefaults.standard.integer(forKey: "vicesix.mission")
        cash = UserDefaults.standard.integer(forKey: "vicesix.cash")

        // HDR pipeline with the full post stack: bloom for the neon and
        // headlights, SSAO for contact shadows between the towers, a touch
        // of vignette and grain, and motion blur that sells the speed.
        let camera = SCNCamera()
        camera.zFar = 20000
        camera.fieldOfView = 62
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = true
        camera.exposureAdaptationBrighteningSpeedFactor = 1.2
        camera.exposureAdaptationDarkeningSpeedFactor = 1.2
        camera.bloomIntensity = 0.8
        camera.bloomThreshold = 0.65
        camera.bloomBlurRadius = 12
        camera.screenSpaceAmbientOcclusionIntensity = 1.0
        camera.screenSpaceAmbientOcclusionRadius = 22
        camera.vignettingPower = 1.0
        camera.vignettingIntensity = 0.6
        camera.grainIntensity = 0.07
        camera.grainIsColored = false
        camera.motionBlurIntensity = 0.35
        camera.saturation = 1.15
        camera.contrast = 1.06
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        let sun = SCNLight()
        sun.type = .directional
        sun.castsShadow = true
        sun.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.shadowSampleCount = 8
        sun.shadowColor = UIColor(white: 0, alpha: 0.5)
        sun.shadowRadius = 5
        sun.automaticallyAdjustsShadowProjection = true
        sun.maximumShadowDistance = 1800
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-0.9, -0.7, 0)
        scene.rootNode.addChildNode(sunNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 400
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let spot = SCNLight()
        spot.type = .spot
        spot.spotInnerAngle = 18
        spot.spotOuterAngle = 60
        spot.attenuationEndDistance = 900
        spot.intensity = 0
        spot.color = UIColor(red: 1, green: 0.95, blue: 0.8, alpha: 1)
        headlight.light = spot
        headlight.eulerAngles = SCNVector3(-0.12, -.pi / 2, 0)

        scene.fogStartDistance = 1100
        scene.fogEndDistance = 4200
        scene.fogDensityExponent = 1.4

        playerPos = CGPoint(x: city.missionGiver.x, y: city.missionGiver.y - 130)
        playerNode = Avatar3D.make(for: character)
        playerNode.planePos = playerPos
        playerNode.heading = playerHeading
        scene.rootNode.addChildNode(playerNode)

        refreshGiverMarker()
        cameraNode.position = SCNVector3(Float(city.missionGiver.x + 500), 700,
                                         Float(city.missionGiver.y + 500))
        cameraNode.look(at: SCNVector3(Float(city.missionGiver.x), 0,
                                       Float(city.missionGiver.y)))
        SoundEngine.shared.start()
    }

    /// Called from SwiftUI (main thread); everything is applied on the
    /// render thread so SceneKit is never touched from two threads.
    func perform(_ action: PlayerAction) {
        actionLock.lock()
        pendingActions.append(action)
        actionLock.unlock()
    }

    // MARK: - Game loop

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if lastUpdateTime == 0 { lastUpdateTime = time }
        let dt = CGFloat(min(max(time - lastUpdateTime, 0), 1.0 / 30.0))
        lastUpdateTime = time
        clock += TimeInterval(dt)

        drainActions()

        let playing = phase == .playing && !frozen
        if playing {
            let before = playerPos
            if playerCar != nil {
                updateDriving(dt)
            } else {
                updateOnFoot(dt)
            }
            playerVelocity = CGVector(dx: (playerPos.x - before.x) / max(dt, 0.001),
                                      dy: (playerPos.y - before.y) / max(dt, 0.001))
            updateWanted(dt)
            updateCops(dt)
            updateMission(dt)
            collectMoney()
            regenerate(dt)
        }
        updateTraffic(dt)
        updatePeds(dt)
        updateCamera(dt, playing: playing)
        updateAtmosphere(dt)
        updateWeather(dt)
        updateSignals()
        syncAudio(playing: playing)
        syncHUD(dt)
    }

    private func drainActions() {
        actionLock.lock()
        let actions = pendingActions
        pendingActions.removeAll()
        actionLock.unlock()
        for action in actions {
            switch action {
            case .start(let newGame): startGame(newGame: newGame)
            case .respawnArrest:
                cash = max(0, cash - GameConfig.bustedFine)
                respawn(at: CGPoint(x: city.policeHQ.x, y: city.policeHQ.y - 120))
            case .respawnWasted:
                cash = max(0, cash - GameConfig.wastedFee)
                respawn(at: CGPoint(x: city.hospital.x, y: city.hospital.y - 120))
            case .keepRoaming:
                frozen = false
                setPhase(.playing)
            case .toggleVehicle: toggleVehicle()
            case .primary: primaryAction()
            case .swap: swapCharacter()
            }
        }
    }

    private func setPhase(_ p: AppPhase) {
        phase = p
        DispatchQueue.main.async { [weak self] in
            self?.gameState?.phase = p
        }
    }

    // MARK: - Flow

    private func startGame(newGame: Bool) {
        if newGame {
            cash = 0
            missionsCompleted = 0
            persist()
            for car in parked { car.removeFromParentNode() }
            parked.removeAll()
        }
        if !minimapPublished {
            minimapPublished = true
            publishMinimapModel()
        }
        health = GameConfig.maxHealth
        wanted = 0
        arrestProgress = 0
        exitCarInstantly()
        character = (missionsCompleted % 2 == 0) ? .mia : .jax
        rebuildAvatar()
        placePlayer(at: CGPoint(x: city.missionGiver.x, y: city.missionGiver.y - 130))
        clearMission()
        refreshGiverMarker()
        frozen = false
        camYaw = playerHeading
        setPhase(.playing)
        banner("Welcome to Port Leon. Head for the glowing beacon.", seconds: 4)
    }

    private func respawn(at point: CGPoint) {
        health = GameConfig.maxHealth
        wanted = 0
        arrestProgress = 0
        for cop in cops { cop.removeFromParentNode() }
        cops.removeAll()
        exitCarInstantly()
        if activeMission != nil { failMission(reason: nil) }
        placePlayer(at: point)
        frozen = false
        persist()
        setPhase(.playing)
    }

    private func placePlayer(at point: CGPoint) {
        playerPos = point
        playerHeading = -.pi / 2
        playerVelocity = .zero
        playerNode.planePos = point
        playerNode.heading = playerHeading
        playerNode.isHidden = false
    }

    private func rebuildAvatar() {
        let hidden = playerNode?.isHidden ?? false
        playerNode?.removeFromParentNode()
        playerNode = Avatar3D.make(for: character)
        playerNode.planePos = playerPos
        playerNode.heading = playerHeading
        playerNode.isHidden = hidden
        scene.rootNode.addChildNode(playerNode)
    }

    private func exitCarInstantly() {
        if let car = playerCar {
            car.driver = .parked
            car.forwardSpeed = 0
            car.velocity = .zero
            car.steerVisual = 0
            car.setBraking(false)
            car.setSiren(false)
            headlight.removeFromParentNode()
            parked.append(car)
            playerCar = nil
        }
    }

    private func persist() {
        UserDefaults.standard.set(cash, forKey: "vicesix.cash")
        UserDefaults.standard.set(missionsCompleted, forKey: "vicesix.mission")
    }

    // MARK: - Buttons

    private func toggleVehicle() {
        guard phase == .playing, !frozen else { return }
        if playerCar != nil {
            exitVehicle()
        } else if let car = enterableCar() {
            enter(car)
        }
    }

    private func primaryAction() {
        guard phase == .playing, !frozen else { return }
        if playerCar != nil { honk() } else { punch() }
    }

    private func swapCharacter() {
        guard phase == .playing, !frozen, playerCar == nil else { return }
        character = character.other
        rebuildAvatar()
        banner("Now playing as \(character.rawValue)", seconds: 2)
    }

    private func enterableCar() -> Car3D? {
        var best: Car3D?
        var bestDist: CGFloat = 82
        var candidates = traffic + parked
        if let mc = missionCar { candidates.append(mc) }
        for car in candidates where !car.kind.isPolice {
            let d = dist(car.planePos, playerPos)
            if d < bestDist {
                best = car
                bestDist = d
            }
        }
        return best
    }

    private func enter(_ car: Car3D) {
        if car.driver == .npc {
            crime(1, note: "Carjacking!")
            spawnFleeingDriver(from: car)
        }
        traffic.removeAll { $0 === car }
        parked.removeAll { $0 === car }
        car.driver = .player
        car.brakeTimer = 0
        car.setBraking(false)
        car.velocity = CGVector(dx: cos(car.heading) * car.forwardSpeed,
                                dy: sin(car.heading) * car.forwardSpeed)
        headlight.removeFromParentNode()
        headlight.position = SCNVector3(Float(car.kind.length / 2 - 4), 22, 0)
        car.addChildNode(headlight)
        playerCar = car
        playerNode.isHidden = true
        playerPos = car.planePos
    }

    private func exitVehicle() {
        guard let car = playerCar else { return }
        car.forwardSpeed = 0
        car.velocity = .zero
        car.steerVisual = 0
        car.setBraking(false)
        car.driver = .parked
        headlight.removeFromParentNode()
        parked.append(car)
        playerCar = nil

        let side = CGVector(dx: cos(car.heading + .pi / 2), dy: sin(car.heading + .pi / 2))
        var out = CGPoint(x: car.planePos.x + side.dx * (car.kind.width / 2 + 22),
                          y: car.planePos.y + side.dy * (car.kind.width / 2 + 22))
        out = clampToWorld(out, margin: 40)
        playerPos = out
        playerHeading = car.heading
        playerNode.planePos = out
        playerNode.heading = playerHeading
        playerNode.isHidden = false
        trimParkedCars()
    }

    private func trimParkedCars() {
        while parked.count > 6 {
            if let idx = parked.firstIndex(where: {
                dist($0.planePos, playerPos) > 1400 && $0 !== missionCar
            }) {
                parked[idx].removeFromParentNode()
                parked.remove(at: idx)
            } else {
                break
            }
        }
    }

    private func spawnFleeingDriver(from car: Car3D) {
        let ped = makePed()
        let side = CGVector(dx: cos(car.heading - .pi / 2), dy: sin(car.heading - .pi / 2))
        ped.planePos = CGPoint(x: car.planePos.x + side.dx * (car.kind.width / 2 + 18),
                               y: car.planePos.y + side.dy * (car.kind.width / 2 + 18))
        ped.state = .flee
        ped.stateTimer = 4
        ped.heading = car.heading - .pi / 2
        scene.rootNode.addChildNode(ped)
        peds.append(ped)
    }

    private func punch() {
        let range = character == .jax ? GameConfig.punchRangeJax : GameConfig.punchRange
        for ped in peds where ped.state != .down {
            if dist(ped.planePos, playerPos) < range {
                ped.knockDown()
                SoundEngine.shared.thud()
                dropCash(at: ped.planePos, amount: ped.wallet)
                scatterPeds(from: playerPos, radius: 200)
                if rng.chance(0.5) { crime(1, note: "Assault reported!") }
                break
            }
        }
    }

    private func honk() {
        guard let car = playerCar else { return }
        SoundEngine.shared.horn()
        scatterPeds(from: car.planePos, radius: 240)
    }

    private func scatterPeds(from point: CGPoint, radius: CGFloat) {
        for ped in peds where ped.state == .walk {
            if dist(ped.planePos, point) < radius {
                ped.state = .flee
                ped.stateTimer = 2.5
                ped.heading = atan2(ped.planePos.y - point.y, ped.planePos.x - point.x)
            }
        }
    }

    private func dropCash(at point: CGPoint, amount: Int) {
        let node = Markers3D.cash()
        node.position = SCNVector3(Float(point.x), 4, Float(point.y))
        scene.rootNode.addChildNode(node)
        moneyDrops.append((node, point, amount))
    }

    private func collectMoney() {
        guard !moneyDrops.isEmpty else { return }
        var kept: [(node: SCNNode, pos: CGPoint, amount: Int)] = []
        for drop in moneyDrops {
            if dist(drop.pos, playerPos) < 36 {
                cash += drop.amount
                drop.node.removeFromParentNode()
            } else {
                kept.append(drop)
            }
        }
        moneyDrops = kept
    }

    // MARK: - Stick (camera-relative, like any third-person game)

    private var stickMagnitude: CGFloat {
        min(1, hypot(controls.vector.dx, controls.vector.dy))
    }

    private func stickWorldAngle() -> CGFloat? {
        guard controls.active, stickMagnitude > 0.1 else { return nil }
        let rel = atan2(controls.vector.dy, controls.vector.dx)
        return camYaw + (rel - .pi / 2)
    }

    // MARK: - On foot

    private func updateOnFoot(_ dt: CGFloat) {
        let desired = stickWorldAngle()
        playerMoving = desired != nil
        playerNode.animateWalk(dt, moving: playerMoving,
                               speed: playerMoving ? 170 : 0)
        guard let angle = desired else { return }
        playerHeading += clampMag(shortestAngle(angle - playerHeading), 10 * dt)
        let maxRun = character == .mia ? GameConfig.runSpeedMia : GameConfig.runSpeedJax
        let step = maxRun * stickMagnitude * dt
        let delta = CGVector(dx: cos(playerHeading) * step, dy: sin(playerHeading) * step)
        let (moved, _) = moveCircle(playerPos, delta: delta, radius: GameConfig.playerRadius)
        playerPos = resolveAgainstCars(moved, radius: GameConfig.playerRadius)
        playerNode.planePos = playerPos
        playerNode.heading = playerHeading
    }

    private func resolveAgainstCars(_ p: CGPoint, radius: CGFloat) -> CGPoint {
        var pos = p
        for car in allCars() {
            let minDist = car.collisionRadius + radius + 4
            let d = dist(car.planePos, pos)
            if d < minDist && d > 0.01 {
                let push = minDist - d
                pos.x += (pos.x - car.planePos.x) / d * push
                pos.y += (pos.y - car.planePos.y) / d * push
            }
        }
        return clampToWorld(pos, margin: 30)
    }

    private func allCars() -> [Car3D] {
        var cars = traffic + parked + cops
        if let c = playerCar { cars.append(c) }
        if let m = missionCar, m !== playerCar { cars.append(m) }
        return cars
    }

    // MARK: - Driving

    private func updateDriving(_ dt: CGFloat) {
        guard let car = playerCar else { return }

        playerSlip = stepVehicle(car, desiredHeading: stickWorldAngle(),
                                 throttle: stickMagnitude, dt: dt)

        for other in traffic {
            if collide(car, with: other) { other.brakeTimer = 2 }
        }
        for other in parked where other !== car {
            collide(car, with: other)
        }
        if let mc = missionCar, mc !== car {
            collide(car, with: mc)
        }
        for ped in peds where ped.state != .down {
            if abs(car.forwardSpeed) > 90 &&
                dist(ped.planePos, car.planePos) < car.kind.length * 0.45 {
                ped.knockDown()
                SoundEngine.shared.thud()
                dropCash(at: ped.planePos, amount: ped.wallet / 2)
                crime(1, note: "Hit and run!")
            }
        }
        playerPos = car.planePos
    }

    /// The tyre model, unchanged from the 2D sim: engine power curve,
    /// braking, drag, and lateral grip that fades in the rain.
    @discardableResult
    private func stepVehicle(_ car: Car3D, desiredHeading: CGFloat?,
                             throttle: CGFloat, dt: CGFloat) -> CGFloat {
        let kind = car.kind
        let fwd = CGVector(dx: cos(car.heading), dy: sin(car.heading))
        let right = CGVector(dx: fwd.dy, dy: -fwd.dx)
        var vF = car.velocity.dx * fwd.dx + car.velocity.dy * fwd.dy
        var vLat = car.velocity.dx * right.dx + car.velocity.dy * right.dy
        var braking = false

        if let desired = desiredHeading, !car.disabled {
            let diff = shortestAngle(desired - car.heading)
            if abs(diff) > 2.35 && vF < 40 {
                vF = approach(vF, -kind.maxSpeed * 0.3, kind.accel * 0.9, dt)
                car.heading -= clampMag(diff, 1.5 * dt) * 0.5
                car.steerVisual = 0
            } else {
                if abs(diff) > 2.35 {
                    vF = approach(vF, 0, kind.accel * 3.0, dt)
                    braking = true
                } else {
                    let want = kind.maxSpeed * throttle
                    if want < vF - 15 {
                        vF = approach(vF, want, kind.accel * 2.4, dt)
                        braking = true
                    } else {
                        let power = kind.accel * max(0.28, 1 - max(0, vF) / kind.maxSpeed)
                        vF = approach(vF, want, power, dt)
                    }
                }
                let speedFactor = min(1, abs(vF) / (kind.maxSpeed * 0.45))
                car.heading += clampMag(diff, kind.turnRate * (0.30 + 0.70 * speedFactor) * dt)
                    * (vF >= -5 ? 1 : -1)
                car.steerVisual = clampMag(diff, 0.5)
            }
        } else {
            vF = approach(vF, 0, 240, dt)
            car.steerVisual *= max(0, 1 - 6 * dt)
        }
        if car.disabled {
            vF = approach(vF, 0, 420, dt)
            braking = false
        }

        vF -= vF * 0.20 * dt
        let grip: CGFloat = raining ? 3.4 : 7.5
        vLat *= max(0, 1 - grip * dt)

        car.velocity = CGVector(dx: fwd.dx * vF + right.dx * vLat,
                                dy: fwd.dy * vF + right.dy * vLat)
        car.forwardSpeed = vF

        let delta = CGVector(dx: car.velocity.dx * dt, dy: car.velocity.dy * dt)
        let (moved, hitWall) = moveCircle(car.planePos, delta: delta,
                                          radius: kind.width * 0.62)
        car.planePos = clampToWorld(moved, margin: 50)

        if hitWall {
            let v = hypot(car.velocity.dx, car.velocity.dy)
            if v > 170 {
                car.applyDamage((v - 120) * 0.06)
                if car === playerCar {
                    shake(min(10, v / 60))
                    SoundEngine.shared.crash(Float(min(1, v / 500)))
                }
                car.velocity = CGVector(dx: -car.velocity.dx * 0.25,
                                        dy: -car.velocity.dy * 0.25)
                car.forwardSpeed = -vF * 0.25
            } else {
                car.velocity = .zero
                car.forwardSpeed = 0
            }
        }

        let nose = CGPoint(x: car.planePos.x + fwd.dx * (kind.length / 2 - 6),
                           y: car.planePos.y + fwd.dy * (kind.length / 2 - 6))
        for rect in city.collisionRects(near: nose) where rect.contains(nose) {
            let v = abs(car.forwardSpeed)
            if v > 170 {
                car.applyDamage((v - 120) * 0.05)
                if car === playerCar { SoundEngine.shared.crash(Float(min(1, v / 500))) }
            }
            car.planePos = CGPoint(x: car.planePos.x - fwd.dx * v * dt * 1.2,
                                   y: car.planePos.y - fwd.dy * v * dt * 1.2)
            car.forwardSpeed = -car.forwardSpeed * 0.2
            car.velocity = CGVector(dx: fwd.dx * car.forwardSpeed,
                                    dy: fwd.dy * car.forwardSpeed)
            break
        }

        car.setBraking(braking && abs(vF) > 8)
        car.spinWheels(dt)
        return abs(vLat)
    }

    @discardableResult
    private func collide(_ a: Car3D, with b: Car3D) -> Bool {
        let minDist = (a.kind.length + b.kind.length) * 0.30
        let d = dist(a.planePos, b.planePos)
        guard d < minDist, d > 0.01 else { return false }
        let overlap = (minDist - d) / 2
        let nx = (b.planePos.x - a.planePos.x) / d
        let ny = (b.planePos.y - a.planePos.y) / d
        a.planePos = CGPoint(x: a.planePos.x - nx * overlap, y: a.planePos.y - ny * overlap)
        b.planePos = CGPoint(x: b.planePos.x + nx * overlap, y: b.planePos.y + ny * overlap)
        let rel = CGVector(dx: a.velocity.dx - b.velocity.dx,
                           dy: a.velocity.dy - b.velocity.dy)
        let impact = max(abs(a.forwardSpeed - b.forwardSpeed), hypot(rel.dx, rel.dy))
        if impact > 120 {
            a.applyDamage(impact * 0.035)
            b.applyDamage(impact * 0.05)
            if a === playerCar || b === playerCar {
                shake(min(8, impact / 90))
                SoundEngine.shared.crash(Float(min(1, impact / 600)))
            }
        }
        for car in [a, b] {
            car.forwardSpeed *= 0.72
            car.velocity = CGVector(dx: car.velocity.dx * 0.72, dy: car.velocity.dy * 0.72)
        }
        a.velocity = CGVector(dx: a.velocity.dx - nx * impact * 0.18,
                              dy: a.velocity.dy - ny * impact * 0.18)
        b.velocity = CGVector(dx: b.velocity.dx + nx * impact * 0.18,
                              dy: b.velocity.dy + ny * impact * 0.18)
        return true
    }

    // MARK: - Traffic

    private static let dirVectors: [CGVector] = [
        CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: 1),
        CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1),
    ]
    private static let dirAngles: [CGFloat] = [0, .pi / 2, .pi, -.pi / 2]

    private func updateTraffic(_ dt: CGFloat) {
        trafficSpawnCooldown -= TimeInterval(dt)
        if traffic.count < GameConfig.trafficCount && trafficSpawnCooldown <= 0 {
            trafficSpawnCooldown = 0.25
            spawnTrafficCar()
        }
        var kept: [Car3D] = []
        for car in traffic {
            if dist(car.planePos, playerPos) > GameConfig.despawnDistance {
                car.removeFromParentNode()
                continue
            }
            driveTrafficCar(car, dt)
            kept.append(car)
        }
        traffic = kept
    }

    private func driveTrafficCar(_ car: Car3D, _ dt: CGFloat) {
        guard !car.disabled else { return }
        let dir = Self.dirVectors[car.dirIndex]
        let horizontal = car.dirIndex % 2 == 0
        car.brakeTimer = max(0, car.brakeTimer - TimeInterval(dt))

        let along = horizontal ? car.planePos.x : car.planePos.y
        let crossCoord = City.roadCenter(car.crossIndex)
        let step = (car.dirIndex == 0 || car.dirIndex == 1) ? 1 : -1

        var blocked = car.brakeTimer > 0
        if !blocked {
            let lookAhead: CGFloat = 120 + car.forwardSpeed * 0.3
            blocked = obstacleAhead(of: car, dir: dir, distance: lookAhead)
        }
        if !blocked {
            let parity = (car.crossIndex + car.roadIndex) % 2
            let signal = horizontal ? horizontalSignal(parity: parity)
                                    : verticalSignal(parity: parity)
            if signal != 0 {
                let stopCoord = crossCoord - CGFloat(step) * (City.roadHalf + 16)
                let distToStop = (stopCoord - along) * CGFloat(step)
                if distToStop > -8 && distToStop < 150 { blocked = true }
            }
        }

        let cruise = car.kind.maxSpeed * (raining ? 0.42 : 0.5)
        car.forwardSpeed = approach(car.forwardSpeed, blocked ? 0 : cruise,
                                    blocked ? 600 : car.kind.accel * 0.7, dt)
        car.setBraking(blocked && car.forwardSpeed > 4)

        var p = car.planePos
        p.x += dir.dx * car.forwardSpeed * dt
        p.y += dir.dy * car.forwardSpeed * dt
        let laneTarget = trafficLaneTarget(for: car)
        if horizontal {
            p.y += (laneTarget - p.y) * min(1, 6 * dt)
        } else {
            p.x += (laneTarget - p.x) * min(1, 6 * dt)
        }
        car.planePos = p
        car.velocity = CGVector(dx: dir.dx * car.forwardSpeed, dy: dir.dy * car.forwardSpeed)

        let want = Self.dirAngles[car.dirIndex]
        car.heading += clampMag(shortestAngle(want - car.heading), 7 * dt)
        car.spinWheels(dt)

        let newAlong = horizontal ? p.x : p.y
        if (step > 0 && newAlong >= crossCoord) || (step < 0 && newAlong <= crossCoord) {
            decideTurn(for: car, step: step)
        }
    }

    private func trafficLaneTarget(for car: Car3D) -> CGFloat {
        let c = City.roadCenter(car.roadIndex)
        switch car.dirIndex {
        case 0: return c - City.laneOffset
        case 1: return c + City.laneOffset
        case 2: return c + City.laneOffset
        default: return c - City.laneOffset
        }
    }

    private func decideTurn(for car: Car3D, step: Int) {
        let k = car.crossIndex
        let r = car.roadIndex
        let horizontal = car.dirIndex % 2 == 0

        var options: [(dir: Int, road: Int, cross: Int)] = []
        let straightCross = k + step
        if straightCross >= 0 && straightCross <= City.blocksX {
            options.append((car.dirIndex, r, straightCross))
            options.append((car.dirIndex, r, straightCross))
            options.append((car.dirIndex, r, straightCross))
        }
        if horizontal {
            if r + 1 <= City.blocksY { options.append((1, k, r + 1)) }
            if r - 1 >= 0 { options.append((3, k, r - 1)) }
        } else {
            if r + 1 <= City.blocksX { options.append((0, k, r + 1)) }
            if r - 1 >= 0 { options.append((2, k, r - 1)) }
        }
        guard !options.isEmpty else { return }
        let choice = options[rng.int(0, options.count - 1)]
        car.dirIndex = choice.dir
        car.roadIndex = choice.road
        car.crossIndex = choice.cross
    }

    private func obstacleAhead(of car: Car3D, dir: CGVector,
                               distance lookAhead: CGFloat) -> Bool {
        func ahead(_ p: CGPoint) -> Bool {
            let dx = p.x - car.planePos.x
            let dy = p.y - car.planePos.y
            let along = dx * dir.dx + dy * dir.dy
            let side = abs(dx * dir.dy - dy * dir.dx)
            return along > 20 && along < lookAhead && side < 55
        }
        for other in allCars() where other !== car {
            if ahead(other.planePos) { return true }
        }
        for ped in peds where ped.state != .down {
            if ahead(ped.planePos) { return true }
        }
        if playerCar == nil && ahead(playerPos) { return true }
        return false
    }

    private func spawnTrafficCar() {
        guard let (pos, dirIndex, road, cross) = randomLaneSpot() else { return }
        let kind = CarCatalog.traffic[rng.int(0, CarCatalog.traffic.count - 1)]
        let car = Car3D(kind: kind, color: kind.colors[rng.int(0, kind.colors.count - 1)])
        car.planePos = pos
        car.dirIndex = dirIndex
        car.roadIndex = road
        car.crossIndex = cross
        car.heading = Self.dirAngles[dirIndex]
        car.driver = .npc
        scene.rootNode.addChildNode(car)
        traffic.append(car)
    }

    private func randomLaneSpot() -> (CGPoint, Int, Int, Int)? {
        for _ in 0..<12 {
            let vertical = rng.chance(0.5)
            let road = rng.int(0, City.blocksX)
            let along = rng.range(City.roadHalf + 60, City.worldSize - City.roadHalf - 60)
            let positive = rng.chance(0.5)
            let dirIndex = vertical ? (positive ? 1 : 3) : (positive ? 0 : 2)
            let c = City.roadCenter(road)
            var pos: CGPoint
            switch dirIndex {
            case 0: pos = CGPoint(x: along, y: c - City.laneOffset)
            case 1: pos = CGPoint(x: c + City.laneOffset, y: along)
            case 2: pos = CGPoint(x: along, y: c + City.laneOffset)
            default: pos = CGPoint(x: c - City.laneOffset, y: along)
            }
            let d = dist(pos, playerPos)
            guard d > GameConfig.spawnRingMin && d < GameConfig.spawnRingMax else { continue }
            let step = (dirIndex == 0 || dirIndex == 1) ? 1 : -1
            let cross = nextCrossIndex(coord: along, step: step)
            return (pos, dirIndex, road, cross)
        }
        return nil
    }

    private func nextCrossIndex(coord: CGFloat, step: Int) -> Int {
        let f = (coord - City.roadHalf) / City.cell
        if step > 0 {
            return min(City.blocksX, Int(ceil(f + 0.001)))
        } else {
            return max(0, Int(floor(f - 0.001)))
        }
    }

    // MARK: - Pedestrians

    private func makePed() -> Ped3D {
        let shirts: [UIColor] = [
            UIColor(red: 0.85, green: 0.55, blue: 0.25, alpha: 1),
            UIColor(red: 0.35, green: 0.55, blue: 0.80, alpha: 1),
            UIColor(red: 0.60, green: 0.30, blue: 0.55, alpha: 1),
            UIColor(red: 0.30, green: 0.60, blue: 0.40, alpha: 1),
            UIColor(white: 0.85, alpha: 1),
            UIColor(red: 0.80, green: 0.30, blue: 0.30, alpha: 1),
        ]
        let skins: [UIColor] = [
            UIColor(red: 0.95, green: 0.80, blue: 0.65, alpha: 1),
            UIColor(red: 0.80, green: 0.60, blue: 0.45, alpha: 1),
            UIColor(red: 0.55, green: 0.38, blue: 0.28, alpha: 1),
        ]
        let trousers: [UIColor] = [
            UIColor(white: 0.2, alpha: 1),
            UIColor(red: 0.25, green: 0.3, blue: 0.45, alpha: 1),
            UIColor(red: 0.4, green: 0.35, blue: 0.3, alpha: 1),
        ]
        let ped = Ped3D(shirt: rng.pick(shirts), trousers: rng.pick(trousers),
                        skin: rng.pick(skins))
        ped.walkSpeed = rng.range(40, 70)
        ped.wallet = rng.int(8, 45)
        return ped
    }

    private func updatePeds(_ dt: CGFloat) {
        pedSpawnCooldown -= TimeInterval(dt)
        if peds.count < GameConfig.pedCount && pedSpawnCooldown <= 0 {
            pedSpawnCooldown = 0.2
            spawnPed()
        }
        var kept: [Ped3D] = []
        for ped in peds {
            if dist(ped.planePos, playerPos) > GameConfig.despawnDistance {
                ped.removeFromParentNode()
                continue
            }
            ped.stateTimer -= TimeInterval(dt)
            switch ped.state {
            case .walk:
                if ped.stateTimer <= 0 {
                    if rng.chance(0.75) {
                        let cardinal: [CGFloat] = [0, .pi / 2, .pi, -.pi / 2]
                        ped.heading = cardinal[rng.int(0, 3)] + rng.range(-0.12, 0.12)
                    } else {
                        ped.heading = rng.range(-.pi, .pi)
                    }
                    ped.stateTimer = TimeInterval(rng.range(1.5, 5))
                }
                stepPed(ped, speed: ped.walkSpeed, dt: dt)
                ped.animateWalk(dt, moving: true, speed: ped.walkSpeed)
            case .flee:
                if ped.stateTimer <= 0 {
                    ped.state = .walk
                    ped.stateTimer = 2
                }
                stepPed(ped, speed: 130, dt: dt)
                ped.animateWalk(dt, moving: true, speed: 130)
            case .down:
                if ped.stateTimer <= 0 {
                    ped.runAction(.sequence([.fadeOut(duration: 0.5),
                                             .removeFromParentNode()]))
                    continue
                }
            }
            kept.append(ped)
        }
        peds = kept
    }

    private func stepPed(_ ped: Ped3D, speed: CGFloat, dt: CGFloat) {
        let delta = CGVector(dx: cos(ped.heading) * speed * dt,
                             dy: sin(ped.heading) * speed * dt)
        let (moved, hit) = moveCircle(ped.planePos, delta: delta, radius: 8)
        ped.planePos = clampToWorld(moved, margin: 24)
        if hit { ped.heading = rng.range(-.pi, .pi) }

        if let car = playerCar, abs(car.forwardSpeed) > 120, ped.state == .walk {
            let toPed = CGVector(dx: ped.planePos.x - car.planePos.x,
                                 dy: ped.planePos.y - car.planePos.y)
            let d = hypot(toPed.dx, toPed.dy)
            if d < 160 {
                let facing = cos(car.heading) * toPed.dx / d + sin(car.heading) * toPed.dy / d
                if facing > 0.75 {
                    ped.state = .flee
                    ped.stateTimer = 1.5
                    ped.heading = atan2(toPed.dy, toPed.dx) + rng.range(-0.5, 0.5)
                }
            }
        }
    }

    private func spawnPed() {
        for _ in 0..<10 {
            let i = rng.int(0, City.blocksX - 1)
            let j = rng.int(0, City.blocksY - 1)
            let rect = City.blockRect(i, j).insetBy(dx: 14, dy: 14)
            let p = CGPoint(x: rng.range(rect.minX, rect.maxX),
                            y: rng.range(rect.minY, rect.maxY))
            let d = dist(p, playerPos)
            guard d > GameConfig.spawnRingMin && d < GameConfig.spawnRingMax else { continue }
            if city.buildings[i][j].contains(where: {
                $0.rect.insetBy(dx: -10, dy: -10).contains(p)
            }) { continue }
            let ped = makePed()
            ped.planePos = p
            ped.heading = rng.range(-.pi, .pi)
            ped.stateTimer = TimeInterval(rng.range(1, 4))
            scene.rootNode.addChildNode(ped)
            peds.append(ped)
            return
        }
    }

    // MARK: - Wanted & police

    private func crime(_ stars: Int, note: String) {
        lastCrimeTime = clock
        let old = wanted
        wanted = min(GameConfig.maxWanted, wanted + stars)
        if wanted != old {
            banner("\(note)  ★\(wanted)", seconds: 2.5)
        }
    }

    private func updateWanted(_ dt: CGFloat) {
        guard wanted > 0 else { return }
        let copsNearby = cops.contains {
            dist($0.planePos, playerPos) < GameConfig.copSafeDistance
        }
        if clock - lastCrimeTime > GameConfig.crimeCooldown && !copsNearby {
            starDecayClock += TimeInterval(dt)
            if starDecayClock >= GameConfig.starDecayInterval {
                starDecayClock = 0
                wanted -= 1
                if wanted == 0 {
                    banner("You lost the heat.", seconds: 2.5)
                    arrestProgress = 0
                }
            }
        } else {
            starDecayClock = 0
        }
    }

    private func updateCops(_ dt: CGFloat) {
        let want = wanted == 0 ? 0 : min(wanted + 1, 6)
        copSpawnCooldown -= TimeInterval(dt)
        if cops.count < want && copSpawnCooldown <= 0 {
            copSpawnCooldown = 1.4
            spawnCop()
        }
        if wanted == 0 && !cops.isEmpty {
            for cop in cops {
                cop.setSiren(false)
                cop.runAction(.sequence([.fadeOut(duration: 1.2), .removeFromParentNode()]))
            }
            cops.removeAll()
            arrestProgress = 0
            return
        }

        var arresting = false
        var kept: [Car3D] = []
        for cop in cops {
            if cop.disabled {
                cop.setSiren(false)
                cop.runAction(.sequence([.wait(duration: 20), .fadeOut(duration: 1),
                                         .removeFromParentNode()]))
                continue
            }
            driveCop(cop, dt)
            if updateArrest(for: cop) { arresting = true }
            updateCopFire(cop, dt)
            kept.append(cop)
        }
        cops = kept
        if !arresting {
            arrestProgress = max(0, arrestProgress - TimeInterval(dt) * 1.5)
        } else {
            arrestProgress += TimeInterval(dt)
            if arrestProgress >= GameConfig.arrestTime {
                frozen = true
                persistAndSyncCash()
                setPhase(.busted)
            }
        }
    }

    private func spawnCop() {
        guard let (pos, dirIndex, _, _) = randomLaneSpot() else { return }
        let kind = CarCatalog.police
        let cop = Car3D(kind: kind, color: kind.colors[0])
        cop.planePos = pos
        cop.heading = Self.dirAngles[dirIndex]
        cop.driver = .cop
        cop.setSiren(true)
        cop.repathTimer = 0
        scene.rootNode.addChildNode(cop)
        cops.append(cop)
    }

    private func driveCop(_ cop: Car3D, _ dt: CGFloat) {
        let toPlayer = dist(cop.planePos, playerPos)

        cop.repathTimer -= TimeInterval(dt)
        if cop.repathTimer <= 0 || cop.path.isEmpty {
            cop.path = roadPath(from: cop.planePos, to: playerPos)
            cop.repathTimer = TimeInterval(rng.range(0.8, 1.3))
        }
        if let wp = cop.path.first, dist(cop.planePos, wp) < 95 {
            cop.path.removeFirst()
        }

        let predicted = CGPoint(x: playerPos.x + playerVelocity.dx * 0.35,
                                y: playerPos.y + playerVelocity.dy * 0.35)
        let target = toPlayer < 320 ? predicted : (cop.path.first ?? predicted)

        var targetSpeed = min(cop.kind.maxSpeed, 260 + CGFloat(wanted) * 55)
        if playerCar == nil {
            targetSpeed = min(targetSpeed, max(0, toPlayer - 110) * 1.6)
        }
        let desired = atan2(target.y - cop.planePos.y, target.x - cop.planePos.x)

        if cop.reverseTimer > 0 {
            cop.reverseTimer -= TimeInterval(dt)
            stepVehicle(cop, desiredHeading: cop.heading + .pi, throttle: 0.4, dt: dt)
        } else {
            stepVehicle(cop, desiredHeading: desired,
                        throttle: min(1, targetSpeed / cop.kind.maxSpeed), dt: dt)
        }

        if abs(cop.forwardSpeed) < 30 && targetSpeed > 60 && cop.reverseTimer <= 0 {
            cop.stuckTimer += TimeInterval(dt)
            if cop.stuckTimer > 1.6 {
                cop.stuckTimer = 0
                cop.reverseTimer = 0.8
                cop.path = []
            }
        } else {
            cop.stuckTimer = 0
        }

        if let pcar = playerCar {
            collide(cop, with: pcar)
        }
    }

    private func updateArrest(for cop: Car3D) -> Bool {
        let d = dist(cop.planePos, playerPos)
        if let car = playerCar {
            return d < GameConfig.arrestDistanceCar && abs(car.forwardSpeed) < 50
        }
        let speed = hypot(playerVelocity.dx, playerVelocity.dy)
        return d < GameConfig.arrestDistanceFoot && speed < 70
    }

    private func updateCopFire(_ cop: Car3D, _ dt: CGFloat) {
        guard wanted >= 3 else { return }
        let d = dist(cop.planePos, playerPos)
        guard d < GameConfig.copFireRange else { return }
        if playerCar == nil && d < GameConfig.arrestDistanceFoot { return }

        cop.fireTimer -= TimeInterval(dt)
        guard cop.fireTimer <= 0 else { return }
        cop.fireTimer = TimeInterval(rng.range(0.9, 1.5))

        let jitter = CGPoint(x: playerPos.x + rng.range(-26, 26),
                             y: playerPos.y + rng.range(-26, 26))
        addTracer(from: cop.planePos, to: jitter)
        SoundEngine.shared.shot()

        if rng.chance(0.65) {
            if let car = playerCar {
                car.applyDamage(4)
                if car.disabled { banner("Your ride is toast — bail out!", seconds: 3) }
            } else {
                damagePlayer(7)
            }
        }
    }

    /// A brief glowing line between two ground points.
    private func addTracer(from a: CGPoint, to b: CGPoint) {
        let length = dist(a, b)
        guard length > 1 else { return }
        let beam = SCNCylinder(radius: 0.8, height: length)
        let m = SCNMaterial()
        m.emission.contents = UIColor(red: 1, green: 0.9, blue: 0.5, alpha: 1)
        m.diffuse.contents = UIColor.clear
        beam.materials = [m]

        let holder = SCNNode()
        holder.position = SCNVector3(Float(a.x), 22, Float(a.y))
        let inner = SCNNode(geometry: beam)
        inner.eulerAngles.x = -.pi / 2
        inner.position = SCNVector3(0, 0, Float(-length / 2))
        holder.addChildNode(inner)
        scene.rootNode.addChildNode(holder)
        holder.look(at: SCNVector3(Float(b.x), 22, Float(b.y)))
        holder.runAction(.sequence([.fadeOut(duration: 0.14), .removeFromParentNode()]))
    }

    private func roadPath(from a: CGPoint, to b: CGPoint) -> [CGPoint] {
        let n = City.blocksX + 1
        func nearestNode(_ p: CGPoint) -> Int {
            let i = max(0, min(n - 1, Int(round((p.x - City.roadHalf) / City.cell))))
            let j = max(0, min(n - 1, Int(round((p.y - City.roadHalf) / City.cell))))
            return j * n + i
        }
        let start = nearestNode(a)
        let goal = nearestNode(b)
        if start == goal {
            return [CGPoint(x: City.roadCenter(goal % n), y: City.roadCenter(goal / n))]
        }
        var parent = [Int](repeating: -1, count: n * n)
        parent[start] = start
        var queue = [start]
        var head = 0
        while head < queue.count {
            let node = queue[head]; head += 1
            if node == goal { break }
            let i = node % n, j = node / n
            for (di, dj) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let ni = i + di, nj = j + dj
                guard ni >= 0, ni < n, nj >= 0, nj < n else { continue }
                let next = nj * n + ni
                if parent[next] == -1 {
                    parent[next] = node
                    queue.append(next)
                }
            }
        }
        guard parent[goal] != -1 else { return [] }
        var chain: [Int] = []
        var node = goal
        while node != start {
            chain.append(node)
            node = parent[node]
        }
        return chain.reversed().map {
            CGPoint(x: City.roadCenter($0 % n), y: City.roadCenter($0 / n))
        }
    }

    private func damagePlayer(_ amount: CGFloat) {
        guard health > 0 else { return }
        health = max(0, health - amount)
        lastDamageTime = clock
        if health <= 0 {
            frozen = true
            persistAndSyncCash()
            setPhase(.wasted)
        }
    }

    private func regenerate(_ dt: CGFloat) {
        if health < 45 && clock - lastDamageTime > 6 {
            health = min(45, health + 2 * dt)
        }
        if dist(playerPos, city.hospital) < 140 && health < GameConfig.maxHealth {
            health = min(GameConfig.maxHealth, health + 14 * dt)
        }
        if let car = playerCar, dist(car.planePos, city.garage) < 150, car.hp > 0,
           car.hp < car.kind.maxHP {
            car.hp = min(car.kind.maxHP, car.hp + 16 * dt)
        }
    }

    private func persistAndSyncCash() {
        persist()
    }

    // MARK: - Missions

    private func refreshGiverMarker() {
        giverMarker?.removeFromParentNode()
        giverMarker = nil
        guard activeMission == nil, missionsCompleted < missions.count else { return }
        let marker = Markers3D.giver()
        marker.position = SCNVector3(Float(city.missionGiver.x), 5, Float(city.missionGiver.y))
        scene.rootNode.addChildNode(marker)
        giverMarker = marker
    }

    private func updateMission(_ dt: CGFloat) {
        if activeMission == nil {
            currentTargetPoint = missionsCompleted < missions.count ? city.missionGiver : nil
            if missionsCompleted < missions.count,
               dist(playerPos, city.missionGiver) < 80 {
                startMission(missions[missionsCompleted])
            }
            return
        }
        guard let mission = activeMission else { return }

        switch mission.objectives[objectiveIndex] {
        case .reach(let wp):
            currentTargetPoint = wp.point
            let carOK = !wp.needsMissionCar || (playerCar != nil && playerCar === missionCar)
            if carOK && dist(playerPos, wp.point) < wp.radius {
                advanceObjective()
            } else if wp.needsMissionCar, let mc = missionCar, mc.disabled {
                failMission(reason: "The car was wrecked.")
            }

        case .reachTimed(let wps, _):
            timedRemaining -= TimeInterval(dt)
            if timedRemaining <= 0 {
                failMission(reason: "Out of time.")
                return
            }
            let wp = wps[timedWaypointIndex]
            currentTargetPoint = wp.point
            if dist(playerPos, wp.point) < wp.radius {
                timedWaypointIndex += 1
                if timedWaypointIndex >= wps.count {
                    advanceObjective()
                } else {
                    moveTargetMarker(to: wps[timedWaypointIndex].point)
                    objectiveText = "Go to \(wps[timedWaypointIndex].label)"
                }
            }

        case .stealCar(let at, _, _):
            currentTargetPoint = missionCar?.planePos ?? at
            if let mc = missionCar {
                if mc.disabled {
                    failMission(reason: "The car was wrecked.")
                } else if playerCar === mc {
                    advanceObjective()
                }
            }

        case .survive:
            currentTargetPoint = nil
            surviveRemaining -= TimeInterval(dt)
            if surviveRemaining <= 0 {
                wanted = 0
                banner("You shook them off!", seconds: 2.5)
                advanceObjective()
            }
        }
    }

    private func startMission(_ mission: Mission) {
        activeMission = mission
        objectiveIndex = 0
        if character != mission.giver && playerCar == nil {
            character = mission.giver
            rebuildAvatar()
        }
        refreshGiverMarker()
        banner(mission.brief, seconds: 6)
        missionTitleText = mission.title
        setupObjective()
    }

    private func setupObjective() {
        guard let mission = activeMission else { return }
        switch mission.objectives[objectiveIndex] {
        case .reach(let wp):
            moveTargetMarker(to: wp.point)
            objectiveText = "Go to \(wp.label)"
        case .reachTimed(let wps, let seconds):
            timedRemaining = seconds
            timedWaypointIndex = 0
            moveTargetMarker(to: wps[0].point)
            objectiveText = "Go to \(wps[0].label)"
        case .stealCar(let at, let kind, let hint):
            let car = Car3D(kind: kind, color: kind.colors[0])
            car.planePos = at
            car.heading = rng.pick([0, .pi / 2, .pi, -.pi / 2])
            car.driver = .parked
            scene.rootNode.addChildNode(car)
            missionCar = car
            moveTargetMarker(to: at)
            objectiveText = "Steal \(hint)"
        case .survive(let seconds, let stars):
            surviveRemaining = seconds
            crime(stars, note: "The alarm is ringing!")
            removeTargetMarker()
            objectiveText = "Survive the heat!"
        }
    }

    private func advanceObjective() {
        guard let mission = activeMission else { return }
        objectiveIndex += 1
        if objectiveIndex >= mission.objectives.count {
            completeMission(mission)
        } else {
            setupObjective()
        }
    }

    private func completeMission(_ mission: Mission) {
        cash += mission.reward
        missionsCompleted += 1
        clearMission()
        banner("MISSION PASSED — +$\(mission.reward)", seconds: 4)
        persist()
        refreshGiverMarker()
        if missionsCompleted >= missions.count {
            frozen = true
            setPhase(.finale)
        }
    }

    private func failMission(reason: String?) {
        if let reason {
            banner("MISSION FAILED — \(reason)", seconds: 4)
        }
        clearMission()
        refreshGiverMarker()
    }

    private func clearMission() {
        activeMission = nil
        objectiveIndex = 0
        removeTargetMarker()
        missionTitleText = nil
        objectiveText = nil
        if let mc = missionCar, mc !== playerCar {
            parked.removeAll { $0 === mc }
            mc.removeFromParentNode()
        }
        missionCar = nil
        currentTargetPoint = nil
    }

    private func moveTargetMarker(to point: CGPoint) {
        removeTargetMarker()
        let marker = Markers3D.waypoint(color: UIColor(red: 1, green: 0.85, blue: 0.2, alpha: 1))
        marker.position = SCNVector3(Float(point.x), 5, Float(point.y))
        scene.rootNode.addChildNode(marker)
        targetMarker = marker
    }

    private func removeTargetMarker() {
        targetMarker?.removeFromParentNode()
        targetMarker = nil
    }

    // MARK: - Camera & atmosphere

    private func updateCamera(_ dt: CGFloat, playing: Bool) {
        if playing {
            let heading = playerCar?.heading ?? playerHeading
            camYaw += shortestAngle(heading - camYaw) * min(1, 3.2 * dt)

            let speedFrac: CGFloat
            if let car = playerCar {
                speedFrac = min(1, abs(car.forwardSpeed) / 640)
            } else {
                speedFrac = 0
            }
            let back: CGFloat = playerCar != nil ? 230 + speedFrac * 90 : 130
            let height: CGFloat = playerCar != nil ? 95 + speedFrac * 30 : 58

            var camPlane = CGPoint(x: playerPos.x - cos(camYaw) * back,
                                   y: playerPos.y - sin(camYaw) * back)
            camPlane = clampToWorld(camPlane, margin: -400)

            var shakeX: Float = 0
            var shakeY: Float = 0
            if shakeRemaining > 0 {
                shakeRemaining -= TimeInterval(dt)
                shakeX = Float(rng.range(-shakeStrength, shakeStrength))
                shakeY = Float(rng.range(-shakeStrength, shakeStrength))
            }

            let target = SCNVector3(Float(camPlane.x) + shakeX, Float(height),
                                    Float(camPlane.y) + shakeY)
            let k = Float(min(1, 6 * dt))
            cameraNode.position = SCNVector3(
                cameraNode.position.x + (target.x - cameraNode.position.x) * k,
                cameraNode.position.y + (target.y - cameraNode.position.y) * k,
                cameraNode.position.z + (target.z - cameraNode.position.z) * k)

            let lookAhead: CGFloat = playerCar != nil ? 120 : 40
            cameraNode.look(at: SCNVector3(Float(playerPos.x + cos(camYaw) * lookAhead),
                                           32,
                                           Float(playerPos.y + sin(camYaw) * lookAhead)))
            cameraNode.camera?.fieldOfView = 62 + speedFrac * 14
        } else if phase == .menu {
            let t = Float(clock) * 0.06
            let cx = Float(city.missionGiver.x)
            let cz = Float(city.missionGiver.y)
            cameraNode.position = SCNVector3(cx + cos(t) * 900, 520, cz + sin(t) * 900)
            cameraNode.look(at: SCNVector3(cx, 60, cz))
            let camPlane = CGPoint(x: CGFloat(cameraNode.position.x),
                                   y: CGFloat(cameraNode.position.z))
            camYaw = atan2(playerPos.y - camPlane.y, playerPos.x - camPlane.x)
        }
    }

    private func shake(_ strength: CGFloat) {
        shakeRemaining = 0.22
        shakeStrength = strength
    }

    private func updateAtmosphere(_ dt: CGFloat) {
        dayClock += TimeInterval(dt)
        let phase = sin(CGFloat(dayClock) * 2 * .pi / 420)
        let day = max(0, phase)              // 1 at noon
        nightFactor = max(0, -phase)

        atmosphereCooldown -= TimeInterval(dt)
        guard atmosphereCooldown <= 0 else { return }
        atmosphereCooldown = 0.25

        if let sun = sunNode.light {
            sun.intensity = 150 + 950 * day
            sun.color = UIColor(red: 1, green: 0.9 - 0.25 * (1 - day),
                                blue: 0.8 - 0.35 * (1 - day), alpha: 1)
        }
        sunNode.eulerAngles = SCNVector3(Float(-0.35 - day * 0.75), -0.7, 0)
        ambientNode.light?.intensity = 130 + 320 * day

        // The sky dome darkens through dusk to night; the image-based
        // light follows it so reflections dim with the sun, and the haze
        // colour tracks the horizon.
        let skyTint = blend(UIColor(red: 0.10, green: 0.11, blue: 0.24, alpha: 1),
                            UIColor.white, t: day)
        handles.skyMaterial.multiply.contents = skyTint
        scene.lightingEnvironment.intensity = 0.25 + 1.1 * day
        scene.fogColor = blend(UIColor(red: 0.05, green: 0.06, blue: 0.13, alpha: 1),
                               UIColor(red: 0.72, green: 0.80, blue: 0.88, alpha: 1),
                               t: day)

        // Wet streets go glassy and mirror the lights.
        let wetTarget: CGFloat = raining ? 0.12 : 0.9
        roadWetness += (wetTarget - roadWetness) * 0.15
        handles.asphaltMaterial.roughness.contents = NSNumber(value: Double(roadWetness))
        handles.asphaltMaterial.metalness.contents =
            NSNumber(value: raining ? 0.3 : 0.0)

        for m in handles.facadeMaterials { m.emission.intensity = nightFactor * 1.1 }
        for m in handles.lampMaterials { m.emission.intensity = nightFactor * 1.6 }
        handles.lampGlowMaterial.emission.intensity = nightFactor * 1.3
        for m in handles.signalMatsV + handles.signalMatsH {
            m.emission.intensity = 0.5 + nightFactor * 0.9
        }
        for car in allCars() { car.setNight(nightFactor) }
        headlight.light?.intensity = nightFactor * 1700
    }

    private func blend(_ a: UIColor, _ b: UIColor, t: CGFloat) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(red: ar + (br - ar) * t, green: ag + (bg - ag) * t,
                       blue: ab + (bb - ab) * t, alpha: 1)
    }

    private func updateWeather(_ dt: CGFloat) {
        rainNode?.position = SCNVector3(Float(playerPos.x), 520, Float(playerPos.y))
        weatherTimer -= TimeInterval(dt)
        guard weatherTimer <= 0 else { return }
        raining.toggle()
        weatherTimer = raining ? TimeInterval(rng.range(25, 55))
                               : TimeInterval(rng.range(60, 150))
        if raining {
            let rain = SCNParticleSystem()
            rain.birthRate = 1600
            rain.particleLifeSpan = 1.1
            rain.emittingDirection = SCNVector3(0, -1, 0)
            rain.particleVelocity = 620
            rain.particleVelocityVariation = 120
            rain.particleSize = 10
            rain.particleColor = UIColor(white: 0.85, alpha: 0.5)
            rain.particleImage = World3D.rainStreak()
            rain.emitterShape = SCNBox(width: 1600, height: 4, length: 1600, chamferRadius: 0)
            rain.birthLocation = .volume
            let node = SCNNode()
            node.position = SCNVector3(Float(playerPos.x), 520, Float(playerPos.y))
            node.addParticleSystem(rain)
            scene.rootNode.addChildNode(node)
            rainNode = node
        } else if let node = rainNode {
            node.removeAllParticleSystems()
            node.runAction(.sequence([.wait(duration: 1.5), .removeFromParentNode()]))
            rainNode = nil
        }
    }

    // MARK: - Traffic signals

    private var lastSignalKey = -1

    private func verticalSignal(parity: Int) -> Int {
        let t = (clock + TimeInterval(parity) * 8).truncatingRemainder(dividingBy: 16)
        if t < 7 { return 0 }
        if t < 8 { return 1 }
        return 2
    }

    private func horizontalSignal(parity: Int) -> Int {
        let t = (clock + TimeInterval(parity) * 8).truncatingRemainder(dividingBy: 16)
        if t < 8 { return 2 }
        if t < 15 { return 0 }
        return 1
    }

    private func updateSignals() {
        let key = verticalSignal(parity: 0) + 3 * horizontalSignal(parity: 0)
            + 9 * verticalSignal(parity: 1) + 27 * horizontalSignal(parity: 1)
        guard key != lastSignalKey else { return }
        lastSignalKey = key
        let colors: [UIColor] = [
            UIColor(red: 0.25, green: 0.9, blue: 0.4, alpha: 1),
            UIColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1),
            UIColor(red: 0.95, green: 0.2, blue: 0.2, alpha: 1),
        ]
        for parity in 0...1 {
            let vColor = colors[verticalSignal(parity: parity)]
            handles.signalMatsV[parity].diffuse.contents = vColor
            handles.signalMatsV[parity].emission.contents = vColor
            let hColor = colors[horizontalSignal(parity: parity)]
            handles.signalMatsH[parity].diffuse.contents = hColor
            handles.signalMatsH[parity].emission.contents = hColor
        }
    }

    // MARK: - Audio & HUD

    private func syncAudio(playing: Bool) {
        let sound = SoundEngine.shared
        sound.setMaster(playing ? 1.0 : 0.35)
        if let car = playerCar, playing, !car.disabled {
            let frac = min(1, abs(car.forwardSpeed) / car.kind.maxSpeed)
            sound.setEngine(level: 0.25 + 0.75 * Float(frac), hz: 58 + 190 * Float(frac))
        } else {
            sound.setEngine(level: 0, hz: 70)
        }
        sound.setScreech(playerCar != nil ? Float(min(1, playerSlip / 220)) : 0)
        var sirenLevel: Float = 0
        for cop in cops where !cop.disabled {
            let d = dist(cop.planePos, playerPos)
            sirenLevel = max(sirenLevel, Float(max(0, 1 - d / 1500)))
        }
        sound.setSiren(sirenLevel)
        sound.setRain(raining ? 0.8 : 0)
    }

    private func banner(_ text: String, seconds: TimeInterval) {
        bannerText = text
        bannerRemaining = seconds
    }

    private func syncHUD(_ dt: CGFloat) {
        if bannerRemaining > 0 {
            bannerRemaining -= TimeInterval(dt)
            if bannerRemaining <= 0 { bannerText = nil }
        }
        hudCooldown -= TimeInterval(dt)
        guard hudCooldown <= 0 else { return }
        hudCooldown = 0.12

        var secondsLeft: Int?
        if let mission = activeMission {
            switch mission.objectives[objectiveIndex] {
            case .reachTimed: secondsLeft = max(0, Int(timedRemaining.rounded(.up)))
            case .survive: secondsLeft = max(0, Int(surviveRemaining.rounded(.up)))
            default: secondsLeft = nil
            }
        }

        let snapshot = MinimapSnapshot(
            player: playerPos,
            heading: playerCar?.heading ?? playerHeading,
            cops: cops.filter { !$0.disabled }.map { $0.planePos },
            target: currentTargetPoint,
            giver: giverMarker != nil ? city.missionGiver : nil)

        let cash = self.cash
        let health = self.health
        let wanted = self.wanted
        let character = self.character
        let inCar = playerCar != nil
        let vName = playerCar?.kind.name
        let vHealth = playerCar.map { max(0, $0.hp / $0.kind.maxHP) } ?? 1
        let kmh = playerCar.map { Int(abs($0.forwardSpeed) * 0.22) } ?? 0
        let canEnter = !inCar && enterableCar() != nil
        let district = city.districtName(at: playerPos)
        let missionTitle = missionTitleText
        let objective = objectiveText
        let bannerNow = bannerText

        DispatchQueue.main.async { [weak self] in
            guard let state = self?.gameState else { return }
            if state.cash != cash { state.cash = cash }
            if abs(state.health - health) > 0.5 { state.health = health }
            if state.wanted != wanted { state.wanted = wanted }
            if state.character != character { state.character = character }
            if state.inVehicle != inCar { state.inVehicle = inCar }
            if state.vehicleName != vName { state.vehicleName = vName }
            if abs(state.vehicleHealth - vHealth) > 0.02 { state.vehicleHealth = vHealth }
            if state.speedKMH != kmh { state.speedKMH = kmh }
            if state.canEnterVehicle != canEnter { state.canEnterVehicle = canEnter }
            if state.districtName != district { state.districtName = district }
            if state.missionTitle != missionTitle { state.missionTitle = missionTitle }
            if state.objectiveText != objective { state.objectiveText = objective }
            if state.objectiveSecondsLeft != secondsLeft {
                state.objectiveSecondsLeft = secondsLeft
            }
            if state.banner != bannerNow { state.banner = bannerNow }
            state.minimap = snapshot
        }
    }

    private func publishMinimapModel() {
        var model = MinimapModel(worldSize: City.worldSize, blocks: [])
        for i in 0..<City.blocksX {
            for j in 0..<City.blocksY {
                let key = i * 100 + j
                let rect = City.blockRect(i, j)
                let color: UIColor
                if city.parkBlocks.contains(key) {
                    color = UIColor(red: 0.32, green: 0.52, blue: 0.30, alpha: 1)
                } else if city.plazaBlocks.contains(key) {
                    color = UIColor(white: 0.62, alpha: 1)
                } else {
                    color = city.districts[city.districtIndex[i][j]].groundColor
                }
                model.blocks.append(MinimapBlock(rect: rect, color: Color(uiColor: color)))
            }
        }
        DispatchQueue.main.async { [weak self] in
            self?.gameState?.minimapModel = model
        }
    }

    // MARK: - Ground-plane geometry helpers

    private func moveCircle(_ p: CGPoint, delta: CGVector,
                            radius: CGFloat) -> (CGPoint, Bool) {
        var hit = false
        let rects = city.collisionRects(near: p)

        var x = p.x + delta.dx
        for r in rects {
            let er = r.insetBy(dx: -radius, dy: -radius)
            if x > er.minX && x < er.maxX && p.y > er.minY && p.y < er.maxY {
                hit = true
                x = delta.dx > 0 ? er.minX : er.maxX
            }
        }
        var y = p.y + delta.dy
        for r in rects {
            let er = r.insetBy(dx: -radius, dy: -radius)
            if x > er.minX && x < er.maxX && y > er.minY && y < er.maxY {
                hit = true
                y = delta.dy > 0 ? er.minY : er.maxY
            }
        }
        return (CGPoint(x: x, y: y), hit)
    }

    private func clampToWorld(_ p: CGPoint, margin: CGFloat) -> CGPoint {
        CGPoint(x: min(max(p.x, margin), City.worldSize - margin),
                y: min(max(p.y, margin), City.worldSize - margin))
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func shortestAngle(_ a: CGFloat) -> CGFloat {
        atan2(sin(a), cos(a))
    }

    private func clampMag(_ value: CGFloat, _ limit: CGFloat) -> CGFloat {
        min(max(value, -limit), limit)
    }

    private func approach(_ value: CGFloat, _ target: CGFloat,
                          _ rate: CGFloat, _ dt: CGFloat) -> CGFloat {
        if value < target {
            return min(target, value + rate * dt)
        } else {
            return max(target, value - rate * dt)
        }
    }
}
