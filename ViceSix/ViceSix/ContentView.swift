import SwiftUI
import SceneKit

struct ContentView: View {
    @StateObject private var gameState = GameState()
    @State private var controller = GameController()

    var body: some View {
        ZStack {
            SceneView(scene: configuredController.scene,
                      pointOfView: controller.cameraNode,
                      options: [.rendersContinuously],
                      delegate: controller)
                .ignoresSafeArea()

            switch gameState.phase {
            case .menu:
                MenuView(hasSave: gameState.hasSave,
                         onContinue: { controller.perform(.start(newGame: false)) },
                         onNewGame: { controller.perform(.start(newGame: true)) })
            case .playing:
                HUDView(gameState: gameState, controller: controller)
            case .busted:
                EndCardView(title: "BUSTED",
                            color: .blue,
                            message: "The VCPD took $\(GameConfig.bustedFine) and your ride.",
                            button: "WALK IT OFF",
                            action: { controller.perform(.respawnArrest) })
            case .wasted:
                EndCardView(title: "WASTED",
                            color: .red,
                            message: "You woke up at Mercy General, $\(GameConfig.wastedFee) lighter.",
                            button: "GET UP",
                            action: { controller.perform(.respawnWasted) })
            case .finale:
                EndCardView(title: "VI / VI",
                            color: .cyan,
                            message: "All six missions passed. Port Leon is yours, \(gameState.character.rawValue).",
                            button: "KEEP CRUISING",
                            action: { controller.perform(.keepRoaming) })
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    private var configuredController: GameController {
        controller.gameState = gameState
        return controller
    }
}

// MARK: - HUD

private struct HUDView: View {
    @ObservedObject var gameState: GameState
    let controller: GameController

    var body: some View {
        ZStack {
            VStack {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        MinimapView(model: gameState.minimapModel,
                                    snapshot: gameState.minimap)
                            .frame(width: 128, height: 128)
                        Text(gameState.districtName)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                            .shadow(radius: 2)
                    }

                    Spacer()

                    VStack(spacing: 4) {
                        if let banner = gameState.banner {
                            Text(banner)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.black.opacity(0.55)))
                        }
                        if let objective = gameState.objectiveText {
                            HStack(spacing: 8) {
                                if let title = gameState.missionTitle {
                                    Text(title.uppercased())
                                        .foregroundColor(.cyan)
                                }
                                Text(objective)
                                if let t = gameState.objectiveSecondsLeft {
                                    Text("\(t / 60):\(String(format: "%02d", t % 60))")
                                        .monospacedDigit()
                                        .foregroundColor(t <= 10 ? .red : .yellow)
                                }
                            }
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: 420)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        WantedStarsView(wanted: gameState.wanted)
                        Text("$\(gameState.cash)")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundColor(Color(red: 0.5, green: 0.95, blue: 0.55))
                            .shadow(radius: 2)
                        BarView(fraction: gameState.health / GameConfig.maxHealth,
                                colors: [.red, .orange, .green])
                            .frame(width: 130, height: 10)
                        if gameState.inVehicle {
                            BarView(fraction: gameState.vehicleHealth,
                                    colors: [.gray, .cyan])
                                .frame(width: 130, height: 7)
                            HStack(spacing: 6) {
                                Text(gameState.vehicleName ?? "")
                                Text("\(gameState.speedKMH) km/h").monospacedDigit()
                            }
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.85))
                        }
                    }
                }
                Spacer()
            }
            .padding(14)

            // The joystick, bottom left.
            VStack {
                Spacer()
                HStack {
                    JoystickPad(controls: controller.controls)
                        .padding(.leading, 30)
                        .padding(.bottom, 26)
                    Spacer()
                }
            }

            // Action buttons, bottom right.
            VStack(alignment: .trailing, spacing: 14) {
                Spacer()
                HStack(spacing: 14) {
                    if !gameState.inVehicle {
                        ActionButton(symbol: "person.2.fill",
                                     label: gameState.character.other.rawValue) {
                            controller.perform(.swap)
                        }
                    }
                    ActionButton(symbol: gameState.inVehicle
                                    ? "speaker.wave.2.fill" : "hand.raised.fill",
                                 label: gameState.inVehicle ? "HORN" : "PUNCH") {
                        controller.perform(.primary)
                    }
                    if gameState.inVehicle || gameState.canEnterVehicle {
                        ActionButton(symbol: "car.fill",
                                     label: gameState.inVehicle ? "EXIT" : "ENTER",
                                     highlighted: true) {
                            controller.perform(.toggleVehicle)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(20)
        }
    }
}

private struct ActionButton: View {
    let symbol: String
    let label: String
    var highlighted = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 22, weight: .bold))
                Text(label).font(.system(size: 9, weight: .heavy, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(width: 62, height: 62)
            .background(Circle().fill(highlighted
                ? Color(red: 0.95, green: 0.25, blue: 0.5).opacity(0.75)
                : Color.black.opacity(0.45)))
            .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1.5))
        }
    }
}

