import SpriteKit

/// Draws the ground.
///
/// Only the slice of track inside the camera window plus a margin is ever
/// converted to geometry, and the geometry is rebuilt only when the camera has
/// moved far enough to matter. A 900 m track therefore costs the same to draw
/// as a 90 m one.
public final class TerrainNode: SKNode {

    private let terrain: Terrain
    private let palette: EnvironmentPalette

    private let fillNode = SKShapeNode()
    private let surfaceNode = SKShapeNode()
    private let subsurfaceNode = SKShapeNode()

    /// Extra width built beyond each edge of the screen, in metres, so the
    /// player never sees geometry pop in at the edge of the display.
    private let margin: Double = 14
    /// How far the camera may move before the strip is rebuilt.
    private let rebuildThreshold: Double = 6

    private var builtCenterX: Double = .infinity
    private var builtHalfWidth: Double = 0

    public init(terrain: Terrain, palette: EnvironmentPalette) {
        self.terrain = terrain
        self.palette = palette
        super.init()

        subsurfaceNode.zPosition = 8
        fillNode.zPosition = 10
        surfaceNode.zPosition = 12

        fillNode.fillColor = palette.soil
        fillNode.strokeColor = .clear
        fillNode.lineWidth = 0

        subsurfaceNode.fillColor = palette.deepSoil
        subsurfaceNode.strokeColor = .clear

        surfaceNode.strokeColor = palette.topsoil
        surfaceNode.fillColor = .clear
        surfaceNode.lineWidth = 5
        surfaceNode.lineCap = .round
        surfaceNode.lineJoin = .round

        addChild(subsurfaceNode)
        addChild(fillNode)
        addChild(surfaceNode)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TerrainNode is created in code only") }

    /// Rebuilds the visible strip if the camera has moved far enough.
    public func update(cameraX: Double, visibleWidth: Double) {
        let halfWidth = visibleWidth / 2 + margin
        let movedFarEnough = abs(cameraX - builtCenterX) > rebuildThreshold
        let widthChanged = abs(halfWidth - builtHalfWidth) > 1
        guard movedFarEnough || widthChanged else { return }

        builtCenterX = cameraX
        builtHalfWidth = halfWidth
        rebuild(centerX: cameraX, halfWidth: halfWidth)
    }

    private func rebuild(centerX: Double, halfWidth: Double) {
        let startX = centerX - halfWidth
        let endX = centerX + halfWidth
        // One vertex per two terrain samples is indistinguishable from full
        // resolution at gameplay zoom and halves the vertex count.
        let step = Terrain.sampleSpacing * 2
        let points = terrain.profile(from: startX, to: endX, step: step)
        guard points.count > 1 else { return }

        let floor = terrain.minimumHeight - 30

        let outline = CGMutablePath()
        outline.move(to: RenderScale.point(points[0]))
        for point in points.dropFirst() {
            outline.addLine(to: RenderScale.point(point))
        }
        surfaceNode.path = outline

        let solid = CGMutablePath()
        solid.move(to: RenderScale.point(Vector2(startX, floor)))
        for point in points {
            solid.addLine(to: RenderScale.point(point))
        }
        solid.addLine(to: RenderScale.point(Vector2(endX, floor)))
        solid.closeSubpath()
        fillNode.path = solid

        // A darker band a little below the surface reads as a soil layer and
        // gives the ground depth without a texture.
        let band = CGMutablePath()
        let bandDepth = 1.1
        band.move(to: RenderScale.point(Vector2(startX, floor)))
        for point in points {
            band.addLine(to: RenderScale.point(Vector2(point.x, point.y - bandDepth)))
        }
        band.addLine(to: RenderScale.point(Vector2(endX, floor)))
        band.closeSubpath()
        subsurfaceNode.path = band
    }
}

/// The colours that define a track's look, derived from its surface, weather
/// and time of day.
///
/// Keeping this as one small value type means art direction for a new track is
/// a data change: no new shaders, no new assets, no code.
public struct EnvironmentPalette {

    public let skyTop: SKColor
    public let skyHorizon: SKColor
    public let sunColor: SKColor
    public let farHills: SKColor
    public let midHills: SKColor
    public let treeLine: SKColor
    public let soil: SKColor
    public let deepSoil: SKColor
    public let topsoil: SKColor
    public let hazeAlpha: CGFloat

    public static func make(for track: TrackDefinition) -> EnvironmentPalette {
        let sky = skyColors(for: track.timeOfDay, weather: track.weather)
        let ground = groundColors(for: track.baseSurface, timeOfDay: track.timeOfDay)
        return EnvironmentPalette(
            skyTop: sky.top,
            skyHorizon: sky.horizon,
            sunColor: sky.sun,
            farHills: sky.horizon.blended(with: ground.soil, fraction: 0.35),
            midHills: sky.horizon.blended(with: ground.soil, fraction: 0.58),
            treeLine: SKColor(red: 0.16, green: 0.28, blue: 0.18, alpha: 1)
                .blended(with: sky.horizon, fraction: 0.25),
            soil: ground.soil,
            deepSoil: ground.deepSoil,
            topsoil: ground.topsoil,
            hazeAlpha: hazeAlpha(for: track.weather)
        )
    }

