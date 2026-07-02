import SpriteKit
import SwiftUI

/// The whole of Port Leon lives here: rendering, driving and on-foot physics,
/// traffic, pedestrians, police, the wanted system and the mission machine.
/// The scene simulates with plain math (no SKPhysicsWorld) — the city is a
/// grid, so axis-aligned collision is cheap and predictable.
final class GameScene: SKScene {

    weak var gameState: GameState?

    // MARK: World

    private let city = City.generate()
    private let worldNode = SKNode()
    private let camNode = SKCameraNode()
    private let uiNode = SKNode()               // screen-fixed children of the camera
    private let nightOverlay = SKSpriteNode(color: .black, size: CGSize(width: 4000, height: 4000))
    private let targetArrow = SKShapeNode()
    private let stick = Joystick()
    private var rng = SeededRandom(seed: 20251117)
    private var built = false

    // MARK: Player

    private var playerNode: SKNode!
    private var playerPos = CGPoint.zero
    private var playerHeading: CGFloat = .pi / 2
    private var playerVelocity = CGVector.zero
    private var character: Protagonist = .mia
    private var health: CGFloat = GameConfig.maxHealth
    private var cash = 0
    private var lastDamageTime: TimeInterval = 0
    private var playerCar: Car?

    // MARK: Population

    private var traffic: [Car] = []
    private var parked: [Car] = []
    private var cops: [Car] = []
    private var peds: [Ped] = []
    private var moneyDrops: [(node: SKNode, amount: Int)] = []
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
    private var activeMission: Mission?
    private var objectiveIndex = 0
    private var timedRemaining: TimeInterval = 0
    private var timedWaypointIndex = 0
    private var surviveRemaining: TimeInterval = 0
    private var missionCar: Car?
    private var targetMarker: SKNode?
    private var giverMarker: SKNode?
    private var currentTargetPoint: CGPoint?

    // MARK: Timing / HUD

    private var lastUpdateTime: TimeInterval = 0
    private var clock: TimeInterval = 0             // scene-relative time, always advances
    private var dayClock: TimeInterval = 40
    private var hudCooldown: TimeInterval = 0
    private var bannerRemaining: TimeInterval = 0
    private var frozen = false                       // busted / wasted / finale overlays

    // MARK: - Setup

    override init() {
        super.init(size: CGSize(width: 1280, height: 720))
        scaleMode = .resizeFill
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMove(to view: SKView) {
        guard !built else { return }
        built = true

        backgroundColor = SKColor(red: 0.10, green: 0.28, blue: 0.42, alpha: 1)   // open water
        addChild(worldNode)
        buildWorld()

        camera = camNode
        addChild(camNode)
        camNode.addChild(uiNode)

        nightOverlay.zPosition = 150
        nightOverlay.alpha = 0
        uiNode.addChild(nightOverlay)

        let arrowPath = CGMutablePath()
        arrowPath.move(to: CGPoint(x: 16, y: 0))
        arrowPath.addLine(to: CGPoint(x: -10, y: 10))
        arrowPath.addLine(to: CGPoint(x: -4, y: 0))
        arrowPath.addLine(to: CGPoint(x: -10, y: -10))
        arrowPath.closeSubpath()
        targetArrow.path = arrowPath
        targetArrow.fillColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 0.95)
        targetArrow.strokeColor = SKColor(white: 0, alpha: 0.5)
        targetArrow.zPosition = 190
        targetArrow.isHidden = true
        uiNode.addChild(targetArrow)

        uiNode.addChild(stick)

        missions = Story.missions(in: city)

        playerPos = CGPoint(x: city.missionGiver.x, y: city.missionGiver.y - 130)
        playerNode = Avatar.make(for: character)
        playerNode.position = playerPos
        worldNode.addChild(playerNode)

        refreshGiverMarker()
        publishMinimapModel()

        camNode.position = city.missionGiver
        camNode.setScale(1.9)
    }

    // MARK: - World construction

    private func buildWorld() {
        let world = City.worldSize
        let asphalt = SKColor(red: 0.16, green: 0.16, blue: 0.19, alpha: 1)

        let ground = SKSpriteNode(color: asphalt, size: CGSize(width: world, height: world))
        ground.position = CGPoint(x: world / 2, y: world / 2)
        ground.zPosition = 0
        worldNode.addChild(ground)

        // A ring of beach so the island reads as an island.
        let sand = SKColor(red: 0.85, green: 0.77, blue: 0.57, alpha: 1)
        for (dx, dy, w, h): (CGFloat, CGFloat, CGFloat, CGFloat) in
            [(world / 2, -90, world + 360, 180), (world / 2, world + 90, world + 360, 180),
             (-90, world / 2, 180, world), (world + 90, world / 2, 180, world)] {
            let strip = SKSpriteNode(color: sand, size: CGSize(width: w, height: h))
            strip.position = CGPoint(x: dx, y: dy)
            strip.zPosition = 0
            worldNode.addChild(strip)
        }

        // Dashed centre lines for every road, one shape node per road.
        for vertical in [true, false] {
            for k in 0...City.blocksX {
                let c = City.roadCenter(k)
                let path = CGMutablePath()
                var t: CGFloat = City.roadHalf
                while t < world - City.roadHalf {
                    if vertical {
                        path.move(to: CGPoint(x: c, y: t))
                        path.addLine(to: CGPoint(x: c, y: min(t + 30, world - City.roadHalf)))
                    } else {
                        path.move(to: CGPoint(x: t, y: c))
                        path.addLine(to: CGPoint(x: min(t + 30, world - City.roadHalf), y: c))
                    }
                    t += 72
                }
                let dashes = SKShapeNode(path: path)
                dashes.strokeColor = SKColor(red: 0.85, green: 0.75, blue: 0.35, alpha: 0.6)
                dashes.lineWidth = 4
                dashes.zPosition = 0.5
                worldNode.addChild(dashes)
            }
        }

        // Blocks: ground plate, then buildings (shadow + body + roof sheen).
        for i in 0..<City.blocksX {
            for j in 0..<City.blocksY {
                let key = i * 100 + j
                let rect = City.blockRect(i, j)
                let district = city.districts[city.districtIndex[i][j]]

                let plateColor: SKColor
                if city.parkBlocks.contains(key) {
                    plateColor = SKColor(red: 0.32, green: 0.52, blue: 0.30, alpha: 1)
                } else if city.plazaBlocks.contains(key) {
                    plateColor = SKColor(white: 0.60, alpha: 1)
                } else {
                    plateColor = district.groundColor
                }
                let plate = SKSpriteNode(color: plateColor, size: rect.size)
                plate.position = CGPoint(x: rect.midX, y: rect.midY)
                plate.zPosition = 1
                worldNode.addChild(plate)

                if city.parkBlocks.contains(key) {
                    scatterTrees(in: rect, count: 6,
                                 color: SKColor(red: 0.16, green: 0.38, blue: 0.18, alpha: 1))
                } else if city.districtIndex[i][j] == 2 && city.buildings[i][j].count <= 1 {
                    scatterTrees(in: rect, count: 3,
                                 color: SKColor(red: 0.25, green: 0.55, blue: 0.30, alpha: 1))
                }

                for b in city.buildings[i][j] {
                    let shadow = SKSpriteNode(color: SKColor(white: 0, alpha: 0.28),
                                              size: CGSize(width: b.rect.width + 10,
                                                           height: b.rect.height + 10))
                    shadow.position = CGPoint(x: b.rect.midX + 4, y: b.rect.midY - 4)
                    shadow.zPosition = 4.8
                    worldNode.addChild(shadow)

                    let body = SKSpriteNode(color: b.color, size: b.rect.size)
                    body.position = CGPoint(x: b.rect.midX, y: b.rect.midY)
                    body.zPosition = 5
                    worldNode.addChild(body)

                    let sheen = SKSpriteNode(color: SKColor(white: 1, alpha: 0.10),
                                             size: CGSize(width: max(10, b.rect.width - 22),
                                                          height: max(10, b.rect.height - 22)))
                    sheen.position = body.position
                    sheen.zPosition = 5.5
                    worldNode.addChild(sheen)
                }
            }
        }

        decoratePlazas()
    }

