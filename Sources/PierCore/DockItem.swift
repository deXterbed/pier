import Foundation

public enum DockItemKind: String, Codable, Sendable, CaseIterable {
    case app
    case folder
    case file
    case widget
}

/// The things a dock can hold: applications, folders you can drop into, plain files, and
/// widgets that draw themselves.
public enum WidgetKind: String, Codable, Sendable, CaseIterable {
    case clock
    case spacer
    case divider
    case trash
    case finder
    case screenName
    case ipAddress

    public var title: String {
        switch self {
        case .clock: return "Clock"
        case .spacer: return "Spacer"
        case .divider: return "Divider"
        case .trash: return "Trash"
        case .finder: return "Finder"
        case .screenName: return "Screen Name"
        case .ipAddress: return "IP Address"
        }
    }

    /// Spacers and dividers are furniture: they never launch and never take a drop.
    public var isDecorative: Bool {
        self == .spacer || self == .divider
    }

    /// A divider is a hairline; a spacer is a gap. Neither wants a full tile.
    public var widthFactor: Double {
        switch self {
        case .divider: return 0.28
        case .spacer: return 0.6
        case .clock: return 1.5
        case .screenName, .ipAddress: return 2.0
        default: return 1
        }
    }
}

public struct DockItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var kind: DockItemKind
    public var title: String
    /// Absolute path for apps, folders and files.
    public var path: String?
    public var bundleIdentifier: String?
    /// An image on disk replacing the item's natural icon.
    public var customIconPath: String?
    public var widget: WidgetKind?
    /// Folders can spring open into a grid instead of opening in Finder.
    public var opensAsGrid: Bool

    public init(
        id: UUID = UUID(),
        kind: DockItemKind,
        title: String,
        path: String? = nil,
        bundleIdentifier: String? = nil,
        customIconPath: String? = nil,
        widget: WidgetKind? = nil,
        opensAsGrid: Bool = true
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.path = path
        self.bundleIdentifier = bundleIdentifier
        self.customIconPath = customIconPath
        self.widget = widget
        self.opensAsGrid = opensAsGrid
    }

    // MARK: - Construction

    public static func app(
        at url: URL,
        bundleIdentifier: String? = nil,
        title: String? = nil
    ) -> DockItem {
        DockItem(
            kind: .app,
            title: title ?? url.deletingPathExtension().lastPathComponent,
            path: url.path,
            bundleIdentifier: bundleIdentifier
        )
    }

    public static func folder(at url: URL) -> DockItem {
        DockItem(kind: .folder, title: url.lastPathComponent, path: url.path)
    }

    public static func file(at url: URL) -> DockItem {
        DockItem(kind: .file, title: url.lastPathComponent, path: url.path)
    }

    public static func widget(_ kind: WidgetKind) -> DockItem {
        DockItem(kind: .widget, title: kind.title, widget: kind)
    }

    // MARK: - Derived

    public var url: URL? { path.map { URL(fileURLWithPath: $0) } }

    public var customIconURL: URL? { customIconPath.map { URL(fileURLWithPath: $0) } }

    /// Decorative widgets don't respond to clicks or drops.
    public var isInteractive: Bool {
        guard kind == .widget, let widget else { return true }
        return !widget.isDecorative
    }

    /// Only apps and folders accept a file dropped onto them.
    public var acceptsDrops: Bool {
        switch kind {
        case .app, .folder: return true
        case .widget: return widget == .trash || widget == .finder
        case .file: return false
        }
    }

    /// How wide this item is relative to one square tile.
    public var widthFactor: Double {
        kind == .widget ? (widget?.widthFactor ?? 1) : 1
    }

    /// What two items being "the same" means for de-duplication.
    var identity: String {
        if let bundleIdentifier, kind == .app { return "app:\(bundleIdentifier)" }
        if let path { return "\(kind.rawValue):\(path)" }
        if let widget { return "widget:\(widget.rawValue):\(id.uuidString)" }
        return id.uuidString
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, kind, title, path, bundleIdentifier, customIconPath, widget, opensAsGrid
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(DockItemKind.self, forKey: .kind) ?? .app
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        path = try c.decodeIfPresent(String.self, forKey: .path)
        bundleIdentifier = try c.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        customIconPath = try c.decodeIfPresent(String.self, forKey: .customIconPath)
        widget = try c.decodeIfPresent(WidgetKind.self, forKey: .widget)
        opensAsGrid = try c.decodeIfPresent(Bool.self, forKey: .opensAsGrid) ?? true
    }
}
