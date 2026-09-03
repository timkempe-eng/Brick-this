import Foundation

/// The whole product: tapping toggles.
///
/// Every trigger funnels through here — the in-app button, an App Intent run
/// by a Shortcuts NFC automation, the shield's emergency button, and the
/// DeviceActivity extension's timed release — so there is exactly one place
/// where a session can begin or end.
///
/// Depends only on the ports in `Ports.swift`, which is what lets the
/// whole state machine be tested without a device. See
/// `docs/adr/001-ports-and-adapters.md`.
struct DadEngine {

    let store: DadPersisting
    let shield: ShieldControlling
    let scheduler: SessionScheduling
    let clock: Clock
    let widget: WidgetRefreshing
    let usage: UsageWatching

    /// - Parameter calendar: only the allowance's day boundary depends on it.
    ///   Injected so a test can pin a time zone, the same way `DadStats` does.
    let calendar: Calendar

    init(store: DadPersisting,
         shield: ShieldControlling,
         scheduler: SessionScheduling,
         clock: Clock,
         widget: WidgetRefreshing,
         usage: UsageWatching,
         calendar: Calendar = .current) {
        self.store = store
        self.shield = shield
        self.scheduler = scheduler
        self.clock = clock
        self.widget = widget
        self.usage = usage
        self.calendar = calendar
    }

    /// How many finished sessions to keep. The shield extension reads this
    /// file under a tight memory limit, so the tail is bounded.
    static let historyLimit = 500

    /// `DeviceActivitySchedule` won't monitor an interval shorter than this,
    /// so a shorter request is rounded up rather than silently ignored.
    static let minimumScheduledRelease: TimeInterval = 15 * 60

    /// What starting a session actually did.
    ///
    /// A Mode that rations can end up blocking anyway — if the system refuses
    /// to count usage, an allowance nobody counts is no allowance — and the
    /// user has to be told, because their apps have just vanished when they
    /// were promised fifteen minutes.
    enum DadStart: Equatable {
        /// The apps are gone, which is what this Mode asks for.
        case blocking
        /// The apps are still there, on the day's budget.
        case rationing(minutesPerDay: Int)
        /// The Mode rations, but the system would not count usage, so the
        /// apps were taken away instead.
        case rationRefused
        /// Today's allowance was already used up in an earlier session, so
        /// this one starts blocked. What makes "a day" mean a day.
        case rationAlreadySpent
    }

    /// Why a session ended.
    ///
    /// It decides two things — whether the stats count it as a clean finish,
    /// and whether the Mode's break is armed — and those two answers do not
    /// line up with a single boolean, which is what this used to be. An
    /// emergency override and a schedule boundary are both "not by tapping",
    /// and only one of them should count against you.
    enum SessionEnd: Equatable {
        /// The tag, the in-app button, or the Un-Dad intent. The only ending
        /// that starts a break.
        case tapped
        /// An override spent. Never starts a break: an override is for when
        /// the tag is out of reach, and coming back in fifteen minutes would
        /// leave someone blocked with no way out.
        case emergency
        /// A timed release, a schedule boundary, a Mode deleted underneath a
        /// running session. Each has already said when this Mode should stop.
        case system
    }

    enum TapResult: Equatable {
        case dadded(mode: DadMode, start: DadStart)
        case unDadded(session: DadSession)
        /// Tapped during a break, which calls it off. Reaching a Mode that
        /// takes breaks is the only way to get here.
        case breakCancelled(mode: DadMode)
        case needsModeChoice
        case unknownTag
    }

    // MARK: - Tapping

