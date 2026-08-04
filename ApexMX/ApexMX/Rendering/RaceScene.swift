import SpriteKit

/// The SpriteKit scene that presents a race.
///
/// The scene is strictly a *view* of the simulation. It owns no gameplay state,
/// makes no gameplay decisions, and never writes back into the physics — it
/// reads `RaceSession` each frame and mirrors it. That separation is what lets
/// the same session be driven headlessly for balance passes, or re-driven from
/// a replay, with no rendering involved at all.
public final class RaceScene: SKScene {

    private let session: RaceSession
    private let palette: EnvironmentPalette

    private var backdrop: BackdropNode?
    private var terrainNode: TerrainNode?
    private var particles = ParticleField()
    private var bikeNodes: [Int: BikeNode] = [:]
    private var ghostNode: BikeNode?

    private var raceCamera = RaceCamera()
    private let cameraNode = SKCameraNode()
    private var lastUpdateTime: TimeInterval = 0

    /// Ghost the player is racing against, if any.
    public var ghost: GhostPlayer?

    /// Mirrors accessibility and quality settings into the presentation layer.
    public var settings: GameSettings = GameSettings() {
        didSet { applySettings() }
    }

    public init(session: RaceSession, size: CGSize) {
        self.session = session
        self.palette = EnvironmentPalette.make(for: session.track)
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = palette.skyHorizon
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("RaceScene is created in code only") }

    // MARK: - Lifecycle

    public override func didMove(to view: SKView) {
        removeAllChildren()

        camera = cameraNode
        addChild(cameraNode)

        let backdrop = BackdropNode(track: session.track, palette: palette, size: size)
        addChild(backdrop)
        self.backdrop = backdrop

        let terrainNode = TerrainNode(terrain: session.terrain, palette: palette)
        addChild(terrainNode)
        self.terrainNode = terrainNode

        addChild(particles)
        buildRiderNodes()
        applySettings()
    }

