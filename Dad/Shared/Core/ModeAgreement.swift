import Foundation

/// Why a Mode exists, in the household's own words, and when that gets talked
/// about again.
///
/// The backlog ranks this third and calls it the cheapest item with the best
/// evidence behind it: adolescent involvement in screen decisions is associated
/// with better compliance, and rules a teenager helped write hold where rules
/// imposed on them get routed around. The build is mostly copy and flow; the
/// part that belongs in Core — and therefore in `swift test` — is the record
/// itself and the arithmetic of when it is due.
///
/// Two structural decisions worth stating before the code.
///
/// **This adds no stored property to `DadMode`.** An agreement carries the
/// `modeID` it belongs to and is stored as its own array beside the Modes.
/// When it eventually moves inline it must be declared `var agreement:
/// ModeAgreement?` — Optional, for the reason written on `DadMode.schedule`:
/// Swift's synthesised decoder has no notion of a default, so a
/// non-Optional new key makes every previously-stored Mode throw, and
/// `LenientDecoding` then *skips* those records rather than failing loudly.
/// The user watches their Modes disappear and nothing reports an error. The
/// side table has the same hazard in reverse, which is why the decoder below
/// is hand-written rather than synthesised.
///
/// **There is no number in here that can be spent.** See "No currency" below.
struct ModeAgreement: Codable, Hashable, Identifiable {

    // MARK: - Who agreed it

    /// How many people were in the room.
    ///
    /// Deliberately not "parent" and "teenager", and it stayed that way after
    /// roles were built: `Household` knows whose phone this is, and repeating
    /// it here would be the same fact in two places — the duplication that
    /// costs this codebase the most. What has to be visible is that a rule was
    /// written by one person rather than two, not which person it was.
    ///
    /// Naming a person would also be the first step towards a comparison
    /// between two of them, which this file must never produce. There is
    /// nothing to compare because nobody is identified.
    enum Parties: String, Codable, Hashable {
        /// Both people present, and both said yes.
        case both
        /// One person wrote it. An imposed rule — and it stays visibly one.
        case onePerson
    }

    /// A Mode nobody agreed to is a restriction that appeared on a phone. The
    /// whole point of the record is that it does not read the same as one two
    /// people wrote, so this is exposed rather than buried.
    var isImposed: Bool { agreedBy == .onePerson }

    // MARK: - Stored

    /// The Mode this belongs to. Also the identity: one current agreement per
    /// Mode, with everything that happened to it in `history`.
    var modeID: UUID

    /// Why this Mode exists, in the household's words. Not a category, not a
    /// picked-from-a-list justification — free text, because the evidence is
    /// about the teenager having *written* something, and a dropdown is not
    /// writing.
    var reason: String

    var agreedAt: Date

    var agreedBy: Parties

    /// The date this comes up again. Optional, and the optionality is the
    /// point: an agreement with no date here never comes up again, which is a
    /// fact the summary reports rather than a blank the reader has to infer.
    ///
    /// Restrictions are supposed to shrink as trust grows. A rule with no
    /// scheduled renegotiation cannot shrink; it can only be argued about.
    var renegotiateOn: Date?

    /// Every time this was talked about, including the times nothing changed.
    var history: [Renegotiation]

    var id: UUID { modeID }

    init(modeID: UUID,
         reason: String,
         agreedAt: Date,
         agreedBy: Parties,
         renegotiateOn: Date? = nil,
         history: [Renegotiation] = []) {
        self.modeID = modeID
        self.reason = reason
        self.agreedAt = agreedAt
        self.agreedBy = agreedBy
        self.renegotiateOn = renegotiateOn
        self.history = history
    }

    // MARK: - The reason

