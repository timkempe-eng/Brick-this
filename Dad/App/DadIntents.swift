import AppIntents
import Foundation

/// These are what make a tap feel like Brick's.
///
/// An NFC personal automation in Shortcuts can run an App Intent in the
/// background, with Dad closed and "Ask Before Running" off — so the tap
/// itself blocks or releases the apps and you never see our UI. That path
/// needs no website, no associated domain and nothing written to the tag.

struct ToggleDadIntent: AppIntent {
    static var title: LocalizedStringResource = "Touch Grass"
    static var description = IntentDescription(
        "Hides your chosen apps, or brings them back if you're already outside."
    )
    /// The whole point is that it runs without the app coming forward.
    static var openAppWhenRun = false

    @Parameter(title: "Mode", optionsProvider: TagModeNameOptions())
    var modeName: String?

    /// The tag this run stands in for. An NFC automation tells its action
    /// nothing about the tag that fired it, so a phone with a Home tag and a
    /// Work tag needs one automation per tag, each built around one of them.
    /// Set, the run is that tag's tap: it starts the Mode the tag names in
    /// Clover, and a tag unpaired since gets the answer that tag would get
    /// tapped for real.
    @Parameter(title: "Tag")
    var tag: TagEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Touch Grass with \(\.$tag)") {
            \.$modeName
        }
    }

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

        // The tag's UID goes through the same call the in-app scan makes with
        // the UID it read, so the two cannot come to mean different things.
        switch engine.handleTap(tagUID: tag?.id, preferredMode: requested) {
        case .dadded(let mode, let start):
            return .result(dialog: Self.dialog(mode: mode, start: start))
        case .unDadded(let session):
            guard let resume = engine.pendingResume else {
                return .result(dialog: "\(Vocab.sessionSummary(duration: session.duration.dadDurationText))")
            }
            return .result(dialog: "\(Vocab.sessionSummary(duration: session.duration.dadDurationText)) \(Vocab.breakRunning(mode: resume.modeName, until: resume.at))")
        case .breakCancelled(let mode):
            return .result(dialog: "\(Vocab.breakCancelled(mode: mode.name))")
        case .needsModeChoice(let among):
            // Names the choices, so a tag set to two Modes asks between those
            // two out loud rather than an open "which one?".
            guard let choices = Vocab.tagStarts(among.map(\.name)) else {
                throw $modeName.needsValueError("Which \(Vocab.modeNoun.lowercased())?")
            }
            throw $modeName.needsValueError("\(choices)?")
        case .unknownTag:
            return .result(dialog: "That isn't one of your \(Vocab.tagNoun)s.")
        }
    }

    /// Siri reads this aloud, so it has to be true. A rationing Mode has taken
    /// nothing away yet, and "Dadded. Deep Work." would tell someone their
    /// apps are gone while they are not.
    /// `IntentDialog`, not `String`: `.result(dialog:)` takes the former, and
    /// the literals at the other call sites only compile because it is
    /// `ExpressibleByStringInterpolation`. A `String` returned from here has
    /// no such conversion.
    static func dialog(mode: DadMode, start: DadEngine.DadStart) -> IntentDialog {
        switch start {
        case .blocking:
            return "\(Vocab.activeTitle). \(mode.name)."
        case .rationing(let minutes):
            return "\(Vocab.activeTitle). \(Vocab.allowanceRunning(mode: mode.name, minutes: minutes))"
        case .rationAlreadySpent:
            return "\(Vocab.activeTitle). \(Vocab.allowanceAlreadySpent(mode: mode.name, minutes: mode.editableAllowance.minutesPerDay))"
        case .rationRefused:
            return "\(Vocab.activeTitle). \(mode.name). \(Vocab.allowanceRefused)"
        }
    }
}

/// One-directional variants, for when you'd rather an automation not toggle —
/// a tag by the bed that only ever Dads, for instance.
struct StartDadIntent: AppIntent {
    static var title: LocalizedStringResource = "Touch Grass with a Mode"
    static var openAppWhenRun = false

