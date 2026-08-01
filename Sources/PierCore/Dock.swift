import CoreGraphics
import Foundation

public enum DockMaterial: String, Codable, CaseIterable, Sendable {
    case hud
    case sidebar
    case popover
    case window
    case solid

    public var displayName: String {
        switch self {
        case .hud: return "HUD"
        case .sidebar: return "Sidebar"
        case .popover: return "Popover"
        case .window: return "Window"
        case .solid: return "Solid colour"
        }
    }
}

public struct DockAppearance: Codable, Hashable, Sendable {
    public var iconSize: Double
    public var spacing: Double
    public var padding: Double
    public var cornerRadius: Double
    public var opacity: Double
    public var material: DockMaterial
    /// Hex, applied over the material. Empty means untinted.
    public var tintHex: String
    public var tintStrength: Double
    public var borderWidth: Double
    public var borderOpacity: Double
    public var shadow: Bool
    public var magnification: Double
    public var showLabels: Bool
    public var showRunningIndicators: Bool

    public init(
        iconSize: Double = 48,
        spacing: Double = 8,
        padding: Double = 10,
        cornerRadius: Double = 18,
        opacity: Double = 1,
        material: DockMaterial = .hud,
        tintHex: String = "",
        tintStrength: Double = 0.18,
        borderWidth: Double = 1,
        borderOpacity: Double = 0.14,
        shadow: Bool = true,
        magnification: Double = 0.55,
        showLabels: Bool = true,
        showRunningIndicators: Bool = true
    ) {
        self.iconSize = iconSize
        self.spacing = spacing
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.opacity = opacity
        self.material = material
        self.tintHex = tintHex
        self.tintStrength = tintStrength
        self.borderWidth = borderWidth
        self.borderOpacity = borderOpacity
        self.shadow = shadow
        self.magnification = magnification
        self.showLabels = showLabels
        self.showRunningIndicators = showRunningIndicators
    }

    public var magnifier: Magnifier {
        Magnifier(strength: magnification)
    }

    /// Clamps everything a slider can reach, so a hand-edited config can't produce a
    /// dock that's a mile wide or invisible.
    public var sanitised: DockAppearance {
        var copy = self
        copy.iconSize = min(max(iconSize, 20), 128)
        copy.spacing = min(max(spacing, 0), 40)
        copy.padding = min(max(padding, 0), 40)
        copy.cornerRadius = min(max(cornerRadius, 0), 60)
        copy.opacity = min(max(opacity, 0.15), 1)
        copy.tintStrength = min(max(tintStrength, 0), 1)
        copy.borderWidth = min(max(borderWidth, 0), 6)
        copy.borderOpacity = min(max(borderOpacity, 0), 1)
        copy.magnification = min(max(magnification, 0), 1)
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case iconSize, spacing, padding, cornerRadius, opacity, material, tintHex
        case tintStrength, borderWidth, borderOpacity, shadow, magnification
        case showLabels, showRunningIndicators
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = DockAppearance()
        iconSize = try c.decodeIfPresent(Double.self, forKey: .iconSize) ?? fallback.iconSize
        spacing = try c.decodeIfPresent(Double.self, forKey: .spacing) ?? fallback.spacing
        padding = try c.decodeIfPresent(Double.self, forKey: .padding) ?? fallback.padding
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? fallback.cornerRadius
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? fallback.opacity
        material = try c.decodeIfPresent(DockMaterial.self, forKey: .material) ?? fallback.material
        tintHex = try c.decodeIfPresent(String.self, forKey: .tintHex) ?? fallback.tintHex
        tintStrength = try c.decodeIfPresent(Double.self, forKey: .tintStrength) ?? fallback.tintStrength
        borderWidth = try c.decodeIfPresent(Double.self, forKey: .borderWidth) ?? fallback.borderWidth
        borderOpacity = try c.decodeIfPresent(Double.self, forKey: .borderOpacity) ?? fallback.borderOpacity
        shadow = try c.decodeIfPresent(Bool.self, forKey: .shadow) ?? fallback.shadow
        magnification = try c.decodeIfPresent(Double.self, forKey: .magnification) ?? fallback.magnification
        showLabels = try c.decodeIfPresent(Bool.self, forKey: .showLabels) ?? fallback.showLabels
        showRunningIndicators = try c.decodeIfPresent(Bool.self, forKey: .showRunningIndicators)
            ?? fallback.showRunningIndicators
    }
}

