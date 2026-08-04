import SwiftUI

@main
struct ApexMXApp: App {

    @StateObject private var coordinator = GameCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(coordinator)
                .preferredColorScheme(.dark)
                .persistentSystemOverlays(.hidden)
        }
        .onChange(of: scenePhase) { phase in
            // Progress must survive a suspension that never resumes, so the
            // write is synchronous here rather than queued.
            if phase != .active { coordinator.saveImmediately() }
        }
    }
}

/// Routes between screens.
///
/// Transitions are cross-fades rather than pushes: the game has no navigation
/// hierarchy to communicate, and a stack would imply one that does not exist.
struct RootView: View {

    @EnvironmentObject private var coordinator: GameCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.Palette.background.ignoresSafeArea()

            switch coordinator.route {
            case .mainMenu:
                MainMenuView().transition(fade)
            case .trackSelect:
                TrackSelectView().transition(fade)
            case .garage:
                GarageView().transition(fade)
            case .settings:
                SettingsView().transition(fade)
            case .profile:
                ProfileView().transition(fade)
            case .race:
                RaceView().transition(.opacity)
            case .results:
                ResultsView().transition(fade)
            }
        }
        .animation(Theme.Motion.respecting(reduceMotion, Theme.Motion.gentle),
                   value: coordinator.route)
        .onAppear {
            HapticEngine.shared.applySettings(coordinator.profile.settings)
        }
    }

    private var fade: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98))
    }
}
