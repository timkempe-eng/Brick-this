import Foundation

/// Earned autonomy: consistency buys **control over your own phone**, and
/// never a single minute of screen time.
///
/// That sentence is the whole design, and the second half of it is the part
/// that took research to arrive at. A whole category of apps — ScreenCoach,
/// Chore Champ, EarnIt — lets chores buy minutes, and child-development
/// researchers keep finding the same backfire: once screens are the thing
/// worth working for, cooperation turns into negotiation, and the household
/// has invented a currency it now has to defend. Dad escapes that trap by a
/// hair, because here the good decision *is* the habit — you Dad your phone,
/// and what you get back for doing it repeatedly is self-determination:
/// setting your own Sleep window, editing your own Modes, eventually holding
/// the tag yourself.
///
/// **Earned minutes are the one currency Dad must not mint.** If a future rung
/// ever unlocks "30 more minutes" the product has quietly become the thing it
/// was built to replace, and no test will catch that — so it is written down
/// here, at the top, where the next person adding a rung will read it.
///
/// Everything below is derived from the session history. Nothing is stored:
/// a level that lives in a file is a level that can drift from the behaviour
/// that earned it, can be edited by whoever can reach the file, and has to be
/// migrated. Deriving it means the ladder can be recomputed from scratch on
/// any device that has the history and always agrees.
struct AutonomyLadder {

    let sessions: [DadSession]
    let calendar: Calendar
    let now: Date

    /// - Parameter calendar: injected for exactly the reason `DadStats`
    ///   injects it. Every number here is a count of *days*, and which instant
    ///   falls in which day is a property of the user's time zone rather than
    ///   of the code. Tests pin UTC so a runner in another zone can't shift a
    ///   boundary under them; the app passes `.current`, which is what the
    ///   household's days actually are.
    init(sessions: [DadSession], now: Date = Date(), calendar: Calendar = .current) {
        // Only finished sessions count, as in `DadStats`. An in-flight session
        // has no outcome yet — we cannot know whether it will end at the tag
        // or on the emergency button — so counting it would let a level appear
        // mid-session and vanish again when it ended badly.
        self.sessions = sessions.filter { $0.endedAt != nil }
        self.calendar = calendar
        self.now = now
    }

    // MARK: - Tunables
    //
    // Named constants rather than literals because each one is a household
    // policy someone will want to argue about, and an argument is easier when
    // the number has a name.

    /// Days with no Dad session at all before one rung is set aside.
    ///
    /// A fortnight, deliberately. One bad night must cost nothing: a level
    /// that evaporates overnight is the single fastest way to make a teenager
    /// stop caring about the ladder, and a ladder nobody cares about is worse
    /// than no ladder, because the parent is still relying on it.
    static let lapseGrace = 14

    /// Clean days that bring one set-aside rung back.
    ///
    /// Losing is slow and regaining is fast, on purpose. The asymmetry is the
    /// difference between a ladder and a punishment: the fortnight exists to
    /// stop a rung being lost by accident, not to make the climb back long
    /// enough to be worth abandoning.
    static let restoreDays = 3

    /// How many days before a loss the app can warn.
    ///
    /// A rung that disappears with no warning is indistinguishable from a bug,
    /// and will be reported as one. `demotionWarning` exists so the app can
    /// say it out loud first.
    static let warningLead = 3

    // MARK: - The rungs

    /// The ladder itself. `rawValue` is the autonomy level, so
    /// `RolePermissions.for(role:autonomyLevel:)` and anything else that has
    /// only an `Int` can still ask the right question.
    ///
    /// Ordered, and the requirements below increase monotonically at every
    /// step, which is what lets `earnedRung` stop at the first unmet rung —
    /// you cannot skip one by being spectacular at the criterion the next rung
    /// happens to weight.
    enum Rung: Int, CaseIterable, Comparable {
        /// Where everyone starts. Not a null state: you can already Dad and
        /// Un-Dad your own phone and see your own history, which is more than
        /// most parental-control products give the person being controlled.
        case gettingStarted = 0

        /// The apps inside a Mode are yours to change.
        case trusted = 1

        /// Your Sleep window is yours to set, inside the range a parent chose.
        case selfScheduling = 2

