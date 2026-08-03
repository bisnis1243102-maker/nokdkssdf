import SwiftUI

/// The career map: a region qualifier with a row of track cards, each gated
/// behind the one before it, plus the region strip along the bottom.
struct CareerView: View {
    @EnvironmentObject var game: GameState
    @State private var regionId: String = ""

    private var region: Region {
        game.region(regionId.isEmpty ? game.profile.lastRegion : regionId)
    }

    var body: some View {
        ZStack {
            MenuBackground()
            VStack(spacing: 0) {
                topBar
                regionHeader
                trackRow
                Spacer(minLength: 4)
                regionStrip
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
        }
        .onAppear {
            if regionId.isEmpty { regionId = game.profile.lastRegion }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            LevelRing(level: game.profile.level,
                      progress: Double(game.profile.xp) / Double(max(1, game.profile.xpForNext)))

            Text(game.profile.name)
                .font(.system(size: 14, weight: .heavy))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.gold.opacity(0.9)))
                .foregroundColor(.black)

            Spacer(minLength: 0)

            DivisionBadge(trophies: game.profile.trophies)
            CurrencyChip(icon: "bolt.fill", value: "\(game.profile.tokens)", tint: Theme.cyan)
            CurrencyChip(icon: "circle.fill", value: "\(game.profile.coins)", tint: Theme.gold)
            CurrencyChip(icon: "diamond.fill", value: "\(game.profile.gems)", tint: Color(hex: "#F0B429"))

            IconTile(system: "trophy.fill", tint: Theme.gold) {}
            IconTile(system: "clock.arrow.circlepath",
                     badge: game.dailyGoalDone ? "✓" : nil, tint: .white) {}
            IconTile(system: "bicycle", tint: .white) { game.screen = .garage }
            IconTile(system: "person.fill", tint: .white) { game.screen = .rider }
            IconTile(system: "gearshape.fill", tint: .white) { game.screen = .settings }
        }
        .padding(.bottom, 6)
    }

    // MARK: Region header

    private var regionHeader: some View {
        HStack(spacing: 12) {
            RegionEmblem(region: region, size: 42)
            Text("\(region.name) Qualifier")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
            Text("\(Int(game.regionProgress(region) * 100))%")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(.white.opacity(0.85))
            Spacer()
            dailyGoalPill
        }
        .padding(.vertical, 8)
    }

    private var dailyGoalPill: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("DAILY GOAL")
                .font(.system(size: 10, weight: .black))
                .foregroundColor(.white.opacity(0.75))
            Text(DailyGoal.text(game.profile.dailyGoalKind))
                .font(.system(size: 13, weight: .heavy))
                .foregroundColor(Theme.gold)
            HStack(spacing: 6) {
                ProgressView(value: Double(game.profile.dailyGoalProgress),
                             total: Double(game.dailyGoalTarget))
                    .tint(Theme.green)
                    .frame(width: 90)
                Text("\(min(game.profile.dailyGoalProgress, game.dailyGoalTarget))/\(game.dailyGoalTarget)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.4)))
    }

    // MARK: Track cards

    private var trackRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                JamCard(track: game.jamTrack,
                        best: game.profile.jamBest,
                        runs: game.profile.jamRuns) {
                    game.screen = .race(GameState.CareerTrackRef(regionId: "jam",
                                                                 trackId: game.jamTrack.id))
                }
                ForEach(region.tracks) { track in
                    TrackCard(track: track,
                              region: region,
                              unlocked: game.isUnlocked(track, in: region),
                              medal: game.profile.medals[track.id] ?? 0,
                              power: game.currentPower) {
                        game.profile.lastRegion = region.id
                        game.save()
                        game.screen = .race(GameState.CareerTrackRef(regionId: region.id, trackId: track.id))
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }

    // MARK: Region strip

    private var regionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Region.all) { r in
                    let unlocked = game.isRegionUnlocked(r)
                    Button {
                        guard unlocked else { return }
                        Haptics.select()
                        regionId = r.id
                        game.profile.lastRegion = r.id
                        game.save()
                    } label: {
                        VStack(spacing: 4) {
                            Text(r.name.uppercased())
                                .font(.system(size: 9, weight: .black))
                                .foregroundColor(.white.opacity(unlocked ? 0.9 : 0.5))
                            ZStack {
                                RegionEmblem(region: r, size: 54)
                                    .saturation(unlocked ? 1 : 0)
                                    .opacity(unlocked ? 1 : 0.55)
                                if !unlocked {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 18, weight: .black))
                                        .foregroundColor(.white)
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(r.id == region.id ? Theme.gold : .clear, lineWidth: 3)
                            )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(.bottom, 6)
    }
}

struct RegionEmblem: View {
    let region: Region
    let size: CGFloat

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: region.tint), Color(hex: region.tint2)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Path { p in
                p.move(to: CGPoint(x: 0, y: size * 0.62))
                p.addLine(to: CGPoint(x: size * 1.4, y: size * 0.18))
                p.addLine(to: CGPoint(x: size * 1.4, y: size * 0.42))
                p.addLine(to: CGPoint(x: 0, y: size * 0.86))
                p.closeSubpath()
            }
            .fill(Color.white.opacity(0.25))
        }
        .frame(width: size * 1.4, height: size * 0.95)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

