import SwiftUI

@main
struct TgApp: App {
    @StateObject private var tg = TG()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(tg)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
