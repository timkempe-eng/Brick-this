import Foundation

/// Bending a schedule for one night, and saying so ten minutes beforehand.
///
/// Both halves exist because of the same failure, observed in every blocker
/// that lacks them: a schedule you cannot bend gets switched off "just for
/// tonight" and never switched back on. Brick makes you delete the schedule and
/// rebuild it; Unpluq gives you a skip. A schedule that lands mid-sentence gets
/// resented first and disabled second, and the evidence that the schedule was
/// worth keeping is real — a week of limited evening screen use had teenagers
/// falling asleep about twenty minutes earlier.
///
/// Everything here is pure arithmetic over `ModeSchedule`, deliberately: the
/// decisions are the part that goes quietly wrong, and Core is the only place
/// `swift test` can reach. Storing the skips and delivering the notification
/// are adapter work and are not in this file — see the boundary notes on
/// `ScheduleWarning`.

// MARK: - Which occurrence

/// One occurrence of a recurring window, named by the wall-clock day it
/// *starts* on.
///
/// The identifier has to survive a flight and a daylight-saving change, and the
/// choice follows straight from `ModeSchedule` storing wall-clock components
/// rather than instants: 10pm means 10pm after the clocks go forward, not
/// "whatever instant 10pm was when you set it". An occurrence identified by an
/// instant would inherit exactly the bug that storage was designed to avoid —
/// record "skip tonight" on 28 March in London and the stored instant is an
/// hour off the window that actually fires on the 29th, so the skip silently
/// does nothing on the one night the arithmetic is hardest.
///
/// A whole date rather than a weekday, and a whole date rather than a day of
/// the month, because those repeat: a skip recorded in March would suppress a
/// window in June. This one names a day that happens once.
///
/// The start rather than the end, because an overnight window's end lands on
/// the next day and "skip tonight" is a statement about tonight. Pinning the
/// same day to both ends of a 22:00–07:00 window is the mistake
/// `ScheduledWindow.endWeekday` already documents, from the other direction.
struct ScheduleOccurrence: Codable, Hashable, Comparable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    /// The occurrence a window starting at `start` belongs to.
    ///
    /// - Parameter start: the window's *scheduled* start, as computed by
    ///   `ModeSchedule.nextStart(after:calendar:)` — not "now". The system can
    ///   deliver a boundary a little late, and a 23:50 window whose start is
    ///   reported at 00:00:04 would otherwise be filed under the following day
    ///   and its skip would miss.
    init(startingAt start: Date, calendar: Calendar) {
        // `dateComponents` always populates what it was asked for, so the
        // defaults below are unreachable; they exist because Foundation types
        // them as optional.
        let parts = calendar.dateComponents([.year, .month, .day], from: start)
        self.year = parts.year ?? 0
        self.month = parts.month ?? 0
        self.day = parts.day ?? 0
    }

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    static func < (lhs: ScheduleOccurrence, rhs: ScheduleOccurrence) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// "2026-09-03". Sorts the same way it compares, which makes a failing test
    /// readable without decoding three integers by eye.
    var description: String { String(format: "%04d-%02d-%02d", year, month, day) }
}

/// "Not tonight" for one Mode, recorded against one occurrence.
///
/// A value, not a flag on the Mode: a flag would have to be cleared by
/// something, and whatever failed to clear it would leave a Mode that looks
/// scheduled and never fires. This expires by arithmetic instead — see
/// `ScheduleSkipping.live(_:now:calendar:)`.
///
/// `Codable` because it is stored. The `DadPersisting` property that holds
/// these is a separate change: a new port, not a framework import.
struct ScheduleSkip: Codable, Hashable {
    let modeID: UUID
    let occurrence: ScheduleOccurrence
}

// MARK: - Skipping

/// The skip arithmetic: what is still live, whether a window should run, and
/// which occurrence a "Skip tonight" button would take.
///
/// Free functions over a list rather than a mutating store, following
/// `EmergencyAllowance`: the list goes in, the answer and the new list come
/// out, and the window edges are exactly testable.
enum ScheduleSkipping {

    /// How long a skip is kept after the day it names.
    ///
    /// One day, not zero. A skip records the day a window *starts*, and an
    /// overnight window is still open after midnight, so pruning at the stroke
    /// of midnight would throw away a skip whose occurrence has not finished.
    /// The system can deliver `intervalDidStart` more than once — a restart
    /// inside the window will do it — and a skip discarded early would let the
    /// second delivery start the very session the user said no to.
    ///
    /// One day is enough for any window: `ModeSchedule.duration` caps at 24
    /// wall-clock hours, which is at most 25 real hours on the night the clocks
    /// go back, so a window starting on day D has always ended before day D+2
    /// begins.
    static let graceDays = 1

