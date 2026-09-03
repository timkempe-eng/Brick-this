import AppIntents
import Foundation

/// These are what make a tap feel like Brick's.
///
/// An NFC personal automation in Shortcuts can run an App Intent in the
/// background, with Dad closed and "Ask Before Running" off — so the tap
/// itself blocks or releases the apps and you never see our UI. That path
/// needs no website, no associated domain and nothing written to the tag.

struct ToggleDadIntent: AppIntent {
    static var title: LocalizedStringResource = "Dad my phone"
    static var description = IntentDescription(
        "Hides your chosen apps, or brings them back if your phone is already Dadded."
    )
    /// The whole point is that it runs without the app coming forward.
    static var openAppWhenRun = false

    @Parameter(title: "Mode", optionsProvider: ModeNameOptions())
    var modeName: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let engine = DadEngine.live
        let requested = modeName.flatMap { name in
            engine.store.modes.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }

        // A name that no longer matches anything — the Mode was renamed or
        // deleted after the automation was built — must stop here. Falling
        // through would let the sole-usable-mode fallback silently Dad with a
        // *different* Mode's blocklist.
        if modeName != nil, requested == nil, engine.store.activeSession == nil {
            throw $modeName.needsValueError(
                "\"\(modeName ?? "")\" isn't one of your \(Vocab.modeNoun)s any more — which one?")
        }

        switch engine.handleTap(preferredMode: requested) {
        case .dadded(let mode, let start):
            return .result(dialog: Self.dialog(mode: mode, start: start))
        case .unDadded(let session):
            return .result(dialog: "\(Vocab.sessionSummary(duration: session.duration.dadDurationText))")
        case .needsModeChoice:
            throw $modeName.needsValueError("Which \(Vocab.modeNoun.lowercased())?")
        case .unknownTag:
            return .result(dialog: "That isn't one of your \(Vocab.tagNoun)s.")
        }
    }

    /// Siri reads this aloud, so it has to be true. A rationing Mode has taken
    /// nothing away yet, and "Dadded. Deep Work." would tell someone their
    /// apps are gone while they are not.
    static func dialog(mode: DadMode, start: DadEngine.DadStart) -> String {
        switch start {
        case .blocking:
            return "\(Vocab.verbPast). \(mode.name)."
        case .rationing(let minutes):
            return "\(Vocab.verbPast). \(Vocab.allowanceRunning(mode: mode.name, minutes: minutes))"
        case .rationRefused:
            return "\(Vocab.verbPast). \(mode.name). \(Vocab.allowanceRefused)"
        }
    }
}

/// One-directional variants, for when you'd rather an automation not toggle —
/// a tag by the bed that only ever Dads, for instance.
struct StartDadIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Dadding"
    static var openAppWhenRun = false

    @Parameter(title: "Mode", optionsProvider: ModeNameOptions())
    var modeName: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let engine = DadEngine.live
        guard engine.store.activeSession == nil else {
            return .result(dialog: "Already \(Vocab.verbPast).")
        }
        guard let name = modeName,
              let mode = engine.store.modes.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }),
              mode.blocksAnything else {
            throw $modeName.needsValueError("Which \(Vocab.modeNoun.lowercased())?")
        }
        let start = engine.dad(with: mode)
        return .result(dialog: ToggleDadIntent.dialog(mode: mode, start: start))
    }
}

struct StopDadIntent: AppIntent {
    static var title: LocalizedStringResource = "Un-Dad my phone"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let finished = DadEngine.live.unDad(byEmergency: false) else {
            return .result(dialog: "Your phone isn't \(Vocab.verbPast).")
        }
        return .result(dialog: "\(Vocab.sessionSummary(duration: finished.duration.dadDurationText))")
    }
}

struct DadStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Is my phone Dadded?"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Bool> {
        if let session = DadEngine.live.store.activeSession {
            return .result(
                value: true,
                dialog: "\(Vocab.verbPast) for \(session.duration.dadDurationText) — \(session.modeName)."
            )
        }
        return .result(value: false, dialog: "\(Vocab.idleTitle).")
    }
}

/// Offers the user's own mode names in the Shortcuts editor, so building the
/// automation is a picker rather than typing a string that has to match.
struct ModeNameOptions: DynamicOptionsProvider {
    func results() async throws -> [String] {
        DadEngine.live.store.modes.filter(\.blocksAnything).map(\.name)
    }
}

struct DadShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleDadIntent(),
            phrases: [
                "Dad my phone with \(.applicationName)",
                "\(.applicationName) my phone",
            ],
            shortTitle: "Dad my phone",
            systemImageName: "lock.iphone"
        )
        AppShortcut(
            intent: StopDadIntent(),
            phrases: [
                "Un-Dad my phone with \(.applicationName)",
                "Unlock my phone with \(.applicationName)",
            ],
            shortTitle: "Un-Dad my phone",
            systemImageName: "lock.open.iphone"
        )
        AppShortcut(
            intent: DadStatusIntent(),
            phrases: [
                "Is my phone Dadded in \(.applicationName)",
            ],
            shortTitle: "Dad status",
            systemImageName: "questionmark.circle"
        )
    }
}
