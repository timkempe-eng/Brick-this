import Foundation

/// Every user-facing string that carries the product's words lives here.
///
/// The app is **Clover**. The action is **Touch Grass**: physically, because
/// you touch your phone to a tag; and the other way, because the point is to
/// step away from the screen and back into the room you are in.
///
///     "Touch Grass"                 (the action, standing alone — a button)
///     "Tap your Clover tag to touch grass."  (the action, mid-sentence)
///     "You're outside."             (the state)
///     "Come Back In"                (the release)
///
/// The action is an English idiom rather than a coined word, so it follows
/// English: title case where it stands alone as the name of an action, lower
/// case in a sentence. docs/naming.md has the reasoning and the one thing to
/// watch — "go touch grass" is also an insult, so it is said as something you
/// do, never as something you tell someone else to do.
///
/// Keeping the copy in one place means the tone stays consistent across the
/// app, the shield extension, the widgets and the Shortcuts phrases — the
/// shield extension in particular runs in a separate process and cannot
/// reach the app's own strings any other way.
enum Vocab {
    // MARK: The name and the action
    static let appName         = "Clover"
    static let action          = "Touch Grass"
    static let actionInProse   = "touch grass"
    static let actionPast      = "touched grass"
    /// The state, as one word you can read from across the room.
    static let state           = "Outside"
    static let stateInProse    = "outside"
    static let release         = "Come Back In"
    static let releaseInProse  = "come back in"
    /// What you are once you have come back in.
    static let released        = "Back in"
    static let emergencyRelease = "Emergency Exit"

    // MARK: Nouns
    static let tagline       = "Touch grass. Your phone will wait."
    static let modeNoun      = "Mode"
    static let tagNoun       = "Clover tag"
    static let streakNoun    = "grass streak"

    /// A Mode that rations rather than forbids is a qualifier on the state,
    /// not a state of its own: "Outside · rationed".
    static let rationedNoun  = "rationed"

    // MARK: Status copy
    /// The widget gallery's one line under the name. A plain `String` on
    /// purpose: see `DadStatusWidget`.
    static let widgetDescription = "Whether you're \(stateInProse), and for how long."
    static let idleTitle     = "Your phone is free"
    static let idleSubtitle  = "Tap your \(tagNoun) to \(actionInProse)."
    static let activeTitle   = "You're \(stateInProse)"
    static func activeSubtitle(mode: String) -> String {
        "\(mode) · tap your \(tagNoun) again to \(releaseInProse)."
    }

    // MARK: Assistive Access copy
    //
    // A phone in Assistive Access is a phone reduced to large buttons and
    // plain sentences, so the release hint is said without the "·" and without
    // the release's name: "Come Back In" is the product's phrase, and the
    // whole point of the mode is that it does not make you learn one.

    /// The prompt after a tap, on a Mode that asks for the second half of the
    /// gesture. It names the Mode so a notification that arrives a moment late
    /// still makes sense on its own.
    static func assistiveAccessPromptTitle(mode: String) -> String {
        "\(mode) is on."
    }

    /// "Side button (or Home)" rather than either alone: which one it is
    /// depends on the iPhone, Clover cannot tell from here, and a prompt naming
    /// the button somebody does not have is a prompt they conclude is broken.
    ///
    /// It names the passcode because Apple's own wording is that the Assistive
    /// Access passcode "is used to enter or exit" — measured on a phone on
    /// 2026-09-17, where the triple-click asked for the Screen Time passcode
    /// that was already set. So this is a prompt to do something that will ask
    /// for a code, and a prompt that omits that is one somebody follows into a
    /// dead end.
    static func assistiveAccessPromptBody(role: HouseholdRole) -> String {
        switch role {
        case .grownUp:
            // "The", not "your". An adult can be the grown-up of this
            // household and still not hold the passcode — handing it to a
            // spouse on purpose is a guardrail people actually choose, and
            // telling somebody it is theirs is the app being wrong about
            // their own arrangement.
            return "Triple-click the side button (or Home) for Assistive Access. "
                + "It asks for the Screen Time passcode."
        case .youngPerson:
            // The same failure `refusal(_:)` exists to prevent: an instruction
            // this phone cannot carry out alone, given with no subject. A young
            // person who triple-clicks, meets a passcode they do not have and is
            // told nothing concludes the app is broken — and an app they think
            // is broken is one they route around.
            return "Assistive Access needs a grown-up's passcode. "
                + "Hand them the phone and triple-click the side button (or Home) together."
        }
    }

