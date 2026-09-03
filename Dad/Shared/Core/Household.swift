import Foundation

/// Who is using this phone, and what that lets them do.
///
/// Dad has so far assumed one shape: an adult who chose the Modes, bought the
/// sticker, and is Dadding themselves. Every restriction in the app is
/// therefore self-imposed, and "may I change this?" has never needed asking —
/// the answer was always yes, because there was nobody else in the
/// arrangement.
///
/// The moment a second person is involved — a phone whose Modes were agreed
/// with a parent rather than chosen alone — that stops being true, and the
/// question has to be answered somewhere. This file is that somewhere, and it
/// is in Core rather than in a settings screen for the usual reason: it is a
/// product decision about what a household agreed to, not a detail of how a
/// toggle is drawn. `swift test` can reach it here.
///
/// Nothing in this file touches the shield, the tag or the store. It answers
/// questions; it does not enforce anything. Enforcement is the caller asking
/// before it acts.

// MARK: - Roles

/// The two ways a phone can be running Dad.
///
/// Deliberately two, not a spectrum. A spectrum of roles is how you end up
/// with five half-defined middles that each need their own permission table;
/// the gradient that does exist lives in the autonomy level below, which is a
/// number and behaves like one.
enum HouseholdRole: String, Codable, CaseIterable, Hashable {

    /// An adult running Dad on their own phone. Chose the Modes, holds the
    /// tag, answers to nobody. This is the whole product as shipped today and
    /// remains the default.
    case grownUp

    /// A phone whose Modes were agreed with a grown-up. The arrangement is
    /// between two people, so this phone cannot unilaterally rewrite it — how
    /// much of it this phone *can* change is what the autonomy level decides.
    ///
    /// Note the framing: "agreed with", not "imposed by". A young person who
    /// experiences Dad as something done to them will get around it in an
    /// afternoon — the tag is a sticker, and the App Store is full of other
    /// phones. The ladder exists because the only version of this that
    /// survives contact with a teenager is one where the restrictions shrink
    /// on a schedule they can see.
    case youngPerson

    /// What an unrecognised stored role decodes to.
    ///
    /// A role string this build does not know comes from a newer build — a
    /// TestFlight rollback, a second device on an older version. Both possible
    /// answers are wrong in some way, so the question is which wrongness is
    /// recoverable:
    ///
    /// - Guess `youngPerson` and a solo adult whose stored role got ahead of
    ///   their build finds themselves unable to turn Dad off, unpair the tag
    ///   or edit a Mode, with no grown-up anywhere to ask. That is a bricked
    ///   phone, and the app offers no way out of it.
    /// - Guess `grownUp` and a young person's phone is briefly unrestricted
    ///   until someone notices and sets it back. Which is a conversation, not
    ///   a brick.
    ///
    /// So: fail open on the role, and accept the cost in writing. The autonomy
    /// level goes the other way and fails closed — see `normalisedLevel` — and
    /// the asymmetry is deliberate. An unreadable role tells you nothing at
    /// all. An unreadable level still tells you the phone belongs to a young
    /// person, and the safe number for a young person is the bottom of the
    /// ladder.
    static let fallback: HouseholdRole = .grownUp

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HouseholdRole(rawValue: raw) ?? Self.fallback
    }
}

// MARK: - Capabilities

/// Everything in Dad that one person can do and another may not.
///
/// An explicit closed set, rather than a scatter of `canEditModes` booleans on
/// whatever type happened to need one, because the failure mode of booleans is
/// silence: add a capability, forget one of the eleven places that gate on
/// them, and the new thing is permitted for everybody by default. Nobody sees
/// it until a young person deletes a Mode.
///
/// With a set, the derivation below is a single exhaustive `switch`, so adding
/// a case here does not compile until someone has answered "and who may do
/// this?" — in the one place that question belongs.
enum HouseholdCapability: String, Codable, CaseIterable, Hashable {

    /// Change what a Mode blocks, what it is called, whether it is strict.
    case editMode

    /// Remove a Mode outright.
    ///
    /// Sits at the same rung as `editMode` on purpose. A Mode you can edit is
    /// a Mode you can empty, and an empty Mode blocks nothing — deletion by
    /// another name, minus the row disappearing to make it obvious. Granting
    /// one without the other would be a restriction that reads as a
    /// restriction and isn't one.
    case deleteMode

    /// Change when a Mode runs itself — the recurring window in
    /// `ModeSchedule`.
    case changeSchedule

    /// Change how many emergency Un-Dads the rolling window allows.
    case changeAllowance

    /// Forget the paired tag, or pair a different one.
    ///
    /// The most under-rated item on this list. The product is not the
    /// software, it is the sticker being *in another room*; whoever may pair a
    /// tag may pair one they keep in their pocket, and the whole arrangement
    /// becomes a button on the phone. Ranked accordingly.
    case unpairTag

    /// Spend one of the five overrides in `EmergencyAllowance`.
    case spendEmergencyOverride

    /// Switch Dad off entirely — no Modes, no schedules, no shield.
    case turnDadOff
}

