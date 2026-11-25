import AppKit

/// Where a window may be dragged from, worked out a beat after an edit rather
/// than in its frame.
///
/// Whenever a view in the window moves, AppKit works out again which part of
/// the title bar drags the window, by asking everything in it what it covers
/// and whether it takes the keyboard: 3.5 ms of the frame a 50 track timeline
/// makes room for a track in (2026-11-25). Only a movable window is asked, so
/// the window is not one for the moment the edit's frames take, with the
/// pointer on a menu row or a hand on the keyboard, and is asked once after.
/// A pointer that comes to the title bar ends the hold at once, so an edit
/// and a grab of the window straight after it moves the window.
@MainActor final class TitleBarRegionLater {
    static let holdMS = 400
    /// How often the pointer is looked for on the title bar meanwhile.
    private static let lookMS = 25
    private weak var window: NSWindow?
    private var release: Task<Void, Never>?

    func hold(_ window: NSWindow?) {
        // One already held is held a little longer; one that something else
        // keeps still is left alone, and so is one in a hand.
        guard let window, window.isMovable || window === self.window,
              NSEvent.pressedMouseButtons == 0, !Self.isOnTitleBar(NSEvent.mouseLocation, of: window) else { return }
        if window !== self.window { letGo() }
        self.window = window
        window.isMovable = false
        release?.cancel()
        // Holds the window and not this, so a window always gets it back,
        // even from an editor that has gone.
        release = Task { @MainActor [weak self, weak window] in
            let until = ContinuousClock.now + .milliseconds(Self.holdMS)
            while ContinuousClock.now < until {
                try? await Task.sleep(for: .milliseconds(Self.lookMS))
                guard !Task.isCancelled else { return }
                guard let window, !Self.isOnTitleBar(NSEvent.mouseLocation, of: window) else { break }
            }
            window?.isMovable = true
            self?.window = nil
        }
    }

    /// The strip above the window's own content, and a little below it for a
    /// pointer on its way up.
    private static func isOnTitleBar(_ point: NSPoint, of window: NSWindow) -> Bool {
        let strip = max(0, window.frame.height - window.contentLayoutRect.height) + 24
        return NSRect(x: window.frame.minX, y: window.frame.maxY - strip, width: window.frame.width, height: strip)
            .contains(point)
    }

    private func letGo() {
        release?.cancel()
        release = nil
        window?.isMovable = true
        window = nil
    }
}
