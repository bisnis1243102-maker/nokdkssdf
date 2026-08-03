import SwiftUI

/// Two ways to make an image: the procedural engines, which need nothing but
/// the app, and the on-device diffusion model, which draws whatever you
/// describe once you have installed it.
struct RootView: View {
    var body: some View {
        TabView {
            ContentView()
                .tabItem { Label("Studio", systemImage: "paintbrush.pointed") }

            NavigationStack { DiffusionView() }
                .tabItem { Label("AI", systemImage: "sparkles") }
        }
        .tint(Theme.accent)
    }
}
