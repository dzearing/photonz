import AppKit

/// The modifier flags of the key press being handled right now.
///
/// SwiftUI's `keyboardShortcut` matches a letter with its modifiers and its
/// case IGNORED, and when two buttons claim the same letter the winner is
/// arbitrary (measured 2026-09-02: a plain O fired the Shift O button as
/// often as its own). So a tool family cannot register M and Shift M as two
/// shortcuts. It registers the letter ONCE and asks this tracker whether
/// shift was down, which is what the old marquee slot's M / Shift M pair had
/// been silently getting wrong.
///
/// Fed by a local event monitor for real key presses, and by the playtest
/// harness for the synthetic ones it sends straight to a window (those never
/// pass through the application, so no monitor sees them).
@MainActor
enum KeyModifierTracker {
    private static var lastKeyDownFlags: NSEvent.ModifierFlags = []
    private static var monitor: Any?

    /// Whether shift is held for the key press in flight: the flags the press
    /// carried, or the hardware state as a fallback for a path nobody fed.
    static var isShiftDown: Bool {
        lastKeyDownFlags.contains(.shift) || NSEvent.modifierFlags.contains(.shift)
    }

    /// Records a key press about to be dispatched.
    static func record(_ event: NSEvent) {
        guard event.type == .keyDown else { return }
        lastKeyDownFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    }

    /// Installs the monitor once, at launch.
    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            record(event)
            return event
        }
    }
}
