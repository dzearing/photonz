import CoreGraphics
import Observation
import PhotonzCore
import PhotonzRender
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppState {
    private(set) var history: History?
    let store = ImageStore()
    let capture = CaptureCenter()
    /// Created lazily (not in init) so its frame-delivery closure can capture self.
    private var scheduler: RenderScheduler?

    /// The composited document, refreshed asynchronously after every edit
    /// (latest-wins: rapid edits coalesce instead of queueing renders).
    private(set) var renderedImage: CGImage?
    var isImporterPresented = false

    /// Canvas camera. Nil until a document is open. All zoom/pan flows through
    /// `Viewport` (PhotonzCore) so the math stays tested.
    private(set) var viewport: Viewport?
    /// Marquee selection in document coordinates (pixel-aligned). Nil = no selection.
    private(set) var selection: CGRect?
    /// The layer targeted by click-to-select / drag-to-move. Nil = none.
    private(set) var selectedLayerID: UUID?
    /// Frame override while a move drag is in flight — rendered as a preview,
    /// committed to history only on mouse-up.
    private var previewMove: (id: UUID, frame: CGRect)?
    /// Last known canvas view size, so a document opened before/after the first
    /// layout pass can still be fit correctly.
    private var canvasViewSize: CGSize = .zero

    var zoom: CGFloat { viewport?.zoom ?? 1 }

    var document: PhotonzDocument? { history?.current }
    var canUndo: Bool { history?.canUndo ?? false }
    var canRedo: Bool { history?.canRedo ?? false }

    func openImage(at url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        openCapture(image)
    }

    /// Opens a CGImage (from a file or a screen capture) as a fresh document.
    func openCapture(_ image: CGImage) {
        let ref = store.register(image)
        history = History(document: .withBaseImage(ref))
        viewport = .fit(documentSize: ref.pixelSize, in: canvasViewSize)
        selection = nil
        selectedLayerID = nil
        previewMove = nil
        rerender()
    }

    // MARK: - Viewport

    func canvasViewSizeChanged(_ size: CGSize) {
        let hadNoSize = canvasViewSize == .zero
        canvasViewSize = size
        guard let current = viewport else { return }
        // The first real layout after opening re-fits; later resizes keep the
        // user's framing (center-preserving).
        viewport = hadNoSize
            ? .fit(documentSize: current.documentSize, in: size)
            : current.resized(viewSize: size)
    }

    /// Gesture-driven camera updates from the canvas (already clamped by Viewport).
    func setViewport(_ vp: Viewport) {
        viewport = vp
    }

    /// Marquee result from the canvas (document coords, already pixel-aligned).
    func setSelection(_ rect: CGRect?) {
        selection = rect
    }

    // MARK: - Layer selection & move

    /// The selected layer's frame (preview-aware), for the canvas outline.
    var selectedLayerFrame: CGRect? {
        guard let id = selectedLayerID else { return nil }
        if let previewMove, previewMove.id == id { return previewMove.frame }
        return document?.layer(id: id)?.frame
    }

    func selectLayer(_ id: UUID?) {
        selectedLayerID = id
    }

    /// Live drag update (move or resize): renders the new frame without
    /// touching history.
    func previewLayerFrame(id: UUID, frame: CGRect) {
        guard var doc = document, doc.layer(id: id) != nil else { return }
        previewMove = (id, frame)
        doc.updateLayer(id: id) { $0.frame = frame }
        submit(doc)
    }

    /// Mouse-up: one undoable step from the pre-drag frame to the final one.
    /// Committing back to the original frame is a recognized no-op (History
    /// skips it), which is how an Esc-cancelled drag restores the real render.
    func commitLayerFrame(id: UUID, frame: CGRect) {
        previewMove = nil
        perform { $0.updateLayer(id: id) { $0.frame = frame } }
    }

    func zoomIn() { zoomTowardCenter(zoom * 1.25) }
    func zoomOut() { zoomTowardCenter(zoom / 1.25) }

    func zoomToFit() {
        guard let viewport else { return }
        self.viewport = .fit(documentSize: viewport.documentSize, in: viewport.viewSize)
    }

    func zoomToActualSize() { zoomTowardCenter(1) }

    private func zoomTowardCenter(_ newZoom: CGFloat) {
        guard let viewport else { return }
        let center = CGPoint(x: viewport.viewSize.width / 2, y: viewport.viewSize.height / 2)
        self.viewport = viewport.zoomed(to: newZoom, anchorInView: center)
    }

    func perform(_ mutate: (inout PhotonzDocument) -> Void) {
        history?.perform(mutate)
        rerender()
    }

    func undo() {
        history?.undo()
        rerender()
    }

    func redo() {
        history?.redo()
        rerender()
    }

    private func rerender() {
        guard let document = history?.current else {
            renderedImage = nil
            viewport = nil
            selection = nil
            selectedLayerID = nil
            previewMove = nil
            return
        }
        // Crop/resize/undo can change the canvas size; keep the camera in sync.
        if var vp = viewport, vp.documentSize != document.canvasSize {
            vp.documentSize = document.canvasSize
            viewport = vp.clamped()
            // A selection from the old canvas no longer means anything reliable.
            selection = nil
        }
        // Undo can remove the selected layer out from under us.
        if let id = selectedLayerID, document.layer(id: id) == nil {
            selectedLayerID = nil
        }
        submit(document)
    }

    /// Hands a document (committed or move-preview) to the render scheduler.
    private func submit(_ document: PhotonzDocument) {
        if scheduler == nil {
            scheduler = RenderScheduler(store: store) { [weak self] image in
                await MainActor.run {
                    // Drop the frame if the document was closed while rendering.
                    guard let self, self.history != nil else { return }
                    self.renderedImage = image
                }
            }
        }
        guard let scheduler else { return }
        Task { await scheduler.submit(document) }
    }
}
