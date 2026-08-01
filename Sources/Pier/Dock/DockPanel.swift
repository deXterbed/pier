import AppKit
import PierCore

/// A dock's window.
///
/// Non-activating so clicking an icon never makes Pier the front app — the click's whole
/// purpose is to put some *other* app in front. Joins every Space and floats over
/// full-screen apps, which is the entire point of pinning one to a second monitor.
final class DockPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isOpaque = false
        backgroundColor = .clear
        // The shadow is drawn in SwiftUI so it can be soft; the window's own shadow would
        // trace the transparent bleed instead of the card.
        hasShadow = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        worksWhenModal = true
        animationBehavior = .none
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The panel's content view. Owns hit-testing, hover tracking, clicks, drags and drops —
/// everything that has to agree with `DockLayout` about where a tile is.
final class DockSurfaceView: NSView {
    weak var controller: DockWindowController?
    /// The card's rect inside the window; everything outside it is transparent bleed.
    var cardRect: NSRect = .zero

    private var trackingArea: NSTrackingArea?
    private var mouseDownAt: NSPoint?
    private var mouseDownIndex: Int?
    private var isDraggingItem = false

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .URL, .string, .pierItem])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Clicks in the bleed fall through to whatever is underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return cardRect.contains(local) ? self : nil
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Card coordinates: top-left of the visible card, which is what `DockLayout` speaks.
    private func cardPoint(_ windowPoint: NSPoint) -> NSPoint {
        let local = convert(windowPoint, from: nil)
        return NSPoint(x: local.x - cardRect.minX, y: local.y - cardRect.minY)
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        controller?.pointerEntered()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = cardPoint(event.locationInWindow)
        if cardRect.contains(convert(event.locationInWindow, from: nil)) {
            controller?.pointerMoved(to: point)
        } else {
            controller?.pointerLeft()
        }
    }

    override func mouseExited(with event: NSEvent) {
        controller?.pointerLeft()
    }

    // MARK: - Clicking and dragging tiles

    override func mouseDown(with event: NSEvent) {
        mouseDownAt = event.locationInWindow
        isDraggingItem = false
        mouseDownIndex = controller?.itemIndex(at: cardPoint(event.locationInWindow))
        controller?.pressed(index: mouseDownIndex)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownAt else { return }
        let travel = hypot(
            event.locationInWindow.x - start.x,
            event.locationInWindow.y - start.y
        )
        guard travel > 5 else { return }

        if let index = mouseDownIndex {
            isDraggingItem = true
            controller?.dragItem(at: index, to: cardPoint(event.locationInWindow))
        } else {
            // A drag on the dock's own background moves the whole dock.
            isDraggingItem = true
            controller?.dragWindow(with: event)
            mouseDownAt = nil
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownAt = nil
            mouseDownIndex = nil
            isDraggingItem = false
        }
        controller?.pressed(index: nil)

        if isDraggingItem {
            controller?.finishItemDrag(at: cardPoint(event.locationInWindow), inside: isInsideCard(event))
            return
        }
        guard let index = mouseDownIndex else { return }
        controller?.clicked(index: index)
    }

    override func rightMouseDown(with event: NSEvent) {
        let index = controller?.itemIndex(at: cardPoint(event.locationInWindow))
        guard let menu = controller?.contextMenu(forItemAt: index) else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func isInsideCard(_ event: NSEvent) -> Bool {
        cardRect.contains(convert(event.locationInWindow, from: nil))
    }

    // MARK: - Drops from other apps

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        controller?.dropEntered()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let point = cardPoint(sender.draggingLocation)
        controller?.dropMoved(to: point)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        controller?.dropExited()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        controller?.accept(sender, at: cardPoint(sender.draggingLocation)) ?? false
    }
}

extension NSPasteboard.PasteboardType {
    /// Marks a drag that started inside a Pier dock.
    static let pierItem = NSPasteboard.PasteboardType("app.openware.pier.item")
}
