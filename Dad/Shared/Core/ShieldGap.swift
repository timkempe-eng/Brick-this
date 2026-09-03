import Foundation

/// Was there a stretch where the phone should have been Dadded, and does the
/// evidence say it was not?
///
/// The restrictions are held by the system, not by this app, which is why
/// force-quitting Dad does not unblock anything. But "held by the system" is
/// not "unbreakable": Screen Time authorization can be withdrawn in Settings,
/// a device can be restored from a backup, an extension can be jetsammed. When
/// any of that happens `reconcile()` quietly puts the shield back and says
/// nothing, so a night with no shield and a night with a shield look identical
/// afterwards.
///
/// This file is the pure half of fixing that: given what the app was able to
/// observe, it says where the evidence has a hole in it. It is deliberately a
/// function over a value type rather than anything stateful, for the same
/// reason `DadStats` is — the awkward parts here are time arithmetic and
/// wording, and both are only testable if nothing else is in the way.
///
/// # The copy constraint, which is the whole point
///
/// **A gap is evidence of a gap, not proof of intent.** A phone that ran out
/// of battery, a restore, an iOS update and a deliberate revocation all look
/// exactly the same from in here — there is no observation that separates
/// them, and there never will be, because the app is absent during the gap by
/// definition. So every string in this file reports *what was observed* and
/// never *why*, and `caveat` ships the innocent explanations alongside the
/// number so a reader is not left to supply a motive of their own.
///
/// Nothing here may say or imply that a person did something. The README's
/// position is that Dad is a boundary, not a spy, and this is the one feature
/// that can violate that by accident: the moment the copy says "someone turned
/// this off", the tool has become the problem in the household rather than the
/// thing that solved it. Where a sentence would have to assign blame to be
/// useful, the value is exposed instead and the view is left to say nothing.
///
/// # Why this is not simply "reconcile had to re-apply the shield"
///
/// The tempting cheap signal is: `reconcile()` calls `shield.apply(mode)`, so
/// if it had to apply, the shield must have been missing. That is wrong, and
/// wrong in the direction that accuses people. `reconcile()` re-applies on
/// *every* foreground — it is idempotent by design, precisely so a
/// half-finished start cannot strand anyone — and the system was holding the
/// restrictions the entire time. A gap detector built on that would light up
/// every single time the app was opened during a session, and the number it
/// produced would be an accusation with no evidence under it at all.
///
/// The two observations below are the ones that genuinely carry information.
///
/// # Everything here is derivable at the next foreground
///
/// Dad has no background wake it can rely on. Nothing in this file needs one:
/// each input is either read at the moment of the check or persisted across
/// process death, so the whole report is reconstructible from stored values
/// the next time the app comes to the front. That is the same backstop shape
/// as `reconcile()` itself.

// MARK: - What the app can actually observe

/// Screen Time authorization as the app finds it, at the moment it looks.
///
/// `.unknown` is not a polite spelling of `.notApproved`. Being unable to ask
/// the question is not an answer to it, and a report that treated the two
/// alike would manufacture gaps out of a slow or unavailable
/// `AuthorizationCenter` — exactly the class of false positive this feature
/// cannot afford, because here a false positive reads as an accusation.
enum ShieldAuthorization: Equatable {
    case approved
    case notApproved
    case unknown
}

/// Who a report would be addressed to.
///
/// One adult Dadding their own phone has nobody to explain anything to. They
/// already know their phone rebooted; a running tally of the times Dad lost
/// sight of the shield turns a boundary they chose into a self-audit they
/// didn't, which is the tone the README exists to refuse. So `.solo`
/// suppresses the retrospective copy entirely and keeps only what is
/// actionable *about the tool* — see `ShieldGapReport.setupNote`.
///
/// The default is `.solo` deliberately. The failure mode of getting this field
/// wrong is a household where the app appears to accuse somebody, so the value
/// you get by not thinking about it has to be the quiet one.
enum ShieldAudience: Equatable {
    case solo
    case shared
}

/// One scheduled window that has already opened, clipped to the present.
struct ScheduledOccurrence: Equatable {
    let modeName: String
    /// From the window's start to its end, or to `now` if it is still open.
    let interval: DateInterval
}

/// Everything the report is allowed to know.
///
/// Assembled by the caller from `DadEngine`'s own store and ports at a
/// foreground; the notes on each field say where each value comes from.
struct ShieldObservations: Equatable {

    /// The instant the app looked — `clock.now` inside `reconcile()`.
    let now: Date

    /// Screen Time authorization, read at `now`.
    let authorization: ShieldAuthorization