    private func scatterTrees(in rect: CGRect, count: Int, color: SKColor) {
        for _ in 0..<count {
            let tree = SKShapeNode(circleOfRadius: rng.range(14, 26))
            tree.fillColor = color
            tree.strokeColor = SKColor(white: 0, alpha: 0.25)
            tree.lineWidth = 2
            tree.position = CGPoint(x: rng.range(rect.minX + 40, rect.maxX - 40),
                                    y: rng.range(rect.minY + 40, rect.maxY - 40))
            tree.zPosition = 6
            worldNode.addChild(tree)
        }
    }

    private func decoratePlazas() {
        func badge(at p: CGPoint, glyph: String, color: SKColor) {
            let disc = SKShapeNode(circleOfRadius: 54)
            disc.fillColor = color.withAlphaComponent(0.85)
            disc.strokeColor = SKColor(white: 1, alpha: 0.7)
            disc.lineWidth = 4
            disc.position = p
            disc.zPosition = 2
            worldNode.addChild(disc)

            let label = SKLabelNode(text: glyph)
            label.fontName = "AvenirNext-Heavy"
            label.fontSize = 46
            label.fontColor = .white
            label.verticalAlignmentMode = .center
            label.position = p
            label.zPosition = 3
            worldNode.addChild(label)
        }
        badge(at: city.hospital, glyph: "+", color: SKColor(red: 0.85, green: 0.2, blue: 0.25, alpha: 1))
        badge(at: city.policeHQ, glyph: "P", color: SKColor(red: 0.15, green: 0.3, blue: 0.65, alpha: 1))
        badge(at: city.garage, glyph: "R", color: SKColor(red: 0.5, green: 0.35, blue: 0.2, alpha: 1))
        badge(at: city.bank, glyph: "$", color: SKColor(red: 0.2, green: 0.5, blue: 0.35, alpha: 1))
        badge(at: city.hideout, glyph: "H", color: SKColor(red: 0.4, green: 0.3, blue: 0.5, alpha: 1))
        badge(at: city.airport, glyph: "A", color: SKColor(red: 0.35, green: 0.4, blue: 0.45, alpha: 1))
        badge(at: city.marina, glyph: "M", color: SKColor(red: 0.2, green: 0.45, blue: 0.6, alpha: 1))
    }

    private func publishMinimapModel() {
        var model = MinimapModel(worldSize: City.worldSize, blocks: [])
        for i in 0..<City.blocksX {
            for j in 0..<City.blocksY {
                let key = i * 100 + j
                let rect = City.blockRect(i, j)
                let color: SKColor
                if city.parkBlocks.contains(key) {
                    color = SKColor(red: 0.32, green: 0.52, blue: 0.30, alpha: 1)
                } else if city.plazaBlocks.contains(key) {
                    color = SKColor(white: 0.62, alpha: 1)
                } else {
                    color = city.districts[city.districtIndex[i][j]].groundColor
                }
                model.blocks.append(MinimapBlock(rect: rect, color: Color(uiColor: color)))
            }
        }
        gameState?.minimapModel = model
    }

    // MARK: - Flow control (called by the SwiftUI layer)

    func startGame(newGame: Bool) {
        guard let state = gameState else { return }
        if newGame {
            state.wipeSave()
            for car in parked { car.removeFromParent() }
            parked.removeAll()
        }
        if state.minimapModel.blocks.isEmpty { publishMinimapModel() }
        cash = state.cash
        health = GameConfig.maxHealth
        wanted = 0
        arrestProgress = 0
        exitCarInstantly()
        character = (state.missionsCompleted % 2 == 0) ? .mia : .jax
        rebuildAvatar()
        placePlayer(at: CGPoint(x: city.missionGiver.x, y: city.missionGiver.y - 130))
        clearMission(silently: true)
        refreshGiverMarker()
        frozen = false
        state.phase = .playing
        camNode.position = playerPos
        camNode.setScale(1.0)
        banner("Welcome to Port Leon. Look for the VI marker.", seconds: 4)
    }

    func respawnAfterArrest() {
        guard let state = gameState else { return }
        cash = max(0, cash - GameConfig.bustedFine)
        respawn(at: CGPoint(x: city.policeHQ.x, y: city.policeHQ.y - 120))
        state.phase = .playing
    }

    func respawnAfterWasted() {
        guard let state = gameState else { return }
        cash = max(0, cash - GameConfig.wastedFee)
        respawn(at: CGPoint(x: city.hospital.x, y: city.hospital.y - 120))
        state.phase = .playing
    }

    func keepRoaming() {
        frozen = false
        gameState?.phase = .playing
    }

    private func respawn(at point: CGPoint) {
        health = GameConfig.maxHealth
        wanted = 0
        arrestProgress = 0
        for cop in cops { cop.removeFromParent() }
        cops.removeAll()
        exitCarInstantly()
        if activeMission != nil { failMission(reason: nil) }
        placePlayer(at: point)
        frozen = false
        camNode.position = playerPos
        persist()
    }