private struct WantedStarsView: View {
    let wanted: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<GameConfig.maxWanted, id: \.self) { i in
                Image(systemName: i < wanted ? "star.fill" : "star")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(i < wanted ? .yellow : .white.opacity(0.35))
                    .shadow(radius: 1)
            }
        }
    }
}

private struct BarView: View {
    let fraction: CGFloat
    let colors: [Color]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.45))
                Capsule()
                    .fill(LinearGradient(colors: colors,
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, geo.size.width * min(1, max(0, fraction))))
            }
        }
    }
}

// MARK: - Minimap

private struct MinimapView: View {
    let model: MinimapModel
    let snapshot: MinimapSnapshot

    var body: some View {
        Canvas { context, size in
            let s = size.width / max(1, model.worldSize)
            func map(_ p: CGPoint) -> CGPoint {
                CGPoint(x: p.x * s, y: size.height - p.y * s)
            }

            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(red: 0.12, green: 0.12, blue: 0.15)))
            for block in model.blocks {
                let r = CGRect(x: block.rect.minX * s,
                               y: size.height - block.rect.maxY * s,
                               width: block.rect.width * s,
                               height: block.rect.height * s)
                context.fill(Path(r), with: .color(block.color))
            }
            if let giver = snapshot.giver {
                let p = map(giver)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
                             with: .color(.cyan))
            }
            if let target = snapshot.target {
                let p = map(target)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)),
                             with: .color(.yellow))
            }
            for cop in snapshot.cops {
                let p = map(cop)
                context.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)),
                             with: .color(.blue))
            }
            let p = map(snapshot.player)
            let a = -snapshot.heading
            var tri = Path()
            tri.move(to: CGPoint(x: p.x + cos(a) * 6, y: p.y + sin(a) * 6))
            tri.addLine(to: CGPoint(x: p.x + cos(a + 2.5) * 5, y: p.y + sin(a + 2.5) * 5))
            tri.addLine(to: CGPoint(x: p.x + cos(a - 2.5) * 5, y: p.y + sin(a - 2.5) * 5))
            tri.closeSubpath()
            context.fill(tri, with: .color(.white))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color.white.opacity(0.5), lineWidth: 1.5))
        .opacity(0.92)
    }
}

// MARK: - Menu & end cards

private struct MenuView: View {
    let hasSave: Bool
    let onContinue: () -> Void
    let onNewGame: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black.opacity(0.7), Color.black.opacity(0.2)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                VStack(spacing: 2) {
                    Text("VICE")
                        .font(.system(size: 58, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(
                            colors: [Color(red: 1, green: 0.4, blue: 0.7),
                                     Color(red: 0.95, green: 0.6, blue: 0.2)],
                            startPoint: .top, endPoint: .bottom))
                    Text("SIX")
                        .font(.system(size: 58, weight: .black, design: .rounded))
                        .foregroundStyle(LinearGradient(
                            colors: [.cyan, Color(red: 0.3, green: 0.4, blue: 1)],
                            startPoint: .top, endPoint: .bottom))
                }
                .shadow(color: .pink.opacity(0.6), radius: 16)

                Text("A Port Leon Story — now in 3D")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.85))

                VStack(spacing: 4) {
                    Text("Left stick: move & steer (camera relative)")
                    Text("Walk into the glowing beacon to start missions")
                    Text("Steal cars. Outrun the VCPD. Get paid.")
                }
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.65))

                HStack(spacing: 16) {
                    if hasSave {
                        BigButton(title: "CONTINUE",
                                  colors: [.cyan, Color(red: 0.3, green: 0.4, blue: 1)],
                                  action: onContinue)
                    }
                    BigButton(title: hasSave ? "NEW GAME" : "PLAY",
                              colors: [Color(red: 1, green: 0.4, blue: 0.7),
                                       Color(red: 0.9, green: 0.2, blue: 0.4)],
                              action: onNewGame)
                }
            }
            .padding(30)
        }
    }
}

private struct EndCardView: View {
    let title: String
    let color: Color
    let message: String
    let button: String
    let action: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(title)
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundColor(color)
                    .shadow(color: color.opacity(0.7), radius: 14)
                Text(message)
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                BigButton(title: button, colors: [color.opacity(0.9), color], action: action)
            }
            .padding(36)
        }
    }
}

private struct BigButton: View {
    let title: String
    let colors: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 34).padding(.vertical, 13)
                .background(Capsule().fill(LinearGradient(colors: colors,
                                                          startPoint: .top,
                                                          endPoint: .bottom)))
                .shadow(color: colors.first?.opacity(0.6) ?? .clear, radius: 10)
        }
    }
}

#Preview {
    ContentView()
}
