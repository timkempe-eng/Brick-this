import Foundation

/// A named set of things to block — the equivalent of a Brick "Mode".
struct TimMode: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var symbol: String

    /// Apps, categories and web domains this mode takes away, opaque to Core.
    var blocked: BlockedSelection = BlockedSelection()

    /// Strict mode: while this mode is active, iOS refuses to delete the Tim
    /// app. Stops the two-second "delete the blocker" escape hatch.
    var isStrict: Bool = false

    /// Optional auto-release. `nil` means the session runs until the tag is
    /// tapped again.
    var autoUnTimAfter: TimeInterval?

    /// Optional recurring window during which this Mode runs on its own.
    /// Optional so that Modes stored before schedules existed still decode.
    var schedule: ModeSchedule?

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

    static let starterModes: [TimMode] = [
        TimMode(name: "Deep Work", symbol: "brain.head.profile"),
        TimMode(name: "Dinner",    symbol: "fork.knife"),
        TimMode(name: "Sleep",     symbol: "moon.zzz.fill", isStrict: true),
        TimMode(name: "Gym",       symbol: "figure.run"),
    ]
}
