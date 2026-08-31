import Foundation
import DeviceActivity

/// The one place that starts and stops a session, so a tap from the app, a
/// tap routed through Shortcuts, and a shield button all take the same path.
enum TimEngine {

    enum TapResult: Equatable {
        case timmed(mode: TimMode)
        case unTimmed(session: TimSession)
        case needsModeChoice
        case unknownTag
    }

    /// The whole product in one function: tapping toggles.
    ///
    /// `tagUID` is `nil` when the toggle came from somewhere other than a tag
    /// (the in-app button, a Shortcut you ran by hand), in which case there is
    /// nothing to verify.
    @discardableResult
    static func handleTap(tagUID: String?, preferredMode: TimMode? = nil) -> TapResult {
        let store = TimStore.shared

        if let uid = tagUID, !store.isPaired(tagUID: uid) {
            return .unknownTag
        }

        if let active = store.activeSession {
            let ended = unTim(session: active, byEmergency: false)
            return .unTimmed(session: ended)
        }

        // Starting: use the mode we were handed, else the only mode that
        // blocks anything, else make the user choose.
        let candidate = preferredMode ?? soleUsableMode()
        guard let mode = candidate, mode.blocksAnything else {
            return .needsModeChoice
        }
        tim(with: mode)
        return .timmed(mode: mode)
    }

    static func tim(with mode: TimMode) {
        let store = TimStore.shared
        Shielder.applyShield(for: mode)
        store.activeSession = TimSession(modeID: mode.id, modeName: mode.name, startedAt: Date())

        if let duration = mode.autoUnTimAfter {
            scheduleAutoUnTim(after: duration)
        }
    }

    @discardableResult
    static func unTim(session: TimSession, byEmergency: Bool) -> TimSession {
        let store = TimStore.shared
        Shielder.removeShield()
        cancelAutoUnTim()

        var finished = session
        finished.endedAt = Date()
        finished.endedByEmergency = byEmergency

        store.activeSession = nil
        store.archive(finished)
        return finished
    }

    /// Spends an emergency override, if any are left.
    static func emergencyUnTim() -> Bool {
        let store = TimStore.shared
        guard let active = store.activeSession else { return true }
        guard store.consumeEmergencyUnTim() else { return false }
        unTim(session: active, byEmergency: true)
        return true
    }

    // MARK: - Timed sessions
    //
    // `DeviceActivitySchedule` is what releases a timed session even if the
    // app never runs again. Its interval has a 15-minute floor, so anything
    // shorter is rounded up rather than silently ignored.

    static let autoUnTimActivity = DeviceActivityName("tim.autoUnTim")
    private static let minimumSchedule: TimeInterval = 15 * 60

    private static func scheduleAutoUnTim(after duration: TimeInterval) {
        let end = Date().addingTimeInterval(max(duration, minimumSchedule))
        let calendar = Calendar.current
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents([.hour, .minute], from: Date()),
            intervalEnd: calendar.dateComponents([.hour, .minute], from: end),
            repeats: false
        )
        try? DeviceActivityCenter().startMonitoring(autoUnTimActivity, during: schedule)
    }

    private static func cancelAutoUnTim() {
        DeviceActivityCenter().stopMonitoring([autoUnTimActivity])
    }

    // MARK: -

    private static func soleUsableMode() -> TimMode? {
        let usable = TimStore.shared.modes.filter(\.blocksAnything)
        return usable.count == 1 ? usable.first : nil
    }
}

extension TimeInterval {
    /// "1h 42m" / "8m" — used in the status screen and the session summaries.
    var timDurationText: String {
        let total = Int(self)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }
}