struct TrackCard: View {
    let track: CareerTrack
    let region: Region
    let unlocked: Bool
    let medal: Int
    let power: Int
    let onRace: () -> Void

    private var powerOK: Bool { power >= track.recommendedPower }

    var body: some View {
        VStack(spacing: 0) {
            Text(track.name.uppercased())
                .font(.system(size: 15, weight: .black))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .frame(height: 38)
                .padding(.horizontal, 8)

            ZStack {
                if unlocked {
                    RegionEmblem(region: region, size: 60)
                        .opacity(0.9)
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Theme.medalColor(medal > i ? medal : 0))
                                .frame(width: 26, height: 26)
                                .overlay(
                                    Image(systemName: ["figure.walk", "bicycle", "flag.checkered"][i])
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.black.opacity(0.65))
                                )
                                .rotationEffect(.degrees(45))
                        }
                    }
                    .offset(y: 26)
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 26))
                        .foregroundColor(medal == 3 ? Theme.gold : Color.white.opacity(0.35))
                        .offset(x: 52, y: -26)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 40, weight: .black))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .frame(height: 108)

            Spacer(minLength: 0)

            if unlocked {
                VStack(spacing: 2) {
                    Text("Recommended Power")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill").foregroundColor(Theme.gold).font(.system(size: 11))
                        Text("\(track.recommendedPower)")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Image(systemName: powerOK ? "checkmark" : "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .black))
                            .foregroundColor(powerOK ? Theme.green : Theme.red)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(Color(hex: "#0F3D2E").opacity(powerOK ? 0.95 : 0.5))

                Button(action: {
                    Haptics.select()
                    onRace()
                }) {
                    Text("RACE")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "#1A1206"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.gold)
                }
                .buttonStyle(.plain)
            } else {
                Text("Beat all previous\ntracks to unlock")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.black.opacity(0.5))
            }
        }
        .frame(width: 176, height: 268)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(unlocked
                      ? LinearGradient(colors: [Color(hex: "#14415C"), Color(hex: "#0D2C41")],
                                       startPoint: .top, endPoint: .bottom)
                      : LinearGradient(colors: [Color(hex: "#5C6068"), Color(hex: "#3C4048")],
                                       startPoint: .top, endPoint: .bottom))
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 8, x: 4, y: 6)
        .rotation3DEffect(.degrees(4), axis: (x: 0, y: 1, z: 0))
    }
}


/// Current division and progress towards the next one.
struct DivisionBadge: View {
    let trophies: Int

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 13, weight: .black))
                .foregroundColor(Theme.gold)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(trophies)")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text(Division.name(for: trophies).uppercased())
                    .font(.system(size: 8, weight: .black))
                    .foregroundColor(Theme.gold.opacity(0.9))
            }
            Capsule()
                .fill(Color.white.opacity(0.15))
                .frame(width: 34, height: 5)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Theme.green)
                        .frame(width: 34 * Division.progress(for: trophies), height: 5)
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// The weekly Jam: one rotating track, solo, run against your own best.
struct JamCard: View {
    let track: CareerTrack
    let best: Double
    let runs: Int
    let onRace: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("WEEKLY JAM")
                .font(.system(size: 15, weight: .black))
                .foregroundColor(Color(hex: "#1A1206"))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Theme.gold)

            VStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 34))
                    .foregroundColor(Theme.accent)
                Text(Biome.named(track.biome).name)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(.white)
                Text(best > 0 ? "Best \(fmtTime(best))" : "No time set")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.75))
                Text("\(runs) run\(runs == 1 ? "" : "s") this week")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.55))
            }
            .frame(maxHeight: .infinity)

            Button(action: {
                Haptics.select()
                onRace()
            }) {
                Text("RIDE")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "#1A1206"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.gold)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 176, height: 268)
        .background(
            LinearGradient(colors: [Color(hex: "#4A2418"), Color(hex: "#231018")],
                           startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 8, x: 4, y: 6)
        .rotation3DEffect(.degrees(4), axis: (x: 0, y: 1, z: 0))
    }
}
