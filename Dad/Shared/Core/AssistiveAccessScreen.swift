import Foundation

/// Everything Dad shows on a phone running in Assistive Access.
///
/// Assistive Access is the iOS mode a trusted supporter turns on in Settings
/// to reduce the whole phone to a few large buttons and plain sentences. Dad
/// cannot put a phone into it — no API does, see
/// [ADR 008](../../../docs/adr/008-assistive-access.md) — but a phone already
/// in it is a phone where the household's off switch should still work, and
/// where the standard home screen's four toolbar buttons, streak flame and
/// monospaced timer are four too many things.
///
/// Same division of labour as `WidgetSnapshot`: the decision of *what it says*
/// is here, where `swift test` covers it, and the scene above is left with
/// nothing but layout.
///
/// The headlines are whole sentences rather than the widget's single words.
/// A widget is a glance beside the clock and has room for one; Assistive
/// Access is the whole screen, and its guidance asks for plain language rather
/// than the shortest possible label.
enum AssistiveAccessScreen: Equatable {

    /// The phone is Dadded.
    ///
    /// - Parameter rationing: the Mode rations rather than forbids and today's
    ///   allowance is not spent, so the apps are still there. The same third
    ///   state the widget and the shield draw separately, for the same reason:
    ///   telling someone their phone is Dadded while their apps still open is
    ///   how a product stops being believed.
    case dadded(modeName: String, rationing: Bool, release: Release)

    /// Released by hand onto a leash — the Mode comes back on its own.
    case onBreak(modeName: String, until: Date)

    case free

    /// What this screen can offer besides the tag.
    ///
    /// The tag is the control, and a button that Un-Dads would make it
    /// optional. The one exception is the override the shield already carries:
    /// a person in Assistive Access may not be able to reach a shielded app to
    /// find that button, and a tag in another room would then be a trap rather
    /// than a friction. Offering the same rationed, permissioned escape hatch
    /// here widens nothing — it is the existing hatch, reachable.
    enum Release: Equatable {
        /// Nothing on this screen ends the session. Go and find the tag.
        case tagOnly
        /// The emergency override, with what is left of the allowance.
        case emergency(remaining: Int)
    }

    /// - Parameters:
    ///   - mayOverride: whether this phone's role is allowed to spend an
    ///     emergency override at all. Defaulted to `false`, which is the
    ///     conservative direction: a permission that defaults to granted is a
    ///     permission a call site can forget to pass and never be told.
    ///   - emergencyOverridesRemaining: what is left of the rolling allowance.
    static func make(session: DadSession?,
                     mode: DadMode? = nil,
                     pendingResume: PendingResume? = nil,
                     mayOverride: Bool = false,
                     emergencyOverridesRemaining: Int = 0,
                     now: Date = Date(),
                     calendar: Calendar = .current) -> AssistiveAccessScreen {
        // Session first, then the break, then free — the same order
        // `WidgetSnapshot.make` reads them in. Two surfaces answering "is this
        // phone Dadded" from the same stored state must not be able to
        // disagree; `AssistiveAccessAgreesWithTheWidgetTests` walks the matrix.
        if let session {
            let state = ShieldPolicy.state(session: session, mode: mode,
                                           now: now, calendar: calendar)
            return .dadded(modeName: session.modeName,
                           rationing: state == .rationing,
                           release: release(mayOverride: mayOverride,
                                            remaining: emergencyOverridesRemaining))
        }
        if let pendingResume, !pendingResume.isDue(now: now) {
            return .onBreak(modeName: pendingResume.modeName, until: pendingResume.at)
        }
        return .free
    }

    private static func release(mayOverride: Bool, remaining: Int) -> Release {
        guard mayOverride, remaining > 0 else { return .tagOnly }
        return .emergency(remaining: remaining)
    }

    /// The sentence at the top, in the largest type on the screen.
    var headline: String {
        switch self {
        case .dadded:  return Vocab.activeTitle
        case .onBreak: return Vocab.breakTitle
        case .free:    return Vocab.idleTitle
        }
    }

    /// The one line under it, and the only place the Mode is named.
    ///
    /// The Dadded line names the triple-click as well as the tag, and does so
    /// unconditionally rather than only for a Mode that asked to be paired
    /// with Assistive Access. This screen renders only while Assistive Access
    /// is on — that is what the scene is for — so whoever is reading it is
    /// already inside, and getting out needs the passcode whether or not the
    /// Mode had an opinion about getting in.
    var detail: String {
        switch self {
        case .dadded(let modeName, let rationing, _):
            return rationing
                ? "\(modeName). Your apps are still here for now."
                : "\(modeName). \(Vocab.assistiveAccessExitHint)"
        case .onBreak(let modeName, let until):
            return "\(Vocab.breakRunning(mode: modeName, until: until)) \(Vocab.breakTapHint)"
        case .free:
            return Vocab.idleSubtitle
        }
    }

    var symbolName: String {
        switch self {
        case .dadded(_, let rationing, _): return rationing ? "hourglass" : "lock.iphone"
        case .onBreak:                     return "arrow.clockwise.circle"
        case .free:                        return "iphone.gen3"
        }
    }

    /// The single button, or `nil` when the tag is the only way out.
    var actionTitle: String? {
        guard case .dadded(_, _, .emergency) = self else { return nil }
        return Vocab.emergencyUnDad
    }

    /// The line under the button. It says what is left *before* the button is
    /// pressed — the banner afterwards is too late to inform the decision, and
    /// noticing the hatch is being reached for is the whole point of counting
    /// them at all.
    var actionFootnote: String? {
        guard case .dadded(_, _, .emergency(let remaining)) = self else { return nil }
        return "Only for an emergency. \(remaining) left this month."
    }

    var isDadded: Bool {
        if case .dadded = self { return true }
        return false
    }
}
