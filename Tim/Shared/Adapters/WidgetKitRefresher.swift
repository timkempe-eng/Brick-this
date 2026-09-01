import WidgetKit

/// `WidgetRefreshing` over WidgetKit.
///
/// WidgetCenter is callable from app extensions as well as the app, which is
/// what lets a session ended by the shield's emergency button or by the
/// DeviceActivity monitor still clear the Lock Screen.
struct WidgetKitRefresher: WidgetRefreshing {
    func reload() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
