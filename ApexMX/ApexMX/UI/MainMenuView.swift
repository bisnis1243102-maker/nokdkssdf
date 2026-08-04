import SwiftUI

/// The title screen.
@MainActor
public struct MainMenuView: View {

    @EnvironmentObject private var coordinator: GameCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    public init() {}

    public var body: some View {
        ZStack {
            backdrop
            HStack(spacing: Theme.Spacing.xl) {
                branding
                menu
            }
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.vertical, Theme.Spacing.lg)

            if let notice = coordinator.notice {
                noticeBanner(notice)
            }
        }
        .onAppear {
            withAnimation(Theme.Motion.respecting(reduceMotion, Theme.Motion.standard)) {
                hasAppeared = true
            }
        }
    }

    private var backdrop: some View {
        LinearGradient(colors: [Theme.Palette.background,
                                Theme.Palette.surface,
                                Theme.Palette.background],
                       startPoint: .topLeading,
                       endPoint: .bottomTrailing)
            .ignoresSafeArea()
            .overlay(
                // A single angled accent stripe gives the screen a direction of
                // travel without costing a texture.
                Rectangle()
                    .fill(LinearGradient(colors: [Theme.Palette.accent.opacity(0.25), .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 180)
                    .rotationEffect(.degrees(-8))
                    .offset(y: 120)
                    .blur(radius: 40)
                    .ignoresSafeArea()
            )
    }

    private var branding: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Spacer()
            Text("APEX")
                .font(.system(size: 76, weight: .black, design: .rounded))
                .foregroundStyle(Theme.Palette.textPrimary)
            Text("MX")
                .font(.system(size: 76, weight: .black, design: .rounded))
                .foregroundStyle(Theme.Palette.accent)
                .offset(x: 6)
            Text("Momentum is everything.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.textSecondary)
            Spacer()
            profileStrip
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(x: hasAppeared ? 0 : -20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profileStrip: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(coordinator.profile.displayName)
                    .font(Theme.Typography.heading)
                    .foregroundStyle(Theme.Palette.textPrimary)
                Text("Level \(coordinator.profile.level)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Divider().frame(height: 30).overlay(Theme.Palette.stroke)
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "circle.hexagongrid.fill")
                    .foregroundStyle(Theme.Palette.warning)
                Text(Format.credits(coordinator.profile.credits))
                    .font(Theme.Typography.mono)
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .fill(Theme.Palette.surface.opacity(0.8))
        )
    }

    private var menu: some View {
        VStack(spacing: Theme.Spacing.md) {
            Spacer()
            PrimaryButton("Race", systemImage: "flag.checkered") {
                HapticEngine.shared.select()
                coordinator.navigate(to: .trackSelect)
            }
            SecondaryButton("Garage", systemImage: "wrench.and.screwdriver.fill") {
                HapticEngine.shared.select()
                coordinator.navigate(to: .garage)
            }
            SecondaryButton("Profile & Records", systemImage: "chart.bar.fill") {
                HapticEngine.shared.select()
                coordinator.navigate(to: .profile)
            }
            SecondaryButton("Settings", systemImage: "gearshape.fill") {
                HapticEngine.shared.select()
                coordinator.navigate(to: .settings)
            }
            Spacer()
        }
        .frame(width: 320)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 20)
    }

    private func noticeBanner(_ text: String) -> some View {
        VStack {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "lock.open.fill")
                Text(text)
            }
            .font(Theme.Typography.body)
            .foregroundStyle(.black)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Capsule().fill(Theme.Palette.success))
            .padding(.top, Theme.Spacing.md)
            .onTapGesture { coordinator.notice = nil }
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            withAnimation(Theme.Motion.gentle) { coordinator.notice = nil }
        }
    }
}
