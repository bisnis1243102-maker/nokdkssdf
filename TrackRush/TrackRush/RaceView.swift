import SwiftUI
import SpriteKit

/// The race screen: the SpriteKit scene, a thin HUD, and the hold-to-act
/// controls. Everything the player touches lives here.
struct RaceView: View {
    let track: Track
    @ObservedObject var store: GameStore
    @Environment(\.dismiss) private var dismiss

    /// Built once, in init.
    ///
    /// This used to be created inside a GeometryReader, which was a real bug:
    /// `ignoresSafeArea` makes the SpriteView bigger than the geometry, and
    /// `resizeFill` then rewrites `scene.size` to the view's size, so the
    /// "have I already got a scene this size?" check never matched. With the
    /// HUD re-rendering sixty times a second, that built a fresh scene every
    /// frame and the controls ended up writing to a scene nobody was watching.
    @State private var scene: GameScene
    @State private var progress: Double = 0
    @State private var elapsed: TimeInterval = 0
    @State private var speed: Double = 0
    @State private var outcome: Outcome?

    private enum Outcome: Equatable {
        case crashed
        case finished(time: TimeInterval, isBest: Bool)
    }

    init(track: Track, store: GameStore) {
        self.track = track
        self.store = store
        _scene = State(initialValue: GameScene(track: track, size: UIScreen.main.bounds.size))
    }

    var body: some View {
        ZStack {
            SpriteView(scene: scene)
                .ignoresSafeArea()

            VStack {
                hud
                Spacer()
                if outcome == nil { controls }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 26)

            if let outcome { resultOverlay(outcome) }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { attachCallbacks(to: scene) }
    }

    private func attachCallbacks(to scene: GameScene) {
        scene.onTick = { progress, elapsed, speed in
            self.progress = progress
            self.elapsed = elapsed
            self.speed = speed
        }
        scene.onCrash = {
            guard outcome == nil else { return }
            withAnimation(.spring(response: 0.35)) { outcome = .crashed }
        }
        scene.onFinish = { time in
            guard outcome == nil else { return }
            let isBest = store.record(time: time, for: track)
            withAnimation(.spring(response: 0.35)) {
                outcome = .finished(time: time, isBest: isBest)
            }
        }
    }

    // MARK: HUD

    private var hud: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.black.opacity(0.35)))
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(GameStore.timeText(elapsed))
                        .font(.system(size: 19, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    if let best = store.best(for: track) {
                        Text("best \(GameStore.timeText(best))")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(Palette.accent.opacity(0.9))
                    }
                    Spacer()
                    Text("\(Int(abs(speed) / 5.2)) km/h")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.75))
                }

                // Progress along the track.
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.black.opacity(0.35))
                        Capsule().fill(Palette.accent)
                            .frame(width: max(6, geometry.size.width * progress))
                    }
                }
                .frame(height: 6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.28)))
        }
        .padding(.top, 12)
    }

    // MARK: Controls

    private var controls: some View {
        HStack(alignment: .bottom) {
            VStack(spacing: 12) {
                holdButton(icon: "arrow.counterclockwise", label: "LEAN BACK", tint: .white) { down in
                    scene.leanInput = down ? 1 : 0
                }
                holdButton(icon: "arrow.clockwise", label: "LEAN FWD", tint: .white) { down in
                    scene.leanInput = down ? -1 : 0
                }
            }

            Spacer()

            HStack(spacing: 14) {
                holdButton(icon: "backward.fill", label: "BRAKE", tint: .red.opacity(0.9)) { down in
                    scene.brake = down
                }
                holdButton(icon: "bolt.fill", label: "GAS", tint: Palette.accent, large: true) { down in
                    scene.throttle = down
                }
            }
        }
    }

    private func holdButton(icon: String, label: String, tint: Color,
                            large: Bool = false,
                            action: @escaping (Bool) -> Void) -> some View {
        let size: CGFloat = large ? 92 : 66
        return VStack(spacing: 4) {
            ZStack {
                Circle().fill(.black.opacity(0.34))
                Circle().stroke(tint.opacity(0.75), lineWidth: 2)
                Image(systemName: icon)
                    .font(.system(size: large ? 30 : 20, weight: .bold))
                    .foregroundColor(tint)
            }
            .frame(width: size, height: size)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white.opacity(0.55))
        }
        // A plain Button only fires on release; a race needs press-and-hold.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in action(true) }
                .onEnded { _ in action(false) }
        )
    }

    // MARK: Result

    private func resultOverlay(_ outcome: Outcome) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: 16) {
                switch outcome {
                case .crashed:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.orange)
                    Text("Crashed")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("\(Int(progress * 100))% of the track")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.65))

                case .finished(let time, let isBest):
                    Image(systemName: isBest ? "trophy.fill" : "flag.checkered")
                        .font(.system(size: 36))
                        .foregroundColor(isBest ? Palette.accent : .white)
                    Text(isBest ? "New best time" : "Finished")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text(GameStore.timeText(time))
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundColor(Palette.accent)
                }

                HStack(spacing: 12) {
                    Button {
                        retry()
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.system(size: 15, weight: .bold))
                            .padding(.horizontal, 20).padding(.vertical, 13)
                            .background(Capsule().fill(Palette.accent))
                            .foregroundColor(.black)
                    }
                    .buttonStyle(.plain)

                    Button {
                        dismiss()
                    } label: {
                        Label("Tracks", systemImage: "list.bullet")
                            .font(.system(size: 15, weight: .bold))
                            .padding(.horizontal, 20).padding(.vertical, 13)
                            .background(Capsule().fill(.white.opacity(0.16)))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.55)))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.12), lineWidth: 1))
        }
    }

    /// Replaces the scene wholesale, which is the simplest way to guarantee a
    /// run starts from an identical state every time.
    private func retry() {
        progress = 0
        elapsed = 0
        speed = 0
        outcome = nil
        let fresh = GameScene(track: track, size: scene.size)
        attachCallbacks(to: fresh)
        scene = fresh
    }
}
