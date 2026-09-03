import Foundation

/// A streak that belongs to the household rather than to one phone, carried on
/// the tag itself.
///
/// The problem is stated in the parking lot: a parent's own device habits are
/// among the strongest predictors of their child's, and the fastest way to make
/// Dad feel like a punishment is for it to run on exactly one phone in the
/// house. But a shared number needs two phones to agree on something, and Dad
/// has no accounts, no server and no step of a tap that touches the internet —
/// a property every comparison with Brick notices, and one not to spend
/// casually.
///
/// So the tag is the courier. It is already the thing both people physically
/// share; it has user memory; the app already writes to tags. Every tap made
/// **inside the app** reads what the other phones left there, merges it with
/// this phone's standing, and writes it back. Zero infrastructure, no accounts,
/// and it works on a plane.
///
/// Three consequences that shape everything below.
///
/// **Anyone who taps the tag can read it.** A stranger with any phone, a
/// visitor, a shop. So the ledger carries no names, no app selections, no times
/// of day, and no Mode ids — an opaque member id, a date, and a count. There is
/// deliberately no `String` field anybody types into: the privacy model made
/// structural, the same way `BlockedSelection` is opaque outside one file.
///
/// **The tag is small.** An NTAG213 has 144 bytes of user memory and may
/// already hold a URL record. So the encoding is a compact line rather than
/// JSON, and it drops the stalest members rather than growing past what a tag
/// can hold — a ledger that fails to write is worse than one that carries four
/// people instead of six.
///
/// **It syncs only on an in-app tap.** A tap through a Shortcuts automation
/// runs with no UI and cannot open a write session. So the shared number lags,
/// and the honest response to lag is not to hide it: `HouseholdStreak` carries
/// the day it was computed as of, and the UI says so. Each phone's *own*
/// streak is always locally true; only the shared one can be stale, and it is
/// never presented as current when it isn't.
enum HouseholdLedgerFormat {

    /// `d` for Dad, then the version. A tag written by a later build says so in
    /// its first two bytes and is left alone rather than half-parsed.
    static let prefix = "d"

    static let version = 1

    /// Beyond this the tag write starts failing on the smallest chips people
    /// actually buy. Chosen against NTAG213's 144 bytes with room for a URL
    /// record beside it.
    static let maximumPayload = 120

    /// The widest a member's line can be: eight for the id, eight for the
    /// date, and up to three digits of streak, plus the two separators and the
    /// leading semicolon.
    static let maximumMemberBytes = 8 + 8 + 3 + 3

    /// How many members fit, **derived rather than chosen**, and that is the
    /// fix for a real defect rather than tidiness.
    ///
    /// It was six, and six does not fit: the header is two bytes and a member
    /// is at least twenty, so a sixth member pushed the line past
    /// `maximumPayload` and `encoded()`'s loop dropped it. The phone that wrote
    /// the tag reported six people; every phone that read it reported five —
    /// and the member dropped is the *stalest*, which is the one whose
    /// `lastActive` decides whether the streak is current. So a reader
    /// computed a longer, possibly falsely-current streak than the writer.
    ///
    /// Two numbers that have to agree cannot both be written down. This one is
    /// arithmetic on the other, and a test pins that a full household survives
    /// a round trip.
    static let maximumMembers =
        (maximumPayload - 2) / maximumMemberBytes

    /// The exact bytes a ledger record written by *this* build starts with.
    ///
    /// Three characters, not one, and the third is what matters. Matching on
    /// `"d"` alone — which is what the three call sites did — treats any text
    /// record beginning with that letter as a ledger: "desk", "dinner",
    /// "downstairs", the sort of thing somebody writes with NFC Tools. Such a
    /// record was destroyed on the first in-app tap, and if it happened to sit
    /// before a real ledger record it was read *as* one, which fails to decode
    /// — so the other phones' standings were dropped and replaced with this
    /// phone's un-merged view. That is the "never half-applied" failure the
    /// exchange is built to avoid, one layer above where the guard for it is.
    static let recordPrefix = "\(prefix)\(version);"

    /// Whether an NDEF text payload is a ledger this build wrote and can read.
    ///
    /// Deliberately version-exact, and it is the same decision `decoded` makes
    /// for the same reason: a record from a later build is not ours to read
    /// and not ours to replace. It is left on the tag rather than overwritten,
    /// so a household running two builds ends up carrying two records and
    /// heals itself when both update — instead of one build silently deleting
    /// data it could not parse.
    ///
    /// One predicate, called from all three places that had written the rule
    /// out: reading the tag, replacing the record on it, and keeping it while
    /// writing a link.
    static func isOurRecord(_ text: String?) -> Bool {
        text?.hasPrefix(recordPrefix) ?? false
    }
}

