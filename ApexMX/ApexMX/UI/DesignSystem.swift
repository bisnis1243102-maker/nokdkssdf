import SwiftUI

/// The single source of truth for the game's visual language.
///
/// Colours, spacing, radii, type and motion all live here. Screens compose from
/// these tokens rather than hard-coding values, so a change to the brand is one
/// edit and every screen stays consistent by construction.
public enum Theme {

    // MARK: Colour

    public enum Palette {
        /// Deep, cool background the whole interface sits on.
        public static let background = Color(red: 0.055, green: 0.067, blue: 0.094)
        public static let surface = Color(red: 0.098, green: 0.114, blue: 0.153)
        public static let surfaceRaised = Color(red: 0.137, green: 0.157, blue: 0.208)
        public static let stroke = Color.white.opacity(0.10)

        /// Signature accent — a hot competition orange.
        public static let accent = Color(red: 1.00, green: 0.45, blue: 0.13)
        public static let accentSoft = Color(red: 1.00, green: 0.62, blue: 0.35)
        /// Secondary accent for information and progress.
        public static let info = Color(red: 0.32, green: 0.68, blue: 1.00)
        public static let success = Color(red: 0.30, green: 0.82, blue: 0.52)
        public static let warning = Color(red: 1.00, green: 0.78, blue: 0.25)
        public static let danger = Color(red: 0.98, green: 0.34, blue: 0.36)

        public static let textPrimary = Color.white
        public static let textSecondary = Color.white.opacity(0.66)
        public static let textTertiary = Color.white.opacity(0.40)

        public static let gold = Color(red: 1.00, green: 0.80, blue: 0.30)
        public static let silver = Color(red: 0.82, green: 0.85, blue: 0.90)
        public static let bronze = Color(red: 0.82, green: 0.55, blue: 0.33)

        /// Accent colour adjusted for a colour-vision deficiency, so that
        /// accent-versus-success distinctions survive.
        public static func accent(for mode: ColorblindMode) -> Color {
            switch mode {
            case .none: return accent
            case .protanopia, .deuteranopia: return Color(red: 0.98, green: 0.72, blue: 0.10)
            case .tritanopia: return Color(red: 0.98, green: 0.35, blue: 0.45)
            }
        }
    }

    // MARK: Spacing and shape

    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 24
        public static let xl: CGFloat = 36
        public static let xxl: CGFloat = 56
    }

    public enum Radius {
        public static let small: CGFloat = 8
        public static let medium: CGFloat = 14
        public static let large: CGFloat = 22
        public static let pill: CGFloat = 999
    }

    // MARK: Type

    public enum Typography {
        public static let display = Font.system(size: 44, weight: .heavy, design: .rounded)
        public static let title = Font.system(size: 28, weight: .bold, design: .rounded)
        public static let heading = Font.system(size: 20, weight: .semibold, design: .rounded)
        public static let body = Font.system(size: 16, weight: .medium, design: .rounded)
        public static let caption = Font.system(size: 13, weight: .medium, design: .rounded)
        public static let mono = Font.system(size: 16, weight: .semibold, design: .monospaced)
        /// Large monospaced digits for timers, where digit jitter is unacceptable.
        public static let timer = Font.system(size: 30, weight: .bold, design: .monospaced)
    }

    // MARK: Motion

    public enum Motion {
        public static let quick = Animation.spring(response: 0.28, dampingFraction: 0.82)
        public static let standard = Animation.spring(response: 0.42, dampingFraction: 0.80)
        public static let gentle = Animation.easeInOut(duration: 0.35)

        /// Returns an animation, or `nil` when the player has asked for reduced
        /// motion — passing `nil` to `withAnimation` disables it entirely.
        public static func respecting(_ reduceMotion: Bool, _ animation: Animation) -> Animation? {
            reduceMotion ? nil : animation
        }
    }

    /// Minimum touch target, per Apple's Human Interface Guidelines.
    public static let minimumTouchTarget: CGFloat = 44
}

// MARK: - Reusable components

/// A raised panel used to group related controls.
public struct Panel<Content: View>: View {
    private let content: Content
    private let padding: CGFloat

    public init(padding: CGFloat = Theme.Spacing.md, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .fill(Theme.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .strokeBorder(Theme.Palette.stroke, lineWidth: 1)
            )
    }
}

/// The primary call-to-action button.
public struct PrimaryButton: View {
    private let title: String
    private let systemImage: String?
    private let isEnabled: Bool
    private let action: () -> Void

    public init(_ title: String,
                systemImage: String? = nil,
                isEnabled: Bool = true,
                action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(Theme.Typography.heading)
            .foregroundStyle(isEnabled ? Color.black : Theme.Palette.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .fill(isEnabled
                          ? LinearGradient(colors: [Theme.Palette.accentSoft, Theme.Palette.accent],
                                           startPoint: .top, endPoint: .bottom)
                          : LinearGradient(colors: [Theme.Palette.surfaceRaised,
                                                    Theme.Palette.surfaceRaised],
                                           startPoint: .top, endPoint: .bottom))
            )
        }
        .disabled(!isEnabled)
        .buttonStyle(PressableButtonStyle())
    }
}

/// A quieter secondary action.
public struct SecondaryButton: View {
    private let title: String
    private let systemImage: String?
    private let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Palette.textPrimary)
            .frame(maxWidth: .infinity, minHeight: Theme.minimumTouchTarget)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .fill(Theme.Palette.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                    .strokeBorder(Theme.Palette.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Gives every button the same tactile press response.
public struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
    }
}

/// A labelled 0–100 bar, used for bike statistics.
public struct StatBar: View {
    private let label: String
    private let value: Double
    private let comparison: Double?

    public init(label: String, value: Double, comparison: Double? = nil) {
        self.label = label
        self.value = value
        self.comparison = comparison
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(label)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.textSecondary)
                Spacer()
                Text("\(Int(value.rounded()))")
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.textPrimary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.surfaceRaised)
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.Palette.accentSoft, Theme.Palette.accent],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * CGFloat(MathUtils.clamp01(value / 100)))
                    // A tick showing what the part being previewed would change,
                    // so the player can see the effect before spending.
                    if let comparison {
                        Rectangle()
                            .fill(Theme.Palette.info)
                            .frame(width: 2)
                            .offset(x: geometry.size.width * CGFloat(MathUtils.clamp01(comparison / 100)))
                    }
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value.rounded())) out of 100")
    }
}

// MARK: - Formatting

/// Shared, locale-aware formatting for times and numbers.
public enum Format {

    /// `1:23.456` — the standard motorsport lap format.
    public static func lapTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < 60 * 60 else { return "--:--.---" }
        let minutes = Int(seconds) / 60
        let remaining = seconds - Double(minutes * 60)
        return String(format: "%d:%06.3f", minutes, remaining)
    }

    /// A signed gap, e.g. `+1.284`.
    public static func gap(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "--" }
        return String(format: "%+.3f", seconds)
    }

    public static func credits(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    public static func ordinal(_ position: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: position)) ?? "\(position)"
    }
}
