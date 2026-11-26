import AppKit
import PhotonzCore
import SwiftUI

// Full screen (`PlayerFullScreen`): F in the player, Escape out of it, View ▸
// Enter Full Screen on ⌃⌘F everywhere, a double click on the canvas, and the
// transport's button all come here. The transport fades away full screen the
// same way it does in a window (`EditorState+PlayerControlsFade`).
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
        // The window's own title bar is the Mac's in full screen; whatever
        // the fade left it at is put back as the window changes over.
        showPlayerTitleBar()
        watchPlayerControls()
    }
}

/// The transport fading out of the way while a video is watched, and back the
/// moment the pointer moves (`PlayerControlsFade`). Opacity and hit testing
/// only: it keeps its room, so the picture never refits as it comes and goes.
struct PlayerControlsTuck: ViewModifier {
    @Environment(EditorState.self) private var editorState

    func body(content: Content) -> some View {
        let tucked = editorState.arePlayerControlsTuckedAway
        content
            .opacity(tucked ? 0 : 1)
            .allowsHitTesting(!tucked)
    }
}