    private func placePlayer(at point: CGPoint) {
        playerPos = point
        playerNode.position = point
        playerNode.isHidden = false
        playerHeading = -.pi / 2
        playerVelocity = .zero
    }

    private func exitCarInstantly() {
        if let car = playerCar {
            car.driver = .parked
            car.speed = 0
            car.setSiren(false)
            parked.append(car)
            playerCar = nil
        }
    }

    // MARK: - Buttons (called by the SwiftUI layer)

    func toggleVehicle() {
        guard gameState?.phase == .playing, !frozen else { return }
        if playerCar != nil {
            exitVehicle()
        } else if let car = enterableCar() {
            enter(car)
        }
    }

    func primaryAction() {
        guard gameState?.phase == .playing, !frozen else { return }
        if playerCar != nil {
            honk()
        } else {
            punch()
        }
    }

    func swapCharacter() {
        guard gameState?.phase == .playing, !frozen, playerCar == nil else { return }
        character = character.other
        rebuildAvatar()
        banner("Now playing as \(character.rawValue)", seconds: 2)
    }

    private func rebuildAvatar() {
        let pos = playerNode?.position ?? playerPos
        let hidden = playerNode?.isHidden ?? false
        playerNode?.removeFromParent()
        playerNode = Avatar.make(for: character)
        playerNode.position = pos
        playerNode.zRotation = playerHeading
        playerNode.isHidden = hidden
        worldNode.addChild(playerNode)
    }

    private func enterableCar() -> Car? {
        var best: Car?
        var bestDist: CGFloat = 78
        for car in traffic + parked + (missionCar.map { [$0] } ?? []) where !car.kind.isPolice {
            let d = distance(car.position, playerPos)
            if d < bestDist {
                best = car
                bestDist = d
            }
        }
        return best
    }

    private func enter(_ car: Car) {
        if car.driver == .npc {
            crime(1, note: "Carjacking!")
            spawnFleeingDriver(from: car)
        }
        traffic.removeAll { $0 === car }
        parked.removeAll { $0 === car }
        car.driver = .player
        car.brakeTimer = 0
        playerCar = car
        playerNode.isHidden = true
        playerPos = car.position
    }

    private func exitVehicle() {
        guard let car = playerCar else { return }
        car.speed = 0
        car.driver = .parked
        parked.append(car)
        playerCar = nil

        // Step out beside the driver's door, or wherever there is room.
        let side = CGVector(dx: cos(car.heading + .pi / 2), dy: sin(car.heading + .pi / 2))
        var out = CGPoint(x: car.position.x + side.dx * (car.kind.width / 2 + 20),
                          y: car.position.y + side.dy * (car.kind.width / 2 + 20))
        out = clampToWorld(out, margin: 40)
        playerPos = out
        playerHeading = car.heading
        playerNode.position = out
        playerNode.zRotation = playerHeading
        playerNode.isHidden = false
        trimParkedCars()
    }

    private func trimParkedCars() {
        while parked.count > 6 {
            if let idx = parked.firstIndex(where: {
                distance($0.position, playerPos) > 1400 && $0 !== missionCar
            }) {
                parked[idx].removeFromParent()
                parked.remove(at: idx)
            } else {
                break
            }
        }
    }

    private func spawnFleeingDriver(from car: Car) {
        let ped = makePed()
        let side = CGVector(dx: cos(car.heading - .pi / 2), dy: sin(car.heading - .pi / 2))
        ped.position = CGPoint(x: car.position.x + side.dx * (car.kind.width / 2 + 16),
                               y: car.position.y + side.dy * (car.kind.width / 2 + 16))
        ped.state = .flee
        ped.stateTimer = 4
        ped.heading = car.heading - .pi / 2
        worldNode.addChild(ped)
        peds.append(ped)
    }

    private func punch() {
        let range = character == .jax ? GameConfig.punchRangeJax : GameConfig.punchRange
        let flash = SKShapeNode(circleOfRadius: 20)
        flash.fillColor = SKColor(white: 1, alpha: 0.5)
        flash.strokeColor = .clear
        flash.position = CGPoint(x: playerPos.x + cos(playerHeading) * 24,
                                 y: playerPos.y + sin(playerHeading) * 24)
        flash.zPosition = 11
        worldNode.addChild(flash)
        flash.run(.sequence([.fadeOut(withDuration: 0.16), .removeFromParent()]))

        for ped in peds where ped.state != .down {
            if distance(ped.position, playerPos) < range {
                ped.knockDown()
                dropCash(at: ped.position, amount: ped.wallet)
                scatterPeds(from: playerPos, radius: 200)
                if rng.chance(0.5) { crime(1, note: "Assault reported!") }
                break
            }
        }
    }

    private func honk() {
        guard let car = playerCar else { return }
        scatterPeds(from: car.position, radius: 220)
        let ring = SKShapeNode(circleOfRadius: 30)
        ring.strokeColor = SKColor(white: 1, alpha: 0.6)
        ring.lineWidth = 3
        ring.fillColor = .clear
        ring.position = car.position
        ring.zPosition = 11
        worldNode.addChild(ring)
        ring.run(.sequence([.group([.scale(to: 3.2, duration: 0.4),
                                    .fadeOut(withDuration: 0.4)]),
                            .removeFromParent()]))
    }

    private func scatterPeds(from point: CGPoint, radius: CGFloat) {
        for ped in peds where ped.state == .walk {
            if distance(ped.position, point) < radius {
                ped.state = .flee
                ped.stateTimer = 2.5
                ped.heading = atan2(ped.position.y - point.y, ped.position.x - point.x)
            }
        }
    }

    private func dropCash(at point: CGPoint, amount: Int) {
        let node = SKNode()
        let disc = SKShapeNode(circleOfRadius: 11)
        disc.fillColor = SKColor(red: 0.2, green: 0.65, blue: 0.3, alpha: 1)
        disc.strokeColor = SKColor(white: 1, alpha: 0.8)
        disc.lineWidth = 2
        node.addChild(disc)
        let label = SKLabelNode(text: "$")
        label.fontName = "AvenirNext-Bold"
        label.fontSize = 14
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        node.addChild(label)
        node.position = point
        node.zPosition = 7
        node.run(.repeatForever(.sequence([.scale(to: 1.2, duration: 0.5),
                                           .scale(to: 1.0, duration: 0.5)])))
        worldNode.addChild(node)
        moneyDrops.append((node, amount))
    }

