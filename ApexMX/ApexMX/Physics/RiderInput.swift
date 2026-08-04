import Foundation

/// The complete set of controls a rider — human or AI — can apply.
///
/// This is the *only* channel through which anything influences a bike. The AI
/// has no privileged access to the simulation: it fills in one of these
/// structures exactly as the touch controls do, which is what makes the
/// "no hidden advantages" guarantee structural rather than aspirational.
public struct RiderInput: Sendable, Equatable, Codable {
    /// Throttle demand, `0...1`.
    public var throttle: Double
    /// Front brake demand, `0...1`.
    public var frontBrake: Double
    /// Rear brake demand, `0...1`. Also the primary air-control brake.
    public var rearBrake: Double
    /// Body lean, `-1` fully back to `+1` fully forward.
    public var lean: Double

    public init(throttle: Double = 0,
                frontBrake: Double = 0,
                rearBrake: Double = 0,
                lean: Double = 0) {
        self.throttle = MathUtils.clamp01(throttle)
        self.frontBrake = MathUtils.clamp01(frontBrake)
        self.rearBrake = MathUtils.clamp01(rearBrake)
        self.lean = MathUtils.clamp(lean, -1, 1)
    }

    public static let neutral = RiderInput()

    /// Clamps every channel into its legal range. Applied at the simulation
    /// boundary so that malformed input — from a decoded replay, a network
    /// packet, or a bug — can never destabilise the physics.
    public var sanitised: RiderInput {
        RiderInput(throttle: throttle.isFinite ? throttle : 0,
                   frontBrake: frontBrake.isFinite ? frontBrake : 0,
                   rearBrake: rearBrake.isFinite ? rearBrake : 0,
                   lean: lean.isFinite ? lean : 0)
    }
}