/// Who a phone is, to the tag. Opaque by construction.
///
/// Eight hex characters: short enough that six of them fit on a cheap tag,
/// wide enough that two phones in one house colliding is not a thing that
/// happens. Derived from a UUID rather than from anything about the person,
/// because the point is that the tag reveals nothing.
struct MemberID: Codable, Hashable, CustomStringConvertible {

    let value: String

    static let length = 8

    private static let alphabet = Set("0123456789abcdef")

    /// A fresh id for this phone. Stored once and never regenerated — a new id
    /// would read as a new person and reset the household's streak.
    static func fresh() -> MemberID {
        MemberID(unchecked: String(UUID().uuidString.lowercased()
            .filter { alphabet.contains($0) }
            .prefix(length)))
    }

    /// `nil` for anything that is not exactly eight lowercase hex characters,
    /// which is what makes a garbled tag read a decode failure rather than a
    /// seventh member who never goes away.
    init?(_ value: String) {
        guard value.count == Self.length,
              value.allSatisfy({ Self.alphabet.contains($0) }) else { return nil }
        self.value = value
    }

    private init(unchecked value: String) { self.value = value }

    var description: String { value }
}

/// One member's standing, as small as it can be and still mean something.
///
/// A streak is a *contiguous run of days ending on `lastActive`*, which is what
/// makes two of these intersectable without carrying a calendar of days: the
/// run is `(lastActive - streak, lastActive]`. That is the whole reason the
/// household number is computable from a payload this small.
/// **Every property added here must be Optional**, and the reason is sharper
/// than it is for the arrays.
///
/// Swift's synthesised decoder throws on a missing key rather than falling back
/// to a default. The lenient arrays respond to a throw by dropping one element;
/// this type is read as part of a *whole value* —
/// `decode(HouseholdLedger.self, …) ?? HouseholdLedger()` — so a throw anywhere
/// inside it resets the **entire household ledger to empty**, with the "absent
/// decodes as nobody" comment beside it making the result look intended. The
/// household would lose its shared streak on the morning it updated and there
/// would be nothing to point at.
struct MemberStanding: Codable, Hashable {

    let member: MemberID

    /// The last day this member had a session. Days, not instants: the phones
    /// are in the same house but not necessarily in the same time zone, and a
    /// day is the coarsest unit that makes the comparison meaningful.
    var lastActive: ScheduleOccurrence

    /// Consecutive days ending on `lastActive`. Never negative; zero means a
    /// member who has been seen but has not Dadded.
    var streak: Int

    init(member: MemberID, lastActive: ScheduleOccurrence, streak: Int) {
        self.member = member
        self.lastActive = lastActive
        self.streak = max(0, streak)
    }
}

/// Everyone the tag knows about.
///
/// A value type with no stored derivation: the household streak is computed on
/// demand from the standings, so there is no second number that can disagree
/// with the first.
struct HouseholdLedger: Codable, Hashable {

    var standings: [MemberStanding]

    init(standings: [MemberStanding] = []) {
        self.standings = standings
    }

    func standing(for member: MemberID) -> MemberStanding? {
        standings.first { $0.member == member }
    }

    // MARK: - Merging

    /// This ledger updated with everything in `other`.
    ///
    /// Per member, the standing with the later `lastActive` wins, and a tie
    /// goes to the longer streak. That rule is right rather than arbitrary:
    /// only a member's own phone ever writes their standing, so between two
    /// copies of one member the fresher one is the true one and the other is
    /// a stale echo off the tag. The tie-break matters for the same day seen
    /// twice — a phone that has since had another session reports the longer
    /// run.
    ///
    /// A member this ledger has never heard of is kept. That is what makes a
    /// third phone joinable without anything being configured.
    func merged(with other: HouseholdLedger) -> HouseholdLedger {
        var byMember: [MemberID: MemberStanding] = [:]
        for standing in standings + other.standings {
            guard let existing = byMember[standing.member] else {
                byMember[standing.member] = standing
                continue
            }
            if (standing.lastActive, standing.streak) > (existing.lastActive, existing.streak) {
                byMember[standing.member] = standing
            }
        }
        // Freshest first, so `trimmed` drops the stalest and the encoding is
        // stable between two phones that hold the same facts.
        let ordered = byMember.values.sorted {
            ($0.lastActive, $0.streak, $0.member.value) > ($1.lastActive, $1.streak, $1.member.value)
        }
        return HouseholdLedger(standings: ordered)
    }