    /// The skips still worth storing at `now`.
    ///
    /// Pruning here rather than in a sweep somewhere means there is no sweep to
    /// forget to run. Note what this is *not* doing: it is not what makes a
    /// stale skip harmless. A skip names one dated day, so a skip recorded in
    /// March cannot match a window in June whether it was pruned or not.
    /// Correctness comes from the identifier; this only stops the list growing
    /// without bound, the same division of labour as
    /// `EmergencyAllowance.recent`.
    static func live(_ skips: [ScheduleSkip],
                     now: Date,
                     calendar: Calendar = .current) -> [ScheduleSkip] {
        let today = calendar.startOfDay(for: now)
        guard let oldestKept = calendar.date(byAdding: .day, value: -graceDays, to: today) else {
            // Only reachable if the calendar refuses day arithmetic. Keeping
            // everything is the harmless failure; dropping everything would
            // silently un-skip tonight.
            return skips
        }
        let cutoff = ScheduleOccurrence(startingAt: oldestKept, calendar: calendar)
        return skips.filter { $0.occurrence >= cutoff }
    }

    /// Whether the window starting at `start` was skipped.
    static func isSkipped(_ skips: [ScheduleSkip],
                          modeID: UUID,
                          windowStartingAt start: Date,
                          calendar: Calendar = .current) -> Bool {
        let occurrence = ScheduleOccurrence(startingAt: start, calendar: calendar)
        return skips.contains(ScheduleSkip(modeID: modeID, occurrence: occurrence))
    }

    /// The answer to "should this window run", together with the list to store
    /// back.
    struct Resolution: Equatable {
        let shouldRun: Bool
        let skips: [ScheduleSkip]
    }

    /// Given this Mode's recorded skips, should the window starting at `start`
    /// actually run?
    ///
    /// Prunes while it answers, like `EmergencyAllowance.consume`, so the only
    /// caller that has to exist is the one already asking the question.
    ///
    /// A skip is *not* consumed by being used. It stays until it expires by
    /// date, because the boundary that asks this can be delivered twice, and
    /// answering "yes, run" the second time would be worse than keeping one
    /// dead entry for a day.
    static func resolve(skips: [ScheduleSkip],
                        modeID: UUID,
                        windowStartingAt start: Date,
                        now: Date,
                        calendar: Calendar = .current) -> Resolution {
        let kept = live(skips, now: now, calendar: calendar)
        let skipped = isSkipped(kept, modeID: modeID, windowStartingAt: start, calendar: calendar)
        return Resolution(shouldRun: !skipped, skips: kept)
    }

    /// The list after recording `skip`, pruned, with no duplicate.
    ///
    /// Returning the list rather than mutating keeps this pure, and de-duping
    /// means tapping "Skip tonight" twice is the same as tapping it once —
    /// there is no second night to un-skip by accident.
    static func adding(_ skip: ScheduleSkip,
                       to skips: [ScheduleSkip],
                       now: Date,
                       calendar: Calendar = .current) -> [ScheduleSkip] {
        let kept = live(skips, now: now, calendar: calendar)
        guard !kept.contains(skip) else { return kept }
        return kept + [skip]
    }

    /// The next moment this schedule starts that has not been skipped, strictly
    /// after `date`.
    ///
    /// Strictly after, inherited from `ModeSchedule.nextStart(after:)`, is what
    /// makes skipping unable to touch a session already running: the occurrence
    /// on offer is always one that has not begun. A skip is a statement about a
    /// window that has not opened yet, never a way to release the phone — the
    /// tag and the emergency override are the only two things that do that.
    ///
    /// Stale skips are left in whatever list the caller passes, on purpose:
    /// they name days that have gone, so they cannot match a future start, and
    /// the loop below simply never trips over them.
    static func nextRunningStart(of schedule: ModeSchedule,
                                 modeID: UUID,
                                 after date: Date,
                                 skips: [ScheduleSkip],
                                 calendar: Calendar = .current) -> Date? {
        var cursor = date
        // Each turn of the loop either answers or steps past one skipped
        // occurrence, and `nextStart` is strictly increasing, so no occurrence
        // is stepped past twice. `skips.count + 1` attempts is therefore enough
        // however many nights in a row were skipped.
        for _ in 0...skips.count {
            guard let start = schedule.nextStart(after: cursor, calendar: calendar) else {
                return nil
            }
            if !isSkipped(skips, modeID: modeID, windowStartingAt: start, calendar: calendar) {
                return start
            }
            cursor = start
        }
        return nil
    }

    /// The skip a "Skip tonight" button would record: the next occurrence that
    /// is still going to run.
    ///
    /// `nil` for a schedule that can never fire, so a button bound to this has
    /// something honest to disable itself with rather than recording a skip
    /// against a window that was never coming.
    static func nextSkip(of schedule: ModeSchedule,
                         modeID: UUID,
                         after now: Date,
                         skips: [ScheduleSkip],
                         calendar: Calendar = .current) -> ScheduleSkip? {
        guard let start = nextRunningStart(of: schedule, modeID: modeID,
                                           after: now, skips: skips, calendar: calendar) else {
            return nil
        }
        return ScheduleSkip(modeID: modeID,
                            occurrence: ScheduleOccurrence(startingAt: start, calendar: calendar))
    }
}

// MARK: - Warning before a scheduled Mode starts