    public override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        backdrop?.resize(to: size)
    }

    private func buildRiderNodes() {
        for (_, node) in bikeNodes { node.removeFromParent() }
        bikeNodes.removeAll()

        for rider in session.riders {
            let node = BikeNode(spec: rider.bike.spec,
                                liveryHue: rider.liveryHue,
                                isPlayer: rider.isPlayer)
            addChild(node)
            bikeNodes[rider.id] = node
        }

        if let ghost = ghost {
            let node = BikeNode(spec: ghost.bike.spec, liveryHue: 0.55, isPlayer: false)
            node.alpha = 0.38
            node.zPosition = 50
            addChild(node)
            ghostNode = node
        }
    }

    private func applySettings() {
        raceCamera.reduceMotion = settings.reduceMotion
        // Quality tiers trade particle density for frame time. The simulation is
        // untouched, so a battery-saver run is not an easier or harder race.
        switch settings.graphicsQuality {
        case .battery:
            particles.isHidden = true
        case .balanced, .quality, .automatic:
            particles.isHidden = false
        }
    }

    // MARK: - Frame loop

    public override func update(_ currentTime: TimeInterval) {
        // The first frame has no previous timestamp to difference against.
        if lastUpdateTime == 0 { lastUpdateTime = currentTime }
        let deltaTime = min(currentTime - lastUpdateTime, 0.25)
        lastUpdateTime = currentTime
        guard deltaTime > 0 else { return }

        session.update(deltaTime: deltaTime)
        if let ghost { advanceGhost(ghost, dt: deltaTime) }

        syncRiders()
        emitEffects(dt: deltaTime)
        updateCamera(dt: deltaTime)
        particles.update(dt: CGFloat(deltaTime))
    }

    private func advanceGhost(_ ghost: GhostPlayer, dt: Double) {
        // The ghost is stepped at the same fixed rate as the race so its run
        // reproduces exactly rather than drifting with frame rate.
        let step = 1.0 / 240.0
        var remaining = dt
        while remaining > 0 {
            ghost.step(dt: min(step, remaining), terrain: session.terrain)
            remaining -= step
        }
    }

    private func syncRiders() {
        for rider in session.riders {
            bikeNodes[rider.id]?.sync(with: rider.bike)
        }
        if let ghost = ghost {
            ghostNode?.sync(with: ghost.bike)
        }
    }

    private func updateCamera(dt: Double) {
        guard let player = session.player else { return }
        let viewportHeight = RenderScale.metres(size.height)
        let frame = raceCamera.update(dt: dt,
                                      bike: player.bike,
                                      terrain: session.terrain,
                                      viewportHeightMetres: viewportHeight)
        cameraNode.position = frame.position
        cameraNode.setScale(frame.scale)

        let visibleWidth = RenderScale.metres(size.width) * Double(frame.scale)
        terrainNode?.update(cameraX: RenderScale.metres(frame.position.x),
                            visibleWidth: visibleWidth)
        backdrop?.update(cameraPosition: frame.position)
    }

    /// Turns physics events into visual feedback.
    ///
    /// Every effect here is driven by a quantity the solver already computes —
    /// slip ratio, suspension load, landing impact — so what the player sees is
    /// a readout of the simulation, not decoration layered on top of it. Roost
    /// off the rear wheel genuinely means the tyre is spinning.
    private func emitEffects(dt: Double) {
        guard !particles.isHidden else { return }
        let densityScale: Double = settings.graphicsQuality == .quality ? 1.4 : 1.0

        for rider in session.riders {
            let bike = rider.bike

            // Roost: thrown backward from a spinning rear tyre.
            let rear = bike.rearWheel
            if rear.isGrounded && rear.slipRatio > 0.12 {
                let intensity = MathUtils.clamp01(rear.slipRatio * 1.4)
                let count = Int((intensity * 6 * densityScale).rounded())
                particles.emit(at: rear.contactPoint,
                               direction: Vector2(-6 - bike.forwardSpeed * 0.35, 3.5),
                               spread: 0.45,
                               count: count,
                               surface: rear.surface,
                               intensity: intensity)
            }

            // Dust kicked up simply by rolling over loose ground at speed.
            if rear.isGrounded && bike.forwardSpeed > 6 {
                let looseness = rear.surface.properties.deformability
                if looseness > 0.4 {
                    let intensity = MathUtils.clamp01(bike.forwardSpeed / 30 * looseness)
                    let count = Int((intensity * 2 * densityScale).rounded())
                    particles.emit(at: rear.contactPoint,
                                   direction: Vector2(-2.5, 1.6),
                                   spread: 0.7,
                                   count: count,
                                   surface: rear.surface,
                                   intensity: intensity * 0.6)
                }
            }

            // Landing debris, scaled by how hard the bike actually hit.
            if bike.didLandThisStep {
                let intensity = MathUtils.clamp01(bike.lastLandingImpact / 12)
                let count = Int((6 + intensity * 16) * densityScale)
                particles.emit(at: bike.rearWheel.contactPoint,
                               direction: Vector2(-3, 5.5 + intensity * 5),
                               spread: 1.2,
                               count: count,
                               surface: bike.rearWheel.surface,
                               intensity: intensity)
            }

            // Front-wheel dust under heavy braking.
            let front = bike.frontWheel
            if front.isGrounded && front.slipRatio < -0.15 && bike.forwardSpeed > 4 {
                let intensity = MathUtils.clamp01(-front.slipRatio)
                particles.emit(at: front.contactPoint,
                               direction: Vector2(1.5, 2.0),
                               spread: 0.6,
                               count: Int((intensity * 3 * densityScale).rounded()),
                               surface: front.surface,
                               intensity: intensity * 0.7)
            }
        }
        _ = dt
    }

    // MARK: - External control

    /// Clears transient visuals and re-frames the camera for a fresh start.
    public func prepareForRestart() {
        particles.clear()
        raceCamera.snap()
        if let ghost = ghost {
            ghost.reset(on: session.terrain, atX: TrackBuilder.startPadding)
        }
    }
}
