import SwiftUI

/// Collects touch input and publishes a `RiderInput`.
///
/// Controls are held, not tapped, so the object tracks which pads are down and
/// converts that into analogue values. Throttle and lean ramp rather than
/// snapping: an instant 0-to-100% throttle is both unrealistic and, more
/// importantly, impossible to modulate, which would remove throttle control as
/// a skill.
@MainActor
public final class TouchControlState: ObservableObject {

    @Published public var isThrottleDown = false
    @Published public var isFrontBrakeDown = false
    @Published public var isRearBrakeDown = false
    @Published public var leanDirection: Double = 0   // -1 back, +1 forward

    private var throttle: Double = 0
    private var frontBrake: Double = 0
    private var rearBrake: Double = 0
    private var lean: Double = 0

    /// How fast each control reaches full deflection, in units per second.
    private let throttleRampRate: Double = 4.5
    private let throttleReleaseRate: Double = 8.0
    private let brakeRampRate: Double = 7.0
    private let leanRampRate: Double = 6.0

    public init() {}

    /// Advances the analogue values and returns the input for this frame.
    public func resolve(dt: Double, invertLean: Bool) -> RiderInput {
        throttle = MathUtils.moveToward(throttle,
                                        isThrottleDown ? 1 : 0,
                                        maxDelta: (isThrottleDown ? throttleRampRate : throttleReleaseRate) * dt)
        frontBrake = MathUtils.moveToward(frontBrake,
                                          isFrontBrakeDown ? 1 : 0,
                                          maxDelta: brakeRampRate * dt)
        rearBrake = MathUtils.moveToward(rearBrake,
                                         isRearBrakeDown ? 1 : 0,
                                         maxDelta: brakeRampRate * dt)
        let leanTarget = invertLean ? -leanDirection : leanDirection
        lean = MathUtils.moveToward(lean, leanTarget, maxDelta: leanRampRate * dt)

        return RiderInput(throttle: throttle,
                          frontBrake: frontBrake,
                          rearBrake: rearBrake,
                          lean: lean)
    }

    /// Releases every control. Used on pause and on scene teardown so a held
    /// button cannot survive into a state where it can no longer be released.
    public func releaseAll() {
        isThrottleDown = false
        isFrontBrakeDown = false
        isRearBrakeDown = false
        leanDirection = 0
        throttle = 0
        frontBrake = 0
        rearBrake = 0
        lean = 0
    }
}

/// A hold-to-activate control pad.
public struct ControlPad: View {
    private let label: String
    private let systemImage: String
    private let tint: Color
    private let isActive: Bool
    private let size: CGFloat
    private let onChange: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(label: String,
                systemImage: String,
                tint: Color,
                isActive: Bool,
                size: CGFloat = 96,
                onChange: @escaping (Bool) -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.tint = tint
        self.isActive = isActive
        self.size = size
        self.onChange = onChange
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(isActive ? 0.85 : 0.28))
            Circle()
                .strokeBorder(tint.opacity(0.9), lineWidth: 2)
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.30, weight: .bold))
                Text(label)
                    .font(.system(size: size * 0.13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .scaleEffect(isActive && !reduceMotion ? 0.94 : 1)
        .animation(Theme.Motion.quick, value: isActive)
        // A zero-distance drag gesture is what makes this a *hold* control:
        // `onTapGesture` would only fire on release, which is useless for a
        // throttle.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isActive { onChange(true) } }
                .onEnded { _ in onChange(false) }
        )
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Hold to apply")
    }
}
