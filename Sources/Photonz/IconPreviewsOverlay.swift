import SwiftUI

/// The icon preview strip in the top left of the canvas, and the read of the
/// selection that decides whether there is one.
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
        let tiles = editorState.iconPreviewTiles
        if !tiles.isEmpty {
            IconPreviewsStrip(tiles: tiles)
                .animation(.easeInOut(duration: 0.2), value: editorState.iconPreviewFrameID)
        }
    }
}
