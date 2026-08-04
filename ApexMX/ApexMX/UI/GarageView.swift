import SwiftUI

/// The garage: choose a machine, fit parts, and see exactly what changes.
@MainActor
public struct GarageView: View {

    @EnvironmentObject private var coordinator: GameCoordinator
    @State private var previewCategory: UpgradeCategory?

    public init() {}

    public var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            header
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                bikeColumn
                upgradeColumn
            }
            .padding(.horizontal, Theme.Spacing.lg)
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

            Text("Garage")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.textPrimary)
            Spacer()
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "circle.hexagongrid.fill")
                    .foregroundStyle(Theme.Palette.warning)
                Text(Format.credits(coordinator.profile.credits))
                    .font(Theme.Typography.mono)
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    // MARK: Machines

    private var bikeColumn: some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Machines")
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.Palette.textPrimary)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: Theme.Spacing.sm) {
                        ForEach(coordinator.bikes) { bike in
                            bikeRow(bike)
                        }
                    }
                }

                Divider().overlay(Theme.Palette.stroke)
                statBlock
            }
        }
        .frame(width: 360)
    }

    private func bikeRow(_ bike: BikeSpec) -> some View {
        let owned = coordinator.profile.owns(bike.id)
        let selected = coordinator.profile.selectedBikeID == bike.id
        let price = BikeCatalog.price(for: bike.id)
        let affordable = coordinator.profile.credits >= price

        return Button {
            HapticEngine.shared.select()
            if owned {
                coordinator.selectBike(bike.id)
            } else if affordable {
                coordinator.purchaseBike(bike.id)
            }
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bike.displayName)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(bike.className)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
                if owned {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Theme.Palette.accent : Theme.Palette.textTertiary)
                } else {
                    Text(Format.credits(price))
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(affordable ? Theme.Palette.warning : Theme.Palette.textTertiary)
                }
            }
            .padding(Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .fill(selected ? Theme.Palette.accent.opacity(0.12) : Theme.Palette.surfaceRaised)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(owned
                            ? "\(bike.displayName), \(selected ? "selected" : "owned")"
                            : "\(bike.displayName), costs \(price) credits")
    }

    /// Live stat bars for the selected machine, with a preview tick showing what
    /// the highlighted upgrade would do before the player spends anything.
    private var statBlock: some View {
        let current = coordinator.activeSpec
        let previewed = previewSpec

        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(current.flavorText)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(UpgradeCategory.allCases) { category in
                StatBar(label: category.displayName,
                        value: UpgradeSystem.rating(for: current, category: category),
                        comparison: previewed.map {
                            UpgradeSystem.rating(for: $0, category: category)
                        })
            }
        }
    }

    /// The machine as it would be with one more level of the highlighted part.
    private var previewSpec: BikeSpec? {
        guard let category = previewCategory else { return nil }
        var loadout = coordinator.profile.loadout(for: coordinator.profile.selectedBikeID)
        guard loadout.level(category) < UpgradeCategory.maximumLevel else { return nil }
        loadout.setLevel(loadout.level(category) + 1, for: category)
        let base = BikeCatalog.spec(withID: coordinator.profile.selectedBikeID, in: coordinator.bikes)
        return UpgradeSystem.apply(loadout, to: base)
    }

    // MARK: Upgrades

    private var upgradeColumn: some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Performance parts")
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.Palette.textPrimary)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: Theme.Spacing.sm) {
                        ForEach(UpgradeCategory.allCases) { category in
                            upgradeRow(category)
                        }
                    }
                }

                PrimaryButton("Race this bike", systemImage: "flag.checkered") {
                    coordinator.navigate(to: .trackSelect)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func upgradeRow(_ category: UpgradeCategory) -> some View {
        let loadout = coordinator.profile.loadout(for: coordinator.profile.selectedBikeID)
        let level = loadout.level(category)
        let cost = loadout.upgradeCost(for: category)
        let affordable = cost.map { coordinator.profile.credits >= $0 } ?? false

        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: category.iconName)
                    .foregroundStyle(Theme.Palette.accent)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.displayName)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    Text(category.summary)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Spacing.sm)
                levelPips(level)
            }

            HStack {
                if let cost {
                    Button {
                        HapticEngine.shared.select()
                        if coordinator.purchaseUpgrade(category) {
                            HapticEngine.shared.success()
                        }
                    } label: {
                        Text("Fit — \(Format.credits(cost))")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(affordable ? .black : Theme.Palette.textTertiary)
                            .padding(.horizontal, Theme.Spacing.md)
                            .frame(minHeight: 36)
                            .background(
                                Capsule().fill(affordable
                                               ? Theme.Palette.accent
                                               : Theme.Palette.surfaceRaised)
                            )
                    }
                    .disabled(!affordable)
                    .buttonStyle(PressableButtonStyle())
                } else {
                    Text("Fully upgraded")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.success)
                }
                Spacer()
            }
        }
        .padding(Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .fill(Theme.Palette.surfaceRaised)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(Theme.Motion.quick) {
                previewCategory = previewCategory == category ? nil : category
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .strokeBorder(previewCategory == category ? Theme.Palette.info : .clear,
                              lineWidth: 1.5)
        )
    }

    private func levelPips(_ level: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<UpgradeCategory.maximumLevel, id: \.self) { index in
                Capsule()
                    .fill(index < level ? Theme.Palette.accent : Theme.Palette.stroke)
                    .frame(width: 12, height: 5)
            }
        }
        .accessibilityLabel("Level \(level) of \(UpgradeCategory.maximumLevel)")
    }
}
