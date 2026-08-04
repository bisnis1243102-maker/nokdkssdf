import Foundation

/// Drives a simulation at a constant rate regardless of the display refresh rate.
///
/// The renderer may run at 30, 60 or 120 Hz; the physics always advances in
/// identical `step` increments so that results are reproducible and stable.
/// Left-over time is exposed as `alpha` so the presentation layer can
/// interpolate between the previous and current simulation states, which
/// removes the judder that a naive fixed step otherwise introduces.
public struct FixedTimestepAccumulator {

    /// Duration of a single simulation step, in seconds.
    public let step: Double

    /// Upper bound on the real time consumed by one `advance` call. This
    /// prevents the "spiral of death" where a slow frame queues more steps than
    /// the device can execute, which would make the next frame slower still.
    public let maxFrameTime: Double

    private var accumulator: Double = 0

    public init(stepsPerSecond: Double = 240, maxFrameTime: Double = 0.25) {
        precondition(stepsPerSecond > 0, "Simulation rate must be positive")
        self.step = 1.0 / stepsPerSecond
        self.maxFrameTime = maxFrameTime
    }

    /// Blend factor in `[0, 1)` between the previous and current simulation state.
    public var alpha: Double { accumulator / step }

    /// Consumes `deltaTime` and returns the number of simulation steps to run.
    public mutating func advance(by deltaTime: Double) -> Int {
        guard deltaTime.isFinite, deltaTime > 0 else { return 0 }
        accumulator += min(deltaTime, maxFrameTime)
        var steps = 0
        while accumulator >= step {
            accumulator -= step
            steps += 1
        }
        return steps
    }

    /// Discards buffered time. Used when resuming from pause or loading a scene,
    /// where the elapsed wall-clock time is not gameplay time.
    public mutating func reset() { accumulator = 0 }
}
