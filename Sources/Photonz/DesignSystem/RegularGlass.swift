import SwiftUI

extension View {
    /// `.glassEffect(.regular, in: shape)`, except while the legibility check
    /// draws this into a picture (`LegibilitySheet`). Glass is drawn by the
    /// window server, and offscreen it blanks everything inside it, words
    /// included (even `.identity` glass does), so there it is left off and
    /// the check draws its own stand-in behind. In the app it is always the
    /// regular glass.
    func regularGlass<S: Shape>(in shape: S) -> some View {
        modifier(RegularGlass(shape: shape))
    }
}

private struct RegularGlass<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.drawnOffscreen) private var drawnOffscreen

    func body(content: Content) -> some View {
        if drawnOffscreen {
            content
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}
