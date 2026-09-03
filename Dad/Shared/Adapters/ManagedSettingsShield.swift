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

    func apply(_ mode: DadMode, neverBlocked: BlockedSelection) {
        applyShield(mode.shieldTokens(neverBlocked: neverBlocked))
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

    /// The `except:` arguments are where the never-block list lands, and they
    /// are the reason it works for categories at all: "Social, except
    /// WhatsApp" is a thing ManagedSettings expresses natively, and it is a
    /// far better answer than declining to shield Social.
    private func applyShield(_ tokens: ShieldTokens) {
        store.shield.applications = tokens.applications.isEmpty
            ? nil : tokens.applications

        switch tokens.categoryScope {
        case .none:
            store.shield.applicationCategories = nil
            store.shield.webDomainCategories = nil
        case .specific(let categories):
            store.shield.applicationCategories = .specific(categories, except: tokens.exceptApplications)
            store.shield.webDomainCategories = .specific(categories, except: tokens.exceptWebDomains)
        case .all:
            // An allowlist Mode: leave only what was named. This is the whole
            // reason the inversion is cheap — ManagedSettings does the "except"
            // itself, so nothing here has to know what apps exist.
            store.shield.applicationCategories = .all(except: tokens.exceptApplications)
            store.shield.webDomainCategories = .all(except: tokens.exceptWebDomains)
        }

        store.shield.webDomains = tokens.webDomains.isEmpty
            ? nil : tokens.webDomains
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

    /// `.notApproved` for both denied and not-determined, because in neither
    /// can anything be held. Anything else — a status this build does not
    /// recognise — is `.unknown`, not `.notApproved`: being unable to read the
    /// answer is not an answer, and treating it as one is what would turn a
    /// slow `AuthorizationCenter` into an accusation.
    var authorization: ShieldAuthorization {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved:                  return .approved
        case .denied, .notDetermined:    return .notApproved
        @unknown default:                return .unknown
        }
    }
}

extension ManagedSettingsStore.Name {
    static let dad = Self("dad")
}
