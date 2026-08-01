import AppKit
import PierCore

/// The menu bar icon: every dock, switchable, plus the way into settings.
@MainActor
final class StatusItemController: NSObject {

    private let statusItem: NSStatusItem
    private let manager: DockManager

    var onOpenSettings: ((UUID?) -> Void)?
    var onQuit: (() -> Void)?

    init(manager: DockManager) {
        self.manager = manager
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.stack.fill",
                accessibilityDescription: "Pier"
            )
            button.image?.isTemplate = true
        }
        statusItem.menu = buildMenu()
    }

    func refresh() {
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        for dock in manager.store.docks {
            let entry = NSMenuItem(
                title: dock.name,
                action: #selector(toggleDock(_:)),
                keyEquivalent: ""
            )
            entry.target = self
            entry.representedObject = dock.id
            entry.state = dock.isEnabled ? .on : .off

            let submenu = NSMenu()
            add(to: submenu, dock.isEnabled ? "Hide" : "Show") { [weak self] in
                self?.setEnabled(!dock.isEnabled, for: dock.id)
            }
            if dock.behavior.collapsible {
                add(to: submenu, dock.behavior.collapsed ? "Expand" : "Collapse") { [weak self] in
                    self?.manager.store.update(id: dock.id) { $0.behavior.collapsed.toggle() }
                    self?.manager.refreshAll()
                    self?.refresh()
                }
            }
            add(to: submenu, "Settings…") { [weak self] in self?.onOpenSettings?(dock.id) }
            add(to: submenu, "Duplicate") { [weak self] in
                _ = self?.manager.store.duplicate(id: dock.id)
                self?.manager.rebuild()
                self?.refresh()
            }
            add(to: submenu, "Remove") { [weak self] in
                self?.manager.removeDock(id: dock.id)
                self?.refresh()
            }
            entry.submenu = submenu
            menu.addItem(entry)
        }

        menu.addItem(.separator())

        let newDock = NSMenuItem(title: "New Dock", action: #selector(newDock), keyEquivalent: "n")
        newDock.target = self
        menu.addItem(newDock)

        let settings = NSMenuItem(title: "Pier Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Pier", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func setEnabled(_ enabled: Bool, for id: UUID) {
        manager.store.update(id: id) { $0.isEnabled = enabled }
        manager.rebuild()
        refresh()
    }

    @objc private func toggleDock(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID,
              let dock = manager.store.dock(id: id) else { return }
        setEnabled(!dock.isEnabled, for: id)
    }

    @objc private func newDock() {
        let dock = manager.addDock()
        refresh()
        onOpenSettings?(dock.id)
    }

    @objc private func openSettings() { onOpenSettings?(nil) }
    @objc private func quit() { onQuit?() }

    // MARK: - Menu plumbing

    private final class Block: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
    }

    @objc private func runBlock(_ sender: NSMenuItem) {
        (sender.representedObject as? Block)?.run()
    }

    private func add(to menu: NSMenu, _ title: String, _ action: @escaping () -> Void) {
        let entry = NSMenuItem(title: title, action: #selector(runBlock(_:)), keyEquivalent: "")
        entry.target = self
        entry.representedObject = Block(action)
        menu.addItem(entry)
    }
}

extension StatusItemController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        statusItem.menu = buildMenu()
    }
}
