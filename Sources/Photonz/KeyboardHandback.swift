import AppKit
import PhotonzCore
import SwiftUI

/// Giving the keyboard back to the picture.
///
/// A text field that keeps the keyboard after you are finished with it is a
/// trap: every tool letter becomes a character in the number, and clicking the
/// canvas is the only way out. So every field that can be finished (Return,
/// Escape) asks for this the moment it is done, and the canvas answers the
/// next key the way it always does — tool letters pick tools, arrows nudge the
/// layer.
enum KeyboardHandback {

    /// Hand the keyboard to the canvas of the window that has it.
    ///
    /// Deferred a tick on purpose: this is called from inside a key press the
    /// field editor is still handling, and changing first responder in the
    /// middle of that re-enters AppKit's responder hand-off.
    ///
    /// With no canvas on screen (a dialog, the video window) the field simply
    /// lets go, which is still better than holding on.
    static func toCanvas() {
        DispatchQueue.main.async {
            // Every window, not just the key one: an app that is not frontmost
            // has no key window at all (which is exactly the state a probe run
            // is in), and the field would keep the keyboard forever.
            let windows = [NSApp.keyWindow, NSApp.mainWindow].compactMap { $0 } + NSApp.windows
            for window in windows {
                guard let content = window.contentView,
                      let canvas = firstCanvas(in: content) else { continue }
                window.makeFirstResponder(canvas)
                return
            }
            // No canvas on screen (a dialog, the video window): letting go of
            // the keyboard is still better than holding on to it.
            for window in windows where window.firstResponder is NSText {
                window.makeFirstResponder(nil)
                return
            }
        }
    }

    private static func firstCanvas(in view: NSView) -> CanvasNSView? {
        if let canvas = view as? CanvasNSView { return canvas }
        for subview in view.subviews {
            if let canvas = firstCanvas(in: subview) { return canvas }
        }
        return nil
    }
}

extension View {
    /// The keys of a typed number field, in one place: Return lands the number,
    /// Escape puts it back, both hand the keyboard to the picture, and up and
    /// down step the number without letting go. The rule itself lives in
    /// `NumberFieldEntry`, so the geometry fields and the canvas size fields
    /// cannot answer the same key differently.
    ///
    /// It has to watch EVERY key rather than a list of four: a key list matches
    /// on the key alone and ⇧↑ never reaches it, because the field editor takes
    /// that one first as "extend the selection upward".
    ///
    /// `commit` and `revert` run before the keyboard moves, so the field is
    /// already showing the number the layer really has by the time it loses
    /// focus, and whatever it does on focus loss cannot land an abandoned draft.
    func numberFieldKeys(isEditable: Bool = true,
                         commit: @escaping () -> Void,
                         revert: @escaping () -> Void,
                         step: @escaping (_ direction: Int, _ coarse: Bool) -> Void) -> some View {
        onKeyPress(phases: .down) { press in
            guard isEditable else { return .ignored }
            let key: NumberFieldEntry.Key
            switch press.key {
            // ⏎ and the keypad's Enter. Left and right stay caret movement,
            // the way they do in every other number field.
            case .return, KeyEquivalent("\u{3}"): key = .return
            case .escape: key = .escape
            case .upArrow: key = .upArrow
            case .downArrow: key = .downArrow
            default: return .ignored
            }
            let action = NumberFieldEntry.action(for: key, shift: press.modifiers.contains(.shift))
            switch action {
            case .commitAndRelease: commit()
            case .revertAndRelease: revert()
            case .step(let direction, let coarse): step(direction, coarse)
            case .type: return .ignored
            }
            if NumberFieldEntry.releasesKeyboard(action) { KeyboardHandback.toCanvas() }
            return .handled
        }
    }
}
