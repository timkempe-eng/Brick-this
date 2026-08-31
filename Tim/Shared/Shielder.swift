import Foundation
import FamilyControls
import ManagedSettings

/// The thin layer over `ManagedSettings` that actually takes the apps away.
///
/// Everything Brick does at this level, iOS already does: we hand a set of
/// opaque tokens to a `ManagedSettingsStore` and the system draws its shield
/// over those apps until we clear the store. There is no polling, no
/// background task, and nothing to keep alive — the settings outlive our
/// process, which is exactly why the block survives a force-quit.
enum Shielder {
    /// A named store keeps our restrictions in their own bucket, so clearing
    /// ours never disturbs Screen Time limits the user set up themselves.
    private static let store = ManagedSettingsStore(named: .tim)

    static func applyShield(for mode: TimMode) {
        let selection = mode.selection

        store.shield.applications = selection.applicationTokens.isEmpty
            ? nil
            : selection.applicationTokens

        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens, except: Set())

        store.shield.webDomains = selection.webDomainTokens.isEmpty
            ? nil
            : selection.webDomainTokens

        store.shield.webDomainCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens, except: Set())

        // Strict mode closes the obvious escape hatch: deleting Tim would
        // otherwise tear down the shield with it.
        if mode.isStrict {
            store.application.denyAppRemoval = true
        } else {
            store.application.denyAppRemoval = nil
        }
    }

    static func removeShield() {
        store.clearAllSettings()
    }
}

extension ManagedSettingsStore.Name {
    static let tim = Self("tim")
}
