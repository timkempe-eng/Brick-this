import Foundation

/// Asking for a release, and granting a *bounded* one.
///
/// Apple's own "ask for more time" is the pattern every family already knows,
/// and the complaint about it is always the same: the parent taps Approve and
/// the phone is simply back. Saying yes costs the rest of the evening, so
/// parents learn to say no, and the feature stops being used.
///
/// The rule this file exists to enforce is therefore: **a grant is bounded by
/// construction.** Fifteen minutes, then the phone Dads itself again. There is
/// deliberately no code path — not a convenience initialiser, not a decoder,
/// not a `nil` meaning "no limit" — that produces an unbounded grant. Every
/// type below either clamps or refuses.
///
/// Two structural decisions follow from the rest of the product:
///
/// 1. **Everything is derived from stored values.** A grant ends because the
///    stored end date has passed, not because a background wake fired. Dad
///    already learned this with timed sessions (`DadEngine.reconcile`): a
///    `DeviceActivity` release can be lost — the process died before
///    registering it, or registration failed silently — and if the only thing
///    that ends a release is a timer, a lost timer means a phone that is free
///    forever. `state(at:)` is the backstop: whatever the system did or didn't
///    deliver, the next foreground computes the truth from `askedAt`,
///    `startsAt` and a duration.
/// 2. **No accounts, no network, no server.** That is a feature, and it shapes
///    the first version of granting: it is in-person and tag-mediated. The
///    parent is physically there, so a grant is a tag tap plus a short PIN
///    typed on the young person's phone. See `PINHashing` for where the
///    cryptography lives, which is not here.
///
/// User-facing copy for any of this belongs in `Vocab`, not in this file.

// MARK: - How long a grant may be

/// A grant's length, clamped into the only range that actually works.
///
/// The floor is not a preference. `DeviceActivitySchedule` will not monitor an
/// interval shorter than fifteen minutes (`DadEngine.minimumScheduledRelease`),
/// so a ten-minute grant would be accepted, shown to both people, and then
/// never re-Dad the phone. That is the worst possible failure: it looks like
/// the bounded grant worked and is indistinguishable from having given up for
/// the evening. So a short request is rounded **up**, and `adjustment` records
/// that it was, so the UI can say so rather than lie about the number the
/// parent typed.
///
/// The ceiling is a product decision rather than a system one. Past an hour a
/// "bounded grant" is just the evening back, and the whole point is that
/// saying yes is cheap because it is small.
struct GrantDuration: Hashable {

    /// The system floor. Shorter than this and the re-Dad never happens.
    static let minimum: TimeInterval = DadEngine.minimumScheduledRelease

    /// Past this a grant stops being a grant.
    static let maximum: TimeInterval = 60 * 60

    /// What a parent gets by tapping once, without choosing.
    static let standard = GrantDuration(requesting: 15 * 60)

    /// What happened to the number that was asked for. Surfaced rather than
    /// swallowed: silently changing a duration is how a UI ends up disagreeing
    /// with the phone.
    enum Adjustment: String, Codable, Hashable {
        case none
        /// Rounded up to the fifteen-minute system floor.
        case roundedUpToFloor
        /// Trimmed down to the maximum useful grant.
        case clampedToCeiling
    }

    let seconds: TimeInterval
    let adjustment: Adjustment

    /// The only way to make one. Non-failable on purpose: a parent who typed
    /// five minutes should get fifteen with an explanation, not an error and a
    /// phone that stays Dadded.
    init(requesting requested: TimeInterval) {
        if !(requested >= Self.minimum) {
            // Written as a negated `>=` so that a NaN request lands here too,
            // rather than falling through to the `else` and being stored
            // verbatim. There is no representable zero-length, negative or
            // non-finite grant.
            seconds = Self.minimum
            adjustment = .roundedUpToFloor
        } else if requested > Self.maximum {
            seconds = Self.maximum
            adjustment = .clampedToCeiling
        } else {
            seconds = requested
            adjustment = .none
        }
    }
}

