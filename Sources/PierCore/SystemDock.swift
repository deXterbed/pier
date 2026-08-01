import Foundation

/// Reads the macOS Dock's own list of apps.
///
/// The Dock stores its tiles in `com.apple.dock`'s `persistent-apps`, each one a nest of
/// dictionaries ending in a bookmark-ish `_CFURLString`. Parsing is split out from reading
/// so the awkward part is testable without a Dock.
public enum SystemDock {

    public static let defaultsDomain = "com.apple.dock"

    /// Pulls file URLs out of a `persistent-apps` / `persistent-others` array.
    public static func urls(fromPersistentEntries entries: [Any]) -> [URL] {
        entries.compactMap { entry in
            guard let tile = entry as? [String: Any] else { return nil }
            guard let data = tile["tile-data"] as? [String: Any] else { return nil }

            // Newer macOS nests the URL under "file-data"; older tiles used "file-label"
            // plus a path elsewhere. Take whichever is present.
            if let fileData = data["file-data"] as? [String: Any],
               let string = fileData["_CFURLString"] as? String {
                return url(fromCFURLString: string)
            }
            if let string = data["file-data"] as? String {
                return url(fromCFURLString: string)
            }
            return nil
        }
    }

    static func url(fromCFURLString string: String) -> URL? {
        if string.hasPrefix("file://") {
            return URL(string: string)?.standardizedFileURL
        }
        guard !string.isEmpty else { return nil }
        return URL(fileURLWithPath: string).standardizedFileURL
    }

    /// Turns those URLs into dock items, skipping anything that has since been deleted.
    public static func items(
        from urls: [URL],
        existsCheck: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> [DockItem] {
        urls.compactMap { url in
            guard existsCheck(url) else { return nil }
            return url.pathExtension == "app" ? DockItem.app(at: url) : DockItem.folder(at: url)
        }
    }
}
