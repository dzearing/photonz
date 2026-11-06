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
// used (up to twice its own size, each on a light and a dark ground), and it is
// redrawn as the picture changes. A hairline that disappears at 16 disappears
// there, while you can still thicken it.
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

    /// Where the card goes and which sizes it has room for, or nil when there
    /// is no icon in hand or nowhere to put it that does not cover the drawing
    /// (`IconPreviews.placement`).
    ///
    /// Everything it keeps clear of is worked out from the frame AS DRAWN,
    /// never the moving one: a card that hopped corners with a swinging icon
    /// would be the worst thing on the screen.
    var iconPreviewPlacement: IconPreviews.Placement? {
        guard let frameID = iconPreviewFrameID, let document,
              let authored = document.layer(id: frameID),
              let icon = document.canvasBounds(of: frameID) else { return nil }
        let sides = IconPreviews.sides(forFrameSize: authored.frame.size)
        guard !sides.isEmpty else { return nil }
        let playable = iconPreviewsPlayable
        let inset = EditorChromeLayout.cornerInset
        guard let viewport else {
            // Not laid out yet, so nothing can be under it.
            let size = IconPreviews.cardSize(sides: sides, hasTransport: playable)
            return IconPreviews.Placement(sides: sides, anchor: .topLeading,
                                          frame: CGRect(origin: CGPoint(x: inset, y: inset), size: size))
        }
        func onScreen(_ box: CGRect) -> CGRect {
            CGRect(origin: viewport.viewPoint(fromDocument: box.origin),
                   size: CGSize(width: box.width * viewport.zoom, height: box.height * viewport.zoom))
        }
        // What is picked stays in view with its handles, the frame included:
        // a card on a corner handle is a card eating the drag that handle is for.
        let picked = selectedLayerID.flatMap { document.canvasBounds(of: $0) }.map { [$0] } ?? []
        return IconPreviews.placement(sides: sides, hasTransport: playable, in: viewport.viewSize,
                                      inset: inset, icon: onScreen(icon),
                                      ink: (document.iconPreviewInk(id: frameID) + picked).map(onScreen),
                                      chrome: canvasFloorChrome(in: viewport))
    }

    /// What the strip draws at the sizes it has room for right now. A walk's
    /// way in: the card itself is told its sizes, so that panning the canvas
    /// does not redraw it.
    var iconPreviewTiles: [IconPreviewTile] {
        iconPreviewTiles(sides: iconPreviewPlacement?.sides ?? [])
    }

    /// One tile per size, in size order, each carrying the frame drawn at that
    /// many pixels on both grounds. Empty whenever there is no icon frame in
    /// hand, which is what makes the strip cost nothing the rest of the time.
    ///
    /// A picture that has not landed yet is nil and leaves its place on the
    /// ground empty, so the card keeps its shape.
    func iconPreviewTiles(sides: [CGFloat]) -> [IconPreviewTile] {
        guard let frameID = iconPreviewFrameID, let document,
              let authored = document.layer(id: frameID) else { return [] }
        let source = iconPreviewSource(document, frameID: frameID)
        let frame = source.layer(id: frameID) ?? authored
        return sides.map { side in
            IconPreviewTile(side: side,
                            light: iconPreview(of: frame, in: source, side: side, onDarkGround: false),
                            dark: iconPreview(of: frame, in: source, side: side, onDarkGround: true))
        }
    }

    /// The colour of the Light ground for the icon in hand.
    var iconPreviewGroundHex: String {
        iconPreviewFrameID.flatMap { document?.iconPreviewGroundHex(id: $0) }
            ?? IconPreviews.lightGroundHex
    }

    /// The picture the previews are drawn from: the one you drew, or where the
    /// loop has got to while the preview runs.
    ///
    /// This is what makes the strip the REVIEW rather than a still life. The
    /// icon moves on both grounds at the sizes it will really be used, which
    /// is the only place a swing that reads beautifully on a 512 point canvas
    /// can be caught being a shimmer at 16.
    ///
    /// Only this frame is worked out, not the whole document: the strip shows
    /// one frame and nothing else, and moving a picture it is not drawing would
    /// be a copy of every layer in it, thirty times a second.
    private func iconPreviewSource(_ document: PhotonzDocument, frameID: UUID) -> PhotonzDocument {
        let document = withDraggedMotionTiming(document)
        // A keyed picture's previews show the moment the canvas does.
        if document.isKeyedPicture {
            return document.moved(layerID: frameID,
                                  toMotionTimeMS: isMotionPlaying ? motionPlayheadMS : documentTimeMS)
        }
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
    private func iconPreview(of frame: Layer, in document: PhotonzDocument, side: CGFloat,
                             onDarkGround: Bool) -> CGImage? {
        let key = IconPreviewKey(frameID: frame.id, side: Int(side), onDarkGround: onDarkGround)
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
                                         side: CGFloat(key.side),
                                         onDarkGround: key.onDarkGround)
                }.value
                self.iconPreviewsInFlight.remove(key)
                if let image { self.iconPreviews[key] = (hash, image) }
            }
        }
        return iconPreviews[key]?.image
    }

    /// Where the card is, so anything else that wants that corner can step
    /// around it.
    var iconPreviewsReservedRect: CGRect? { iconPreviewPlacement?.frame }

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

/// One size in the strip: the frame drawn at it, on each ground.
struct IconPreviewTile: Identifiable {
    let side: CGFloat
    let light: CGImage?
    let dark: CGImage?
    var id: Int { Int(side) }
}

/// A cached preview: which frame, at how many pixels.
struct IconPreviewKey: Hashable {
    let frameID: UUID
    let side: Int
    /// The picture on the Dark ground can be a different colour from the same
    /// size on the Light one, so it is cached on its own.
    let onDarkGround: Bool
}