    /// Whitespace is not an explanation. A Mode whose reason is blank counts
    /// as unexplained, which is exactly what it is.
    var hasReason: Bool {
        !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Renegotiation arithmetic
    //
    // Day boundaries follow the convention the rest of Core uses: a session
    // counts toward the day it *started*, so dates are compared at start of
    // day and never as instants. An agreement due today is due today all day.
    // Comparing raw `Date`s instead would make a review "overdue" from one
    // minute past the moment it was set, which is not how anyone says it.

    /// The last time two people (or one) actually looked at this. Falls back to
    /// the day it was agreed, because being written down *is* the first look.
    ///
    /// Taken as a maximum rather than `history.last` so a history stored out of
    /// order — or one carrying a record whose date failed to decode — cannot
    /// report a review as older than the agreement itself.
    var lastReviewedAt: Date {
        ([agreedAt] + history.map(\.date)).max() ?? agreedAt
    }

    /// Whether this ever comes up again. `false` is not a failing grade; it is
    /// a missing date, and the view says so in those words.
    var comesUpAgain: Bool { renegotiateOn != nil }

    /// Whole days from today to the review date. Negative once it has passed,
    /// `nil` when no date was ever set.
    ///
    /// Days, not seconds — see "No currency". A `TimeInterval` returned from
    /// here would be one addition away from `DadMode.autoUnDadAfter`.
    func daysUntilRenegotiation(now: Date = Date(),
                                calendar: Calendar = .current) -> Int? {
        guard let renegotiateOn else { return nil }
        let today = calendar.startOfDay(for: now)
        let due = calendar.startOfDay(for: renegotiateOn)
        return calendar.dateComponents([.day], from: today, to: due).day
    }

    /// Past its review date. An agreement with no date set is *not* overdue —
    /// it is un-scheduled, which is a different problem and gets its own line.
    /// Folding the two together would let "we never set a date" hide inside a
    /// list of things that are merely late.
    func isOverdue(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let days = daysUntilRenegotiation(now: now, calendar: calendar) else { return false }
        return days < 0
    }

    // MARK: - Recording that it happened

    /// What came out of a conversation.
    ///
    /// `keptAsIs` exists because "we talked and kept it" is a different fact
    /// from "nobody has looked at this since March", and a design that cannot
    /// express the first will read as the second — the review date slides past,
    /// the Mode joins the overdue list, and the household is told off for a
    /// conversation it actually had. That is the failure this enum prevents.
    ///
    /// Two cases and no third: there is no "partially", because a partially
    /// changed rule is a changed rule, and no ordering, because an ordering is
    /// a score.
    enum Outcome: String, Codable, Hashable {
        case keptAsIs
        case changed
    }

    /// One conversation.
    struct Renegotiation: Codable, Hashable {
        var date: Date
        var outcome: Outcome
        /// Who was there this time. An imposed Mode that both people later sat
        /// down over stops being imposed; that is the direction the product is
        /// supposed to move in, and it has to be expressible.
        var agreedBy: Parties
        /// The reason as re-stated, if it was. Empty means the wording stood.
        var reason: String

        init(date: Date, outcome: Outcome, agreedBy: Parties, reason: String = "") {
            self.date = date
            self.outcome = outcome
            self.agreedBy = agreedBy
            self.reason = reason
        }

        private enum CodingKeys: String, CodingKey {
            case date, outcome, agreedBy, reason
        }

        /// Total, like its parent's: nothing in a stored conversation can throw
        /// and take the surrounding agreement down with it.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // A dateless record decodes to 1970, which reads as "reviewed
            // longer ago than anything else" — the conservative direction. The
            // alternatives are `now`, which would silently clear an overdue
            // flag, and a throw, which would delete the agreement.
            let storedDate = try c.decodeIfPresent(Date.self, forKey: .date)
            date = storedDate ?? Date(timeIntervalSince1970: 0)
            let storedOutcome = try c.decodeIfPresent(String.self, forKey: .outcome) ?? ""
            outcome = Outcome(rawValue: storedOutcome) ?? .changed
            let storedParties = try c.decodeIfPresent(String.self, forKey: .agreedBy) ?? ""
            agreedBy = Parties(rawValue: storedParties) ?? .onePerson
            reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
        }
    }

