import Foundation

/// The composition root: the one place the real adapters are wired to the
/// engine. Everything else — app, extensions, intents — takes `.live`.
extension TimEngine {
    static let live = TimEngine(
        store: UserDefaultsStore.shared,
        shield: ManagedSettingsShield(),
        scheduler: DeviceActivityScheduler(),
        clock: SystemClock()
    )
}
