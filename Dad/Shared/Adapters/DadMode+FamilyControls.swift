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

    /// The same bridge for the survivors of an allowlist Mode. A second
    /// property rather than one that switches on the style, so the editor
    /// cannot write the wrong list into the wrong field.
    var allowedFamilySelection: FamilyActivitySelection {
        get { allowedSelection.familyActivitySelection }
        set { allowed = BlockedSelection(newValue) }
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

    /// Which categories the shield covers.
    ///
    /// `all` is what makes an allowlist possible at all: ManagedSettings
    /// expresses "everything except these apps" natively as
    /// `.all(except:)`, so inverting a Mode is a change of policy case rather
    /// than an attempt to enumerate every app on the phone — which nothing
    /// here can do, and which would rot the moment a new app was installed.
    enum CategoryScope: Equatable {
        case none
        case specific(Set<ActivityCategoryToken>)
        case all
    }

    let applications: Set<ApplicationToken>
    let categoryScope: CategoryScope
    let webDomains: Set<WebDomainToken>

    /// Handed to ManagedSettings as the `except:` of a category policy.
    /// Categories are deliberately *not* filtered by removing them: shielding
    /// "Social except WhatsApp" is a better answer than not shielding Social,
    /// and ManagedSettings expresses it natively.
    let exceptApplications: Set<ApplicationToken>
    let exceptWebDomains: Set<WebDomainToken>

    var isEmpty: Bool {
        applications.isEmpty && categoryScope == .none && webDomains.isEmpty
    }

    /// The categories named explicitly, for a caller that cannot express
    /// "all" — `DeviceActivityEvent` has no such form and its categories
    /// cannot be enumerated from here.
    ///
    /// Empty for `.all`, which is only safe because `DadMode.rations` refuses
    /// an allowlist Mode outright: were that guard ever removed, this would
    /// quietly count nothing rather than everything, which is the failure that
    /// guard exists to prevent. Both live in `DadMode` next to each other for
    /// that reason.
    var namedCategories: Set<ActivityCategoryToken> {
        if case .specific(let categories) = categoryScope { return categories }
        return []
    }
}

extension DadMode {
    /// - Parameter neverBlocked: apps and sites no Mode may take away.
    func shieldTokens(neverBlocked: BlockedSelection) -> ShieldTokens {
        let safe = neverBlocked.familyActivitySelection

        switch effectiveStyle {
        case .blocklist:
            let wanted = selection
            return ShieldTokens(
                // An app named on both lists is protected. The never-block list
                // wins by construction rather than by ordering, because a rule
                // whose outcome depends on which screen you edited last is not a
                // safety net.
                applications: wanted.applicationTokens.subtracting(safe.applicationTokens),
                categoryScope: wanted.categoryTokens.isEmpty
                    ? .none : .specific(wanted.categoryTokens),
                webDomains: wanted.webDomainTokens.subtracting(safe.webDomainTokens),
                exceptApplications: safe.applicationTokens,
                exceptWebDomains: safe.webDomainTokens
            )

        case .allowlist:
            // Everything, minus what you chose to keep — and the never-blocked
            // list is unioned into the same exception rather than applied
            // afterwards, so the two lists cannot disagree about an app that is
            // on both.
            let keep = allowedSelection.familyActivitySelection
            return ShieldTokens(
                applications: [],
                categoryScope: .all,
                webDomains: [],
                exceptApplications: keep.applicationTokens.union(safe.applicationTokens),
                exceptWebDomains: keep.webDomainTokens.union(safe.webDomainTokens)
            )
        }
    }

    /// The apps whose use counts against a rationed Mode's allowance.
    ///
    /// The same subtraction, and it has to be: time spent in a banking app you
    /// protected must not spend the allowance for the apps you were rationing.
    /// A `DeviceActivityEvent` has no `except:`, so here the categories cannot
    /// carry an exception either — which is a real limitation and is written
    /// down in docs/roadmap.md rather than hidden.
    ///
    /// Only ever called for a blocklist Mode: `DadMode.rations` refuses an
    /// allowlist, because a usage event counts a *named* set and there is no
    /// "everything except" form of one.
    func usageTokens(neverBlocked: BlockedSelection) -> ShieldTokens {
        shieldTokens(neverBlocked: neverBlocked)
    }
}
