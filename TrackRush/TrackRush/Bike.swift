import SpriteKit

/// All the drawing for the bike and rider.
///
/// Kept apart from the physics so the shapes can be fussed over without going
/// anywhere near the simulation. Everything is built from paths rather than
/// image assets, so it stays sharp at any zoom and the app ships no artwork.
enum BikeArt {

    static let orange = SKColor(red: 0.98, green: 0.46, blue: 0.10, alpha: 1)
    static let darkMetal = SKColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1)
    static let midMetal = SKColor(red: 0.34, green: 0.36, blue: 0.41, alpha: 1)
    static let gear = SKColor(red: 0.11, green: 0.13, blue: 0.18, alpha: 1)
    static let skin = SKColor(red: 0.85, green: 0.66, blue: 0.52, alpha: 1)

    // MARK: Wheel

    /// A knobby dirt tyre: black carcass, bright rim, spokes, and tread blocks
    /// around the edge so rotation reads clearly at speed.
    static func wheel(radius: CGFloat) -> SKNode {
        let node = SKNode()

        let tyre = SKShapeNode(circleOfRadius: radius)
        tyre.fillColor = SKColor(white: 0.10, alpha: 1)
        tyre.strokeColor = SKColor(white: 0.05, alpha: 1)
        tyre.lineWidth = 1
        node.addChild(tyre)

        // Tread blocks, alternating in and out around the circumference.
        let blocks = 16
        for i in 0..<blocks {
            let angle = CGFloat(i) / CGFloat(blocks) * .pi * 2
            let block = SKShapeNode(rectOf: CGSize(width: radius * 0.26, height: radius * 0.2),
                                    cornerRadius: 1.2)
            block.fillColor = SKColor(white: 0.18, alpha: 1)
            block.strokeColor = .clear
            block.position = CGPoint(x: cos(angle) * (radius - 1.5), y: sin(angle) * (radius - 1.5))
            block.zRotation = angle
            node.addChild(block)
        }

        let rim = SKShapeNode(circleOfRadius: radius * 0.62)
        rim.fillColor = SKColor(white: 0.14, alpha: 1)
        rim.strokeColor = orange
        rim.lineWidth = 2.4
        node.addChild(rim)

        // Spokes.
        for i in 0..<8 {
            let angle = CGFloat(i) / 8 * .pi * 2
            let spoke = SKShapeNode(rectOf: CGSize(width: 1.4, height: radius * 1.18))
            spoke.fillColor = SKColor(white: 0.72, alpha: 0.85)
            spoke.strokeColor = .clear
            spoke.zRotation = angle
            node.addChild(spoke)
        }

        let hub = SKShapeNode(circleOfRadius: radius * 0.2)
        hub.fillColor = midMetal
        hub.strokeColor = SKColor(white: 0.8, alpha: 0.8)
        hub.lineWidth = 1.2
        node.addChild(hub)

        return node
    }

    // MARK: Bike body

    /// The machine, drawn around an origin at the middle of the wheelbase.
    /// `rearAxle` and `frontAxle` are where the wheels actually sit, so the
    /// swingarm and forks line up with the physics rather than merely looking
    /// like they might.
    static func body(rearAxle: CGPoint, frontAxle: CGPoint) -> SKNode {
        let node = SKNode()

        func line(from a: CGPoint, to b: CGPoint, width: CGFloat, color: SKColor, z: CGFloat = 0) {
            let path = CGMutablePath()
            path.move(to: a)
            path.addLine(to: b)
            let shape = SKShapeNode(path: path)
            shape.strokeColor = color
            shape.lineWidth = width
            shape.lineCap = .round
            shape.zPosition = z
            node.addChild(shape)
        }

        // Rear shock and swingarm.
        line(from: rearAxle, to: CGPoint(x: -6, y: 2), width: 6, color: darkMetal, z: -1)
        line(from: CGPoint(x: -20, y: -2), to: CGPoint(x: -8, y: 16), width: 4, color: midMetal, z: -1)

        // Front forks, angled back the way a real fork rakes.
        line(from: frontAxle, to: CGPoint(x: 22, y: 20), width: 5, color: midMetal, z: -1)
        line(from: CGPoint(x: 22, y: 20), to: CGPoint(x: 17, y: 27), width: 4, color: darkMetal, z: -1)

        // Exhaust.
        line(from: CGPoint(x: -4, y: 4), to: CGPoint(x: -26, y: 12), width: 4.5,
             color: SKColor(white: 0.62, alpha: 1), z: -2)

        // Engine block.
        let engine = SKShapeNode(rectOf: CGSize(width: 22, height: 15), cornerRadius: 3)
        engine.fillColor = darkMetal
        engine.strokeColor = SKColor(white: 0.45, alpha: 0.9)
        engine.lineWidth = 1.2
        engine.position = CGPoint(x: -2, y: 2)
        node.addChild(engine)

        // Fuel tank and shroud: the main orange mass.
        let tank = CGMutablePath()
        tank.move(to: CGPoint(x: -12, y: 12))
        tank.addCurve(to: CGPoint(x: 14, y: 16),
                      control1: CGPoint(x: -2, y: 22), control2: CGPoint(x: 6, y: 22))
        tank.addLine(to: CGPoint(x: 18, y: 10))
        tank.addCurve(to: CGPoint(x: -12, y: 12),
                      control1: CGPoint(x: 8, y: 6), control2: CGPoint(x: -4, y: 6))
        tank.closeSubpath()
        let tankShape = SKShapeNode(path: tank)
        tankShape.fillColor = orange
        tankShape.strokeColor = SKColor(white: 0.05, alpha: 0.55)
        tankShape.lineWidth = 1.4
        node.addChild(tankShape)

        // Rear fender and seat.
        let seat = CGMutablePath()
        seat.move(to: CGPoint(x: -13, y: 13))
        seat.addLine(to: CGPoint(x: -30, y: 17))
        seat.addLine(to: CGPoint(x: -31, y: 12))
        seat.addLine(to: CGPoint(x: -13, y: 9))
        seat.closeSubpath()
        let seatShape = SKShapeNode(path: seat)
        seatShape.fillColor = gear
        seatShape.strokeColor = .clear
        node.addChild(seatShape)

        // Front number plate.
        let plate = SKShapeNode(rectOf: CGSize(width: 12, height: 10), cornerRadius: 2.5)
        plate.fillColor = SKColor(white: 0.94, alpha: 1)
        plate.strokeColor = SKColor(white: 0.1, alpha: 0.7)
        plate.lineWidth = 1
        plate.position = CGPoint(x: 24, y: 24)
        plate.zRotation = -0.25
        node.addChild(plate)

        // Handlebar.
        line(from: CGPoint(x: 13, y: 28), to: CGPoint(x: 21, y: 31), width: 3, color: darkMetal)

        return node
    }

    // MARK: Rider

    /// A rider in a riding stance, built so the whole thing can be leaned as
    /// one piece and the limbs still land where they should.
    static func rider() -> SKNode {
        let node = SKNode()

        func limb(_ points: [CGPoint], width: CGFloat, color: SKColor) {
            let path = CGMutablePath()
            path.move(to: points[0])
            for point in points.dropFirst() { path.addLine(to: point) }
            let shape = SKShapeNode(path: path)
            shape.strokeColor = color
            shape.lineWidth = width
            shape.lineCap = .round
            shape.lineJoin = .round
            node.addChild(shape)
        }

        // Leg: hip to knee to boot on the peg.
        limb([CGPoint(x: -8, y: 16), CGPoint(x: 2, y: 8), CGPoint(x: -3, y: 0)],
             width: 7, color: gear)
        let boot = SKShapeNode(rectOf: CGSize(width: 9, height: 5), cornerRadius: 2)
        boot.fillColor = SKColor(white: 0.08, alpha: 1)
        boot.strokeColor = .clear
        boot.position = CGPoint(x: -1, y: -1)
        node.addChild(boot)

        // Torso, leaning forward over the tank.
        let torso = CGMutablePath()
        torso.move(to: CGPoint(x: -10, y: 15))
        torso.addLine(to: CGPoint(x: -3, y: 30))
        torso.addLine(to: CGPoint(x: 6, y: 29))
        torso.addLine(to: CGPoint(x: -1, y: 13))
        torso.closeSubpath()
        let torsoShape = SKShapeNode(path: torso)
        torsoShape.fillColor = SKColor(red: 0.16, green: 0.44, blue: 0.78, alpha: 1)
        torsoShape.strokeColor = SKColor(white: 0.05, alpha: 0.4)
        torsoShape.lineWidth = 1
        node.addChild(torsoShape)

        // Arm reaching to the bar.
        limb([CGPoint(x: 2, y: 27), CGPoint(x: 11, y: 22), CGPoint(x: 15, y: 17)],
             width: 5.5, color: SKColor(red: 0.20, green: 0.52, blue: 0.86, alpha: 1))
        let glove = SKShapeNode(circleOfRadius: 3)
        glove.fillColor = SKColor(white: 0.1, alpha: 1)
        glove.strokeColor = .clear
        glove.position = CGPoint(x: 16, y: 17)
        node.addChild(glove)

        // Helmet: shell, peak, and visor.
        let helmet = SKShapeNode(circleOfRadius: 8.5)
        helmet.fillColor = SKColor(white: 0.96, alpha: 1)
        helmet.strokeColor = SKColor(white: 0.1, alpha: 0.55)
        helmet.lineWidth = 1.2
        helmet.position = CGPoint(x: 1, y: 35)
        node.addChild(helmet)

        let visor = CGMutablePath()
        visor.addArc(center: CGPoint(x: 1, y: 35), radius: 8.5,
                     startAngle: -0.55, endAngle: 0.5, clockwise: false)
        visor.addLine(to: CGPoint(x: 1, y: 35))
        visor.closeSubpath()
        let visorShape = SKShapeNode(path: visor)
        visorShape.fillColor = SKColor(red: 0.12, green: 0.16, blue: 0.24, alpha: 1)
        visorShape.strokeColor = .clear
        node.addChild(visorShape)

        let peak = SKShapeNode(rectOf: CGSize(width: 11, height: 2.6), cornerRadius: 1.2)
        peak.fillColor = orange
        peak.strokeColor = .clear
        peak.position = CGPoint(x: 7, y: 41)
        peak.zRotation = 0.25
        node.addChild(peak)

        return node
    }
}
