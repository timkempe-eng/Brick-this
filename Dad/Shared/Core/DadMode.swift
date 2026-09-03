import Foundation

/// A named set of things to block — the equivalent of a Brick "Mode".
struct DadMode: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var symbol: String

    /// Apps, categories and web domains this mode takes away, opaque to Core.
    /// Used when `effectiveStyle` is `.blocklist`.
    var blocked: BlockedSelection = BlockedSelection()

    /// The few things that stay, when this Mode leaves only what you name.
    /// Used when `effectiveStyle` is `.allowlist`.
    ///
    /// A separate field rather than reinterpreting `blocked`, because a value
    /// whose meaning depends on a sibling field is how you end up shielding
    /// the apps someone meant to keep. It also means switching a Mode between
    /// the two styles and back does not destroy either list.
    ///
    /// **Optional, and that is load-bearing.** Swift's synthesised decoder does
    /// not fall back to a property's default when the key is absent — it fails
    /// the whole record. `LenientDecoding` then *skips* that record, so a
    /// non-optional field added here would silently delete every Mode stored
    /// before this build. `schedule`, `allowance` and `resumeAfter` are
    /// Optional for exactly the same reason.
    var allowed: BlockedSelection?

    /// Whether this Mode names what goes away, or the only things that stay.
    /// `nil` decodes as `.blocklist` — see the note on `allowed`.
    var style: ModeStyle?

    /// Strict mode: while this mode is active, iOS refuses to delete the Dad
    /// app. Stops the two-second "delete the blocker" escape hatch.
    var isStrict: Bool = false

    /// Optional auto-release. `nil` means the session runs until the tag is
    /// tapped again.
    var autoUnDadAfter: TimeInterval?

    /// How long a break lasts before this Mode starts itself again, or `nil`
    /// for the ordinary behaviour: releasing means released.
    ///
    /// Only a release *by hand* arms it — a tap, or the Un-Dad intent. An
    /// emergency override never does, because an override is for when the tag
    /// is genuinely out of reach and re-blocking someone in fifteen minutes
    /// would trap them; and neither does a timed release or a schedule
    /// boundary, both of which have already said when this Mode should stop.
    var resumeAfter: TimeInterval?

    /// Optional recurring window during which this Mode runs on its own.
    /// Optional so that Modes stored before schedules existed still decode.
    var schedule: ModeSchedule?

    /// Optional daily budget. When set, the Mode rations its apps rather than
    /// taking them away: they stay usable until the allowance runs out, and
    /// only then does the shield go up. Optional for the same reason as
    /// `schedule` — Modes stored before allowances existed must still decode.
    var allowance: ModeAllowance?

    /// Whether this Mode runs on a schedule. The editor's switch binds
    /// straight to this.
    ///
    /// It used to build a `Binding(get:set:)` inside the view instead, which
    /// put the one decision here — switched on with no schedule yet, so make a
    /// usable one — somewhere no test could reach. A Simulator run showed the
    /// switch springing back to off and nothing could say why, because the
    /// logic wasn't anywhere a test could call it.
    var isScheduled: Bool {
        get { schedule?.isEnabled ?? false }
        set {
            var updated = schedule ?? .starter
            updated.isEnabled = newValue
            schedule = updated
        }
    }

    /// The schedule the editor edits. Reading yields the starter window when
    /// none is stored, so every control below the switch can bind directly
    /// rather than through an optional.
    var editableSchedule: ModeSchedule {
        get { schedule ?? .starter }
        set { schedule = newValue }
    }

    /// Whether this Mode rations rather than forbids. Same shape as
    /// `isScheduled`, and here for the same reason: the one decision the
    /// switch carries — switched on with no allowance yet, so make a usable
    /// one — belongs somewhere a test can call it.
    var isRationed: Bool {
        get { allowance?.isEnabled ?? false }
        set {
            var updated = allowance ?? .starter
            updated.isEnabled = newValue
            allowance = updated
        }
    }

    /// The allowance the editor edits, yielding the starter budget when none
    /// is stored so the controls below the switch bind directly.
    var editableAllowance: ModeAllowance {
        get { allowance ?? .starter }
        set { allowance = newValue }
    }

    var effectiveStyle: ModeStyle { style ?? .blocklist }

    /// The survivors, when this Mode leaves only what you name.
    var allowedSelection: BlockedSelection { allowed ?? BlockedSelection() }

    /// Whether starting this Mode would actually take something away.
    ///
    /// An allowlist always does, and deliberately even when nothing is allowed:
    /// "leave nothing" is a legitimate Sleep Mode, not a misconfiguration. iOS
    /// never shields Phone, so it cannot lock anyone out of a call.
    var blocksAnything: Bool {
        switch effectiveStyle {
        case .blocklist: return !blocked.isEmpty
        case .allowlist: return true
        }
    }

    /// Shown under the name in the Modes list.
    /// Whether releasing this Mode by hand starts a break rather than ending it.
    var takesBreaks: Bool { (resumeAfter ?? 0) > 0 && blocksAnything }

    var summary: String {
        var parts = [styleSummary]
        if let allowance, allowance.isEnabled, allowance.isValid {
            parts.append(allowance.displayText)
        }
        if takesBreaks, let seconds = resumeAfter {
            parts.append("\(seconds.dadDurationText) breaks")
        }
        if isStrict { parts.append("strict") }
        if let schedule, schedule.isEnabled, schedule.isValid {
            parts.append(schedule.displayText())
        }
        return parts.joined(separator: " · ")
    }

    /// "3 apps · 1 category" for a blocklist; "Only 2 apps stay" for an
    /// allowlist. The two must not read alike — the whole risk of inverting a
    /// Mode is picking a list and having it mean the opposite of what you
    /// intended.
    private var styleSummary: String {
        switch effectiveStyle {
        case .blocklist:
            return blocked.summary
        case .allowlist:
            let allowed = allowedSelection
            return allowed.isEmpty ? "Everything goes" : "Only \(allowed.summary)"
        }
    }

    /// Whether this Mode should be registered with the system scheduler.
    var hasLiveSchedule: Bool {
        guard let schedule else { return false }
        return schedule.isEnabled && schedule.isValid && blocksAnything
    }

    /// Whether this Mode rations its apps instead of taking them away.
    ///
    /// Requires the Mode to block something, for the same reason
    /// `hasLiveSchedule` does: an allowance over an empty selection counts
    /// nothing, would never reach its threshold, and would leave a Mode that
    /// says "15 min a day" and means "no limit at all".
    var rations: Bool {
        guard let allowance else { return false }
        // An allowlist Mode cannot ration. `DeviceActivityEvent` counts usage
        // of a *named* set of applications, categories and domains — there is
        // no "everything except" form of it, and the categories cannot be
        // enumerated from here. So the threshold would count nothing, never
        // fire, and leave a Mode reading "15 min a day" that lets you use the
        // phone all day. Refused in Core rather than discovered on a device.
        guard effectiveStyle == .blocklist else { return false }
        return allowance.isEnabled && allowance.isValid && blocksAnything
    }

    /// Whether a Mode names what goes, or the only things that stay.
    ///
    /// Blocklists decay: a Sleep Mode is only as good as your memory, and every
    /// app installed after you built it is a silent hole. An allowlist is the
    /// one shape on this list that improves with time instead — which is why it
    /// is the right default for exactly the two Modes a household cares most
    /// about, Sleep and School.
    enum ModeStyle: String, Codable, Hashable, CaseIterable {
        /// Take these away.
        case blocklist
        /// Leave only these.
        case allowlist
    }

    static let starterModes: [DadMode] = [
        DadMode(name: "Deep Work", symbol: "brain.head.profile"),
        DadMode(name: "Dinner",    symbol: "fork.knife"),
        DadMode(name: "Sleep",     symbol: "moon.zzz.fill", isStrict: true),
        DadMode(name: "Gym",       symbol: "figure.run"),
    ]
}
