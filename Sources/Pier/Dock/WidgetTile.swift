import AppKit
import PierCore
import SwiftUI

/// Widgets that draw themselves rather than showing an app icon.
struct WidgetTile: View {
    let kind: WidgetKind
    let side: CGFloat
    let appearance: DockAppearance
    /// A divider has to cross the dock, not run alongside it.
    let orientation: DockOrientation

    var body: some View {
        switch kind {
        case .spacer:
            Color.clear
        case .divider:
            Capsule()
                .fill(Color.primary.opacity(0.16))
                .frame(
                    width: orientation == .vertical ? nil : max(1, side * 0.035),
                    height: orientation == .vertical ? max(1, side * 0.035) : nil
                )
                .padding(orientation == .vertical ? .horizontal : .vertical, side * 0.12)
        case .clock:
            ClockWidget(side: side)
        case .trash:
            TrashWidget(side: side)
        case .finder:
            SystemIconWidget(path: "/System/Library/CoreServices/Finder.app", side: side)
        case .screenName:
            PlateWidget(title: ScreenLabels.currentName, symbol: "display", side: side)
        case .ipAddress:
            PlateWidget(title: NetworkInfo.localAddress, symbol: "wifi", side: side)
        }
    }
}

private struct ClockWidget: View {
    let side: CGFloat
    @State private var now = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Text(now, format: .dateTime.hour().minute())
                .font(.system(size: side * 0.30, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(now, format: .dateTime.weekday(.abbreviated).day())
                .font(.system(size: side * 0.17, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .onReceive(tick) { now = $0 }
    }
}

/// Shows whether the Trash has anything in it, and takes drops.
private struct TrashWidget: View {
    let side: CGFloat
    @State private var isEmpty = true

    var body: some View {
        Image(systemName: isEmpty ? "trash" : "trash.fill")
            .font(.system(size: side * 0.52, weight: .regular))
            .foregroundStyle(.secondary)
            .task {
                isEmpty = TrashState.isEmpty()
                // Cheap poll: the Trash has no notification worth subscribing to, and
                // this only runs while a dock with the widget is on screen.
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                    isEmpty = TrashState.isEmpty()
                }
            }
    }
}

private struct SystemIconWidget: View {
    let path: String
    let side: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .padding(side * 0.04)
    }
}

private struct PlateWidget: View {
    let title: String
    let symbol: String
    let side: CGFloat

    var body: some View {
        HStack(spacing: side * 0.1) {
            Image(systemName: symbol)
                .font(.system(size: side * 0.26, weight: .medium))
            Text(title)
                .font(.system(size: side * 0.2, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, side * 0.12)
    }
}

enum TrashState {
    static func isEmpty() -> Bool {
        guard let trash = try? FileManager.default.url(
            for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        ) else { return true }
        let contents = try? FileManager.default.contentsOfDirectory(
            at: trash, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
        return (contents?.isEmpty ?? true)
    }
}

enum ScreenLabels {
    static var currentName: String {
        NSScreen.main?.localizedName ?? "Display"
    }
}

enum NetworkInfo {
    /// The machine's LAN address — handy on a dock, and read locally with no requests.
    static var localAddress: String {
        var address = "—"
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return address }
        defer { freeifaddrs(pointer) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let interface = current.pointee
            let family = interface.ifa_addr.pointee.sa_family
            let name = String(cString: interface.ifa_name)

            if family == UInt8(AF_INET), name == "en0" || name == "en1" {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    interface.ifa_addr,
                    socklen_t(interface.ifa_addr.pointee.sa_len),
                    &host, socklen_t(host.count),
                    nil, 0,
                    NI_NUMERICHOST
                ) == 0 {
                    address = String(cString: host)
                    break
                }
            }
            cursor = interface.ifa_next
        }
        return address
    }
}