    /// Records a conversation and returns the agreement as it now stands.
    ///
    /// Pure: the caller stores the result. Nothing in Core mutates persisted
    /// state on its own — that is the engine's job, and it is the only place a
    /// write happens.
    ///
    /// `nextReviewOn: nil` genuinely clears the date rather than leaving the
    /// old one. Keeping a date that has already been talked past would make an
    /// agreement permanently overdue *because* it was reviewed, which is the
    /// exact inversion this method exists to avoid.
    func renegotiated(_ outcome: Outcome,
                      on date: Date,
                      by parties: Parties,
                      reason newReason: String? = nil,
                      nextReviewOn: Date?) -> ModeAgreement {
        var updated = self
        updated.history.append(Renegotiation(date: date,
                                             outcome: outcome,
                                             agreedBy: parties,
                                             reason: newReason ?? ""))
        updated.agreedBy = parties
        if let newReason, !newReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updated.reason = newReason
        }
        updated.renegotiateOn = nextReviewOn
        return updated
    }

    /// A review date `days` from `date`, snapped to the start of that day so it
    /// matches how `isOverdue` reads it back.
    ///
    /// `nil` for a non-positive `days`, and that is a guard rather than
    /// tidiness. A screen that starts its picker on "days remaining" hands
    /// this a *negative* number for an agreement that is already overdue — so
    /// two people talk a rule over, save, and it re-files in the past and is
    /// still overdue the moment the conversation ends. That is the exact
    /// inversion `renegotiated` exists to prevent, arriving through the one
    /// door it does not watch.
    ///
    /// `nil` means "no date set", which the summary reports as a fact rather
    /// than a blank. Refusing here rather than at the call site because there
    /// is more than one call site and only one of them is testable without a
    /// Mac.
    static func reviewDate(_ days: Int,
                           after date: Date,
                           calendar: Calendar = .current) -> Date? {
        guard days > 0 else { return nil }
        return calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date))
    }

    // MARK: - Decoding
    //
    // Hand-written, and every key but `modeID` is `decodeIfPresent` with a
    // default. The synthesised decoder treats a missing key as a throw, and a
    // throw inside `LenientDecoding.array` silently drops the record — so the
    // first time a field is added to this type, every agreement written by an
    // older build would vanish without an error anywhere. `DadMode.schedule`
    // carries the same warning; this is the durable version of obeying it,
    // because it keeps holding once someone adds a field without reading the
    // comment.
    //
    // Raw-value enums are decoded through their `String` and defaulted on a
    // miss for the same reason: adding a third `Parties` case later must not
    // delete every agreement an older build can't name.

    private enum CodingKeys: String, CodingKey {
        case modeID, reason, agreedAt, agreedBy, renegotiateOn, history
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Required: an agreement with no Mode belongs to nothing and cannot be
        // shown, repaired or renegotiated. Dropping it is correct.
        modeID = try c.decode(UUID.self, forKey: .modeID)
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
        agreedAt = try c.decodeIfPresent(Date.self, forKey: .agreedAt) ?? Date(timeIntervalSince1970: 0)
        // Defaults to `onePerson` on purpose. When the record does not say,
        // the safe reading is that this was not agreed together: an imposed
        // rule must never become silently indistinguishable from an agreed one,
        // and a decode gap is not evidence of a conversation.
        let storedParties = try c.decodeIfPresent(String.self, forKey: .agreedBy) ?? ""
        agreedBy = Parties(rawValue: storedParties) ?? .onePerson
        renegotiateOn = try c.decodeIfPresent(Date.self, forKey: .renegotiateOn)
        history = try c.decodeIfPresent([Renegotiation].self, forKey: .history) ?? []
    }
}

// MARK: - Where a Mode stands

/// What the household knows about one Mode.
///
/// Three cases, and the precedence between them is a decision rather than an
/// accident:
///
/// - no agreement at all → `unexplained`
/// - an agreement written by one person → `imposed`, whatever else is missing
/// - an agreement written by both, with something written down → `agreed`
/// - an agreement written by both with a blank reason → `unexplained`
///
/// A blank reason demotes an agreed Mode but never rescues an imposed one,
/// because the imposition is the fact that most needs to stay visible. Letting
/// a missing sentence fold an imposed rule into the same bucket as an
/// unconfigured one is exactly the silent equivalence this feature exists to
/// stop.
///
/// No `Int` raw values, no `Comparable`, no ordering. See "No currency".
enum ModeStanding: Hashable {
    case agreed
    case imposed
    case unexplained
}

