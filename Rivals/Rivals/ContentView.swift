import SwiftUI
import SpriteKit

struct ContentView: View {
    @StateObject private var gameState = GameState()
    @State private var scene = GameScene()

    var body: some View {
        ZStack {
            SpriteView(scene: configuredScene)
                .ignoresSafeArea()

            switch gameState.phase {
            case .menu:
                MenuView(bestScore: gameState.bestScore, onPlay: startGame)
            case .playing:
                HUDView(gameState: gameState).padding()
            case .gameOver:
                GameOverView(score: gameState.score,
                             wave: gameState.wave,
                             bestScore: gameState.bestScore,
                             onRetry: startGame)
            }
        }
        .statusBarHidden(true)
    }

    private var configuredScene: GameScene {
        scene.gameState = gameState
        return scene
    }

    private func startGame() {
        gameState.phase = .playing
        scene.startGame()
    }
}

// MARK: - HUD

private struct HUDView: View {
    @ObservedObject var gameState: GameState

    var body: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SCORE \(gameState.score)")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                    healthBar
                        .frame(width: 160, height: 14)
                }
                Spacer()
                Text("WAVE \(gameState.wave)")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.12)))
            }
            Spacer()
        }
        .foregroundColor(.white)
    }

    private var healthBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule()
                    .fill(LinearGradient(colors: [.green, .yellow, .red],
                                         startPoint: .trailing, endPoint: .leading))
                    .frame(width: max(0, geo.size.width * gameState.healthFraction))
            }
        }
    }
}

// MARK: - Menu

private struct MenuView: View {
    let bestScore: Int
    let onPlay: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 24) {
                Text("RIVALS")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.cyan, .blue],
                                                    startPoint: .top, endPoint: .bottom))
                Text("Arena Shooter")
                    .font(.headline).foregroundColor(.white.opacity(0.8))

                VStack(spacing: 6) {
                    Text("Left side: move").foregroundColor(.white.opacity(0.7))
                    Text("Right side: aim & fire").foregroundColor(.white.opacity(0.7))
                    Text("Survive the waves!").foregroundColor(.white.opacity(0.7))
                }
                .font(.subheadline)

                if bestScore > 0 {
                    Text("Best: \(bestScore)")
                        .font(.headline).foregroundColor(.yellow)
                }

                PlayButton(title: "PLAY", action: onPlay)
            }
            .padding(40)
        }
    }
}

// MARK: - Game over

private struct GameOverView: View {
    let score: Int
    let wave: Int
    let bestScore: Int
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 18) {
                Text("GAME OVER")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundColor(.red)
                Text("Score \(score)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("Reached Wave \(wave)")
                    .font(.headline).foregroundColor(.white.opacity(0.8))
                Text(score >= bestScore ? "🏆 New Best!" : "Best: \(bestScore)")
                    .font(.headline).foregroundColor(.yellow)
                PlayButton(title: "PLAY AGAIN", action: onRetry)
            }
            .padding(40)
        }
    }
}

private struct PlayButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 48).padding(.vertical, 16)
                .background(
                    Capsule().fill(LinearGradient(colors: [.cyan, .blue],
                                                  startPoint: .top, endPoint: .bottom)))
                .shadow(color: .cyan.opacity(0.6), radius: 12)
        }
    }
}

#Preview {
    ContentView()
}
