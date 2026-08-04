import SpriteKit
import SwiftUI

/// The race screen: the SpriteKit scene, the controls and the HUD.
///
/// SwiftUI owns the interface, SpriteKit owns the rendering, and the two meet
/// only through the `RaceSession` — SwiftUI writes `playerInput` into it and
/// reads a `HUDSnapshot` back out. Neither framework drives the other's frame
/// loop, which avoids the layout thrash that comes from rebuilding a view tree
/// at simulation rate.
@MainActor
public struct RaceView: View {

    @EnvironmentObject private var coordinator: GameCoordinator
    @StateObject private var controls = TouchControlState()
    @State private var scene: RaceScene?
    @State private var snapshot = HUDSnapshot()
    @State private var isPaused = false
    @State private var lastSampleTime = Date()

    /// The HUD is refreshed on a timer rather than every physics step: 20 Hz is
    /// past the point where a human reads a changing number, and it keeps
    /// SwiftUI's work off the critical path.
    private let hudTimer = Timer.publish(every: 1.0 / 20.0, on: .main, in: .common).autoconnect()
    /// Controls are resolved more often than the HUD, because input latency is
    /// felt directly.
    private let inputTimer = Timer.publish(every: 1.0 / 120.0, on: .main, in: .common).autoconnect()

    public init() {}

    public var body: some View {
        ZStack {
            sceneLayer
            RaceHUDView(snapshot: snapshot,
                        settings: coordinator.profile.settings,
                        onPause: pause,
                        onRecover: { coordinator.session?.requestPlayerRecovery() })
            controlLayer
            if coordinator.profile.settings.developerOverlay {
                DeveloperOverlayView(session: coordinator.session)
            }
            if isPaused { pauseMenu }
        }
        .background(Theme.Palette.background)
        .ignoresSafeArea()
        .statusBarHidden()
        .onAppear(perform: configureScene)
        .onDisappear { controls.releaseAll() }
        .onReceive(inputTimer) { _ in resolveInput() }
        .onReceive(hudTimer) { _ in refreshSnapshot() }
    }

    // MARK: - Layers

    @ViewBuilder
    private var sceneLayer: some View {
        if let scene {
            SpriteView(scene: scene,
                       preferredFramesPerSecond: preferredFPS,
                       options: [.ignoresSiblingOrder],
                       debugOptions: [])
                .ignoresSafeArea()
        } else {
            Color.black
        }
    }

