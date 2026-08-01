import AppKit
import PierCore

/// Follows the pointer so hidden docks know when you're reaching for them.
///
/// Global *mouse* monitoring needs no Accessibility permission — only keyboard does.
/// That's why reaching for a dock is a pointer gesture and never a keystroke.
@MainActor
final class PointerWatcher {
    var onMove: ((NSPoint) -> Void)?

    private var monitors: [Any] = []
    private var lastReport: TimeInterval = 0
    private let interval: TimeInterval = 1.0 / 60

    func start() {
        stop()
        add(matching: [.mouseMoved, .leftMouseDragged])
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
    }

    private func add(matching mask: NSEvent.EventTypeMask) {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            self?.report()
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.report()
            return event
        }) {
            monitors.append(local)
        }
    }

    private func report() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastReport >= interval else { return }
        lastReport = now
        onMove?(NSEvent.mouseLocation)
    }
}

/// Which screens currently have a full-screen window on them.
///
/// There's no public notification for another app entering full screen, so this reads the
/// window list — metadata only, which needs no Screen Recording permission.
enum FullscreenWatcher {

    static func screensWithFullscreenWindows() -> Set<ScreenIdentity> {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return [] }

        var covered: Set<ScreenIdentity> = []

        for screen in NSScreen.screens {
            let bounds = screen.frame
            let full = windows.contains { window in
                guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0 else {
                    return false
                }
                guard let owner = window[kCGWindowOwnerName as String] as? String,
                      owner != "Pier", owner != "Window Server", owner != "Dock"
                else { return false }
                guard let rect = window[kCGWindowBounds as String] as? [String: CGFloat] else {
                    return false
                }

                // CGWindow bounds are top-left origin; comparing sizes and the left edge
                // is enough to recognise a window filling a display.
                let width = rect["Width"] ?? 0
                let height = rect["Height"] ?? 0
                return abs(width - bounds.width) < 2 && abs(height - bounds.height) < 2
            }
            if full { covered.insert(screen.pierIdentity) }
        }
        return covered
    }
}
