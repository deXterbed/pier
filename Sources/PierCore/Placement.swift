import CoreGraphics
import Foundation

public enum DockEdge: String, Codable, CaseIterable, Sendable {
    case top
    case bottom
    case leading
    case trailing
    /// Anywhere you drag it to; keeps its own orientation.
    case floating

    public var displayName: String {
        switch self {
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .leading: return "Left"
        case .trailing: return "Right"
        case .floating: return "Anywhere"
        }
    }

    public var isVertical: Bool { self == .leading || self == .trailing }
}

public enum DockAlignment: String, Codable, CaseIterable, Sendable {
    case start
    case center
    case end

    public func displayName(vertical: Bool) -> String {
        switch self {
        case .start: return vertical ? "Top" : "Left"
        case .center: return "Center"
        case .end: return vertical ? "Bottom" : "Right"
        }
    }
}

public enum DockOrientation: String, Codable, Sendable {
    case horizontal
    case vertical
}

/// Where a dock sits on its screen.
///
/// Edges give you the familiar behaviour; `.floating` remembers an exact spot, which is
/// what dragging a dock somewhere by hand produces.
public struct DockPlacement: Codable, Hashable, Sendable {
    public var edge: DockEdge
    public var alignment: DockAlignment
    /// Distance from the docked edge.
    public var margin: Double
    /// Slide along the edge, in points, from the alignment anchor.
    public var offsetAlongEdge: Double
    /// Absolute position (bottom-left, screen coordinates) when floating.
    public var freePosition: CGPoint?
    /// Only consulted while floating; edges imply their own orientation.
    public var floatingOrientation: DockOrientation

    public init(
        edge: DockEdge = .bottom,
        alignment: DockAlignment = .center,
        margin: Double = 12,
        offsetAlongEdge: Double = 0,
        freePosition: CGPoint? = nil,
        floatingOrientation: DockOrientation = .horizontal
    ) {
        self.edge = edge
        self.alignment = alignment
        self.margin = margin
        self.offsetAlongEdge = offsetAlongEdge
        self.freePosition = freePosition
        self.floatingOrientation = floatingOrientation
    }

    public var orientation: DockOrientation {
        switch edge {
        case .top, .bottom: return .horizontal
        case .leading, .trailing: return .vertical
        case .floating: return floatingOrientation
        }
    }

    /// Where the dock's card belongs, given how big it currently is.
    /// `visible` is the screen's visible frame, so the menu bar and native Dock are
    /// already accounted for.
    public func frame(contentSize: CGSize, in visible: CGRect) -> CGRect {
        var origin: CGPoint

        switch edge {
        case .floating:
            origin = freePosition ?? CGPoint(
                x: visible.midX - contentSize.width / 2,
                y: visible.midY - contentSize.height / 2
            )
        case .bottom:
            origin = CGPoint(x: alignedX(contentSize, in: visible), y: visible.minY + margin)
        case .top:
            origin = CGPoint(
                x: alignedX(contentSize, in: visible),
                y: visible.maxY - contentSize.height - margin
            )
        case .leading:
            origin = CGPoint(x: visible.minX + margin, y: alignedY(contentSize, in: visible))
        case .trailing:
            origin = CGPoint(
                x: visible.maxX - contentSize.width - margin,
                y: alignedY(contentSize, in: visible)
            )
        }

        return CGRect(origin: origin, size: contentSize).clamped(to: visible)
    }

    /// Where the dock hides to: just past the edge it belongs to, still on the same axis.
    /// A floating dock leaves by its nearest edge, since it has no other opinion.
    public func hiddenFrame(contentSize: CGSize, in visible: CGRect, peek: Double = 3) -> CGRect {
        let shown = frame(contentSize: contentSize, in: visible)
        switch resolvedHidingEdge(for: shown, in: visible) {
        case .bottom:
            return shown.offsetBy(dx: 0, dy: -(shown.height + margin) + peek)
        case .top:
            return shown.offsetBy(dx: 0, dy: shown.height + margin - peek)
        case .leading:
            return shown.offsetBy(dx: -(shown.width + margin) + peek, dy: 0)
        case .trailing:
            return shown.offsetBy(dx: shown.width + margin - peek, dy: 0)
        case .floating:
            return shown
        }
    }

    private func resolvedHidingEdge(for shown: CGRect, in visible: CGRect) -> DockEdge {
        guard edge == .floating else { return edge }
        let distances: [(DockEdge, CGFloat)] = [
            (.leading, shown.minX - visible.minX),
            (.trailing, visible.maxX - shown.maxX),
            (.bottom, shown.minY - visible.minY),
            (.top, visible.maxY - shown.maxY),
        ]
        return distances.min { $0.1 < $1.1 }?.0 ?? .bottom
    }

    private func alignedX(_ size: CGSize, in visible: CGRect) -> CGFloat {
        let base: CGFloat
        switch alignment {
        case .start: base = visible.minX + margin
        case .center: base = visible.midX - size.width / 2
        case .end: base = visible.maxX - size.width - margin
        }
        return base + offsetAlongEdge
    }

    private func alignedY(_ size: CGSize, in visible: CGRect) -> CGFloat {
        let base: CGFloat
        switch alignment {
        case .start: base = visible.maxY - size.height - margin
        case .center: base = visible.midY - size.height / 2
        case .end: base = visible.minY + margin
        }
        return base - offsetAlongEdge
    }

    /// After a dock is dragged by hand, this is the placement that describes where it
    /// landed — snapping to an edge when it's close enough to one.
    public static func resolving(
        droppedFrame: CGRect,
        in visible: CGRect,
        snapDistance: Double = 34,
        margin: Double = 12,
        orientation: DockOrientation
    ) -> DockPlacement {
        let gaps: [(DockEdge, CGFloat)] = [
            (.leading, droppedFrame.minX - visible.minX),
            (.trailing, visible.maxX - droppedFrame.maxX),
            (.bottom, droppedFrame.minY - visible.minY),
            (.top, visible.maxY - droppedFrame.maxY),
        ]
        guard let nearest = gaps.min(by: { $0.1 < $1.1 }), nearest.1 <= snapDistance else {
            return DockPlacement(
                edge: .floating,
                margin: margin,
                freePosition: droppedFrame.origin,
                floatingOrientation: orientation
            )
        }

        // Keep where it landed along the edge; only the perpendicular axis snaps.
        let vertical = nearest.0.isVertical
        let anchor = vertical
            ? visible.midY - droppedFrame.height / 2
            : visible.midX - droppedFrame.width / 2
        let landed = vertical ? droppedFrame.minY : droppedFrame.minX
        let offset = vertical ? anchor - landed : landed - anchor

        return DockPlacement(
            edge: nearest.0,
            alignment: .center,
            margin: margin,
            offsetAlongEdge: offset,
            floatingOrientation: orientation
        )
    }
}

extension CGRect {
    /// Keeps a rect inside `bounds` without resizing it.
    public func clamped(to bounds: CGRect) -> CGRect {
        guard bounds.width >= width, bounds.height >= height else { return self }
        var result = self
        result.origin.x = Swift.min(Swift.max(minX, bounds.minX), bounds.maxX - width)
        result.origin.y = Swift.min(Swift.max(minY, bounds.minY), bounds.maxY - height)
        return result
    }
}