/// "Sleep in ten minutes" — the decision, not the notification.
///
/// Core answers two things: whether a warning is owed at all, and the instant
/// it should be delivered. Everything after that is an adapter — a
/// `WarningScheduling` port over `UNUserNotificationCenter`, plus copy in
/// `Vocab` — and none of it belongs here, for the same reason nothing else in
/// Core imports a framework. The split is the point: the arithmetic that gets
/// this wrong at a midnight or a clock change is testable without a Mac, and
/// the part that needs a device does nothing but deliver a string at a `Date`.
struct ScheduleWarning: Equatable {
    let modeID: UUID
    /// When the notification should be delivered.
    let fireAt: Date
    /// The window start being warned about. Carried so the adapter can write
    /// the time into the copy without recomputing it and disagreeing.
    let windowStart: Date

    var leadTime: TimeInterval { windowStart.timeIntervalSince(fireAt) }
}

extension ScheduleWarning {

    /// Ten minutes.
    ///
    /// Long enough to finish the message you are typing, which is the whole
    /// complaint being answered — a Mode that lands mid-sentence is the one
    /// that gets switched off. Short enough that the notice is still about
    /// *now*: warn half an hour ahead and it is filed as noise and dismissed,
    /// and you get the same resentment by a slower route.
    ///
    /// This is the number in the user-facing copy, so it is spelled out
    /// literally where it is promised rather than only referred to
    /// symbolically.
    static let defaultLeadTime: TimeInterval = 10 * 60

    /// When this Mode's warning should fire, or `nil` for no warning.
    ///
    /// `nil` in four cases, each one a lie avoided rather than a state
    /// invented:
    ///
    /// - the Mode would not start anyway (`hasLiveSchedule` is the same guard
    ///   `DadEngine.beginScheduledSession` applies, so the warning and the
    ///   start can never disagree);
    /// - a session is already running, because `beginScheduledSession` refuses
    ///   to stomp one, so the window being warned about will not open;
    /// - the schedule can never fire again;
    /// - the lead time is not positive, which would make this a notification
    ///   delivered at or after the thing it is warning about.
    ///
    /// An occurrence that has been skipped is not a `nil` case: it is simply
    /// not the occurrence warned about. The answer is the next night that is
    /// actually going to run.
    ///
    /// - Parameter isSessionActive: whether the phone is Dadded right now. The
    ///   answer is only true at the moment it is asked — a session ending
    ///   before the window opens changes it — so the adapter re-asks when a
    ///   session ends. Core cannot know when a session will end; a session with
    ///   no auto-release ends when someone taps the tag.
    static func next(for mode: DadMode,
                     now: Date,
                     skips: [ScheduleSkip] = [],
                     isSessionActive: Bool = false,
                     leadTime: TimeInterval = defaultLeadTime,
                     calendar: Calendar = .current) -> ScheduleWarning? {
        guard leadTime > 0 else { return nil }
        guard !isSessionActive else { return nil }
        guard mode.hasLiveSchedule, let schedule = mode.schedule else { return nil }

        guard let first = ScheduleSkipping.nextRunningStart(of: schedule, modeID: mode.id,
                                                            after: now, skips: skips,
                                                            calendar: calendar) else { return nil }

        if first.addingTimeInterval(-leadTime) > now {
            return ScheduleWarning(modeID: mode.id,
                                   fireAt: first.addingTimeInterval(-leadTime),
                                   windowStart: first)
        }

        // Inside the lead time already: the warning moment for the next window
        // is in the past. Delivering it late — "in ten minutes" when it starts
        // in two — is worse than not delivering it, so that occurrence gets no
        // warning and the answer is the one after it. At most one occurrence
        // can be inside the lead time, because a schedule starts at most once a
        // day and the lead time is minutes.
        guard let second = ScheduleSkipping.nextRunningStart(of: schedule, modeID: mode.id,
                                                             after: first, skips: skips,
                                                             calendar: calendar) else { return nil }
        return ScheduleWarning(modeID: mode.id,
                               fireAt: second.addingTimeInterval(-leadTime),
                               windowStart: second)
    }

    /// The soonest warning owed across every Mode.
    ///
    /// One notification is worth scheduling; seven Modes' worth queued days out
    /// is a schedule of its own, and every one of them is a guess that a
    /// session or a skip can invalidate. The adapter asks again after anything
    /// that could change the answer.
    ///
    /// Ties break on the Mode's id so the answer is stable — an unstable answer
    /// would have the adapter cancelling and re-registering the same
    /// notification on every launch.
    static func next(among modes: [DadMode],
                     now: Date,
                     skips: [ScheduleSkip] = [],
                     isSessionActive: Bool = false,
                     leadTime: TimeInterval = defaultLeadTime,
                     calendar: Calendar = .current) -> ScheduleWarning? {
        modes
            .compactMap {
                next(for: $0, now: now, skips: skips, isSessionActive: isSessionActive,
                     leadTime: leadTime, calendar: calendar)
            }
            .min { ($0.fireAt, $0.modeID.uuidString) < ($1.fireAt, $1.modeID.uuidString) }
    }
}
