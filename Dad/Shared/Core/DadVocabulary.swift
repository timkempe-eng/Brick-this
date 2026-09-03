import Foundation

/// Every user-facing string that carries the verb lives here.
///
/// The product verb is **Dad**. It conjugates like any other one-syllable
/// consonant-vowel-consonant verb, so the final `d` doubles before a vowel
/// suffix: Dad / Dads / Dadding / Dadded.
///
///     "Dad your phone."            (imperative)
///     "I Dadded my phone at 9am."  (past)
///     "Your phone is Dadded."      (state)
///     "Stop Dadding and answer me." (gerund, affectionate)
///     "Un-Dad"                      (release)
///
/// Keeping the copy in one place means the tone stays consistent across the
/// app, the shield extension, the widgets and the Shortcuts phrases — the
/// shield extension in particular runs in a separate process and cannot
/// reach the app's own strings any other way.
enum Vocab {
    // MARK: Core verb forms
    static let verb          = "Dad"
    static let verbThirdPerson = "Dads"
    static let verbPast      = "Dadded"
    static let verbGerund    = "Dadding"
    static let unVerb        = "Un-Dad"
    static let unVerbPast    = "Un-Dadded"

    // MARK: Nouns
    static let appName       = "Dad"
    static let tagline       = "Dad your phone. Get your day back."
    static let modeNoun      = "Mode"
    static let sessionNoun   = "Dad session"
    static let tagNoun       = "Dad tag"
    static let streakNoun    = "Dad streak"

    /// A Mode that rations rather than forbids is *not* a form of the verb, so
    /// it is an ordinary lowercase word — the same exemption `modeNoun` has.
    /// "Dadded · rationed" reads as one state with a qualifier, which is what
    /// it is.
    static let rationedNoun  = "rationed"

    // MARK: Status copy
    static let idleTitle     = "Your phone is free"
    static let idleSubtitle  = "Tap your \(tagNoun) to Dad it."
    static let activeTitle   = "Your phone is \(verbPast)"
    static func activeSubtitle(mode: String) -> String {
        "\(mode) · tap your \(tagNoun) again to \(unVerb)."
    }

    // MARK: Household copy
    //
    // A refusal has to name what was refused and who can undo it. "Not
    // allowed" with no subject is how a young person concludes the app is
    // broken, and an app they think is broken is one they route around.
    static func refusal(_ capability: HouseholdCapability) -> String {
        switch capability {
        case .editMode:
            return "Changing a \(modeNoun.lowercased()) is part of the arrangement — ask whoever you set this up with."
        case .deleteMode:
            return "Deleting a \(modeNoun.lowercased()) needs the grown-up who set this up."
        case .changeSchedule:
            return "The schedule was agreed together. Changing it needs both of you."
        case .changeAllowance:
            return "The allowance was agreed together. Changing it needs both of you."
        case .unpairTag:
            return "Un-pairing the \(tagNoun) would end the arrangement, so it isn't yours alone to do."
        case .spendEmergencyOverride:
            return "Emergency \(unVerb) isn't available on this phone yet."
        case .turnDadOff:
            return "Turning \(appName) off isn't something either of you can do from here."
        }
    }

    // MARK: Break copy — a session released by hand that comes back on its own
    static let breakNoun = "break"
    static func breakRunning(mode: String, until: Date) -> String {
        "\(mode) comes back at \(until.formatted(date: .omitted, time: .shortened))."
    }
    static func breakCancelled(mode: String) -> String {
        "\(breakNoun.capitalized) called off. \(mode) won't come back on its own."
    }
    static let breakTapHint = "Tap your \(tagNoun) again to call the break off."
    static let breakTitle = "You're on a \(breakNoun)"
    static let breakCancelAction = "Call off the \(breakNoun)"

    // MARK: Allowance copy
    static func allowanceRunning(mode: String, minutes: Int) -> String {
        "\(mode) · \(minutes) minutes of those apps today, then they go."
    }
    static func allowanceSpent(mode: String, minutes: Int) -> String {
        "\(mode) · your \(minutes) minutes are gone until tomorrow."
    }
    /// Starting a session on a Mode whose day is already spent. Said plainly,
    /// because nothing visibly happened when they tapped and the apps went.
    static func allowanceAlreadySpent(mode: String, minutes: Int) -> String {
        "\(mode) · you already used today's \(minutes) minutes, so the apps are hidden."
    }
    /// The system refused to count usage, so the apps were taken away instead.
    /// Said plainly, because the user was promised minutes and did not get them.
    static let allowanceRefused =
        "The system wouldn't count your app use, so \(appName) hid the apps instead of rationing them."

    // MARK: Shield copy — what you see when you open a blocked app
    static let shieldTitle   = "\(verbPast)."
    static func shieldSubtitle(mode: String) -> String {
        "You Dadded your phone for \(mode). Tap your \(tagNoun) when you're ready to come back."
    }
    /// The shield you meet after using up a rationed Mode's minutes. Different
    /// from the one above on purpose: nothing was taken away when you started,
    /// so "you Dadded your phone" would read as a non-sequitur.
    static func shieldSubtitleAllowanceSpent(mode: String) -> String {
        "Your \(mode) allowance is gone for today. Tap your \(tagNoun) to \(unVerb), or come back tomorrow."
    }
    static let shieldPrimaryButton   = "OK"
    static let shieldSecondaryButton = "Emergency \(unVerb)"

    // MARK: Actions
    static let dadAction     = "\(verb) my phone"
    static let unDadAction   = "\(unVerb) my phone"
    static let emergencyUnDad = "Emergency \(unVerb)"

    /// Past-tense sentence for a finished session, e.g.
    /// "You were Dadded for 1h 42m."
    static func sessionSummary(duration: String) -> String {
        "You were \(verbPast) for \(duration)."
    }
}
