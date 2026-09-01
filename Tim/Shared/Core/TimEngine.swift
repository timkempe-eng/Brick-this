import Foundation

/// The whole product: tapping toggles.
///
/// Every trigger funnels through here — the in-app button, an App Intent run
/// by a Shortcuts NFC automation, the shield's emergency button, and the
/// DeviceActivity extension's timed release — so there is exactly one place
/// where a session can begin or end.
///
/// Depends only on the four ports in `Ports.swift`, which is what lets the
/// whole state machine be tested without a device. See
/// `docs/adr/001-ports-and-adapters.md`.
struct TimEngine {

    let store: TimPersisting
    let shield: ShieldControlling
    let scheduler: SessionScheduling
    let clock: Clock

    init(store: TimPersisting,
         shield: ShieldControlling,
         scheduler: SessionScheduling,
         clock: Clock) {
        self.store = store
        self.shield = shield
        self.scheduler = scheduler
        self.clock = clock
    }

    /// How many finished sessions to keep. The shield extension reads this
    /// file under a tight memory limit, so the tail is bounded.
    static let historyLimit = 500

    /// `DeviceActivitySchedule` won't monitor an interval shorter than this,
    /// so a shorter request is rounded up rather than silently ignored.
    static let minimumScheduledRelease: TimeInterval = 15 * 60

    enum TapResult: Equatable {
        case timmed(mode: TimMode)
        case unTimmed(session: TimSession)
        case needsModeChoice
        case unknownTag
    }

    // MARK: - Tapping

    /// - Parameters:
    ///   - tagUID: `nil` when the toggle didn't come from a tag — the in-app
    ///     button, or a Shortcut run by hand. Nothing to verify in that case.
    ///   - preferredMode: which Mode to start. Ignored when already Timmed,
    ///     because then the tap can only mean "release".
    @discardableResult
    func handleTap(tagUID: String? = nil, preferredMode: TimMode? = nil) -> TapResult {
        if let uid = tagUID, !isPaired(tagUID: uid) {
            return .unknownTag
        }

        if store.activeSession != nil {
            guard let ended = unTim(byEmergency: false) else { return .needsModeChoice }
            return .unTimmed(session: ended)
        }

        // Starting: the Mode we were handed, else the only one that blocks
        // anything, else make the user choose. Never start an empty session —
        // it would look like it worked and block nothing.
        guard let mode = preferredMode ?? soleUsableMode(), mode.blocksAnything else {
            return .needsModeChoice
        }
        tim(with: mode)
        return .timmed(mode: mode)
    }

    // MARK: - Starting and stopping

    func tim(with mode: TimMode, startedBySchedule: Bool = false) {
        // Starting while a session is running would drop the old one from
        // history without ever ending it. Close it out first so the record
        // stays honest, whoever called us.
        if store.activeSession != nil {
            unTim(byEmergency: false)
        }

        // State first, then the shield. If the process dies between the two,
        // `reconcile()` on next launch puts the shield back — whereas a shield
        // with no session recorded would leave the user blocked with nothing
        // in the app able to release it.
        store.activeSession = TimSession(modeID: mode.id,
                                         modeName: mode.name,
                                         startedAt: clock.now,
                                         startedBySchedule: startedBySchedule ? true : nil)
        shield.apply(mode)

        if let duration = mode.autoUnTimAfter {
            let release = clock.now.addingTimeInterval(max(duration, Self.minimumScheduledRelease))
            scheduler.scheduleRelease(at: release)
        }
    }

    /// Ends the active session. Returns the finished session, or `nil` if
    /// there wasn't one.
    @discardableResult
    func unTim(byEmergency: Bool) -> TimSession? {
        guard var session = store.activeSession else { return nil }

        shield.clear()
        scheduler.cancelScheduledRelease()

        session.endedAt = clock.now
        session.endedByEmergency = byEmergency

        store.activeSession = nil
        archive(session)
        return session
    }

    /// Spends an emergency override to release without the tag.
    ///
    /// Returns `false` only when the allowance is gone — in which case nothing
    /// changes and the phone stays Timmed.
    @discardableResult
    func emergencyUnTim() -> Bool {
        // Not Timmed: nothing to release, and no reason to charge for it.
        guard store.activeSession != nil else { return true }

        guard let spent = EmergencyAllowance.consume(uses: store.emergencyUses, now: clock.now) else {
            return false
        }
        store.emergencyUses = spent
        unTim(byEmergency: true)
        return true
    }

    var emergencyUnTimsRemaining: Int {
        EmergencyAllowance.remaining(uses: store.emergencyUses, now: clock.now)
    }

    // MARK: - Recurring schedules

    var desiredSchedules: [RecurringSchedule] {
        store.modes
            .filter(\.hasLiveSchedule)
            .map { RecurringSchedule(modeID: $0.id, schedule: $0.schedule!) }
    }

