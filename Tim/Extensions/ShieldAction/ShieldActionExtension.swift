import ManagedSettings

/// Handles the two buttons on the shield.
///
/// Primary just closes the app you shouldn't be in. Secondary spends an
/// emergency override — and when the allowance is gone it deliberately does
/// nothing but close, because a button that apologises is still a button you
/// press out of habit.
class ShieldActionExtension: ShieldActionDelegate {

    private func handle(_ action: ShieldAction,
                        completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            completionHandler(.close)
        case .secondaryButtonPressed:
            if TimEngine.live.emergencyUnTim() {
                // The shield is torn down with the rest of the settings, so
                // `.defer` leaves the user looking at the app they opened,
                // now unblocked.
                completionHandler(.defer)
            } else {
                completionHandler(.close)
            }
        @unknown default:
            completionHandler(.close)
        }
    }

    override func handle(action: ShieldAction,
                         for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        handle(action, completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction,
                         for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        handle(action, completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction,
                         for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        handle(action, completionHandler: completionHandler)
    }
}
