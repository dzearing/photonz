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
//  - **Nothing at all unless an icon frame is what you are in.** No frame in
//    the document, a selection on a screen, or an icon that has since been
//    deleted: `iconPreviewTiles` is empty before it renders anything, so a
//    document of screenshots never pays a pixel. Picking NOTHING is not one of
//    those cases any more — standing back to look is when the pictures are
//    worth most, so the strip keeps the last icon it had an answer for.
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
    ///
    /// With NOTHING picked the pointer says which icon, and failing that the
    /// last icon either of them named. That last part is what keeps the
    /// pictures up when you click an empty part of the canvas or press Escape,
    /// which is the ordinary way to stand back and look at what you have
    /// drawn. The rule is `PhotonzDocument.iconPreviewFrameID`, shared with
    /// the tool bar's Width row so the number and the pictures are always
    /// about one icon.
    var iconPreviewFrameID: UUID? {
        guard iconPreviewsEnabled, let document else { return nil }
        return document.iconPreviewFrameID(picked: selectedLayerID,
                                           pointerIn: pointerIconFrameID,
                                           remembered: lastIconPreviewFrameID)
    }

    /// Re-decides which icon the strip is speaking for and remembers it.
    ///
    /// Called from the two places the answer can change — the selection and
    /// the pointer — because the strip itself cannot remember anything: it is
    /// a view, and writing state while SwiftUI reads a body is a redraw loop.
    /// Everything it decides is re-derivable, so a missed call costs a stale
    /// memory at worst and the read path checks that anyway.
    func noteIconPreviewFocus() {
        guard iconPreviewsEnabled, let document else { return }
        let id = document.iconPreviewFrameID(picked: selectedLayerID,
                                             pointerIn: pointerIconFrameID,
                                             remembered: lastIconPreviewFrameID)
        if id != lastIconPreviewFrameID { lastIconPreviewFrameID = id }
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
              let authored = document.layer(id: frameID) else { return [] }
        // The sizes come off the frame AS DRAWN, never off the moving one. A
        // frame with a scale motion on it is a different size every frame, and
        // a row that added and dropped a column thirty times a second would be
        // unreadable at exactly the moment it is being watched.
        let sides = IconPreviews.sides(forFrameSize: authored.frame.size)
        guard !sides.isEmpty else { return [] }
        let source = iconPreviewSource(document, frameID: frameID)
        let frame = source.layer(id: frameID) ?? authored
        return sides.map { side in
            IconPreviewTile(side: side, image: iconPreview(of: frame, in: source, side: side))
        }
    }

    /// The picture the previews are drawn from: the one you drew, or where the
    /// loop has got to while the preview runs.
    ///
    /// This is what makes the strip the REVIEW rather than a still life. The
    /// icon moves in the four chips at the sizes it will really be used, which
    /// is the only place a swing that reads beautifully on a 512 point canvas
    /// can be caught being a shimmer at 16.
    ///
    /// Only this frame is worked out, not the whole document: the strip shows
    /// one frame and nothing else, and moving a picture it is not drawing would
    /// be a copy of every layer in it, thirty times a second.
    private func iconPreviewSource(_ document: PhotonzDocument, frameID: UUID) -> PhotonzDocument {
        let document = withDraggedMotionTiming(document)
        guard Experiments.shared.motionEnabled, isMotionPlaying, document.hasMotion else { return document }
        return document.moved(layerID: frameID, toMotionTimeMS: motionPlayheadMS)
    }

    /// One preview, from the cache or ordered up.
    ///
    /// The hash covers everything about the frame and everything inside it, so
    /// a shape landing, a colour changing or an undo all invalidate it and
    /// nothing else does. While a fresh one is being drawn the last one stays
    /// on screen: a strip that blinked empty on every stroke would be worse
    /// than one a frame behind.
    private func iconPreview(of frame: Layer, in document: PhotonzDocument, side: CGFloat) -> CGImage? {
        let key = IconPreviewKey(frameID: frame.id, side: Int(side))
        // The hash is of the frame the picture will be made FROM, which while
        // the loop runs is the frame at this moment of it. So a moving icon
        // orders a fresh picture per frame and a still one orders none, with no
        // second rule for the running case.
        let hash = frame.hashValue
        if let cached = iconPreviews[key], cached.hash == hash { return cached.image }
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
        // The sides, not the tiles: this is a measurement, and asking for the
        // tiles would order a batch of pictures to find out how wide a row of
        // them is.
        guard let frameID = iconPreviewFrameID, let document,
              let frame = document.layer(id: frameID) else { return nil }
        let sides = IconPreviews.sides(forFrameSize: frame.frame.size)
        guard !sides.isEmpty else { return nil }
        let chips = sides.map { IconPreviews.chipSide(for: $0) }
        let width = chips.reduce(0, +) + CGFloat(sides.count - 1) * IconPreviewsStrip.gap
            + IconPreviewsStrip.padding * 2
        let height = (chips.max() ?? 0) + IconPreviewsStrip.labelHeight
            + IconPreviewsStrip.padding * 2
            + (iconPreviewsPlayable ? IconPreviewsStrip.headerHeight : 0)
        let inset = EditorChromeLayout.cornerInset
        return CGRect(x: inset, y: inset, width: width, height: height)
    }

    /// Whether the previews card carries a transport.
    ///
    /// Only when something in THIS frame moves. A play button over four still
    /// pictures is a control that does nothing, and the card is chrome sitting
    /// on somebody's canvas: with a still icon it stays exactly the row of
    /// pictures it has always been.
    var iconPreviewsPlayable: Bool {
        guard canPlayMotion, let frameID = iconPreviewFrameID,
              let frame = document?.layer(id: frameID) else { return false }
        return frame.hasMotionInside
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