    @Parameter(title: "Mode", optionsProvider: ModeNameOptions())
    var modeName: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let engine = DadEngine.live
        guard engine.store.activeSession == nil else {
            return .result(dialog: "Already \(Vocab.stateInProse).")
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
    static var title: LocalizedStringResource = "Come Back In"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // `.tapped`: this is a person deliberately releasing, so it starts a
        // break on a Mode that takes them, exactly as the tag would.
        guard let finished = DadEngine.live.unDad(.tapped) else {
            return .result(dialog: "You're not out touching grass.")
        }
        return .result(dialog: "\(Vocab.sessionSummary(duration: finished.duration.dadDurationText))")
    }
}

struct DadStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Am I outside?"
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Bool> {
        if let session = DadEngine.live.store.activeSession {
            return .result(
                value: true,
                dialog: "\(Vocab.state) for \(session.duration.dadDurationText) — \(session.modeName)."
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

/// The same, narrowed to the chosen tag's own Modes when it names several —
/// the list the question "Deep Work or Meetings?" is answered from.
struct TagModeNameOptions: DynamicOptionsProvider {
    @IntentParameterDependency<ToggleDadIntent>(\.$tag)
    var toggle

    func results() async throws -> [String] {
        let store = DadEngine.live.store
        let usable = store.modes.filter(\.blocksAnything)
        guard let uid = toggle?.tag.id else { return usable.map(\.name) }
        let named = store.tags.modeIDs(for: uid)
        let mine = usable.filter { named.contains($0.id) }
        return (mine.count > 1 ? mine : usable).map(\.name)
    }
}

/// A paired tag, as Shortcuts sees it.
///
/// Carries the UID as its id because the UID is what the engine resolves; it
/// is a factory number any NFC reader can see, not a secret. The tag is only
/// ever handed to `handleTap`, never to the household calls that take a tag
/// as proof a grown-up is in the room — those stay with a real scan.
struct TagEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Tag"
    static var defaultQuery = TagQuery()

    let id: String
    let name: String
    /// "Deep Work", or "Deep Work or Meetings"; `nil` for the app's choice.
    let startsMode: String?

    var displayRepresentation: DisplayRepresentation {
        let starts = startsMode ?? "Whichever \(Vocab.modeNoun.lowercased()) you pick"
        return DisplayRepresentation(title: "\(name)", subtitle: "\(starts)")
    }

    /// Every paired tag, in Settings' order.
    static func paired() -> [TagEntity] {
        let store = DadEngine.live.store
        let modes = store.modes
        return store.tags.pairs.map { pair in
            TagEntity(id: pair.uid,
                      name: pair.displayName,
                      startsMode: Vocab.tagStarts(pair.modeIDs.compactMap { id in
                          modes.first { $0.id == id }?.name
                      }))
        }
    }
}

struct TagQuery: EntityQuery {
    /// Answers for every id asked about, paired or not. A Shortcut built
    /// around a tag that has since been unpaired must still run *as that
    /// tag* — refused while other tags are paired, as the sticker itself
    /// would be — rather than find its tag missing and fall back to a plain
    /// toggle with some other Mode.
    func entities(for identifiers: [String]) async throws -> [TagEntity] {
        let paired = TagEntity.paired()
        return identifiers.map { id in
            paired.first { $0.id == id }
                ?? TagEntity(id: id, name: "A \(Vocab.tagNoun) that isn't paired", startsMode: nil)
        }
    }

    func suggestedEntities() async throws -> [TagEntity] {
        TagEntity.paired()
    }
}

struct DadShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleDadIntent(),
            phrases: [
                "Touch grass with \(.applicationName)",
                "Touch grass in \(.applicationName)",
                // One per paired tag, from `TagQuery.suggestedEntities`, so
                // each tag's action is waiting in Shortcuts by name. The
                // system only re-reads the list when `DadModel` says so.
                "Touch grass with \(\.$tag) in \(.applicationName)",
            ],
            shortTitle: "Touch Grass",
            systemImageName: "lock.iphone"
        )
        AppShortcut(
            intent: StopDadIntent(),
            phrases: [
                "Come back in with \(.applicationName)",
                "Unlock my phone with \(.applicationName)",
            ],
            shortTitle: "Come Back In",
            systemImageName: "lock.open.iphone"
        )
        AppShortcut(
            intent: DadStatusIntent(),
            phrases: [
                "Am I outside in \(.applicationName)",
            ],
            shortTitle: "Clover status",
            systemImageName: "questionmark.circle"
        )
    }
}