    /// - Parameters:
    ///   - tagUID: `nil` when the toggle didn't come from a tag — the in-app
    ///     button, or a Shortcut run by hand. Nothing to verify in that case.
    ///   - preferredMode: which Mode to start. Ignored when already Dadded,
    ///     because then the tap can only mean "release".
    @discardableResult
    func handleTap(tagUID: String? = nil, preferredMode: DadMode? = nil) -> TapResult {
        if let uid = tagUID, !isPaired(tagUID: uid) {
            return .unknownTag
        }

        if store.activeSession != nil {
            guard let ended = unDad(.tapped) else { return .needsModeChoice }
            return .unDadded(session: ended)
        }

        // Free, but a break is running. Both readings of a bare tap here are
        // defensible — call the break off, or start the session early — and
        // calling it off wins because it is the one the user cannot get any
        // other way. Waiting gets you the session; nothing else gets you your
        // evening back. It also keeps every state change at the tag, which is
        // the whole product.
        //
        // A tap that *names* a Mode is not a bare tap, though. It comes from
        // the "which Mode?" dialog, or from a Shortcut built around one
        // particular Mode, and both mean "start this now" — so the break is
        // superseded rather than cancelled, which `dad` does on its own.
        if preferredMode == nil, let pending = store.pendingResume {
            let mode = store.modes.first { $0.id == pending.modeID }
            cancelBreak()
            // A break whose Mode has since been deleted is stale. Drop it and
            // let the tap mean what a tap normally means, rather than
            // reporting a cancellation of something we cannot name.
            if let mode { return .breakCancelled(mode: mode) }
        }

        // Starting: the Mode we were handed, else the only one that blocks
        // anything, else make the user choose. Never start an empty session —
        // it would look like it worked and block nothing.
        guard let mode = preferredMode ?? soleUsableMode(), mode.blocksAnything else {
            return .needsModeChoice
        }
        return .dadded(mode: mode, start: dad(with: mode))
    }

    // MARK: - Starting and stopping

    @discardableResult
    func dad(with mode: DadMode, startedBySchedule: Bool = false) -> DadStart {
        // Starting while a session is running would drop the old one from
        // history without ever ending it. Close it out first so the record
        // stays honest, whoever called us.
        if store.activeSession != nil {
            unDad(.system)
        }

        // Whatever we were waiting to bring back, it is here now — or
        // something else is, which supersedes it either way.
        cancelBreak()

        // State first, then the shield. If the process dies between the two,
        // `reconcile()` on next launch puts the shield back — whereas a shield
        // with no session recorded would leave the user blocked with nothing
        // in the app able to release it.
        var session = DadSession(modeID: mode.id,
                                 modeName: mode.name,
                                 startedAt: clock.now,
                                 startedBySchedule: startedBySchedule ? true : nil)

        let start: DadStart
        if mode.rations {
            if allowanceAlreadySpentToday(modeID: mode.id) {
                // The system counts usage per registered window, and a window
                // is registered per session — so without this, ending a
                // session and starting another would hand out a fresh
                // fifteen minutes, and "15 min a day" would mean "15 min per
                // tap". Two taps at the tag you are already standing at is
                // not a limit.
                session.allowanceSpentAt = clock.now
                start = .rationAlreadySpent
            } else if usage.startWatching(mode, neverBlocked: store.neverBlocked) {
                start = .rationing(minutesPerDay: mode.editableAllowance.minutesPerDay)
            } else {
                // Recorded as spent, not merely reported: every later reader —
                // reconcile, the widget, the shield's copy — goes through
                // `ShieldPolicy`, and this is what tells it the apps are gone.
                // It also self-heals, because tomorrow is a different day and
                // the watch is attempted again.
                session.allowanceSpentAt = clock.now
                start = .rationRefused
            }
        } else {
            start = .blocking
        }

        store.activeSession = session
        applyShield(for: session, mode: mode)

        if let duration = mode.autoUnDadAfter {
            let release = clock.now.addingTimeInterval(max(duration, Self.minimumScheduledRelease))
            scheduler.scheduleRelease(at: release)
        }

        widget.reload()
        return start
    }

