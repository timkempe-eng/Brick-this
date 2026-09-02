import SwiftUI
import FamilyControls

@main
struct DadApp: App {
    @StateObject private var model = DadModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                // Background NFC reading and the Shortcuts automation both
                // arrive as a URL. Same entry point either way.
                .onOpenURL { model.handleIncoming(url: $0) }
                // A Shortcuts tap or the shield's emergency button can change
                // the session while the app is backgrounded, and a crash can
                // leave the shield disagreeing with the stored session. Both
                // are settled on the way back in.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.reconcile() }
                }
        }
    }
}
