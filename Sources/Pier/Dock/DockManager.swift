import AppKit
import PierCore

/// Owns every dock: which screen each one is on, when they hide, and what happens when a
/// monitor is plugged in or pulled out.
@MainActor
final class DockManager: NSObject, DockWindowControllerHost, ObservableObject {

    let store: DockStore
    let prefs: Preferences

    @Published private(set) var controllers: [DockWindowController] = []
    var onChange: (() -> Void)?
    var onRequestSettings: ((UUID?) -> Void)?

    private let pointer = PointerWatcher()
    private var hideWork: [UUID: DispatchWorkItem] = [:]
    private var fullscreenTimer: Timer?

    init(store: DockStore, prefs: Preferences) {
        self.store = store
        self.prefs = prefs
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        store.load()
        if store.docks.isEmpty {
            store.add(DockManager.starterDock())
        }
        rebuild()

        pointer.onMove = { [weak self] location in
            self?.pointerMoved(to: location)
        }
        pointer.start()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }

        // The multi-display rule can be switched off, which changes whether each dock has a
        // screen to sit on at all.
        NotificationCenter.default.addObserver(
            forName: .pierPreferencesChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }

        // Full-screen state has no notification worth subscribing to, so it's sampled.
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateFullscreenVisibility() }
        }
        RunLoop.main.add(timer, forMode: .common)
        fullscreenTimer = timer
    }

    func stop() {
        pointer.stop()
        fullscreenTimer?.invalidate()
        hideWork.values.forEach { $0.cancel() }
        controllers.forEach { $0.close() }
    }

    /// A first dock with something already in it — an empty dock in a corner explains
    /// nothing about what this app does.
    static func starterDock() -> Dock {
        var dock = Dock(name: "Dock 1")
        dock.placement = DockPlacement(edge: .bottom, alignment: .center)
        dock.behavior.hideOnFullscreen = true

        let candidates = [
            "/System/Applications/Launchpad.app",
            "/System/Library/CoreServices/Finder.app",
            "/System/Applications/System Settings.app",
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            dock.add(.app(at: URL(fileURLWithPath: path)))
        }
        dock.add(.widget(.divider))
        dock.add(.widget(.trash))
        return dock
    }

    // MARK: - Building

    func rebuild() {
        let wanted = store.docks
        var kept: [DockWindowController] = []

        for dock in wanted {
            if let existing = controllers.first(where: { $0.dockID == dock.id }) {
                existing.refresh(with: dock)
                kept.append(existing)
            } else {
                kept.append(DockWindowController(dock: dock, store: store, host: self))
            }
        }
        for gone in controllers where !wanted.contains(where: { $0.id == gone.dockID }) {
            gone.close()
        }
        controllers = kept
        applyAutoHide(initial: true)
        onChange?()
    }

    func refreshAll() {
        for controller in controllers {
            if let dock = store.dock(id: controller.dockID) {
                controller.refresh(with: dock)
            }
        }
        onChange?()
    }

    @discardableResult
    func addDock() -> Dock {
        var dock = DockManager.starterDock()
        dock.name = "Dock \(store.docks.count + 1)"
        dock.items = []
        // A new dock goes somewhere the last one isn't.
        let used = Set(store.docks.map(\.placement.edge))
        dock.placement.edge = [.bottom, .trailing, .leading, .top].first { !used.contains($0) } ?? .trailing
        let added = store.add(dock)
        rebuild()
        return added
    }

    func removeDock(id: UUID) {
        store.remove(id: id)
        rebuild()
    }

    // MARK: - Screens

    /// Every connected display, in the identity a dock stores.
    func connectedScreens() -> [(screen: NSScreen, identity: ScreenIdentity)] {
        NSScreen.screens.map { ($0, $0.pierIdentity) }
    }

    func screen(for dock: Dock) -> NSScreen? {
        // Optionally stand down on a single display, where Pier has nothing to add over the
        // system Dock. Returning nil reuses the existing unplugged-monitor path, which
        // already hides the panel.
        if prefs.onlyWithMultipleDisplays, NSScreen.screens.count < 2 { return nil }
        let connected = connectedScreens()
        guard let wanted = dock.screen else { return NSScreen.main ?? connected.first?.screen }
        guard let resolved = ScreenIdentity.resolve(
            wanted: wanted,
            connected: connected.map(\.identity)
        ) else {
            // Its display is gone, so the dock goes with it rather than piling onto
            // whatever screen is left.
            return nil
        }
        return connected.first { $0.identity == resolved }?.screen
    }

    // MARK: - Auto-hide

    private func applyAutoHide(initial: Bool) {
        for controller in controllers {
            let dock = controller.dock
            if dock.behavior.autoHide {
                if initial { controller.setRevealed(false, animated: false) }
            } else {
                controller.setRevealed(true, animated: !initial)
            }
        }
    }

    private func pointerMoved(to location: NSPoint) {
        for controller in controllers {
            let dock = controller.dock
            guard dock.behavior.autoHide, dock.isEnabled else { continue }
            guard let screen = screen(for: dock) else { continue }

            let card = controller.cardFrameOnScreen
            let trigger = revealZone(for: dock, card: card, in: screen.visibleFrame)

            if trigger.contains(location) || card.insetBy(dx: -8, dy: -8).contains(location) {
                hideWork[dock.id]?.cancel()
                hideWork[dock.id] = nil
                controller.setRevealed(true)
            } else if controller.revealed, hideWork[dock.id] == nil {
                scheduleHide(controller, after: dock.behavior.hideDelay)
            }
        }
    }

    /// A band along the dock's edge, so you can reach a hidden dock by shoving the
    /// pointer at the side of the screen it lives on.
    private func revealZone(for dock: Dock, card: NSRect, in visible: NSRect) -> NSRect {
        let depth: CGFloat = 4
        switch dock.placement.edge {
        case .bottom:
            return NSRect(x: card.minX, y: visible.minY, width: card.width, height: depth)
        case .top:
            return NSRect(x: card.minX, y: visible.maxY - depth, width: card.width, height: depth)
        case .leading:
            return NSRect(x: visible.minX, y: card.minY, width: depth, height: card.height)
        case .trailing:
            return NSRect(x: visible.maxX - depth, y: card.minY, width: depth, height: card.height)
        case .floating:
            return card.insetBy(dx: -14, dy: -14)
        }
    }

    private func scheduleHide(_ controller: DockWindowController, after delay: TimeInterval) {
        let id = controller.dockID
        let work = DispatchWorkItem { [weak self, weak controller] in
            guard let self, let controller else { return }
            controller.setRevealed(false)
            self.hideWork[id] = nil
        }
        hideWork[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(delay, 0.1), execute: work)
    }

    // MARK: - Fullscreen

    private func updateFullscreenVisibility() {
        let covered = FullscreenWatcher.screensWithFullscreenWindows()
        for controller in controllers {
            let dock = controller.dock
            guard let screen = screen(for: dock) else {
                // Nothing to sit on (unplugged, or fewer than two displays): leave it
                // hidden rather than forcing the panel back on screen.
                continue
            }
            guard dock.behavior.hideOnFullscreen else {
                controller.setHiddenForFullscreen(false)
                continue
            }
            controller.setHiddenForFullscreen(covered.contains(screen.pierIdentity))
        }
    }

    // MARK: - DockWindowControllerHost

    func dockChanged(_ controller: DockWindowController) {
        if let dock = store.dock(id: controller.dockID) {
            controller.refresh(with: dock)
        }
        onChange?()
    }

    func dockRequestsSettings(_ controller: DockWindowController) {
        onRequestSettings?(controller.dockID)
    }

    func dockRequestsRemoval(_ controller: DockWindowController) {
        removeDock(id: controller.dockID)
    }

    func dockRequestsNewDock() {
        addDock()
    }
}

extension NSScreen {
    /// The identity a dock stores to find this display again later.
    var pierIdentity: ScreenIdentity {
        let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let displayID = number.map { CGDirectDisplayID($0.uint32Value) }
        let uuid = displayID
            .flatMap { CGDisplayCreateUUIDFromDisplayID($0)?.takeRetainedValue() }
            .map { CFUUIDCreateString(nil, $0) as String }

        return ScreenIdentity(
            uuid: uuid,
            name: localizedName,
            width: Int(frame.width),
            height: Int(frame.height),
            wasMain: self == NSScreen.main
        )
    }
}