// MARK: - Permissions

/// What a role may do, derived from the role and an autonomy level.
///
/// Derived, never stored. There is no public initialiser and this type is
/// deliberately not `Codable`: a permission set written to disk is a
/// permission set that can disagree with the rules that produced it. That
/// drift is the specific bug this shape exists to prevent — someone raises a
/// level, the stored set is not rewritten because one of four call sites
/// forgot, and the phone keeps enforcing a bargain that was renegotiated
/// weeks ago with nothing on screen to explain why.
///
/// The autonomy level arrives as a parameter rather than living here. *How*
/// a young person climbs the ladder — time served, sessions kept, a parent
/// simply deciding — is a separate question with its own file. This type only
/// answers what a given rung is worth.
struct RolePermissions: Hashable {

    /// The top rung. Also the contract between this file and whatever computes
    /// the level: a ladder that can produce a number above this one will find
    /// it treated as unreadable, not as "even more trusted".
    static let maxAutonomyLevel = 3

    static let autonomyLevels = 0...maxAutonomyLevel

    let allowed: Set<HouseholdCapability>

    private init(allowed: Set<HouseholdCapability>) {
        self.allowed = allowed
    }

    func may(_ capability: HouseholdCapability) -> Bool {
        allowed.contains(capability)
    }

    /// The one way to obtain a `RolePermissions`.
    static func `for`(role: HouseholdRole, autonomyLevel: Int) -> RolePermissions {
        switch role {
        case .grownUp:
            // Every capability, at any level. A grown-up Dadding their own
            // phone is not being governed by anything, so the level they
            // happen to have stored is inert — see `Household.autonomyLevel`
            // for why it is stored at all.
            return RolePermissions(allowed: Set(HouseholdCapability.allCases))

        case .youngPerson:
            let level = normalisedLevel(autonomyLevel)
            let granted = HouseholdCapability.allCases.filter { capability in
                guard let minimum = minimumAutonomyLevel(for: capability) else { return false }
                return level >= minimum
            }
            return RolePermissions(allowed: Set(granted))
        }
    }

    /// The rung at which a young person gains this capability, or `nil` for
    /// one no rung ever grants.
    ///
    /// This is the ladder's rungs, and the single exhaustive switch that makes
    /// a new capability a compile error rather than a silent grant.
    ///
    /// The ordering is not "how annoying is this to lose" — every item below
    /// can be used to undo the arrangement, which is worth saying plainly
    /// because it is easy to design a gradient that isn't one. Emptying a
    /// Mode, shrinking its window to the fifteen-minute floor, raising the
    /// override allowance to a hundred: all of them end with a phone that is
    /// nominally Dadded and blocks nothing. The ordering is instead **how
    /// visible the misuse is to the grown-up who agreed to it**, because a
    /// permission whose abuse shows up in the Modes list the next time
    /// somebody glances at it is a permission you can safely hand over early.
    ///
    /// `nil` rather than a sentinel like `Int.max`: a sentinel invites someone
    /// to conclude the level just needs raising.
    static func minimumAutonomyLevel(for capability: HouseholdCapability) -> Int? {
        switch capability {

        // Level 0 — from the first day, including the first day.
        //
        // The override allowance is a safety valve, not a privilege. A phone
        // that cannot be Un-Dadded at all is a phone that cannot be used to
        // call anyone, and Dad is not willing to be the reason for that. Five
        // per rolling thirty days is already the friction; it restores itself;
        // and every use is countable, so a young person burning through them
        // is a fact a grown-up can see rather than an argument.
        case .spendEmergencyOverride:
            return 0

        // Level 1 — moving the window, not choosing what is in it.
        //
        // Shifting Sleep to start at eleven is the smallest real negotiation
        // there is, and `ModeSchedule.displayText()` prints the result under
        // the Mode: a window quietly whittled to fifteen minutes reads as
        // "22:00–22:15" to anyone who looks at the list.
        case .changeSchedule:
            return 1

        // Level 2 — what is blocked at all.
        //
        // Also visible, via the Mode summary, but a step further: it is the
        // difference between agreeing when the phone goes away and agreeing
        // what "away" means.
        case .editMode, .deleteMode:
            return 2

        // Level 3 — the two that hide.
        //
        // A raised allowance looks like nothing on the Modes list; you find
        // out because the phone was never really away. An unpaired tag is
        // worse — the tag is the product, and a tag paired in a pocket ends
        // the arrangement without changing a single Mode. Top rung, and only
        // because a young person who has spent months at level 2 is, at that
        // point, a person who could simply be trusted with the whole thing.
        case .changeAllowance, .unpairTag:
            return 3

        // Never, at any rung.
        //
        // This is what separates the top of the ladder from being a grown-up,
        // and there is nothing to unlock: the exit from level 3 is the role
        // changing, which is a conversation between two people, not a toggle
        // one of them can reach. A ladder whose last rung is "switch the whole
        // thing off" was never a ladder, and both people know it.
        case .turnDadOff:
            return nil
        }
    }

