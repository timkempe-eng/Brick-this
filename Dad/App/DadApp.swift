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

        // The same app on a phone whose owner runs it in Assistive Access:
        // one sentence, one thing to do, nothing to navigate. Declared
        // alongside `WindowGroup` rather than replacing it — iOS picks this
        // scene only while Assistive Access is on, so the two are the same
        // app and the same session, drawn for two different phones.
        //
        // `SceneBuilder.buildLimitedAvailability` is what lets a scene be
        // gated this way (iOS 16.1); the scene type itself is iOS 26, and the
        // deployment target is 17. Below 26 the app simply renders its
        // standard UI in the frame Assistive Access gives it, which is what it
        // does today.
        if #available(iOS 26.0, *) {
            AssistiveAccess {
                AssistiveAccessView()
                    .environmentObject(model)
                    .onOpenURL { model.handleIncoming(url: $0) }
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active { model.reconcile() }
                    }
            }
        }
    }
}
