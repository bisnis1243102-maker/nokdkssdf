import SpriteKit

/// Floating virtual joystick: it appears wherever the thumb lands on the
/// left side of the screen and reports a normalized direction vector.
final class Joystick: SKNode {
    private let base = SKShapeNode(circleOfRadius: 60)
    private let knob = SKShapeNode(circleOfRadius: 28)
    private let maxRadius: CGFloat = 60

    private(set) var vector = CGVector.zero
    private(set) var isActive = false
    /// The touch driving the stick, so other touches don't steal it.
    var trackedTouch: UITouch?

    /// Direction of the stick, radians. Only meaningful while active.
    var angle: CGFloat { atan2(vector.dy, vector.dx) }
    /// Deflection 0...1.
    var magnitude: CGFloat { min(1, hypot(vector.dx, vector.dy)) }

    override init() {
        super.init()
        base.fillColor = SKColor(white: 1, alpha: 0.07)
        base.strokeColor = SKColor(white: 1, alpha: 0.28)
        base.lineWidth = 2
        addChild(base)

        knob.fillColor = SKColor(white: 1, alpha: 0.32)
        knob.strokeColor = SKColor(white: 1, alpha: 0.55)
        knob.lineWidth = 2
        addChild(knob)

        alpha = 0
        zPosition = 200
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func begin(at point: CGPoint, touch: UITouch) {
        position = point
        knob.position = .zero
        vector = .zero
        isActive = true
        trackedTouch = touch
        alpha = 1
    }

    func move(to point: CGPoint) {
        let dx = point.x - position.x
        let dy = point.y - position.y
        let dist = hypot(dx, dy)
        guard dist > 0.01 else {
            vector = .zero
            knob.position = .zero
            return
        }
        let clamped = min(dist, maxRadius)
        let a = atan2(dy, dx)
        knob.position = CGPoint(x: cos(a) * clamped, y: sin(a) * clamped)
        vector = CGVector(dx: cos(a) * clamped / maxRadius,
                          dy: sin(a) * clamped / maxRadius)
    }

    func end() {
        isActive = false
        trackedTouch = nil
        vector = .zero
        knob.position = .zero
        alpha = 0
    }
}
