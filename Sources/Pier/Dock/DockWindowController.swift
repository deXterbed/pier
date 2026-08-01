import AppKit
import PierCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
protocol DockWindowControllerHost: AnyObject {
    func dockChanged(_ controller: DockWindowController)
    func dockRequestsSettings(_ controller: DockWindowController)
    func dockRequestsRemoval(_ controller: DockWindowController)
    func dockRequestsNewDock()
    /// The screen this dock is pinned to, or nil when that display is unplugged.
    func screen(for dock: Dock) -> NSScreen?
}

/// One dock on screen: its window, its contents, and everything you can do to it.
@MainActor
final class DockWindowController: NSObject {

    let dockID: UUID
    let model: DockViewModel

    private let store: DockStore
    private weak var host: DockWindowControllerHost?

    private let panel: DockPanel
    private let surface: DockSurfaceView
    private let hosting: NSHostingView<DockContentView>

    private var isRevealed = true
    private var hideWork: DispatchWorkItem?
    private var pendingDragIndex: Int?

    init(dock: Dock, store: DockStore, host: DockWindowControllerHost) {
        self.dockID = dock.id
        self.store = store
        self.host = host
        self.model = DockViewModel(dock: dock)

        let windowSize = dock.layout.windowSize(for: dock.items)
        panel = DockPanel(contentRect: NSRect(origin: .zero, size: windowSize))
        surface = DockSurfaceView(frame: NSRect(origin: .zero, size: windowSize))
        hosting = NSHostingView(rootView: DockContentView(model: model))

        super.init()

        hosting.frame = surface.bounds
        hosting.autoresizingMask = [.width, .height]
        surface.addSubview(hosting)
        surface.controller = self
        panel.contentView = surface

        relayout()
    }

    // MARK: - Geometry

    var dock: Dock { model.dock }

    var isVisible: Bool { panel.isVisible }

    var windowFrame: NSRect { panel.frame }

    /// The card's frame on screen — what "is the pointer near the dock" means.
    var cardFrameOnScreen: NSRect {
        let bleed = model.layout.bleed
        return panel.frame.insetBy(dx: bleed, dy: bleed)
    }

    private var cardSize: CGSize {
        dock.behavior.collapsed
            ? model.layout.collapsedCardSize()
            : model.layout.cardSize(for: dock.items)
    }

    /// Re-seats the window for the current contents, placement and screen.
    func relayout() {
        guard let screen = host?.screen(for: dock) else {
            panel.orderOut(nil)
            return
        }

        let bleed = model.layout.bleed
        let card = cardSize
        let cardFrame = dock.placement.frame(contentSize: card, in: screen.visibleFrame)
        let windowFrame = cardFrame.insetBy(dx: -bleed, dy: -bleed)

        surface.cardRect = NSRect(x: bleed, y: bleed, width: card.width, height: card.height)

        if panel.isVisible && isRevealed {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(windowFrame, display: true)
            }
        } else {
            panel.setFrame(windowFrame, display: false)
        }

