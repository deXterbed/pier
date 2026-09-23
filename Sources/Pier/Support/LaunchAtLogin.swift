import Foundation
import ServiceManagement

/// Starts Pier at login through SMAppService, the API that also puts an entry in
/// System Settings > General > Login Items, so the setting can be seen and switched off there.
///
/// A hand-written LaunchAgent works too, but it never appears in Login Items and pins a
/// hardcoded bundle path. An ad-hoc signed build can use SMAppService as long as the app lives
/// in /Applications: measured, register() reports .notFound before and .enabled after.
enum LaunchAtLogin {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    /// requiresApproval counts as on: the app is registered and macOS is waiting for the user
    /// to allow it in Login Items.
    static var isEnabled: Bool {
        switch status {
        case .enabled, .requiresApproval: return true
        default: return false
        }
    }

    static func setEnabled(_ enabled: Bool) {
        // Errors are ignored deliberately: the status getter is the truth and the menu item
        // re-reads it, so a failure simply leaves the switch where it was.
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }
}
