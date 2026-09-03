import Foundation
import SwiftUI
import FamilyControls

/// View-facing state. `DadEngine` is the truth; this republishes it so SwiftUI
/// redraws, and owns the running clock for the active session.
@MainActor
final class DadModel: ObservableObject {

    @Published private(set) var activeSession: DadSession?
    @Published private(set) var modes: [DadMode] = []

    /// Whether the apps are actually taken away right now, which a rationing
    /// Mode makes a different question from "is there a session". Republished
    /// rather than computed on demand so the home screen and the engine can
    /// never be drawing from different answers mid-render.
    @Published private(set) var shieldState: ShieldState = .off

    /// A break in progress: the phone is free, and a Mode is coming back.
    @Published private(set) var pendingResume: PendingResume?

    /// Snapshotted rather than computed on demand: reading it walks the whole
    /// session history out of `UserDefaults` and back through JSON, and the
    /// stats screen touches it a dozen times per render.
    @Published private(set) var stats = DadStats(sessions: [])
    @Published var authorization: AuthorizationStatus = AuthorizationCenter.shared.authorizationStatus
    @Published var banner: String?
    @Published var pendingModeChoice = false

    /// Ticks once a second while Dadded so the counter on the home screen moves.
    @Published private(set) var now = Date()
    private var ticker: Timer?

    private let engine: DadEngine

    init(engine: DadEngine = .live) {
        self.engine = engine
        reload()

        if engine.store.hasDataFromANewerBuild {
            // Their Modes and history are intact on disk, just unreadable
            // here. Saying so beats showing an empty app and letting the
            // first edit overwrite what they still have.
            banner = """
                Some of your data was written by a newer version of \(Vocab.appName) \
                and can't be read by this one. Update to see it again — changes you \
                make here will replace it.
                """
        }
    }

    func reload() {
        modes = engine.store.modes
        activeSession = engine.store.activeSession
        shieldState = engine.shieldState
        pendingResume = engine.pendingResume
        stats = engine.stats
        authorization = AuthorizationCenter.shared.authorizationStatus
        updateTicker()
    }

    /// Makes the shield agree with the stored session. Called at launch and
    /// whenever the app comes back to the foreground, so a session interrupted
    /// by a crash or a kill can't leave the two out of step.
    func reconcile() {
        engine.reconcile()
        reload()
    }

    var isDadded: Bool { activeSession != nil }

    /// The Mode the running session names, if it still exists.
    var activeMode: DadMode? {
        guard let activeSession else { return nil }
        return modes.first { $0.id == activeSession.modeID }
    }

    /// What the home screen says under the title.
    ///
    /// Three states, not two: a rationing Mode has taken nothing away yet, and
    /// telling someone their phone is Dadded while their apps still open is
    /// how a product stops being believed.
    var statusSubtitle: String {
        guard let session = activeSession else {
            guard let resume = pendingResume else { return Vocab.idleSubtitle }
            return "\(Vocab.breakRunning(mode: resume.modeName, until: resume.at)) \(Vocab.breakTapHint)"
        }
        guard let mode = activeMode, mode.rations else {
            return Vocab.activeSubtitle(mode: session.modeName)
        }
        let minutes = mode.editableAllowance.minutesPerDay
        return shieldState == .rationing
            ? Vocab.allowanceRunning(mode: session.modeName, minutes: minutes)
            : Vocab.allowanceSpent(mode: session.modeName, minutes: minutes)
    }

    var statusTitle: String {
        if isDadded { return Vocab.activeTitle }
        return pendingResume == nil ? Vocab.idleTitle : Vocab.breakTitle
    }

    /// What the button under it will do. A tap during a break calls the break
    /// off rather than Dadding, and saying so is the difference between a
    /// discoverable rule and a surprising one.
    var tapActionText: String {
        if isDadded { return Vocab.unDadAction }
        return pendingResume == nil ? Vocab.dadAction : Vocab.breakCancelAction
    }

    /// The glyph at the top. Rationing gets its own, the same way the widget
    /// and the shield do — one look, one answer.
    var statusSymbol: String {
        switch shieldState {
        case .off:       return pendingResume == nil ? "iphone.gen3" : "arrow.clockwise.circle"
        case .rationing: return "hourglass"
        case .blocking:  return "lock.iphone"
        }
    }

    var elapsedText: String {
        guard let session = activeSession else { return "" }
        return now.timeIntervalSince(session.startedAt).dadDurationText
    }