        /// Make and name your own Modes, and a wider emergency allowance.
        case selfGoverning = 3

        /// The tag lives in your room. You decide where it goes.
        case keeperOfTheTag = 4

        static func < (lhs: Rung, rhs: Rung) -> Bool { lhs.rawValue < rhs.rawValue }

        /// Clamps rather than failing, so a level that arrives from storage
        /// written by a newer build — one that has a fifth rung — reads as the
        /// top rung this build knows about instead of returning nil and
        /// silently collapsing the user to zero.
        init(autonomyLevel: Int) {
            // Deliberately the *same* normalisation `RolePermissions` uses,
            // rather than a clamp of its own. These two files answer the same
            // question — what does this stored number mean — and when they
            // answered it differently, a level written by a newer build
            // displayed "Keeper of the \(Vocab.tagNoun)" while granting no
            // capability at all. Clamping up here reads generously and is the
            // tempting version; failing closed in both places, with the
            // store's existing newer-build banner to explain it, is the honest
            // one.
            self = Rung(rawValue: RolePermissions.normalisedLevel(autonomyLevel)) ?? .gettingStarted
        }

        var title: String {
            switch self {
            case .gettingStarted: return "Getting started"
            case .trusted:        return "Trusted"
            case .selfScheduling: return "Self-scheduling"
            case .selfGoverning:  return "Self-governing"
            case .keeperOfTheTag: return "Keeper of the \(Vocab.tagNoun)"
            }
        }

        /// What this rung newly grants, in the words the app shows.
        ///
        /// Copy, for the screen. Anything that has to *branch* on a capability
        /// reads the booleans below instead — a caller that string-matches on
        /// this list breaks the first time the copy is edited.
        var unlocks: [String] {
            switch self {
            case .gettingStarted:
                return ["\(Vocab.verb) and \(Vocab.unVerb) your phone whenever you want",
                        "See your own history and \(Vocab.streakNoun)"]
            case .trusted:
                return ["Choose which apps each \(Vocab.modeNoun) takes away"]
            case .selfScheduling:
                return ["Set your own Sleep window, inside the range a parent chose"]
            case .selfGoverning:
                return ["Make and name your own \(Vocab.modeNoun)s",
                        "A wider emergency \(Vocab.unVerb) allowance"]
            case .keeperOfTheTag:
                return ["The \(Vocab.tagNoun) lives in your room"]
            }
        }

        // MARK: Capabilities
        //
        // Each is `rawValue >= n`, so a rung inherits everything below it. A
        // capability that switched off again higher up the ladder would be a
        // reward for consistency that took something away.

        /// Change which apps an existing Mode blocks, without a parent
        /// approving each edit.
        var canEditModeApps: Bool { rawValue >= Rung.trusted.rawValue }

        /// Set your own Sleep window. The *range* it must sit inside stays a
        /// parent's decision at every rung — this unlocks choosing within it,
        /// not abolishing it.
        var canSetOwnSleepWindow: Bool { rawValue >= Rung.selfScheduling.rawValue }

        /// Create and name new Modes, rather than only editing the ones you
        /// were given.
        var canCreateModes: Bool { rawValue >= Rung.selfGoverning.rawValue }

        /// The tag is yours to keep and to move.
        var keepsTheTag: Bool { rawValue >= Rung.keeperOfTheTag.rawValue }

        /// Emergency overrides on top of `EmergencyAllowance.perWindow`.
        ///
        /// This is the one unlock that sits anywhere near the forbidden
        /// currency, so it is worth being explicit about why it isn't one. An
        /// override is a hatch you can already reach; the limit exists to make
        /// you notice you are reaching for it. Widening it says "you have
        /// shown you don't reach for it lightly" — it is not awarded per good
        /// deed, cannot be accumulated, and cannot be spent on a specific app
        /// for a specific number of minutes. If any of those three ever stops
        /// being true, this has become minted screen time and must be removed.
        var extraEmergencyOverrides: Int {
            switch self {
            case .gettingStarted, .trusted, .selfScheduling: return 0
            case .selfGoverning: return 2
            case .keeperOfTheTag: return 3
            }
        }

