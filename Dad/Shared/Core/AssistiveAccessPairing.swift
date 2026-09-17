import Foundation

/// Pairing a tag tap with the triple-click that enters Assistive Access.
///
/// Dad cannot switch Assistive Access on — nothing can, see
/// [ADR 008](../../../docs/adr/008-assistive-access.md). What it can do is ask
/// the person holding the phone to finish the job, at the one moment they are
/// certainly holding it: the second after they tapped the tag.
///
/// So the gesture is two halves. The tag takes the apps away, and a triple-click
/// takes the phone's whole interface down to a few large buttons. Neither half
/// needs the other to be useful, which is why this is per Mode and off by
/// default: Sleep wants both, and Gym does not.
///
/// **The way back is the same two halves in reverse**, and that asymmetry is
/// the thing most likely to strand somebody. Leaving Assistive Access needs its
/// passcode, which Dad neither knows nor can ask for, so a person in Assistive
/// Access cannot be released by anything Dad does. `AssistiveAccessScreen`
/// therefore spells the order out — triple-click first, then tap — rather than
/// leaving it to be worked out by somebody whose phone has just become
/// unfamiliar.
enum AssistiveAccessPairing {

    /// What to say when a session just started on a Mode that asks for
    /// Assistive Access, or `nil` when it doesn't.
    ///
    /// Posted from wherever the session began, which means it reaches you on
    /// the paths that run in the app's process — a tap, the Shortcuts intent,
    /// the in-app button — and not from the DeviceActivity extension, which
    /// holds a `SilentNotifier` and could not ask for notification permission
    /// if it wanted to. A scheduled Mode that asks for Assistive Access
    /// therefore starts without saying so; `docs/roadmap.md` records that as a
    /// limitation rather than this pretending otherwise.
    /// - Parameter role: whose phone this is. Entering Assistive Access asks
    ///   for its passcode — Apple's setup page says the code "is used to enter
    ///   or exit", and on a phone with a Screen Time passcode already set it is
    ///   that one. A young person's phone therefore cannot complete this alone,
    ///   so it is told what it needs rather than told to press a button that
    ///   will stop and ask for something it does not have.
    static func noticeOnDad(mode: DadMode, role: HouseholdRole) -> ImmediateNotice? {
        guard mode.asksForAssistiveAccess else { return nil }
        return ImmediateNotice(id: noticeID,
                               title: Vocab.assistiveAccessPromptTitle(mode: mode.name),
                               body: Vocab.assistiveAccessPromptBody(role: role))
    }

    /// One id for this kind of notice, so a second tap replaces the first
    /// rather than leaving two banners about the same phone.
    static let noticeID = "notice.assistive-access"
}
