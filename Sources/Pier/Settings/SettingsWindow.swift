import AppKit
import PierCore
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let manager: DockManager

    init(manager: DockManager) {
        self.manager = manager
    }

    func show(selecting dockID: UUID? = nil) {
        if window == nil {
            let hosting = NSHostingController(
                rootView: SettingsView(manager: manager, initialSelection: dockID)
            )
            let window = NSWindow(contentViewController: hosting)
            window.title = "Pier"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.setContentSize(NSSize(width: 760, height: 560))
            window.center()
            window.delegate = self
            window.isReleasedWhenClosed = false
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        // Back to a menu-bar app: the settings window is the only reason to be in the
        // Dock or the app switcher at all.
        NSApp.setActivationPolicy(.accessory)
    }
}

struct SettingsView: View {
    @ObservedObject var manager: DockManager
    @State private var selection: UUID?

    init(manager: DockManager, initialSelection: UUID?) {
        self.manager = manager
        _selection = State(initialValue: initialSelection ?? manager.store.docks.first?.id)
    }

    private var docks: [Dock] { manager.store.docks }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Docks") {
                    ForEach(docks) { dock in
                        DockRow(dock: dock, manager: manager).tag(dock.id)
                    }
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 6) {
                    Button {
                        selection = manager.addDock().id
                    } label: {
                        Label("New Dock", systemImage: "plus")
                    }
                    Spacer()
                    Button {
                        guard let selection else { return }
                        manager.removeDock(id: selection)
                        self.selection = manager.store.docks.first?.id
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selection == nil || docks.count <= 1)
                }
                .buttonStyle(.borderless)
                .padding(10)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            if let selection, let dock = docks.first(where: { $0.id == selection }) {
                DockEditor(dock: dock, manager: manager)
                    .id(dock.id)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 34, weight: .light))
                    Text("No dock selected").font(.system(size: 15, weight: .medium))
                    Text("Pick a dock on the left, or make a new one.")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}

