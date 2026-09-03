import Foundation

/// DeviceActivity identifies each monitored window by an opaque string, and
/// the monitor extension is woken with nothing but that string. So whatever
/// the window is *for* has to be encoded into the name and parsed back out.
///
/// Pure string work, kept in Core so it can be tested — a round-trip bug here
/// would mean scheduled sessions silently never start, or an allowance that is
/// counted and then never acted on.
enum ScheduleActivityNaming {

    /// The one-shot "release this timed session" window, which belongs to no
    /// particular Mode.
    static let release = "dad.autoUnDad"

    /// The one-shot "the break is over, bring the Mode back" window.
    static let resume = "dad.resume"

    /// The event within an allowance window that fires once the Mode's apps
    /// have been used for as long as the allowance permits. One name for all
    /// Modes: the *activity* already says which Mode this is, and a second
    /// place to encode it is a second place to get it wrong.
    static let allowanceSpent = "dad.allowance.spent"

    private static let schedulePrefix = "dad.schedule."
    private static let allowancePrefix = "dad.allowance."

    /// - Parameter weekday: `nil` for a schedule that runs every day, which
    ///   needs only one window rather than seven.
    static func name(modeID: UUID, weekday: Int? = nil) -> String {
        let base = schedulePrefix + modeID.uuidString
        guard let weekday else { return base }
        return base + ".\(weekday)"
    }

    /// The daily window inside which a rationing Mode's usage is counted.
    static func allowanceName(modeID: UUID) -> String {
        allowancePrefix + modeID.uuidString
    }

    static func modeID(from name: String) -> UUID? {
        guard name.hasPrefix(schedulePrefix) else { return nil }
        return uuid(afterPrefixOf: name, prefix: schedulePrefix)
    }

    static func isRelease(_ name: String) -> Bool { name == release }

    // MARK: - Dispatch

    /// What a window the system just woke us for actually is.
    ///
    /// The extension is the only caller and it has exactly one string to go
    /// on, so the decision is made once, here, rather than as a chain of
    /// `hasPrefix` checks in a process that is hard to observe. Adding a
    /// fourth kind of window without teaching this function about it is then a
    /// compile error at the switch rather than a window that is registered,
    /// fires, and is quietly ignored.
    enum Activity: Equatable {
        /// A timed session's one-shot release.
        case release
        /// The end of a break, when the Mode starts itself again.
        case resume
        /// One end of a Mode's recurring wall-clock window.
        case scheduledWindow(modeID: UUID)
        /// The day within which a rationing Mode's allowance is counted.
        case allowanceDay(modeID: UUID)
        /// Not ours, or a name from a build that knew about something we don't.
        case unrecognised
    }

    static func activity(named name: String) -> Activity {
        if isRelease(name) { return .release }
        if name == resume { return .resume }
        // Order matters: both prefixes start "dad.", and only an exact prefix
        // match distinguishes them.
        if name.hasPrefix(allowancePrefix),
           let id = uuid(afterPrefixOf: name, prefix: allowancePrefix) {
            return .allowanceDay(modeID: id)
        }
        if let id = modeID(from: name) { return .scheduledWindow(modeID: id) }
        return .unrecognised
    }

    /// Either "<uuid>" or "<uuid>.<suffix>"; a UUID has no dots of its own.
    private static func uuid(afterPrefixOf name: String, prefix: String) -> UUID? {
        let rest = name.dropFirst(prefix.count)
        let head = rest.split(separator: ".", maxSplits: 1).first.map(String.init) ?? ""
        return UUID(uuidString: head)
    }
}
