import Foundation

/// A named set of things to block — the equivalent of a Brick "Mode".
struct DadMode: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var symbol: String

    /// Apps, categories and web domains this mode takes away, opaque to Core.
    var blocked: BlockedSelection = BlockedSelection()

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

    var blocksAnything: Bool { !blocked.isEmpty }

    /// Shown under the name in the Modes list.
    /// Whether releasing this Mode by hand starts a break rather than ending it.
    var takesBreaks: Bool { (resumeAfter ?? 0) > 0 && blocksAnything }

    var summary: String {
        var parts = [blocked.summary]
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
        return allowance.isEnabled && allowance.isValid && blocksAnything
    }

    static let starterModes: [DadMode] = [
        DadMode(name: "Deep Work", symbol: "brain.head.profile"),
        DadMode(name: "Dinner",    symbol: "fork.knife"),
        DadMode(name: "Sleep",     symbol: "moon.zzz.fill", isStrict: true),
        DadMode(name: "Gym",       symbol: "figure.run"),
    ]
}
