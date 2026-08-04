import Foundation

/// Live state of one wheel and its suspension unit.
///
/// Everything the renderer, audio engine, particle system and debug overlay
/// need to know about a wheel is published here, so none of them has to reach
/// back into the solver.
public struct WheelState: Sendable {
    /// Current suspension compression from full extension, in metres.
    public var compression: Double = 0
    /// Rate of change of compression. Positive while the spring is being
    /// compressed, negative on rebound.
    public var compressionVelocity: Double = 0
    /// Wheel spin rate in rad/s. Positive drives the bike forward.
    public var spinVelocity: Double = 0
    /// Accumulated spin angle, used to orient the wheel's render node.
    public var spinAngle: Double = 0
    /// True while the tyre is touching the ground.
    public var isGrounded: Bool = false
    /// Load carried by the tyre in newtons. Zero when airborne.
    public var normalLoad: Double = 0
    /// Longitudinal slip ratio. Positive is wheelspin, negative is lock-up.
    public var slipRatio: Double = 0
    /// Fraction of available grip currently used, `0...1`. Drives tyre smoke,
    /// audio and the traction readout in the developer overlay.
    public var gripUtilisation: Double = 0
    /// World-space centre of the wheel.
    public var center: Vector2 = .zero
    /// World-space contact patch. Equal to `center` projected onto the ground.
    public var contactPoint: Vector2 = .zero
    /// Material currently under the tyre.
    public var surface: SurfaceType = .hardDirt
    /// True on the step where the suspension reached the end of its travel.
    public var isBottomedOut: Bool = false

    /// Compression as a fraction of total travel, for gauges and animation.
    public func compressionFraction(travel: Double) -> Double {
        guard travel > 0 else { return 0 }
        return MathUtils.clamp01(compression / travel)
    }
}
