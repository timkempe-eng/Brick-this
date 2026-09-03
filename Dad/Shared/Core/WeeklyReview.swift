import Foundation

/// The week, told back to the household as numbers.
///
/// `DadStats` answers "how much, ever" — totals, streaks, a rolling bar chart.
/// This answers a different question: "what did *this week* look like, and how
/// does it sit against the one before it". They deliberately do not share code
/// beyond `DadSession`; the streak logic and the 7-day chart stay where they
/// are, and nothing here recomputes them.
///
/// Three rules shape almost every decision below.
///
/// **A session counts toward the day it started.** The same rule `DadStats`
/// uses for streaks, applied here to days, weeks and parts of day alike. A
/// session begun at 23:40 on Saturday and released at 00:20 on Sunday is a
/// Saturday session, in the week Saturday belongs to, in the evening bucket —
/// because that is how anyone would describe it out loud, and because the
/// alternative (splitting a session across boundaries) produces day totals
/// that no one can reconcile against the session list they can see.
///
/// **This is one phone's week.** There is deliberately no API here that takes
/// two histories, two people or two devices. A weekly review that ranks a
/// household against each other is a review nobody in the household wants to
/// open twice, and the surest way to make sure it never gets built is to give
/// it nowhere to live.
///
/// **Values, not verdicts.** Almost everything here is a number or a small
/// enum for the view to phrase. The little text this type does produce is
/// stated flat — no praise, no scolding, no "you only managed". The one
/// competitor review that mattered here abandoned an app for feeling
/// "annoying and intrusive and somewhat judgmental", and that is exactly how a
/// teenager stops reading something. Where a name had to choose between an
/// evaluative word and a factual one — `busiest` rather than `best`, `quietest`
/// rather than `worst` — the factual one won: more time Dadded is not
/// self-evidently better, and this type is in no position to say.
///
/// Like `DadStats` it takes the *whole* history and does its own windowing.
/// It needs more than the current week: last week for the comparison, and up
/// to thirty days back for the emergency allowance, whose window is longer
/// than the review it appears in.
///
/// Foundation-only and stateless, so every awkward part — week starts, days
/// that have not happened yet, a percentage against an empty baseline — is
/// reachable from `swift test` without a device.
struct WeeklyReview {

    /// Finished sessions only. Order is irrelevant; everything here windows
    /// by date rather than by position.
    let sessions: [DadSession]
    let calendar: Calendar
    let now: Date

    /// - Parameter calendar: injected so tests can pin a time zone. The app
    ///   passes `.current`, which is what the user's day boundaries actually
    ///   are — and, just as importantly, whose `firstWeekday` decides where
    ///   this week starts. A review that began the week on Monday for a user
    ///   whose phone begins it on Sunday would disagree with every other date
    ///   the phone shows them.
    init(sessions: [DadSession], now: Date = Date(), calendar: Calendar = .current) {
        // Only finished sessions count, for the same reason as `DadStats`: an
        // in-flight session has no duration yet, so including it would make
        // this week creep upward each time the screen is opened, and could
        // flip the week-over-week comparison while you watch it.
        self.sessions = sessions.filter { $0.endedAt != nil }
        self.calendar = calendar
        self.now = now
    }

    // MARK: - Week boundaries

    /// The week `now` falls in, per the injected calendar's `firstWeekday`.
    var week: DateInterval { Self.week(containing: now, calendar: calendar) }

    /// The week before it. Stepped with `.weekOfYear` rather than by
    /// subtracting 604800 seconds, because a week containing a DST change is
    /// not 604800 seconds long and the arithmetic version lands an hour inside
    /// the wrong week twice a year.
    var previousWeek: DateInterval {
        guard let aWeekAgo = calendar.date(byAdding: .weekOfYear, value: -1, to: week.start) else {
            return DateInterval(start: week.start.addingTimeInterval(-Self.nominalWeek),
                                duration: Self.nominalWeek)
        }
        return Self.week(containing: aWeekAgo, calendar: calendar)
    }

    private static let nominalWeek: TimeInterval = 7 * 24 * 60 * 60

    private static func week(containing date: Date, calendar: Calendar) -> DateInterval {
        if let interval = calendar.dateInterval(of: .weekOfYear, for: date) { return interval }
        // Unreachable for any calendar Foundation ships. Falling back to a
        // seven-day window from midnight keeps every derived value defined
        // rather than silently reporting an empty week.
        return DateInterval(start: calendar.startOfDay(for: date), duration: nominalWeek)
    }

