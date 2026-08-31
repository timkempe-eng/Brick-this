import SwiftUI
import FamilyControls

@main
struct TimApp: App {
    @StateObject private var model = TimModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                // Background NFC reading and the Shortcuts automation both
                // arrive as a URL. Same entry point either way.
                .onOpenURL { model.handleIncoming(url: $0) }
        }
    }
}
