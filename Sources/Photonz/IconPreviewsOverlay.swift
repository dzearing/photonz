import SwiftUI

/// The icon preview strip in a corner of the canvas, and the read of the
/// selection that decides whether there is one and which corner.
///
/// It is a view of its own for a measured reason. `iconPreviewFrameID` asks
/// which icon frame the PICKED layer sits in, so it reads `selectedLayerID`;
/// while that read (and the `.animation(value:)` that went with it) sat in
/// `EditorView.body`, clicking any layer row invalidated the whole editor —
/// canvas, tool bar, zoom bar, dock — and SwiftUI re-measured every stack in
/// the window for a strip that is empty unless you are drawing an icon
/// (`layer-pick-latency-walk`, 2026-09-14).
///
/// Anything else that wants to know what is selected belongs in a small view
/// like this one too, not in the editor's own body.
struct IconPreviewsOverlay: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        if let placement = editorState.iconPreviewPlacement {
            IconPreviewsStrip(sides: placement.sides,
                              showsTransport: editorState.iconPreviewsPlayable)
                .frame(width: placement.frame.width, height: placement.frame.height)
                .offset(x: placement.frame.minX, y: placement.frame.minY)
                .transition(.opacity)
                // Stepping out of the icon's way, or giving up a size to do it,
                // is a move rather than a jump: a card that appeared in another
                // corner between two frames would read as a glitch.
                .animation(.easeInOut(duration: 0.2), value: placement)
                .animation(.easeInOut(duration: 0.2), value: editorState.iconPreviewFrameID)
                // The transport arrives the moment the first motion is added.
                .animation(.easeInOut(duration: 0.2), value: editorState.iconPreviewsPlayable)
        }
    }
}
