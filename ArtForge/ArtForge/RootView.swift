import SwiftUI

/// Two ways to make an image: the procedural engines, which need nothing but
/// the app, and the on-device diffusion model, which draws whatever you
/// describe once you have installed it.
struct RootView: View {
    var body: some View {
        TabView {
            ContentView()
                .tabItem { Label("Studio", systemImage: "paintbrush.pointed") }

            NavigationStack { ChatView() }
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }
        }
        .tint(Theme.accent)
    }
}
