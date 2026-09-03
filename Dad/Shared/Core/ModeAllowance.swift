import Foundation

/// A daily budget of the apps a Mode covers, instead of taking them away
/// outright — "fifteen minutes of Instagram a day, then it's gone".
///
/// Screen Time can throttle as well as forbid, and a rationed Mode is a softer
/// tool than a hard shield. It is also a different mechanism: a shield is
/// applied and stays applied, while an allowance is *counted* by the system
/// and only becomes a shield once it runs out.
///
/// Not to be confused with `EmergencyAllowance`, which rations the emergency
/// overrides that end a session early. This one rations the apps themselves.
/// They share a word because the user meets neither of them by that name — one
/// is "emergency overrides", the other is "a daily allowance".
struct ModeAllowance: Codable, Hashable {

    var isEnabled: Bool = true

    /// Minutes of the Mode's apps permitted each day.
    var minutesPerDay: Int

    /// The allowance a Mode gets the moment rationing is switched on. Already
    /// valid, so the switch never leaves a Mode that looks rationed and
    /// enforces nothing.
    static let starter = ModeAllowance(minutesPerDay: 15)

    /// The lengths the editor offers.
    static let offered = [5, 10, 15, 30, 45, 60, 90, 120]

    /// A whole day is not a limit, and zero is a block with extra steps — both
    /// are allowances that would look set up and do nothing recognisable.
    static let maximumMinutes = 720

    var isValid: Bool { (1...Self.maximumMinutes).contains(minutesPerDay) }

    var duration: TimeInterval { TimeInterval(minutesPerDay * 60) }

    /// "15 min a day" — shown under the Mode in the list.
    var displayText: String {
        guard isEnabled else { return "No allowance" }
        guard isValid else { return "Allowance incomplete" }
        if minutesPerDay % 60 == 0 {
            let hours = minutesPerDay / 60
            return "\(hours)h a day"
        }
        return "\(minutesPerDay) min a day"
    }
}
