import AppKit

// Run as a background agent — no Dock icon (T1.2)
// main.swift runs on the main thread at startup; assumeIsolated is safe here.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

MainActor.assumeIsolated {
    let delegate = AppDelegate()
    app.delegate = delegate
}
app.run()
