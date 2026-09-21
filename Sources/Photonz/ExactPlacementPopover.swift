import PhotonzCore
import SwiftUI

/// The X, Y, W, H and A boxes, opened over the thing they are about
/// (`ExactPlacement`).
///
/// These are the same fields that used to be a Position & Size section sitting
/// open at the top of the right hand panel for every layer, forever. Nothing
/// about the fields changed: same typing, same Mixed where the picked layers
/// differ, same arrow keys stepping 1 and 10, same single undo step, same line
/// underneath explaining a number that was refused. What changed is that you
/// ask for them.
///
/// They open over the selection rather than in the panel because that is where
/// the eye already is when the number matters, and because a panel is a place
/// things live while a popover is a place a thing happens: type 240, press
/// Return, and it is gone.
struct ExactPlacementPopover: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(editorState.exactPlacementHeading)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
                .padding(.top, 10)
                .padding(.bottom, 2)
            GeometryInspector()
        }
        // The width the dock opens at (`EditorState.inspectorWidthDefault`), so
        // the two fields side by side are exactly the shape they were when
        // this was a section and nobody has to re-learn where a number sits.
        .frame(width: EditorState.inspectorWidthDefault)
    }
}

extension View {
    /// Hangs the numbers off whatever is picked, in the canvas view's own
    /// coordinates. The anchor is worked out by `ExactPlacement`, which keeps
    /// it inside what is on screen so the arrow never points past the window.
    @MainActor
    func exactPlacementPopover(_ editorState: EditorState) -> some View {
        // ...and it stays open only while there is still something to place.
        // Step into a copy while the numbers are up and a PIECE becomes the
        // selection, which owns neither its place nor its size: the fields
        // would stand there over it taking numbers that get written straight
        // back over on the next redraw. So the same test that turns the
        // command on keeps it open (`canOpenExactPlacement`).
        popover(isPresented: Binding(get: { editorState.isExactPlacementPresented
                                            && editorState.canOpenExactPlacement },
                                     set: { editorState.isExactPlacementPresented = $0 }),
                attachmentAnchor: .rect(.rect(editorState.exactPlacementAnchor)),
                arrowEdge: .trailing) {
            ExactPlacementPopover()
                .environment(editorState)
        }
    }
}
