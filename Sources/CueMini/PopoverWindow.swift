import AppKit
import SwiftUI

@MainActor
final class PopoverWindowController {
    static let shared = PopoverWindowController()

    private var panel: NSPanel?
    private let positionDefaultsKey = "popoverFrameOrigin"

    private init() {}

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func toggle(near button: NSStatusBarButton?) {
        if isVisible {
            hide()
        } else {
            show(near: button)
        }
    }

    func show(near button: NSStatusBarButton?) {
        let panel = panel ?? makePanel()
        self.panel = panel

        let origin: NSPoint
        if let saved = savedOrigin() {
            origin = saved
        } else {
            origin = defaultOrigin(near: button, panel: panel)
        }
        panel.setFrameOrigin(origin)

        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func resetPosition(near button: NSStatusBarButton?) {
        UserDefaults.standard.removeObject(forKey: positionDefaultsKey)
        guard let panel else { return }
        panel.setFrameOrigin(defaultOrigin(near: button, panel: panel))
    }

    private func makePanel() -> NSPanel {
        let host = NSHostingView(
            rootView: PopoverView()
                .environmentObject(AppState.shared)
                .environmentObject(Settings.shared)
                .preferredColorScheme(Settings.shared.appearance.colorScheme)
                .frame(width: 436)
        )
        host.translatesAutoresizingMaskIntoConstraints = false

        let initialFrame = NSRect(x: 0, y: 0, width: 436, height: 180)
        let panel = DraggablePanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = host

        // Resize the window when SwiftUI changes its intrinsic size
        host.invalidateIntrinsicContentSize()
        let sizeObserver = HostSizeObserver(panel: panel, host: host)
        panel.sizeObserver = sizeObserver

        // Persist position when user drags
        panel.onMoved = { [weak self] origin in
            self?.persist(origin: origin)
        }

        return panel
    }

    private func defaultOrigin(near button: NSStatusBarButton?, panel: NSPanel) -> NSPoint {
        let panelSize = panel.frame.size
        if let button, let buttonWindow = button.window {
            let buttonFrameInScreen = buttonWindow.convertToScreen(button.frame)
            let x = buttonFrameInScreen.midX - panelSize.width / 2
            let y = buttonFrameInScreen.minY - panelSize.height - 4
            return clampToScreen(NSPoint(x: x, y: y), size: panelSize)
        }
        // Fallback: top-right of primary screen
        guard let screen = NSScreen.main else { return .zero }
        let frame = screen.visibleFrame
        return NSPoint(
            x: frame.maxX - panelSize.width - 16,
            y: frame.maxY - panelSize.height - 4
        )
    }

    private func clampToScreen(_ point: NSPoint, size: NSSize) -> NSPoint {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else {
            return point
        }
        let frame = screen.visibleFrame
        var x = point.x
        var y = point.y
        if x + size.width > frame.maxX - 4 { x = frame.maxX - size.width - 4 }
        if x < frame.minX + 4 { x = frame.minX + 4 }
        if y + size.height > frame.maxY - 4 { y = frame.maxY - size.height - 4 }
        if y < frame.minY + 4 { y = frame.minY + 4 }
        return NSPoint(x: x, y: y)
    }

    private func savedOrigin() -> NSPoint? {
        guard let dict = UserDefaults.standard.dictionary(forKey: positionDefaultsKey),
              let x = dict["x"] as? CGFloat,
              let y = dict["y"] as? CGFloat else { return nil }
        return NSPoint(x: x, y: y)
    }

    private func persist(origin: NSPoint) {
        UserDefaults.standard.set(["x": origin.x, "y": origin.y], forKey: positionDefaultsKey)
    }
}

// MARK: - Panel subclass

final class DraggablePanel: NSPanel {
    var onMoved: ((NSPoint) -> Void)?
    var sizeObserver: HostSizeObserver?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(point)
    }

    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
        if event.type == .leftMouseUp {
            onMoved?(frame.origin)
        }
    }
}

// Watches the SwiftUI host view for size changes and resizes the panel to match.
@MainActor
final class HostSizeObserver: NSObject {
    private weak var panel: NSPanel?
    private weak var host: NSView?

    init(panel: NSPanel, host: NSView) {
        self.panel = panel
        self.host = host
        super.init()
        host.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hostFrameChanged(_:)),
            name: NSView.frameDidChangeNotification,
            object: host
        )
        DispatchQueue.main.async { [weak self] in
            self?.resizeToFit()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func hostFrameChanged(_ note: Notification) {
        resizeToFit()
    }

    private func resizeToFit() {
        guard let panel, let host else { return }
        let fitting = host.fittingSize
        let newSize = NSSize(
            width: max(420, fitting.width),
            height: max(160, fitting.height)
        )
        var frame = panel.frame
        // Anchor to top-left so the card grows downward when content changes
        frame.origin.y += (frame.size.height - newSize.height)
        frame.size = newSize
        panel.setFrame(frame, display: true, animate: false)
    }
}