    /// Half-open on purpose: `DateInterval.contains` is closed at both ends, so
    /// a session starting exactly on a week boundary would be counted in both
    /// weeks — and would then appear on both sides of the week-over-week
    /// comparison, which is the one place a double count actually changes a
    /// number the household reads.
    private func sessions(in interval: DateInterval) -> [DadSession] {
        sessions.filter { $0.startedAt >= interval.start && $0.startedAt < interval.end }
    }

    var sessionsThisWeek: [DadSession] { sessions(in: week) }

    // MARK: - The week in one number

    var totalThisWeek: TimeInterval { sessionsThisWeek.reduce(0) { $0 + $1.duration } }
    var sessionCountThisWeek: Int { sessionsThisWeek.count }

    // MARK: - Per Mode

    struct ModeTotal: Identifiable, Hashable {
        let modeID: UUID
        let modeName: String
        let total: TimeInterval
        let sessionCount: Int
        var id: UUID { modeID }
    }

    /// Time reclaimed per Mode this week, most first.
    ///
    /// Grouped by `modeID`, not by name: renaming "Deep Work" to "Homework"
    /// mid-week should move a bar's label, not split it into two bars. The
    /// name shown is the one from that Mode's most recent session this week,
    /// which is the name the user currently sees in the Modes list.
    ///
    /// Ties are broken by name and then by id so the order is stable between
    /// two reads of the same history. An unordered tie-break is invisible in
    /// tests and infuriating on screen, where two equal Modes swap places
    /// every time the view redraws.
    var timeByMode: [ModeTotal] {
        var totals: [UUID: TimeInterval] = [:]
        var counts: [UUID: Int] = [:]
        var latestName: [UUID: (name: String, at: Date)] = [:]

        for session in sessionsThisWeek {
            totals[session.modeID, default: 0] += session.duration
            counts[session.modeID, default: 0] += 1
            if let known = latestName[session.modeID], known.at >= session.startedAt { continue }
            latestName[session.modeID] = (session.modeName, session.startedAt)
        }

        return totals.map { id, total in
            ModeTotal(modeID: id,
                      modeName: latestName[id]?.name ?? "",
                      total: total,
                      sessionCount: counts[id] ?? 0)
        }
        .sorted { a, b in
            if a.total != b.total { return a.total > b.total }
            if a.modeName != b.modeName { return a.modeName < b.modeName }
            return a.modeID.uuidString < b.modeID.uuidString
        }
    }

    // MARK: - Which days

    struct Day: Identifiable, Hashable {
        /// Midnight, in the injected calendar's time zone.
        let date: Date
        /// `Calendar`'s weekday number — 1 is Sunday in the Gregorian calendar.
        /// Left as a number rather than a localised name so the view can format
        /// it in the user's language without this type carrying a formatter.
        let weekday: Int
        let total: TimeInterval
        let sessionCount: Int
        /// False for the days of this week still to come.
        ///
        /// This is the difference between "we never Dad on Fridays" and "it is
        /// Wednesday". Without it, every mid-week review shows a row of empty
        /// bars at the end and invites the household to read a pattern into
        /// days that have not happened.
        let hasHappened: Bool
        var id: Date { date }
    }