extension GrantDuration: Codable {
    // Hand-written, because the synthesised `init(from:)` would assign the
    // stored fields directly and so become a second way to make a grant —
    // one that bypasses the clamp. Anything on disk (an older build, a
    // hand-edited App Group plist, a value written by a bug) goes back through
    // the same initialiser as everything else. `adjustment` is derived, not
    // stored, so a tampered value re-declares itself as clamped.
    private enum CodingKeys: String, CodingKey { case seconds }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(requesting: try container.decode(TimeInterval.self, forKey: .seconds))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(seconds, forKey: .seconds)
    }
}

// MARK: - The ask

/// One request for a release: which Mode, when, optionally why, and how long
/// the ask itself stays alive.
///
/// The lifetime is the part that is easy to leave out and expensive to leave
/// out. A request with no lifetime sits in a list until someone notices it,
/// which in practice means a parent picking up the phone at midnight and
/// granting an ask from four o'clock — releasing a phone whose owner is
/// asleep, for reasons that stopped applying hours ago. An unanswered request
/// expires on its own, and expiry is derived from `askedAt`, so it happens
/// whether or not anything was running at the time.
struct GrantRequest: Codable, Hashable, Identifiable {

    /// A request nobody answers is dead by this point.
    static let defaultLifetime: TimeInterval = 10 * 60
    static let minimumLifetime: TimeInterval = 60
    static let maximumLifetime: TimeInterval = 60 * 60

    /// A reason is a sentence to a parent in the same room, not an essay.
    /// Capped because it is persisted into the App Group that the shield
    /// extension reads under a tight memory limit.
    static let reasonLimit = 140

    let id: UUID
    let modeID: UUID
    /// Denormalised the way `DadSession` denormalises it: the Mode can be
    /// deleted while a request is outstanding, and the request should still be
    /// able to describe itself.
    let modeName: String
    let askedAt: Date
    /// `nil` rather than `""`. Whitespace-only text is not a reason.
    let reason: String?
    /// Clamped, never zero, never unbounded.
    let lifetime: TimeInterval

    init(id: UUID = UUID(),
         modeID: UUID,
         modeName: String,
         askedAt: Date,
         reason: String? = nil,
         lifetime: TimeInterval = GrantRequest.defaultLifetime) {
        self.id = id
        self.modeID = modeID
        self.modeName = modeName
        self.askedAt = askedAt
        self.reason = Self.tidy(reason)
        self.lifetime = Self.clamp(lifetime)
    }

    /// Derived, never stored: a stored `expiresAt` is one more field that can
    /// disagree with `askedAt` after a migration, and there is no version of
    /// "the expiry says one thing and the ask says another" that helps anyone.
    var expiresAt: Date { askedAt.addingTimeInterval(lifetime) }

    private static func clamp(_ lifetime: TimeInterval) -> TimeInterval {
        guard lifetime.isFinite else { return defaultLifetime }
        return min(max(lifetime, minimumLifetime), maximumLifetime)
    }

    private static func tidy(_ reason: String?) -> String? {
        guard let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(reasonLimit))
    }
}

extension GrantRequest {
    // Same reasoning as `GrantDuration`: the decoder must not be a second door
    // into an unclamped value. A request stored with a lifetime of a week — by
    // an older build, or a bug — decodes as an hour, not as a week.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try container.decode(UUID.self, forKey: .id),
                  modeID: try container.decode(UUID.self, forKey: .modeID),
                  modeName: try container.decode(String.self, forKey: .modeName),
                  askedAt: try container.decode(Date.self, forKey: .askedAt),
                  reason: try container.decodeIfPresent(String.self, forKey: .reason),
                  lifetime: try container.decode(TimeInterval.self, forKey: .lifetime))
    }
}

// MARK: - The answer

