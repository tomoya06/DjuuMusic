import SwiftUI

@main
struct DjuuMusicApp: App {
    @State private var player = PlayerModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(player)
                .preferredColorScheme(.dark)
                .tint(.accentColor)
        }
    }
}
