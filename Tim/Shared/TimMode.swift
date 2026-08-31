import Foundation
import FamilyControls
import ManagedSettings

/// A named set of things to block — the equivalent of a Brick "Mode".
///
/// The blocked set is a `FamilyActivitySelection`, which is what
/// `FamilyActivityPicker` hands back. It holds opaque `ApplicationToken`s,
/// `ActivityCategoryToken`s and `WebDomainToken`s: we never learn which apps
/// the user picked, we just pass the tokens straight to `ManagedSettings`.
/// The tokens are stable for this app's install, so persisting the whole
/// selection is enough to restore a mode across launches.
struct TimMode: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var symbol: String

    /// Apps, categories and web domains that this mode takes away.
    var selection: FamilyActivitySelection = FamilyActivitySelection()

    /// Strict mode: while this mode is active, iOS refuses to delete the Tim
    /// app or let Screen Time settings be changed. Stops the two-second
    /// "delete the blocker" escape hatch.
    var isStrict: Bool = false

    /// Optional auto-release. `nil` means the session runs until the tag is
    /// tapped again.
    var autoUnTimAfter: TimeInterval?

    var blocksAnything: Bool {
        !selection.applicationTokens.isEmpty
            || !selection.categoryTokens.isEmpty
            || !selection.webDomainTokens.isEmpty
    }

    static let starterModes: [TimMode] = [
        TimMode(name: "Deep Work", symbol: "brain.head.profile"),
        TimMode(name: "Dinner",    symbol: "fork.knife"),
        TimMode(name: "Sleep",     symbol: "moon.zzz.fill", isStrict: true),
        TimMode(name: "Gym",       symbol: "figure.run"),
    ]
}