    private var controlLayer: some View {
        HStack {
            VStack(spacing: Theme.Spacing.md) {
                Spacer()
                ControlPad(label: "LEAN BACK",
                           systemImage: "arrow.uturn.left",
                           tint: Theme.Palette.info,
                           isActive: controls.leanDirection < -0.5,
                           size: 82) { down in
                    controls.leanDirection = down ? -1 : 0
                }
                ControlPad(label: "LEAN FWD",
                           systemImage: "arrow.uturn.right",
                           tint: Theme.Palette.info,
                           isActive: controls.leanDirection > 0.5,
                           size: 82) { down in
                    controls.leanDirection = down ? 1 : 0
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: Theme.Spacing.md) {
                Spacer()
                HStack(spacing: Theme.Spacing.md) {
                    ControlPad(label: "F.BRAKE",
                               systemImage: "hand.raised.fill",
                               tint: Theme.Palette.danger,
                               isActive: controls.isFrontBrakeDown,
                               size: 72) { controls.isFrontBrakeDown = $0 }
                    ControlPad(label: "R.BRAKE",
                               systemImage: "hand.raised",
                               tint: Theme.Palette.warning,
                               isActive: controls.isRearBrakeDown,
                               size: 72) { controls.isRearBrakeDown = $0 }
                    ControlPad(label: "THROTTLE",
                               systemImage: "bolt.fill",
                               tint: Theme.Palette.accent,
                               isActive: controls.isThrottleDown,
                               size: 104) { controls.isThrottleDown = $0 }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.md)
        // Mirror the layout for left-handed players.
        .environment(\.layoutDirection,
                      coordinator.profile.settings.throttleOnRight ? .leftToRight : .rightToLeft)
    }

    private var pauseMenu: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            Panel(padding: Theme.Spacing.lg) {
                VStack(spacing: Theme.Spacing.md) {
                    Text("Paused")
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    PrimaryButton("Resume", systemImage: "play.fill") { resume() }
                    SecondaryButton("Restart race", systemImage: "arrow.counterclockwise") {
                        coordinator.restartRace()
                        scene?.prepareForRestart()
                        resume()
                    }
                    SecondaryButton("Quit to menu", systemImage: "xmark") {
                        controls.releaseAll()
                        coordinator.abandonRace()
                    }
                }
                .frame(width: 300)
            }
        }
        .transition(.opacity)
    }

    // MARK: - Wiring

    private func configureScene() {
        guard scene == nil, let session = coordinator.session else { return }
        let size = UIScreen.main.bounds.size
        let newScene = RaceScene(session: session, size: size)
        newScene.settings = coordinator.profile.settings
        newScene.ghost = coordinator.makeGhostPlayer()
        scene = newScene
        HapticEngine.shared.applySettings(coordinator.profile.settings)
        HapticEngine.shared.prepare()
    }

    /// Automatic means "whatever this display can do" — on a 120 Hz device
    /// that is 120, not SpriteKit's 60-frame default.
    private var preferredFPS: Int {
        coordinator.profile.settings.frameRateCap.preferredFPS
            ?? UIScreen.main.maximumFramesPerSecond
    }

    private func resolveInput() {
        guard let session = coordinator.session, !isPaused else { return }
        let now = Date()
        let dt = min(now.timeIntervalSince(lastSampleTime), 0.1)
        lastSampleTime = now
        session.playerInput = controls.resolve(dt: dt,
                                               invertLean: coordinator.profile.settings.invertLeanControls)
    }

    private func pause() {
        controls.releaseAll()
        withAnimation(Theme.Motion.quick) { isPaused = true }
        scene?.isPaused = true
    }

    private func resume() {
        lastSampleTime = Date()
        scene?.isPaused = false
        withAnimation(Theme.Motion.quick) { isPaused = false }
    }

    /// Samples the session into the HUD's value type and fires feedback for any
    /// events that happened since the last sample.
    private func refreshSnapshot() {
        guard let session = coordinator.session, let player = session.player else { return }
        var next = HUDSnapshot()
        let bike = player.bike

        next.speedKPH = max(bike.speedKPH, 0)
        next.position = session.playerPosition
        next.fieldSize = session.riders.count
        next.lap = min(player.lap, session.track.laps)
        next.totalLaps = session.track.laps
        next.raceTime = session.raceTime
        next.isAirborne = bike.isAirborne
        next.airTime = bike.airTime
        next.lastLapTime = player.lapTimes.last
        next.bestLapTime = player.bestLapTime

        let lapProgress = (bike.position.x - TrackBuilder.startPadding) / max(session.track.lapLength, 1)
        next.lapProgress = MathUtils.clamp01(lapProgress)

        if case let .countdown(remaining) = session.phase {
            next.countdown = remaining
        } else if session.raceTime >= 0 && session.raceTime < 0.8 {
            next.countdown = 0
        }

        if bike.hasCrashed, let reason = bike.crashReason {
            next.crashReason = reason.rawValue
            next.crashAdvice = reason.advice
        }
        next.isFinished = player.hasFinished

        fireFeedback(previous: snapshot, next: next, bike: bike)
        snapshot = next
    }

    /// Converts state changes into haptics. Driven off the snapshot rather than
    /// the physics so a dropped frame cannot produce a burst of buzzes.
    private func fireFeedback(previous: HUDSnapshot, next: HUDSnapshot, bike: BikePhysicsBody) {
        if next.crashReason != nil && previous.crashReason == nil {
            HapticEngine.shared.failure()
        } else if previous.isAirborne && !next.isAirborne {
            HapticEngine.shared.impact(MathUtils.clamp01(bike.lastLandingImpact / 12))
        }
        if next.isFinished && !previous.isFinished {
            HapticEngine.shared.success()
        }
    }
}