    /// A level this build can act on.
    ///
    /// Anything outside `autonomyLevels` — negative, or a rung invented by a
    /// build that shipped after this one — collapses to the bottom rather than
    /// to the nearest end. Clamping upwards is the tempting version and it is
    /// wrong: it hands out permissions on the strength of a number nobody in
    /// this build understands. The cost of guessing low is a young person
    /// asking why the schedule went read-only. The cost of guessing high is
    /// permissions nobody agreed to, discovered later.
    static func normalisedLevel(_ level: Int) -> Int {
        autonomyLevels.contains(level) ? level : autonomyLevels.lowerBound
    }
}

// MARK: - Moving the level

/// A proposed move of one phone's autonomy level, and who is proposing it.
///
/// Modelled as a value rather than a bare comparison so the guard has one
/// name and one test. "Only a grown-up may lower a level" is the sentence this
/// exists to make expressible; the rest of the rules fall out of taking that
/// sentence seriously.
struct AutonomyLevelChange: Hashable {

    let current: Int
    let proposed: Int

    init(from current: Int, to proposed: Int) {
        self.current = current
        self.proposed = proposed
    }

    var isNoOp: Bool { proposed == current }
    var isRaising: Bool { proposed > current }
    var isLowering: Bool { proposed < current }

    /// Whether `role` may make this change.
    ///
    /// Three rules, in order:
    ///
    /// 1. A level outside the ladder is refused for everybody, a grown-up
    ///    included. There is no rung 9; writing one would only produce a
    ///    stored number that `normalisedLevel` later reads as 0, which is the
    ///    kind of setting that looks applied and quietly isn't.
    /// 2. A change to the level it already holds is allowed for anybody. A
    ///    settings screen saved without touching the slider must not come back
    ///    as a permission error, and refusing a no-op teaches callers to skip
    ///    the guard.
    /// 3. Otherwise only a grown-up. Not just for lowering — a young person
    ///    cannot raise their own level either, which barely needs arguing, but
    ///    they cannot lower it either, which does: giving up permissions
    ///    voluntarily harms nobody. The reason is that the level is not a
    ///    setting on a phone, it is the written-down half of an agreement
    ///    between two people. A number that can move without the grown-up
    ///    knowing is not a record of anything, and whatever computes the
    ///    ladder would then be reading a rung nobody agreed to — in the
    ///    direction that reads as *progress being lost*, which is worse for
    ///    this product than a slider that says "ask a grown-up".
    func canBeChangedBy(role: HouseholdRole) -> Bool {
        guard RolePermissions.autonomyLevels.contains(proposed) else { return false }
        if isNoOp { return true }
        return role == .grownUp
    }
}

// MARK: - The household

/// One phone's place in a household: the role it is in, and how far up the
/// ladder it has got.
struct Household: Codable, Hashable {

    var role: HouseholdRole

    /// Where this phone sits on the ladder. Only consulted for a
    /// `.youngPerson`.
    ///
    /// Stored even for a grown-up, which is the one value in this file that
    /// currently does nothing — worth defending, because "configured and
    /// inert" is normally the smell this codebase refuses. The alternative is
    /// that the number lives only while the role does, and then handing the
    /// phone to a grown-up for an afternoon erases a rung that took months,
    /// while handing it back invents a fresh one. It is dormant, not
    /// decorative: the moment the role changes back it is exactly the number
    /// the household last agreed on.
    var autonomyLevel: Int

    /// A fresh install: one adult, their own phone, nobody else involved.
    ///
    /// Level 0 rather than the top, even though it is inert here. The day this
    /// phone is handed to a young person, the rung it inherits should be the
    /// bottom one — the ladder is climbed, not granted by an accident of what
    /// the default happened to be.
    static let solo = Household(role: .grownUp, autonomyLevel: 0)

    var permissions: RolePermissions {
        .for(role: role, autonomyLevel: autonomyLevel)
    }

    func may(_ capability: HouseholdCapability) -> Bool {
        permissions.may(capability)
    }

    /// Whether this phone's level may be moved to `proposed` by `actor`.
    ///
    /// `actor` is a parameter rather than assumed to be `role` because the
    /// interesting case is precisely when it isn't: a grown-up standing over
    /// a young person's phone.
    func mayChangeAutonomyLevel(to proposed: Int, by actor: HouseholdRole) -> Bool {
        AutonomyLevelChange(from: autonomyLevel, to: proposed).canBeChangedBy(role: actor)
    }

    /// The household after the move, or `nil` when `actor` may not make it.
    ///
    /// Returns a new value rather than mutating, following
    /// `EmergencyAllowance.consume`: a refused change must be impossible to
    /// half-apply, and a caller that ignores a `nil` is a caller that visibly
    /// did nothing rather than one that silently succeeded.
    func changingAutonomyLevel(to proposed: Int, by actor: HouseholdRole) -> Household? {
        guard mayChangeAutonomyLevel(to: proposed, by: actor) else { return nil }
        return Household(role: role, autonomyLevel: proposed)
    }
}
