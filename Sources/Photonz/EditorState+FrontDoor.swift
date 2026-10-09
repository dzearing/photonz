import AppKit
import PhotonzCore

// The front door New Window opens (Next, `next-front-door`,
// `ui-entry-wt.html` steps 2 to 5). It is an editor window that holds no
// document and never comes to: what it makes opens in an editor window of its
// own, and the front door closes on its own once that window is up.
extension EditorState {

    /// Whether this is the front door. A window that has taken a document in
    /// (a picture dropped on it, a paste) is an editor like any other.
    var isFrontDoor: Bool { frontDoorChoice == true && document == nil }

    /// Close the front door once the window it asked for is in front.
    ///
    /// Not at once: focus goes back to the most recently used thing when a
    /// window closes (`AppCoordinator.editorWindowWillClose`), and while the
    /// new window is still on its way that thing is whatever app was in front
    /// before, which would then be brought forward over the editor somebody
    /// just asked for. So it waits for the new window to become main, which is
    /// what puts it first in that list, and closes then. A window that never
    /// becomes main (a scripted walk keeps every window behind the person)
    /// still closes the front door after a moment.
    func closeFrontDoorOnceTheEditorOpens() {
        guard frontDoorChoice == true, frontDoorClosing == nil, let window = hostWindow else { return }
        frontDoorClosing = FrontDoorCloser(frontDoor: window)
    }

    /// Close the front door now: for a capture, which opens no window until a
    /// rectangle has been drawn, and which wants the screen to itself.
    func closeFrontDoorNow() {
        guard frontDoorChoice == true else { return }
        hostWindow?.close()
    }
}

/// Waits for another editor window to become main, then closes the front door.
@MainActor
final class FrontDoorCloser {
    private weak var frontDoor: NSWindow?
    private var observer: (any NSObjectProtocol)?

    /// How long a front door waits for a window that never becomes main.
    static let longestWait: Double = 1.5

    init(frontDoor: NSWindow) {
        self.frontDoor = frontDoor
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main) { [weak self] note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                guard let self, let window, window !== self.frontDoor, !(window is NSPanel) else { return }
                // A pass later, so the list of recently used windows has
                // already put the new one first.
                DispatchQueue.main.async { self.close() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.longestWait) { [weak self] in
            self?.close()
        }
    }

    private func close() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        frontDoor?.close()
        frontDoor = nil
    }
}
