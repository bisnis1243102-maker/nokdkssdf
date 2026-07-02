import SwiftUI

/// Shared control state: SwiftUI gestures write it on the main thread and
/// the render loop reads it each frame. Plain value reads keep it simple.
final class TouchControls {
    var vector = CGVector.zero      // x right, y up, length 0...1
    var active = false

    func set(dx: CGFloat, dy: CGFloat) {
        let mag = min(1, hypot(dx, dy))
        let a = atan2(dy, dx)
        vector = CGVector(dx: cos(a) * mag, dy: sin(a) * mag)
        active = mag > 0.05
    }

    func clear() {
        vector = .zero
        active = false
    }
}

/// Fixed on-screen joystick, bottom-left. Push up to move away from the
/// camera; the controller makes it camera-relative like a modern
/// third-person game.
struct JoystickPad: View {
    let controls: TouchControls
    @State private var knob = CGSize.zero

    private let radius: CGFloat = 62

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
                .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 2))
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .fill(Color.white.opacity(0.35))
                .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 2))
                .frame(width: 56, height: 56)
                .offset(knob)
        }
        .contentShape(Circle().scale(1.7))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    let dist = max(1, hypot(dx, dy))
                    let clamped = min(dist, radius)
                    knob = CGSize(width: dx / dist * clamped,
                                  height: dy / dist * clamped)
                    controls.set(dx: dx / radius, dy: -dy / radius)
                }
                .onEnded { _ in
                    knob = .zero
                    controls.clear()
                }
        )
    }
}
