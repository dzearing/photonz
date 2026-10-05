/// How a button answers the pointer: quiet at rest, a soft fill under the
/// pointer, a stronger one while pressed. A button that cannot be pressed
/// does not answer at all, so it never says "press me" and then does nothing
/// (the shared button styles in the app all read this).
public enum ButtonPointerLook: Sendable, Equatable {
    case rest, hovered, pressed

    /// - Parameters:
    ///   - enabled: whether the button can be pressed. A disabled one rests.
    ///   - hovering: whether the pointer is on it.
    ///   - pressed: whether it is held down.
    ///   - answersHover: whether this button shows a hover at all (Current's
    ///     tool bar shows only a press).
    public init(enabled: Bool, hovering: Bool, pressed: Bool, answersHover: Bool = true) {
        if !enabled {
            self = .rest
        } else if pressed {
            self = .pressed
        } else if hovering && answersHover {
            self = .hovered
        } else {
            self = .rest
        }
    }

    /// Hovered or pressed: the button is drawn brightened.
    public var isLit: Bool { self != .rest }

    public var isPressed: Bool { self == .pressed }
}
