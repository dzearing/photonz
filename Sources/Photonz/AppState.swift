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
    /// The active editor tool. Annotation tools are sticky: each drag creates
    /// another layer until the user returns to `.select` (Esc or V).
    private(set) var activeTool: Tool = .select
    /// Styling for new annotations, set from the style popover. Persisted so
    /// the user's color/width survive relaunches.
    private(set) var annotationStyles: AnnotationStyles = AppState.loadAnnotationStyles()
    /// Styling for new text blocks, set from the font picker. Persisted like
    /// annotation styles.
    private(set) var textStyles: TextStyles = AppState.loadTextStyles()
    /// The text layer being re-edited inline. Hidden from renders while the
    /// canvas's editor overlay visually replaces it.
    private(set) var editingTextLayerID: UUID?
    /// The layer targeted by click-to-select / drag-to-move. Nil = none.
    private(set) var selectedLayerID: UUID?
    /// Frame override while a move drag is in flight — rendered as a preview,
    /// committed to history only on mouse-up.
    private var previewMove: (id: UUID, frame: CGRect)?
    /// Cheap drag preview: underlay + sprite the canvas composites in Core
    /// Animation, so mouse moves cost zero Core Image work. Nil until the
    /// session's two renders finish (the full-submit path covers the gap).
    private(set) var dragPreview: DragPreview?
    /// Renders preview sessions off the scheduler's queue.
    private let previewRenderer = DocumentRenderer()
    private var dragPreviewGeneration = 0
    /// Set on commit: the preview must survive until the post-commit frame
    /// lands, or the dragged layer would flash back to its pre-drag position.
    private var clearPreviewAfterNextFrame = false
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
        activeTool = .select
        previewMove = nil
        dragPreview = nil
        editingTextLayerID = nil
        dragPreviewGeneration += 1
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

    // MARK: - Tools

    func setTool(_ tool: Tool) {
        guard activeTool != tool else { return }
        activeTool = tool
        // Drawing tools own the pointer; select-mode chrome (marquee ants,
        // layer handles) would read as interactive when it isn't.
        if tool != .select {
            selection = nil
            selectedLayerID = nil
        }
    }

    /// Completed drag-to-create from the canvas (document coords, ⇧ already
    /// applied). Adds one annotation layer as a single undo step.
    func addAnnotation(from start: CGPoint, to end: CGPoint) {
        guard let content = annotationStyles.content(for: activeTool) else { return }
        let layer = AnnotationBuilder.layer(content: content, from: start, to: end)
        perform { $0.addLayer(layer) }
    }

    // MARK: - Annotation styling

    /// Styled content the active tool would draw, for the canvas drag preview.
    var activeAnnotationContent: AnnotationContent? {
        annotationStyles.content(for: activeTool)
    }

    /// The selected annotation layer when the select tool is active — the
    /// style popover edits this layer instead of the new-annotation defaults.
    var selectedAnnotationLayer: Layer? {
        guard activeTool == .select, let id = selectedLayerID,
              let layer = document?.layer(id: id), layer.annotation != nil else { return nil }
        return layer
    }

    /// A swatch pick restyles the selected annotation (one undo step) when
    /// there is one; either way it becomes the default for new annotations.
    func setAnnotationColor(_ hex: String) {
        if let layer = selectedAnnotationLayer, let shape = layer.annotation?.shape {
            discardDragPreview() // a click-select's held sprite shows the old style
            perform { $0.updateLayer(id: layer.id) { $0 = AnnotationBuilder.restyled($0, colorHex: hex) } }
            annotationStyles.setColorHex(hex, forShape: shape)
        } else {
            annotationStyles.setColorHex(hex, for: activeTool)
        }
        saveAnnotationStyles()
    }

    func setAnnotationStrokeWidth(_ width: CGFloat) {
        if let layer = selectedAnnotationLayer, layer.annotation?.shape != .highlight {
            discardDragPreview()
            perform { $0.updateLayer(id: layer.id) { $0 = AnnotationBuilder.restyled($0, strokeWidth: width) } }
        }
        annotationStyles.strokeWidth = width
        saveAnnotationStyles()
    }

    /// Drops a live drag preview whose sprite no longer matches the layer
    /// (content edits, undo/redo). The canvas falls back to the last composite
    /// until the re-render lands, so nothing flashes.
    private func discardDragPreview() {
        dragPreviewGeneration += 1
        dragPreview = nil
        clearPreviewAfterNextFrame = false
    }

    private static let annotationStylesKey = "annotationStyles"

    private static func loadAnnotationStyles() -> AnnotationStyles {
        guard let data = UserDefaults.standard.data(forKey: annotationStylesKey),
              let styles = try? JSONDecoder().decode(AnnotationStyles.self, from: data) else {
            return AnnotationStyles()
        }
        return styles
    }

    private func saveAnnotationStyles() {
        if let data = try? JSONEncoder().encode(annotationStyles) {
            UserDefaults.standard.set(data, forKey: Self.annotationStylesKey)
        }
    }

    // MARK: - Text styling & inline editing

    /// Styled (empty) content for the current text style; the canvas's inline
    /// editor mirrors it so what you type matches what commit rasterizes.
    var activeTextContent: TextContent { textStyles.content() }

    func setTextFont(_ name: String) {
        textStyles.fontName = name
        saveTextStyles()
    }

    func setTextFontSize(_ size: CGFloat) {
        textStyles.fontSize = size
        saveTextStyles()
    }

    func setTextWeight(_ weight: TextWeight) {
        textStyles.weight = weight
        saveTextStyles()
    }

    func setTextColor(_ hex: String) {
        textStyles.colorHex = hex
        saveTextStyles()
    }

    /// An inline edit began. Re-editing an existing layer adopts its style (so
    /// the font picker edits what's on screen) and hides the layer until
    /// commit/cancel — the editor overlay visually replaces it.
    func beginTextEdit(layerID: UUID?) {
        guard let layerID, let layer = document?.layer(id: layerID),
              case .text(let content) = layer.content else { return }
        textStyles.adopt(content)
        saveTextStyles()
        editingTextLayerID = layerID
        if let document { submit(document) }
    }

    /// Inline edit finished. Empty text adds nothing (new block) or deletes the
    /// layer (re-edit); otherwise one undo step adds/updates the layer with its
    /// frame hugging the re-measured text. `maxWidth` is the wrap width the
    /// editor used (document points), so layout doesn't shift on commit.
    func commitTextEdit(layerID: UUID?, origin: CGPoint, string: String, maxWidth: CGFloat) {
        editingTextLayerID = nil
        let isEmpty = string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let content = textStyles.content(string: string)
        if let layerID {
            if isEmpty {
                perform { $0.removeLayer(id: layerID) }
            } else {
                let size = TextRasterizer.naturalSize(content, maxWidth: maxWidth)
                perform { document in
                    document.updateLayer(id: layerID) {
                        $0.content = .text(content)
                        $0.frame = CGRect(origin: origin, size: size)
                        // Re-edit may have changed the color; keep the
                        // auto-contrast shadow (3.6) opposing it.
                        $0.style.shadow = TextBuilder.autoContrastShadow(forColorHex: content.colorHex)
                    }
                }
            }
        } else {
            guard !isEmpty else { return }
            let size = TextRasterizer.naturalSize(content, maxWidth: maxWidth)
            perform { $0.addLayer(TextBuilder.layer(content: content, at: origin, naturalSize: size)) }
        }
    }

    /// Inline edit abandoned (Esc): a hidden re-edited layer comes back as-is.
    func cancelTextEdit() {
        editingTextLayerID = nil
        rerender()
    }

    private static let textStylesKey = "textStyles"

    private static func loadTextStyles() -> TextStyles {
        guard let data = UserDefaults.standard.data(forKey: textStylesKey),
              let styles = try? JSONDecoder().decode(TextStyles.self, from: data) else {
            return TextStyles()
        }
        return styles
    }

    private func saveTextStyles() {
        if let data = try? JSONEncoder().encode(textStyles) {
            UserDefaults.standard.set(data, forKey: Self.textStylesKey)
        }
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

    /// A drag is starting on `id`: kick off the underlay + sprite renders.
    /// Until they land, per-move previews fall back to full submits.
    func beginLayerDrag(id: UUID) {
        guard dragPreview?.layerID != id else { return }
        dragPreview = nil
        clearPreviewAfterNextFrame = false
        dragPreviewGeneration += 1
        let generation = dragPreviewGeneration
        guard let doc = document, let layer = doc.layer(id: id) else { return }
        let padding = layer.style.previewPadding
        let blend = layer.effectiveBlendMode
        let renderer = previewRenderer
        let store = store
        Task.detached(priority: .userInitiated) {
            let underlay = renderer.render(doc, store: store, hiding: id)
            let sprite = renderer.renderSprite(for: id, in: doc, store: store, padding: padding)
            await MainActor.run { [weak self] in
                guard let self, self.dragPreviewGeneration == generation,
                      let underlay, let sprite else { return }
                self.dragPreview = DragPreview(layerID: id, underlay: underlay, sprite: sprite,
                                               padding: padding, blendMode: blend)
            }
        }
    }

    /// Live drag update (move or resize). With a CA preview active the canvas
    /// already shows the move, so this only records state; otherwise it
    /// renders the new frame without touching history.
    func previewLayerFrame(id: UUID, frame: CGRect) {
        previewMove = (id, frame)
        guard dragPreview?.layerID != id else { return }
        guard var doc = document, doc.layer(id: id) != nil else { return }
        doc.updateLayer(id: id) { $0 = $0.resized(to: frame) }
        submit(doc)
    }

    /// Mouse-up: one undoable step from the pre-drag frame to the final one.
    /// Committing back to the original frame is a recognized no-op (History
    /// skips it), which is how an Esc-cancelled drag restores the real render.
    /// `resized(to:)` remaps annotation endpoints so resize scales the shape.
    func commitLayerFrame(id: UUID, frame: CGRect) {
        previewMove = nil
        dragPreviewGeneration += 1 // cancels an in-flight preview session
        clearPreviewAfterNextFrame = dragPreview != nil
        perform { $0.updateLayer(id: id) { $0 = $0.resized(to: frame) } }
    }

    /// Endpoint-drag commit from the canvas (document coords, ⇧ already
    /// applied). Rebuilds the layer's frame around the new endpoints in one
    /// undo step; committing the original endpoints is a History no-op (how
    /// an Esc-cancelled endpoint drag restores the real render).
    func commitAnnotationEndpoints(id: UUID, start: CGPoint, end: CGPoint) {
        previewMove = nil
        dragPreviewGeneration += 1
        clearPreviewAfterNextFrame = dragPreview != nil
        perform { $0.updateLayer(id: id) { $0 = AnnotationBuilder.updating($0, start: start, end: end) } }
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
        discardDragPreview() // undone edits may invalidate a held sprite
        history?.undo()
        rerender()
    }

    func redo() {
        discardDragPreview()
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
            dragPreview = nil
            editingTextLayerID = nil
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
        // Same for the layer behind an inline text edit (the canvas cancels
        // its editor when the layer disappears).
        if let id = editingTextLayerID, document.layer(id: id) == nil {
            editingTextLayerID = nil
        }
        submit(document)
    }

    /// Hands a document (committed or move-preview) to the render scheduler.
    private func submit(_ document: PhotonzDocument) {
        var document = document
        // The inline editor overlay stands in for the layer being edited.
        if let id = editingTextLayerID {
            document.updateLayer(id: id) { $0.isVisible = false }
        }
        if scheduler == nil {
            scheduler = RenderScheduler(store: store) { [weak self] image in
                await MainActor.run {
                    // Drop the frame if the document was closed while rendering.
                    guard let self, self.history != nil else { return }
                    self.renderedImage = image
                    if self.clearPreviewAfterNextFrame {
                        self.clearPreviewAfterNextFrame = false
                        self.dragPreview = nil
                    }
                }
            }
        }
        guard let scheduler else { return }
        Task { await scheduler.submit(document) }
    }
}
