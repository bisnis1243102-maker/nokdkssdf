import SwiftUI

struct ContentView: View {
    @StateObject private var game = GameState()

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch game.screen {
            case .career:
                CareerView().environmentObject(game)
                    .transition(.opacity)
            case .garage:
                GarageView().environmentObject(game)
                    .transition(.opacity)
            case .rider:
                RiderView().environmentObject(game)
                    .transition(.opacity)
            case .settings:
                SettingsView().environmentObject(game)
                    .transition(.opacity)
            case .race(let ref):
                RaceView(ref: ref)
                    .environmentObject(game)
                    .id(ref.trackId)     // a fresh scene per entry
            case .podium:
                PodiumView().environmentObject(game)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: game.screen)
        .preferredColorScheme(.dark)
        .onAppear { Haptics.enabled = game.profile.hapticsOn }
    }
}
