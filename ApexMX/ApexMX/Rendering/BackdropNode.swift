import SpriteKit
import UIKit

/// Sky, sun and parallax scenery.
///
/// Every layer is generated procedurally from the track's seed, so each course
/// gets its own skyline for free and none of it ships as art. Layers scroll at
/// a fraction of the camera speed, which is what gives the 2.5D depth cue.
public final class BackdropNode: SKNode {

    private struct Layer {
        let node: SKNode
        /// 0 is painted-on sky, 1 moves with the world.
        let parallaxFactor: CGFloat
        /// World-space width of one repeat, in points.
        let tileWidth: CGFloat
    }

    private let palette: EnvironmentPalette
    private var layers: [Layer] = []
    private let skyNode = SKSpriteNode()
    private let sunNode = SKShapeNode(circleOfRadius: 42)
    private let hazeNode = SKSpriteNode()

    private var viewSize: CGSize = .zero

    public init(track: TrackDefinition, palette: EnvironmentPalette, size: CGSize) {
        self.palette = palette
        super.init()
        self.viewSize = size

        zPosition = -100

        skyNode.zPosition = -100
        addChild(skyNode)

        sunNode.fillColor = palette.sunColor
        sunNode.strokeColor = .clear
        sunNode.glowWidth = 26
        sunNode.alpha = track.weather == .storm || track.weather == .overcast ? 0.35 : 0.9
        sunNode.zPosition = -95
        addChild(sunNode)

        var random = DeterministicRandom(seed: track.seed &* 31 &+ 7)
        layers.append(buildHillLayer(color: palette.farHills, amplitude: 120, baseline: 0.30,
                                     segments: 22, parallax: 0.12, random: &random, z: -90))
        layers.append(buildHillLayer(color: palette.midHills, amplitude: 78, baseline: 0.18,
                                     segments: 30, parallax: 0.26, random: &random, z: -80))
        layers.append(buildTreeLayer(color: palette.treeLine, parallax: 0.45,
                                     random: &random, z: -70))

        for layer in layers { addChild(layer.node) }

        hazeNode.color = palette.skyHorizon
        hazeNode.alpha = palette.hazeAlpha
        hazeNode.zPosition = -60
        addChild(hazeNode)

        resize(to: size)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("BackdropNode is created in code only") }

    public func resize(to size: CGSize) {
        viewSize = size
        // The sky is a single vertical gradient texture, regenerated only when
        // the view actually changes size.
        skyNode.texture = BackdropNode.gradientTexture(top: palette.skyTop,
                                                       bottom: palette.skyHorizon,
                                                       size: CGSize(width: 8, height: max(size.height, 64)))
        skyNode.size = CGSize(width: size.width * 1.2, height: size.height * 1.2)

        hazeNode.size = CGSize(width: size.width * 1.2, height: size.height * 0.35)
        hazeNode.position = CGPoint(x: 0, y: -size.height * 0.18)

        sunNode.position = CGPoint(x: size.width * 0.22, y: size.height * 0.28)
    }

    /// Scrolls each layer against the camera.
    ///
    /// - Parameter cameraPosition: Camera position in scene points.
    public func update(cameraPosition: CGPoint) {
        skyNode.position = cameraPosition
        hazeNode.position = CGPoint(x: cameraPosition.x,
                                    y: cameraPosition.y - viewSize.height * 0.18)
        sunNode.position = CGPoint(x: cameraPosition.x + viewSize.width * 0.22,
                                   y: cameraPosition.y + viewSize.height * 0.28)

        for layer in layers {
            // Move the layer with the camera, minus its share of the travel.
            let drift = cameraPosition.x * (1 - layer.parallaxFactor)
            // Wrap by the tile width so a finite strip of scenery covers an
            // unbounded track without ever running out.
            let wrapped = drift.truncatingRemainder(dividingBy: layer.tileWidth)
            layer.node.position = CGPoint(x: wrapped + cameraPosition.x - drift,
                                          y: cameraPosition.y * (1 - layer.parallaxFactor))
        }
    }

    // MARK: - Layer construction

    private func buildHillLayer(color: SKColor,
                                amplitude: CGFloat,
                                baseline: CGFloat,
                                segments: Int,
                                parallax: CGFloat,
                                random: inout DeterministicRandom,
                                z: CGFloat) -> Layer {
        // Three tiles are built so that wrapping never exposes an edge.
        let tileWidth: CGFloat = 2_400
        let container = SKNode()
        container.zPosition = z

        for tile in -1...1 {
            let shape = SKShapeNode()
            let path = CGMutablePath()
            let offset = CGFloat(tile) * tileWidth
            path.move(to: CGPoint(x: offset, y: -1_200))

            var heights: [CGFloat] = []
            for _ in 0...segments { heights.append(CGFloat(random.unit())) }
            // Force the ends to match so adjacent tiles join seamlessly.
            heights[segments] = heights[0]

            for i in 0...segments {
                let t = CGFloat(i) / CGFloat(segments)
                let x = offset + t * tileWidth
                let y = baseline * 400 + heights[i] * amplitude
                if i == 0 {
                    path.addLine(to: CGPoint(x: x, y: y))
                } else {
                    let previousX = offset + CGFloat(i - 1) / CGFloat(segments) * tileWidth
                    let previousY = baseline * 400 + heights[i - 1] * amplitude
                    path.addQuadCurve(to: CGPoint(x: x, y: y),
                                      control: CGPoint(x: (previousX + x) / 2,
                                                       y: max(previousY, y) + amplitude * 0.15))
                }
            }
            path.addLine(to: CGPoint(x: offset + tileWidth, y: -1_200))
            path.closeSubpath()

            shape.path = path
            shape.fillColor = color
            shape.strokeColor = .clear
            container.addChild(shape)
        }

        return Layer(node: container, parallaxFactor: parallax, tileWidth: tileWidth)
    }

    private func buildTreeLayer(color: SKColor,
                                parallax: CGFloat,
                                random: inout DeterministicRandom,
                                z: CGFloat) -> Layer {
        let tileWidth: CGFloat = 1_600
        let container = SKNode()
        container.zPosition = z

        for tile in -1...1 {
            let offset = CGFloat(tile) * tileWidth
            var x: CGFloat = 0
            while x < tileWidth {
                let height = CGFloat(random.range(46, 96))
                let width = height * CGFloat(random.range(0.42, 0.62))
                let tree = SKShapeNode()
                let path = CGMutablePath()
                // A simple conifer silhouette: two stacked tapers.
                path.move(to: CGPoint(x: -width / 2, y: 0))
                path.addLine(to: CGPoint(x: 0, y: height))
                path.addLine(to: CGPoint(x: width / 2, y: 0))
                path.closeSubpath()
                tree.path = path
                tree.fillColor = color.withBrightness(CGFloat(random.range(0.82, 1.12)))
                tree.strokeColor = .clear
                tree.position = CGPoint(x: offset + x, y: CGFloat(random.range(-16, 18)))
                container.addChild(tree)
                x += CGFloat(random.range(26, 62))
            }
        }

        return Layer(node: container, parallaxFactor: parallax, tileWidth: tileWidth)
    }

    /// Renders a vertical two-stop gradient into a texture once, rather than
    /// blending it per frame.
    private static func gradientTexture(top: SKColor, bottom: SKColor, size: CGSize) -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: [top.cgColor, bottom.cgColor] as CFArray,
                                            locations: [0, 1]) else { return }
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: size.height),
                options: []
            )
        }
        return SKTexture(image: image)
    }
}