        /// Overrides per rolling window at this rung. Reads the base from
        /// `EmergencyAllowance` rather than restating it, so the two can never
        /// disagree about what "five" means.
        var emergencyAllowance: Int {
            EmergencyAllowance.perWindow + extraEmergencyOverrides
        }

        /// What the rung costs, as numbers.
        ///
        /// Legibility is a design requirement, not a nicety: a reward you
        /// cannot predict is not an incentive, it is a surprise. Because this
        /// is data rather than prose, the app can show "4 more clean days and
        /// a 7-day run" before the rung is reached, and show the same numbers
        /// the code is actually testing.
        var requirement: Requirement {
            switch self {
            case .gettingStarted: return Requirement(cleanDays: 0,  cleanStreak: 0)
            case .trusted:        return Requirement(cleanDays: 5,  cleanStreak: 3)
            case .selfScheduling: return Requirement(cleanDays: 15, cleanStreak: 7)
            case .selfGoverning:  return Requirement(cleanDays: 30, cleanStreak: 14)
            case .keeperOfTheTag: return Requirement(cleanDays: 60, cleanStreak: 30)
            }
        }
    }

    /// Both criteria must be met. Two of them rather than one because either
    /// alone is gameable in a way that isn't the habit: a total alone rewards
    /// one heroic fortnight and then nothing, and a streak alone rewards a
    /// month of thirty-second sessions.
    struct Requirement: Equatable {
        /// Days on which at least one session was finished at the tag.
        let cleanDays: Int
        /// The longest run of consecutive such days — ever, not currently.
        let cleanStreak: Int
    }

    /// "What am I on, what's next, and exactly what do I still need."
    struct Progress: Equatable {
        let rung: Rung
        let requirement: Requirement
        let cleanDays: Int
        let cleanStreak: Int

        var cleanDaysRemaining: Int { max(0, requirement.cleanDays - cleanDays) }
        var cleanStreakRemaining: Int { max(0, requirement.cleanStreak - cleanStreak) }
        var isMet: Bool { cleanDaysRemaining == 0 && cleanStreakRemaining == 0 }

        /// 0...1 for a progress bar, and deliberately the *minimum* of the two
        /// ratios rather than their average. Averaging would draw a bar at 50%
        /// for someone who has thirty clean days and has never strung two
        /// together, which reads as nearly-there when in fact nothing about
        /// the binding constraint has moved.
        var fraction: Double {
            func ratio(_ have: Int, _ need: Int) -> Double {
                guard need > 0 else { return 1 }
                return min(1, Double(have) / Double(need))
            }
            return min(ratio(cleanDays, requirement.cleanDays),
                       ratio(cleanStreak, requirement.cleanStreak))
        }
    }

    // MARK: - The days underneath it
    //
    // Two day sets, and the difference between them is a decision rather than
    // bookkeeping.
    //
    // A session counts toward the day it *started*, exactly as in `DadStats`:
    // an evening that runs past midnight credits the evening you began it,
    // because that is how anyone would describe it out loud.

    /// Any day you Dadded at all, however it ended. This is what stops the
    /// lapse clock — bailing out with an override is still engagement, and
    /// must never be the thing that costs a rung.
    private var activeDays: Set<Date> {
        Set(sessions.map { calendar.startOfDay(for: $0.startedAt) })
    }

    /// Days with at least one session finished by walking back to the tag.
    /// One clean finish makes the day clean even if another session that day
    /// ended on the emergency button: the day contains the evidence.
    private var cleanDays: Set<Date> {
        Set(sessions.filter { !$0.endedByEmergency }
                    .map { calendar.startOfDay(for: $0.startedAt) })
    }

    /// Total clean days in the whole history.
    var cleanDayCount: Int { cleanDays.count }

    /// The longest run of consecutive clean days, ever.
    ///
    /// The requirements read this rather than the current streak, and that is
    /// the single most important line in the file. A rung gated on the
    /// *current* streak would be lost the first night you skipped — the silent
    /// drop this type exists to make impossible. A high-water mark can only
    /// ever go up, so no amount of future history, and no passage of time, can
    /// take an earned rung away.
    var longestCleanStreak: Int {
        let days = cleanDays.sorted()
        guard !days.isEmpty else { return 0 }

        var longest = 1
        var running = 1
        for (previous, day) in zip(days, days.dropFirst()) {
            if calendar.dateComponents([.day], from: previous, to: day).day == 1 {
                running += 1
                longest = max(longest, running)
            } else {
                running = 1
            }
        }
        return longest
    }

