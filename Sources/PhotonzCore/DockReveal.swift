import CoreGraphics

/// Bringing a dock section into view when the app opens it for you.
///
/// The right dock is one tall scrolling column, so a section the app turns on
/// for you — the Library shelf, when making a component fills it — can land
/// below the fold. You press the key, the app says it did something, and
/// nothing you are looking at changes. This decides what the dock should do
/// about that, and its first answer is usually to do nothing: a shelf already
/// on screen must not twitch just because the app pointed at it again.
///
/// All measurements are in points, taken with the top of the dock's visible
/// area as zero, so a negative `sectionTop` means the section starts above the
/// fold.
public enum DockReveal {
    /// What the dock should do to put a section on screen.
    public enum Action: Equatable, Sendable {
        /// The section is readable where it is. Nothing moves.
        case none
        /// Line the section's top up with the top of the dock. Used when the
        /// section is above the fold, and when it is taller than the dock and
        /// so can never fit: then its beginning is the part worth showing.
        case top
        /// Line the section's bottom up with the bottom of the dock. The
        /// shortest move that puts a section below the fold on screen, which
        /// keeps as much of what you were already looking at as it can.
        case bottom
    }

    /// Rounding slack, in points. Measured frames arrive with sub-point dust on
    /// them, and a section one third of a point short of the edge is a section
    /// you can read.
    static let slack: CGFloat = 0.5

    /// What to do to bring a section into view.
    ///
    /// - Parameters:
    ///   - sectionTop: the section's top edge, measured from the top of the
    ///     dock's visible area. Negative when it starts above the fold.
    ///   - sectionHeight: how tall the section is.
    ///   - viewportHeight: how tall the dock's visible area is.
    public static func action(sectionTop: CGFloat,
                              sectionHeight: CGFloat,
                              viewportHeight: CGFloat) -> Action {
        // Nothing measured yet (a section that has not been laid out, a dock
        // with no height): moving on a guess is worse than waiting.
        guard viewportHeight > 0, sectionHeight > 0 else { return .none }
        let sectionBottom = sectionTop + sectionHeight
        // Taller than the dock: it can never be all on screen, so "in view"
        // means it fills the dock. Once it does, leave it exactly where the
        // reader left it.
        if sectionHeight >= viewportHeight - slack {
            let fillsTheDock = sectionTop <= slack && sectionBottom >= viewportHeight - slack
            return fillsTheDock ? .none : .top
        }
        if sectionTop >= -slack && sectionBottom <= viewportHeight + slack { return .none }
        return sectionTop < 0 ? .top : .bottom
    }
}
