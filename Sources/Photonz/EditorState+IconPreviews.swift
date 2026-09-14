import CoreGraphics
import Foundation
import Observation
import PhotonzCore
import PhotonzRender

// Seeing an icon at the size it will really be used (Next, `next-icon-previews`).
//
// An icon is the only thing in this app drawn at one size and looked at at
// another. So while an icon frame is what you are working in, the same drawing
// is shown small at the top left of the canvas, at the sizes it will really be
// used, and it is redrawn as the picture changes. A hairline that disappears at
// 16 disappears there, while you can still thicken it.
//
// Two rules decide what it costs:
//
//  - **Nothing at all unless an icon frame is what you are in.** No frame, no
//    selection, or a selection on a screen: `iconPreviewTiles` is empty before
//    it renders anything, so a document of screenshots never pays a pixel.
//  - **A picture is made once per drawing.** Each one is cached against the
//    frame's own hash, exactly as the layers panel caches its rows, and the
//    render happens off the main actor. Drawing in the frame costs one batch of
//    tiny renders per change, not one per redraw.
extension EditorState {

    /// Whether the strip exists at all in this release.
    var iconPreviewsEnabled: Bool { Experiments.shared.iconPreviewsEnabled }

    /// The icon frame the strip is showing, or nil for everything else.
    ///
    /// The frame itself when it is what you picked, and the frame ABOVE what
    /// you picked while you are drawing in it — which is nearly the whole time,
    /// since what is selected right after drawing a shape is the shape.
    var iconPreviewFrameID: UUID? {
        guard iconPreviewsEnabled, let document, let id = selectedLayerID else { return nil }
        return document.iconFrameID(containing: id)
    }

    /// What the strip draws: one tile per size, in size order, each carrying
    /// the frame drawn at that many pixels. Empty whenever there is no icon
    /// frame in hand, which is what makes the strip cost nothing the rest of
    /// the time.
    ///
    /// A tile whose picture has not landed yet carries nil and draws as an
    /// empty chip, so the row keeps its shape rather than growing a column at a
    /// time.
    var iconPreviewTiles: [IconPreviewTile] {
        guard let frameID = iconPreviewFrameID, let document,
              let frame = document.layer(id: frameID) else { return [] }
        return IconPreviews.sides(forFrameSize: frame.frame.size).map { side in
            IconPreviewTile(side: side, image: iconPreview(of: frame, side: side))
        }
    }

    /// One preview, from the cache or ordered up.
    ///
    /// The hash covers everything about the frame and everything inside it, so
    /// a shape landing, a colour changing or an undo all invalidate it and
    /// nothing else does. While a fresh one is being drawn the last one stays
    /// on screen: a strip that blinked empty on every stroke would be worse
    /// than one a frame behind.
    private func iconPreview(of frame: Layer, side: CGFloat) -> CGImage? {
        let key = IconPreviewKey(frameID: frame.id, side: Int(side))
        let hash = frame.hashValue
        if let cached = iconPreviews[key], cached.hash == hash { return cached.image }
        guard let document else { return iconPreviews[key]?.image }
        if !iconPreviewsInFlight.contains(key) {
            let renderer = previewRenderer
            let store = store
            // The bookkeeping is deferred off the view-body read path, the way
            // the layers panel's thumbnails are: a view that mutated state
            // while SwiftUI was reading it would be a redraw loop.
            Task { @MainActor [weak self] in
                guard let self, !self.iconPreviewsInFlight.contains(key) else { return }
                self.iconPreviewsInFlight.insert(key)
                let image = await Task.detached(priority: .userInitiated) {
                    renderer.iconPreview(for: key.frameID, in: document, store: store,
                                         side: CGFloat(key.side))
                }.value
                self.iconPreviewsInFlight.remove(key)
                if let image { self.iconPreviews[key] = (hash, image) }
            }
        }
        return iconPreviews[key]?.image
    }

    /// How much room the strip takes in the canvas's top left corner, so
    /// anything else that wants that corner can step around it. Generous: it is
    /// laid out by SwiftUI, so its exact size is not knowable here, and
    /// over-reserving only makes the other thing step aside a little sooner.
    var iconPreviewsReservedRect: CGRect? {
        let tiles = iconPreviewTiles
        guard !tiles.isEmpty else { return nil }
        let chips = tiles.map { IconPreviews.chipSide(for: $0.side) }
        let width = chips.reduce(0, +) + CGFloat(tiles.count - 1) * IconPreviewsStrip.gap
            + IconPreviewsStrip.padding * 2
        let height = (chips.max() ?? 0) + IconPreviewsStrip.labelHeight
            + IconPreviewsStrip.padding * 2
        let inset = EditorChromeLayout.cornerInset
        return CGRect(x: inset, y: inset, width: width, height: height)
    }
}

/// One preview in the strip: a size, and the frame drawn at it.
struct IconPreviewTile: Identifiable {
    let side: CGFloat
    let image: CGImage?
    var id: Int { Int(side) }
}

/// A cached preview: which frame, at how many pixels.
struct IconPreviewKey: Hashable {
    let frameID: UUID
    let side: Int
}
