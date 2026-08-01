import AppKit
import PierCore
import SwiftUI

enum Motion {
    static let magnify = Animation.interactiveSpring(response: 0.16, dampingFraction: 0.75)
    static let card = Animation.spring(response: 0.32, dampingFraction: 0.8)
    static let quick = Animation.spring(response: 0.2, dampingFraction: 0.86)
}

extension DockMaterial {
    var nsMaterial: NSVisualEffectView.Material {
        switch self {
        case .hud: return .hudWindow
        case .sidebar: return .sidebar
        case .popover: return .popover
        case .window: return .underWindowBackground
        case .solid: return .windowBackground
        }
    }
}

extension Color {
    /// "#3B7BFF" or "3b7bff". Anything unparseable is simply no colour, which is how an
    /// empty tint field turns into "leave the material alone".
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    var hexString: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return String(
            format: "#%02X%02X%02X",
            Int(round(color.redComponent * 255)),
            Int(round(color.greenComponent * 255)),
            Int(round(color.blueComponent * 255))
        )
    }
}

/// Behind-window blur. SwiftUI's own materials don't reliably reach the desktop from
/// inside a borderless panel; `NSVisualEffectView` always does.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// The dock's surface: blur or solid, an optional tint, a hairline edge and a shadow —
/// all of it driven by the dock's own appearance settings.
struct DockSurface: View {
    let appearance: DockAppearance
    /// Live blur is composited by the window server, so an offscreen render falls back to
    /// a flat fill rather than drawing an "unsupported view" placeholder.
    @Environment(\.isOffscreenRender) private var offscreen

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: appearance.cornerRadius, style: .continuous)

        shape
            .fill(Color.clear)
            .background {
                if appearance.material == .solid {
                    shape.fill(Color(hex: appearance.tintHex) ?? Color(nsColor: .windowBackgroundColor))
                } else if offscreen {
                    shape.fill(Color(nsColor: .windowBackgroundColor).opacity(0.88))
                } else {
                    VisualEffectBackground(material: appearance.material.nsMaterial)
                        .clipShape(shape)
                }
            }
            .overlay {
                if appearance.material != .solid, let tint = Color(hex: appearance.tintHex) {
                    shape.fill(tint.opacity(appearance.tintStrength))
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(appearance.borderOpacity * 1.4),
                            .white.opacity(appearance.borderOpacity * 0.4),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: appearance.borderWidth
                )
            }
            .opacity(appearance.opacity)
            .shadow(color: .black.opacity(appearance.shadow ? 0.34 : 0), radius: 16, y: 6)
            .shadow(color: .black.opacity(appearance.shadow ? 0.14 : 0), radius: 2, y: 1)
    }
}

/// True while views are drawn by `ImageRenderer` rather than by a window: live blur is
/// composited by the window server and can't be captured that way.
struct OffscreenRenderKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isOffscreenRender: Bool {
        get { self[OffscreenRenderKey.self] }
        set { self[OffscreenRenderKey.self] = newValue }
    }
}