/// Who granted it.
///
/// One case, deliberately. Granting is in-person and tag-mediated because Dad
/// has no accounts and no server; a `.remote` case would be a state that looks
/// configured and does nothing, which is the one thing this codebase refuses
/// to ship. When there is a second way to grant, it earns a case then.
enum Granter: Codable, Hashable {
    /// The parent was standing there with the tag, and the PIN was checked on
    /// the young person's phone.
    case inPerson(tagUID: String)
}

/// A granted release. Bounded by construction, twice over: the length is a
/// `GrantDuration`, which cannot be unbounded, and the end is *computed* from
/// the start plus that length rather than stored, so there is no field anyone
/// can set to `Date.distantFuture`.
struct Grant: Codable, Hashable {
    let duration: GrantDuration
    let grantedBy: Granter
    let startsAt: Date

    /// The instant the phone Dads itself again.
    var endsAt: Date { startsAt.addingTimeInterval(duration.seconds) }

    init(requesting requested: TimeInterval, grantedBy: Granter, startsAt: Date) {
        self.duration = GrantDuration(requesting: requested)
        self.grantedBy = grantedBy
        self.startsAt = startsAt
    }

    init(duration: GrantDuration, grantedBy: Granter, startsAt: Date) {
        self.duration = duration
        self.grantedBy = grantedBy
        self.startsAt = startsAt
    }
}

/// The answer that was recorded, if there is one.
///
/// Note what is *absent*: there is no `.expired` case. Expiry is not something
/// anyone decides, it is what happens when nobody does — so recording it would
/// mean a background job had to write it, and a missed job would leave a
/// request that never expires. It is derived in `state(at:)` instead.
enum GrantDecision: Codable, Hashable {
    case granted(Grant)
    /// The parent said no.
    case declined(at: Date)
    /// The young person took the ask back before it was answered.
    case withdrawn(at: Date)
}

// MARK: - The state machine

/// What a request is, at a given instant. Every case is derived from stored
/// values plus `now`; nothing here needs a timer to have fired.
enum GrantRequestState: Equatable {
    /// Nobody has answered, and the ask is still alive.
    case pending(expiresAt: Date)
    /// Nobody answered in time. Derived, never recorded.
    case expired(at: Date)
    case declined(at: Date)
    case withdrawn(at: Date)
    /// Granted and running: the phone is released until this instant.
    case active(until: Date)
    /// Granted, and the grant has run out. The phone should be Dadded again —
    /// and this is what says so when the scheduled re-Dad never arrived.
    case elapsed(at: Date)
}

/// The ask and its answer, kept together because neither is meaningful alone.
struct GrantExchange: Codable, Hashable, Identifiable {

    var request: GrantRequest
    /// `nil` means unanswered. It never means expired — see `GrantDecision`.
    var decision: GrantDecision?

    var id: UUID { request.id }

    init(request: GrantRequest, decision: GrantDecision? = nil) {
        self.request = request
        self.decision = decision
    }

    /// The whole point of the file: what is true at `now`, computed from what
    /// is on disk.
    ///
    /// Called on every foreground and by `reconcile`-shaped code, exactly like
    /// a timed session's overdue check. If the `DeviceActivity` release for a
    /// grant is lost, this still reports `.elapsed`, and the phone goes back to
    /// being Dadded a moment late instead of never.
    func state(at now: Date) -> GrantRequestState {
        switch decision {
        case .none:
            // `>=` so the expiry instant itself is expired. A request cannot
            // be granted at the exact moment it dies; the alternative is a
            // one-tick window in which the ask is simultaneously answerable
            // and over.
            return now >= request.expiresAt
                ? .expired(at: request.expiresAt)
                : .pending(expiresAt: request.expiresAt)
        case .declined(let at):
            return .declined(at: at)
        case .withdrawn(let at):
            return .withdrawn(at: at)
        case .granted(let grant):
            return now >= grant.endsAt ? .elapsed(at: grant.endsAt) : .active(until: grant.endsAt)
        }
    }

