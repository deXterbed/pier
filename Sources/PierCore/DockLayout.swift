import CoreGraphics
import Foundation

/// Turns "these items, this size, this orientation" into exact geometry.
///
/// Every position in the dock comes from here — the SwiftUI drawing, the AppKit
/// hit-testing, and the drag-to-reorder insertion point all ask the same struct, so they
/// can't disagree about where a tile is.
public struct DockLayout: Sendable, Equatable {
    public var iconSize: Double
    public var spacing: Double
    public var padding: Double
    public var orientation: DockOrientation
    /// Extra room around the card for the shadow and for magnified icons to grow into.
    public var bleed: Double

    public init(
        iconSize: Double = 48,
        spacing: Double = 8,
        padding: Double = 10,
        orientation: DockOrientation = .horizontal,
        bleed: Double = 26
    ) {
        self.iconSize = iconSize
        self.spacing = spacing
        self.padding = padding
        self.orientation = orientation
        self.bleed = bleed
    }

    public var isVertical: Bool { orientation == .vertical }

    /// Length taken along the dock's axis by an item of this width factor.
    public func length(of item: DockItem) -> Double {
        iconSize * item.widthFactor
    }

    /// The visible card, excluding the transparent bleed.
    public func cardSize(for items: [DockItem]) -> CGSize {
        let along = items.reduce(0.0) { $0 + length(of: $1) }
            + spacing * Double(max(items.count - 1, 0))
            + padding * 2
        let across = iconSize + padding * 2
        let minimum = iconSize + padding * 2

        return isVertical
            ? CGSize(width: across, height: max(along, minimum))
            : CGSize(width: max(along, minimum), height: across)
    }

    /// Card plus the bleed the window needs around it.
    public func windowSize(for items: [DockItem]) -> CGSize {
        let card = cardSize(for: items)
        return CGSize(width: card.width + bleed * 2, height: card.height + bleed * 2)
    }

    /// A collapsed dock is one square button.
    public func collapsedCardSize() -> CGSize {
        CGSize(width: iconSize + padding * 2, height: iconSize + padding * 2)
    }

    /// Each item's frame inside the card, top-left origin, in the order given.
    public func frames(for items: [DockItem]) -> [CGRect] {
        var result: [CGRect] = []
        var cursor = padding

        for item in items {
            let run = length(of: item)
            if isVertical {
                result.append(CGRect(x: padding, y: cursor, width: iconSize, height: run))
            } else {
                result.append(CGRect(x: cursor, y: padding, width: run, height: iconSize))
            }
            cursor += run + spacing
        }
        return result
    }

    /// Which item is under a point in card coordinates.
    public func index(at point: CGPoint, items: [DockItem]) -> Int? {
        frames(for: items).firstIndex { $0.contains(point) }
    }

    /// Where a dragged item would land if dropped here — 0...count, counting the gaps
    /// rather than the tiles, so dropping between two icons does the obvious thing.
    public func insertionIndex(at point: CGPoint, items: [DockItem]) -> Int {
        guard !items.isEmpty else { return 0 }
        let position = isVertical ? point.y : point.x
        let frames = self.frames(for: items)

        for (index, frame) in frames.enumerated() {
            let middle = isVertical ? frame.midY : frame.midX
            if position < middle { return index }
        }
        return items.count
    }

    /// Position along the axis, 0...1 across the card's interior — what magnification
    /// needs from a pointer location.
    public func axisProgress(of point: CGPoint, items: [DockItem]) -> Double? {
        let card = cardSize(for: items)
        let span = (isVertical ? card.height : card.width) - padding * 2
        guard span > 0 else { return nil }
        let position = (isVertical ? point.y : point.x) - padding
        return min(max(position / span, 0), 1)
    }
}
