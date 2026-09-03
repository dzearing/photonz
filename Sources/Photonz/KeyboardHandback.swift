import AppKit
import PhotonzCore
import SwiftUI

/// Giving the keyboard back to the picture.
///
/// A text field that keeps the keyboard after you are finished with it is a
/// trap: every tool letter becomes a character in the box, and clicking the
/// canvas is the only way out. So every field that can be finished (Return,
/// Escape) asks for this the moment it is done, and the canvas answers the
/// next key the way it always does — tool letters pick tools, arrows nudge the
/// layer. Numbers and words alike: `numberFieldKeys` and `nameFieldKeys` below
/// are the two doors into it.
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

    /// The keys of a typed WORD field — a name, a label, a caption, a search
    /// box — in one place: Return lands it, Escape puts things back, and both
    /// hand the keyboard to the picture so the next tool letter picks a tool.
    /// The rule itself lives in `NameFieldEntry`, next door to the number
    /// fields' `NumberFieldEntry`, so the two kinds of field finish the same
    /// way.
    ///
    /// Every other key is left alone, arrows included: there is no next name to
    /// step to, so up and down stay caret movement.
    ///
    /// `commit` and `revert` run before the keyboard moves, so a field that
    /// also commits when it loses focus is already showing what the document
    /// really holds by then and cannot land the same draft twice.
    /// `canCommit` is false when there is nothing for Return to land — an empty
    /// search, say. Return then does nothing and the field KEEPS the keyboard,
    /// so a typo is one backspace away instead of a hunt for the box again.
    /// Escape still works: giving up is always available.
    func nameFieldKeys(isEditable: Bool = true,
                       canCommit: Bool = true,
                       commit: @escaping () -> Void,
                       revert: @escaping () -> Void) -> some View {
        onKeyPress(phases: .down) { press in
            guard isEditable else { return .ignored }
            let key: NameFieldEntry.Key
            switch press.key {
            // ⏎ and the keypad's Enter. Tab still walks to the next field, the
            // way it does in every Mac dialog, and goes through `onSubmit`.
            case .return, KeyEquivalent("\u{3}"): key = .return
            case .escape: key = .escape
            default: return .ignored
            }
            guard canCommit || key != .return else { return .ignored }
            let action = NameFieldEntry.action(for: key)
            switch action {
            case .commitAndRelease: commit()
            case .revertAndRelease: revert()
            case .type: return .ignored
            }
            if NameFieldEntry.releasesKeyboard(action) { KeyboardHandback.toCanvas() }
            return .handled
        }
    }
}
