import SwiftUI
import SpriteKit

/// Hosts the SpriteKit race and draws the HUD and touch controls over it.
struct RaceView: View {
    @EnvironmentObject var game: GameState
    let ref: GameState.CareerTrackRef

    @StateObject private var hud = RaceHUD()
    @State private var scene: RaceScene?
    @State private var paused = false
    @State private var runId = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let s = scene {
                    SpriteView(scene: s, preferredFramesPerSecond: 120)
                        .ignoresSafeArea()
                        .id(runId)
                } else {
                    Theme.bg.ignoresSafeArea()
                }

                hudLayer
                controlLayer

                if hud.countdown > 0 && !hud.racing {
                    Text("\(hud.countdown)")
                        .font(.system(size: 96, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.6), radius: 12, y: 6)
                        .transition(.scale)
                        .id(hud.countdown)
                }

                if !hud.message.isEmpty {
                    Text(hud.message)
                        .font(.system(size: hud.messageKind == "big" ? 44 : 26,
                                      weight: .black, design: .rounded))
                        .foregroundColor(messageColor)
                        .shadow(color: .black.opacity(0.7), radius: 10, y: 4)
                        .offset(y: -geo.size.height * 0.16)
                        .transition(.opacity)
                        .id(hud.message)
                }

                if paused { pauseOverlay }
            }
            .onAppear { buildSceneIfNeeded(size: geo.size) }
            .onChange(of: runId) { _ in rebuild(size: geo.size) }
        }
        .statusBarHidden(true)
    }

    private var messageColor: Color {
        switch hud.messageKind {
        case "good": return Theme.green
        case "bad": return Theme.red
        default: return .white
        }
    }

    /// Instant restart: drop the old scene and build a fresh one on the same
    /// track, exactly as it was at the gate.
    private func rebuild(size: CGSize) {
        scene?.isPaused = true
        scene = nil
        hud.finished = false
        hud.racing = false
        hud.message = ""
        paused = false
        buildSceneIfNeeded(size: size)
    }

    private func buildSceneIfNeeded(size: CGSize) {
        guard scene == nil else { return }
        let career = game.trackFor(ref)
        let track = Track(seed: career.seed, biomeKey: career.biome, difficulty: career.difficulty)
        let s = RaceScene(size: size)
        s.scaleMode = .resizeFill
        s.track = track
        s.playerSpec = game.currentSpec
        s.playerUpgrades = game.currentUpgrades
        s.playerName = game.profile.name
        s.playerNumber = game.profile.number
        s.difficulty = career.difficulty
        let isJam = ref.regionId == "jam"
        s.aiCount = isJam ? 0 : 5
        s.assistLanding = game.profile.assistLanding
        s.ghostFrames = game.ghost(for: career.id)
        s.hud = hud
        Haptics.enabled = game.profile.hapticsOn
        s.onFinish = { outcome in
            let posBonus = [1.0, 0.75, 0.6, 0.5, 0.42, 0.36]
            let mult = outcome.position <= posBonus.count ? posBonus[outcome.position - 1] : 0.3
            var coins = Int((220 + career.difficulty * 420 + Double(outcome.perfects) * 28) * mult)
            var xp = Int((60 + career.difficulty * 120 + Double(outcome.style) * 0.4) * mult)
            if outcome.beatGhost { coins += 150; xp += 40 }
            let result = RaceResult(trackId: career.id,
                                    regionId: ref.regionId,
                                    trackName: career.name,
                                    position: outcome.position,
                                    fieldSize: isJam ? 1 : 6,
                                    time: outcome.time,
                                    perfects: outcome.perfects,
                                    crashes: outcome.crashes,
                                    airTime: outcome.airTime,
                                    style: outcome.style,
                                    coins: coins,
                                    xp: xp,
                                    beatGhost: outcome.beatGhost,
                                    order: outcome.order)
            // Keep the ghost only when the run was actually an improvement.
            let previousBest = game.profile.bestTimes[career.id]
            if previousBest == nil || outcome.time < (previousBest ?? .infinity) {
                game.storeGhost(outcome.ghost, for: career.id)
            }
            DispatchQueue.main.async {
                game.apply(result: result)
                game.pendingResult = result
                game.screen = .podium
            }
        }
        scene = s
    }

    // MARK: HUD

    private var hudLayer: some View {
        VStack {
            HStack(alignment: .top, spacing: 8) {
                hudChip(label: "POS", value: "\(hud.position)/\(hud.fieldSize)")
                hudChip(label: "TRACK", value: "\(Int(hud.progress * 100))%")
                hudChip(label: "TIME", value: fmtTime(hud.time))
                hudChip(label: "STYLE", value: "\(hud.style)")
                if hud.hasGhost {
                    hudChip(label: "GHOST",
                            value: String(format: "%+.2f", -hud.ghostGap),
                            tint: hud.ghostGap >= 0 ? Theme.green : Theme.red)
                }
                Spacer()
                Button {
                    Haptics.select()
                    runId += 1
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
                Button {
                    paused = true
                    scene?.isPaused = true
                } label: {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.45)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(hud.standings.enumerated()), id: \.offset) { idx, entry in
                        HStack(spacing: 6) {
                            Text("\(idx + 1)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                                .frame(width: 12)
                            Text(entry.0)
                                .font(.system(size: 12, weight: entry.1 ? .black : .semibold))
                                .foregroundColor(entry.1 ? Theme.gold : .white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.35)))
                    }
                }
                Spacer()
                speedo
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)

            Spacer()
        }
    }

    private var speedo: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.45)).frame(width: 96, height: 96)
            Circle()
                .trim(from: 0, to: min(1, Double(hud.speedKmh) / 190))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 88, height: 88)
            VStack(spacing: 0) {
                Text("\(hud.speedKmh)")
                    .font(.system(size: 27, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                Text("km/h")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
                Text("G\(hud.gear)")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(Theme.gold)
            }
        }
    }

    private func hudChip(label: String, value: String, tint: Color = .white) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .foregroundColor(.white.opacity(0.6))
            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.45)))
    }

    // MARK: Controls

    private var controlLayer: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        ControlButton(label: "WHIP L", small: true) { down in
                            scene?.controls.whip = down ? -1 : 0
                        }
                        ControlButton(label: "WHIP R", small: true) { down in
                            scene?.controls.whip = down ? 1 : 0
                        }
                    }
                    HStack(spacing: 10) {
                        ControlButton(label: "LEAN\nBACK", tint: Theme.cyan.opacity(0.35)) { down in
                            scene?.controls.lean = down ? -1 : 0
                        }
                        ControlButton(label: "LEAN\nFWD", tint: Theme.cyan.opacity(0.35)) { down in
                            scene?.controls.lean = down ? 1 : 0
                        }
                    }
                }
                Spacer()
                VStack(spacing: 10) {
                    ControlButton(label: "BRAKE", tint: Color.white.opacity(0.18)) { down in
                        scene?.controls.brake = down ? 1 : 0
                    }
                    ControlButton(label: "THROTTLE", tint: Theme.accent.opacity(0.85), big: true) { down in
                        scene?.controls.throttle = down ? 1 : 0
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
    }

    private var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("PAUSED")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                PillButton(title: "Resume") {
                    paused = false
                    scene?.isPaused = false
                }
                PillButton(title: "Restart", tint: Theme.panelHi, textColor: .white) {
                    runId += 1
                }
                PillButton(title: "Quit to Career", tint: Theme.red, textColor: .white) {
                    scene?.isPaused = false
                    game.screen = .career
                }
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.panel))
        }
    }
}

/// A hold-to-press control. `onChange(true)` on touch down, `false` on release.
struct ControlButton: View {
    let label: String
    var tint: Color = Color.white.opacity(0.16)
    var small: Bool = false
    var big: Bool = false
    let onChange: (Bool) -> Void

    @State private var pressed = false

    var body: some View {
        Text(label)
            .font(.system(size: small ? 11 : 13, weight: .black))
            .multilineTextAlignment(.center)
            .foregroundColor(.white)
            .frame(width: small ? 76 : (big ? 132 : 104),
                   height: small ? 40 : (big ? 76 : 56))
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(tint)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.25)))
            )
            .scaleEffect(pressed ? 0.93 : 1)
            .animation(.easeOut(duration: 0.08), value: pressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressed {
                            pressed = true
                            Haptics.light()
                            onChange(true)
                        }
                    }
                    .onEnded { _ in
                        pressed = false
                        onChange(false)
                    }
            )
    }
}

func fmtTime(_ t: Double) -> String {
    guard t.isFinite, t >= 0 else { return "—" }
    let m = Int(t) / 60
    let s = t - Double(m) * 60
    return String(format: "%d:%05.2f", m, s)
}
