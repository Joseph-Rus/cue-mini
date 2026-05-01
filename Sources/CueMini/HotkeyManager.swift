import Foundation
import AppKit
import Carbon.HIToolbox

@MainActor
final class HotkeyManager {
    static let shared = HotkeyManager()
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var onFire: (() -> Void)?
    private let signature: OSType = 0x43554541 // 'CUEA'

    private init() {}

    func register(onFire: @escaping () -> Void) {
        self.onFire = onFire

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_: EventHandlerCallRef?, _: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in manager.onFire?() }
                return noErr
            },
            1,
            &spec,
            selfPtr,
            &eventHandler
        )
        guard installStatus == noErr else { return }

        // Alt+Space (Option+Space)
        let keyCode: UInt32 = UInt32(kVK_Space)
        let modifiers: UInt32 = UInt32(optionKey)
        let hotKeyID = EventHotKeyID(signature: signature, id: 1)

        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        onFire = nil
    }
}
