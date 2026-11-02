/// How strongly an icon button's glyph is drawn: the one rule every icon
/// button in the panels reads, so a button you can press never looks like one
/// you cannot.
///
/// The user, 2026-10-24, pointing at the cross that takes an effect out of the
/// list: "the remove x button on effects seems disabled but it is not. buttons
/// which are active should not look diminished. look at the eye visibility
/// icon button next to it." The cross wore the system's tertiary label, which
/// is the tone of a disabled control, beside an eye in the full label tone.
///
/// `ink` is how much of the full foreground (black in light, white in dark)
/// the glyph is drawn with; the numbers are the Mac's own label colours, so a
/// button at rest reads exactly as a label does. `wash` is the soft fill drawn
/// behind the glyph under the pointer.
public enum IconButtonTone: Sendable, Equatable, CaseIterable {
    /// Can be pressed, nothing happening: the system's label tone, the eye's.
    case rest
    /// The pointer is on it: a little brighter, with a soft wash behind.
    case hovered
    /// Held down: the hover's ink with a stronger wash.
    case pressed
    /// A switch that is off (a hidden layer's eye, an open padlock): the
    /// system's secondary label, quieter than on and well clear of disabled.
    case off
    /// Cannot be pressed: the only tone drawn faint.
    case disabled

    /// The system's label colour, as a share of the full foreground (0.85 in
    /// both light and dark on macOS 26).
    public static let labelInk = 0.85

    /// How far above the disabled tone every tone of a button you can press
    /// must sit, so the two can never be mistaken for each other.
    public static let enabledMargin = 0.25

    public init(enabled: Bool, isOn: Bool = true, look: ButtonPointerLook) {
        if !enabled {
            self = .disabled
        } else {
            switch look {
            case .pressed: self = .pressed
            case .hovered: self = .hovered
            case .rest: self = isOn ? .rest : .off
            }
        }
    }

    public var ink: Double {
        switch self {
        case .rest: Self.labelInk
        case .hovered, .pressed: 1
        // The system's secondary label (0.55 dark, 0.50 light).
        case .off: 0.55
        // The system's tertiary label (0.25 dark, 0.26 light).
        case .disabled: 0.25
        }
    }

    public var wash: Double {
        switch self {
        case .hovered: 0.10
        case .pressed: 0.18
        case .rest, .off, .disabled: 0
        }
    }
}
