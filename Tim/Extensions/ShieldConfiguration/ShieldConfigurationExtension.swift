import ManagedSettings
import ManagedSettingsUI
import UIKit

/// The screen iOS draws over a blocked app. This is the only place the user
/// meets the verb while they are actually being stopped, so the copy matters
/// more here than anywhere else in the app.
///
/// This runs in its own process, launched by the system on demand, with a
/// tight memory budget. It reads the active session out of the App Group and
/// does nothing else — no networking, no heavy work.
class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    private func shield() -> ShieldConfiguration {
        let modeName = TimStore.shared.activeSession?.modeName ?? "focus"

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: UIColor.black.withAlphaComponent(0.55),
            icon: UIImage(systemName: "lock.iphone"),
            title: ShieldConfiguration.Label(text: Vocab.shieldTitle, color: .white),
            subtitle: ShieldConfiguration.Label(
                text: Vocab.shieldSubtitle(mode: modeName),
                color: .white.withAlphaComponent(0.75)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(text: Vocab.shieldPrimaryButton, color: .black),
            primaryButtonBackgroundColor: .white,
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: Vocab.shieldSecondaryButton,
                color: .white.withAlphaComponent(0.6)
            )
        )
    }

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        shield()
    }

    override func configuration(shielding application: Application,
                                in category: ActivityCategory) -> ShieldConfiguration {
        shield()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        shield()
    }

    override func configuration(shielding webDomain: WebDomain,
                                in category: ActivityCategory) -> ShieldConfiguration {
        shield()
    }
}