    /// Ends the active session. Returns the finished session, or `nil` if
    /// there wasn't one.
    @discardableResult
    func unDad(_ end: SessionEnd) -> DadSession? {
        guard var session = store.activeSession else { return nil }

        shield.clear()
        scheduler.cancelScheduledRelease()
        usage.stopWatching(modeID: session.modeID)

        session.endedAt = clock.now
        session.endedByEmergency = end == .emergency

        store.activeSession = nil
        archive(session)

        if end == .tapped,
           let mode = store.modes.first(where: { $0.id == session.modeID }),
           mode.takesBreaks,
           let length = mode.resumeAfter {
            startBreak(mode: mode, length: length,
                       startedBySchedule: session.startedBySchedule)
        }

        // Whichever process ended this — the app, the shield's emergency
        // button, the DeviceActivity monitor — the Lock Screen must stop
        // saying "Dadded".
        widget.reload()
        return session
    }

    /// Spends an emergency override to release without the tag.
    ///
    /// Returns `false` only when the allowance is gone — in which case nothing
    /// changes and the phone stays Dadded.
    @discardableResult
    func emergencyUnDad() -> Bool {
        // Not Dadded: nothing to release, and no reason to charge for it.
        guard store.activeSession != nil else { return true }

        // An override is a capability, but it is the *first* rung — a phone
        // with no way out at all is one nobody will agree to carry, and the
        // allowance is already bounded at five a month and self-restoring.
        guard may(.spendEmergencyOverride) else { return false }

        guard let spent = EmergencyAllowance.consume(uses: store.emergencyUses, now: clock.now) else {
            return false
        }
        store.emergencyUses = spent
        unDad(.emergency)
        return true
    }

    var emergencyUnDadsRemaining: Int {
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
        dad(with: mode, startedBySchedule: true)
    }

    /// The system reached the end of a Mode's scheduled window.
    func endScheduledSession(modeID: UUID) {
        // Only release the session this schedule started. Matching on Mode
        // alone would let Sleep's 07:00 boundary end a session the user
        // started by hand with Sleep at 20:00, meaning "until I tap again".
        guard let active = store.activeSession,
              active.modeID == modeID,
              active.startedBySchedule == true else { return }
        unDad(.system)
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

        guard var session = store.activeSession else {
            shield.clear()

            // A break whose end never arrived. The registration can be lost
            // with the process, exactly as a timed release can, and the
            // consequence is the same shape: a Mode that promised to come back
            // and silently didn't. Overdue resumes now; otherwise it is
            // re-armed, and the adapter no-ops when it is already registered.
            if let pending = store.pendingResume {
                if pending.isDue(now: clock.now) {
                    resumeFromBreak()
                } else {
                    scheduler.scheduleResume(at: pending.at)
                }
            }
            return
        }

        // A session is running, so nothing is waiting to come back.
        cancelBreak()

        guard let mode = store.modes.first(where: { $0.id == session.modeID }) else {
            // The Mode was deleted while a session was running. Nothing
            // left to re-apply, so end the session rather than leave a
            // shield we can no longer describe.
            unDad(.system)
            return
        }

        // A timed session's release can be lost — the process died between
        // recording the session and registering it, or registration failed
        // silently. Restoring only the shield would turn "Dad me for 15
        // minutes" into "until you find the tag". Overdue ends now;
        // otherwise the release is re-armed (the adapter no-ops when the
        // window is already registered, so this never disturbs a live one).
        if let duration = mode.autoUnDadAfter {
            let release = session.startedAt.addingTimeInterval(
                max(duration, Self.minimumScheduledRelease))
            if clock.now >= release {
                unDad(.system)
                return
            }
            scheduler.scheduleRelease(at: release)
        }

        // A spent allowance from an earlier day is this morning's allowance,
        // not a permanent block. The monitor is woken at midnight to say so,
        // but a wake that never arrives would otherwise leave the apps hidden
        // indefinitely — so the marker is cleared here too, on evidence rather
        // than on being told. Same backstop as the overdue release above.
        if mode.rations, let spentAt = session.allowanceSpentAt,
           !calendar.isDate(spentAt, inSameDayAs: clock.now) {
            session.allowanceSpentAt = nil
            store.activeSession = session
        }

        // Re-arm the usage watch before deciding the shield: if the system has
        // forgotten the registration, the allowance is not being counted, and
        // the shield has to go up instead of leaving the apps open forever.
        if mode.rations, session.allowanceSpentAt == nil,
           !usage.startWatching(mode, neverBlocked: store.neverBlocked) {
            session.allowanceSpentAt = clock.now
            store.activeSession = session
        }

        applyShield(for: session, mode: mode)
    }

