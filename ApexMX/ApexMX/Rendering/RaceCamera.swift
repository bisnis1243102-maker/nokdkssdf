import SpriteKit

/// Follows the player without making anyone motion sick.
///
/// The camera never snaps and never tracks the bike exactly. It leads in the
/// direction of travel so the rider can see what is coming, pulls back with
/// speed and altitude, and adds a short, damped kick on hard landings. Every
/// response is exponential and frame-rate independent, so the feel is the same
/// at 30 and 120 Hz.
public struct RaceCamera {

    /// How far ahead of the bike the camera looks, per m/s of speed.
    private let leadPerSpeed: Double = 0.42
    /// Maximum look-ahead distance, in metres.
    private let maximumLead: Double = 9.5
    /// Height the camera sits above the bike at rest, in metres.
    private let baseHeight: Double = 1.6

    private var smoothedTarget: Vector2 = .zero
    private var smoothedZoom: Double = 1
    private var shake: Double = 0
    private var shakePhase: Double = 0
    private var initialised = false

    /// Reduced-motion mode halves the lead, removes shake and softens the zoom.
    public var reduceMotion: Bool = false

    public init() {}

    /// Advances the camera and returns its scene-space position and zoom.
    ///
    /// - Returns: `position` in scene points and `scale` to apply to the camera
    ///   node (values above 1 zoom out).
    public mutating func update(dt: Double,
                                bike: BikePhysicsBody,
                                terrain: Terrain,
                                viewportHeightMetres: Double) -> (position: CGPoint, scale: CGFloat) {
        let speed = max(bike.forwardSpeed, 0)
        let leadScale = reduceMotion ? 0.45 : 1.0
        let lead = min(speed * leadPerSpeed, maximumLead) * leadScale

        // Vertical framing blends between the bike and the ground beneath it, so
        // a big jump shows both the rider and the landing rather than only sky.
        let groundBelow = terrain.height(at: bike.position.x + lead)
        let altitude = max(bike.position.y - groundBelow, 0)
        let verticalBias = MathUtils.clamp(altitude * 0.35, 0, 4.5)

        let target = Vector2(bike.position.x + lead,
                             bike.position.y + baseHeight - verticalBias * 0.4)

        if !initialised {
            smoothedTarget = target
            smoothedZoom = 1
            initialised = true
        }

        // Horizontal tracking is stiffer than vertical: losing the rider
        // sideways is disorienting, while vertical float feels natural.
        smoothedTarget.x = MathUtils.damp(smoothedTarget.x, target.x, rate: 9.0, dt: dt)
        smoothedTarget.y = MathUtils.damp(smoothedTarget.y, target.y, rate: 5.0, dt: dt)

        // Zoom out with speed and with height, so fast sections and big air both
        // stay readable, then ease back in.
        let speedZoom = MathUtils.remap(speed, 8, 32, 1.0, 1.22)
        let altitudeZoom = MathUtils.remap(altitude, 1, 9, 1.0, 1.20)
        let targetZoom = reduceMotion
            ? MathUtils.lerp(1.0, max(speedZoom, altitudeZoom), 0.5)
            : max(speedZoom, altitudeZoom)
        smoothedZoom = MathUtils.damp(smoothedZoom, targetZoom, rate: 3.2, dt: dt)

        // Landing kick.
        if bike.didLandThisStep && !reduceMotion {
            let severity = MathUtils.clamp01(bike.lastLandingImpact / 14)
            shake = max(shake, severity * 0.5)
        }
        if bike.hasCrashed && !reduceMotion {
            shake = max(shake, 0.35)
        }
        shake = MathUtils.damp(shake, 0, rate: 5.5, dt: dt)
        shakePhase += dt * 42

        var offset = Vector2.zero
        if shake > 0.001 {
            // Two incommensurable frequencies avoid a mechanical-looking wobble.
            offset = Vector2(sin(shakePhase) * shake * 0.28,
                             sin(shakePhase * 1.63 + 1.1) * shake * 0.34)
        }

        let final = smoothedTarget + offset
        _ = viewportHeightMetres
        return (RenderScale.point(final), CGFloat(smoothedZoom))
    }

    /// Re-frames instantly. Used on restart, where smoothing would produce a
    /// long, useless pan across the track.
    public mutating func snap() {
        initialised = false
        shake = 0
    }
}