    /// Brings the system's registered windows to the current live set, by
    /// diffing against what was last synced and touching only what changed.
    ///
    /// The diff is load-bearing, not an optimisation: stopping a window that
    /// is currently *open* means the system never delivers its end, so a
    /// scheduled session would run forever. A Mode whose schedule didn't
    /// change is never touched, even while other Modes are edited around it —
    /// and a no-change sync (this runs on every foreground) touches nothing.
    ///
    /// Returns false when some windows failed to register — the system caps
    /// how many activities an app may monitor. The synced state is then NOT
    /// recorded, so the next sync retries instead of believing a registration
    /// that never happened.
    @discardableResult
    func syncSchedules() -> Bool {
        let desired = desiredSchedules
        let (stop, start) = ScheduleWindows.diff(
            from: ScheduleWindows.windows(for: store.syncedSchedules),
            to: ScheduleWindows.windows(for: desired)
        )

        if !stop.isEmpty { scheduler.stopWindows(named: stop) }
        let failed = start.isEmpty ? [] : scheduler.startWindows(start)

        guard failed.isEmpty else { return false }
        if store.syncedSchedules != desired { store.syncedSchedules = desired }
        return true
    }

    /// The system reached the start of a Mode's scheduled window.
    func beginScheduledSession(modeID: UUID) {
        // Never stomp a session the user started by hand — theirs wins, and
        // the scheduled end below won't touch it either.
        guard store.activeSession == nil else { return }
        guard let mode = store.modes.first(where: { $0.id == modeID }), mode.hasLiveSchedule else {
            return
        }
        tim(with: mode, startedBySchedule: true)
    }

    /// The system reached the end of a Mode's scheduled window.
    func endScheduledSession(modeID: UUID) {
        // Only release the session this schedule started. Matching on Mode
        // alone would let Sleep's 07:00 boundary end a session the user
        // started by hand with Sleep at 20:00, meaning "until I tap again".
        guard let active = store.activeSession,
              active.modeID == modeID,
              active.startedBySchedule == true else { return }
        unTim(byEmergency: false)
    }

    // MARK: - Reconciliation

    /// Makes the shield agree with the stored session.
    ///
    /// Called at launch and when the app returns to the foreground. It closes
    /// the crash window in both directions: a session with no shield gets the
    /// shield back, and a shield with no session gets cleared, so neither a
    /// half-finished start nor a half-finished stop can strand the user.
    func reconcile() {
        syncSchedules()

        if let session = store.activeSession {
            guard let mode = store.modes.first(where: { $0.id == session.modeID }) else {
                // The Mode was deleted while a session was running. Nothing
                // left to re-apply, so end the session rather than leave a
                // shield we can no longer describe.
                unTim(byEmergency: false)
                return
            }

            // A timed session's release can be lost — the process died between
            // recording the session and registering it, or registration failed
            // silently. Restoring only the shield would turn "Tim me for 15
            // minutes" into "until you find the tag". Overdue ends now;
            // otherwise the release is re-armed (the adapter no-ops when the
            // window is already registered, so this never disturbs a live one).
            if let duration = mode.autoUnTimAfter {
                let release = session.startedAt.addingTimeInterval(
                    max(duration, Self.minimumScheduledRelease))
                if clock.now >= release {
                    unTim(byEmergency: false)
                    return
                }
                scheduler.scheduleRelease(at: release)
            }

            shield.apply(mode)
        } else {
            shield.clear()
        }
    }

    // MARK: - Tags

    /// An empty pairing list means "any tag works", which is what you want
    /// before the user has paired anything.
    func isPaired(tagUID: String) -> Bool {
        store.pairedTagUIDs.isEmpty || store.pairedTagUIDs.contains(tagUID)
    }

    func pair(tagUID: String) {
        guard !store.pairedTagUIDs.contains(tagUID) else { return }
        store.pairedTagUIDs.append(tagUID)
    }

    // MARK: - Modes

    func upsert(_ mode: TimMode) {
        var all = store.modes
        if let i = all.firstIndex(where: { $0.id == mode.id }) { all[i] = mode } else { all.append(mode) }
        store.modes = all
        syncSchedules()
    }

    func deleteMode(id: UUID) {
        store.modes = store.modes.filter { $0.id != id }
        syncSchedules()
    }

    private func soleUsableMode() -> TimMode? {
        let usable = store.modes.filter(\.blocksAnything)
        return usable.count == 1 ? usable.first : nil
    }

    // MARK: -

    private func archive(_ session: TimSession) {
        store.history = Array((store.history + [session]).suffix(Self.historyLimit))
    }

    var stats: TimStats { TimStats(sessions: store.history, now: clock.now) }
}
