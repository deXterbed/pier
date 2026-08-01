import AppKit

// AppKit from the ground up: docks are floating non-activating panels, which SwiftUI's
// scene types don't model.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    // `NSApplication.delegate` is weak, so this local has to outlive the run loop — it
    // does, because `run()` doesn't return until Pier quits.
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
