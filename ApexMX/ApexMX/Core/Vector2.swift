import Foundation

/// A double-precision 2D vector used throughout the simulation.
///
/// The physics core deliberately avoids `CGPoint`/`SIMD` so that simulation
/// values stay in real-world units (metres, m/s, newtons) and remain
/// independent of any rendering framework.
public struct Vector2: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vector2(0, 0)

    public var length: Double { (x * x + y * y).squareRoot() }
    public var lengthSquared: Double { x * x + y * y }

    /// Unit vector in the same direction, or `.zero` for a degenerate vector.
    public var normalized: Vector2 {
        let l = length
        guard l > 1e-12 else { return .zero }
        return Vector2(x / l, y / l)
    }

    /// The vector rotated 90° counter-clockwise.
    public var perpendicular: Vector2 { Vector2(-y, x) }

    public func dot(_ other: Vector2) -> Double { x * other.x + y * other.y }

    /// The scalar z-component of the 3D cross product of two planar vectors.
    public func cross(_ other: Vector2) -> Double { x * other.y - y * other.x }

    public func rotated(by radians: Double) -> Vector2 {
        let c = cos(radians), s = sin(radians)
        return Vector2(x * c - y * s, x * s + y * c)
    }

    public static func + (a: Vector2, b: Vector2) -> Vector2 { Vector2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vector2, b: Vector2) -> Vector2 { Vector2(a.x - b.x, a.y - b.y) }
    public static prefix func - (v: Vector2) -> Vector2 { Vector2(-v.x, -v.y) }
    public static func * (v: Vector2, s: Double) -> Vector2 { Vector2(v.x * s, v.y * s) }
    public static func * (s: Double, v: Vector2) -> Vector2 { v * s }
    public static func / (v: Vector2, s: Double) -> Vector2 { Vector2(v.x / s, v.y / s) }
    public static func += (a: inout Vector2, b: Vector2) { a = a + b }
    public static func -= (a: inout Vector2, b: Vector2) { a = a - b }
    public static func *= (a: inout Vector2, s: Double) { a = a * s }

    /// A unit vector pointing `radians` counter-clockwise from the +x axis.
    public static func angled(_ radians: Double) -> Vector2 {
        Vector2(cos(radians), sin(radians))
    }
}
