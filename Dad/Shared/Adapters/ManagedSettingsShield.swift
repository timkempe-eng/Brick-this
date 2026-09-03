import Foundation
import FamilyControls
import ManagedSettings

/// `ShieldControlling` over ManagedSettings — the thing that actually takes
/// the apps away.
///
/// There is no polling and nothing to keep alive: the restrictions are stored
/// by the system and outlive our process, which is exactly why the block
/// survives a force-quit.
struct ManagedSettingsShield: ShieldControlling {

    /// A named store keeps our restrictions in their own bucket, so clearing
    /// ours never disturbs Screen Time limits the user set up themselves.
    private let store = ManagedSettingsStore(named: .dad)

    func apply(_ mode: DadMode) {
        applyShield(mode)
        applyRestrictions(mode)
    }

    /// A rationing Mode while its allowance lasts: the apps are still there,
    /// but strict still refuses to let Dad be deleted. The shield fields are
    /// cleared explicitly rather than left alone, because this is also the
    /// path back down when a new day hands the allowance back.
    func applyRestrictionsOnly(_ mode: DadMode) {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        store.shield.webDomainCategories = nil
        applyRestrictions(mode)
    }

    private func applyShield(_ mode: DadMode) {
        let selection = mode.selection

        store.shield.applications = selection.applicationTokens.isEmpty
            ? nil : selection.applicationTokens

        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil : .specific(selection.categoryTokens, except: Set())

        store.shield.webDomains = selection.webDomainTokens.isEmpty
            ? nil : selection.webDomainTokens

        store.shield.webDomainCategories = selection.categoryTokens.isEmpty
            ? nil : .specific(selection.categoryTokens, except: Set())
    }

    /// Strict closes the obvious escape hatch: deleting Dad would otherwise
    /// tear the shield down with it. Applied whether the Mode is blocking or
    /// merely rationing — the free period is precisely when someone would
    /// reach for that hatch.
    private func applyRestrictions(_ mode: DadMode) {
        store.application.denyAppRemoval = mode.isStrict ? true : nil
    }

    func clear() {
        store.clearAllSettings()
    }
}

extension ManagedSettingsStore.Name {
    static let dad = Self("dad")
}