// MARK: - The household's agreements

/// An honest picture of every Mode and the agreement behind it.
///
/// Deliberately Foundation-only and free of stored state, in the shape of
/// `DadStats`: it takes the Modes, the agreements, a calendar and a reference
/// `now`, and returns values. The awkward parts — day boundaries, time zones,
/// an agreement whose Mode was deleted — become testable without a device.
///
/// ## Tone
///
/// This type exposes values and nothing else phrased as a verdict. The view
/// writes the sentences. Phrasings that were considered and rejected, so the
/// next person does not re-derive them:
///
/// - "You haven't reviewed Sleep in 6 months" — guilt, and aimed at a person.
/// - "3 of 4 Modes agreed — nice work!" — praise, and a percentage is a grade.
/// - "Deep Work was imposed on you" — true, adversarial, and useless.
/// - Anything of the form "<name> agreed 4, <name> agreed 1" — a comparison
///   between two people, which is the one output this file must never produce.
///   It cannot: nobody is named anywhere in it.
///
/// There is deliberately no `agreedShare: Double`. A percentage of agreed Modes
/// is a report card, and a report card is the thing that makes a teenager stop
/// reading the screen. Counts and lists let the view say "two Modes have no
/// reason written down" and leave it there.
///
/// ## No currency
///
/// The strongest finding in the research is that paying for good behaviour in
/// screen time backfires: screens become the thing worth working for, and
/// cooperation turns into negotiation. Earned minutes are the one currency Dad
/// must not mint.
///
/// This is structural here, not a promise:
///
/// - Nothing in this file returns a `TimeInterval`, and no arithmetic in it
///   produces a duration. `daysUntilRenegotiation` returns whole calendar days,
///   which is a date fact, not a balance — there is no meaningful way to add it
///   to `DadMode.autoUnDadAfter` or to an `EmergencyAllowance`.
/// - `ModeStanding` and `Outcome` have `String` raw values and are not
///   `Comparable`, so `standing.rawValue * 15` does not compile and the cases
///   cannot be ranked into points.
/// - There is no score, rate or total anywhere — only counts of Modes, which
///   are counts of *rules*, not of minutes.
///
/// Anyone wanting to pay for an agreement in screen time would have to invent
/// the number somewhere else, in a diff where it is visible.
struct HouseholdAgreements {

    /// One Mode and what is known about it.
    struct Entry: Identifiable, Hashable {
        let modeID: UUID
        let modeName: String
        let standing: ModeStanding
        let agreement: ModeAgreement?
        /// Negative once past, `nil` when no review date was ever set.
        let daysUntilRenegotiation: Int?
        let isOverdue: Bool
        /// An agreement exists but has no date to come up again.
        let neverComesUpAgain: Bool

        var id: UUID { modeID }
    }

    let entries: [Entry]

    /// - Parameter calendar: injected so tests can pin a time zone. The app
    ///   passes `.current`, which is what the household's day boundaries
    ///   actually are — a review due "Tuesday" is due on their Tuesday.
    init(modes: [DadMode],
         agreements: [ModeAgreement],
         now: Date = Date(),
         calendar: Calendar = .current) {

        // A side table can end up holding two rows for one Mode — a merge, a
        // write that raced a read. Keep the one reviewed most recently rather
        // than whichever the array happened to yield first, so the summary does
        // not change between launches for reasons nobody can see.
        var byMode: [UUID: ModeAgreement] = [:]
        for agreement in agreements {
            if let existing = byMode[agreement.modeID],
               existing.lastReviewedAt >= agreement.lastReviewedAt {
                continue
            }
            byMode[agreement.modeID] = agreement
        }

        // Driven by the Modes, never by the agreements: an agreement whose Mode
        // was deleted describes a rule that no longer exists, and counting it
        // would show a household four agreements for three Modes.
        entries = modes.map { mode in
            let agreement = byMode[mode.id]
            let days = agreement?.daysUntilRenegotiation(now: now, calendar: calendar)
            return Entry(
                modeID: mode.id,
                modeName: mode.name,
                standing: HouseholdAgreements.standing(for: agreement),
                agreement: agreement,
                daysUntilRenegotiation: days,
                isOverdue: agreement?.isOverdue(now: now, calendar: calendar) ?? false,
                neverComesUpAgain: agreement.map { !$0.comesUpAgain } ?? false)
        }
    }

