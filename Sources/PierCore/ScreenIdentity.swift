import CoreGraphics
import Foundation

/// A display, named in a way that survives sleep, reboots and unplugging.
///
/// Display IDs are recycled by macOS, so they can't be stored on their own: a dock pinned
/// to display 3 would reappear on whatever became display 3 next. The UUID is stable when
/// it's available; the name and size are the fallback for adapters that don't provide one.
public struct ScreenIdentity: Codable, Hashable, Sendable {
    public var uuid: String?
    public var name: String
    public var width: Int
    public var height: Int
    /// Whether this was the main display when the dock was created — used only to name it.
    public var wasMain: Bool

    public init(uuid: String?, name: String, width: Int, height: Int, wasMain: Bool = false) {
        self.uuid = uuid
        self.name = name
        self.width = width
        self.height = height
        self.wasMain = wasMain
    }

    public var displayName: String {
        name.isEmpty ? "\(width)×\(height)" : name
    }

    public var resolution: String { "\(width)×\(height)" }

    /// How well `self` describes `candidate`. Higher wins; zero means no.
    public func match(_ candidate: ScreenIdentity) -> Int {
        if let uuid, let other = candidate.uuid, uuid == other { return 3 }
        if !name.isEmpty, name == candidate.name, width == candidate.width, height == candidate.height {
            return 2
        }
        if !name.isEmpty, name == candidate.name { return 1 }
        return 0
    }

    /// Picks the connected screen a dock belongs on, or nil when its display is gone —
    /// which is what makes a dock disappear with the monitor it was pinned to instead of
    /// piling onto whatever is left.
    public static func resolve(
        wanted: ScreenIdentity?,
        connected: [ScreenIdentity]
    ) -> ScreenIdentity? {
        guard let wanted else { return connected.first }
        let scored = connected
            .map { (screen: $0, score: wanted.match($0)) }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
        return scored.first?.screen
    }
}