    var emergencyUnDadsRemaining: Int { engine.emergencyUnDadsRemaining }

    var pairedTagCount: Int { engine.store.pairedTagUIDs.count }

    /// Apps and sites no Mode may take away.
    var neverBlocked: BlockedSelection {
        get { engine.store.neverBlocked }
        set {
            engine.store.neverBlocked = newValue
            // Take effect now rather than at the next session. Someone who
            // has just protected their bank because a Mode hid it is not
            // going to wait for a shield they can currently see.
            engine.reconcile()
            reload()
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authorization = AuthorizationCenter.shared.authorizationStatus
            engine.store.hasOnboarded = true
        } catch {
            // Refresh here too: the denied state is what makes OnboardingView
            // show its explanation instead of looking like a dead button.
            authorization = AuthorizationCenter.shared.authorizationStatus
            banner = "Screen Time access was declined. Dad can't hide apps without it."
        }
    }

    // MARK: - Tapping

    func tap(tagUID: String? = nil, mode: DadMode? = nil) {
        switch engine.handleTap(tagUID: tagUID, preferredMode: mode) {
        case .dadded(let mode, .blocking):
            banner = "\(Vocab.verbPast) — \(mode.name)."
        case .dadded(let mode, .rationing(let minutes)):
            banner = "\(Vocab.verbPast) — \(Vocab.allowanceRunning(mode: mode.name, minutes: minutes))"
        case .dadded(let mode, .rationAlreadySpent):
            banner = "\(Vocab.verbPast) — \(Vocab.allowanceAlreadySpent(mode: mode.name, minutes: mode.editableAllowance.minutesPerDay))"
        case .dadded(let mode, .rationRefused):
            // Said out loud rather than swallowed: they were promised minutes
            // and their apps vanished instead.
            banner = "\(Vocab.verbPast) — \(mode.name). \(Vocab.allowanceRefused)"
        case .unDadded(let session):
            let summary = Vocab.sessionSummary(duration: session.duration.dadDurationText)
            // Read the break off the store rather than the result: it is armed
            // inside `unDad`, so the engine already knows and the view model
            // does not need a second copy of the rule.
            banner = engine.pendingResume.map {
                "\(summary) \(Vocab.breakRunning(mode: $0.modeName, until: $0.at))"
            } ?? summary
        case .breakCancelled(let mode):
            banner = Vocab.breakCancelled(mode: mode.name)
        case .needsModeChoice:
            pendingModeChoice = true
        case .unknownTag:
            banner = "That isn't one of your \(Vocab.tagNoun)s."
        }
        reload()
    }

    func emergencyUnDad() {
        if engine.emergencyUnDad() {
            banner = "\(Vocab.unVerbPast). \(emergencyUnDadsRemaining) emergency overrides left this month."
        } else {
            banner = "No emergency overrides left this month. Go find your tag."
        }
        reload()
    }

    // MARK: - Modes

    func save(_ mode: DadMode) {
        engine.upsert(mode)
        // upsert syncs internally; ask again to learn whether it stuck. The
        // sync is a no-op diff when it already succeeded, and a retry when it
        // didn't — a schedule the system refused must not look configured.
        if !engine.syncSchedules() {
            banner = "The system couldn't register every schedule — too many scheduled \(Vocab.modeNoun)s. Trim one and save again."
        }
        reload()
    }

    func delete(_ mode: DadMode) {
        engine.deleteMode(id: mode.id)
        reload()
    }

    // MARK: - Tags

    func pair(tagUID: String) {
        engine.pair(tagUID: tagUID)
        banner = "\(Vocab.tagNoun.capitalized) paired. Tap it to \(Vocab.verb) your phone."
        reload()
    }

    func forgetAllTags() {
        engine.store.pairedTagUIDs = []
        reload()
    }

    // MARK: - Incoming links
    //
    // Both the background-NFC universal link and the Shortcuts automation land
    // here. `/tap` toggles; `/dad` and `/undad` are one-directional so an
    // automation can be explicit if you'd rather it not toggle.

    func handleIncoming(url: URL) {
        switch IncomingLink.action(for: url) {
        case .toggle:            tap()
        case .dad:               if !isDadded { tap() }
        case .unDad:             if isDadded { tap() }
        case .open, .none:       break   // the widget, and anything unrecognised
        }
        reload()
    }

    // MARK: -

    private func updateTicker() {
        ticker?.invalidate()
        guard isDadded else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
    }
}
