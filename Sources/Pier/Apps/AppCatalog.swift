import AppKit
import PierCore
import SwiftUI

/// Everything Pier knows about the apps on this Mac: their icons, whether they're
/// running, and how to start or focus them.
@MainActor
final class AppCatalog: ObservableObject {
    static let shared = AppCatalog()

    /// Bundle identifiers of everything currently running, so tiles can show a dot.
    @Published private(set) var runningBundleIDs: Set<String> = []
    /// Bundle identifier of the app in front, for a brighter dot.
    @Published private(set) var frontmostBundleID: String?
    /// Items mid-launch, so their icon can bounce.
    @Published private(set) var launching: Set<UUID> = []

    private var iconCache: [String: NSImage] = [:]

    private init() {
        refreshRunning()

        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
        ] {
            center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshRunning() }
            }
        }
    }

    private func refreshRunning() {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        runningBundleIDs = Set(apps.compactMap(\.bundleIdentifier))
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    // MARK: - Identity

    func bundleIdentifier(forAppAt url: URL) -> String? {
        Bundle(url: url)?.bundleIdentifier
    }

    func isRunning(_ item: DockItem) -> Bool {
        guard item.kind == .app else { return false }
        if let bundleID = item.bundleIdentifier { return runningBundleIDs.contains(bundleID) }
        guard let url = item.url, let resolved = bundleIdentifier(forAppAt: url) else { return false }
        return runningBundleIDs.contains(resolved)
    }

    func isFrontmost(_ item: DockItem) -> Bool {
        guard let bundleID = item.bundleIdentifier else { return false }
        return frontmostBundleID == bundleID
    }

    // MARK: - Icons

    func icon(for item: DockItem, size: CGFloat) -> NSImage? {
        if let custom = item.customIconURL, let image = cachedImage(at: custom, size: size) {
            return image
        }
        switch item.kind {
        case .app, .folder, .file:
            guard let path = item.path else { return nil }
            return cachedSystemIcon(path: path, size: size)
        case .widget:
            return nil
        }
    }

    private func cachedImage(at url: URL, size: CGFloat) -> NSImage? {
        let key = "custom:\(url.path)@\(Int(size))"
        if let hit = iconCache[key] { return hit }
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: size, height: size)
        iconCache[key] = image
        return image
    }

    private func cachedSystemIcon(path: String, size: CGFloat) -> NSImage? {
        let key = "file:\(path)@\(Int(size))"
        if let hit = iconCache[key] { return hit }
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: size, height: size)
        iconCache[key] = icon
        return icon
    }

    func forgetIcons() {
        iconCache.removeAll()
    }

    // MARK: - Doing things

    /// Click behaviour: launch it, or bring it forward if it's already up.
    func activate(_ item: DockItem) {
        guard let url = item.url else { return }

        if item.kind == .app,
           let bundleID = item.bundleIdentifier ?? bundleIdentifier(forAppAt: url),
           let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .first(where: { $0.activationPolicy == .regular }) {
            running.activate(options: [.activateAllWindows])
            return
        }

        markLaunching(item)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(url, configuration: configuration) { _, _ in }
    }

    /// Dropping files on an app icon opens them with that app; on a folder, moves them in.
    func open(_ urls: [URL], with item: DockItem) {
        guard let target = item.url, !urls.isEmpty else { return }

        switch item.kind {
        case .app:
            markLaunching(item)
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open(urls, withApplicationAt: target, configuration: configuration) { _, _ in }
        case .folder:
            for url in urls {
                let destination = uniqueDestination(for: url, in: target)
                try? FileManager.default.moveItem(at: url, to: destination)
            }
        case .file, .widget:
            break
        }
    }

    func moveToTrash(_ urls: [URL]) {
        for url in urls {
            NSWorkspace.shared.recycle([url]) { _, _ in }
        }
    }

    func quit(_ item: DockItem, force: Bool = false) {
        guard let bundleID = item.bundleIdentifier ?? item.url.flatMap(bundleIdentifier(forAppAt:))
        else { return }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            _ = force ? app.forceTerminate() : app.terminate()
        }
    }

    private func uniqueDestination(for source: URL, in folder: URL) -> URL {
        var destination = folder.appendingPathComponent(source.lastPathComponent)
        var attempt = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            let base = source.deletingPathExtension().lastPathComponent
            let ext = source.pathExtension
            let name = ext.isEmpty ? "\(base) \(attempt)" : "\(base) \(attempt).\(ext)"
            destination = folder.appendingPathComponent(name)
            attempt += 1
        }
        return destination
    }

    private func markLaunching(_ item: DockItem) {
        launching.insert(item.id)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            self?.launching.remove(item.id)
        }
    }
}

/// Reads the macOS Dock's own contents so a Pier dock can mirror it.
enum SystemDockReader {
    static func items() -> [DockItem] {
        guard let defaults = UserDefaults(suiteName: SystemDock.defaultsDomain) else { return [] }
        let apps = defaults.array(forKey: "persistent-apps") ?? []
        let others = defaults.array(forKey: "persistent-others") ?? []
        let urls = SystemDock.urls(fromPersistentEntries: apps)
            + SystemDock.urls(fromPersistentEntries: others)
        return SystemDock.items(from: urls)
    }

    /// Running apps that aren't already on the dock — the "show what's open" option.
    @MainActor
    static func runningItems(excluding existing: [DockItem]) -> [DockItem] {
        let known = Set(existing.compactMap(\.bundleIdentifier))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> DockItem? in
                guard let url = app.bundleURL, let bundleID = app.bundleIdentifier,
                      !known.contains(bundleID)
                else { return nil }
                return .app(at: url, bundleIdentifier: bundleID, title: app.localizedName)
            }
    }
}
