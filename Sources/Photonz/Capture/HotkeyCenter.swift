import AppKit
import Carbon.HIToolbox

/// System-wide hotkeys via Carbon's RegisterEventHotKey — the one mechanism
/// that works without the Accessibility permission and fires even when the
/// app is in the background.
///
/// Caveat for ⌘⇧3/⌘⇧4: macOS's own Screenshots shortcuts intercept these
/// before any app while they're enabled. Registration still succeeds, and our
/// hotkeys start firing as soon as the user disables the system ones
/// (System Settings → Keyboard → Keyboard Shortcuts → Screenshots).
@MainActor
final class HotkeyCenter {
    struct Hotkey {
        let keyCode: UInt32
        let carbonModifiers: UInt32

        static func commandShift(_ keyCode: Int) -> Hotkey {
            Hotkey(keyCode: UInt32(keyCode), carbonModifiers: UInt32(cmdKey | shiftKey))
        }
    }

    private var actions: [UInt32: () -> Void] = [:]
    private var hotkeyRefs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?
    private var nextID: UInt32 = 1

    func register(_ hotkey: Hotkey, action: @escaping () -> Void) {
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x5048_545A) /* 'PHTZ' */, id: nextID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.carbonModifiers, id,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("HotkeyCenter: failed to register keyCode \(hotkey.keyCode) (status \(status))")
            return
        }
        actions[nextID] = action
        hotkeyRefs.append(ref)
        nextID += 1
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var hotkeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)
            guard let userData else { return noErr }
            // Carbon dispatches application-target events on the main thread.
            MainActor.assumeIsolated {
                let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
                center.actions[hotkeyID.id]?()
            }
            return noErr
        }, 1, &eventType, selfPtr, &handlerRef)
    }
}
