import AppKit
import PhotonzCore
import QuartzCore
import SwiftUI

// The player's controls fading away while a video is watched in View, the way
// QuickTime's do (`PlayerControlsFade` decides; this watches and does it). The
// transport, and in a window the title bar with its buttons, ease out a moment
// after the last thing a person did and come straight back on a mouse move
// over the window, a key, a click on the picture, or play starting or
// stopping. The pointer hides over the picture with them.
//
// One timer per window, looking at the pointer five times a second, and
// nothing on the play path: a frame of the video changes nothing here.
extension EditorState {

    /// Start the window's one look at the pointer. Safe to ask again.
    func watchPlayerControls() {
        guard playerControlsWatch == nil else { return }
        playerIdleSince = CACurrentMediaTime()
        playerWasPlaying = isDocumentPlaying
        let timer = Timer(timeInterval: PlayerControlsFade.pointerLookSeconds, repeats: true) { [weak self] timer in
            // A window that has gone takes its look with it.
            guard self != nil else { timer.invalidate(); return }
            MainActor.assumeIsolated { self?.lookAtThePlayer() }
        }
        // Common modes, so it still looks while a menu is open or a drag runs.
        RunLoop.main.add(timer, forMode: .common)
        playerControlsWatch = timer
    }

    /// A person did something to the player: a key, a click on the picture,
    /// a walk's hand. The controls come back now and the wait starts again.
    func notePlayerActivity() {
        playerIdleSince = CACurrentMediaTime()
        if arePlayerControlsTuckedAway { setPlayerControlsFaded(false, hidePointer: false) }
    }

    /// The window's title bar as it should be with the controls up.
    func showPlayerTitleBar() {
        guard let bar = playerTitleBar, bar.alphaValue != 1 else { return }
        bar.alphaValue = 1
    }

    private func lookAtThePlayer() {
        guard let window = hostWindow else {
            playerControlsWatch?.invalidate()
            playerControlsWatch = nil
            return
        }
        let now = CACurrentMediaTime()
        // Only a player fades; the editor never does. A window under other
        // windows still keeps time, so it reads the same however it is
        // covered (a walk's window always sits under the person's).
        guard isWatching, documentHasTime, window.isVisible else {
            playerIdleSince = now
            playerPointerLastSeen = nil
            if arePlayerControlsTuckedAway { setPlayerControlsFaded(false, hidePointer: false) }
            return
        }
        let playing = isDocumentPlaying
        if playing != playerWasPlaying {
            playerWasPlaying = playing
            playerIdleSince = now
        }
        let pointer = pointerOverPlayer(window)
        if pointer != playerPointerLastSeen {
            // Into the window or across it is a move; out of it is not.
            if pointer != nil { playerIdleSince = now }
            playerPointerLastSeen = pointer
        }
        let overControls = pointer.map { isOverPlayerControls($0, in: window) } ?? false
        let moment = PlayerControlsFade.Moment(watching: true, playing: playing,
                                               secondsIdle: now - playerIdleSince,
                                               pointerOverControls: overControls,
                                               held: playerControlsHeld(window))
        let faded = PlayerControlsFade.faded(moment)
        if faded != arePlayerControlsTuckedAway {
            setPlayerControlsFaded(faded, hidePointer: pointer != nil)
        }
    }

    /// Where the pointer is over this window, in its own coordinates, or nil
    /// when it is anywhere else (another app's window on top of it included).
    /// A walk's pointer is its own, never the person's (`PlaytestPointer`).
    private func pointerOverPlayer(_ window: NSWindow) -> CGPoint? {
        #if PHOTONZ_PLAYTEST
        if PlaytestHarness.isDrivingAWalk { return PlaytestPointer.location(in: window) }
        #endif
        let onScreen = NSEvent.mouseLocation
        guard NSWindow.windowNumber(at: onScreen, belowWindowWithWindowNumber: 0) == window.windowNumber
        else { return nil }
        return window.convertPoint(fromScreen: onScreen)
    }

    /// The pointer rests on the controls: the transport along the bottom, or
    /// in a window the title bar along the top.
    private func isOverPlayerControls(_ point: CGPoint, in window: NSWindow) -> Bool {
        if point.y <= timelineDockFrame.height + 8 { return true }
        if !isWindowFullScreen, point.y >= window.contentLayoutRect.maxY - 4 { return true }
        return false
    }

    /// Something is open off the controls or a hand is on them: a menu (the
    /// speed menu, a right-click), a popover, a sheet, a guide's card, or the
    /// play bar being dragged.
    private func playerControlsHeld(_ window: NSWindow) -> Bool {
        playerControlsHeldBy = playerControlsHolder(window)
        return playerControlsHeldBy != nil
    }

    /// What is holding the controls up, in a word a walk can print.
    private func playerControlsHolder(_ window: NSWindow) -> String? {
        if playheadInHand { return "a hand on the play bar" }
        if TutorialController.shared.isRunning { return "a guide" }
        if RunLoop.current.currentMode == .eventTracking { return "a menu or a drag" }
        if window.attachedSheet != nil { return "a sheet" }
        // A popover or a tip is a panel of its own on the window. Not every
        // child window is one: while the window is being shared or filmed
        // (a call, a screen recording) the Mac hangs one of its own on it,
        // and that held the controls up for as long as the sharing lasted.
        if let open = window.childWindows?.first(where: Self.isPopoverLike) {
            return "a popover (\(type(of: open)))"
        }
        return nil
    }

    private static func isPopoverLike(_ child: NSWindow) -> Bool {
        guard child.isVisible, child.alphaValue > 0 else { return false }
        return child is NSPanel || String(describing: type(of: child)).contains("Popover")
    }

    private func setPlayerControlsFaded(_ faded: Bool, hidePointer: Bool) {
        let seconds = faded ? PlayerControlsFade.fadeOutSeconds : PlayerControlsFade.fadeInSeconds
        withAnimation(faded ? .easeInOut(duration: seconds) : .easeOut(duration: seconds)) {
            arePlayerControlsTuckedAway = faded
        }
        // In a window the title bar and its buttons go with them, as
        // QuickTime's do; full screen, the title bar is the Mac's.
        if let bar = playerTitleBar, !isWindowFullScreen {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = seconds
                context.timingFunction = CAMediaTimingFunction(name: faded ? .easeInEaseOut : .easeOut)
                bar.animator().alphaValue = faded ? 0 : 1
            }
        }
        playerHidesPointer = faded && hidePointer
        guard playerHidesPointer else { return }
        #if PHOTONZ_PLAYTEST
        // A walk never touches the person's own pointer.
        if PlaytestHarness.isDrivingAWalk { return }
        #endif
        if NSApp.isActive, hostWindow?.isKeyWindow == true { NSCursor.setHiddenUntilMouseMoves(true) }
    }

    /// The window's title bar: the traffic lights, the title and the buttons
    /// along it, as one view.
    private var playerTitleBar: NSView? {
        hostWindow?.standardWindowButton(.closeButton)?.superview?.superview
    }
}