    // MARK: - Breaks

    /// Arms the Mode to start itself again once the break is over.
    private func startBreak(mode: DadMode, length: TimeInterval,
                            startedBySchedule: Bool?) {
        // The same 15-minute floor the timed release has, and for the same
        // reason: DeviceActivity will not monitor a shorter interval, so a
        // ten-minute break would simply never fire. Rounding up is visible;
        // silently not coming back is not.
        let at = clock.now.addingTimeInterval(max(length, Self.minimumScheduledRelease))
        store.pendingResume = PendingResume(modeID: mode.id, modeName: mode.name, at: at,
                                            startedBySchedule: startedBySchedule)
        scheduler.scheduleResume(at: at)
    }

    /// Calls off a break — by tapping, or because something superseded it.
    private func cancelBreak() {
        guard store.pendingResume != nil else { return }
        store.pendingResume = nil
        scheduler.cancelScheduledResume()
        widget.reload()
    }

    /// The break is over. Called by the DeviceActivity monitor, with the app
    /// most likely closed.
    func resumeFromBreak() {
        guard let pending = store.pendingResume else { return }

        // Something started a session during the break. Nothing to bring back,
        // and stomping it would be worse than doing nothing.
        guard store.activeSession == nil else { return cancelBreak() }

        guard let mode = store.modes.first(where: { $0.id == pending.modeID }),
              mode.blocksAnything else {
            // Deleted or emptied while we were away. Drop the break rather
            // than leave a resume that can never happen.
            return cancelBreak()
        }

        cancelBreak()
        // Resumed as the same kind of session it interrupted, so a scheduled
        // Mode's own boundary still ends it.
        dad(with: mode, startedBySchedule: pending.startedBySchedule == true)
    }

    /// The break in progress, if any — for the home screen and the widget.
    var pendingResume: PendingResume? { store.pendingResume }

    // MARK: - Allowances

    /// The Mode's apps have been used for as long as today's allowance permits.
    ///
    /// Called by the DeviceActivity monitor, in its own process, with the app
    /// most likely closed.
    func spendAllowance(modeID: UUID) {
        guard var session = store.activeSession,
              session.modeID == modeID,
              let mode = store.modes.first(where: { $0.id == modeID }),
              mode.rations else { return }

        // Already spent today: the system can deliver a threshold more than
        // once, and re-stamping would move the moment the allowance ran out to
        // whenever the last duplicate arrived.
        guard !ShieldPolicy.isAllowanceSpent(session: session,
                                             now: clock.now,
                                             calendar: calendar) else { return }

        session.allowanceSpentAt = clock.now
        store.activeSession = session
        applyShield(for: session, mode: mode)
        widget.reload()
    }

    /// A new day began while a rationing session was running, so the allowance
    /// is back. Called at the start of the monitored day.
    func renewAllowance(modeID: UUID) {
        guard var session = store.activeSession,
              session.modeID == modeID,
              session.allowanceSpentAt != nil,
              let mode = store.modes.first(where: { $0.id == modeID }),
              mode.rations else { return }

        // Only if the day really has turned. The system delivers the start of
        // the window we registered, and re-registering an already-open one
        // would otherwise hand back an allowance that was spent minutes ago.
        guard !ShieldPolicy.isAllowanceSpent(session: session,
                                             now: clock.now,
                                             calendar: calendar) else { return }

        session.allowanceSpentAt = nil
        store.activeSession = session
        applyShield(for: session, mode: mode)
        widget.reload()
    }

