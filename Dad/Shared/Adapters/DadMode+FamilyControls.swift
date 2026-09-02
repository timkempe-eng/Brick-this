import Foundation
import FamilyControls

/// The only place a `BlockedSelection`'s payload is interpreted.
///
/// Both directions live here, adjacent, because the two representations have
/// to stay in step: the counts Core reads must describe the tokens the shield
/// applies. Encoding is the single writer of both.
extension BlockedSelection {

    /// Decodes back to the FamilyControls selection. An unreadable payload
    /// yields an empty selection rather than throwing — a Mode that blocks
    /// nothing is a visible, recoverable state; a crash on launch is not.
    var familyActivitySelection: FamilyActivitySelection {
        guard !payload.isEmpty,
              let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: payload)
        else { return FamilyActivitySelection() }
        return decoded
    }

    init(_ selection: FamilyActivitySelection) {
        self.init(
            payload: (try? JSONEncoder().encode(selection)) ?? Data(),
            appCount: selection.applicationTokens.count,
            categoryCount: selection.categoryTokens.count,
            webDomainCount: selection.webDomainTokens.count
        )
    }
}

extension DadMode {
    /// Read/write bridge for `FamilyActivityPicker`, which binds to a
    /// `FamilyActivitySelection` directly.
    var selection: FamilyActivitySelection {
        get { blocked.familyActivitySelection }
        set { blocked = BlockedSelection(newValue) }
    }
}
