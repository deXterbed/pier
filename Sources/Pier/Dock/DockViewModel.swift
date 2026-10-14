import AppKit
import PierCore
import SwiftUI

/// What the SwiftUI layer of a dock draws from.
@MainActor
final class DockViewModel: ObservableObject {
    @Published var dock: Dock
    /// Pointer position in card coordinates, or nil when it's elsewhere.
    @Published var pointer: CGPoint?
    /// Index being pressed, for the click-down dip.
    @Published var pressedIndex: Int?
    /// Where a dragged item would land, drawn as a gap.
    @Published var insertionIndex: Int?
    /// Tile a file is hovering over, which would open with it.
    @Published var dropTargetIndex: Int?
    @Published var isDropTargeted = false
    /// The item being dragged along the dock, hidden from its old spot.
    @Published var draggingIndex: Int?

    init(dock: Dock) {
        self.dock = dock
    }

    /// Running apps shown after the dock's own items without being stored: an app appears when
    /// it launches and goes when it quits. Recomputed on every refresh, never persisted.
    @Published private(set) var runningExtras: [DockItem] = []

    /// Everything to draw and hit-test: the dock's own items, then any running apps being shown.
    var items: [DockItem] { dock.items + runningExtras }

    var layout: DockLayout { dock.layout }
    var appearance: DockAppearance { dock.appearance.sanitised }

    /// Fractional item index under the pointer, which is what magnification wants.
    var hoveredPosition: Double? {
        guard let pointer, !items.isEmpty else { return nil }
        let layout = self.layout
        let frames = layout.frames(for: items)
        let position = layout.isVertical ? pointer.y : pointer.x

        // Distance measured in tiles, interpolating between tile centres so the swell
        // slides smoothly instead of snapping from icon to icon.
        let centres = frames.map { layout.isVertical ? $0.midY : $0.midX }
        guard let first = centres.first, let last = centres.last else { return nil }
        if position <= first { return 0 }
        if position >= last { return Double(centres.count - 1) }

        for index in 0..<(centres.count - 1) {
            let low = centres[index]
            let high = centres[index + 1]
            if position >= low && position <= high {
                let span = high - low
                let progress = span > 0 ? (position - low) / span : 0
                return Double(index) + progress
            }
        }
        return nil
    }

    var scales: [Double] {
        appearance.magnifier.scales(count: items.count, hovered: hoveredPosition)
    }

    var offsets: [Double] {
        appearance.magnifier.offsets(
            count: items.count,
            hovered: hoveredPosition,
            itemLength: appearance.iconSize
        )
    }

    /// Recomputes the running extras. Called when the dock changes and when the set of running
    /// apps changes. Ids are carried over between refreshes so SwiftUI reuses each tile rather
    /// than rebuilding it, which would restart its animations on every app launch.
    func refreshRunningExtras() {
        guard dock.behavior.showsRunningApps else {
            if !runningExtras.isEmpty { runningExtras = [] }
            return
        }
        let extras = SystemDockReader.runningItems(excluding: dock.items)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        runningExtras = extras.map { item in
            var item = item
            if let existing = runningExtras.first(where: { $0.bundleIdentifier == item.bundleIdentifier }) {
                item.id = existing.id
            }
            return item
        }
    }
}