    /// The same ledger with `standing` taking the place of that member's entry,
    /// unconditionally.
    ///
    /// Unconditional on purpose, and the one place the merge rule is not
    /// applied: this is a phone writing *its own* standing, where it is the
    /// authority even when its news is worse. A young person whose streak just
    /// broke must not have the tag's older, longer number win it back.
    func setting(_ standing: MemberStanding) -> HouseholdLedger {
        var kept = standings.filter { $0.member != standing.member }
        kept.insert(standing, at: 0)
        return HouseholdLedger(standings: kept)
    }

    /// At most `maximumMembers`, freshest kept.
    func trimmed() -> HouseholdLedger {
        HouseholdLedger(standings: Array(standings.prefix(HouseholdLedgerFormat.maximumMembers)))
    }

    /// What should go back on a tag that was carrying `tagPayload`.
    ///
    /// The whole exchange in one pure function, and it is one function on
    /// purpose: it runs inside an NFC callback on a background queue, where
    /// nothing that touches a store or a screen can go. Everything the caller
    /// needs is a value it computed before the session opened.
    ///
    /// The order matters and is the seam this feature can get wrong. `merged`
    /// first, so everyone else's news is taken in; `setting` second, so this
    /// phone's view of *itself* wins unconditionally. Reversed, the tag's
    /// stale copy of us would beat our own history whenever it happened to
    /// carry the same day and a longer run — handing back a streak that broke.
    func afterExchange(with tagPayload: String?, own: MemberStanding?) -> HouseholdLedger {
        var result = self
        if let tagPayload, let incoming = HouseholdLedger.decoded(tagPayload) {
            result = result.merged(with: incoming)
        }
        if let own { result = result.setting(own) }
        return result.trimmed()
    }

    // MARK: - The shared number

    /// The run of days on which *everyone* took part, and the day it is true
    /// as of.
    ///
    /// Everyone, not anyone. That is the decision the whole feature turns on:
    /// a number that counts the child alone is the number they already have,
    /// and the point of #10 is to put the parent's phone inside it.
    ///
    /// It is the intersection of the members' runs, which is computable because
    /// each run is contiguous by definition: it ends at the earliest
    /// `lastActive` anybody reports and starts at the latest run start, so its
    /// length is the overlap or nothing.
    ///
    /// `nil` for a household of one. A "shared" streak with one member is that
    /// member's own streak wearing a different hat, and showing it would be the
    /// product claiming a thing it has not got.
    func streak(asOf reference: ScheduleOccurrence, calendar: Calendar) -> HouseholdStreak? {
        guard standings.count > 1 else { return nil }

        var earliestEnd: Int?
        var latestStart: Int?
        for standing in standings {
            guard let end = standing.lastActive.dayNumber(in: calendar) else { return nil }
            // A member seen but not Dadding ends the run rather than being
            // skipped over. Skipping them is exactly how a household streak
            // quietly becomes one person's streak with extra words on it.
            let start = end - standing.streak
            earliestEnd = min(earliestEnd ?? end, end)
            latestStart = max(latestStart ?? start, start)
        }

        guard let end = earliestEnd, let start = latestStart,
              let today = reference.dayNumber(in: calendar) else { return nil }

        // The same forgiveness `DadStats.currentStreak` gives one phone: a run
        // that ends yesterday is still current, because today is not over.
        // Beyond that the run is history, and reporting it as live is the
        // stale-number lie this type exists to avoid.
        //
        // Freshness is asked separately from length, so "everyone is up to
        // date and the shared run is nought" is sayable. Folding the two — an
        // empty run reported as stale — would put a "check the tag" note in
        // front of a household whose tag is perfectly current.
        let isCurrent = end >= today - 1

        // `end - start` goes negative when nobody shares a day. The clamp is
        // in `HouseholdStreak`, not here: a mutation proved a `max(0, …)` on
        // this line could not change any output, because the only path that
        // reads it already zeroes a stale run. A guard no test can reach is
        // not a guard.
        return HouseholdStreak(days: isCurrent ? end - start : 0,
                               members: standings.count,
                               asOf: lastActiveDay,
                               isCurrent: isCurrent)
    }

    /// The freshest day any member reports — how up to date the tag is.
    var lastActiveDay: ScheduleOccurrence? {
        standings.map(\.lastActive).max()
    }

    // MARK: - The wire format

