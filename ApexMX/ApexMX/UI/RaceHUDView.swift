import SwiftUI

/// A snapshot of everything the HUD needs, sampled from the session.
///
/// The HUD reads a plain value type rather than the live session so that
/// SwiftUI only re-renders when a displayed value actually changes, instead of
/// once per physics step.
public struct HUDSnapshot: Equatable {
    public var speedKPH: Double = 0
    public var position: Int = 1
    public var fieldSize: Int = 1
    public var lap: Int = 1
    public var totalLaps: Int = 1
    public var raceTime: Double = 0
    public var lapProgress: Double = 0
    public var countdown: Double?
    public var isFinished: Bool = false
    public var crashReason: String?
    public var crashAdvice: String?
    public var airTime: Double = 0
    public var isAirborne: Bool = false
    public var lastLapTime: Double?
    public var bestLapTime: Double?
    public var gapAhead: Double?

    public init() {}
}

/// The in-race heads-up display.
public struct RaceHUDView: View {

    public let snapshot: HUDSnapshot
    public let settings: GameSettings
    public let onPause: () -> Void
    public let onRecover: () -> Void

    public init(snapshot: HUDSnapshot,
                settings: GameSettings,
                onPause: @escaping () -> Void,
                onRecover: @escaping () -> Void) {
        self.snapshot = snapshot
        self.settings = settings
        self.onPause = onPause
        self.onRecover = onRecover
    }

    public var body: some View {
        ZStack {
            VStack {
                topBar
                Spacer()
                if settings.showMiniMap { progressTrack }
            }
            .padding(Theme.Spacing.md)

            if let countdown = snapshot.countdown {
                countdownOverlay(countdown)
            }
            if snapshot.crashReason != nil {
                crashOverlay
            }
            if snapshot.isAirborne && snapshot.airTime > 0.6 {
                airTimeBadge
            }
        }
        .scaleEffect(CGFloat(settings.hudScale), anchor: .center)
        .allowsHitTesting(true)
    }

    // MARK: - Sections

    private var topBar: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Button(action: onPause) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: Theme.minimumTouchTarget, height: Theme.minimumTouchTarget)
                    .background(Circle().fill(Color.black.opacity(0.42)))
            }
            .accessibilityLabel("Pause race")

            positionBadge

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.lapTime(max(snapshot.raceTime, 0)))
                    .font(Theme.Typography.timer.monospacedDigit())
                    .foregroundStyle(.white)
                if let best = snapshot.bestLapTime {
                    Text("Best \(Format.lapTime(best))")
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(Theme.Palette.textSecondary)
                }
            }

            if settings.showSpeedometer { speedometer }
        }
        .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
    }

    private var positionBadge: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(snapshot.position)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("/ \(snapshot.fieldSize)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            Text("LAP \(snapshot.lap)/\(snapshot.totalLaps)")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(Color.black.opacity(0.38))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Position \(snapshot.position) of \(snapshot.fieldSize), lap \(snapshot.lap) of \(snapshot.totalLaps)")
    }

    private var speedometer: some View {
        VStack(spacing: 0) {
            Text("\(Int(snapshot.speedKPH.rounded()))")
                .font(.system(size: 38, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
            Text("KM/H")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .fill(Color.black.opacity(0.38))
        )
        .accessibilityLabel("Speed \(Int(snapshot.speedKPH)) kilometres per hour")
    }

    /// A slim bar showing progress around the current lap.
    private var progressTrack: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.35))
                Capsule()
                    .fill(Theme.Palette.accent(for: settings.colorblindMode))
                    .frame(width: geometry.size.width * CGFloat(MathUtils.clamp01(snapshot.lapProgress)))
                Circle()
                    .fill(.white)
                    .frame(width: 10, height: 10)
                    .offset(x: geometry.size.width * CGFloat(MathUtils.clamp01(snapshot.lapProgress)) - 5)
            }
        }
        .frame(height: 6)
        .padding(.horizontal, Theme.Spacing.xl)
        .accessibilityHidden(true)
    }

    private func countdownOverlay(_ remaining: Double) -> some View {
        let count = Int(remaining.rounded(.up))
        return Text(count > 0 ? "\(count)" : "GO")
            .font(.system(size: 110, weight: .black, design: .rounded))
            .foregroundStyle(count > 0 ? Color.white : Theme.Palette.success)
            .shadow(color: .black.opacity(0.6), radius: 12)
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel(count > 0 ? "Starting in \(count)" : "Go")
    }

    private var crashOverlay: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text(snapshot.crashReason ?? "")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.danger)
            if let advice = snapshot.crashAdvice {
                Text(advice)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
            Button(action: onRecover) {
                Text("Remount now")
                    .font(Theme.Typography.body)
                    .foregroundStyle(.black)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .frame(minHeight: Theme.minimumTouchTarget)
                    .background(Capsule().fill(Theme.Palette.accent))
            }
        }
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .fill(Color.black.opacity(0.62))
        )
    }

    private var airTimeBadge: some View {
        VStack {
            Spacer()
            Text(String(format: "AIR %.1fs", snapshot.airTime))
                .font(Theme.Typography.heading.monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
                .background(Capsule().fill(Theme.Palette.info.opacity(0.75)))
            Spacer().frame(height: 90)
        }
        .accessibilityHidden(true)
    }
}