    /// `store.activeSession?.startedAt`. `nil` when nothing was supposed to be
    /// held, in which case absent authorization is a setup problem and not a
    /// gap — there was no shield to lose.
    let activeSessionStartedAt: Date?

    /// The last foreground at which a session was running *and* authorization
    /// was approved: the most recent moment the app can honestly say the
    /// shield was in place. Persisted, because it is the left edge of the
    /// bound below and it has to survive the process dying.
    ///
    /// `nil` means there has been no such moment during this session, and the
    /// bound falls back to the session's own start.
    let lastConfirmedAt: Date?

    /// Scheduled windows that have already opened, from `ShieldGap.occurrences`.
    let occurrences: [ScheduledOccurrence]

    /// Every stretch the records say the phone was Dadded — finished sessions
    /// from `store.history` plus the active one, as intervals. Used only to
    /// rule occurrences *out*; see `ShieldGap.scheduledGaps`.
    let daddedIntervals: [DateInterval]

    let audience: ShieldAudience

    init(now: Date,
         authorization: ShieldAuthorization,
         activeSessionStartedAt: Date? = nil,
         lastConfirmedAt: Date? = nil,
         occurrences: [ScheduledOccurrence] = [],
         daddedIntervals: [DateInterval] = [],
         audience: ShieldAudience = .solo) {
        self.now = now
        self.authorization = authorization
        self.activeSessionStartedAt = activeSessionStartedAt
        self.lastConfirmedAt = lastConfirmedAt
        self.occurrences = occurrences
        self.daddedIntervals = daddedIntervals
        self.audience = audience
    }
}

// MARK: - What was observed

/// Why a stretch is unaccounted for. Two kinds, because there are exactly two
/// observations that carry information, and neither of them is about a person.
enum ShieldGapEvidence: Equatable {
    /// A session was recorded as running, and Screen Time authorization was
    /// found absent. ManagedSettings restrictions do not outlive the
    /// authorization that permitted them, so the shield cannot have been in
    /// place at the moment of the check.
    case authorizationNotInPlace

    /// A scheduled window opened and no session is recorded anywhere inside
    /// it. Either the window never fired, or the session it started was never
    /// written down; either way the records do not show the phone Dadded when
    /// the schedule says it would have been.
    case noSessionForScheduledWindow(modeName: String)
}

/// One stretch the app cannot vouch for.
///
/// `interval` is a *bound*, not a measurement. The app is absent during a gap
/// by construction, so it knows the shield was in place at the left edge and
/// absent at the right edge, and nothing whatsoever about the middle. A gap of
/// six hours may have been six hours or six seconds. Every string this type
/// produces says "up to" for that reason, and the raw interval is exposed so a
/// view can render the two edges rather than one confident number — the same
/// reason `WidgetSnapshot` carries a raw `since` instead of a formatted one.
struct ShieldGap: Equatable {

    let interval: DateInterval
    let evidence: ShieldGapEvidence

    /// The most this gap can have been.
    var longestPossible: TimeInterval { interval.duration }

    // MARK: - Thresholds
    //
    // The numbers below are decisions, not tuning. They are here rather than
    // in a view because getting either wrong changes what the app says about a
    // person, and that belongs where `swift test` can reach it.

    /// Shorter than this and nothing is said at all.
    ///
    /// Tied to `DadEngine.minimumScheduledRelease` on purpose: fifteen minutes
    /// is the shortest interval `DeviceActivitySchedule` will monitor, which
    /// makes it the granularity the platform itself works at. Below it, a
    /// clock correction, a reboot, an iOS update and a slow foreground are all
    /// indistinguishable from each other *and* from a real lapse, and Dad has
    /// no business making a claim at a resolution the system it depends on
    /// does not offer. A smaller number would not find more lapses; it would
    /// find more reboots and call them something else.
    static let minimumReportable: TimeInterval = DadEngine.minimumScheduledRelease

    /// How far back a gap can be and still be worth raising.
    ///
    /// A week. The question this feature answers is "is the setup actually
    /// working?", and that is only worth answering while the answer is still
    /// actionable — the response to a gap is to go and check Screen Time, not
    /// to have a conversation about a Tuesday. Past a week a gap stops being a
    /// diagnostic and becomes a grievance with a timestamp, and a permanent
    /// ledger of those is the thing this file is most careful not to be.
    static let lookback: TimeInterval = 7 * 24 * 60 * 60

    /// Repeated short gaps deliberately do **not** aggregate.
    ///
    /// Recorded as a constant so the decision is visible rather than implied
    /// by the absence of code. Counting sub-threshold observations is the
    /// mechanical definition of building a profile: it turns eleven
    /// four-minute intervals that individually mean nothing into "this keeps
    /// happening", which is a claim about a person drawn from evidence that
    /// does not support one. The failure mode is not symmetric either — a
    /// phone that dies overnight because its battery is old would accumulate
    /// the worst-looking count in the household while nothing was wrong at
    /// all. So each gap stands or falls alone, and the report never totals,
    /// ranks or trends them.
    static let aggregatesShortGaps = false

