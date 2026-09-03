import Foundation

/// The composition root: the one place the real adapters are wired to the
/// engine. Everything else — app, extensions, intents — takes `.live`.
extension DadEngine {
    static let live = DadEngine(
        store: UserDefaultsStore.shared,
        shield: ManagedSettingsShield(),
        scheduler: DeviceActivityScheduler(),
        clock: SystemClock(),
        widget: WidgetKitRefresher(),
        usage: DeviceActivityUsageWatcher()
    )
}