    // MARK: - Touch input → joystick

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard gameState?.phase == .playing, !frozen, let view = view else { return }
        for t in touches where stick.trackedTouch == nil {
            let loc = t.location(in: view)
            if loc.x < view.bounds.width * 0.55 {
                stick.begin(at: uiPoint(for: t), touch: t)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches where t === stick.trackedTouch {
            stick.move(to: uiPoint(for: t))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches where t === stick.trackedTouch { stick.end() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for t in touches where t === stick.trackedTouch { stick.end() }
    }

    /// Touch position in screen points, centred on the camera. `uiNode` is
    /// scaled to match the camera zoom, so these coordinates stay 1:1 with
    /// screen points regardless of zoom.
    private func uiPoint(for touch: UITouch) -> CGPoint {
        guard let view = view else { return .zero }
        let loc = touch.location(in: view)
        return CGPoint(x: loc.x - view.bounds.width / 2,
                       y: view.bounds.height / 2 - loc.y)
    }

    // MARK: - Main loop

    override func update(_ currentTime: TimeInterval) {
        if lastUpdateTime == 0 { lastUpdateTime = currentTime }
        let dt = CGFloat(min(max(currentTime - lastUpdateTime, 0), 1.0 / 30.0))
        lastUpdateTime = currentTime
        clock += TimeInterval(dt)

        let playing = gameState?.phase == .playing && !frozen
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
        // Ambient life keeps running behind the menu for a living backdrop.
        updateTraffic(dt)
        updatePeds(dt)
        updateCamera(dt, playing: playing)
        updateDayNight(dt)
        syncHUD(dt)
    }

    // MARK: - Player: on foot

    private func updateOnFoot(_ dt: CGFloat) {
        guard stick.isActive, stick.magnitude > 0.12 else { return }
        playerHeading = stick.angle
        let maxRun = character == .mia ? GameConfig.runSpeedMia : GameConfig.runSpeedJax
        let step = maxRun * stick.magnitude * dt
        let delta = CGVector(dx: cos(playerHeading) * step, dy: sin(playerHeading) * step)
        let (moved, _) = moveCircle(playerPos, delta: delta, radius: GameConfig.playerRadius)
        playerPos = resolveAgainstCars(moved, radius: GameConfig.playerRadius)
        playerNode.position = playerPos
        playerNode.zRotation = playerHeading
    }

    /// Keeps the on-foot player from walking through parked or moving cars.
    private func resolveAgainstCars(_ p: CGPoint, radius: CGFloat) -> CGPoint {
        var pos = p
        for car in allCars() {
            let minDist = car.collisionRadius + radius + 4
            let d = distance(car.position, pos)
            if d < minDist && d > 0.01 {
                let push = (minDist - d)
                pos.x += (pos.x - car.position.x) / d * push
                pos.y += (pos.y - car.position.y) / d * push
            }
        }
        return clampToWorld(pos, margin: 30)
    }

    private func allCars() -> [Car] {
        var cars = traffic + parked + cops
        if let c = playerCar { cars.append(c) }
        if let m = missionCar, m !== playerCar { cars.append(m) }
        return cars
    }

    // MARK: - Player: driving

    private func updateDriving(_ dt: CGFloat) {
        guard let car = playerCar else { return }
        let kind = car.kind

        if stick.isActive && stick.magnitude > 0.1 && !car.disabled {
            let desired = stick.angle
            let diff = shortestAngle(desired - car.heading)
            if abs(diff) > 2.35 && car.speed < 60 {
                // Pulling hard against the nose at low speed = reverse.
                car.speed = approach(car.speed, -kind.maxSpeed * 0.35,
                                     kind.accel * 1.1, dt)
                car.heading -= clampMag(diff, 1.6 * dt) * 0.6
            } else {
                let target = kind.maxSpeed * stick.magnitude
                let rate = target < car.speed ? kind.accel * 2.6 : kind.accel
                car.speed = approach(car.speed, target, rate, dt)
                let agility = 0.35 + 0.65 * min(1, abs(car.speed) / (kind.maxSpeed * 0.55))
                car.heading += clampMag(diff, kind.turnRate * agility * dt)
            }
        } else {
            car.speed = approach(car.speed, 0, 340, dt)
        }
        if car.disabled { car.speed = approach(car.speed, 0, 500, dt) }

        let delta = CGVector(dx: cos(car.heading) * car.speed * dt,
                             dy: sin(car.heading) * car.speed * dt)
        let (moved, hitWall) = moveCircle(car.position, delta: delta,
                                          radius: kind.width * 0.62)
        car.position = clampToWorld(moved, margin: 50)

        if hitWall && abs(car.speed) > 170 {
            car.applyDamage((abs(car.speed) - 120) * 0.06)
            shakeCamera(intensity: min(10, abs(car.speed) / 60))
            car.speed *= -0.25
        } else if hitWall {
            car.speed = 0
        }

        // Nose probe stops long cars from clipping corners nose-first.
        let nose = CGPoint(x: car.position.x + cos(car.heading) * (kind.length / 2 - 6),
                           y: car.position.y + sin(car.heading) * (kind.length / 2 - 6))
        for rect in city.collisionRects(near: nose) where rect.contains(nose) {
            if abs(car.speed) > 170 { car.applyDamage((abs(car.speed) - 120) * 0.05) }
            car.position = CGPoint(x: car.position.x - cos(car.heading) * abs(car.speed) * dt * 1.2,
                                   y: car.position.y - sin(car.heading) * abs(car.speed) * dt * 1.2)
            car.speed = -car.speed * 0.2
            break
        }

        // Bumping the population.
        for other in traffic {
            if collide(car, with: other) {
                other.brakeTimer = 2
            }
        }
        for other in parked where other !== car {
            collide(car, with: other)
        }
        if let mc = missionCar, mc !== car {
            collide(car, with: mc)
        }
        for ped in peds where ped.state != .down {
            if abs(car.speed) > 90 &&
                distance(ped.position, car.position) < kind.length * 0.45 {
                ped.knockDown()
                dropCash(at: ped.position, amount: ped.wallet / 2)
                crime(1, note: "Hit and run!")
            }
        }

        playerPos = car.position
    }

    /// Push two cars apart and damage both; returns true when they touched.
    @discardableResult
    private func collide(_ a: Car, with b: Car) -> Bool {
        let minDist = (a.kind.length + b.kind.length) * 0.30
        let d = distance(a.position, b.position)
        guard d < minDist, d > 0.01 else { return false }
        let overlap = (minDist - d) / 2
        let nx = (b.position.x - a.position.x) / d
        let ny = (b.position.y - a.position.y) / d
        a.position = CGPoint(x: a.position.x - nx * overlap, y: a.position.y - ny * overlap)
        b.position = CGPoint(x: b.position.x + nx * overlap, y: b.position.y + ny * overlap)
        let impact = abs(a.speed - b.speed)
        if impact > 120 {
            a.applyDamage(impact * 0.035)
            b.applyDamage(impact * 0.05)
            shakeCamera(intensity: min(8, impact / 90))
        }
        a.speed *= 0.72
        b.speed *= 0.72
        return true
    }

    // MARK: - Traffic

    private func updateTraffic(_ dt: CGFloat) {
        trafficSpawnCooldown -= TimeInterval(dt)
        if traffic.count < GameConfig.trafficCount && trafficSpawnCooldown <= 0 {
            trafficSpawnCooldown = 0.25
            spawnTrafficCar()
        }

        var kept: [Car] = []
        for car in traffic {
            if distance(car.position, playerPos) > GameConfig.despawnDistance {
                car.removeFromParent()
                continue
            }
            driveTrafficCar(car, dt)
            kept.append(car)
        }
        traffic = kept
    }

    private static let dirVectors: [CGVector] = [
        CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: 1),
        CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1),
    ]
    private static let dirAngles: [CGFloat] = [0, .pi / 2, .pi, -.pi / 2]

    private func driveTrafficCar(_ car: Car, _ dt: CGFloat) {
        guard !car.disabled else { return }
        let dir = Self.dirVectors[car.dirIndex]
        let horizontal = car.dirIndex % 2 == 0
        car.brakeTimer = max(0, car.brakeTimer - TimeInterval(dt))

        // Brake for anything ahead in the lane.
        var blocked = car.brakeTimer > 0
        if !blocked {
            let lookAhead: CGFloat = 120 + car.speed * 0.3
            blocked = obstacleAhead(of: car, dir: dir, distance: lookAhead)
        }
        let cruise = car.kind.maxSpeed * 0.5
        car.speed = approach(car.speed, blocked ? 0 : cruise,
                             blocked ? 600 : car.kind.accel * 0.7, dt)

        // Advance along the axis; ease laterally onto the lane centre.
        var p = car.position
        p.x += dir.dx * car.speed * dt
        p.y += dir.dy * car.speed * dt
        let laneTarget = trafficLaneTarget(for: car)
        if horizontal {
            p.y += (laneTarget - p.y) * min(1, 6 * dt)
        } else {
            p.x += (laneTarget - p.x) * min(1, 6 * dt)
        }
        car.position = p

        // Face the direction of travel, smoothly.
        let want = Self.dirAngles[car.dirIndex]
        car.heading += clampMag(shortestAngle(want - car.heading), 7 * dt)

        // Intersection reached? Decide where to go next.
        let along = horizontal ? p.x : p.y
        let crossCoord = City.roadCenter(car.crossIndex)
        let step = (car.dirIndex == 0 || car.dirIndex == 1) ? 1 : -1
        if (step > 0 && along >= crossCoord) || (step < 0 && along <= crossCoord) {
            decideTurn(for: car, step: step)
        }
    }

    private func trafficLaneTarget(for car: Car) -> CGFloat {
        let c = City.roadCenter(car.roadIndex)
        switch car.dirIndex {
        case 0: return c - City.laneOffset      // +x drives below the centre line
        case 1: return c + City.laneOffset      // +y drives right of it
        case 2: return c + City.laneOffset
        default: return c - City.laneOffset
        }
    }

    private func decideTurn(for car: Car, step: Int) {
        let k = car.crossIndex          // intersection just reached (on the crossing axis)
        let r = car.roadIndex
        let horizontal = car.dirIndex % 2 == 0

        var options: [(dir: Int, road: Int, cross: Int)] = []
        let straightCross = k + step
        if straightCross >= 0 && straightCross <= City.blocksX {
            options.append((car.dirIndex, r, straightCross))
            options.append((car.dirIndex, r, straightCross))    // straight is likeliest
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

    private func obstacleAhead(of car: Car, dir: CGVector, distance lookAhead: CGFloat) -> Bool {
        func ahead(_ p: CGPoint) -> Bool {
            let dx = p.x - car.position.x
            let dy = p.y - car.position.y
            let along = dx * dir.dx + dy * dir.dy
            let side = abs(dx * dir.dy - dy * dir.dx)
            return along > 20 && along < lookAhead && side < 55
        }
        for other in allCars() where other !== car {
            if ahead(other.position) { return true }
        }
        for ped in peds where ped.state != .down {
            if ahead(ped.position) { return true }
        }
        if playerCar == nil && ahead(playerPos) { return true }
        return false
    }

    private func spawnTrafficCar() {
        guard let (pos, dirIndex, road, cross) = randomLaneSpot() else { return }
        let kind = CarCatalog.traffic[rng.int(0, CarCatalog.traffic.count - 1)]
        let car = Car(kind: kind, color: kind.colors[rng.int(0, kind.colors.count - 1)])
        car.position = pos
        car.dirIndex = dirIndex
        car.roadIndex = road
        car.crossIndex = cross
        car.heading = Self.dirAngles[dirIndex]
        car.driver = .npc
        worldNode.addChild(car)
        traffic.append(car)
    }

    /// A random point on a random lane, inside the spawn ring around the
    /// player and away from their line of sight.
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
            let d = distance(pos, playerPos)
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

    private func makePed() -> Ped {
        let shirts: [SKColor] = [
            SKColor(red: 0.85, green: 0.55, blue: 0.25, alpha: 1),
            SKColor(red: 0.35, green: 0.55, blue: 0.80, alpha: 1),
            SKColor(red: 0.60, green: 0.30, blue: 0.55, alpha: 1),
            SKColor(red: 0.30, green: 0.60, blue: 0.40, alpha: 1),
            SKColor(white: 0.85, alpha: 1),
            SKColor(red: 0.80, green: 0.30, blue: 0.30, alpha: 1),
        ]
        let skins: [SKColor] = [
            SKColor(red: 0.95, green: 0.80, blue: 0.65, alpha: 1),
            SKColor(red: 0.80, green: 0.60, blue: 0.45, alpha: 1),
            SKColor(red: 0.55, green: 0.38, blue: 0.28, alpha: 1),
        ]
        let ped = Ped(shirt: rng.pick(shirts), skin: rng.pick(skins))
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

        var kept: [Ped] = []
        for ped in peds {
            if distance(ped.position, playerPos) > GameConfig.despawnDistance {
                ped.removeFromParent()
                continue
            }
            ped.stateTimer -= TimeInterval(dt)
            switch ped.state {
            case .walk:
                if ped.stateTimer <= 0 {
                    ped.heading = rng.range(-.pi, .pi)
                    ped.stateTimer = TimeInterval(rng.range(1.5, 5))
                }
                stepPed(ped, speed: ped.walkSpeed, dt: dt)
            case .flee:
                if ped.stateTimer <= 0 {
                    ped.state = .walk
                    ped.stateTimer = 2
                }
                stepPed(ped, speed: 130, dt: dt)
            case .down:
                if ped.stateTimer <= 0 {
                    ped.run(.sequence([.fadeOut(withDuration: 0.5), .removeFromParent()]))
                    continue
                }
            }
            kept.append(ped)
        }
        peds = kept
    }

    private func stepPed(_ ped: Ped, speed: CGFloat, dt: CGFloat) {
        let delta = CGVector(dx: cos(ped.heading) * speed * dt,
                             dy: sin(ped.heading) * speed * dt)
        let (moved, hit) = moveCircle(ped.position, delta: delta, radius: 8)
        ped.position = clampToWorld(moved, margin: 24)
        if hit {
            ped.heading = rng.range(-.pi, .pi)
        }
        // Dive out of the way of the player's car.
        if let car = playerCar, abs(car.speed) > 120, ped.state == .walk {
            let toPed = CGVector(dx: ped.position.x - car.position.x,
                                 dy: ped.position.y - car.position.y)
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
        // A wanderable point: inside a block, outside its buildings.
        for _ in 0..<10 {
            let i = rng.int(0, City.blocksX - 1)
            let j = rng.int(0, City.blocksY - 1)
            let rect = City.blockRect(i, j).insetBy(dx: 14, dy: 14)
            let p = CGPoint(x: rng.range(rect.minX, rect.maxX),
                            y: rng.range(rect.minY, rect.maxY))
            let d = distance(p, playerPos)
            guard d > GameConfig.spawnRingMin && d < GameConfig.spawnRingMax else { continue }
            if city.buildings[i][j].contains(where: { $0.rect.insetBy(dx: -10, dy: -10).contains(p) }) {
                continue
            }
            let ped = makePed()
            ped.position = p
            ped.heading = rng.range(-.pi, .pi)
            ped.stateTimer = TimeInterval(rng.range(1, 4))
            worldNode.addChild(ped)
            peds.append(ped)
            return
        }
    }

    // MARK: - Wanted level & police

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
            distance($0.position, playerPos) < GameConfig.copSafeDistance
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
                cop.run(.sequence([.fadeOut(withDuration: 1.2), .removeFromParent()]))
            }
            cops.removeAll()
            arrestProgress = 0
            return
        }

        var arresting = false
        var kept: [Car] = []
        for cop in cops {
            if cop.disabled {
                // A wrecked cruiser lingers as scenery, then clears out —
                // and stops counting against the pursuit, so backup arrives.
                cop.setSiren(false)
                cop.run(.sequence([.wait(forDuration: 20),
                                   .fadeOut(withDuration: 1),
                                   .removeFromParent()]))
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
                busted()
            }
        }
    }

    private func spawnCop() {
        guard let (pos, dirIndex, _, _) = randomLaneSpot() else { return }
        let kind = CarCatalog.police
        let cop = Car(kind: kind, color: kind.colors[0])
        cop.position = pos
        cop.heading = Self.dirAngles[dirIndex]
        cop.driver = .cop
        cop.setSiren(true)
        cop.repathTimer = 0
        worldNode.addChild(cop)
        cops.append(cop)
    }

    private func driveCop(_ cop: Car, _ dt: CGFloat) {
        let toPlayer = distance(cop.position, playerPos)

        cop.repathTimer -= TimeInterval(dt)
        if cop.repathTimer <= 0 || cop.path.isEmpty {
            cop.path = roadPath(from: cop.position, to: playerPos)
            cop.repathTimer = TimeInterval(rng.range(0.8, 1.3))
        }
        if let wp = cop.path.first, distance(cop.position, wp) < 95 {
            cop.path.removeFirst()
        }

        // Close in directly when near; follow the road grid when far.
        let predicted = CGPoint(x: playerPos.x + playerVelocity.dx * 0.35,
                                y: playerPos.y + playerVelocity.dy * 0.35)
        let target = toPlayer < 320 ? predicted : (cop.path.first ?? predicted)

        var targetSpeed = min(cop.kind.maxSpeed, 260 + CGFloat(wanted) * 55)
        if playerCar == nil {
            // Roll up to a stop next to a suspect on foot instead of ramming.
            targetSpeed = min(targetSpeed, max(0, toPlayer - 110) * 1.6)
        }

        let desired = atan2(target.y - cop.position.y, target.x - cop.position.x)
        let diff = shortestAngle(desired - cop.heading)

        if cop.reverseTimer > 0 {
            cop.reverseTimer -= TimeInterval(dt)
            cop.speed = approach(cop.speed, -140, 500, dt)
            cop.heading -= clampMag(diff, 1.4 * dt)
        } else {
            cop.speed = approach(cop.speed, targetSpeed * (abs(diff) > 1.9 ? 0.35 : 1), cop.kind.accel, dt)
            let agility = 0.4 + 0.6 * min(1, abs(cop.speed) / (cop.kind.maxSpeed * 0.5))
            cop.heading += clampMag(diff, cop.kind.turnRate * agility * dt)
        }

        let delta = CGVector(dx: cos(cop.heading) * cop.speed * dt,
                             dy: sin(cop.heading) * cop.speed * dt)
        let (moved, hitWall) = moveCircle(cop.position, delta: delta,
                                          radius: cop.kind.width * 0.62)
        cop.position = clampToWorld(moved, margin: 50)
        if hitWall { cop.speed *= 0.3 }

        // Unstick: reversing for a moment beats spinning wheels forever.
        if abs(cop.speed) < 30 && targetSpeed > 60 && cop.reverseTimer <= 0 {
            cop.stuckTimer += TimeInterval(dt)
            if cop.stuckTimer > 1.6 {
                cop.stuckTimer = 0
                cop.reverseTimer = 0.8
                cop.path = []
            }
        } else {
            cop.stuckTimer = 0
        }

        // Ramming the player's car is the job.
        if let pcar = playerCar {
            collide(cop, with: pcar)
        }
    }

    /// True while this cop is close enough (and the player slow enough)
    /// for the arrest timer to run.
    private func updateArrest(for cop: Car) -> Bool {
        let d = distance(cop.position, playerPos)
        if playerCar == nil {
            let speed = hypot(playerVelocity.dx, playerVelocity.dy)
            return d < GameConfig.arrestDistanceFoot && speed < 70
        } else if let car = playerCar {
            return d < GameConfig.arrestDistanceCar && abs(car.speed) < 50
        }
        return false
    }

    private func updateCopFire(_ cop: Car, _ dt: CGFloat) {
        guard wanted >= 3 else { return }
        let d = distance(cop.position, playerPos)
        guard d < GameConfig.copFireRange else { return }
        // Point blank on foot they arrest, not execute.
        if playerCar == nil && d < GameConfig.arrestDistanceFoot { return }

        cop.fireTimer -= TimeInterval(dt)
        guard cop.fireTimer <= 0 else { return }
        cop.fireTimer = TimeInterval(rng.range(0.9, 1.5))

        let jitter = CGPoint(x: playerPos.x + rng.range(-26, 26),
                             y: playerPos.y + rng.range(-26, 26))
        let path = CGMutablePath()
        path.move(to: cop.position)
        path.addLine(to: jitter)
        let tracer = SKShapeNode(path: path)
        tracer.strokeColor = SKColor(red: 1, green: 0.9, blue: 0.5, alpha: 0.8)
        tracer.lineWidth = 2
        tracer.zPosition = 11
        worldNode.addChild(tracer)
        tracer.run(.sequence([.fadeOut(withDuration: 0.12), .removeFromParent()]))

        if rng.chance(0.65) {
            if let car = playerCar {
                car.applyDamage(4)
                if car.disabled { banner("Your ride is toast — bail out!", seconds: 3) }
            } else {
                damagePlayer(7)
            }
        }
    }

    /// Breadth-first search over the road-intersection grid; keeps pursuit
    /// on the streets instead of nosing into buildings.
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
        if health <= 0 { wasted() }
    }

