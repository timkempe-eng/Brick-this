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

    // MARK: Allowance copy
    static func allowanceRunning(mode: String, minutes: Int) -> String {
        "\(mode) · \(minutes) minutes of those apps today, then they go."
    }
    static func allowanceSpent(mode: String, minutes: Int) -> String {
        "\(mode) · your \(minutes) minutes are gone until tomorrow."
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
