import AppKit
import CoreGraphics
import PhotonzCore
import PhotonzRender

// An empty track is somewhere to put something, and a layer on the canvas and
// on no track can be put back on the timeline
// (`a-shape-s-bar-never-vanishes-from-its-track-and`, `EmptyTracks.swift`).
//
// The user met a Rectangle track with nothing on it and no way to bring the
// rectangle back or to use the row. Now a track's right-click menu adds a
// rectangle or a title to it at the playhead, pastes onto it, or puts a layer
// that is on no track onto it; the layer's own menus (its row and the canvas)
// offer Put on Timeline; a bar carried up or down onto an empty track lands
// there, as any clip always has; and Delete Empty Tracks clears what is left.
// There is no drag from the layers list: in Next the open timeline IS the
// layers list (`TimelineIsTheLayerList`), so the two are never on screen
// together.
extension EditorState {

    // MARK: Reading

    /// Whether nothing is on this track: no clip, and no clip's own sound.
    func isTrackEmpty(_ id: UUID) -> Bool {
        document?.emptyTrackIDs.contains(id) == true
    }

    var hasEmptyTracks: Bool { !(document?.emptyTrackIDs.isEmpty ?? true) }

    /// Whether a layer is on the canvas and on no track, so Put on Timeline
    /// has something to do.
    func canPutOnTimeline(_ id: UUID) -> Bool {
        document?.canPutOnTimeline(id) == true
    }

    /// The layers a track's Put Layer Here can offer, topmost first.
    var layersOffTheTimeline: [Layer] { document?.layersOffTheTimeline ?? [] }

    // MARK: Doing

    /// Put a layer on the timeline from the playhead (or `atMS`), onto
    /// `trackID` where one is given, and pick it.
    func putLayerOnTimeline(_ id: UUID, onTrack trackID: UUID? = nil, atMS ms: Int? = nil) {
        let moment = ms ?? documentTimeMS
        var landed = false
        perform { landed = $0.putOnTimeline(id, atMS: moment, onTrack: trackID) }
        guard landed else { return }
        selectLayer(id)
        openTimelineForAnEdit()
    }

    func deleteEmptyTracks() {
        if let empty = document?.emptyTrackIDs { selectedTrackIDs.subtract(empty) }
        perform { $0.deleteEmptyTracks() }
    }

    /// Run `make` with whatever it adds landing on `trackID` at the playhead.
    private func landing(on trackID: UUID, _ make: () -> Void) {
        landingTrack = (trackID, documentTimeMS)
        defer { landingTrack = nil }
        make()
    }

    /// A rectangle in the middle of the picture, in the rectangle tool's own
    /// look, on this track from the playhead.
    func addRectangle(onTrack trackID: UUID) {
        guard let document, let content = annotationStyles.content(for: .rectangle) else { return }
        let size = document.canvasSize
        let box = CGSize(width: size.width * 0.3, height: size.height * 0.3)
        let start = CGPoint(x: (size.width - box.width) / 2, y: (size.height - box.height) / 2)
        let end = CGPoint(x: start.x + box.width, y: start.y + box.height)
        var layer = AnnotationBuilder.layer(content: content, from: start, to: end)
        layer.style = annotationStyles.arrivingStyle(forShape: .rectangle)
        layer = document.wearingArmedColorStyles(layer, styles: annotationStyles)
        landing(on: trackID) { addDrawnLayer(layer) }
        finishCreating(layer.id)
    }

    /// A title in the middle of the picture, in the look new words over a
    /// video take, on this track from the playhead. Double-click to retype it.
    func addText(onTrack trackID: UUID) {
        guard let document else { return }
        let size = document.canvasSize
        var content = textStyles.content(string: "Title")
        let isTitle = usesTitleLook
        if !isTitle { content.colorHex = foregroundFillHex }
        let natural = TextBlockMetrics.frameSize(for: content, maxWidth: size.width * 0.8,
                                                 hugsShortWords: Experiments.shared.placementEnabled)
        let origin = CGPoint(x: (size.width - natural.width) / 2, y: (size.height - natural.height) / 2)
        var layer = wearingArmedTextStyle(TextBuilder.layer(content: content, at: origin, naturalSize: natural))
        if isTitle {
            layer.style.shadow = TitleLook.shadow(forColorHex: content.colorHex, fontSize: content.fontSize)
        }
        landing(on: trackID) { addDrawnLayer(layer) }
        finishCreating(layer.id)
    }

    /// Whether the clipboard holds a layer or a picture to paste.
    var canPasteLayerOrPicture: Bool {
        let pasteboard = NSPasteboard.general
        return pasteboard.data(forType: NSPasteboard.PasteboardType(LayerTransfer.pasteboardType)) != nil
            || NSImage.canInit(with: pasteboard)
    }

    /// Paste onto this track, from the playhead.
    func paste(onTrack trackID: UUID) {
        landing(on: trackID) { paste() }
    }
}
