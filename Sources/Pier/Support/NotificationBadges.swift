import AppKit
import ApplicationServices

/// Reads notification badges off the real Dock, because macOS publishes them nowhere else.
///
/// The Dock's accessibility tree exposes each app's tile with an `AXStatusLabel` holding the
/// badge text ("7", "12"). That is the only route to it: `NSRunningApplication` has no badge,
/// and the Dock keeps the value to itself. It makes this a best-effort dependency on the Dock's
/// AX shape, and it needs Accessibility permission.
///
/// Nothing reports when a badge changes, so callers have to poll.
enum NotificationBadges {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Asks macOS for Accessibility. The prompt can only be raised by the app that wants the
    /// permission, and it is also what puts Pier in the list to be switched on.
    static func requestTrust() {
        // The constant's value is "AXTrustedCheckOptionPrompt"; the literal avoids the
        // Unmanaged<CFString> dance for the same result.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Badge text keyed by resolved app path. Empty when permission is missing or the Dock is
    /// not running.
    static func read() -> [String: String] {
        guard isTrusted,
              let dock = NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return [:] }

        var badges: [String: String] = [:]
        for tile in tiles(of: dock.processIdentifier) {
            guard let badge = string(tile, "AXStatusLabel"), !badge.isEmpty,
                  let url = url(of: tile)
            else { continue }
            badges[normalizedPath(url.path)] = badge
        }
        return badges
    }

    /// Both sides have to be normalized the same way to match: the Dock reports
    /// `/private/tmp/...` where an item may carry `/tmp/...`.
    static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    // MARK: - Accessibility plumbing

    private static func tiles(of pid: pid_t) -> [AXUIElement] {
        var found: [AXUIElement] = []
        func walk(_ element: AXUIElement, depth: Int) {
            guard depth <= 3 else { return }
            for child in children(of: element) {
                if string(child, "AXSubrole") == "AXApplicationDockItem" {
                    found.append(child)
                } else {
                    walk(child, depth: depth + 1)
                }
            }
        }
        walk(AXUIElementCreateApplication(pid), depth: 0)
        return found
    }

    /// AXURL comes back as a CFURL, not a string, so a plain `as? String` yields nil for every
    /// tile and nothing ever matches.
    private static func url(of element: AXUIElement) -> URL? {
        if let url = value(element, "AXURL") as? URL { return url }
        if let string = value(element, "AXURL") as? String { return URL(string: string) }
        return nil
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        (value(element, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success
        else { return nil }
        return result
    }
}