    /// Shown inside Assistive Access, where the tag alone may not be enough.
    /// Names the order, because the half that has to happen first is the one
    /// nobody guesses: leaving Assistive Access needs its passcode, and no
    /// amount of tapping substitutes for it.
    static let assistiveAccessExitHint =
        "Triple-click the side button (or Home) to leave Assistive Access, then tap your \(tagNoun)."

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
            return "\(emergencyRelease) isn't available on this phone yet."
        case .turnDadOff:
            return "Turning \(appName) off isn't something either of you can do from here."
        }
    }

    // MARK: Authorization
    static let authorizationDeclined =
        "Screen Time access was declined. \(appName) can't hide apps without it."

    /// Said separately from a plain decline on purpose. Sending somebody to
    /// Screen Time settings when the actual problem is that this phone is not
    /// in an iCloud Family wastes an evening, and the two failures are
    /// indistinguishable from the error alone.
    static let childAuthorizationFailed =
        "\(appName) couldn't set this up as a young person's phone. Apple only allows that "
        + "when the phone is signed into a child account inside an iCloud Family — check "
        + "Settings › Family. You can also set this phone to \"Mine\" for now; everything "
        + "works, but it can be switched off from here."

    // MARK: Setup

    /// Asked before the permission, because the answer decides which
    /// permission is requested — and said in full, because the second choice
    /// only works on a phone inside an iCloud Family and finding that out
    /// from an error after the prompt is the worst place to learn it.
    static func roleExplanation(_ role: HouseholdRole) -> String {
        switch role {
        case .grownUp:
            return "You set it up and you're in charge. You can switch \(appName) off "
                + "in Settings whenever you like."
        case .youngPerson:
            return "Set up together with a grown-up, and it can't be switched off from "
                + "this phone alone. Apple only allows this on a phone signed into a "
                + "child account in an iCloud Family."
        }
    }

    static let setupTitle = "Finish setting up"

    static func setupStepTitle(_ step: SetupChecklist.Step) -> String {
        switch step {
        case .chooseApps: return "Choose what to hide"
        case .pairTag:    return "Pair your \(tagNoun)"
        case .tryIt:      return "Try it"
        }
    }

    static func setupStepDetail(_ step: SetupChecklist.Step) -> String {
        switch step {
        case .chooseApps:
            return "Start small — three or four apps you actually lose time to."
        case .pairTag:
            return "An NTAG215 sticker is ideal. Until you pair one, any tag your phone can read will work."
        case .tryIt:
            return "Tap your \(tagNoun) to \(actionInProse), then open one of the apps you hid."
        }
    }

    /// `nil` for trying it: the home screen's own button already does that,
    /// and a second one saying the same thing is a question about which.
    static func setupStepAction(_ step: SetupChecklist.Step) -> String? {
        switch step {
        case .chooseApps: return "Choose apps"
        case .pairTag:    return "Pair a tag"
        case .tryIt:      return nil
        }
    }

    /// Shown once every derived step is done. Both are advice the app cannot
    /// see taken, so this card is the one part of setup a person dismisses.
    static let setupFinishingTitle = "Two last things"
    static let setupShortcutsTip =
        "So a tap works with \(appName) closed: Shortcuts › Automation › NFC › scan your "
        + "tag › add the “\(action)” action, and turn Ask Before Running off."
    static let setupPlacementTip =
        "Put the tag somewhere a little out of the way — a drawer in another room. "
        + "One on your desk is too easy to reach for."
    static let setupDoneAction = "Done"

    /// What a tap says when no Mode hides anything yet. A "which Mode?"
    /// question with nothing to pick is the dead end this replaces.
    static let nothingToHideYet =
        "Nothing to hide yet. Choose some apps for a \(modeNoun.lowercased()) first."

    // MARK: The warning before a scheduled Mode

    /// "Sleep sends you outside at 22:00 — 10 minutes."
    ///
    /// The whole answer to the most-repeated complaint about scheduled
    /// blockers: one that lands mid-sentence is the one that gets switched off.
    /// It names the Mode, the time and how long you have, and it asks for
    /// nothing — a warning with a "postpone" button is a schedule you did not
    /// agree to.
    static func warning(mode: String, at time: String, minutes: Int) -> String {
        "\(mode) sends you \(stateInProse) at \(time) — \(minutes) minute\(minutes == 1 ? "" : "s")."
    }

    // MARK: Asking, and granting
    static let askAction = "Ask for a few minutes"
    static func asking(mode: String) -> String {
        "Waiting on a grown-up. Hand them the phone, or take the ask back."
    }
    static func granted(mode: String, minutes: Int) -> String {
        "\(minutes) minutes. \(mode) comes back on its own — nobody has to remember."
    }

    // MARK: Break copy — a session released by hand that comes back on its own
    static let breakNoun = "break"
    static func breakRunning(mode: String, until: Date) -> String {
        "\(mode) comes back at \(until.formatted(date: .omitted, time: .shortened))."
    }
    /// What a tag starts, in a line: "Deep Work", "Deep Work or Meetings",
    /// "Deep Work, Meetings or Focus". `nil` for none, so a caller says what
    /// a tag with no Mode does in its own words rather than showing "".
    static func tagStarts(_ modeNames: [String]) -> String? {
        guard let last = modeNames.last else { return nil }
        let rest = modeNames.dropLast()
        return rest.isEmpty ? last : "\(rest.joined(separator: ", ")) or \(last)"
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
    static let shieldTitle   = "\(activeTitle)."
    static func shieldSubtitle(mode: String) -> String {
        "You \(actionPast) for \(mode). Tap your \(tagNoun) when you're ready to \(releaseInProse)."
    }
    /// The shield you meet after using up a rationed Mode's minutes. Different
    /// from the one above on purpose: nothing was taken away when you started,
    /// so "you touched grass" would read as a non-sequitur.
    static func shieldSubtitleAllowanceSpent(mode: String) -> String {
        "Your \(mode) allowance is gone for today. Tap your \(tagNoun) to \(releaseInProse), or wait for tomorrow."
    }
    static let shieldPrimaryButton   = "OK"
    static let shieldSecondaryButton = emergencyRelease

    /// Past-tense sentence for a finished session, e.g.
    /// "You were outside for 1h 42m."
    static func sessionSummary(duration: String) -> String {
        "You were \(stateInProse) for \(duration)."
    }
}
