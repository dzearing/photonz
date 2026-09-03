import Foundation

/// The rules of a typed number field in the inspector: what each key does, and
/// in particular when the field is finished with the keyboard.
///
/// The idea in one line: **typing a number is a moment, not a mode.** A field
/// that holds the keyboard after you are done with it turns the next tool
/// letter into a digit and leaves clicking the picture as the only way out.
/// So Return lands the number and Escape puts it back, and both hand the
/// keyboard to the picture, where the tool keys and the nudge arrows live.
///
/// Up and down still step the number for as long as you are working in the
/// field, because stepping IS working in the field. Every other key types, so
/// a tool letter never steals a digit from a half-typed number.
///
/// Every number field reads its keys from here, so the geometry fields and the
/// canvas size fields cannot drift apart.
public enum NumberFieldEntry {

    public enum Key: Equatable, Sendable {
        case `return`
        case escape
        case upArrow
        case downArrow
        /// Everything else, including the tool shortcut letters.
        case other
    }

    public enum Action: Equatable, Sendable {
        /// Land the draft on the layer and let the keyboard go.
        case commitAndRelease
        /// Put the field back to the number the layer really has, land
        /// nothing, and let the keyboard go.
        case revertAndRelease
        /// Step the number in place. Direction is 1 up, -1 down; `coarse` is
        /// the Shift-sized step.
        case step(direction: Int, coarse: Bool)
        /// An ordinary keystroke the field editor should handle itself.
        case type
    }

    public static func action(for key: Key, shift: Bool) -> Action {
        switch key {
        case .return: .commitAndRelease
        case .escape: .revertAndRelease
        case .upArrow: .step(direction: 1, coarse: shift)
        case .downArrow: .step(direction: -1, coarse: shift)
        case .other: .type
        }
    }

    /// Whether the draft in the field reaches the layer. False for the two
    /// actions that must never commit: an abandoned draft, and a keystroke
    /// that is still being typed.
    public static func lands(_ action: Action) -> Bool {
        action == .commitAndRelease
    }

    /// Whether the keyboard goes back to the picture after this action.
    public static func releasesKeyboard(_ action: Action) -> Bool {
        switch action {
        case .commitAndRelease, .revertAndRelease: true
        case .step, .type: false
        }
    }
}