    static func standing(for agreement: ModeAgreement?) -> ModeStanding {
        guard let agreement else { return .unexplained }
        if agreement.isImposed { return .imposed }
        return agreement.hasReason ? .agreed : .unexplained
    }

    // MARK: - Counts
    //
    // The three partition `total`, so a view can show them side by side without
    // a remainder it has to explain away.

    var total: Int { entries.count }
    var agreedCount: Int { entries.filter { $0.standing == .agreed }.count }
    var imposedCount: Int { entries.filter { $0.standing == .imposed }.count }
    var unexplainedCount: Int { entries.filter { $0.standing == .unexplained }.count }

    // MARK: - Lists

    /// Past their review date, soonest-overdue last, so the longest-ignored
    /// agreement is the one at the top.
    var overdue: [Entry] {
        entries.filter(\.isOverdue)
            .sorted { ($0.daysUntilRenegotiation ?? 0) < ($1.daysUntilRenegotiation ?? 0) }
    }

    /// Recorded, but with no date to come up again — a rule nobody revisits.
    var neverRevisited: [Entry] { entries.filter(\.neverComesUpAgain) }

    /// Nothing written down about why these exist.
    var unexplained: [Entry] { entries.filter { $0.standing == .unexplained } }

    /// Written by one person.
    var imposed: [Entry] { entries.filter { $0.standing == .imposed } }

    /// True when there is nothing at all to talk about right now. Not the same
    /// as everything being fine — a household with no Modes returns `true`.
    var nothingToRaise: Bool { overdue.isEmpty && unexplained.isEmpty && neverRevisited.isEmpty }
}

// MARK: - Copy

/// The wording, kept in Core for the reason `WidgetSnapshot` is: where the
/// phrasing is the decision, the phrasing is testable.
///
/// Every line here is a statement of fact with no verdict attached. That is a
/// hard requirement, not a preference: the feature only works if the screen
/// reads like the start of a conversation, and one scolding sentence in the
/// middle of it undoes the rest.
enum AgreementCopy {

    static let reasonPrompt = "Why is this \(Vocab.modeNoun.lowercased()) here?"
    static let reasonHint = "In your own words. Both people should recognise it."

    static func partiesLabel(_ parties: ModeAgreement.Parties) -> String {
        switch parties {
        case .both:      return "Agreed together"
        case .onePerson: return "Set by one person"
        }
    }

    static func standingLabel(_ standing: ModeStanding) -> String {
        switch standing {
        case .agreed:      return "Agreed together"
        case .imposed:     return "Set by one person"
        case .unexplained: return "No reason written down"
        }
    }

    static func outcomeLabel(_ outcome: ModeAgreement.Outcome) -> String {
        switch outcome {
        // Named as an event, not as a non-event. "No change" would read as a
        // wasted conversation; the conversation is the point.
        case .keptAsIs: return "Talked it over, kept it"
        case .changed:  return "Talked it over, changed it"
        }
    }

    /// The one line under a Mode's name. `nil` days means no date was set.
    static func dueLine(daysUntil: Int?) -> String {
        guard let days = daysUntil else { return "No date set to talk about this again" }
        switch days {
        case 0:          return "Comes up today"
        case 1:          return "Comes up tomorrow"
        case let d where d > 1:  return "Comes up in \(d) days"
        case -1:         return "Was due yesterday"
        default:         return "Was due \(-days) days ago"
        }
    }

    /// What to put at the top of the agreements screen. Plural-correct, and
    /// silent when there is nothing to raise — an empty household gets an empty
    /// string rather than a congratulation.
    static func overdueHeadline(count: Int) -> String {
        switch count {
        case 0:  return ""
        case 1:  return "1 \(Vocab.modeNoun.lowercased()) is due to be talked about"
        default: return "\(count) \(Vocab.modeNoun.lowercased())s are due to be talked about"
        }
    }
}
