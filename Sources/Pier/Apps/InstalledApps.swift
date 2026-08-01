import AppKit
import PierCore

/// The applications on this Mac, so a dock can be filled from a menu instead of a file
/// picker. Scanned once and reused — the list changes about as often as you install
/// something, and rescanning on every right-click would be silly.
@MainActor
enum InstalledApps {

    private static var cache: [URL] = []

    private static let searchPaths = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
    ]

    static func all(refresh: Bool = false) -> [URL] {
        if !refresh, !cache.isEmpty { return cache }

        var found: [URL] = []
        var seen: Set<String> = []

        for path in searchPaths {
            let directory = URL(fileURLWithPath: path)
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries where entry.pathExtension == "app" {
                let name = entry.lastPathComponent
                guard !seen.contains(name) else { continue }
                seen.insert(name)
                found.append(entry)
            }
        }

        cache = found.sorted {
            $0.deletingPathExtension().lastPathComponent
                .localizedCaseInsensitiveCompare($1.deletingPathExtension().lastPathComponent)
                == .orderedAscending
        }
        return cache
    }

    static func item(for url: URL) -> DockItem {
        .app(at: url, bundleIdentifier: AppCatalog.shared.bundleIdentifier(forAppAt: url))
    }
}

/// Open panels, run so they actually come to the front.
///
/// Pier is an accessory app, and a modal panel opened by one routinely appears behind
/// whatever you were looking at — which reads exactly like the menu item did nothing.
/// Becoming a regular app for the duration fixes it.
@MainActor
enum OpenPanels {

    static func chooseApps() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Add"
        panel.message = "Pick one or more applications."
        return run(panel)
    }

    static func chooseFolders() -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Pick one or more folders."
        return run(panel)
    }

    static func chooseImage() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Use Icon"
        return run(panel).first
    }

    private static func run(_ panel: NSOpenPanel) -> [URL] {
        let previous = NSApp.activationPolicy()
        if previous != .regular { NSApp.setActivationPolicy(.regular) }
        NSApp.activate(ignoringOtherApps: true)

        panel.level = .modalPanel
        panel.makeKeyAndOrderFront(nil)
        let response = panel.runModal()

        if previous != .regular { NSApp.setActivationPolicy(previous) }
        return response == .OK ? panel.urls : []
    }
}
