import Foundation

/// Every user-facing string that carries the verb lives here.
///
/// The product verb is **Tim**. It conjugates like any other one-syllable
/// consonant-vowel-consonant verb, so the final `m` doubles before a vowel
/// suffix: Tim / Tims / Timming / Timmed.
///
///     "Tim your phone."            (imperative)
///     "I Timmed my phone at 9am."  (past)
///     "Your phone is Timmed."      (state)
///     "Stop Timming and answer me." (gerund, affectionate)
///     "Un-Tim"                      (release)
///
/// Keeping the copy in one place means the tone stays consistent across the
/// app, the shield extension, the widgets and the Shortcuts phrases — the
/// shield extension in particular runs in a separate process and cannot
/// reach the app's own strings any other way.
enum Vocab {
    // MARK: Core verb forms
    static let verb          = "Tim"
    static let verbThirdPerson = "Tims"
    static let verbPast      = "Timmed"
    static let verbGerund    = "Timming"
    static let unVerb        = "Un-Tim"
    static let unVerbPast    = "Un-Timmed"

    // MARK: Nouns
    static let appName       = "Tim"
    static let tagline       = "Tim your phone. Get your day back."
    static let modeNoun      = "Mode"
    static let sessionNoun   = "Tim session"
    static let tagNoun       = "Tim tag"
    static let streakNoun    = "Tim streak"

    // MARK: Status copy
    static let idleTitle     = "Your phone is free"
    static let idleSubtitle  = "Tap your \(tagNoun) to Tim it."
    static let activeTitle   = "Your phone is \(verbPast)"
    static func activeSubtitle(mode: String) -> String {
        "\(mode) · tap your \(tagNoun) again to \(unVerb.lowercased())."
    }

    // MARK: Shield copy — what you see when you open a blocked app
    static let shieldTitle   = "\(verbPast)."
    static func shieldSubtitle(mode: String) -> String {
        "You Timmed your phone for \(mode). Tap your \(tagNoun) when you're ready to come back."
    }
    static let shieldPrimaryButton   = "OK"
    static let shieldSecondaryButton = "Emergency \(unVerb)"

    // MARK: Actions
    static let timAction     = "\(verb) my phone"
    static let unTimAction   = "\(unVerb) my phone"
    static let emergencyUnTim = "Emergency \(unVerb)"

    /// Past-tense sentence for a finished session, e.g.
    /// "You were Timmed for 1h 42m."
    static func sessionSummary(duration: String) -> String {
        "You were \(verbPast) for \(duration)."
    }
}
