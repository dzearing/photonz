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

// MARK: - ...and what the action PRODUCED

extension DockReveal {

    /// Where a reveal leaves the dock once the thing an action produced has
    /// had its say.
    public enum Reveal: Equatable, Sendable {
        /// Nothing moves.
        case nothing
        /// The reveal gets what it asked for: scroll to the revealed section,
        /// doing this.
        case reveal(Action)
        /// The reveal cannot have what it asked for without cutting the
        /// produced section, so the dock scrolls to the PRODUCED section
        /// instead, doing this. `.top` is the usual one: as far towards the
        /// revealed section as the produced section can afford.
        case produced(Action)
    }

    /// **After an action, the panel looks at what the action produced.**
    ///
    /// A reveal is the app pointing at something you could not have known was
    /// there. It is never allowed to do that at the cost of the thing you just
    /// made. Dropping a component on the canvas used to scroll the dock all
    /// the way to the Library shelf, which pushed the new component's own
    /// section clean off the top of the panel: the answer to "what did I just
    /// put down" was above the edge, and you scrolled back up to it every
    /// time (reported 2026-09-22).
    ///
    /// So the produced section sets a cap on how far the dock may travel, and
    /// the reveal spends whatever is left. On the window that reported it, the
    /// shelf wanted 270 points of travel and the new Component section could
    /// afford 169, so the dock goes 169: the component is whole at the top of
    /// the panel, and the shelf's head comes up at the bottom edge saying it
    /// is one flick away rather than vanishing.
    ///
    /// The cap works both ways, so this is also how a produced section that is
    /// ALREADY off the top comes back: there is nothing to reveal, the cap is
    /// negative, and the dock scrolls up to it.
    ///
    /// - Parameters:
    ///   - sectionTop: the section to reveal, measured from the top of the
    ///     dock's visible area.
    ///   - sectionHeight: how tall that section is.
    ///   - keepingWholeTop: the top of the section the action produced, in the
    ///     same coordinates.
    ///   - keepingWholeHeight: how tall it is. Zero when the action produced
    ///     no section of its own, which leaves the reveal unconstrained.
    ///   - viewportHeight: how tall the dock's visible area is.
    public static func reveal(sectionTop: CGFloat,
                              sectionHeight: CGFloat,
                              keepingWholeTop: CGFloat,
                              keepingWholeHeight: CGFloat,
                              viewportHeight: CGFloat) -> Reveal {
        guard viewportHeight > 0 else { return .nothing }
        let wanted = action(sectionTop: sectionTop,
                            sectionHeight: sectionHeight,
                            viewportHeight: viewportHeight)
        let asked = travel(for: wanted, sectionTop: sectionTop,
                           sectionHeight: sectionHeight, viewportHeight: viewportHeight)
        // No produced section: the old rule, unchanged.
        guard keepingWholeHeight > 0 else {
            return wanted == .none ? .nothing : .reveal(wanted)
        }
        // How far the dock may travel with the produced section still whole.
        // Down as far as its own top; up as far as its foot reaching the
        // bottom edge. A produced section taller than the dock can never be
        // whole, and then its top wins, exactly as a too-tall reveal target's
        // does.
        let ceiling = keepingWholeTop
        let floor = min(keepingWholeTop + keepingWholeHeight - viewportHeight, ceiling)
        let allowed = min(max(asked, floor), ceiling)
        if abs(allowed - asked) <= slack {
            return wanted == .none ? .nothing : .reveal(wanted)
        }
        // The reveal has been cut short. Spending what is left only makes
        // sense if there is some: sub-point travel is a twitch.
        guard abs(allowed) > slack else { return .nothing }
        return .produced(allowed >= ceiling - slack ? .top : .bottom)
    }

    /// How far the dock travels to do `action`, in points, positive downwards
    /// (the content moving up).
    private static func travel(for action: Action,
                               sectionTop: CGFloat,
                               sectionHeight: CGFloat,
                               viewportHeight: CGFloat) -> CGFloat {
        switch action {
        case .none: 0
        case .top: sectionTop
        case .bottom: sectionTop + sectionHeight - viewportHeight
        }
    }
}