    private func regenerate(_ dt: CGFloat) {
        if health < 45 && clock - lastDamageTime > 6 {
            health = min(45, health + 2 * dt)
        }
        if distance(playerPos, city.hospital) < 140 && health < GameConfig.maxHealth {
            health = min(GameConfig.maxHealth, health + 14 * dt)
        }
        if let car = playerCar, distance(car.position, city.garage) < 150, car.hp > 0,
           car.hp < car.kind.maxHP {
            car.hp = min(car.kind.maxHP, car.hp + 16 * dt)
        }
    }

    private func busted() {
        guard let state = gameState, state.phase == .playing else { return }
        frozen = true
        stick.end()
        state.phase = .busted
        persist()
    }

    private func wasted() {
        guard let state = gameState, state.phase == .playing else { return }
        frozen = true
        stick.end()
        state.phase = .wasted
        persist()
    }

    // MARK: - Money

    private func collectMoney() {
        guard !moneyDrops.isEmpty else { return }
        var kept: [(node: SKNode, amount: Int)] = []
        for drop in moneyDrops {
            if distance(drop.node.position, playerPos) < 30 {
                cash += drop.amount
                floatText("+$\(drop.amount)", at: drop.node.position,
                          color: SKColor(red: 0.4, green: 0.95, blue: 0.5, alpha: 1))
                drop.node.removeFromParent()
            } else {
                kept.append(drop)
            }
        }
        moneyDrops = kept
    }

