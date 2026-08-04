import SwiftUI

/// Track selection, with each course's records and conditions.
@MainActor
public struct TrackSelectView: View {

    @EnvironmentObject private var coordinator: GameCoordinator

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.md) {
                    ForEach(coordinator.tracks) { track in
                        TrackCard(track: track,
                                  record: coordinator.profile.records[track.id],
                                  isUnlocked: coordinator.profile.hasUnlocked(track.id),
                                  isSelected: coordinator.selectedTrackID == track.id,
                                  medalPoints: coordinator.profile.medalPoints(tracks: coordinator.tracks))
                            .onTapGesture {
                                guard coordinator.profile.hasUnlocked(track.id) else { return }
                                HapticEngine.shared.select()
                                withAnimation(Theme.Motion.quick) {
                                    coordinator.selectTrack(track.id)
                                }
                            }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
            }
            footer
        }
        .padding(.vertical, Theme.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.background.ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            Button {
                coordinator.navigate(to: .mainMenu)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .frame(width: Theme.minimumTouchTarget, height: Theme.minimumTouchTarget)
            }
            .accessibilityLabel("Back to main menu")

            Text("Select a track")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
            Text("\(coordinator.profile.medalPoints(tracks: coordinator.tracks)) medal points")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(coordinator.activeSpec.displayName)
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text(coordinator.activeSpec.className)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Spacer()
            SecondaryButton("Garage", systemImage: "wrench.and.screwdriver.fill") {
                coordinator.navigate(to: .garage)
            }
            .frame(width: 180)
            PrimaryButton("Start race", systemImage: "flag.checkered") {
                HapticEngine.shared.select()
                coordinator.startRace()
            }
            .frame(width: 240)
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }
}

/// One track's card in the selection carousel.
private struct TrackCard: View {
    let track: TrackDefinition
    let record: TrackRecord?
    let isUnlocked: Bool
    let isSelected: Bool
    let medalPoints: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            profilePreview
            Text(track.displayName)
                .font(Theme.Typography.heading)
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(track.location)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)

            HStack(spacing: Theme.Spacing.sm) {
                tag(track.difficultyLabel, color: difficultyColor)
                tag("\(track.laps) laps", color: Theme.Palette.info)
                tag(track.weather.displayName, color: Theme.Palette.textTertiary)
            }

            Divider().overlay(Theme.Palette.stroke)

            if isUnlocked {
                unlockedFooter
            } else {
                lockedFooter
            }
        }
        .padding(Theme.Spacing.md)
        .frame(width: 280)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .fill(Theme.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .strokeBorder(isSelected ? Theme.Palette.accent : Theme.Palette.stroke,
                              lineWidth: isSelected ? 2.5 : 1)
        )
        .opacity(isUnlocked ? 1 : 0.55)
        .scaleEffect(isSelected ? 1.02 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.displayName), \(track.difficultyLabel)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// A miniature elevation profile drawn from the real feature list, so the
    /// card previews the actual course rather than generic artwork.
    ///
    /// The samples are computed once when the card is created — building the
    /// terrain inside the `Path` closure would regenerate the whole track on
    /// every redraw of a scrolling carousel.
    private var profilePreview: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                for (index, value) in profileSamples.enumerated() {
                    let t = CGFloat(index) / CGFloat(max(profileSamples.count - 1, 1))
                    let point = CGPoint(x: width * t,
                                        y: height * (1 - value) * 0.85 + height * 0.1)
                    index == 0 ? path.move(to: point) : path.addLine(to: point)
                }
            }
            .stroke(Theme.Palette.accentSoft, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
        .frame(height: 64)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(Theme.Palette.background)
        )
        .accessibilityHidden(true)
    }

    /// Normalised elevation samples in `0...1`.
    private let profileSamples: [CGFloat]

    init(track: TrackDefinition,
         record: TrackRecord?,
         isUnlocked: Bool,
         isSelected: Bool,
         medalPoints: Int) {
        self.track = track
        self.record = record
        self.isUnlocked = isUnlocked
        self.isSelected = isSelected
        self.medalPoints = medalPoints

        let terrain = TrackBuilder.build(track)
        let span = terrain.endX - terrain.originX
        let minY = terrain.minimumHeight
        let maxY = max(terrain.maximumHeight, minY + 1)
        let sampleCount = 60
        self.profileSamples = (0...sampleCount).map { index in
            let t = Double(index) / Double(sampleCount)
            let y = terrain.height(at: terrain.originX + span * t)
            return CGFloat((y - minY) / (maxY - minY))
        }
    }

    private var unlockedFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Best lap")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                Spacer()
                Text(record.map { Format.lapTime($0.bestLapTime) } ?? "—")
                    .font(Theme.Typography.mono)
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            HStack {
                Text("Gold target")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                Spacer()
                Text(Format.lapTime(track.goldLapTime))
                    .font(Theme.Typography.mono)
                    .foregroundStyle(Theme.Palette.gold)
            }
            if let medal = record?.medal(goldLapTime: track.goldLapTime), medal != .none {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "medal.fill")
                    Text(medal.displayName)
                }
                .font(Theme.Typography.caption)
                .foregroundStyle(medalColor(medal))
            }
        }
    }

    private var lockedFooter: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "lock.fill")
            Text("\(CareerService.pointsRequired(for: track.id)) medal points to unlock — you have \(medalPoints)")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Theme.Typography.caption)
        .foregroundStyle(Theme.Palette.textSecondary)
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    private var difficultyColor: Color {
        switch track.difficulty {
        case ...1: return Theme.Palette.success
        case 2: return Theme.Palette.info
        case 3: return Theme.Palette.warning
        default: return Theme.Palette.danger
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
