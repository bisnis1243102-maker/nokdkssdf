import SwiftUI
import SpriteKit

struct ContentView: View {
    @State private var scene: GameScene = {
        let s = GameScene()
        s.scaleMode = .resizeFill
        return s
    }()

    var body: some View {
        GeometryReader { geo in
            SpriteView(scene: configured(size: geo.size))
                .ignoresSafeArea()
        }
        .statusBarHidden(true)
    }

    private func configured(size: CGSize) -> GameScene {
        scene.size = size
        return scene
    }
}

#Preview {
    ContentView()
}