private struct DockRow: View {
    let dock: Dock
    @ObservedObject var manager: DockManager

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: dock.placement.orientation == .vertical
                ? "rectangle.portrait"
                : "rectangle")
                .foregroundStyle(dock.isEnabled ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(dock.name).font(.system(size: 12.5, weight: .medium))
                Text("\(dock.items.count) item\(dock.items.count == 1 ? "" : "s") · \(dock.placement.edge.displayName)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Editor

private struct DockEditor: View {
    let dock: Dock
    @ObservedObject var manager: DockManager

    private var store: DockStore { manager.store }

    var body: some View {
        Form {
            Section("Dock") {
                LabeledContent("Name") {
                    TextField("", text: binding(\.name))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
                Toggle("Show this dock", isOn: binding(\.isEnabled))
                LabeledContent("Screen") {
                    Picker("", selection: screenBinding) {
                        Text("Wherever the pointer's main screen is").tag(ScreenIdentity?.none)
                        ForEach(manager.connectedScreens(), id: \.identity) { entry in
                            Text("\(entry.identity.displayName) · \(entry.identity.resolution)")
                                .tag(ScreenIdentity?.some(entry.identity))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 300)
                }
            }

            Section("Position") {
                Picker("Edge", selection: binding(\.placement.edge)) {
                    ForEach(DockEdge.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                if dock.placement.edge != .floating {
                    Picker("Align", selection: binding(\.placement.alignment)) {
                        ForEach(DockAlignment.allCases, id: \.self) {
                            Text($0.displayName(vertical: dock.placement.edge.isVertical)).tag($0)
                        }
                    }
                } else {
                    Picker("Orientation", selection: binding(\.placement.floatingOrientation)) {
                        Text("Horizontal").tag(DockOrientation.horizontal)
                        Text("Vertical").tag(DockOrientation.vertical)
                    }
                }
                slider("Distance from edge", binding(\.placement.margin), 0...80, unit: "pt")
                Text("You can also just drag a dock where you want it — drop it near an edge to snap.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Section("Look") {
                slider("Icon size", binding(\.appearance.iconSize), 20...128, unit: "pt")
                slider("Spacing", binding(\.appearance.spacing), 0...40, unit: "pt")
                slider("Padding", binding(\.appearance.padding), 0...40, unit: "pt")
                slider("Corner radius", binding(\.appearance.cornerRadius), 0...60, unit: "pt")
                slider("Magnification", binding(\.appearance.magnification), 0...1)
                slider("Opacity", binding(\.appearance.opacity), 0.15...1)
                Picker("Background", selection: binding(\.appearance.material)) {
                    ForEach(DockMaterial.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                LabeledContent("Tint") {
                    HStack(spacing: 8) {
                        ColorPicker("", selection: tintBinding, supportsOpacity: false)
                            .labelsHidden()
                        if !dock.appearance.tintHex.isEmpty {
                            Button("Clear") { update { $0.appearance.tintHex = "" } }
                                .buttonStyle(.borderless)
                                .font(.system(size: 11))
                        }
                    }
                }
                slider("Tint strength", binding(\.appearance.tintStrength), 0...1)
                slider("Border", binding(\.appearance.borderOpacity), 0...1)
                Toggle("Drop shadow", isOn: binding(\.appearance.shadow))
                Toggle("Show names on hover", isOn: binding(\.appearance.showLabels))
                Toggle("Show a dot under running apps", isOn: binding(\.appearance.showRunningIndicators))
            }

            Section("Behaviour") {
                Toggle("Hide until I reach for it", isOn: binding(\.behavior.autoHide))
                slider("Hide after", binding(\.behavior.hideDelay), 0.1...3, unit: "s")
                    .disabled(!dock.behavior.autoHide)
                Toggle("Hide when an app goes full screen", isOn: binding(\.behavior.hideOnFullscreen))
                Toggle("Allow collapsing to a button", isOn: binding(\.behavior.collapsible))
                Toggle("Mirror the macOS Dock's contents", isOn: mirrorBinding)
                Toggle("Also show apps that are running", isOn: runningBinding)
            }

            Section("Contents") {
                if dock.items.isEmpty {
                    Text("Empty. Drag apps, folders or files straight onto the dock, or right-click it.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(dock.items) { item in
                        HStack(spacing: 9) {
                            ItemThumbnail(item: item)
                            Text(item.title).font(.system(size: 12))
                            Spacer()
                            Button {
                                update { $0.remove(id: item.id) }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Bindings

    private func update(_ body: @escaping (inout Dock) -> Void) {
        store.update(id: dock.id, body)
        manager.refreshAll()
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Dock, Value>) -> Binding<Value> {
        Binding(
            get: { store.dock(id: dock.id)?[keyPath: keyPath] ?? dock[keyPath: keyPath] },
            set: { value in update { $0[keyPath: keyPath] = value } }
        )
    }

    private var screenBinding: Binding<ScreenIdentity?> {
        Binding(
            get: { store.dock(id: dock.id)?.screen },
            set: { value in update { $0.screen = value } }
        )
    }

    private var tintBinding: Binding<Color> {
        Binding(
            get: { Color(hex: dock.appearance.tintHex) ?? .accentColor },
            set: { value in update { $0.appearance.tintHex = value.hexString } }
        )
    }

    /// Mirroring replaces the dock's contents there and then, so it's an action as much
    /// as a setting — the icons have to appear the moment it's switched on.
    private var mirrorBinding: Binding<Bool> {
        Binding(
            get: { dock.behavior.mirrorsSystemDock },
            set: { value in
                update {
                    $0.behavior.mirrorsSystemDock = value
                    if value { $0.items = SystemDockReader.items() }
                }
            }
        )
    }

    private var runningBinding: Binding<Bool> {
        Binding(
            get: { dock.behavior.showsRunningApps },
            set: { value in
                update { dock in
                    dock.behavior.showsRunningApps = value
                    if value {
                        dock.add(contentsOf: SystemDockReader.runningItems(excluding: dock.items))
                    }
                }
            }
        )
    }

    private func slider(
        _ title: String,
        _ value: Binding<Double>,
        _ range: ClosedRange<Double>,
        unit: String = ""
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Slider(value: value, in: range)
                    .frame(width: 190)
                Text(unit == "s"
                     ? String(format: "%.1f%@", value.wrappedValue, unit)
                     : "\(Int(value.wrappedValue.rounded()))\(unit)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }
        }
    }
}

private struct ItemThumbnail: View {
    let item: DockItem

    var body: some View {
        Group {
            if let icon = AppCatalog.shared.icon(for: item, size: 32) {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "square.dashed")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 18, height: 18)
    }
}
