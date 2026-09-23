import Foundation

/// Starts Pier at login by managing a per-user LaunchAgent.
///
/// SMAppService is the modern API, but it wants a real signing identity. An ad-hoc signed
/// build, which is what this repo produces, reports .notFound and the registration quietly
/// does nothing. A LaunchAgent works however the app is signed, at the cost of the app
/// writing and loading a plist itself.
///
/// The file is the single source of truth for whether this is on, so the setting reflects
/// what is actually happening rather than a stored intention that can drift from it.
enum LaunchAtLogin {
    static let label = "app.openware.pier"

    private static var agentURL: URL {
        let library = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return library
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: agentURL.path)
    }

    static func setEnabled(_ enabled: Bool) {
        if enabled {
            enable()
        } else {
            disable()
        }
    }

    private static func enable() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>Label</key>
        \t<string>\(label)</string>
        \t<key>ProgramArguments</key>
        \t<array>
        \t\t<string>/usr/bin/open</string>
        \t\t<string>\(Bundle.main.bundlePath)</string>
        \t</array>
        \t<key>RunAtLoad</key>
        \t<true/>
        </dict>
        </plist>
        """

        try? FileManager.default.createDirectory(
            at: agentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? plist.write(to: agentURL, atomically: true, encoding: .utf8)
        // load -w is deprecated in favour of bootstrap, but it is the form that works
        // without having to know the user's uid.
        launchctl(["load", "-w", agentURL.path])
    }

    private static func disable() {
        launchctl(["unload", "-w", agentURL.path])
        try? FileManager.default.removeItem(at: agentURL)
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return -1
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
