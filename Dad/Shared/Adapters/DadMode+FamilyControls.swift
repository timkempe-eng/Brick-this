import Foundation
import FamilyControls
// `ApplicationToken`, `ActivityCategoryToken` and `WebDomainToken` are
// declared by ManagedSettings, not FamilyControls — a `FamilyActivitySelection`
// hands them out but does not vend the types. Preflight already requires every
// target that compiles this file to link what it imports, and all four that do
// already link ManagedSettings; the widget does not compile it at all.
import ManagedSettings

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

/// What the system should actually restrict, once the never-block list has
/// been taken out of the Mode's selection.
///
/// Both halves are opaque tokens everywhere else in the codebase, so this is
/// the only place the subtraction can happen — hard rule 3 as a location
/// rather than a convention. It is also the only place that *could* do it:
/// Core holds two `Data` blobs and has no way to tell whether they overlap.
struct ShieldTokens {
    let applications: Set<ApplicationToken>
    let categories: Set<ActivityCategoryToken>
    let webDomains: Set<WebDomainToken>

    /// Handed to ManagedSettings as the `except:` of a category policy.
    /// Categories are deliberately *not* filtered by removing them: shielding
    /// "Social except WhatsApp" is a better answer than not shielding Social,
    /// and ManagedSettings expresses it natively.
    let exceptApplications: Set<ApplicationToken>
    let exceptWebDomains: Set<WebDomainToken>

    var isEmpty: Bool {
        applications.isEmpty && categories.isEmpty && webDomains.isEmpty
    }
}

extension DadMode {
    /// - Parameter neverBlocked: apps and sites no Mode may take away.
    func shieldTokens(neverBlocked: BlockedSelection) -> ShieldTokens {
        let wanted = selection
        let safe = neverBlocked.familyActivitySelection

        return ShieldTokens(
            // An app named on both lists is protected. The never-block list
            // wins by construction rather than by ordering, because a rule
            // whose outcome depends on which screen you edited last is not a
            // safety net.
            applications: wanted.applicationTokens.subtracting(safe.applicationTokens),
            categories: wanted.categoryTokens,
            webDomains: wanted.webDomainTokens.subtracting(safe.webDomainTokens),
            exceptApplications: safe.applicationTokens,
            exceptWebDomains: safe.webDomainTokens
        )
    }

    /// The apps whose use counts against a rationed Mode's allowance.
    ///
    /// The same subtraction, and it has to be: time spent in a banking app you
    /// protected must not spend the allowance for the apps you were rationing.
    /// A `DeviceActivityEvent` has no `except:`, so here the categories cannot
    /// carry an exception either — which is a real limitation and is written
    /// down in docs/roadmap.md rather than hidden.
    func usageTokens(neverBlocked: BlockedSelection) -> ShieldTokens {
        shieldTokens(neverBlocked: neverBlocked)
    }
}
