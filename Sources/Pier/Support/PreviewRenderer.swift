import AppKit
import PierCore
import SwiftUI

/// Renders Pier's own views to PNG:
///
///     Pier.app/Contents/MacOS/Pier --render-preview ~/Desktop
///
/// A dock only exists as a floating panel, so this is the cheapest way to look at one
/// closely — and a smoke test that the whole view stack draws.
@MainActor
enum PreviewRenderer {

    static func run(directory: String) async {
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        write(sample(edge: .bottom, hovered: 2), name: "dock-horizontal", in: output)
        write(sample(edge: .leading, hovered: nil), name: "dock-vertical", in: output)

        print("rendered previews to \(output.path)")
    }

    private static func sample(edge: DockEdge, hovered: Double?) -> DockViewModel {
        var dock = Dock(name: "Preview")
        dock.placement = DockPlacement(edge: edge)
        dock.appearance.iconSize = 52
        dock.appearance.magnification = 0.6

        let candidates = [
            "/System/Library/CoreServices/Finder.app",
            "/System/Applications/Safari.app",
            "/System/Applications/Mail.app",
            "/System/Applications/Notes.app",
            "/System/Applications/Music.app",
            "/System/Applications/System Settings.app",
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            dock.add(.app(at: URL(fileURLWithPath: path)))
        }
        dock.add(.widget(.divider))
        dock.add(.widget(.trash))

        let model = DockViewModel(dock: dock)
        if let hovered {
            let frames = dock.layout.frames(for: dock.items)
            let index = min(Int(hovered), frames.count - 1)
            model.pointer = CGPoint(x: frames[index].midX, y: frames[index].midY)
        }
        return model
    }

    private static func write(_ model: DockViewModel, name: String, in output: URL) {
        let card = model.layout.cardSize(for: model.items)
        let padding = model.layout.bleed + 30

        let renderer = ImageRenderer(
            content: Backdrop {
                DockContentView(model: model)
                    .frame(width: card.width, height: card.height)
            }
            .environment(\.isOffscreenRender, true)
            .frame(width: card.width + padding * 2, height: card.height + padding * 2)
        )
        renderer.scale = 2

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            print("failed to render \(name)")
            return
        }
        try? png.write(to: output.appendingPathComponent("\(name).png"))
    }
}

/// A stand-in desktop, so the dock's edges and shadow are visible in a flat PNG.
private struct Backdrop<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.22, green: 0.16, blue: 0.38),
                    Color(red: 0.08, green: 0.07, blue: 0.16),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            content
        }
    }
}