    /// How much release is left, or `nil` when the phone should be Dadded.
    /// Never negative, so a caller cannot turn a lapsed grant into a countdown
    /// running backwards.
    func remaining(at now: Date) -> TimeInterval? {
        guard case .active(let until) = state(at: now) else { return nil }
        return until.timeIntervalSince(now)
    }

    /// True while the phone should be released on account of this exchange.
    func isReleasing(at now: Date) -> Bool {
        if case .active = state(at: now) { return true }
        return false
    }

    // MARK: Transitions

    /// Why a transition was refused. Refusing rather than trapping: these
    /// arrive from two people tapping at once on the same phone, which is a
    /// normal Tuesday, not a programming error.
    enum Refusal: Error, Equatable {
        /// Already granted, declined or withdrawn. Answers are final.
        case alreadyAnswered(GrantRequestState)
        /// Nobody answered in time. This is the midnight case: the ask is
        /// dead, and the young person can make a fresh one.
        case requestExpired(at: Date)
    }

    /// Grant a bounded release. The returned value is a new exchange; nothing
    /// mutates in place, so a refused transition cannot leave a half-answered
    /// record behind.
    func granting(_ requested: TimeInterval,
                  by granter: Granter,
                  now: Date) -> Result<GrantExchange, Refusal> {
        answering(now: now) {
            .granted(Grant(requesting: requested, grantedBy: granter, startsAt: now))
        }
    }

    func declining(now: Date) -> Result<GrantExchange, Refusal> {
        answering(now: now) { .declined(at: now) }
    }

    /// Taking the ask back. Legal only while pending — withdrawing an answered
    /// request would rewrite history, and revoking a *running* grant is not a
    /// decision about the request at all: it is Dadding the phone again, which
    /// is a tag tap and `DadEngine`'s business.
    func withdrawing(now: Date) -> Result<GrantExchange, Refusal> {
        answering(now: now) { .withdrawn(at: now) }
    }

    /// The one place a decision is attached, so every transition shares the
    /// same two guards and a new transition cannot forget one.
    private func answering(now: Date,
                           _ decide: () -> GrantDecision) -> Result<GrantExchange, Refusal> {
        let current = state(at: now)
        switch current {
        case .pending:
            return .success(GrantExchange(request: request, decision: decide()))
        case .expired(let at):
            return .failure(.requestExpired(at: at))
        case .declined, .withdrawn, .active, .elapsed:
            return .failure(.alreadyAnswered(current))
        }
    }
}

// MARK: - The PIN

/// Turning a typed PIN into a hash.
///
/// A port, not an implementation, and the reason is the first hard rule in
/// `CLAUDE.md`: Core imports Foundation and nothing else. Foundation alone has
/// no key-derivation function worth trusting a PIN to — a four-digit secret has
/// ten thousand possible values, so the only thing standing between a stolen
/// App Group file and the PIN is how slow the hash is. That is CryptoKit's job
/// (or a deliberately-tuned PBKDF2), and CryptoKit is an adapter's import, in
/// `Dad/Shared/Adapters`, alongside the ManagedSettings and DeviceActivity
/// adapters.
///
/// So Core defines the boundary and never crosses it: it stores a salt and a
/// hash, compares hashes, and counts failures. It never sees, stores or logs
/// the digits.
///
/// An implementation must be:
/// - deterministic for the same `(pin, salt)`;
/// - salted, so two families who both chose 1234 do not share a hash;
/// - slow — tens of milliseconds, tuned on device, not a bare SHA-256.
protocol PINHashing {
    func hash(pin: String, salt: Data) -> Data
}

/// What is stored for a parent's PIN: a salt and a hash, and deliberately not
/// a field the digits could be put in. There is no `pin` property here and
/// there must never be one — a plaintext PIN in the App Group is readable by
/// three extensions and by anyone holding the device's backup.
struct PINCredential: Codable, Hashable {
    let salt: Data
    let hash: Data
}

