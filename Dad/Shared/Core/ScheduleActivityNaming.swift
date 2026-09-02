import Foundation

/// DeviceActivity identifies each monitored window by an opaque string, and
/// the monitor extension is woken with nothing but that string. So the Mode a
/// window belongs to has to be encoded into the name and parsed back out.
///
/// Pure string work, kept in Core so it can be tested — a round-trip bug here
/// would mean scheduled sessions silently never start.
enum ScheduleActivityNaming {

    /// The one-shot "release this timed session" window, which belongs to no
    /// particular Mode.
    static let release = "dad.autoUnDad"

    private static let schedulePrefix = "dad.schedule."

    /// - Parameter weekday: `nil` for a schedule that runs every day, which
    ///   needs only one window rather than seven.
    static func name(modeID: UUID, weekday: Int? = nil) -> String {
        let base = schedulePrefix + modeID.uuidString
        guard let weekday else { return base }
        return base + ".\(weekday)"
    }

    static func modeID(from name: String) -> UUID? {
        guard name.hasPrefix(schedulePrefix) else { return nil }
        let rest = name.dropFirst(schedulePrefix.count)
        // Either "<uuid>" or "<uuid>.<weekday>"; a UUID has no dots of its own.
        let uuidPart = rest.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
        return UUID(uuidString: uuidPart)
    }

    static func isRelease(_ name: String) -> Bool { name == release }
}
