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

    /// Optional recurring window during which this Mode runs on its own.
    /// Optional so that Modes stored before schedules existed still decode.
    var schedule: ModeSchedule?

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

    var blocksAnything: Bool { !blocked.isEmpty }

    /// Shown under the name in the Modes list.
    var summary: String {
        var parts = [blocked.summary]
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

    static let starterModes: [DadMode] = [
        DadMode(name: "Deep Work", symbol: "brain.head.profile"),
        DadMode(name: "Dinner",    symbol: "fork.knife"),
        DadMode(name: "Sleep",     symbol: "moon.zzz.fill", isStrict: true),
        DadMode(name: "Gym",       symbol: "figure.run"),
    ]
}
