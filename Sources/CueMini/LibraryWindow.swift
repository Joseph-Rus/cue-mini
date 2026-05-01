import AppKit
import SwiftUI

@MainActor
final class LibraryWindowController {
    static let shared = LibraryWindowController()
    private var window: NSWindow?

    private init() {}

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let host = NSHostingController(
            rootView: LibraryView()
                .environmentObject(Settings.shared)
                .preferredColorScheme(Settings.shared.appearance.colorScheme)
        )
        // Let SwiftUI drive the window size — the LibraryView reports its
        // ideal height based on the song count, and the window grows to fit.
        host.sizingOptions = [.preferredContentSize]

        let window = NSWindow(contentViewController: host)
        window.title = "Cue Mini Library"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