    private static func skyColors(for time: TimeOfDay,
                                  weather: WeatherPreset) -> (top: SKColor, horizon: SKColor, sun: SKColor) {
        var top: SKColor
        var horizon: SKColor
        var sun: SKColor

        switch time {
        case .sunrise:
            top = SKColor(red: 0.16, green: 0.24, blue: 0.44, alpha: 1)
            horizon = SKColor(red: 0.95, green: 0.62, blue: 0.42, alpha: 1)
            sun = SKColor(red: 1.00, green: 0.83, blue: 0.60, alpha: 1)
        case .morning:
            top = SKColor(red: 0.26, green: 0.53, blue: 0.83, alpha: 1)
            horizon = SKColor(red: 0.73, green: 0.86, blue: 0.95, alpha: 1)
            sun = SKColor(red: 1.00, green: 0.97, blue: 0.88, alpha: 1)
        case .midday:
            top = SKColor(red: 0.20, green: 0.48, blue: 0.86, alpha: 1)
            horizon = SKColor(red: 0.78, green: 0.89, blue: 0.98, alpha: 1)
            sun = SKColor(white: 1.0, alpha: 1)
        case .afternoon:
            top = SKColor(red: 0.28, green: 0.52, blue: 0.80, alpha: 1)
            horizon = SKColor(red: 0.88, green: 0.87, blue: 0.82, alpha: 1)
            sun = SKColor(red: 1.00, green: 0.95, blue: 0.80, alpha: 1)
        case .goldenHour:
            top = SKColor(red: 0.24, green: 0.36, blue: 0.62, alpha: 1)
            horizon = SKColor(red: 0.98, green: 0.74, blue: 0.44, alpha: 1)
            sun = SKColor(red: 1.00, green: 0.86, blue: 0.55, alpha: 1)
        case .sunset:
            top = SKColor(red: 0.17, green: 0.20, blue: 0.44, alpha: 1)
            horizon = SKColor(red: 0.94, green: 0.48, blue: 0.36, alpha: 1)
            sun = SKColor(red: 1.00, green: 0.68, blue: 0.42, alpha: 1)
        case .night:
            top = SKColor(red: 0.04, green: 0.05, blue: 0.14, alpha: 1)
            horizon = SKColor(red: 0.12, green: 0.15, blue: 0.28, alpha: 1)
            sun = SKColor(red: 0.82, green: 0.86, blue: 1.00, alpha: 1)
        }

        // Weather desaturates and flattens the sky rather than replacing it, so
        // the time of day still reads through the conditions.
        let grey = SKColor(white: 0.62, alpha: 1)
        switch weather {
        case .sunny:
            break
        case .cloudy:
            top = top.blended(with: grey, fraction: 0.18)
            horizon = horizon.blended(with: grey, fraction: 0.14)
        case .overcast:
            top = top.blended(with: grey, fraction: 0.42)
            horizon = horizon.blended(with: grey, fraction: 0.38)
        case .rain:
            top = top.blended(with: SKColor(white: 0.42, alpha: 1), fraction: 0.55)
            horizon = horizon.blended(with: SKColor(white: 0.50, alpha: 1), fraction: 0.50)
        case .storm:
            top = top.blended(with: SKColor(white: 0.22, alpha: 1), fraction: 0.68)
            horizon = horizon.blended(with: SKColor(white: 0.34, alpha: 1), fraction: 0.60)
        case .fog:
            top = top.blended(with: SKColor(white: 0.78, alpha: 1), fraction: 0.45)
            horizon = horizon.blended(with: SKColor(white: 0.85, alpha: 1), fraction: 0.62)
        }

        return (top, horizon, sun)
    }

    private static func groundColors(for surface: SurfaceType,
                                     timeOfDay: TimeOfDay) -> (soil: SKColor, deepSoil: SKColor, topsoil: SKColor) {
        let base = surface.properties.particleColor
        let soil = SKColor(red: CGFloat(base.r), green: CGFloat(base.g), blue: CGFloat(base.b), alpha: 1)
        let warm = timeOfDay == .goldenHour || timeOfDay == .sunset
        let tinted = warm ? soil.blended(with: SKColor(red: 1, green: 0.75, blue: 0.45, alpha: 1),
                                         fraction: 0.18) : soil
        return (soil: tinted,
                deepSoil: tinted.withBrightness(0.62),
                topsoil: tinted.withBrightness(1.28))
    }

    private static func hazeAlpha(for weather: WeatherPreset) -> CGFloat {
        switch weather {
        case .sunny: return 0.10
        case .cloudy: return 0.14
        case .overcast: return 0.20
        case .rain: return 0.30
        case .storm: return 0.38
        case .fog: return 0.55
        }
    }
}

extension SKColor {
    /// Linear blend toward another colour. `fraction` of 1 returns `other`.
    func blended(with other: SKColor, fraction: CGFloat) -> SKColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        guard getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2) else { return self }
        let t = min(max(fraction, 0), 1)
        return SKColor(red: r1 + (r2 - r1) * t,
                       green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t,
                       alpha: a1 + (a2 - a1) * t)
    }
}
