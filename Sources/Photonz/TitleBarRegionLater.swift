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
@MainActor final class TitleBarRegionLater {
    static let holdMS = 400
    private weak var window: NSWindow?
    private var release: Task<Void, Never>?

    func hold(_ window: NSWindow?) {
        // One already held is held a little longer; one that something else
        // keeps still is left alone, and so is one in a hand.
        guard let window, window.isMovable || window === self.window, NSEvent.pressedMouseButtons == 0 else { return }
        if window !== self.window { letGo() }
        self.window = window
        window.isMovable = false
        release?.cancel()
        // Holds the window and not this, so a window always gets it back,
        // even from an editor that has gone.
        release = Task { @MainActor [weak self, weak window] in
            try? await Task.sleep(for: .milliseconds(Self.holdMS))
            guard !Task.isCancelled else { return }
            window?.isMovable = true
            self?.window = nil
        }
    }

    private func letGo() {
        release?.cancel()
        release = nil
        window?.isMovable = true
        window = nil
    }
}