    /// All seven days of this week, oldest first, empty ones kept.
    ///
    /// Days are never dropped for being empty: the gaps *are* the finding. A
    /// household that wants to see "nothing on Fridays" can only see it if
    /// Friday has a row. One week cannot support a claim about every Friday,
    /// which is exactly why this returns days rather than a sentence.
    var days: [Day] {
        var totals: [Date: TimeInterval] = [:]
        var counts: [Date: Int] = [:]
        for session in sessionsThisWeek {
            let day = calendar.startOfDay(for: session.startedAt)
            totals[day, default: 0] += session.duration
            counts[day, default: 0] += 1
        }

        let today = calendar.startOfDay(for: now)
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: week.start) else { return nil }
            // Re-normalised to midnight: adding days to a week start is exact
            // in every calendar Foundation ships, but a DST transition that
            // skips midnight would otherwise leave an hour of drift in the key
            // these totals are looked up by.
            let midnight = calendar.startOfDay(for: day)
            return Day(date: midnight,
                       weekday: calendar.component(.weekday, from: midnight),
                       total: totals[midnight] ?? 0,
                       sessionCount: counts[midnight] ?? 0,
                       hasHappened: midnight <= today)
        }
    }

    /// The days of this week that have actually arrived.
    var daysSoFar: [Day] { days.filter(\.hasHappened) }

    /// Days with at least one session. Counted by session, not by duration: a
    /// two-minute session still means the phone was Dadded that day.
    var activeDayCount: Int { days.filter { $0.sessionCount > 0 }.count }

    // MARK: - Which times of day

    /// Four buckets, wide enough that a session lands in the one a person would
    /// name it by. Night wraps midnight, which is why this is a function over
    /// the hour rather than a range comparison.
    enum PartOfDay: String, CaseIterable, Hashable {
        case morning, afternoon, evening, night

        static func containing(hour: Int) -> PartOfDay {
            switch hour {
            case 5..<12:  return .morning
            case 12..<17: return .afternoon
            case 17..<22: return .evening
            default:      return .night
            }
        }

        /// Copy lives here, next to the boundaries it names, for the same
        /// reason `WidgetSnapshot` keeps its strings in Core: a label that
        /// disagrees with the bucket it sits on is a bug, and it can only be
        /// tested if both are in the same place.
        var label: String {
            switch self {
            case .morning:   return "Morning"
            case .afternoon: return "Afternoon"
            case .evening:   return "Evening"
            case .night:     return "Night"
            }
        }
    }

    struct PartOfDayTotal: Identifiable, Hashable {
        let part: PartOfDay
        let total: TimeInterval
        let sessionCount: Int
        var id: PartOfDay { part }
    }

    /// All four buckets in clock order, empty ones kept — same reasoning as
    /// `days`: an absent bucket reads as a missing bar, not as a zero.
    ///
    /// A session is filed by the hour it *started*, never split across
    /// buckets. A 21:00–23:00 session is an evening session in full; carving
    /// it into an evening hour and a night hour would give the household a
    /// chart whose numbers do not add up to any session they can point at.
    var timeOfDay: [PartOfDayTotal] {
        var totals: [PartOfDay: TimeInterval] = [:]
        var counts: [PartOfDay: Int] = [:]
        for session in sessionsThisWeek {
            let part = PartOfDay.containing(hour: calendar.component(.hour, from: session.startedAt))
            totals[part, default: 0] += session.duration
            counts[part, default: 0] += 1
        }
        return PartOfDay.allCases.map {
            PartOfDayTotal(part: $0, total: totals[$0] ?? 0, sessionCount: counts[$0] ?? 0)
        }
    }

    /// Nil when the week is empty. Ties go to the earlier part of the day, so
    /// the answer does not wobble between reads.
    var busiestPartOfDay: PartOfDay? {
        let used = timeOfDay.filter { $0.total > 0 }
        guard let top = used.map(\.total).max() else { return nil }
        return used.first { $0.total == top }?.part
    }

    // MARK: - Busiest and quietest day

    /// Deliberately not "best and worst".
    ///
    /// The `.notEnoughDays` case exists because of a specific way this feature
    /// misleads: with one day of data, "your busiest day was Tuesday" is true,
    /// vacuous, and reads as a finding. Anything the view could phrase as a
    /// contrast needs at least two days that have happened *and* at least two
    /// days with something on them — otherwise the comparison is against a day
    /// that had no chance to compete.
    ///
    /// `.level` covers the other way a contrast lies: when every day that has
    /// happened carries the same total, naming one of them "busiest" invents a
    /// difference out of a tie.
    enum DayContrast: Equatable {
        /// Fewer than two days with sessions, or fewer than two days elapsed.
        case notEnoughDays(activeDays: Int)
        /// Every day so far carries the same total; there is no contrast to draw.
        case level(each: TimeInterval)
        case contrast(busiest: Day, quietest: Day)
    }

    /// Quietest is chosen among the days that have *happened*, including empty
    /// ones — a zero Friday in a week with four busy days is the single most
    /// useful thing on this screen, and skipping empty days would hide it.
    var dayContrast: DayContrast {
        let elapsed = daysSoFar
        let active = activeDayCount
        guard elapsed.count >= 2, active >= 2 else { return .notEnoughDays(activeDays: active) }

        // Ties resolve to the earlier day in both directions, so the pair is
        // stable across reads and the two ends never land on the same day.
        let ranked = elapsed.enumerated()
        let busiest = ranked.min {
            $0.element.total != $1.element.total
                ? $0.element.total > $1.element.total
                : $0.offset < $1.offset
        }!.element
        let quietest = ranked.min {
            $0.element.total != $1.element.total
                ? $0.element.total < $1.element.total
                : $0.offset < $1.offset
        }!.element

        if busiest.total == quietest.total { return .level(each: busiest.total) }
        return .contrast(busiest: busiest, quietest: quietest)
    }

    // MARK: - Against last week

    /// Below this, last week is not a baseline worth dividing by.
    ///
    /// Fifteen minutes is a judgement call, but the failure it prevents is
    /// not: two minutes last week and ninety this week is "+4,400%", which is
    /// arithmetically correct and a lie in every sense that matters. The same
    /// movement stated in absolute terms — "88 minutes more than last week" —
    /// is honest and needs no caveat.
    static let smallestComparableWeek: TimeInterval = 15 * 60

    /// What we are willing to say about this week versus last.
    ///
    /// The zero-baseline decision, stated once: **when last week was empty we
    /// report no percentage at all.** Not "+100%", not "∞", not "new". A
    /// percentage change needs something to be a percentage *of*, and the two
    /// tempting substitutes are both wrong — "+100%" understates going from
    /// nothing to nine hours, and "∞" is not a number anyone wants in a
    /// household review. The view gets the two raw totals and phrases it as
    /// the plain fact it is: last week had nothing to compare against.
    enum WeekComparison: Equatable {
        /// Last week had no finished sessions at all. Absolute values only.
        case noBaseline(thisWeek: TimeInterval)
        /// Last week had something, but too little to divide by. Absolute
        /// values only, for the same reason.
        case baselineTooSmall(thisWeek: TimeInterval, lastWeek: TimeInterval)
        /// Both weeks are substantial enough that a proportion means something.
        case measured(thisWeek: TimeInterval, lastWeek: TimeInterval)

        var thisWeek: TimeInterval {
            switch self {
            case .noBaseline(let this): return this
            case .baselineTooSmall(let this, _), .measured(let this, _): return this
            }
        }

        var lastWeek: TimeInterval {
            switch self {
            case .noBaseline: return 0
            case .baselineTooSmall(_, let last), .measured(_, let last): return last
            }
        }

        /// Always available, always honest. Negative means less than last week,
        /// which is a fact and not a failing.
        var delta: TimeInterval { thisWeek - lastWeek }

        /// The proportional change, or `nil` when there is no baseline worth
        /// dividing by. `nil` is not "no change" — the view must render the two
        /// cases differently, which is why this is optional rather than 0.
        var fraction: Double? {
            guard case .measured(let this, let last) = self, last > 0 else { return nil }
            return (this - last) / last
        }
    }

    var comparison: WeekComparison {
        let last = sessions(in: previousWeek).reduce(0) { $0 + $1.duration }
        let this = totalThisWeek
        if last <= 0 { return .noBaseline(thisWeek: this) }
        if last < Self.smallestComparableWeek {
            return .baselineTooSmall(thisWeek: this, lastWeek: last)
        }
        return .measured(thisWeek: this, lastWeek: last)
    }

    // MARK: - How sessions ended

    /// Ended by tapping the tag, or by an auto-release — either way, no
    /// override was spent. `DadStats` counts the same thing over all history
    /// and calls it `cleanFinishes`; this week's version is named for what
    /// happened rather than for how it scores, because this number appears on
    /// a screen a teenager reads.
    var endedAtTheTag: Int { sessionsThisWeek.filter { !$0.endedByEmergency }.count }

    var endedWithAnOverride: Int { sessionsThisWeek.filter(\.endedByEmergency).count }

    // MARK: - Running out of overrides

    /// The days this week on which an emergency override took the last of the
    /// rolling allowance.
    ///
    /// This is the moment `DadSession.allowanceSpentAt` is meant to record.
    /// Nothing stores this, so it is recovered: an override is spent at the
    /// session's `endedAt`, and `EmergencyAllowance` already knows how many
    /// remain at any instant. Replaying the overrides in order and asking it
    /// after each one gives the same answer a stored timestamp would, with the
    /// advantage of needing no schema bump and no migration for the sessions
    /// already on disk (see `SchemaCoding`).
    ///
    /// **Not to be confused with a rationed Mode's daily allowance**, which is
    /// `daysTheRationRanOut` below and is a different number about a different
    /// thing. The two were briefly the same property, because "allowance"
    /// names both the five emergency overrides and the minutes a rationing
    /// Mode hands out. `ModeAllowance`'s own doc comment warns about exactly
    /// this collision; it still caught us.
    ///
    /// Two boundary decisions, both consistent with the rest of this type:
    ///
    /// - The exhaustion is attributed to the day the *session started*, not
    ///   the instant the override was spent. A session begun at 23:40 and
    ///   broken at 00:10 keeps all of its numbers on one day; splitting it
    ///   would put a household's "we ran out on Tuesday" on Wednesday.
    /// - The replay runs over the *whole* history, because the allowance
    ///   window is thirty days and the fifth use of a window that opened three
    ///   weeks ago still lands in this week.
    var daysTheOverrideAllowanceRanOut: [Date] {
        let overrides = sessions
            .compactMap { session -> (spentAt: Date, day: Date)? in
                guard session.endedByEmergency, let spentAt = session.endedAt else { return nil }
                return (spentAt, calendar.startOfDay(for: session.startedAt))
            }
            .sorted { $0.spentAt < $1.spentAt }

        var found: [Date] = []
        for (index, override) in overrides.enumerated() {
            // Uses up to and including this one: an override that has not
            // happened yet cannot be what emptied the allowance.
            let sofar = overrides.prefix(index + 1).map(\.spentAt)
            guard EmergencyAllowance.remaining(uses: sofar, now: override.spentAt) == 0 else { continue }
            guard override.day >= week.start, override.day < week.end else { continue }
            if !found.contains(override.day) { found.append(override.day) }
        }
        return found
    }

    /// How many days this week the hatch was closed behind you.
    var daysTheOverrideAllowanceRanOutCount: Int { daysTheOverrideAllowanceRanOut.count }

    /// Days this week a rationing Mode's daily minutes ran out.
    ///
    /// The *other* allowance: a Mode that hands out fifteen minutes of an app
    /// a day rather than taking it away. `DadSession.allowanceSpentAt` records
    /// the moment it happened, so unlike the overrides above this one is read
    /// rather than reconstructed.
    ///
    /// Attributed to the day the session *started*, like every other number
    /// here — a session begun at 23:40 whose ration ran out at 00:10 keeps its
    /// numbers on one day, or a household's "we ran out on Tuesday" lands on
    /// Wednesday.
    var daysTheRationRanOut: [Date] {
        var found: [Date] = []
        for session in sessionsThisWeek where session.allowanceSpentAt != nil {
            let day = calendar.startOfDay(for: session.startedAt)
            if !found.contains(day) { found.append(day) }
        }
        return found.sorted()
    }

    var daysTheRationRanOutCount: Int { daysTheRationRanOut.count }

    // MARK: - Is there enough here to say anything?

    /// The honest empty state, decided here rather than guessed at by the view.
    ///
    /// A chart of one bar under a bold claim is the failure mode this exists to
    /// prevent. Two days is the bar: one day is an anecdote, and the moment
    /// there are two the view can legitimately draw a shape.
    enum DataAdequacy: Equatable {
        case nothingYet
        case oneDayOnly(sessions: Int)
        case enough(days: Int, sessions: Int)

        var isEnoughToSaySomething: Bool {
            if case .enough = self { return true }
            return false
        }
    }

    var adequacy: DataAdequacy {
        let days = activeDayCount
        let count = sessionCountThisWeek
        if count == 0 { return .nothingYet }
        if days < 2 { return .oneDayOnly(sessions: count) }
        return .enough(days: days, sessions: count)
    }

    // MARK: - The one line of copy

    /// A flat statement of what happened, for the top of the screen.
    ///
    /// Everything else on this type is a value the view phrases; this is the
    /// exception, and it is kept here for the reason `WidgetSnapshot` gives:
    /// what the app *says* is a decision, and decisions belong where
    /// `swift test` can reach them.
    ///
    /// It reports and stops. No "only", no "just", no "well done", no mention
    /// of a streak — a streak in a headline is a debt notice, and a household
    /// review is not the place to open one.
    var headline: String {
        switch adequacy {
        case .nothingYet:
            return "No \(Vocab.sessionNoun)s this week."
        case .oneDayOnly(let count), .enough(_, let count):
            let sessions = "\(count) session\(count == 1 ? "" : "s")"
            let days = "\(activeDayCount) day\(activeDayCount == 1 ? "" : "s")"
            return "\(totalThisWeek.dadDurationText) \(Vocab.verbPast) over \(sessions) on \(days)."
        }
    }
}