    // MARK: - Copy

    /// Neutral phrasing of what was observed. States a system condition; never
    /// a cause, and never an actor.
    var evidenceText: String {
        switch evidence {
        case .authorizationNotInPlace:
            return "Screen Time access was not in place."
        case .noSessionForScheduledWindow(let modeName):
            return "No \(modeName) session is recorded for a scheduled window."
        }
    }

    /// "Up to 2h 10m". The "up to" is load-bearing, and is why this is not
    /// just `longestPossible.dadDurationText` at the call site.
    var boundText: String {
        "Up to \(longestPossible.dadDurationText)"
    }
}

// MARK: - The report

struct ShieldGapReport: Equatable {

    /// Newest first. Empty is the normal case, and the one the UI should be
    /// built around.
    let gaps: [ShieldGap]

    /// True when Screen Time access is absent *right now* — a fact about the
    /// tool rather than about anybody's evening: until it is granted again,
    /// the next tap will block nothing.
    let authorizationMissingNow: Bool

    let audience: ShieldAudience

    /// The standing disclaimer, shipped with the number rather than tucked
    /// into a help screen, because the number is meaningless and slightly
    /// dangerous without it.
    static let caveat =
        "A restart, a restore, an iOS update and a change in Settings all look the same from here."

    var caveat: String { Self.caveat }

    /// Nothing to show. The overwhelmingly common case, and for a solo phone
    /// with a working setup, the only one.
    var isSilent: Bool { headline == nil && setupNote == nil }

    /// How many stretches, and nothing more.
    ///
    /// `nil` for a solo audience even when gaps exist. The values stay
    /// available on `gaps` for anything that genuinely needs them; what is
    /// withheld is the sentence, because a sentence addressed to nobody in
    /// particular is the one that gets read as an accusation.
    var headline: String? {
        guard audience == .shared, !gaps.isEmpty else { return nil }
        return gaps.count == 1
            ? "1 unconfirmed stretch"
            : "\(gaps.count) unconfirmed stretches"
    }

    /// The line under the headline. It is the caveat, on purpose: the second
    /// thing a reader should learn is that the first thing does not mean what
    /// they are about to assume it means.
    var detail: String? {
        headline == nil ? nil : caveat
    }

    /// The one thing worth saying to anybody, a household of one included,
    /// because it is about the tool and it can be fixed in the next minute.
    var setupNote: String? {
        guard authorizationMissingNow else { return nil }
        return "Screen Time access is not granted. \(Vocab.appName) cannot hold anything until it is."
    }

    /// Every string this report can currently produce. Exists so the test that
    /// sweeps for blaming language has a complete surface to sweep, rather
    /// than a hand-kept list that quietly falls behind the copy.
    var allStrings: [String] {
        var strings = [caveat]
        strings += [headline, detail, setupNote].compactMap { $0 }
        strings += gaps.flatMap { [$0.evidenceText, $0.boundText] }
        return strings
    }
}

// MARK: - The analysis

extension ShieldGap {

    /// The whole feature, as one pure function.
    static func report(_ observations: ShieldObservations) -> ShieldGapReport {
        let authorizationMissingNow = observations.authorization == .notApproved

        var found = authorizationGap(observations).map { [$0] } ?? []
        let authorizationInterval = found.first?.interval

        for gap in scheduledGaps(observations) {
            // A scheduled window sitting entirely inside an authorization gap
            // is the same event seen twice. Reporting both would double the
            // count, and the count is the only number a reader takes away.
            if let authorizationInterval,
               authorizationInterval.start <= gap.interval.start,
               gap.interval.end <= authorizationInterval.end {
                continue
            }
            found.append(gap)
        }

        let horizon = observations.now.addingTimeInterval(-lookback)
        let kept = found
            .filter { $0.longestPossible >= minimumReportable }
            .filter { $0.interval.end >= horizon }
            .sorted { $0.interval.end > $1.interval.end }

        return ShieldGapReport(gaps: kept,
                               authorizationMissingNow: authorizationMissingNow,
                               audience: observations.audience)
    }