    /// The live run of clean days, for display only. Today not having one yet
    /// does not break it — the day isn't over — which is the same rule
    /// `DadStats.currentStreak` follows.
    var currentCleanStreak: Int {
        let days = cleanDays
        guard !days.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }

        var cursor: Date
        if days.contains(today) {
            cursor = today
        } else if days.contains(yesterday) {
            cursor = yesterday
        } else {
            return 0
        }

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// Whole days since the last day you Dadded at all. `nil` when you never
    /// have — you cannot lapse from a habit you have not started.
    var daysSinceLastSession: Int? {
        guard let last = activeDays.max() else { return nil }
        let today = calendar.startOfDay(for: now)
        let gap = calendar.dateComponents([.day], from: last, to: today).day ?? 0
        // Clamped: a session dated in the future (a clock that moved
        // backwards, a restored backup) would otherwise read as a negative
        // lapse and hand out rungs.
        return max(0, gap)
    }

    // MARK: - Earning
    //
    // Note what this half of the file does not touch: `now`. Earning is a
    // function of the history alone, so the clock ticking cannot promote or
    // demote anyone. Only `withheldRungs` below looks at the time, and it is
    // the only thing in the type that can lower a level.

    func progress(toward rung: Rung) -> Progress {
        Progress(rung: rung,
                 requirement: rung.requirement,
                 cleanDays: cleanDayCount,
                 cleanStreak: longestCleanStreak)
    }

    /// The highest rung the history has paid for, before any lapse is applied.
    ///
    /// Stops at the first unmet rung rather than taking the highest rung whose
    /// requirement happens to be satisfied, so the ladder is climbed one rung
    /// at a time even if a future rung is ever mis-specified as easier than
    /// the one below it.
    var earnedRung: Rung {
        var earned = Rung.gettingStarted
        for rung in Rung.allCases.dropFirst() {
            guard progress(toward: rung).isMet else { break }
            earned = rung
        }
        return earned
    }

    // MARK: - Demotion, modelled out loud
    //
    // A rung can be lost. Pretending otherwise would be dishonest — a ladder
    // that only ever goes up stops meaning anything the first time the habit
    // stops. But it is lost in exactly one way, and that way is slow, visible
    // in advance, and reversible:
    //
    //   * only a *lapse* costs a rung — `lapseGrace` whole days with no Dad
    //     session at all. Not a bad night, not an emergency override, not a
    //     short session, not a missed streak.
    //   * one rung per lapse period, so a month away costs two, not everything.
    //   * `demotionWarning` reports it `warningLead` days before it happens.
    //   * `restoreDays` clean days bring one back.

    /// Rungs set aside by the lapse you are in right now.
    private var rungsWithheldByCurrentLapse: Int {
        guard let lapsed = daysSinceLastSession else { return 0 }
        return lapsed / AutonomyLadder.lapseGrace
    }

    /// The last lapse that has already ended: how long it was, and the day you
    /// came back. `nil` when the history has no completed lapse in it.
    private var lastCompletedLapse: (length: Int, resumedOn: Date)? {
        let days = activeDays.sorted()
        guard days.count >= 2 else { return nil }

        var found: (length: Int, resumedOn: Date)?
        for (previous, day) in zip(days, days.dropFirst()) {
            let gap = calendar.dateComponents([.day], from: previous, to: day).day ?? 0
            if gap >= AutonomyLadder.lapseGrace {
                found = (gap, day)
            }
        }
        return found
    }

    /// Clean days accumulated since the last completed lapse ended, counting
    /// the day you came back.
    private var cleanDaysSinceLastLapse: Int {
        guard let lapse = lastCompletedLapse else { return 0 }
        return cleanDays.filter { $0 >= lapse.resumedOn }.count
    }

    /// Rungs still owed from the last completed lapse, after crediting the
    /// rebuilding done since.
    private var rungsWithheldAfterLastLapse: Int {
        guard let lapse = lastCompletedLapse else { return 0 }
        let cost = lapse.length / AutonomyLadder.lapseGrace
        let restored = cleanDaysSinceLastLapse / AutonomyLadder.restoreDays
        return max(0, cost - restored)
    }

