import Foundation

/// A sampled ground profile.
///
/// The track is stored as a uniformly spaced height field rather than as
/// arbitrary polygons. That choice makes every query the simulation needs —
/// height, slope, surface material — an O(1) lookup with no broad phase, which
/// is what keeps the physics cheap enough to run several riders at 240 Hz.
public struct Terrain: Sendable {

    /// Horizontal distance between samples, in metres. 0.25 m resolves whoops
    /// and jump faces accurately while keeping a 900 m track under 4,000 samples.
    public static let sampleSpacing: Double = 0.25

    private let heights: [Double]
    private let surfaces: [SurfaceType]

    /// World-space x of the first sample.
    public let originX: Double

    public init(heights: [Double], surfaces: [SurfaceType], originX: Double = 0) {
        precondition(heights.count >= 2, "Terrain needs at least two samples")
        precondition(surfaces.count == heights.count, "Every height sample needs a surface")
        self.heights = heights
        self.surfaces = surfaces
        self.originX = originX
    }

    /// World-space x of the last sample.
    public var endX: Double { originX + Double(heights.count - 1) * Terrain.sampleSpacing }

    public var sampleCount: Int { heights.count }

    /// Continuous index into the height array for a world position, clamped to
    /// the track so that off-track queries return sane values instead of crashing.
    private func continuousIndex(at x: Double) -> Double {
        let raw = (x - originX) / Terrain.sampleSpacing
        return MathUtils.clamp(raw, 0, Double(heights.count - 1))
    }

    /// Ground height at a world x, linearly interpolated between samples.
    public func height(at x: Double) -> Double {
        let index = continuousIndex(at: x)
        let lower = Int(index)
        let upper = min(lower + 1, heights.count - 1)
        let t = index - Double(lower)
        return MathUtils.lerp(heights[lower], heights[upper], t)
    }

    /// Ground gradient (dy/dx) at a world x, from a central difference.
    ///
    /// A central difference is used rather than the slope of the containing
    /// segment because it is continuous across sample boundaries; a
    /// discontinuous normal makes tyres chatter on smooth ground.
    public func gradient(at x: Double) -> Double {
        let h = Terrain.sampleSpacing
        let ahead = height(at: x + h)
        let behind = height(at: x - h)
        return (ahead - behind) / (2 * h)
    }

    /// Upward-facing unit normal at a world x.
    public func normal(at x: Double) -> Vector2 {
        let g = gradient(at: x)
        return Vector2(-g, 1).normalized
    }

    /// Unit vector pointing along the surface in the +x direction.
    public func tangent(at x: Double) -> Vector2 {
        let g = gradient(at: x)
        return Vector2(1, g).normalized
    }

    /// Slope angle in radians; positive uphill in +x.
    public func slopeAngle(at x: Double) -> Double {
        atan(gradient(at: x))
    }

    /// Second derivative of the profile. Positive on a jump lip (convex),
    /// negative in a compression. The jump system uses this to decide how much
    /// of the launch is ramp shape and how much is suspension release.
    public func curvature(at x: Double) -> Double {
        let h = Terrain.sampleSpacing * 2
        return (gradient(at: x + h) - gradient(at: x - h)) / (2 * h)
    }

    public func surface(at x: Double) -> SurfaceType {
        let index = Int(continuousIndex(at: x).rounded())
        return surfaces[min(max(index, 0), surfaces.count - 1)]
    }

    /// Heights over a world-space range, for building render geometry.
    public func profile(from startX: Double, to endX: Double, step: Double) -> [Vector2] {
        guard step > 0, endX > startX else { return [] }
        var points: [Vector2] = []
        points.reserveCapacity(Int((endX - startX) / step) + 2)
        var x = startX
        while x < endX {
            points.append(Vector2(x, height(at: x)))
            x += step
        }
        points.append(Vector2(endX, height(at: endX)))
        return points
    }

    /// Highest point on the track, used to frame cameras and minimaps.
    public var maximumHeight: Double { heights.max() ?? 0 }
    public var minimumHeight: Double { heights.min() ?? 0 }
}