    /// A session was recorded as running and authorization was found absent.
    ///
    /// The left edge is the later of the session's start and the last
    /// confirmation, because both are moments the shield is known to have been
    /// in place and the tighter one is the honest bound. The right edge is
    /// `now` and not a second later: the app learned this at the check, and
    /// pretending it knew earlier would inflate every figure it prints.
    private static func authorizationGap(_ o: ShieldObservations) -> ShieldGap? {
        guard o.authorization == .notApproved else { return nil }
        // Nothing was supposed to be held, so nothing was lost. That is a
        // setup problem, reported as `setupNote`, and it is not a gap.
        guard let startedAt = o.activeSessionStartedAt else { return nil }

        let left = max(startedAt, o.lastConfirmedAt ?? startedAt)

        // A crash guard, not tidiness. `DateInterval(start:end:)` traps when
        // the end precedes the start, and `lastConfirmedAt` can be after `now`
        // for reasons that happen to real phones: a restored backup carrying a
        // stamp from the future, or a clock corrected backwards mid-session —
        // the same events this file's own caveat calls indistinguishable from
        // a gap. The honest answer is no gap, not a crash on the Stats screen.
        //
        // `<` rather than `<=` is taste and not behaviour, and that is worth
        // saying so nobody spends a mutation on it twice: a zero-length gap is
        // below `minimumReportable` and would be filtered out anyway.
        guard left < o.now else { return nil }
        return ShieldGap(interval: DateInterval(start: left, end: o.now),
                         evidence: .authorizationNotInPlace)
    }

    /// A scheduled window opened and the records show no session inside it.
    ///
    /// The test is *any overlap at all*, not full coverage, and that is a
    /// deliberate under-claim. Working out that a ninety-minute window only
    /// held forty minutes of session is exactly the per-minute ledger this
    /// file refuses to keep, and it would be built on records that were never
    /// meant to be evidence. A window with a session anywhere in it is
    /// therefore silent, and the false negative is accepted: over-reporting
    /// here costs somebody's trust, under-reporting costs a line of text.
    private static func scheduledGaps(_ o: ShieldObservations) -> [ShieldGap] {
        o.occurrences.compactMap { occurrence in
            let covered = o.daddedIntervals.contains { overlaps($0, occurrence.interval) }
            guard !covered else { return nil }
            return ShieldGap(interval: occurrence.interval,
                             evidence: .noSessionForScheduledWindow(modeName: occurrence.modeName))
        }
    }

    /// Strict overlap: sharing a single instant is not sharing any time.
    ///
    /// `DateInterval.intersects` says yes when two intervals merely touch, so
    /// a session that ended exactly as a window opened would be read as having
    /// covered it. That is the wrong direction for a silence rule — it hides a
    /// window that genuinely had nothing in it.
    private static func overlaps(_ a: DateInterval, _ b: DateInterval) -> Bool {
        a.start < b.end && b.start < a.end
    }

    /// Scheduled windows that have already opened within the lookback, clipped
    /// to the present.
    ///
    /// Derived from the stored Modes rather than from anything the system
    /// delivered, so it works at the next foreground with no background wake —
    /// the same backstop rule `reconcile()` follows. A window still open
    /// contributes only its elapsed part, because the rest of it has not had a
    /// chance to happen yet and reporting it would be a prediction.
    ///
    /// The end instant is built from the calendar rather than by adding
    /// `schedule.duration`, so a window spanning a daylight-saving change ends
    /// at the wall-clock time the user chose. Adding seconds would have made
    /// the bound an hour wrong twice a year, and every bound in this file is
    /// an upper one already.
    static func occurrences(of modes: [DadMode],
                            now: Date,
                            calendar: Calendar = .current) -> [ScheduledOccurrence] {
        let horizon = now.addingTimeInterval(-lookback)
        var results: [ScheduledOccurrence] = []

        for mode in modes where mode.hasLiveSchedule {
            guard let schedule = mode.schedule else { continue }
            // One extra day back: an overnight window that began just outside
            // the horizon can still end inside it.
            let days = Int(lookback / (24 * 60 * 60)) + 1

            for offset in 0...days {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
                guard schedule.weekdays.contains(calendar.component(.weekday, from: day)) else { continue }
                guard let start = calendar.date(bySettingHour: schedule.startHour,
                                                minute: schedule.startMinute,
                                                second: 0,
                                                of: day) else { continue }
                guard start < now, start >= horizon else { continue }

                let endDay = schedule.crossesMidnight
                    ? calendar.date(byAdding: .day, value: 1, to: start)
                    : start
                guard let endDay,
                      let end = calendar.date(bySettingHour: schedule.endHour,
                                              minute: schedule.endMinute,
                                              second: 0,
                                              of: endDay) else { continue }

                let clipped = min(end, now)
                guard clipped > start else { continue }
                results.append(ScheduledOccurrence(
                    modeName: mode.name,
                    interval: DateInterval(start: start, end: clipped)))
            }
        }

        return results.sorted { $0.interval.start > $1.interval.start }
    }
}