/// Comparison, rate limiting, and the lockout — all as derived state.
enum PINCheck {

    /// Wrong attempts allowed before the lockout starts.
    static let freeAttempts = 3

    /// The first lockout. It doubles with each further wrong attempt.
    static let baseLockout: TimeInterval = 60

    /// …up to here. Unbounded escalation locks a parent out of their own
    /// child's phone for a day because of a typo at breakfast.
    static let maximumLockout: TimeInterval = 15 * 60

    /// How long a wrong attempt counts against you.
    ///
    /// This must be **at least** `maximumLockout`, and that is not a taste
    /// call: failures older than the window are pruned, so a window shorter
    /// than the longest lockout would let the failures that caused a lockout
    /// age out while it was still running — unlocking the phone early and
    /// resetting the escalation at the same time. A test pins the relationship.
    static let window: TimeInterval = 60 * 60

    /// Whether two hashes are equal, without leaking *where* they differ.
    ///
    /// Every byte is examined even after a mismatch is found. The early-return
    /// version returns fractionally sooner the earlier the first differing
    /// byte is, which over enough attempts is a hint about the hash — and the
    /// hash of a four-digit PIN is a short walk from the PIN. This is
    /// constant-time in spirit rather than in guarantee: Swift's bounds checks
    /// and the optimiser put a real guarantee out of reach here, which is one
    /// more reason the cryptography itself belongs behind `PINHashing`.
    ///
    /// The length check folds into the same accumulator instead of returning
    /// early, so a wrong-length candidate takes the same path as a wrong one.
    static func matches(_ candidate: Data, _ stored: Data) -> Bool {
        let a = [UInt8](candidate)
        let b = [UInt8](stored)
        var difference: UInt8 = (a.count == b.count) ? 0 : 1
        // Walk the stored hash's full length regardless, so the work done does
        // not depend on the candidate's length.
        for i in 0..<b.count {
            difference |= b[i] ^ (i < a.count ? a[i] : 0)
        }
        // An empty stored hash would otherwise match an empty candidate, which
        // is what an uninitialised credential looks like. No PIN set is not
        // the same as every PIN correct.
        return difference == 0 && !b.isEmpty
    }

    /// Whether the phone is currently refusing attempts, derived from the
    /// stored failure timestamps alone. No timer, no scheduled unlock: the
    /// lockout ends because a stored date has passed, so force-quitting the
    /// app, rebooting, or the app being killed in the background changes
    /// nothing about when it lifts.
    enum Lockout: Equatable {
        case open(attemptsRemaining: Int)
        case locked(until: Date)
    }

    /// Failures still counting against the user at `now`.
    static func recent(failures: [Date], now: Date) -> [Date] {
        let cutoff = now.addingTimeInterval(-window)
        return failures.filter { $0 > cutoff }.sorted()
    }

    static func lockout(failures: [Date], now: Date) -> Lockout {
        let counting = recent(failures: failures, now: now)
        guard counting.count >= freeAttempts, let last = counting.last else {
            // Never zero: "no attempts left, but not locked either" is a state
            // that looks configured and does nothing, and a screen showing
            // "0 remaining" next to an enabled keypad is a lie about which.
            return .open(attemptsRemaining: freeAttempts - counting.count)
        }

        // 60s, 120s, 240s… capped. Doubling on a `Double` rather than by
        // shifting an `Int`, because `1 << 40` is not a number anyone wants to
        // compute by accident on the fortieth wrong tap.
        let escalation = counting.count - freeAttempts
        let penalty = min(Self.baseLockout * pow(2, Double(escalation)), Self.maximumLockout)
        let until = last.addingTimeInterval(penalty)
        // Once a lockout has run out the user gets exactly one attempt back.
        // Handing back the full three would make the lockout free: wait a
        // minute, get three more guesses, forever.
        return now < until ? .locked(until: until) : .open(attemptsRemaining: 1)
    }

