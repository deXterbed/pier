import AppKit
import PierCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let prefs = Preferences.shared
    private lazy var store = DockStore()
    private lazy var manager = DockManager(store: store, prefs: prefs)
    private lazy var settings = SettingsWindowController(manager: manager)
    private lazy var statusItem = StatusItemController(manager: manager)

    /// Everything above is lazy: without this, an early exit would build a fresh empty
    /// store on the way out and save it over the real docks.
    private var didStart = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let directory = Self.previewDirectory() {
            Task {
                await PreviewRenderer.run(directory: directory)
                NSApp.terminate(nil)
            }
            return
        }

        manager.onChange = { [weak self] in self?.statusItem.refresh() }
        manager.onRequestSettings = { [weak self] id in self?.settings.show(selecting: id) }
        manager.start()
        didStart = true

        statusItem.onOpenSettings = { [weak self] id in self?.settings.show(selecting: id) }
        statusItem.onQuit = { NSApp.terminate(nil) }
        statusItem.refresh()

        installMainMenu()

        if !prefs.confirmedFirstRun {
            prefs.confirmedFirstRun = true
            settings.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard didStart else { return }
        manager.stop()
        store.save()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()

        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Pier",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        appItem.submenu = appMenu
        main.addItem(appItem)
        NSApp.mainMenu = main
    }

    @objc private func openSettings() {
        settings.show()
    }

    private static func previewDirectory() -> String? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--render-preview"),
              arguments.index(after: flag) < arguments.endIndex
        else { return nil }
        return arguments[arguments.index(after: flag)]
    }
}
