import UIKit

/// Tactile feedback for gameplay and UI events.
///
/// Generators are created once and kept prepared, because preparing on demand
/// costs several milliseconds and turns a landing thud into a landing thud that
/// arrives late. Every call is a no-op when the player has haptics switched off
/// or the device cannot produce them.
///
/// Must be used from the main thread — `UIFeedbackGenerator` requires it. Every
/// call site is a UI event or a HUD refresh, both of which already are.
public final class HapticEngine {

    public static let shared = HapticEngine()

    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()

    /// Minimum gap between gameplay haptics, so a rough section does not turn
    /// into continuous buzzing.
    private let minimumInterval: TimeInterval = 0.08
    private var lastFireTime: TimeInterval = 0

    public var isEnabled: Bool = true
    /// Scales gameplay intensity, `0...1`.
    public var strength: Double = 0.7

    private init() {
        prepare()
    }

    /// Warms the generators. Called when a race is about to start.
    public func prepare() {
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        selection.prepare()
        notification.prepare()
    }

    public func applySettings(_ settings: GameSettings) {
        isEnabled = settings.hapticsEnabled
        strength = settings.hapticStrength
    }

    /// A gameplay impact whose weight follows `intensity` in `0...1`.
    public func impact(_ intensity: Double) {
        guard isEnabled, strength > 0.01 else { return }
        let now = CACurrentMediaTime()
        guard now - lastFireTime >= minimumInterval else { return }
        lastFireTime = now

        let scaled = MathUtils.clamp01(intensity * strength)
        guard scaled > 0.05 else { return }

        if scaled > 0.66 {
            impactHeavy.impactOccurred(intensity: CGFloat(scaled))
            impactHeavy.prepare()
        } else if scaled > 0.33 {
            impactMedium.impactOccurred(intensity: CGFloat(scaled))
            impactMedium.prepare()
        } else {
            impactLight.impactOccurred(intensity: CGFloat(scaled))
            impactLight.prepare()
        }
    }

    /// UI selection tick.
    public func select() {
        guard isEnabled else { return }
        selection.selectionChanged()
        selection.prepare()
    }

    public func success() {
        guard isEnabled else { return }
        notification.notificationOccurred(.success)
        notification.prepare()
    }

    public func failure() {
        guard isEnabled else { return }
        notification.notificationOccurred(.error)
        notification.prepare()
    }
}
