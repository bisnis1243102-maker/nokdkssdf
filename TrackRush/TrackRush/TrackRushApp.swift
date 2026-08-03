import SwiftUI

@main
struct TrackRushApp: App {
    var body: some Scene {
        WindowGroup {
            MenuView()
                .preferredColorScheme(.dark)
        }
    }
}
