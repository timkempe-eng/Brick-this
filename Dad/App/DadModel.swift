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

    /// The number both phones see, or `nil` when there is no household yet.
    /// Snapshotted for the same reason `stats` is — it derives this phone's own
    /// standing from the whole session history.
    @Published private(set) var householdStreak: HouseholdStreak?

    /// What the records can honestly say about the shield having been missing.
    /// Silent in the overwhelmingly common case, and always silent about
    /// *anybody* — see `ShieldGap`.
    @Published private(set) var shieldGap = ShieldGapReport(gaps: [],
                                                            authorizationMissingNow: false,
                                                            audience: .solo)
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
        pendingRequest = engine.pendingRequest
        stats = engine.stats
        householdStreak = engine.householdStreak
        shieldGap = engine.shieldGap
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

    /// How many this phone gets — the ladder widens it at the top two rungs,
    /// so Settings must not go on saying "of 5".
    var emergencyUnDadCeiling: Int { engine.emergencyCeiling }

    var pairedTagCount: Int { engine.store.tags.count }

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

    /// Asks iOS for Screen Time access, as the right *kind* of user.
    ///
    /// The two members are not interchangeable and the difference is the whole
    /// family layer:
    ///
    /// - `.individual` is somebody authorising themselves. The phone's owner
    ///   is in charge and can revoke it in Settings whenever they like.
    ///   Correct for an adult Dadding their own phone, and the only mode this
    ///   app had until now.
    /// - `.child` is genuine parental control, and it is what makes an
    ///   arrangement *binding* rather than merely co-operative — the young
    ///   person cannot undo it alone. Apple gates it hard: the device must be
    ///   signed into a child iCloud account inside an iCloud Family, and must
    ///   not be MDM-enrolled.
    ///
    /// That gate is a product constraint rather than a detail. It forces a
    /// household onto Family Sharing, and when it is not set up the request
    /// throws — so the failure has to be explained rather than reported as
    /// "declined", which would send somebody to the Screen Time settings that
    /// are not the problem.
    func requestAuthorization() async {
        let member: FamilyControlsMember =
            engine.store.household.role == .youngPerson ? .child : .individual
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: member)
            authorization = AuthorizationCenter.shared.authorizationStatus
            engine.store.hasOnboarded = true
        } catch {
            // Refresh here too: the denied state is what makes OnboardingView
            // show its explanation instead of looking like a dead button.
            authorization = AuthorizationCenter.shared.authorizationStatus
            banner = member == .child ? Vocab.childAuthorizationFailed : Vocab.authorizationDeclined
        }
    }

    // MARK: - Why each Mode is here

    var householdAgreements: HouseholdAgreements { engine.householdAgreements }

    func agreement(for modeID: UUID) -> ModeAgreement? { engine.agreement(for: modeID) }

    /// Records why a Mode exists.
    ///
    /// The `tagUID` is not a permission — anybody may write down a reason, and
    /// a rule one person wrote is a real thing that happens. It is what makes
    /// the record say "agreed together" rather than "set by one person", and
    /// the engine derives that rather than being told it.
    func agree(modeID: UUID, reason: String, comingUpAgainIn days: Int?, byTagUID tagUID: String?) {
        engine.agree(modeID: modeID, reason: reason, comingUpAgainIn: days, byTagUID: tagUID)
        reload()
    }

    func renegotiate(modeID: UUID, outcome: ModeAgreement.Outcome,
                     reason: String?, comingUpAgainIn days: Int?, byTagUID tagUID: String?) {
        engine.renegotiate(modeID: modeID, outcome: outcome, reason: reason,
                           comingUpAgainIn: days, byTagUID: tagUID)
        reload()
    }

    // MARK: - Rewards

    /// Derived on read, like `stats`, and not snapshotted: the rewards screen
    /// is the only thing that asks, and it asks once per render rather than a
    /// dozen times.
    var rewardLedger: RewardLedger { engine.rewardLedger }

    func offer(_ reward: RewardLedger.Reward, byTagUID tagUID: String?) {
        guard engine.offer(reward, byTagUID: tagUID) else { return refuse() }
        reload()
    }

    func retire(rewardID: UUID, byTagUID tagUID: String?) {
        guard engine.retire(rewardID: rewardID, byTagUID: tagUID) else { return refuse() }
        reload()
    }

    func claim(_ reward: RewardLedger.Reward) {
        guard engine.claim(reward) else {
            // The only two refusals are "not enough days" and "that offer was
            // taken back" — both of which can become true between a render and
            // a tap. Silence would read as the tap not registering, which is
            // the one thing worse than either answer.
            let short = rewardLedger.shortfall(for: reward)
            banner = short > RewardLedger.Days(0)
                ? "\(short.description) to go before you can claim that."
                : "That isn't on offer any more."
            return
        }
        reload()
    }

    func withdraw(claim id: UUID) {
        guard engine.withdraw(claim: id) else { return }
        reload()
    }

    func settle(claim id: UUID, byTagUID tagUID: String?) {
        guard engine.settle(claim: id, byTagUID: tagUID) else { return refuse() }
        reload()
    }

    /// The refusal a wrong or missing tag earns.
    ///
    /// One sentence, and it names the tag rather than the person: the thing
    /// that was missing is proof, not trustworthiness.
    private func refuse() {
        banner = "That needs your \(Vocab.tagNoun). Hold the phone near it and try again."
    }

    // MARK: - The household's streak

    /// What this phone would leave on the tag, and its own line in it.
    ///
    /// Read before the NFC session opens, because the merge happens inside a
    /// completion handler on a background queue and nothing there may reach
    /// the store. Both are values; see `TagScanner.exchange`.
    var ledgerToWrite: HouseholdLedger { engine.ledgerToWrite }
    var myStanding: MemberStanding? { engine.myStanding }

    /// Take in what the tag turned out to be carrying.
    ///
    /// Called after the session closes. Absorbing is not what makes the write
    /// happen — that already did — so a failure here costs the local copy of
    /// the household, not the shared one.
    func absorb(tagLedger payload: String) {
        guard engine.absorb(tagPayload: payload) else { return }
        reload()
    }

    // MARK: - Tapping

    func tap(tagUID: String? = nil, mode: DadMode? = nil) {
        // A tag tapped while somebody is asking answers the ask. That is the
        // whole of "request and grant" on one phone: the grown-up is in the
        // room, they already hold a tag, and no account, server or PIN is
        // involved. Checked before the ordinary toggle, because otherwise the
        // parent's tap would simply Un-Dad the phone — an unbounded release,
        // which is the exact thing a bounded grant exists to avoid.
        if let tagUID, engine.pendingRequest != nil,
           let answered = engine.grantRelease(byTagUID: tagUID) {
            switch answered {
            case .success(let exchange):
                banner = Vocab.granted(mode: exchange.request.modeName,
                                       minutes: Int(GrantDuration.standard.seconds / 60))
            case .failure:
                banner = "That ask has already been answered."
            }
            return reload()
        }

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
        if let refused = engine.upsert(mode) {
            banner = Vocab.refusal(refused)
            return reload()
        }
        // upsert syncs internally; ask again to learn whether it stuck. The
        // sync is a no-op diff when it already succeeded, and a retry when it
        // didn't — a schedule the system refused must not look configured.
        if !engine.syncSchedules() {
            banner = "The system couldn't register every schedule — too many scheduled \(Vocab.modeNoun)s. Trim one and save again."
        }
        reload()
    }

    func delete(_ mode: DadMode) {
        if let refused = engine.deleteMode(id: mode.id) { banner = Vocab.refusal(refused) }
        reload()
    }

    // MARK: - Tags

    func pair(tagUID: String, to modeID: UUID? = nil) {
        engine.pair(tagUID: tagUID, to: modeID)
        banner = "\(Vocab.tagNoun.capitalized) paired. Tap it to \(Vocab.verb) your phone."
        reload()
    }

    func forgetAllTags() {
        if let refused = engine.forgetAllTags() { banner = Vocab.refusal(refused) }
        reload()
    }

    /// What this phone's household arrangement permits, for hiding controls
    /// the engine would refuse anyway.
    func may(_ capability: HouseholdCapability) -> Bool { engine.may(capability) }

    var household: Household { engine.store.household }

    /// The week, as something to talk about rather than a score.
    var week: WeeklyReview {
        WeeklyReview(sessions: engine.store.history, now: now)
    }

    /// Where this phone sits, and what it still owes for the next rung.
    var ladder: AutonomyLadder { engine.ladder }

    /// The ask waiting for an answer, if there is one.
    @Published private(set) var pendingRequest: GrantExchange?

    /// Ask for a bounded release. The grown-up answers by tapping their tag.
    func askForARelease(reason: String? = nil) {
        if engine.requestRelease(reason: reason) == nil {
            banner = "There's nothing to ask about right now."
        }
        reload()
    }

    func withdrawRequest() {
        engine.withdrawRequest()
        reload()
    }

    func declineRequest() {
        engine.declineRequest()
        banner = "Not this time. The phone stays \(Vocab.verbPast)."
        reload()
    }

    /// Sit the next occurrence of a \(Vocab.modeNoun)'s schedule out.
    func skipNextNight(_ mode: DadMode) {
        if engine.skipNextNight(modeID: mode.id) == nil {
            banner = "\(mode.name) has no night coming up to skip."
        }
        reload()
    }

    func isNextNightSkipped(_ mode: DadMode) -> Bool {
        engine.isNextNightSkipped(modeID: mode.id)
    }

    func nextSkippableNight(_ mode: DadMode) -> ScheduleSkip? {
        engine.nextSkippableNight(modeID: mode.id)
    }

    /// Changing whose phone this is.
    ///
    /// Not a permission check on the *role* itself: a phone handed over is a
    /// conversation, and there is nobody in the app to have it with. What the
    /// role does gate is everything else, and the ladder position survives the
    /// change — an afternoon as a grown-up must not erase months of it.
    func setRole(_ role: HouseholdRole) {
        var household = engine.store.household
        household.role = role
        engine.store.household = household
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
