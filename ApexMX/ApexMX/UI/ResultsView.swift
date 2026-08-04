import SwiftUI

/// Post-race classification and rewards.
@MainActor
public struct ResultsView: View {

    @EnvironmentObject private var coordinator: GameCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    public init() {}

    private var playerResult: RaceResult? {
        coordinator.lastResults.first { $0.isPlayer }
    }

    public var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()
            HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                classification
                rewardColumn
            }
            .padding(Theme.Spacing.lg)
        }
        .onAppear {
            withAnimation(Theme.Motion.respecting(reduceMotion, Theme.Motion.standard)) {
                revealed = true
            }
        }
    }

    private var classification: some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(headline)
                    .font(Theme.Typography.display)
                    .foregroundStyle(headlineColor)

                Text(coordinator.selectedTrack.displayName)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(coordinator.lastResults) { result in
                            resultRow(result)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(revealed ? 1 : 0)
    }

    private func resultRow(_ result: RaceResult) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Text("\(result.position)")
                .font(Theme.Typography.mono)
                .foregroundStyle(result.position == 1 ? Theme.Palette.gold : Theme.Palette.textSecondary)
                .frame(width: 28, alignment: .trailing)

            Text(result.name)
                .font(Theme.Typography.body)
                .foregroundStyle(result.isPlayer ? Theme.Palette.accent : Theme.Palette.textPrimary)

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(result.totalTime.map(Format.lapTime) ?? "DNF")
                    .font(Theme.Typography.mono)
                    .foregroundStyle(Theme.Palette.textPrimary)
                if let best = result.bestLap {
                    Text("best \(Format.lapTime(best))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
        .padding(.horizontal, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(result.isPlayer ? Theme.Palette.accent.opacity(0.10) : .clear)
        )
        .accessibilityElement(children: .combine)
    }

    private var rewardColumn: some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Rewards")
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.Palette.textPrimary)

                if let reward = coordinator.lastReward {
                    rewardRow("Finish position", reward.positionCredits)
                    rewardRow("Pace", reward.lapTimeCredits)
                    rewardRow("Style", reward.styleCredits)
                    rewardRow("Medal", reward.medalCredits)
                    Divider().overlay(Theme.Palette.stroke)
                    rewardRow("Total", reward.totalCredits, emphasised: true)
                    rewardRow("Experience", reward.experience, suffix: "XP")

                    if reward.medal != .none {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "medal.fill")
                            Text("\(reward.medal.displayName) medal")
                        }
                        .font(Theme.Typography.body)
                        .foregroundStyle(medalColor(reward.medal))
                    }
                    if reward.newPersonalBest {
                        Label("New personal best", systemImage: "star.fill")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.success)
                    }
                }

                if let result = playerResult {
                    Divider().overlay(Theme.Palette.stroke)
                    statRow("Clean landings", "\(result.cleanLandings)")
                    statRow("Crashes", "\(result.crashes)")
                    statRow("Longest air", String(format: "%.2f s", result.bestAirTime))
                }

                Spacer()

                PrimaryButton("Race again", systemImage: "arrow.counterclockwise") {
                    coordinator.startRace()
                }
                SecondaryButton("Track select", systemImage: "map") {
                    coordinator.navigate(to: .trackSelect)
                }
                SecondaryButton("Main menu", systemImage: "house.fill") {
                    coordinator.navigate(to: .mainMenu)
                }
            }
        }
        .frame(width: 340)
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed ? 0 : 16)
    }

    private func rewardRow(_ label: String,
                           _ value: Int,
                           suffix: String = "cr",
                           emphasised: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(emphasised ? Theme.Typography.body : Theme.Typography.caption)
                .foregroundStyle(emphasised ? Theme.Palette.textPrimary : Theme.Palette.textSecondary)
            Spacer()
            Text("\(Format.credits(value)) \(suffix)")
                .font(Theme.Typography.mono)
                .foregroundStyle(emphasised ? Theme.Palette.warning : Theme.Palette.textPrimary)
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.Typography.mono)
                .foregroundStyle(Theme.Palette.textPrimary)
        }
    }

    private var headline: String {
        guard let result = playerResult else { return "Race over" }
        switch result.position {
        case 1: return "Win"
        case 2, 3: return "Podium"
        default: return "\(Format.ordinal(result.position)) place"
        }
    }

    private var headlineColor: Color {
        guard let result = playerResult else { return Theme.Palette.textPrimary }
        switch result.position {
        case 1: return Theme.Palette.gold
        case 2, 3: return Theme.Palette.silver
        default: return Theme.Palette.textPrimary
        }
    }

    private func medalColor(_ medal: Medal) -> Color {
        switch medal {
        case .gold: return Theme.Palette.gold
        case .silver: return Theme.Palette.silver
        case .bronze: return Theme.Palette.bronze
        case .none: return Theme.Palette.textTertiary
        }
    }
}
