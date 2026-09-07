// The column down the right of the inspector panel.
//
// The eye and the lock on a layer row, the grip on a section header, the cross
// that takes an effect out of a list: different views in different files, each
// of which used to carry its own trailing space and draw a glyph of its own
// width. The result was reported by the user on 2026-09-07 as a ragged edge —
// a line drawn through the eyes missed the grips by 3.5pt, and locking a layer
// slid its padlock 2pt sideways, because the closed padlock is a narrower
// drawing than the open one.
//
// So there is one slot, shared, and every icon on that edge wears it. The
// numbers live in `EditorChromeLayout` beside the rest of the chrome metrics.
import SwiftUI
import PhotonzCore

extension View {
    /// Draws this icon in the panel edge's shared slot: a fixed width with the
    /// glyph centred in it, so whatever is drawn lands on the one centre line
    /// however wide the glyph itself is.
    ///
    /// `kind` and `owner` are the words a scripted walk reads the icon back by
    /// ("eye" on "Background", "section grip" on "Layers"), so the column can
    /// be measured in the running app rather than judged by eye.
    func panelEdgeIcon(_ kind: String, of owner: String) -> some View {
        frame(width: EditorChromeLayout.panelEdgeIconWidth)
            .panelEdgeProbe(kind: kind, owner: owner)
    }

    /// The trailing space for something drawn straight onto the panel — a
    /// section header, a line of its own under a list.
    func panelEdgePadding() -> some View {
        padding(.trailing, EditorChromeLayout.panelEdgeInset)
    }

    /// ...and for a row inside a list that already keeps a gutter, so it
    /// reaches the same line rather than stopping a gutter short of it.
    func panelEdgeRowPadding() -> some View {
        padding(.trailing, EditorChromeLayout.panelEdgeInset(
            insideGutter: EditorChromeLayout.panelListGutter))
    }
}
