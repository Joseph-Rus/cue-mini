import SwiftUI
import AppKit
import Combine

@main
struct CueMiniApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // We don't use a SwiftUI scene — NSStatusItem + a custom NSPanel
        // give us the draggable, free-floating popover behavior we want.
        SwiftUI.Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var stateObservation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Fonts.registerBundled()
        installStatusItem()
        HotkeyManager.shared.register(onFire: { [weak self] in
            self?.toggle()
        })

        // Update tray title when listening state changes
        stateObservation = AppState.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateTrayTitle() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregister()
        AppState.shared.stop()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Cue."
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        self.statusItem = item
    }

    private func updateTrayTitle() {
        guard let button = statusItem?.button else { return }
        if case .listening = AppState.shared.phase {
            button.title = "● Cue."
        } else {
            button.title = "Cue."
        }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        toggle()
    }

    private func toggle() {
        PopoverWindowController.shared.toggle(near: statusItem?.button)
    }
}