public struct DockBehavior: Codable, Hashable, Sendable {
    public var autoHide: Bool
    public var hideOnFullscreen: Bool
    public var collapsible: Bool
    public var collapsed: Bool
    public var hideDelay: Double
    /// Mirror the macOS Dock's own contents instead of a hand-picked list.
    public var mirrorsSystemDock: Bool
    /// Append whatever is running but not already on this dock.
    public var showsRunningApps: Bool

    public init(
        autoHide: Bool = false,
        hideOnFullscreen: Bool = true,
        collapsible: Bool = false,
        collapsed: Bool = false,
        hideDelay: Double = 0.6,
        mirrorsSystemDock: Bool = false,
        showsRunningApps: Bool = false
    ) {
        self.autoHide = autoHide
        self.hideOnFullscreen = hideOnFullscreen
        self.collapsible = collapsible
        self.collapsed = collapsed
        self.hideDelay = hideDelay
        self.mirrorsSystemDock = mirrorsSystemDock
        self.showsRunningApps = showsRunningApps
    }

    private enum CodingKeys: String, CodingKey {
        case autoHide, hideOnFullscreen, collapsible, collapsed, hideDelay
        case mirrorsSystemDock, showsRunningApps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = DockBehavior()
        autoHide = try c.decodeIfPresent(Bool.self, forKey: .autoHide) ?? fallback.autoHide
        hideOnFullscreen = try c.decodeIfPresent(Bool.self, forKey: .hideOnFullscreen) ?? fallback.hideOnFullscreen
        collapsible = try c.decodeIfPresent(Bool.self, forKey: .collapsible) ?? fallback.collapsible
        collapsed = try c.decodeIfPresent(Bool.self, forKey: .collapsed) ?? fallback.collapsed
        hideDelay = try c.decodeIfPresent(Double.self, forKey: .hideDelay) ?? fallback.hideDelay
        mirrorsSystemDock = try c.decodeIfPresent(Bool.self, forKey: .mirrorsSystemDock) ?? fallback.mirrorsSystemDock
        showsRunningApps = try c.decodeIfPresent(Bool.self, forKey: .showsRunningApps) ?? fallback.showsRunningApps
    }
}

/// One dock: what's in it, which screen it belongs to, where it sits, how it looks.
public struct Dock: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var items: [DockItem]
    /// Which display this dock is pinned to. Nil means "wherever the main screen is".
    public var screen: ScreenIdentity?
    public var placement: DockPlacement
    public var appearance: DockAppearance
    public var behavior: DockBehavior
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String = "Dock",
        items: [DockItem] = [],
        screen: ScreenIdentity? = nil,
        placement: DockPlacement = DockPlacement(),
        appearance: DockAppearance = DockAppearance(),
        behavior: DockBehavior = DockBehavior(),
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.items = items
        self.screen = screen
        self.placement = placement
        self.appearance = appearance
        self.behavior = behavior
        self.isEnabled = isEnabled
    }

    public var layout: DockLayout {
        let clean = appearance.sanitised
        return DockLayout(
            iconSize: clean.iconSize,
            spacing: clean.spacing,
            padding: clean.padding,
            orientation: placement.orientation,
            bleed: max(26, clean.iconSize * clean.magnification + 16)
        )
    }

    public var isEmpty: Bool { items.isEmpty }

    public func item(id: UUID) -> DockItem? {
        items.first { $0.id == id }
    }

    // MARK: - Mutation

    /// Adds unless the same app or path is already here. Widgets can repeat.
    @discardableResult
    public mutating func add(_ item: DockItem, at index: Int? = nil) -> Bool {
        if item.kind != .widget, items.contains(where: { $0.identity == item.identity }) {
            return false
        }
        let target = min(max(index ?? items.count, 0), items.count)
        items.insert(item, at: target)
        return true
    }

    @discardableResult
    public mutating func add(contentsOf newItems: [DockItem], at index: Int? = nil) -> [DockItem] {
        var landed: [DockItem] = []
        var cursor = index
        for item in newItems where add(item, at: cursor) {
            landed.append(item)
            if cursor != nil { cursor! += 1 }
        }
        return landed
    }

    @discardableResult
    public mutating func remove(id: UUID) -> DockItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        return items.remove(at: index)
    }

    /// Moves one item to `destination`, an index in the list as it stands now.
    public mutating func move(id: UUID, to destination: Int) {
        guard let from = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: from)
        let corrected = from < destination ? destination - 1 : destination
        items.insert(item, at: min(max(corrected, 0), items.count))
    }
}