    private func floatText(_ text: String, at point: CGPoint, color: SKColor) {
        let label = SKLabelNode(text: text)
        label.fontName = "AvenirNext-Heavy"
        label.fontSize = 22
        label.fontColor = color
        label.position = point
        label.zPosition = 12
        worldNode.addChild(label)
        label.run(.sequence([.group([.moveBy(x: 0, y: 40, duration: 0.9),
                                     .fadeOut(withDuration: 0.9)]),
                             .removeFromParent()]))
    }

    // MARK: - Missions

    private func refreshGiverMarker() {
        giverMarker?.removeFromParent()
        giverMarker = nil
        guard let state = gameState,
              activeMission == nil,
              state.missionsCompleted < missions.count else { return }
        let marker = Markers.giver()
        marker.position = city.missionGiver
        worldNode.addChild(marker)
        giverMarker = marker
    }

    private func updateMission(_ dt: CGFloat) {
        guard let state = gameState else { return }

        if activeMission == nil {
            currentTargetPoint = state.missionsCompleted < missions.count ? city.missionGiver : nil
            if state.missionsCompleted < missions.count,
               distance(playerPos, city.missionGiver) < 80 {
                startMission(missions[state.missionsCompleted])
            }
            return
        }
        guard let mission = activeMission else { return }

        switch mission.objectives[objectiveIndex] {
        case .reach(let wp):
            currentTargetPoint = wp.point
            let carOK = !wp.needsMissionCar || (playerCar != nil && playerCar === missionCar)
            if carOK && distance(playerPos, wp.point) < wp.radius {
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
            if distance(playerPos, wp.point) < wp.radius {
                timedWaypointIndex += 1
                if timedWaypointIndex >= wps.count {
                    advanceObjective()
                } else {
                    moveTargetMarker(to: wps[timedWaypointIndex].point)
                    setObjectiveText("Go to \(wps[timedWaypointIndex].label)")
                }
            }

        case .stealCar(let at, _, _):
            currentTargetPoint = missionCar?.position ?? at
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
        gameState?.missionTitle = mission.title
        setupObjective()
    }

    private func setupObjective() {
        guard let mission = activeMission else { return }
        switch mission.objectives[objectiveIndex] {
        case .reach(let wp):
            moveTargetMarker(to: wp.point)
            setObjectiveText("Go to \(wp.label)")
        case .reachTimed(let wps, let seconds):
            timedRemaining = seconds
            timedWaypointIndex = 0
            moveTargetMarker(to: wps[0].point)
            setObjectiveText("Go to \(wps[0].label)")
        case .stealCar(let at, let kind, let hint):
            let car = Car(kind: kind, color: kind.colors[0])
            car.position = at
            car.heading = rng.pick([0, .pi / 2, .pi, -.pi / 2])
            car.driver = .parked
            worldNode.addChild(car)
            missionCar = car
            moveTargetMarker(to: at)
            setObjectiveText("Steal \(hint)")
        case .survive(let seconds, let stars):
            surviveRemaining = seconds
            crime(stars, note: "The alarm is ringing!")
            removeTargetMarker()
            setObjectiveText("Survive the heat!")
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
        guard let state = gameState else { return }
        cash += mission.reward
        state.missionsCompleted += 1
        clearMission(silently: true)
        banner("MISSION PASSED — +$\(mission.reward)", seconds: 4)
        floatText("+$\(mission.reward)", at: playerPos,
                  color: SKColor(red: 0.4, green: 0.95, blue: 0.5, alpha: 1))
        persist()
        refreshGiverMarker()
        if state.missionsCompleted >= missions.count {
            frozen = true
            stick.end()
            state.phase = .finale
        }
    }

    private func failMission(reason: String?) {
        if let reason {
            banner("MISSION FAILED — \(reason)", seconds: 4)
        }
        clearMission(silently: reason == nil)
        refreshGiverMarker()
    }

    private func clearMission(silently: Bool) {
        activeMission = nil
        objectiveIndex = 0
        removeTargetMarker()
        gameState?.missionTitle = nil
        gameState?.objectiveText = nil
        gameState?.objectiveSecondsLeft = nil
        if let mc = missionCar, mc !== playerCar {
            parked.removeAll { $0 === mc }
            mc.removeFromParent()
        }
        // If the player is sitting in it, it simply becomes an ordinary car.
        missionCar = nil
        currentTargetPoint = nil
    }

    private func moveTargetMarker(to point: CGPoint) {
        removeTargetMarker()
        let marker = Markers.waypoint(color: SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1))
        marker.position = point
        worldNode.addChild(marker)
        targetMarker = marker
    }

    private func removeTargetMarker() {
        targetMarker?.removeFromParent()
        targetMarker = nil
    }

    private func setObjectiveText(_ text: String) {
        gameState?.objectiveText = text
    }

    private func persist() {
        gameState?.cash = cash
        gameState?.persist()
    }

    // MARK: - Camera & atmosphere

    private func updateCamera(_ dt: CGFloat, playing: Bool) {
        if playing {
            var target = playerPos
            if let car = playerCar {
                target.x += cos(car.heading) * min(220, abs(car.speed) * 0.35)
                target.y += sin(car.heading) * min(220, abs(car.speed) * 0.35)
            }
            let k = min(1, 4.5 * dt)
            camNode.position = CGPoint(x: camNode.position.x + (target.x - camNode.position.x) * k,
                                       y: camNode.position.y + (target.y - camNode.position.y) * k)
            let wantScale: CGFloat
            if let car = playerCar {
                wantScale = 1.05 + min(0.55, abs(car.speed) / 640 * 0.6)
            } else {
                wantScale = 0.95
            }
            let s = camNode.xScale + (wantScale - camNode.xScale) * min(1, 2.5 * dt)
            camNode.setScale(s)
        } else if gameState?.phase == .menu {
            // Slow aerial drift over downtown behind the menu.
            let t = CGFloat(clock) * 0.08
            camNode.position = CGPoint(x: city.missionGiver.x + cos(t) * 500,
                                       y: city.missionGiver.y + sin(t * 0.8) * 400)
            camNode.setScale(1.9)
        }
        uiNode.setScale(camNode.xScale)

        // Off-screen objective arrow, hugging a ring around the player.
        if let target = currentTargetPoint, distance(target, playerPos) > 460 {
            targetArrow.isHidden = false
            let a = atan2(target.y - playerPos.y, target.x - playerPos.x)
            targetArrow.position = CGPoint(x: cos(a) * 130, y: sin(a) * 130)
            targetArrow.zRotation = a
        } else {
            targetArrow.isHidden = true
        }
    }

    private func updateDayNight(_ dt: CGFloat) {
        dayClock += TimeInterval(dt)
        let phase = sin(CGFloat(dayClock) * 2 * .pi / 420)     // 7-minute cycle
        nightOverlay.alpha = max(0, -phase) * 0.32
    }

    private func shakeCamera(intensity: CGFloat) {
        let shake = SKAction.sequence([
            .moveBy(x: intensity, y: -intensity, duration: 0.04),
            .moveBy(x: -intensity * 2, y: intensity * 2, duration: 0.05),
            .moveBy(x: intensity, y: -intensity, duration: 0.04),
        ])
        camNode.run(shake)
    }

    // MARK: - HUD sync

    private func banner(_ text: String, seconds: TimeInterval) {
        gameState?.banner = text
        bannerRemaining = seconds
    }

    private func syncHUD(_ dt: CGFloat) {
        if bannerRemaining > 0 {
            bannerRemaining -= TimeInterval(dt)
            if bannerRemaining <= 0 { gameState?.banner = nil }
        }

        hudCooldown -= TimeInterval(dt)
        guard hudCooldown <= 0, let state = gameState else { return }
        hudCooldown = 0.12

        if state.cash != cash { state.cash = cash }
        if abs(state.health - health) > 0.5 { state.health = health }
        if state.wanted != wanted { state.wanted = wanted }
        if state.character != character { state.character = character }

        let inCar = playerCar != nil
        if state.inVehicle != inCar { state.inVehicle = inCar }
        let vName = playerCar?.kind.name
        if state.vehicleName != vName { state.vehicleName = vName }
        if let car = playerCar {
            let frac = max(0, car.hp / car.kind.maxHP)
            if abs(state.vehicleHealth - frac) > 0.02 { state.vehicleHealth = frac }
            let kmh = Int(abs(car.speed) * 0.22)
            if state.speedKMH != kmh { state.speedKMH = kmh }
        } else if state.speedKMH != 0 {
            state.speedKMH = 0
        }

        let canEnter = !inCar && enterableCar() != nil
        if state.canEnterVehicle != canEnter { state.canEnterVehicle = canEnter }

        let district = city.districtName(at: playerPos)
        if state.districtName != district { state.districtName = district }

        var secondsLeft: Int?
        if let mission = activeMission {
            switch mission.objectives[objectiveIndex] {
            case .reachTimed: secondsLeft = max(0, Int(timedRemaining.rounded(.up)))
            case .survive: secondsLeft = max(0, Int(surviveRemaining.rounded(.up)))
            default: secondsLeft = nil
            }
        }
        if state.objectiveSecondsLeft != secondsLeft { state.objectiveSecondsLeft = secondsLeft }

        state.minimap = MinimapSnapshot(
            player: playerPos,
            heading: playerCar?.heading ?? playerHeading,
            cops: cops.filter { !$0.disabled }.map { $0.position },
            target: currentTargetPoint,
            giver: giverMarker != nil ? city.missionGiver : nil)
    }

    // MARK: - Geometry helpers

    /// Move a circle, resolving each axis separately against nearby building
    /// rects and the world edge. Returns the resolved point and whether it hit.
    private func moveCircle(_ p: CGPoint, delta: CGVector, radius: CGFloat) -> (CGPoint, Bool) {
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

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
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
