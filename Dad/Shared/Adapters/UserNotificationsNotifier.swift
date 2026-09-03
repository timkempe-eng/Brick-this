import Foundation
import UserNotifications

/// `Notifying` over UserNotifications — the ten minutes' notice before a
/// scheduled Mode lands.
///
/// The permission is asked for lazily, at the first warning there is actually
/// something to say. Asking at launch, beside the Screen Time prompt, would
/// spend a "not now" on a feature the person has not met yet — and the product
/// works entirely without this one, which is exactly why it must not be a gate.
///
/// Declining is a supported state and not a broken one: `add` fails, nothing is
/// scheduled, and every scheduled Mode still runs. The only thing lost is the
/// warning, which is what was declined.
struct UserNotificationsNotifier: Notifying {

    /// Everything this adapter has ever scheduled shares a prefix, so clearing
    /// ours can never disturb a notification another part of the app adds
    /// later. The same reasoning as `ManagedSettingsStore(named: .dad)`.
    private static let prefix = "warning."

    private let centre = UNUserNotificationCenter.current()

    func setPendingWarning(_ warning: PendingWarning?) {
        guard let warning else { return clearOurs() }

        // Already in the past by the time we got here — a foreground during
        // the last ten minutes before a window. Delivering it now would be a
        // notice about something already happening.
        guard warning.fireAt > Date() else { return clearOurs() }

        centre.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            // Permission can be withdrawn in Settings after a warning was
            // already scheduled. Returning without clearing would leave that
            // one pending, so the *last* warning before somebody turned
            // notifications off would still arrive — which is the one thing a
            // person who just turned them off would find hardest to explain.
            guard granted else { return clearOurs() }
            let content = UNMutableNotificationContent()
            content.title = warning.title
            content.body = warning.body
            // No sound and no badge. A warning is a glance, and a product
            // whose whole argument is that phones interrupt too much should
            // not add a chime to make its point.
            content.interruptionLevel = .passive

            let interval = max(1, warning.fireAt.timeIntervalSinceNow)
            let request = UNNotificationRequest(
                identifier: warning.id,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))

            // Ours cleared inside the callback rather than before the
            // authorization prompt: clearing first would leave nothing pending
            // for however long somebody stares at the permission sheet, and a
            // decline would then have silently removed a warning that was
            // already scheduled and working.
            clearOurs(except: warning.id)
            centre.add(request)
        }
    }

    /// Removes every warning this adapter scheduled, optionally sparing one.
    ///
    /// Sparing rather than remove-then-add, because the identifier is stable
    /// for a given Mode and window: re-registering an unchanged warning
    /// replaces it in place, and dropping it first would open a gap in which
    /// nothing was pending.
    private func clearOurs(except keep: String? = nil) {
        centre.getPendingNotificationRequests { requests in
            let ours = requests.map(\.identifier)
                .filter { $0.hasPrefix(Self.prefix) && $0 != keep }
            guard !ours.isEmpty else { return }
            centre.removePendingNotificationRequests(withIdentifiers: ours)
        }
    }
}
