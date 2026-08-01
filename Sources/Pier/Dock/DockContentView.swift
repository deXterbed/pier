import AppKit
import PierCore
import SwiftUI

struct DockContentView: View {
    @ObservedObject var model: DockViewModel
    @ObservedObject var catalog = AppCatalog.shared

    private var layout: DockLayout { model.layout }
    private var appearance: DockAppearance { model.appearance }

    var body: some View {
        Group {
            if model.dock.behavior.collapsed {
                CollapsedDock(appearance: appearance, count: model.items.count)
                    .frame(
                        width: layout.collapsedCardSize().width,
                        height: layout.collapsedCardSize().height
                    )
            } else {
                card
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(Motion.card, value: model.dock.behavior.collapsed)
    }

    private var card: some View {
        let size = layout.cardSize(for: model.items)

        return ZStack(alignment: .topLeading) {
            DockSurface(appearance: appearance)
                .frame(width: size.width, height: size.height)

            if model.items.isEmpty {
                EmptyDockHint(appearance: appearance)
                    .frame(width: size.width, height: size.height)
            }

            ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                DockTileView(
                    item: item,
                    index: index,
                    model: model,
                    catalog: catalog
                )
                .frame(width: layout.iconSize * item.widthFactor, height: layout.iconSize)
                .scaleEffect(scale(at: index), anchor: growthAnchor)
                .offset(offset(at: index))
                .position(centre(at: index))
                .opacity(model.draggingIndex == index ? 0.25 : 1)
                .zIndex(model.pointer != nil ? scale(at: index) : 1)
            }

            if let insertion = model.insertionIndex {
                InsertionMarker(vertical: layout.isVertical, thickness: appearance.iconSize * 0.08)
                    .frame(
                        width: layout.isVertical ? appearance.iconSize : 3,
                        height: layout.isVertical ? 3 : appearance.iconSize
                    )
                    .position(insertionPoint(insertion))
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay {
            RoundedRectangle(cornerRadius: appearance.cornerRadius, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(model.isDropTargeted && model.dropTargetIndex == nil ? 1 : 0)
        }
        .animation(Motion.magnify, value: model.pointer)
        .animation(Motion.card, value: model.items)
        .animation(Motion.quick, value: model.isDropTargeted)
    }

    // MARK: - Geometry

    private func scale(at index: Int) -> Double {
        let scales = model.scales
        guard index < scales.count else { return 1 }
        return model.pressedIndex == index ? scales[index] * 0.9 : scales[index]
    }

    private func offset(at index: Int) -> CGSize {
        let offsets = model.offsets
        guard index < offsets.count else { return .zero }
        return layout.isVertical
            ? CGSize(width: 0, height: offsets[index])
            : CGSize(width: offsets[index], height: 0)
    }

    /// Icons grow away from the edge the dock is against, like the real Dock's do.
    private var growthAnchor: UnitPoint {
        switch model.dock.placement.edge {
        case .bottom: return .bottom
        case .top: return .top
        case .leading: return .leading
        case .trailing: return .trailing
        case .floating: return .center
        }
    }

    private func centre(at index: Int) -> CGPoint {
        let frames = layout.frames(for: model.items)
        guard index < frames.count else { return .zero }
        return CGPoint(x: frames[index].midX, y: frames[index].midY)
    }

    private func insertionPoint(_ index: Int) -> CGPoint {
        let frames = layout.frames(for: model.items)
        let gap = appearance.spacing / 2

        if frames.isEmpty {
            let size = layout.cardSize(for: model.items)
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }
        if index >= frames.count {
            let last = frames[frames.count - 1]
            return layout.isVertical
                ? CGPoint(x: last.midX, y: last.maxY + gap)
                : CGPoint(x: last.maxX + gap, y: last.midY)
        }
        let frame = frames[index]
        return layout.isVertical
            ? CGPoint(x: frame.midX, y: frame.minY - gap)
            : CGPoint(x: frame.minX - gap, y: frame.midY)
    }
}

private struct InsertionMarker: View {
    let vertical: Bool
    let thickness: Double

    var body: some View {
        Capsule(style: .continuous)
            .fill(Color.accentColor)
            .shadow(color: Color.accentColor.opacity(0.7), radius: 5)
    }
}

private struct EmptyDockHint: View {
    let appearance: DockAppearance

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: appearance.iconSize * 0.36, weight: .light))
            .foregroundStyle(.secondary)
            .opacity(0.55)
    }
}

/// What a collapsed dock shows: one button with the item count on it.
private struct CollapsedDock: View {
    let appearance: DockAppearance
    let count: Int

    var body: some View {
        ZStack {
            DockSurface(appearance: appearance)
            VStack(spacing: 1) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: appearance.iconSize * 0.34, weight: .medium))
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: appearance.iconSize * 0.2, weight: .bold, design: .rounded))
                }
            }
            .foregroundStyle(.secondary)
        }
    }
}
