import AppIntents
import Foundation

/// These are what make a tap feel like Brick's.
///
/// An NFC personal automation in Shortcuts can run an App Intent in the
/// background, with Tim closed and "Ask Before Running" off — so the tap
/// itself blocks or releases the apps and you never see our UI. That path
/// needs no website, no associated domain and nothing written to the tag.

struct ToggleTimIntent: AppIntent {
    static var title: LocalizedStringResource = "Tim my phone"
    static var description = IntentDescription(
        "Hides your chosen apps, or brings them back if your phone is already Timmed."
    )
    /// The whole point is that it runs without the app coming forward.
    static var openAppWhenRun = false

    @Parameter(title: "Mode", optionsProvider: ModeNameOptions())
    var modeName: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = TimStore.shared
        let requested = modeName.flatMap { name in
            store.modes.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }

        switch TimEngine.handleTap(tagUID: nil, preferredMode: requested) {
        case .timmed(let mode):
            return .result(dialog: "\(Vocab.verbPast). \(mode.name).")
        case .unTimmed(let session):
            return .result(dialog: "\(Vocab.sessionSummary(duration: session.duration.timDurationText))")
        case .needsModeChoice:
            throw $modeName.needsValueError("Which \(Vocab.modeNoun.lowercased())?")
        case .unknownTag:
            return .result(dialog: "That isn't one of your \(Vocab.tagNoun)s.")
        }
    }
}

/// One-directional variants, for when you'd rather an automation not toggle —
/// a tag by the bed that only ever Tims, for instance.
struct StartTimIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Timming"
    static var openAppWhenRun = false

    @Parameter(title: "Mode", optionsProvider: ModeNameOptions())
    var modeName: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = TimStore.shared
        guard !store.isTimmed else {
            return .result(dialog: "Already \(Vocab.verbPast.lowercased()).")
        }
        guard let name = modeName,
              let mode = store.modes.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }),
              mode.blocksAnything else {
            throw $modeName.needsValueError("Which \(Vocab.modeNoun.lowercased())?")
        }
        TimEngine.tim(with: mode)
        return .result(dialog: "\(Vocab.verbPast). \(mode.name).")
    }
}

struct StopTimIntent: AppIntent {
    static var title: LocalizedStringResource = "Un-Tim my phone"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let active = TimStore.shared.activeSession else {
            return .result(dialog: "Your phone isn't \(Vocab.verbPast.lowercased()).")
        }
        let finished = TimEngine.unTim(session: active, byEmergency: false)
        return .result(dialog: "\(Vocab.sessionSummary(duration: finished.duration.timDurationText))")
    }
}

struct TimStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Is my phone Timmed?"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Bool> {
        if let session = TimStore.shared.activeSession {
            return .result(
                value: true,
                dialog: "\(Vocab.verbPast) for \(session.duration.timDurationText) — \(session.modeName)."
            )
        }
        return .result(value: false, dialog: "\(Vocab.idleTitle).")
    }
}

/// Offers the user's own mode names in the Shortcuts editor, so building the
/// automation is a picker rather than typing a string that has to match.
struct ModeNameOptions: DynamicOptionsProvider {
    func results() async throws -> [String] {
        TimStore.shared.modes.filter(\.blocksAnything).map(\.name)
    }
}

struct TimShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleTimIntent(),
            phrases: [
                "Tim my phone with \(.applicationName)",
                "\(.applicationName) my phone",
            ],
            shortTitle: "Tim my phone",
            systemImageName: "lock.iphone"
        )
        AppShortcut(
            intent: StopTimIntent(),
            phrases: [
                "Un-Tim my phone with \(.applicationName)",
                "Unlock my phone with \(.applicationName)",
            ],
            shortTitle: "Un-Tim my phone",
            systemImageName: "lock.open.iphone"
        )
        AppShortcut(
            intent: TimStatusIntent(),
            phrases: [
                "Is my phone Timmed in \(.applicationName)",
            ],
            shortTitle: "Tim status",
            systemImageName: "questionmark.circle"
        )
    }
}