    /// `d1;a1b2c3d4,20260903,7;e5f6a7b8,20260902,3`
    ///
    /// A line rather than JSON because the budget is a hundred and twenty
    /// bytes and JSON spends a third of them on punctuation. Members are
    /// dropped from the stale end until it fits, so this never returns
    /// something a tag would refuse.
    func encoded() -> String {
        var kept = trimmed().standings
        while true {
            let line = Self.line(kept)
            if line.utf8.count <= HouseholdLedgerFormat.maximumPayload || kept.count <= 1 {
                return line
            }
            kept.removeLast()
        }
    }

    private static func line(_ standings: [MemberStanding]) -> String {
        ([HouseholdLedgerFormat.prefix + String(HouseholdLedgerFormat.version)]
         + standings.map {
            "\($0.member.value),\($0.lastActive.year)\(String(format: "%02d%02d", $0.lastActive.month, $0.lastActive.day)),\($0.streak)"
         }).joined(separator: ";")
    }

    /// `nil` for anything this build does not understand, including a tag
    /// written by a later one.
    ///
    /// Lenient *within* a version — an unreadable member is skipped and the
    /// rest are kept, following `LenientDecoding` — because a single corrupt
    /// field on a shared physical object must not cost the whole household
    /// their number. Strict *across* versions, because a later build's fields
    /// cannot be guessed and half-reading them would write the guess back.
    static func decoded(_ payload: String) -> HouseholdLedger? {
        var parts = payload.split(separator: ";", omittingEmptySubsequences: false)
        guard let header = parts.first,
              header.hasPrefix(HouseholdLedgerFormat.prefix),
              Int(header.dropFirst(HouseholdLedgerFormat.prefix.count)) == HouseholdLedgerFormat.version
        else { return nil }
        parts.removeFirst()

        var standings: [MemberStanding] = []
        for part in parts {
            let fields = part.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count == 3,
                  let member = MemberID(String(fields[0])),
                  let day = ScheduleOccurrence(compact: String(fields[1])),
                  let streak = Int(fields[2]), streak >= 0,
                  !standings.contains(where: { $0.member == member })
            else { continue }
            standings.append(MemberStanding(member: member, lastActive: day, streak: streak))
        }
        return HouseholdLedger(standings: standings)
    }
}

/// The shared number, with the honesty attached to it.
///
/// `asOf` and `isCurrent` travel with `days` rather than being worked out again
/// by whoever displays it, because the failure this feature can produce is a
/// stale number shown as a live one — and that failure is invisible at the
/// call site if the call site is the thing that has to remember.
struct HouseholdStreak: Equatable {

    /// Consecutive days everyone took part. Never negative, and zero when the
    /// run is not current.
    let days: Int

    let members: Int

    /// The freshest day the tag knows about, which is as recent as this number
    /// can possibly be. `nil` when nobody has ever been active.
    let asOf: ScheduleOccurrence?

    /// Whether the tag is as up to date as it can be: every member reports a
    /// last-active day of today or yesterday.
    ///
    /// Separate from `days` being zero, because they mean different things to
    /// the person reading them. A run of nought that is current says "start
    /// one"; a run of nought that is not says "the tag has not seen everybody
    /// lately", and only the second is a reason to go and tap it.
    let isCurrent: Bool

    /// The one place the count is clamped. Negative days are what an overlap
    /// of nothing computes to, and a negative streak is not a shorter one —
    /// it is a number that would be formatted and shown.
    init(days: Int, members: Int, asOf: ScheduleOccurrence?, isCurrent: Bool) {
        self.days = max(0, days)
        self.members = members
        self.asOf = asOf
        self.isCurrent = isCurrent
    }
}

// MARK: - Days as numbers

extension ScheduleOccurrence {

    /// Days since a fixed reference, for arithmetic that has to cross months.
    ///
    /// Goes through the calendar rather than doing sums on the components: the
    /// month lengths, the leap years and the day a time zone shifts are exactly
    /// the cases a hand-rolled version gets wrong, and they are all cases that
    /// happen to somebody.
    func dayNumber(in calendar: Calendar) -> Int? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { return nil }
        return calendar.dateComponents([.day],
                                       from: Date(timeIntervalSinceReferenceDate: 0),
                                       to: date).day
    }

    /// "20260903", the eight-digit form the tag carries.
    init?(compact: String) {
        guard compact.count == 8, let value = Int(compact) else { return nil }
        let year = value / 10_000
        let month = (value / 100) % 100
        let day = value % 100
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        self.init(year: year, month: month, day: day)
    }
}
