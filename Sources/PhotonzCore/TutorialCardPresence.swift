import Foundation

/// Whether a running guide's card and ring belong on screen right now.
///
/// A guide floats two panels over the window it is teaching in. They are
/// hidden when the window is buried, for one reason only: a card that stayed
/// up over a covered window would be a card floating on top of whatever the
/// person has actually got in front of them.
///
/// That reason does not apply to a scripted walk. A walk drives a window it
/// never brings to the front and photographs that window directly, so what
/// happens to be in front of it — another app, the screen saver, the login
/// window over a locked Mac — is noise. Letting that noise decide whether the
/// card is drawn makes the same walk on the same code answer one way with
/// somebody at the Mac and another way with nobody there, and the pictures it
/// ships are of a window with no card in it while the walk still reports a
/// pass. On the night of 2026-09-14 that cost 31 of 31 tutorial walks and sent
/// runners hunting bugs that were not in the app (`PlaytestScreenState`).
///
/// So: a person's window has to be uncovered, a walk's window does not.
public enum TutorialCardPresence {

    /// - Parameters:
    ///   - miniaturized: the teaching window is in the Dock, so there is
    ///     nowhere to hang a card.
    ///   - windowVisible: any part of the teaching window is really visible,
    ///     which is `NSWindow.occlusionState.contains(.visible)`.
    ///   - aWalkIsDriving: a scripted playtest is driving this app.
    public static func shouldBeOnScreen(miniaturized: Bool,
                                        windowVisible: Bool,
                                        aWalkIsDriving: Bool) -> Bool {
        if miniaturized { return false }
        if aWalkIsDriving { return true }
        return windowVisible
    }
}
