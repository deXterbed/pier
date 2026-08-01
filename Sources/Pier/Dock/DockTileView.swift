import AppKit
import PierCore
import SwiftUI

struct DockTileView: View {
    let item: DockItem
    let index: Int
    @ObservedObject var model: DockViewModel
    @ObservedObject var catalog: AppCatalog

    private var appearance: DockAppearance { model.appearance }
    private var side: CGFloat { appearance.iconSize }
    private var isRunning: Bool { catalog.isRunning(item) }
    private var isDropTarget: Bool { model.dropTargetIndex == index }
    private var isLaunching: Bool { catalog.launching.contains(item.id) }
    private var isHovered: Bool {
        guard let hovered = model.hoveredPosition else { return false }
        return abs(hovered - Double(index)) < 0.5
    }

    var body: some View {
        ZStack {
            content
                .frame(width: side * item.widthFactor, height: side)

            if isDropTarget {
                RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2.5)
                    .background(
                        RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                            .fill(Color.accentColor.opacity(0.18))
                    )
            }
        }
        .overlay(alignment: indicatorAlignment) {
            if appearance.showRunningIndicators && isRunning {
                RunningDot(size: max(3, side * 0.075), frontmost: catalog.isFrontmost(item))
                    .padding(max(1, side * 0.02))
            }
        }
        .offset(y: isLaunching ? -side * 0.18 : 0)
        .animation(
            isLaunching
                ? .interpolatingSpring(stiffness: 240, damping: 6).repeatCount(3, autoreverses: true)
                : Motion.quick,
            value: isLaunching
        )
        .overlay(alignment: labelAlignment) {
            if appearance.showLabels && isHovered && model.draggingIndex == nil {
                TileLabel(text: item.title)
                    .fixedSize()
                    .offset(labelOffset)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .zIndex(100)
            }
        }
        .animation(Motion.quick, value: isHovered)
        .help(item.title)
    }

    @ViewBuilder
    private var content: some View {
        if item.kind == .widget, let widget = item.widget {
            WidgetTile(
                kind: widget,
                side: side,
                appearance: appearance,
                orientation: model.dock.placement.orientation
            )
        } else if let icon = catalog.icon(for: item, size: side * 2) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .padding(side * 0.04)
        } else {
            RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                .fill(Color.secondary.opacity(0.22))
                .overlay {
                    Image(systemName: item.kind == .folder ? "folder" : "questionmark")
                        .font(.system(size: side * 0.4, weight: .light))
                        .foregroundStyle(.secondary)
                }
                .padding(side * 0.06)
        }
    }

    /// The running dot sits on the edge the dock is against, the way the real one does.
    private var indicatorAlignment: Alignment {
        switch model.dock.placement.edge {
        case .top: return .top
        case .leading: return .leading
        case .trailing: return .trailing
        case .bottom, .floating: return .bottom
        }
    }

    private var labelAlignment: Alignment {
        switch model.dock.placement.edge {
        case .top: return .bottom
        case .leading: return .trailing
        case .trailing: return .leading
        case .bottom, .floating: return .top
        }
    }

    private var labelOffset: CGSize {
        let gap = side * 0.34 + 8
        switch model.dock.placement.edge {
        case .top: return CGSize(width: 0, height: gap)
        case .leading: return CGSize(width: gap, height: 0)
        case .trailing: return CGSize(width: -gap, height: 0)
        case .bottom, .floating: return CGSize(width: 0, height: -gap)
        }
    }
}

private struct RunningDot: View {
    let size: CGFloat
    let frontmost: Bool

    var body: some View {
        Circle()
            .fill(Color.primary.opacity(frontmost ? 0.95 : 0.55))
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.3), radius: 1)
    }
}

private struct TileLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            .allowsHitTesting(false)
    }
}
