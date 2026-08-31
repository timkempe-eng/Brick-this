import Foundation

/// What a Mode takes away, as far as Core is concerned: an opaque blob and
/// three counts.
///
/// On iOS the payload is an encoded `FamilyActivitySelection` full of
/// `ApplicationToken`s that only the system can resolve back to real apps.
/// Core never decodes it — only `TimMode+FamilyControls` does, and only to
/// hand it to ManagedSettings.
///
/// That is the privacy model expressed as a type. The app is not supposed to
/// learn which apps you blocked, and now nothing outside one file *can*.
struct BlockedSelection: Codable, Hashable {
    /// Encoded `FamilyActivitySelection`. Opaque here by design.
    var payload: Data = Data()

    var appCount: Int = 0
    var categoryCount: Int = 0
    var webDomainCount: Int = 0

    var totalCount: Int { appCount + categoryCount + webDomainCount }
    var isEmpty: Bool { totalCount == 0 }

    /// "3 apps · 1 category · 2 sites" — used by the Modes list.
    var summary: String {
        guard !isEmpty else { return "Nothing blocked yet" }
        var parts: [String] = []
        if appCount > 0 { parts.append("\(appCount) app\(appCount == 1 ? "" : "s")") }
        if categoryCount > 0 {
            parts.append("\(categoryCount) categor\(categoryCount == 1 ? "y" : "ies")")
        }
        if webDomainCount > 0 { parts.append("\(webDomainCount) site\(webDomainCount == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}
