import AppKit
import SwiftUI

/// Installs the standard "Do you want to save the changes…" confirmation on an
/// editor window. SwiftUI's `WindowGroup` offers no close veto, so a delegate
/// PROXY takes the window's delegate slot: it answers `windowShouldClose`
/// itself and transparently forwards every other delegate call to SwiftUI's
/// original delegate (which still runs scene teardown, resize persistence, …).
struct WindowCloseGuard: NSViewRepresentable {
    let editorState: EditorState

    func makeNSView(context: Context) -> InstallerView {
        let view = InstallerView()
        view.editorState = editorState
        return view
    }

    func updateNSView(_ nsView: InstallerView, context: Context) {
        nsView.editorState = editorState
    }

    /// Installs the guard whenever the view lands in a window. Keyed on the
    /// window's associated proxy — NOT on `editorState.hostWindow`, which the
    /// fit-window-on-open path (`canvasDidMoveToWindow`) also sets, and usually
    /// sets first. Using it as the "already installed" marker silently disabled
    /// the guard entirely (the v0.12.0 silent-discard regression).
    final class InstallerView: NSView {
        weak var editorState: EditorState?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // Deferred a tick so SwiftUI's own window delegate is in place
            // first — the proxy must capture it to keep scene teardown working.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let editorState = self?.editorState, let window,
                      objc_getAssociatedObject(window, &CloseGuardDelegate.associationKey) == nil
                else { return }
                editorState.hostWindow = window
                let proxy = CloseGuardDelegate(original: window.delegate, editorState: editorState)
                objc_setAssociatedObject(window, &CloseGuardDelegate.associationKey,
                                         proxy, .OBJC_ASSOCIATION_RETAIN)
                window.delegate = proxy
            }
        }
    }
}

/// App-termination support: quitting must offer the same protection as
/// closing each window (the user chose "yes" to a ⌘Q guard).
@MainActor
enum CloseGuards {

    /// Visible editor windows currently holding unsaved changes.
    static func dirtyEditorWindows() -> [NSWindow] {
        NSApp.windows.filter { window in
            guard window.isVisible, let proxy = guardProxy(for: window) else { return false }
            return proxy.editor?.hasUnsavedChanges == true
        }
    }

    /// The "Review Changes…" quit flow: walk each dirty window front-to-back,
    /// presenting its standard save sheet. Calls `completion(true)` when every
    /// window resolved (saved or discarded), `completion(false)` the moment a
    /// sheet is cancelled — the user changed their mind about quitting.
    static func reviewAndClose(windows: [NSWindow], completion: @escaping @MainActor (Bool) -> Void) {
        var remaining = windows
        func next() {
            guard let window = remaining.first else {
                completion(true)
                return
            }
            remaining.removeFirst()
            guard let proxy = guardProxy(for: window),
                  proxy.editor?.hasUnsavedChanges == true else {
                next() // already clean (or gone) — nothing to review
                return
            }
            window.makeKeyAndOrderFront(nil)
            proxy.presentSaveConfirmation(on: window) { resolved in
                resolved ? next() : completion(false)
            }
        }
        next()
    }

    private static func guardProxy(for window: NSWindow) -> CloseGuardDelegate? {
        objc_getAssociatedObject(window, &CloseGuardDelegate.associationKey) as? CloseGuardDelegate
    }
}

/// The forwarding proxy. Kept alive by an associated-object reference on the
/// window (NSWindow.delegate is weak).
@MainActor
private final class CloseGuardDelegate: NSObject, NSWindowDelegate {
    nonisolated(unsafe) static var associationKey: UInt8 = 0

    // `nonisolated(unsafe)`: read from the nonisolated forwarding overrides
    // below; window delegate dispatch only ever happens on the main thread.
    nonisolated(unsafe) private weak var original: (any NSWindowDelegate)?
    private weak var editorState: EditorState?

    /// The guarded editor, for the app-termination sweep.
    var editor: EditorState? { editorState }

    init(original: (any NSWindowDelegate)?, editorState: EditorState) {
        self.original = original
        self.editorState = editorState
    }

    // Transparent forwarding: claim and relay every selector the original
    // delegate handles, so SwiftUI's window management keeps working.
    override nonisolated func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (original?.responds(to: aSelector) ?? false)
    }

    override nonisolated func forwardingTarget(for aSelector: Selector!) -> Any? {
        if original?.responds(to: aSelector) == true { return original }
        return super.forwardingTarget(for: aSelector)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let editorState, editorState.hasUnsavedChanges else {
            // Clean — defer to SwiftUI's own decision, if it has one. (Returning
            // focus to the app behind is handled in AppCoordinator's willClose
            // observer, the one hook that fires for every close path.)
            return original?.windowShouldClose?(sender) ?? true
        }
        presentSaveConfirmation(on: sender)
        return false // the sheet's completion closes the window when appropriate
    }

    /// The standard three-option save sheet (Save / Cancel / Don't Save).
    /// `completion(true)` when the window resolved (saved or discarded, and
    /// closed); `completion(false)` when the user cancelled — used by the
    /// quit-review flow to abort termination.
    func presentSaveConfirmation(on window: NSWindow,
                                 completion: (@MainActor (Bool) -> Void)? = nil) {
        guard let editorState else {
            completion?(true)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes made to “\(editorState.windowTitle)”?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save…")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, let editorState = self.editorState else {
                completion?(true)
                return
            }
            switch response {
            case .alertFirstButtonReturn: // Save
                editorState.saveDocument()
                // A cancelled Save-As panel leaves the document dirty — the
                // window stays open rather than silently dropping the edits.
                if !editorState.hasUnsavedChanges {
                    window.close() // close(), not performClose(): skip re-asking
                    completion?(true)
                } else {
                    completion?(false)
                }
            case .alertThirdButtonReturn: // Don't Save
                window.close()
                completion?(true)
            default: // Cancel
                completion?(false)
            }
        }
    }
}
