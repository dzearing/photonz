import AppKit
import SwiftUI

/// How wide a pop-up menu in the dock is, before it is drawn.
///
/// A Mac pop-up sizes itself to the WIDEST name in its list, not to the one
/// showing, and it will never accept a width larger than that. So a menu whose
/// list grows — the Font menu picks up any family the picked labels already
/// wear — changes size out from under the row it sits on, and there is no
/// frame that can stop it growing.
///
/// What there is: the list always contains the curated names, so the width the
/// curated names alone would need is the smallest the menu can ever be, and a
/// pop-up DOES accept a width smaller than its content (it shortens the closed
/// title with an ellipsis, which is exactly what should happen to a name too
/// long for the box). Measure that width once and hold the menu to it, and the
/// box stops moving for good.
///
/// The measurement is taken from a throwaway `NSPopUpButton` set up the way
/// SwiftUI sets up a small `.menu` picker. Measured both ways and compared, the
/// two agree to the point.
@MainActor enum MenuMetrics {
    /// The width a pop-up offering exactly these names would take.
    static func width(ofOptions titles: [String]) -> CGFloat {
        if let known = cache[titles] { return known }
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .small
        button.font = NSFont.menuFont(ofSize: NSFont.systemFontSize(for: .small))
        button.addItems(withTitles: titles)
        let measured = button.intrinsicContentSize.width
        cache[titles] = measured
        return measured
    }

    /// Whether one name fits a box of this width. A pop-up holding a single
    /// name is that name plus the arrows and padding around it, so this asks
    /// the same question the drawing does.
    static func fits(_ title: String, in width: CGFloat) -> Bool {
        self.width(ofOptions: [title]) <= width + 0.5
    }

    /// Measuring builds an AppKit control, so the answers are kept. There are a
    /// handful of lists in the whole dock and none of them change while the app
    /// is running.
    private static var cache: [[String]: CGFloat] = [:]
}
