import Foundation
import ServiceManagement

/// Starts Pier at login through SMAppService, which is the API that also puts an entry in
/// System Settings > General > Login Items, so the setting can be seen and switched off there.
///
/// This replaced a hand-written LaunchAgent. That worked, but it never appeared in Login Items
/// and it pinned a hardcoded bundle path. An ad-hoc signed build can use SMAppService (measured:
/// register() succeeds from .notFound and the status becomes .enabled) as long as the app is in
/// /Applications.
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
        // Errors are ignored deliberately: the status getter is the truth and the toggle
        // re-reads it, so a failure simply leaves the switch where it was.
        if enabled {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
    }

    /// The LaunchAgent this app used to write, before it moved to SMAppService.
    private static var legacyAgentURL: URL {
        let library = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return library
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("app.openware.pier.plist")
    }

    /// Carries the old LaunchAgent setting over to SMAppService, once. If the plist is there the
    /// user had start-at-login on, so it gets registered the new way and the plist removed,
    /// instead of being left behind to start a second copy at login.
    static func migrateFromLegacyAgent() {
        let url = legacyAgentURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", "-w", url.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        try? FileManager.default.removeItem(at: url)
        setEnabled(true)
    }
}
