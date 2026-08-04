import SwiftUI

/// Player options, including the full accessibility set.
@MainActor
public struct SettingsView: View {

    @EnvironmentObject private var coordinator: GameCoordinator

    public init() {}

    private var settings: Binding<GameSettings> {
        Binding(get: { coordinator.profile.settings },
                set: { newValue in
                    coordinator.profile.settings = newValue
                    HapticEngine.shared.applySettings(newValue)
                    coordinator.save()
                })
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.Spacing.md) {
                    audioSection
                    displaySection
                    controlsSection
                    accessibilitySection
                    developerSection
                }
                .padding(Theme.Spacing.lg)
            }
        }
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

            Text("Settings")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.lg)
    }

    private var audioSection: some View {
        section("Audio") {
            slider("Master volume", value: settings.masterVolume)
            slider("Music", value: settings.musicVolume)
            slider("Effects", value: settings.effectsVolume)
        }
    }

    private var displaySection: some View {
        section("Display") {
            picker("Frame rate", selection: settings.frameRateCap, options: FrameRateCap.allCases) {
                $0.displayName
            }
            picker("Graphics quality", selection: settings.graphicsQuality,
                   options: GraphicsQuality.allCases) { $0.displayName }
            toggle("Speedometer", isOn: settings.showSpeedometer)
            toggle("Lap progress bar", isOn: settings.showMiniMap)
            slider("HUD scale", value: settings.hudScale, range: 0.75...1.35)
        }
    }

    private var controlsSection: some View {
        section("Controls") {
            toggle("Throttle on the right", isOn: settings.throttleOnRight)
            toggle("Invert lean", isOn: settings.invertLeanControls)
            toggle("Haptics", isOn: settings.hapticsEnabled)
            slider("Haptic strength", value: settings.hapticStrength)
        }
    }

    private var accessibilitySection: some View {
        section("Accessibility") {
            toggle("Reduce motion", isOn: settings.reduceMotion)
            toggle("High contrast HUD", isOn: settings.highContrastHUD)
            picker("Colourblind mode", selection: settings.colorblindMode,
                   options: ColorblindMode.allCases) { $0.displayName }
        }
    }

    private var developerSection: some View {
        section("Developer") {
            toggle("Physics overlay", isOn: settings.developerOverlay)
            Text("Shows live simulation telemetry during a race: suspension travel, tyre slip, grip use, engine speed and frame timing.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Building blocks

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(title)
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.Palette.textPrimary)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func toggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Text(label)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        .tint(Theme.Palette.accent)
        .frame(minHeight: Theme.minimumTouchTarget)
    }

    private func slider(_ label: String,
                        value: Binding<Double>,
                        range: ClosedRange<Double> = 0...1) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(label)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Spacer()
                Text("\(Int((value.wrappedValue / range.upperBound * 100).rounded()))%")
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Slider(value: value, in: range)
                .tint(Theme.Palette.accent)
        }
        .frame(minHeight: Theme.minimumTouchTarget)
    }

    private func picker<Option: Hashable>(_ label: String,
                                          selection: Binding<Option>,
                                          options: [Option],
                                          title: @escaping (Option) -> String) -> some View {
        HStack {
            Text(label)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
            Picker(label, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(title(option)).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(Theme.Palette.accent)
        }
        .frame(minHeight: Theme.minimumTouchTarget)
    }
}

/// Lifetime statistics and per-track records.
@MainActor
public struct ProfileView: View {

    @EnvironmentObject private var coordinator: GameCoordinator

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(spacing: Theme.Spacing.md) {
                    summary
                    recordsPanel
                }
                .padding(Theme.Spacing.lg)
            }
        }
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

            Text("Profile")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.lg)
    }

    private var summary: some View {
        let stats = coordinator.profile.statistics
        return Panel {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text(coordinator.profile.displayName)
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text("Level \(coordinator.profile.level)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.accent)
                    Spacer()
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4),
                          spacing: Theme.Spacing.md) {
                    stat("Races", "\(stats.racesEntered)")
                    stat("Wins", "\(stats.racesWon)")
                    stat("Podiums", "\(stats.podiums)")
                    stat("Win rate", String(format: "%.0f%%", stats.winRate * 100))
                    stat("Distance", String(format: "%.1f km", stats.totalDistance / 1000))
                    stat("Clean landings", "\(stats.cleanLandings)")
                    stat("Crashes", "\(stats.crashes)")
                    stat("Longest air", String(format: "%.2f s", stats.longestJump))
                }
            }
        }
    }

    private var recordsPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Track records")
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.Palette.textPrimary)

                ForEach(coordinator.tracks) { track in
                    let record = coordinator.profile.records[track.id]
                    HStack {
                        Text(track.displayName)
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Spacer()
                        Text(record.map { Format.lapTime($0.bestLapTime) } ?? "—")
                            .font(Theme.Typography.mono)
                            .foregroundStyle(Theme.Palette.textPrimary)
                        Text(record?.medal(goldLapTime: track.goldLapTime).displayName ?? "—")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.textSecondary)
                            .frame(width: 64, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.Typography.heading.monospacedDigit())
                .foregroundStyle(Theme.Palette.textPrimary)
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
