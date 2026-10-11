import AppKit
import PhotonzCore
import SwiftUI

// Full screen (`PlayerFullScreen`): F in the player, Escape out of it, View ▸
// Enter Full Screen on ⌃⌘F everywhere, a double click on the canvas, and the
// transport's button all come here. While a video plays full screen with the
// pointer still, the transport tucks away and the pointer hides, QuickTime's
// way; a nudge of the mouse brings both back.
extension EditorState {

    /// In if out, out if in.
    func toggleWindowFullScreen() {
        guard let window = hostWindow else { return }
        // The Mac drops a toggle asked for while the window is still sliding,
        // so F pressed twice quickly would leave it full screen. The latest
        // ask is kept instead and carried out the moment the slide lands.
        if let moving = fullScreenSlideTarget {
            fullScreenAskedDuringSlide = !(fullScreenAskedDuringSlide ?? moving)
            return
        }
        // Only a regular app's windows may fill the screen, and a window built
        // while the app was still the menu-bar agent is stamped `fullScreenNone`
        // for life. A window a person has open is already both, so for them
        // this changes nothing; it is what makes the command sure to work.
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        if window.collectionBehavior.contains(.fullScreenNone) || !window.collectionBehavior.contains(.fullScreenPrimary) {
            window.collectionBehavior.remove(.fullScreenNone)
            window.collectionBehavior.insert(.fullScreenPrimary)
        }
        window.toggleFullScreen(nil)
    }

    /// Out, and nothing if already out.
    func leaveWindowFullScreen() {
        guard isWindowFullScreen else { return }
        toggleWindowFullScreen()
    }

    /// F and Escape in the player. True when the press was full screen's.
    func fullScreenKeyDown(_ press: TimelineKeyPress) -> Bool {
        guard let command = PlayerFullScreen.command(for: press, watching: isWatching,
                                                     isFullScreen: isWindowFullScreen) else { return false }
        switch command {
        case .toggle: toggleWindowFullScreen()
        case .leave: leaveWindowFullScreen()
        }
        return true
    }

    /// Follow the window's own notices, so a green button, a double click and
    /// the menu all read the same answer.
    func watchHostWindowFullScreen() {
        let center = NotificationCenter.default
        fullScreenNotices.forEach(center.removeObserver)
        fullScreenNotices = []
        guard let window = hostWindow else { return }
        noteFullScreen(window.styleMask.contains(.fullScreen))
        // From the moment the window starts to move rather than when it
        // lands, so a press during the slide (Escape straight after F) reads
        // where it is going. Where it lands is read off the window itself.
        let notices: [(NSNotification.Name, Bool?)] = [
            (NSWindow.willEnterFullScreenNotification, true), (NSWindow.willExitFullScreenNotification, false),
            (NSWindow.didEnterFullScreenNotification, nil), (NSWindow.didExitFullScreenNotification, nil),
        ]
        for (name, going) in notices {
            fullScreenNotices.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let going {
                        self.fullScreenSlideTarget = going
                        self.noteFullScreen(going)
                        return
                    }
                    let landed = self.hostWindow?.styleMask.contains(.fullScreen) ?? false
                    self.fullScreenSlideTarget = nil
                    self.noteFullScreen(landed)
                    if let asked = self.fullScreenAskedDuringSlide {
                        self.fullScreenAskedDuringSlide = nil
                        // Not from inside the notice: the Mac is still
                        // finishing the slide then, and drops it.
                        if asked != landed {
                            DispatchQueue.main.async { [weak self] in self?.toggleWindowFullScreen() }
                        }
                    }
                }
            })
        }
    }

    private func noteFullScreen(_ full: Bool) {
        if isWindowFullScreen != full { isWindowFullScreen = full }
        if full { watchPlayerControls() } else { stopWatchingPlayerControls() }
    }

    // MARK: The transport tucking away

    /// How often the pointer is looked at while the window fills the screen:
    /// often enough that the controls come back the moment it moves.
    private static let pointerLookSeconds: TimeInterval = 0.2

    private func watchPlayerControls() {
        guard playerControlsWatch == nil else { return }
        pointerLastSeen = NSEvent.mouseLocation
        pointerStillSince = Date()
        let timer = Timer(timeInterval: Self.pointerLookSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.lookAtThePointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        playerControlsWatch = timer
    }

    private func stopWatchingPlayerControls() {
        playerControlsWatch?.invalidate()
        playerControlsWatch = nil
        setPlayerControlsTuckedAway(false)
    }

    private func lookAtThePointer() {
        let now = Date()
        let pointer = NSEvent.mouseLocation
        if pointer != pointerLastSeen {
            pointerLastSeen = pointer
            pointerStillSince = now
        }
        var overControls = false
        if let window = hostWindow {
            // The transport is the dock along the bottom of the window.
            let inWindow = window.convertPoint(fromScreen: pointer)
            overControls = window.frame.contains(pointer) && inWindow.y <= timelineDockFrame.height + 8
        }
        setPlayerControlsTuckedAway(PlayerFullScreen.controlsTuckedAway(
            isFullScreen: isWindowFullScreen, watching: isWatching, playing: isDocumentPlaying,
            secondsPointerStill: now.timeIntervalSince(pointerStillSince), pointerOverControls: overControls))
    }

    private func setPlayerControlsTuckedAway(_ tucked: Bool) {
        guard arePlayerControlsTuckedAway != tucked else { return }
        withAnimation(.easeInOut(duration: 0.3)) { arePlayerControlsTuckedAway = tucked }
        if tucked { NSCursor.setHiddenUntilMouseMoves(true) }
    }
}

/// The transport fading out of the way while a video plays full screen, and
/// back the moment the pointer moves (`PlayerFullScreen`).
struct PlayerControlsTuck: ViewModifier {
    @Environment(EditorState.self) private var editorState

    func body(content: Content) -> some View {
        let tucked = editorState.arePlayerControlsTuckedAway
        content
            .opacity(tucked ? 0 : 1)
            .allowsHitTesting(!tucked)
    }
}
