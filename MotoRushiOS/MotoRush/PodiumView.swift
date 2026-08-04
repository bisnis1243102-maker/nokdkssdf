import SwiftUI

/// Post-race podium. The top three stand on blocks, the daily goal ticks over
/// in the corner, and the rewards summarise the run.
struct PodiumView: View {
    @EnvironmentObject var game: GameState
    @State private var appear = false

    private var result: RaceResult? { game.pendingResult }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#221A14"), Color(hex: "#0C0A0E")],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            // Celebration rays behind the winner.
            if let r = result, r.position == 1 {
                RaysView()
                    .frame(width: 520, height: 520)
                    .opacity(appear ? 0.55 : 0)
                    .scaleEffect(appear ? 1 : 0.7)
                    .animation(.easeOut(duration: 0.7), value: appear)
                    .offset(y: -30)
            }

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                podium
                rewards
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            VStack {
                HStack {
                    Spacer()
                    dailyGoalCard
                }
                Spacer()
            }
            .padding(16)
        }
        .onAppear { appear = true }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text((result?.trackName ?? "RACE").uppercased())
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 34)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.75))
            HStack(spacing: 26) {
                ForEach(Array(topThree().enumerated()), id: \.offset) { idx, name in
                    Text(name)
                        .font(.system(size: 15, weight: .heavy))
                        .italic()
                        .foregroundColor(name == "You" ? Theme.gold : .white)
                }
            }
            .padding(.top, 2)
        }
    }

    /// Displayed left-to-right as 2nd, 1st, 3rd — the order they stand in.
    private func topThree() -> [String] {
        guard let r = result else { return [] }
        let names = r.order.map { $0.0 }
        var out: [String] = []
        if names.count > 1 { out.append(names[1]) }
        if names.count > 0 { out.append(names[0]) }
        if names.count > 2 { out.append(names[2]) }
        return out
    }

    private var podium: some View {
        ShowcaseView(content: .podium(tints: jerseyTints, playerPlace: result?.position ?? 0),
                     spins: false)
            .frame(height: 280)
            .padding(.bottom, 4)
    }

    /// One jersey colour per place, with the player in the game's accent so
    /// they are findable on the blocks at a glance.
    private var jerseyTints: [String] {
        let palette = ["#2E6BFF", "#2BD9E0", "#B7F04A"]
        guard let r = result else { return palette }
        return (0..<3).map { idx in
            let names = r.order.map { $0.0 }
            if idx < names.count, names[idx] == "You" { return "#FF5D3B" }
            return palette[idx]
        }
    }

    private var dailyGoalCard: some View {
        VStack(spacing: 4) {
            Text("DAILY GOAL")
                .font(.system(size: 15, weight: .black))
                .foregroundColor(.white)
            Text(DailyGoal.text(game.profile.dailyGoalKind))
                .font(.system(size: 14, weight: .heavy))
                .foregroundColor(Theme.gold)
            Text("\(min(game.profile.dailyGoalProgress, game.dailyGoalTarget))/\(game.dailyGoalTarget)")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            ProgressView(value: Double(min(game.profile.dailyGoalProgress, game.dailyGoalTarget)),
                         total: Double(game.dailyGoalTarget))
                .tint(Theme.green)
                .frame(width: 130)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.72)))
    }

    private var rewards: some View {
        VStack(spacing: 10) {
            if let r = result {
                HStack(spacing: 18) {
                    stat("P\(r.position)", "PLACE")
                    stat(fmtTime(r.time), "TIME")
                    stat("\(r.perfects)", "PERFECT")
                    stat("\(r.crashes)", "CRASHES")
                    stat(String(format: "%.1fs", r.airTime), "AIR")
                    stat("+\(r.coins)", "COINS")
                    stat("+\(r.xp)", "XP")
                    stat(game.lastTrophyDelta >= 0 ? "+\(game.lastTrophyDelta)" : "\(game.lastTrophyDelta)",
                         "TROPHIES")
                    if r.beatGhost { stat("BEAT", "GHOST") }
                }
            }
            HStack(spacing: 12) {
                PillButton(title: "Race Again", tint: Theme.panelHi, textColor: .white) {
                    if let r = result {
                        game.screen = .race(GameState.CareerTrackRef(regionId: r.regionId, trackId: r.trackId))
                    } else {
                        game.screen = .career
                    }
                }
                PillButton(title: "Continue") {
                    game.pendingResult = nil
                    game.screen = .career
                }
            }
        }
        .padding(.bottom, 6)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

/// Radial celebration rays behind the winner.
struct RaysView: View {
    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            for i in 0..<24 {
                let a0 = Double(i) / 24 * .pi * 2
                let a1 = a0 + 0.09
                var p = Path()
                p.move(to: c)
                p.addLine(to: CGPoint(x: c.x + cos(a0) * size.width, y: c.y + sin(a0) * size.width))
                p.addLine(to: CGPoint(x: c.x + cos(a1) * size.width, y: c.y + sin(a1) * size.width))
                p.closeSubpath()
                ctx.fill(p, with: .color(Color(hex: "#FFC24D").opacity(0.35)))
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}