    /// How many rungs are currently set aside.
    ///
    /// The larger of the two rather than their sum: someone who lapsed, came
    /// back for a week and lapsed again is in one hole, not two, and adding
    /// them would let a history of ordinary gaps compound into a demotion
    /// nobody could account for.
    var withheldRungs: Int {
        min(earnedRung.rawValue,
            max(rungsWithheldByCurrentLapse, rungsWithheldAfterLastLapse))
    }

    /// True when the level on show is lower than the one that was earned —
    /// the app should be saying why.
    var isWithheld: Bool { withheldRungs > 0 }

    // MARK: - What the app reads

    /// The rung in force right now.
    var rung: Rung { Rung(autonomyLevel: earnedRung.rawValue - withheldRungs) }

    /// The same thing as an `Int`, for `RolePermissions.for(role:autonomyLevel:)`
    /// and anything else that shouldn't have to know the enum.
    var level: Int { rung.rawValue }

    /// The rung being climbed toward, or `nil` at the top of the ladder.
    ///
    /// Deliberately the next rung above the *earned* one while nothing is
    /// withheld, and the next one to be *restored* while something is: being
    /// told to go and earn a rung you already earned, because you were away
    /// for a fortnight, is the moment people decide the ladder is arbitrary.
    var nextRung: Rung? {
        if isWithheld { return Rung(autonomyLevel: rung.rawValue + 1) }
        guard earnedRung.rawValue + 1 < Rung.allCases.count else { return nil }
        return Rung(autonomyLevel: earnedRung.rawValue + 1)
    }

    /// Exactly what is still outstanding for `nextRung`, as numbers.
    ///
    /// While a rung is withheld this reports `isMet` — the history did buy
    /// that rung, and saying otherwise would be a lie the user can check
    /// against their own streak. What is outstanding in that case is not
    /// earning but showing up, which is `cleanDaysUntilARungIsRestored`. So
    /// the screen reads `demotionWarning` first and falls through to this only
    /// when it is `.none`.
    var progressToNextRung: Progress? {
        guard let next = nextRung else { return nil }
        return progress(toward: next)
    }

    /// Clean days until one withheld rung comes back, or `nil` when nothing is
    /// withheld.
    ///
    /// While the lapse is still running the answer is the full `restoreDays`:
    /// the count cannot start until you Dad your phone again, and reporting a
    /// part-built total during a lapse would tick downward while the situation
    /// was getting worse.
    var cleanDaysUntilARungIsRestored: Int? {
        guard isWithheld else { return nil }
        guard rungsWithheldByCurrentLapse == 0 else { return AutonomyLadder.restoreDays }
        let built = cleanDaysSinceLastLapse % AutonomyLadder.restoreDays
        return AutonomyLadder.restoreDays - built
    }

    /// What the app should say before a rung goes, rather than after.
    enum DemotionWarning: Equatable {
        /// Nothing is at risk and nothing is set aside.
        case none
        /// `rung` will be set aside in `inDays` days unless the phone is
        /// Dadded before then.
        case approaching(rung: Rung, inDays: Int)
        /// `rung` is already set aside; `cleanDays` clean days bring it back.
        case withheld(rung: Rung, cleanDays: Int)
    }

    /// Reportable, because a level that changed with no warning is
    /// indistinguishable from a bug and will be reported as one.
    var demotionWarning: DemotionWarning {
        if isWithheld {
            // The rung you no longer have is the one directly above the one
            // you're standing on.
            let lost = Rung(autonomyLevel: rung.rawValue + 1)
            return .withheld(rung: lost, cleanDays: cleanDaysUntilARungIsRestored ?? 0)
        }

        // Nothing to lose at the bottom of the ladder, and nothing to lose
        // before you have started.
        guard rung > .gettingStarted, let lapsed = daysSinceLastSession else { return .none }

        let untilNext = AutonomyLadder.lapseGrace - (lapsed % AutonomyLadder.lapseGrace)
        guard untilNext <= AutonomyLadder.warningLead else { return .none }
        return .approaching(rung: rung, inDays: untilNext)
    }
}
