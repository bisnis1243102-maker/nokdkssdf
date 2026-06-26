import SpriteKit

/// A floating, on-demand virtual joystick. It appears wherever the player
/// first touches within its half of the screen and reports a normalized
/// direction vector (length 0...1).
final class Joystick: SKNode {
    private let base = SKShapeNode(circleOfRadius: 56)
    private let knob = SKShapeNode(circleOfRadius: 26)
    private let maxRadius: CGFloat = 56

    private(set) var vector: CGVector = .zero
    private(set) var isActive = false
    /// The touch currently driving this stick (so multi-touch sticks don't fight).
    var trackedTouch: UITouch?

    override init() {
        super.init()
        base.fillColor = SKColor(white: 1.0, alpha: 0.08)
        base.strokeColor = SKColor(white: 1.0, alpha: 0.25)
        base.lineWidth = 2
        addChild(base)

        knob.fillColor = SKColor(white: 1.0, alpha: 0.35)
        knob.strokeColor = SKColor(white: 1.0, alpha: 0.6)
        knob.lineWidth = 2
        addChild(knob)

        alpha = 0
        zPosition = 100
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var magnitude: CGFloat { hypot(vector.dx, vector.dy) }
    var angle: CGFloat { atan2(vector.dy, vector.dx) }

    func begin(at point: CGPoint, touch: UITouch) {
        position = point
        knob.position = .zero
        vector = .zero
        isActive = true
        trackedTouch = touch
        alpha = 1
    }

    func update(to point: CGPoint) {
        let dx = point.x - position.x
        let dy = point.y - position.y
        let dist = hypot(dx, dy)
        let clamped = min(dist, maxRadius)
        let a = atan2(dy, dx)
        knob.position = CGPoint(x: cos(a) * clamped, y: sin(a) * clamped)
        vector = CGVector(dx: cos(a) * (clamped / maxRadius),
                          dy: sin(a) * (clamped / maxRadius))
    }

    func end() {
        isActive = false
        trackedTouch = nil
        vector = .zero
        knob.position = .zero
        alpha = 0
    }
}
