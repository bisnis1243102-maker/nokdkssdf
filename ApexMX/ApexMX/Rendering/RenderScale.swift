import CoreGraphics
import Foundation

/// The single conversion between simulation units (metres) and screen units.
///
/// Every renderer goes through this rather than embedding its own constant,
/// which is what keeps the bike, the terrain, the particles and the HUD in
/// agreement about how big a metre is.
public enum RenderScale {
    /// Points per metre at the default zoom.
    public static let pointsPerMetre: CGFloat = 46

    public static func point(_ v: Vector2) -> CGPoint {
        CGPoint(x: CGFloat(v.x) * pointsPerMetre, y: CGFloat(v.y) * pointsPerMetre)
    }

    public static func length(_ metres: Double) -> CGFloat {
        CGFloat(metres) * pointsPerMetre
    }

    /// Screen points back to metres, for touch-driven camera controls.
    public static func metres(_ points: CGFloat) -> Double {
        Double(points / pointsPerMetre)
    }
}