        if dock.isEnabled && !panel.isVisible {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            isRevealed = true
        }
        if !dock.isEnabled {
            panel.orderOut(nil)
        }
    }

    func refresh(with dock: Dock) {
        model.dock = dock
        relayout()
    }

    func close() {
        hideWork?.cancel()
        panel.orderOut(nil)
    }

    // MARK: - Hiding

    /// Auto-hide slides the dock off its edge; the reveal comes back from the manager,
    /// which watches the pointer.
    func setRevealed(_ revealed: Bool, animated: Bool = true) {
        guard revealed != isRevealed, let screen = host?.screen(for: dock) else { return }
        isRevealed = revealed

        let bleed = model.layout.bleed
        let card = cardSize
        let target = revealed
            ? dock.placement.frame(contentSize: card, in: screen.visibleFrame)
            : dock.placement.hiddenFrame(contentSize: card, in: screen.visibleFrame)
        let frame = target.insetBy(dx: -bleed, dy: -bleed)

        guard animated else {
            panel.setFrame(frame, display: false)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = revealed ? 0.22 : 0.18
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().setFrame(frame, display: true)
        }
    }

    var revealed: Bool { isRevealed }

    func setHiddenForFullscreen(_ hidden: Bool) {
        guard dock.isEnabled else { return }
        if hidden {
            panel.orderOut(nil)
        } else if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    // MARK: - Pointer

    func pointerEntered() {
        hideWork?.cancel()
    }

    func pointerMoved(to point: CGPoint) {
        model.pointer = point
        hideWork?.cancel()
    }

    func pointerLeft() {
        model.pointer = nil
        model.pressedIndex = nil
    }

    func itemIndex(at point: CGPoint) -> Int? {
        guard !dock.behavior.collapsed else { return nil }
        return model.layout.index(at: point, items: dock.items)
    }

    func pressed(index: Int?) {
        model.pressedIndex = index
    }

    // MARK: - Clicking

    func clicked(index: Int) {
        if dock.behavior.collapsed {
            toggleCollapsed()
            return
        }
        guard index < dock.items.count else { return }
        let item = dock.items[index]
        guard item.isInteractive else { return }

        switch item.kind {
        case .app, .file:
            AppCatalog.shared.activate(item)
        case .folder:
            if let url = item.url { NSWorkspace.shared.open(url) }
        case .widget:
            handleWidgetClick(item)
        }
    }

    private func handleWidgetClick(_ item: DockItem) {
        switch item.widget {
        case .trash:
            NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash"))
        case .finder:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        case .clock:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
        default:
            break
        }
    }

    func toggleCollapsed() {
        store.update(id: dockID) { $0.behavior.collapsed.toggle() }
        host?.dockChanged(self)
    }

    // MARK: - Dragging tiles

    func dragItem(at index: Int, to point: CGPoint) {
        model.draggingIndex = index
        pendingDragIndex = index
        model.insertionIndex = model.layout.insertionIndex(at: point, items: dock.items)
    }

    func finishItemDrag(at point: CGPoint, inside: Bool) {
        defer {
            model.draggingIndex = nil
            model.insertionIndex = nil
            pendingDragIndex = nil
        }
        guard let from = pendingDragIndex, from < dock.items.count else { return }
        let item = dock.items[from]

        guard inside else {
            // Dragged off the dock and let go — the macOS gesture for "remove this".
            store.update(id: dockID) { $0.remove(id: item.id) }
            host?.dockChanged(self)
            return
        }

        let destination = model.layout.insertionIndex(at: point, items: dock.items)
        store.update(id: dockID) { $0.move(id: item.id, to: destination) }
        host?.dockChanged(self)
    }

    /// Dragging the dock's background moves the whole dock; where it lands decides
    /// whether it snaps to an edge or floats.
    func dragWindow(with event: NSEvent) {
        panel.performDrag(with: event)

        guard let screen = host?.screen(for: dock) else { return }
        let bleed = model.layout.bleed
        let cardFrame = panel.frame.insetBy(dx: bleed, dy: bleed)
        let placement = DockPlacement.resolving(
            droppedFrame: cardFrame,
            in: screen.visibleFrame,
            margin: dock.placement.margin,
            orientation: dock.placement.orientation
        )
        store.update(id: dockID) { $0.placement = placement }
        host?.dockChanged(self)
    }

    // MARK: - Drops

    func dropEntered() {
        model.isDropTargeted = true
    }

    func dropMoved(to point: CGPoint) {
        model.isDropTargeted = true
        if let index = itemIndex(at: point), dock.items[index].acceptsDrops {
            model.dropTargetIndex = index
            model.insertionIndex = nil
        } else {
            model.dropTargetIndex = nil
            model.insertionIndex = model.layout.insertionIndex(at: point, items: dock.items)
        }
    }

    func dropExited() {
        model.isDropTargeted = false
        model.dropTargetIndex = nil
        model.insertionIndex = nil
    }

    func accept(_ info: NSDraggingInfo, at point: CGPoint) -> Bool {
        let targetIndex = model.dropTargetIndex
        let insertion = model.insertionIndex
        dropExited()

        let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        guard !urls.isEmpty else { return false }

        // Onto an app or folder: hand the files over to it.
        if let targetIndex, targetIndex < dock.items.count {
            let target = dock.items[targetIndex]
            if target.widget == .trash {
                AppCatalog.shared.moveToTrash(urls)
            } else {
                AppCatalog.shared.open(urls, with: target)
            }
            return true
        }

        // Onto the dock itself: these become new tiles.
        let items = urls.map { url -> DockItem in
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if url.pathExtension == "app" {
                return .app(at: url, bundleIdentifier: AppCatalog.shared.bundleIdentifier(forAppAt: url))
            }
            return isDirectory.boolValue ? .folder(at: url) : .file(at: url)
        }

        store.update(id: dockID) { $0.add(contentsOf: items, at: insertion) }
        host?.dockChanged(self)
        return true
    }

    // MARK: - Menus

    func contextMenu(forItemAt index: Int?) -> NSMenu {
        let menu = NSMenu()

        if let index, index < dock.items.count {
            let item = dock.items[index]
            addItemEntries(to: menu, for: item)
            menu.addItem(.separator())
        }

        // A list of what's installed, rather than a file picker — an accessory app's
        // modal panels have a habit of opening behind whatever you were looking at.
        let appsMenu = NSMenu()
        for url in InstalledApps.all() {
            let entry = NSMenuItem(
                title: url.deletingPathExtension().lastPathComponent,
                action: #selector(runBlock(_:)),
                keyEquivalent: ""
            )
            entry.target = self
            entry.representedObject = Block { [weak self] in
                self?.addItems([InstalledApps.item(for: url)])
            }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            entry.image = icon
            appsMenu.addItem(entry)
        }
        appsMenu.addItem(.separator())
        add(to: appsMenu, "Choose…", "folder") { [weak self] in self?.addApp() }

        let appsItem = NSMenuItem(title: "Add App", action: nil, keyEquivalent: "")
        appsItem.image = NSImage(systemSymbolName: "plus.app", accessibilityDescription: nil)
        appsItem.submenu = appsMenu
        menu.addItem(appsItem)

        add(to: menu, "Add Folder…", "folder.badge.plus") { [weak self] in self?.addFolder() }

        let widgets = NSMenu()
        for kind in WidgetKind.allCases {
            let entry = NSMenuItem(title: kind.title, action: #selector(runBlock(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = Block { [weak self] in self?.addWidget(kind) }
            widgets.addItem(entry)
        }
        let widgetItem = NSMenuItem(title: "Add Widget", action: nil, keyEquivalent: "")
        widgetItem.submenu = widgets
        menu.addItem(widgetItem)

        menu.addItem(.separator())

        if dock.behavior.collapsible {
            add(to: menu, dock.behavior.collapsed ? "Expand" : "Collapse", "arrow.down.right.and.arrow.up.left") {
                [weak self] in self?.toggleCollapsed()
            }
        }
        add(to: menu, "Dock Settings…", "slider.horizontal.3") { [weak self] in
            guard let self else { return }
            self.host?.dockRequestsSettings(self)
        }
        add(to: menu, "New Dock", "rectangle.stack.badge.plus") { [weak self] in
            self?.host?.dockRequestsNewDock()
        }
        add(to: menu, "Remove This Dock", "trash") { [weak self] in
            guard let self else { return }
            self.host?.dockRequestsRemoval(self)
        }
        return menu
    }

    private func addItemEntries(to menu: NSMenu, for item: DockItem) {
        if item.isInteractive {
            add(to: menu, "Open", "arrow.up.forward.app") {
                AppCatalog.shared.activate(item)
            }
        }
        if item.url != nil {
            add(to: menu, "Show in Finder", "folder") {
                guard let url = item.url else { return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
        if item.kind == .app, AppCatalog.shared.isRunning(item) {
            add(to: menu, "Quit", "xmark.circle") { AppCatalog.shared.quit(item) }
            add(to: menu, "Force Quit", "exclamationmark.octagon") {
                AppCatalog.shared.quit(item, force: true)
            }
        }
        if item.kind != .widget {
            add(to: menu, "Change Icon…", "photo") { [weak self] in self?.changeIcon(of: item) }
            if item.customIconPath != nil {
                add(to: menu, "Reset Icon", "arrow.uturn.backward") { [weak self] in
                    self?.store.update(id: self?.dockID ?? UUID()) { dock in
                        guard let index = dock.items.firstIndex(where: { $0.id == item.id }) else { return }
                        dock.items[index].customIconPath = nil
                    }
                    AppCatalog.shared.forgetIcons()
                    self.map { $0.host?.dockChanged($0) }
                }
            }
        }
        add(to: menu, "Remove from Dock", "minus.circle") { [weak self] in
            guard let self else { return }
            self.store.update(id: self.dockID) { $0.remove(id: item.id) }
            self.host?.dockChanged(self)
        }
    }

    // MARK: - Adding things

    func addItems(_ items: [DockItem]) {
        guard !items.isEmpty else { return }
        store.update(id: dockID) { $0.add(contentsOf: items) }
        host?.dockChanged(self)
    }

    private func addApp() {
        addItems(OpenPanels.chooseApps().map(InstalledApps.item(for:)))
    }

    private func addFolder() {
        addItems(OpenPanels.chooseFolders().map(DockItem.folder(at:)))
    }

    private func addWidget(_ kind: WidgetKind) {
        addItems([.widget(kind)])
    }

    private func changeIcon(of item: DockItem) {
        guard let url = OpenPanels.chooseImage() else { return }
        store.update(id: dockID) { dock in
            guard let index = dock.items.firstIndex(where: { $0.id == item.id }) else { return }
            dock.items[index].customIconPath = url.path
        }
        AppCatalog.shared.forgetIcons()
        host?.dockChanged(self)
    }

    // MARK: - Menu plumbing

    private final class Block: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
    }

    @objc private func runBlock(_ sender: NSMenuItem) {
        (sender.representedObject as? Block)?.run()
    }

    private func add(to menu: NSMenu, _ title: String, _ symbol: String, _ action: @escaping () -> Void) {
        let entry = NSMenuItem(title: title, action: #selector(runBlock(_:)), keyEquivalent: "")
        entry.target = self
        entry.representedObject = Block(action)
        entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        menu.addItem(entry)
    }
}
