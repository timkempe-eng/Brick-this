import Foundation
import SwiftUI
import FamilyControls

/// View-facing state. `TimEngine` is the truth; this republishes it so SwiftUI
/// redraws, and owns the running clock for the active session.
@MainActor
final class TimModel: ObservableObject {

    @Published private(set) var activeSession: TimSession?
    @Published private(set) var modes: [TimMode] = []

    /// Snapshotted rather than computed on demand: reading it walks the whole
    /// session history out of `UserDefaults` and back through JSON, and the
    /// stats screen touches it a dozen times per render.
    @Published private(set) var stats = TimStats(sessions: [])
    @Published var authorization: AuthorizationStatus = AuthorizationCenter.shared.authorizationStatus
    @Published var banner: String?
    @Published var pendingModeChoice = false

    /// Ticks once a second while Timmed so the counter on the home screen moves.
    @Published private(set) var now = Date()
    private var ticker: Timer?

    private let engine: TimEngine

    init(engine: TimEngine = .live) {
        self.engine = engine
        reload()
    }

    func reload() {
        modes = engine.store.modes
        activeSession = engine.store.activeSession
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

    var isTimmed: Bool { activeSession != nil }

    var elapsedText: String {
        guard let session = activeSession else { return "" }
        return now.timeIntervalSince(session.startedAt).timDurationText
    }

    var emergencyUnTimsRemaining: Int { engine.emergencyUnTimsRemaining }

    var pairedTagCount: Int { engine.store.pairedTagUIDs.count }

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authorization = AuthorizationCenter.shared.authorizationStatus
            engine.store.hasOnboarded = true
        } catch {
            banner = "Screen Time access was declined. Tim can't hide apps without it."
        }
    }

    // MARK: - Tapping

    func tap(tagUID: String? = nil, mode: TimMode? = nil) {
        switch engine.handleTap(tagUID: tagUID, preferredMode: mode) {
        case .timmed(let mode):
            banner = "\(Vocab.verbPast) — \(mode.name)."
        case .unTimmed(let session):
            banner = Vocab.sessionSummary(duration: session.duration.timDurationText)
        case .needsModeChoice:
            pendingModeChoice = true
        case .unknownTag:
            banner = "That isn't one of your \(Vocab.tagNoun)s."
        }
        reload()
    }

    func emergencyUnTim() {
        if engine.emergencyUnTim() {
            banner = "\(Vocab.unVerbPast). \(emergencyUnTimsRemaining) emergency overrides left this month."
        } else {
            banner = "No emergency overrides left this month. Go find your tag."
        }
        reload()
    }

    // MARK: - Modes

    func save(_ mode: TimMode) {
        engine.upsert(mode)
        reload()
    }

    func delete(_ mode: TimMode) {
        engine.deleteMode(id: mode.id)
        reload()
    }

    // MARK: - Tags

    func pair(tagUID: String) {
        engine.pair(tagUID: tagUID)
        banner = "\(Vocab.tagNoun.capitalized) paired. Tap it to \(Vocab.verb.lowercased()) your phone."
        reload()
    }

    func forgetAllTags() {
        engine.store.pairedTagUIDs = []
        reload()
    }

    // MARK: - Incoming links
    //
    // Both the background-NFC universal link and the Shortcuts automation land
    // here. `/tap` toggles; `/tim` and `/untim` are one-directional so an
    // automation can be explicit if you'd rather it not toggle.

    func handleIncoming(url: URL) {
        switch url.lastPathComponent {
        case "tim":
            if !isTimmed { tap() }
        case "untim":
            if isTimmed { tap() }
        default:
            tap()
        }
    }

    // MARK: -

    private func updateTicker() {
        ticker?.invalidate()
        guard isTimmed else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.now = Date() }
        }
    }
}