    /// Whether this Mode's allowance was already used up today, in a session
    /// that has since ended.
    ///
    /// Only a *fully spent* allowance carries across sessions: the system
    /// tells us when a threshold is reached and nothing before that, so ten
    /// minutes used in a session you ended is ten minutes we never hear
    /// about. That is a real hole and it is in docs/roadmap.md — but it is a
    /// much smaller one than a limit you can reset by tapping twice.
    func allowanceAlreadySpentToday(modeID: UUID) -> Bool {
        store.history.contains { session in
            guard session.modeID == modeID, let spentAt = session.allowanceSpentAt else {
                return false
            }
            return calendar.isDate(spentAt, inSameDayAs: clock.now)
        }
    }

    /// What the shield should currently be doing, for whoever is asking.
    var shieldState: ShieldState {
        let session = store.activeSession
        let mode = session.flatMap { s in store.modes.first(where: { $0.id == s.modeID }) }
        return ShieldPolicy.state(session: session, mode: mode,
                                  now: clock.now, calendar: calendar)
    }

    /// The single place the shield is told anything while a session runs.
    /// Everything routes through `ShieldPolicy` so the app, the monitor and
    /// the widget can never disagree about whether the apps are taken away.
    private func applyShield(for session: DadSession, mode: DadMode) {
        switch ShieldPolicy.state(session: session, mode: mode,
                                  now: clock.now, calendar: calendar) {
        case .blocking:
            shield.apply(mode, neverBlocked: store.neverBlocked)
        case .rationing:
            shield.applyRestrictionsOnly(mode)
        case .off:
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

    /// The ladder, computed from this phone's own history.
    var ladder: AutonomyLadder {
        AutonomyLadder(sessions: store.history, now: clock.now, calendar: calendar)
    }

    /// Where this phone actually sits on the ladder.
    ///
    /// The greater of what has been **earned** from the history and what a
    /// grown-up has **granted** in a conversation. The maximum, not either
    /// alone, and both halves of that matter:
    ///
    /// - Earning must always pay, or the ladder is decoration and the whole
    ///   incentive is a lie. A floor set months ago must not cap somebody who
    ///   has since held the habit for sixty days, and nobody should have to
    ///   remember to hand a rung over on the right morning — "a reward you
    ///   cannot predict is not an incentive".
    /// - A granted rung is a decision between two people, and arithmetic does
    ///   not get to undo a conversation. That includes a lapse: the ladder
    ///   withholds *earned* rungs after a fortnight away, and it may, but it
    ///   cannot reach below the floor a grown-up set deliberately.
    ///
    /// A grown-up's own level is left alone — they hold every capability
    /// regardless, and running the ladder over their history would be
    /// scorekeeping nobody asked for.
    var autonomyLevel: Int {
        guard store.household.role == .youngPerson else { return store.household.autonomyLevel }
        return max(ladder.level, store.household.autonomyLevel)
    }

    /// What this phone's household arrangement currently permits.
    var permissions: RolePermissions {
        RolePermissions.for(role: store.household.role, autonomyLevel: autonomyLevel)
    }

    /// Whether the person holding this phone may do something.
    ///
    /// Public so the UI can *hide* what it is going to refuse. Both matter and
    /// they are not the same: hiding alone is a lock on the door of a room with
    /// no walls, since an App Intent reaches the same engine from Shortcuts.
    func may(_ capability: HouseholdCapability) -> Bool {
        permissions.may(capability)
    }

    /// Why an edit was refused, or `nil` if it went through.
    ///
    /// Returned rather than thrown, and named rather than a bare `false`: the
    /// app has to say *which* part of the arrangement stopped this, or a young
    /// person meets a control that silently does nothing and concludes the
    /// whole thing is broken — which is the first step to routing around it.
    @discardableResult
    func upsert(_ mode: DadMode) -> HouseholdCapability? {
        let previous = store.modes.first(where: { $0.id == mode.id })

        // Which permission an edit needs depends on what actually changed, so
        // that raising a young person's autonomy one rung genuinely widens what
        // they can do rather than unlocking everything at once.
        if let refused = refusal(editing: mode, from: previous) { return refused }

        var all = store.modes
        if let i = all.firstIndex(where: { $0.id == mode.id }) { all[i] = mode } else { all.append(mode) }
        store.modes = all
        syncSchedules()
        applyEdit(to: mode, from: previous)
        return nil
    }

    /// The narrowest capability that covers this edit.
    ///
    /// Checked most-specific-first: changing only a schedule needs
    /// `changeSchedule`, not the broader `editMode`, because the ladder hands
    /// those out at different rungs and collapsing them would make one rung do
    /// the work of three.
    private func refusal(editing mode: DadMode, from previous: DadMode?) -> HouseholdCapability? {
        guard let previous else {
            // A new Mode is an edit in the broadest sense: it is a new rule in
            // the arrangement, and adding one is not lesser than changing one.
            return may(.editMode) ? nil : .editMode
        }
        if previous.schedule != mode.schedule, !may(.changeSchedule) { return .changeSchedule }
        if previous.allowance != mode.allowance, !may(.changeAllowance) { return .changeAllowance }

        // Anything else about the Mode — its name, its apps, strict, breaks,
        // its style. Compared by ignoring the two fields already judged, so a
        // schedule change alone is never charged twice.
        var normalised = mode
        normalised.schedule = previous.schedule
        normalised.allowance = previous.allowance
        if normalised != previous, !may(.editMode) { return .editMode }
        return nil
    }

    @discardableResult
    func deleteMode(id: UUID) -> HouseholdCapability? {
        guard may(.deleteMode) else { return .deleteMode }
        store.modes = store.modes.filter { $0.id != id }
        usage.stopWatching(modeID: id)
        syncSchedules()
        return nil
    }

    /// Forgetting the paired tags is how a phone escapes the arrangement
    /// entirely: with no tag paired, any tag works, and any tag is a sticker
    /// you can buy. It is a capability like any other.
    @discardableResult
    func forgetAllTags() -> HouseholdCapability? {
        guard may(.unpairTag) else { return .unpairTag }
        store.pairedTagUIDs = []
        return nil
    }

    /// Editing the Mode a live session is running on has to reach the session,
    /// or the change is one the app accepted and the phone ignored until next
    /// time — which looks exactly like the edit not saving.
    ///
    /// The allowance is the part that cannot simply be re-applied: the system
    /// is counting against the old threshold, and the only way to change it is
    /// to stop and restart the window, which starts today's count again. So
    /// that is done **only when the allowance itself changed**, never as a side
    /// effect of renaming a Mode — otherwise opening the editor and pressing
    /// Save would be a way to buy another fifteen minutes.
    private func applyEdit(to mode: DadMode, from previous: DadMode?) {
        guard var session = store.activeSession, session.modeID == mode.id else { return }

        if previous?.allowance != mode.allowance {
            usage.stopWatching(modeID: mode.id)
            session.allowanceSpentAt = nil
            if mode.rations, !usage.startWatching(mode, neverBlocked: store.neverBlocked) {
                session.allowanceSpentAt = clock.now
            }
            store.activeSession = session
        }

        applyShield(for: session, mode: mode)
        widget.reload()
    }

    private func soleUsableMode() -> DadMode? {
        let usable = store.modes.filter(\.blocksAnything)
        return usable.count == 1 ? usable.first : nil
    }

    // MARK: -

    private func archive(_ session: DadSession) {
        store.history = Array((store.history + [session]).suffix(Self.historyLimit))
    }

    var stats: DadStats { DadStats(sessions: store.history, now: clock.now) }
}