    /// The outcome of one attempt.
    enum Verification: Equatable {
        case accepted
        case rejected(attemptsRemaining: Int)
        case locked(until: Date)
    }

    /// Check a hashed candidate, and return the new failure list.
    ///
    /// Pure, and returning the list rather than mutating it, the same shape as
    /// `EmergencyAllowance.consume` — the caller writes it back, so a crash
    /// mid-check cannot half-record an attempt.
    ///
    /// Takes a hash, never a PIN: the adapter has already run `PINHashing` over
    /// the digits and the credential's salt, and Core is never handed the
    /// digits at all.
    ///
    /// An attempt made *during* a lockout is refused without being recorded.
    /// Recording it would push the unlock time forward on every tap, so a stuck
    /// keyboard or an impatient child could extend a one-minute lockout
    /// indefinitely — and the lockout would then not end when the countdown on
    /// screen says it will, which is the only thing that countdown promises.
    static func verify(candidateHash: Data,
                       against credential: PINCredential,
                       failures: [Date],
                       now: Date) -> (result: Verification, failures: [Date]) {
        if case .locked(let until) = lockout(failures: failures, now: now) {
            return (.locked(until: until), failures)
        }

        guard matches(candidateHash, credential.hash) else {
            // Pruning here as well as counting keeps the stored array bounded,
            // the way `EmergencyAllowance.consume` does.
            let recorded = recent(failures: failures, now: now) + [now]
            switch lockout(failures: recorded, now: now) {
            case .locked(let until):
                return (.locked(until: until), recorded)
            case .open(let remaining):
                return (.rejected(attemptsRemaining: remaining), recorded)
            }
        }

        // A correct PIN clears the slate. Otherwise a parent who fumbled twice
        // this morning starts one attempt away from a lockout tonight, having
        // done nothing wrong in between.
        return (.accepted, [])
    }
}

// MARK: - Granting, PIN and all

/// The whole in-person flow in one pure function, because the ordering of the
/// two checks is a decision, and decisions belong where `swift test` reaches
/// them.
enum GrantAuthorization {

    enum Outcome: Equatable {
        case granted(GrantExchange)
        case refused(GrantExchange.Refusal)
        case wrongPIN(attemptsRemaining: Int)
        case lockedOut(until: Date)
    }

    /// The request's own state is checked *before* the PIN, deliberately.
    ///
    /// It is not a secret — the young person's phone is showing the ask — and
    /// checking it first means fumbling the PIN against a request that already
    /// expired at midnight cannot burn attempts, or start a lockout that then
    /// blocks the fresh, live request made ten seconds later.
    static func authorise(_ exchange: GrantExchange,
                          requesting requested: TimeInterval,
                          by granter: Granter,
                          candidateHash: Data,
                          credential: PINCredential,
                          failures: [Date],
                          now: Date) -> (outcome: Outcome, failures: [Date]) {

        if case .failure(let refusal) = exchange.granting(requested, by: granter, now: now) {
            return (.refused(refusal), failures)
        }

        let (verification, updated) = PINCheck.verify(candidateHash: candidateHash,
                                                      against: credential,
                                                      failures: failures,
                                                      now: now)
        switch verification {
        case .locked(let until):
            return (.lockedOut(until: until), updated)
        case .rejected(let remaining):
            return (.wrongPIN(attemptsRemaining: remaining), updated)
        case .accepted:
            // Re-run the transition rather than reusing the value from the
            // guard above, so the grant starts from the same `now` the PIN was
            // accepted at and the two cannot drift apart if either check grows
            // a side effect later.
            switch exchange.granting(requested, by: granter, now: now) {
            case .success(let granted): return (.granted(granted), updated)
            case .failure(let refusal): return (.refused(refusal), updated)
            }
        }
    }
}
