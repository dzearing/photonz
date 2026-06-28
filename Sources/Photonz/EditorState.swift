import AppKit
import CoreGraphics
import Observation
import PhotonzCore
import PhotonzRender
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class EditorState {
    private(set) var history: History?
    let store = ImageStore()
    /// Created lazily (not in init) so its frame-delivery closure can capture self.
    private var scheduler: RenderScheduler?

    /// The composited document, refreshed asynchronously after every edit
    /// (latest-wins: rapid edits coalesce instead of queueing renders).
    private(set) var renderedImage: CGImage?
    var isImporterPresented = false
    var isResizeDialogPresented = false
    var isCanvasSizeDialogPresented = false
    var isLayersPanelVisible = true
    var isExportDialogPresented = false

    /// Canvas camera. Nil until a document is open. All zoom/pan flows through
    /// `Viewport` (PhotonzCore) so the math stays tested.
    private(set) var viewport: Viewport?
    /// Marquee selection in document coordinates (pixel-aligned). Nil = no selection.
    private(set) var selection: CGRect?
    /// The active editor tool. Drawing tools are ONE-SHOT by default: after a
    /// shape is drawn the editor returns to `.select` (and selects the new
    /// shape). Double-clicking a tool in the toolbar sets `toolLocked`, which
    /// keeps it active for repeated drawing until the user leaves it.
    private(set) var activeTool: Tool = .select
    /// When true, the active drawing tool stays put after each shape instead of
    /// reverting to select. Set by double-clicking the tool; cleared whenever
    /// the tool changes.
    private(set) var toolLocked = false
    /// The pending crop rect (document coords) while the crop tool is active.
    private(set) var cropRect: CGRect?
    /// Crop aspect lock; the crop rect always honors it.
    private(set) var cropAspect: CropAspect = .free
    /// When set, crop mode targets this layer (non-destructive content crop)
    /// instead of the whole document.
    private(set) var cropTargetLayerID: UUID?
    /// Styling for new annotations, set from the style popover. Persisted so
    /// the user's color/width survive relaunches.
    private(set) var annotationStyles: AnnotationStyles = EditorState.loadAnnotationStyles()
    /// Styling for new text blocks, set from the font picker. Persisted like
    /// annotation styles.
    private(set) var textStyles: TextStyles = EditorState.loadTextStyles()
    /// Template style for new measures (color, stroke, unit, label toggle, caps).
    /// In-memory default for now; start/end are ignored (set per drag).
    // strokeWidth is in LOGICAL pixels (rendered ×pixelScale) so a 1px sizer line
    // aligns with the image's pixel grid.
    private(set) var measureStyle = MeasureContent(strokeWidth: 1, colorHex: "#FF3B30",
                                                   showLabel: true, unit: .pixels, form: .bracket)
    /// Recently committed colors, SHARED across annotations/text/borders (13.2).
    /// Recorded on commit only (never on live preview) and persisted.
    private(set) var recentColors: RecentColors = EditorState.loadRecentColors()
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

    /// The .photonz package backing this document; nil until first save (or
    /// always, for plain-image documents the user hasn't saved as a package).
    private(set) var documentURL: URL?

    /// The capture file this window was opened to edit, if it lives in the
    /// capture folder (phase 11.5). Lets "Save to Capture History" offer
    /// Override-in-place vs Save-as-new.
    private(set) var sourceCaptureURL: URL?

    /// The file this window was opened from (screenshot/image/package), for the
    /// window title. Distinct from `documentURL`, which is only set once saved as
    /// a `.photonz` package.
    private(set) var openedFileURL: URL?

    /// "Untitled N" name for a brand-new (unsaved) window, assigned once at seed
    /// so windows are tellable apart in the ⌘` switcher / Window menu / Dock.
    private(set) var untitledName = "Untitled"
    private static var untitledCount = 0
    private static func nextUntitledName() -> String {
        untitledCount += 1
        return "Untitled \(untitledCount)"
    }

    /// The window title: the saved package name, else the opened file's name,
    /// else "Untitled N". Reactive — updates when the document is saved.
    var windowTitle: String {
        if let url = documentURL ?? openedFileURL { return url.lastPathComponent }
        return untitledName
    }

    /// The .photonz document package type. The bundle's Info.plist exports
    /// the same identifier so Finder treats packages as files.
    static let photonzType = UTType(exportedAs: "com.photonz.document", conformingTo: .package)

    func openImage(at url: URL) {
        if url.pathExtension.lowercased() == "photonz" {
            openPackage(at: url)
            return
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        openCapture(image)
    }

    /// Drag-and-drop / drop of an image URL (from the history overlay, Finder, …):
    /// when a document is already open, the image lands as a **new layer**
    /// (centered, aspect-fit) so it can be cropped/moved/styled; with no
    /// document open, it opens as a fresh document. `.photonz` packages always
    /// open as a document.
    func addImageLayerOrOpen(at url: URL) {
        if url.pathExtension.lowercased() == "photonz" || document == nil {
            openImage(at: url)
            return
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        pasteImage(image)
    }

    /// Opens a CGImage (from a file or a screen capture) as a fresh document.
    func openCapture(_ image: CGImage) {
        let ref = store.register(image)
        installDocument(.withBaseImage(ref), url: nil)
    }

    /// Seeds a freshly created editor window from its window identity (phase
    /// 11.1). Called once when the window appears; window reuse (re-opening the
    /// same id) keeps the existing state, giving focus-existing for free, so
    /// this never reloads a window that already holds a document.
    func seed(from windowID: EditorWindowID, capture: CaptureCenter) {
        guard document == nil else { return }
        switch windowID {
        case .file(let url):
            openImage(at: url)
            openedFileURL = url
            // A file opened from the capture folder can round-trip back to history.
            if url.deletingLastPathComponent().standardizedFileURL == capture.store.directory.standardizedFileURL {
                sourceCaptureURL = url
            }
        case .clipboard:
            newFromClipboard()
            untitledName = Self.nextUntitledName()
        case .fresh:
            untitledName = Self.nextUntitledName() // empty editor; onboarding card guides next step
        case .video:
            break // routed to the video editor (VideoEditorState), never here
        }
    }

    /// Installs a freshly opened document, resetting every per-document bit
    /// of editor state.
    private func installDocument(_ document: PhotonzDocument, url: URL?) {
        history = History(document: document)
        documentURL = url
        viewport = .fit(documentSize: document.canvasSize, in: canvasViewSize)
        selection = nil
        selectedLayerID = nil
        activeTool = .select
        previewMove = nil
        dragPreview = nil
        editingTextLayerID = nil
        stylePreview = nil
        thumbnailCache = [:]
        dragPreviewGeneration += 1
        rerender()
    }

    // MARK: - Save / open packages

    /// ⌘S: saves in place, or runs Save As for a never-saved document.
    func saveDocument() {
        if let documentURL {
            save(to: documentURL)
        } else {
            saveDocumentAs()
        }
    }

    /// ⇧⌘S.
    func saveDocumentAs() {
        guard document != nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.photonzType]
        panel.nameFieldStringValue = documentURL?.lastPathComponent ?? "Untitled.photonz"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        save(to: url)
    }

    private func save(to url: URL) {
        guard let document else { return }
        do {
            try PackageIO.write(document, store: store, to: url)
            documentURL = url
        } catch {
            presentError("Couldn't save the document.", error)
        }
    }

    func openPackage(at url: URL) {
        do {
            let document = try PackageIO.read(from: url, into: store)
            installDocument(document, url: url)
        } catch {
            presentError("Couldn't open the document.", error)
        }
    }

    // MARK: - Export

    /// The flattened composite at 1× — used by the capture-history round-trip
    /// (phase 11.5) to write an edited capture back to the store.
    func compositeImage() -> CGImage? {
        guard let document else { return nil }
        return previewRenderer.render(document, store: store)
    }

    /// Renders the composite at `scale` and writes it where the user picks.
    func exportComposite(format: ImageCodec.Format, scale: CGFloat, quality: Double = 0.9) {
        guard let document,
              let image = previewRenderer.render(document, store: store, scale: scale),
              let data = ImageCodec.encode(image, format: format, quality: quality) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        let base = documentURL?.deletingPathExtension().lastPathComponent ?? "Photonz Export"
        panel.nameFieldStringValue = "\(base)\(scale == 2 ? "@2x" : "").\(format.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
        } catch {
            presentError("Couldn't export the image.", error)
        }
    }

    /// ⇧⌘C: the flattened composite goes on the pasteboard as PNG + TIFF
    /// (PNG for modern consumers, TIFF for the long tail of AppKit apps).
    func copyCompositeToClipboard() {
        guard let document,
              let image = previewRenderer.render(document, store: store) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let png = ImageCodec.encode(image, format: .png) {
            pasteboard.setData(png, forType: .png)
        }
        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        if let tiff = nsImage.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    private func presentError(_ message: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = String(describing: error)
        alert.alertStyle = .warning
        alert.runModal()
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

    func setTool(_ tool: Tool, locked: Bool = false) {
        guard activeTool != tool else { return }
        if tool == .crop {
            // A selected image layer makes this a per-layer crop; otherwise
            // the marquee selection seeds the rect (a common flow: marquee
            // the region, then C to crop to it).
            if let id = selectedLayerID, let layer = document?.layer(id: id),
               layer.supportsContentCrop {
                cropTargetLayerID = id
                cropRect = Crop.fitted(layer.frame, to: cropAspect)
            } else {
                cropTargetLayerID = nil
                cropRect = defaultCropRect()
            }
        } else {
            cropTargetLayerID = nil
            cropRect = nil
        }
        activeTool = tool
        // Switching tools always clears any lock; double-clicking re-locks.
        toolLocked = locked
        // Drawing tools own the pointer; select-mode chrome (marquee ants,
        // layer handles) would read as interactive when it isn't.
        if tool != .select {
            selection = nil
            selectedLayerID = nil
        }
    }

    /// Double-click a tool: keep it active for repeated drawing (sticky)
    /// instead of reverting to select after each shape.
    func lockTool(_ tool: Tool) {
        setTool(tool)
        toolLocked = true
    }

    // MARK: - Crop mode

    private func defaultCropRect() -> CGRect? {
        guard let document else { return nil }
        let base = selection ?? CGRect(origin: .zero, size: document.canvasSize)
        return Crop.fitted(base, to: cropAspect)
    }

    /// What the crop rect is confined to: the target layer's frame for a
    /// per-layer crop, else the whole canvas.
    var cropBounds: CGRect? {
        guard activeTool == .crop, let document else { return nil }
        if let id = cropTargetLayerID, let layer = document.layer(id: id) {
            return layer.frame
        }
        return CGRect(origin: .zero, size: document.canvasSize)
    }

    /// Crop rect updates from the canvas (drags already aspect-locked and
    /// canvas-clamped by `Crop`).
    func setCropRect(_ rect: CGRect) {
        cropRect = rect
    }

    /// An aspect pick re-fits the pending rect so it holds immediately.
    func setCropAspect(_ aspect: CropAspect) {
        cropAspect = aspect
        if let rect = cropRect { cropRect = Crop.fitted(rect, to: aspect) }
    }

    /// ⏎ or the toolbar checkmark: one undo step, then back to select. A
    /// layer target gets a non-destructive content crop and stays selected;
    /// otherwise the whole document crops.
    func commitCrop() {
        guard let rect = cropRect else { return }
        let aligned = Geometry.pixelAligned(rect)
        let target = cropTargetLayerID
        if let target {
            perform { $0.updateLayer(id: target) { $0.cropContent(to: aligned) } }
        } else {
            perform { $0.crop(to: aligned) }
        }
        setTool(.select)
        selectedLayerID = target
    }

    /// ⎋ or the toolbar ✕: discard the pending rect.
    func cancelCrop() {
        setTool(.select)
    }

    /// Resize-dialog apply: scales the canvas and every layer frame in one
    /// undo step.
    func resizeDocument(to size: CGSize) {
        perform { $0.resize(to: size) }
    }

    /// Canvas-size apply: grows/shrinks the canvas around the anchor without
    /// scaling content, one undo step.
    func setCanvasSize(to size: CGSize, anchor: CanvasAnchor) {
        perform { $0.setCanvasSize(size, anchor: anchor) }
    }

    /// Completed drag-to-create from the canvas (document coords, ⇧ already
    /// applied). Adds one annotation layer as a single undo step.
    func addAnnotation(from start: CGPoint, to end: CGPoint) {
        guard let shape = activeTool.annotationShape,
              let content = annotationStyles.content(for: activeTool) else { return }
        var layer = AnnotationBuilder.layer(content: content, from: start, to: end)
        // Inherit this shape's last non-destructive effects (e.g. a drop shadow
        // added to the previous arrow carries to the next).
        layer.style = annotationStyles.layerStyle(forShape: shape)
        perform { $0.addLayer(layer) }
        // One-shot by default: return to select and select the new shape so it
        // can be adjusted immediately. A double-click-locked tool stays put.
        if !toolLocked {
            setTool(.select)
            selectedLayerID = layer.id
        }
    }

    /// Completed source-box drag from the zoom tool. One undo step adds the
    /// callout (placement picked by Geometry); unlike the sticky annotation
    /// tools the editor returns to select — callouts are usually adjusted,
    /// not added in batches.
    func addZoomCallout(from start: CGPoint, to end: CGPoint) {
        guard let document,
              let layer = ZoomCalloutBuilder.layer(from: start, to: end,
                                                   canvas: document.canvasSize) else { return }
        perform { $0.addLayer(layer) }
        setTool(.select)
    }

    /// Completed measure drag: place a dimension layer with the active style and
    /// the drag's mode (free / H-lock / V-lock). Sticky like the annotation tools
    /// unless one-shot; selects the new layer so it can be tweaked.
    func addMeasure(from start: CGPoint, to end: CGPoint, mode: MeasureMode) {
        var content = measureStyle
        content.mode = mode
        let layer = MeasureBuilder.layer(content: content, from: start, to: end)
        perform { $0.addLayer(layer) }
        recordRecentColor(hex: content.colorHex)
        if !toolLocked {
            setTool(.select)
            selectedLayerID = layer.id
        }
    }

    // MARK: - Measure styling

    /// The selected layer, if it's a measure.
    var selectedMeasureLayer: Layer? {
        guard let id = selectedLayerID, let layer = document?.layer(id: id),
              layer.measure != nil else { return nil }
        return layer
    }

    /// The unit shown by new measures and the selected one. Each setter restyles
    /// the selected measure (re-padding its frame via the builder) in one undo step.
    func setMeasureUnit(_ unit: MeasureUnit) {
        measureStyle.unit = unit
        applyMeasureRestyle { MeasureBuilder.restyled($0, unit: unit) }
    }

    func setMeasureShowLabel(_ show: Bool) {
        measureStyle.showLabel = show
        applyMeasureRestyle { MeasureBuilder.restyled($0, showLabel: show) }
    }

    func setMeasureForm(_ form: MeasureForm) {
        measureStyle.form = form
        applyMeasureRestyle { MeasureBuilder.restyled($0, form: form) }
    }

    /// Sizer line thickness in logical pixels.
    func setMeasureThickness(_ width: CGFloat) {
        measureStyle.strokeWidth = width
        applyMeasureRestyle { MeasureBuilder.restyled($0, strokeWidth: width) }
    }

    /// Force a measure's orientation (which axis is the gap) instead of relying
    /// on the drag's dominant axis.
    func setMeasureAxis(_ axis: MeasureMode) {
        measureStyle.mode = axis
        applyMeasureRestyle { MeasureBuilder.restyled($0, mode: axis) }
    }

    /// Flip a bracket to the opposite side by swapping its two box corners — the
    /// U opens the other way and the connector/label move across.
    func invertMeasure() {
        guard let layer = selectedMeasureLayer,
              let s = layer.measureEndpoint(.start), let e = layer.measureEndpoint(.end) else { return }
        perform { $0.updateLayer(id: layer.id) { $0 = MeasureBuilder.updating($0, start: e, end: s) } }
    }

    func setMeasureColor(_ hex: String, commit: Bool) {
        measureStyle.colorHex = hex
        applyMeasureRestyle { MeasureBuilder.restyled($0, colorHex: hex) }
        if commit { recordRecentColor(hex: hex) }
    }

    /// The document's pixels-per-point scale, driving the points readout. A Retina
    /// screenshot is 2×. Changing it re-renders every measure's label.
    func setDocumentPixelScale(_ scale: CGFloat) {
        guard let document, document.pixelScale != scale else { return }
        perform { $0.pixelScale = scale }
    }

    /// Live corner-resize of a placed measure (no history) — re-renders so the
    /// gap value updates as the corner moves.
    func previewMeasureEndpoints(id: UUID, start: CGPoint, end: CGPoint) {
        guard var doc = document, doc.layer(id: id)?.measure != nil else { return }
        doc.updateLayer(id: id) { $0 = MeasureBuilder.updating($0, start: start, end: end) }
        if let frame = doc.layer(id: id)?.frame { previewMove = (id, frame) }
        submit(doc)
    }

    /// Mouse-up on a measure corner: one undoable step. Committing the original
    /// corners is a History no-op (the Esc-cancel path).
    func commitMeasureEndpoints(id: UUID, start: CGPoint, end: CGPoint) {
        previewMove = nil
        perform { $0.updateLayer(id: id) { $0 = MeasureBuilder.updating($0, start: start, end: end) } }
    }

    var documentPixelScale: CGFloat { document?.pixelScale ?? 1 }

    private func applyMeasureRestyle(_ restyle: (Layer) -> Layer) {
        guard let layer = selectedMeasureLayer else { return }
        let updated = restyle(layer)
        perform { $0.updateLayer(id: layer.id) { $0 = updated } }
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
        recordRecentColor(hex: hex)
    }

    /// The shape a toolbar-popover style edit applies to: the selected
    /// annotation's shape (select tool) or the active drawing tool's shape.
    private var styleTargetShape: AnnotationShape? {
        selectedAnnotationLayer?.annotation?.shape ?? activeTool.annotationShape
    }

    func setAnnotationStrokeWidth(_ width: CGFloat) {
        if let layer = selectedAnnotationLayer, layer.annotation?.shape != .highlight {
            discardDragPreview()
            perform { $0.updateLayer(id: layer.id) { $0 = AnnotationBuilder.restyled($0, strokeWidth: width) } }
        }
        if let shape = styleTargetShape, shape != .highlight {
            annotationStyles.setStrokeWidth(width, forShape: shape)
        }
        saveAnnotationStyles()
    }

    /// Live slider drag: restyle the selected stroke/arrow WITHOUT recording an
    /// undo step (the canvas updates immediately), keeping that shape's default
    /// in sync so the value also applies to the next-drawn annotation. Commit on
    /// release via `setAnnotationStrokeWidth` / `setAnnotationArrowheadScale`.
    func previewAnnotationRestyle(strokeWidth: CGFloat? = nil, arrowheadScale: CGFloat? = nil) {
        if let shape = styleTargetShape {
            if let strokeWidth, shape != .highlight { annotationStyles.setStrokeWidth(strokeWidth, forShape: shape) }
            if let arrowheadScale { annotationStyles.setArrowheadScale(arrowheadScale, forShape: shape) }
        }
        guard let layer = selectedAnnotationLayer, var doc = document else { return }
        discardDragPreview()
        doc.updateLayer(id: layer.id) {
            $0 = AnnotationBuilder.restyled($0, strokeWidth: strokeWidth, arrowheadScale: arrowheadScale)
        }
        submit(doc)
    }

    /// Arrow-only: the arrowhead size multiplier. Restyles the selected arrow
    /// (one undo step) and updates the arrow default for new arrows.
    func setAnnotationArrowheadScale(_ scale: CGFloat) {
        if let layer = selectedAnnotationLayer, layer.annotation?.shape == .arrow {
            discardDragPreview()
            perform { $0.updateLayer(id: layer.id) { $0 = AnnotationBuilder.restyled($0, arrowheadScale: scale) } }
        }
        if let shape = styleTargetShape, shape == .arrow {
            annotationStyles.setArrowheadScale(scale, forShape: .arrow)
        }
        saveAnnotationStyles()
    }

    // MARK: - Layers-panel annotation inspector (targets a specific layer,
    // independent of the active tool — so editing a selected line/arrow's style
    // from the docked panel always reaches the document and that shape's default).

    /// Live inspector-slider restyle of `layerID` (no undo step). Updates the
    /// shape's persisted default too, so the next-drawn object of that type
    /// inherits it.
    func previewAnnotationRestyle(layerID: UUID, strokeWidth: CGFloat? = nil, arrowheadScale: CGFloat? = nil,
                                  cornerRadius: CGFloat? = nil) {
        guard var doc = document, let shape = doc.layer(id: layerID)?.annotation?.shape else { return }
        if let strokeWidth, shape != .highlight { annotationStyles.setStrokeWidth(strokeWidth, forShape: shape) }
        if let arrowheadScale { annotationStyles.setArrowheadScale(arrowheadScale, forShape: shape) }
        discardDragPreview()
        doc.updateLayer(id: layerID) {
            $0 = AnnotationBuilder.restyled($0, strokeWidth: strokeWidth, arrowheadScale: arrowheadScale,
                                            cornerRadius: cornerRadius)
        }
        submit(doc)
    }

    /// Inspector slider release: one undo step + persist the shape default.
    func commitAnnotationRestyle(layerID: UUID, strokeWidth: CGFloat? = nil, arrowheadScale: CGFloat? = nil,
                                 cornerRadius: CGFloat? = nil) {
        guard let shape = document?.layer(id: layerID)?.annotation?.shape else { return }
        discardDragPreview()
        perform { $0.updateLayer(id: layerID) {
            $0 = AnnotationBuilder.restyled($0, strokeWidth: strokeWidth, arrowheadScale: arrowheadScale,
                                            cornerRadius: cornerRadius)
        } }
        if let strokeWidth, shape != .highlight { annotationStyles.setStrokeWidth(strokeWidth, forShape: shape) }
        if let arrowheadScale { annotationStyles.setArrowheadScale(arrowheadScale, forShape: shape) }
        saveAnnotationStyles()
    }

    /// Inspector color pick on `layerID`: one undo step + persist the shape default.
    func setAnnotationColor(layerID: UUID, _ hex: String) {
        guard let shape = document?.layer(id: layerID)?.annotation?.shape else { return }
        discardDragPreview()
        perform { $0.updateLayer(id: layerID) { $0 = AnnotationBuilder.restyled($0, colorHex: hex) } }
        annotationStyles.setColorHex(hex, forShape: shape)
        saveAnnotationStyles()
        recordRecentColor(hex: hex)
    }

    // MARK: - Zoom-callout inspector

    /// The selected zoom-callout layer when the select tool is active — the
    /// style popover becomes the callout inspector for it.
    var selectedZoomCalloutLayer: Layer? {
        guard activeTool == .select, let id = selectedLayerID,
              let layer = document?.layer(id: id), layer.zoomCallout != nil else { return nil }
        return layer
    }

    /// The selected callout's magnification, preview-aware so the inspector
    /// slider doesn't snap back mid-drag (previews live in the frame, and
    /// frame ÷ source is the magnification by construction).
    var selectedCalloutMagnification: CGFloat? {
        guard let layer = selectedZoomCalloutLayer, let callout = layer.zoomCallout,
              callout.sourceRect.width > 0 else { return nil }
        return (selectedLayerFrame?.width ?? layer.frame.width) / callout.sourceRect.width
    }

    /// Slider movement: the box grows around its center via the regular
    /// frame-preview path (rendered live, no history).
    func previewCalloutMagnification(_ magnification: CGFloat) {
        guard let layer = selectedZoomCalloutLayer else { return }
        previewLayerFrame(id: layer.id, frame: ZoomCalloutBuilder.frame(for: magnification, of: layer))
    }

    /// Slider release: one undo step from the pre-drag frame to the last
    /// previewed one (a no-move release is a History no-op).
    func commitCalloutMagnification() {
        guard let layer = selectedZoomCalloutLayer, let frame = selectedLayerFrame else { return }
        commitLayerFrame(id: layer.id, frame: frame)
    }

    func setCalloutShape(_ shape: ZoomCalloutShape) {
        guard let layer = selectedZoomCalloutLayer, var callout = layer.zoomCallout,
              callout.shape != shape else { return }
        callout.shape = shape
        perform { $0.updateLayer(id: layer.id) { $0.content = .zoomCallout(callout) } }
    }

    func setCalloutBorderColor(_ hex: String) {
        guard let layer = selectedZoomCalloutLayer else { return }
        perform { $0.updateLayer(id: layer.id) { $0.style.borderColorHex = hex } }
        recordRecentColor(hex: hex)
    }

    func setCalloutBorderWidth(_ width: CGFloat) {
        guard let layer = selectedZoomCalloutLayer else { return }
        perform { $0.updateLayer(id: layer.id) { $0.style.borderWidth = width } }
    }

    /// Drops a live drag preview whose sprite no longer matches the layer
    /// (content edits, undo/redo). The canvas falls back to the last composite
    /// until the re-render lands, so nothing flashes.
    private func discardDragPreview() {
        dragPreviewGeneration += 1
        dragPreview = nil
        clearPreviewAfterNextFrame = false
    }

    // MARK: - Recent colors (13.2)

    private static let recentColorsKey = "recentColors"

    private static func loadRecentColors() -> RecentColors {
        guard let data = UserDefaults.standard.data(forKey: recentColorsKey),
              let recents = try? JSONDecoder().decode(RecentColors.self, from: data) else {
            return RecentColors()
        }
        return recents
    }

    /// The single funnel for the shared recents list. Called from every COMMIT
    /// path (not preview): annotation color, per-layer annotation color, text
    /// color, callout border color, and LayerStyle border/shadow. Malformed hex
    /// is ignored by `RecentColors.record`.
    func recordRecentColor(hex: String) {
        recentColors.record(hex: hex)
        if let data = try? JSONEncoder().encode(recentColors) {
            UserDefaults.standard.set(data, forKey: Self.recentColorsKey)
        }
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

    /// The selected text layer when the select tool is active — the properties
    /// panel edits its font face/size/weight/color (13.1) instead of only the
    /// new-text defaults. Mirrors `selectedAnnotationLayer`.
    var selectedTextLayer: Layer? {
        guard activeTool == .select, let id = selectedLayerID,
              let layer = document?.layer(id: id),
              case .text = layer.content else { return nil }
        return layer
    }

    /// Restyles the selected text layer through `TextBuilder.restyled` and
    /// re-measures its frame (the rasterizer needs CoreText, so it's done here),
    /// keeping the wrap width so layout doesn't shift. One undo step.
    private func restyleSelectedText(_ layer: Layer, fontName: String? = nil,
                                     fontSize: CGFloat? = nil, weight: TextWeight? = nil,
                                     colorHex: String? = nil) {
        discardDragPreview()
        let maxWidth = layer.frame.width
        perform { document in
            document.updateLayer(id: layer.id) { l in
                l = TextBuilder.restyled(layer: l, fontName: fontName, fontSize: fontSize,
                                         weight: weight, colorHex: colorHex)
                if case .text(let content) = l.content {
                    let size = TextRasterizer.naturalSize(content, maxWidth: maxWidth,
                                                          minWidth: TextRasterizer.minimumTextWidth)
                    l.frame = CGRect(origin: l.frame.origin, size: size)
                }
            }
        }
    }

    func setTextFont(_ name: String) {
        if let layer = selectedTextLayer { restyleSelectedText(layer, fontName: name) }
        textStyles.fontName = name
        saveTextStyles()
    }

    func setTextFontSize(_ size: CGFloat) {
        if let layer = selectedTextLayer { restyleSelectedText(layer, fontSize: size) }
        textStyles.fontSize = size
        saveTextStyles()
    }

    func setTextWeight(_ weight: TextWeight) {
        if let layer = selectedTextLayer { restyleSelectedText(layer, weight: weight) }
        textStyles.weight = weight
        saveTextStyles()
    }

    func setTextColor(_ hex: String) {
        if let layer = selectedTextLayer { restyleSelectedText(layer, colorHex: hex) }
        textStyles.colorHex = hex
        saveTextStyles()
        recordRecentColor(hex: hex)
    }

    // MARK: - Docked text inspector (targets a specific layer, independent of
    // the active tool — so editing a selected text element's font from the
    // docked panel always reaches the document and updates the new-text default).

    /// Restyles `layerID` if it's a text layer, re-measuring its frame. One undo
    /// step. Also updates the new-text default so the next block inherits it.
    func setTextStyle(layerID: UUID, fontName: String? = nil, fontSize: CGFloat? = nil,
                      weight: TextWeight? = nil, colorHex: String? = nil) {
        guard let layer = document?.layer(id: layerID),
              case .text = layer.content else { return }
        restyleSelectedText(layer, fontName: fontName, fontSize: fontSize,
                            weight: weight, colorHex: colorHex)
        if let fontName { textStyles.fontName = fontName }
        if let fontSize { textStyles.fontSize = fontSize }
        if let weight { textStyles.weight = weight }
        if let colorHex { textStyles.colorHex = colorHex }
        saveTextStyles()
        if let colorHex { recordRecentColor(hex: colorHex) }
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
                let size = TextRasterizer.naturalSize(content, maxWidth: maxWidth,
                                                      minWidth: TextRasterizer.minimumTextWidth)
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
            let size = TextRasterizer.naturalSize(content, maxWidth: maxWidth,
                                                  minWidth: TextRasterizer.minimumTextWidth)
            let layer = TextBuilder.layer(content: content, at: origin, naturalSize: size)
            perform { $0.addLayer(layer) }
            // One-shot text placement reverts to select (re-edits run with the
            // select tool already active, so the guard leaves them untouched).
            if activeTool == .text, !toolLocked {
                setTool(.select)
                selectedLayerID = layer.id
            }
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

    // MARK: - Layers panel

    /// Style override while an inspector slider drag is in flight — rendered
    /// as a preview, committed to history only on release (one undo step per
    /// gesture, same pattern as move/resize drags).
    private var stylePreview: (id: UUID, style: LayerStyle)?
    /// Thumbnail cache keyed by layer id; `hash` invalidates on any layer edit.
    private var thumbnailCache: [UUID: (hash: Int, image: CGImage)] = [:]
    private var thumbnailsInFlight: Set<Int> = []

    /// Layers in panel order (visual index 0 = topmost).
    var panelLayers: [Layer] {
        (document?.layers ?? []).reversed()
    }

    /// The selected layer's style, preview-aware so inspector sliders don't
    /// snap back mid-drag.
    func previewedStyle(of id: UUID) -> LayerStyle? {
        if let stylePreview, stylePreview.id == id { return stylePreview.style }
        return document?.layer(id: id)?.style
    }

    /// Live inspector-slider update: renders the new style without touching
    /// history. The first preview of a gesture drops any held drag sprite
    /// (it shows the old style).
    func previewLayerStyle(id: UUID, _ mutate: (inout LayerStyle) -> Void) {
        guard var style = previewedStyle(of: id) else { return }
        if stylePreview?.id != id { discardDragPreview() }
        mutate(&style)
        stylePreview = (id, style)
        guard var doc = document else { return }
        doc.updateLayer(id: id) { $0.style = style }
        submit(doc)
    }

    /// Slider release: one undo step from the pre-gesture style to the last
    /// previewed one (a no-change release is a History no-op).
    func commitLayerStyle(id: UUID) {
        guard let preview = stylePreview, preview.id == id else { return }
        stylePreview = nil
        perform { $0.updateLayer(id: id) { $0.style = preview.style } }
        captureAnnotationStyleDefault(layerID: id)
    }

    /// One-shot style edit (steppers, toggles): a single undo step, no preview.
    func setLayerStyle(id: UUID, _ mutate: @escaping (inout LayerStyle) -> Void) {
        stylePreview = nil
        discardDragPreview()
        perform { $0.updateLayer(id: id) { mutate(&$0.style) } }
        captureAnnotationStyleDefault(layerID: id)
    }

    /// If `layerID` is an annotation, remember its current effects as that
    /// shape's default so the next-drawn object of the type inherits them.
    private func captureAnnotationStyleDefault(layerID: UUID) {
        guard let layer = document?.layer(id: layerID), let shape = layer.annotation?.shape else { return }
        annotationStyles.setLayerStyle(layer.style, forShape: shape)
        saveAnnotationStyles()
    }

    func toggleLayerVisibility(id: UUID) {
        discardDragPreview()
        perform { $0.updateLayer(id: id) { $0.isVisible.toggle() } }
    }

    func toggleLayerLock(id: UUID) {
        perform { $0.updateLayer(id: id) { $0.isLocked.toggle() } }
        if document?.layer(id: id)?.isLocked == true, selectedLayerID == id {
            selectedLayerID = nil
        }
    }

    func renameLayer(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        perform { $0.updateLayer(id: id) { $0.name = trimmed } }
    }

    func deleteLayer(id: UUID) {
        discardDragPreview()
        if selectedLayerID == id { selectedLayerID = nil }
        perform { $0.removeLayer(id: id) }
    }

    func duplicateLayer(id: UUID) {
        discardDragPreview()
        var copyID: UUID?
        perform { copyID = $0.duplicateLayer(id: id, offsetBy: CGPoint(x: 16, y: 16))?.id }
        selectedLayerID = copyID
    }

    /// Drag-reorder from the layers panel (SwiftUI `onMove` indices, visual
    /// top-down order). One undo step.
    func moveLayers(visualSources: IndexSet, visualDestination: Int) {
        discardDragPreview()
        perform { $0.moveLayers(visualSources: visualSources, visualDestination: visualDestination) }
    }

    /// The panel row thumbnail: cached per layer, re-rendered asynchronously
    /// whenever the layer changes (the hash covers content, frame, and style).
    func thumbnail(for layer: Layer) -> CGImage? {
        let hash = layer.hashValue
        if let cached = thumbnailCache[layer.id], cached.hash == hash { return cached.image }
        guard let doc = document else { return thumbnailCache[layer.id]?.image }
        if !thumbnailsInFlight.contains(hash) {
            let renderer = previewRenderer
            let store = store
            let id = layer.id
            // Defer the in-flight bookkeeping off the view-body read path.
            Task { @MainActor [weak self] in
                guard let self, !self.thumbnailsInFlight.contains(hash) else { return }
                self.thumbnailsInFlight.insert(hash)
                let image = await Task.detached(priority: .utility) {
                    renderer.thumbnail(for: id, in: doc, store: store, maxDimension: 80)
                }.value
                self.thumbnailsInFlight.remove(hash)
                if let image { self.thumbnailCache[id] = (hash, image) }
            }
        }
        return thumbnailCache[layer.id]?.image
    }

    // MARK: - Promote selection

    /// ⌘J: rasterizes the marquee selection from the current composite and
    /// stacks it as a new image layer (one undo step). The new layer is
    /// selected; the marquee clears — it has done its job.
    func promoteSelectionToLayer() {
        guard let document, let region = selection,
              let raster = previewRenderer.rasterize(region: region, of: document, store: store) else { return }
        let ref = store.register(raster)
        var newID: UUID?
        perform { newID = $0.promoteRegionToLayer(region: region, rasterized: ref, name: "Promoted Layer").id }
        selection = nil
        selectedLayerID = newID
    }

    /// One-click blur-behind: a single full-canvas rasterization becomes a
    /// blurred backdrop layer plus a sharp cutout cropped to the selection
    /// (one undo step). The focus layer ends up selected so its blur radius
    /// or crop can be adjusted immediately.
    func blurBehindSelection() {
        guard let document, let region = selection,
              let raster = previewRenderer.rasterize(region: CGRect(origin: .zero, size: document.canvasSize),
                                                     of: document, store: store) else { return }
        let ref = store.register(raster)
        var focusID: UUID?
        perform { focusID = $0.blurBehind(selection: region, rasterized: ref).focus.id }
        selection = nil
        selectedLayerID = focusID
    }

    // MARK: - Clipboard

    /// ⌘C with a layer selected: the layer's model JSON (plus its bitmap for
    /// image layers — ImageRefs only mean something in this window's store)
    /// goes on the pasteboard under a Photonz-private type.
    func copySelectedLayer() {
        guard let id = selectedLayerID, let layer = document?.layer(id: id) else { return }
        var imageData: Data?
        if case .image(let ref) = layer.content, let cg = store.image(for: ref) {
            imageData = ImageCodec.encode(cg, format: .png)
        }
        guard let payload = try? JSONEncoder().encode(LayerTransfer(layer: layer, imageData: imageData)) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(payload, forType: NSPasteboard.PasteboardType(LayerTransfer.pasteboardType))
    }

    /// ⌘X: copy the selected (unlocked) layer, then remove it.
    func cutSelectedLayer() {
        guard let id = selectedLayerID, let layer = document?.layer(id: id),
              !layer.isLocked else { return }
        copySelectedLayer()
        deleteLayer(id: id)
    }

    /// ⌘A (Preview convention): marquee the whole canvas.
    func selectAll() {
        guard let document else { return }
        setSelection(CGRect(origin: .zero, size: document.canvasSize))
    }

    /// ⇧⌘A: clear the marquee.
    func deselect() {
        setSelection(nil)
    }

    /// File > New from Clipboard (⌘N, Preview convention): a clipboard image
    /// becomes a new document; beeps when the clipboard has none.
    func newFromClipboard() {
        if let image = NSImage(pasteboard: .general)?
            .cgImage(forProposedRect: nil, context: nil, hints: nil) {
            openCapture(image)
        } else {
            NSSound.beep()
        }
    }

    /// ⌘V: a copied Photonz layer pastes offset with a fresh identity; any
    /// system image (screenshot, copied web image) pastes as a new layer —
    /// or opens as a document when none is open.
    func paste() {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: NSPasteboard.PasteboardType(LayerTransfer.pasteboardType)),
           let transfer = try? JSONDecoder().decode(LayerTransfer.self, from: data) {
            pasteLayer(transfer)
            return
        }
        if let image = NSImage(pasteboard: pasteboard)?
            .cgImage(forProposedRect: nil, context: nil, hints: nil) {
            pasteImage(image)
        }
    }

    private func pasteLayer(_ transfer: LayerTransfer) {
        var layer = transfer.layer.duplicated(offsetBy: CGPoint(x: 16, y: 16))
        layer.name = transfer.layer.name
        if case .image = transfer.layer.content {
            guard let data = transfer.imageData, let cg = ImageCodec.decode(data) else { return }
            // The payload's ImageRef belonged to the source window's store.
            layer.content = .image(store.register(cg))
        }
        if document == nil, case .image(let ref) = layer.content,
           let cg = store.image(for: ref) {
            openCapture(cg)
            return
        }
        guard document != nil else { return }
        discardDragPreview()
        perform { [layer] in $0.addLayer(layer) }
        selectedLayerID = layer.id
    }

    private func pasteImage(_ image: CGImage) {
        guard let document else {
            openCapture(image)
            return
        }
        let ref = store.register(image)
        let frame = PastePlacement.frame(forImageOf: ref.pixelSize, canvas: document.canvasSize)
        guard !frame.isEmpty else { return }
        let layer = Layer(name: "Pasted Image", content: .image(ref), frame: frame)
        discardDragPreview()
        perform { $0.addLayer(layer) }
        selectedLayerID = layer.id
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
        // Zoom callouts can't be sprited: their content samples the backdrop,
        // and the leader lines must track the frame live. Text can't either: it
        // re-wraps on resize, so a stretched start-bitmap would distort glyphs.
        // Both fall back to full re-renders per move, which keeps them right.
        guard layer.zoomCallout == nil else { return }
        if case .text = layer.content { return }
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

    /// Live rotate/skew update. With a CA preview active the canvas applies
    /// the transform to the floated sprite, so this only renders when the
    /// preview pieces haven't landed yet.
    func previewLayerTransform(id: UUID, transform: LayerTransform) {
        guard dragPreview?.layerID != id else { return }
        guard var doc = document, doc.layer(id: id) != nil else { return }
        doc.updateLayer(id: id) { $0.transform = transform }
        submit(doc)
    }

    /// Mouse-up on a rotate/skew drag: one undo step. Committing the original
    /// transform is a History no-op (the Esc-cancel path).
    func commitLayerTransform(id: UUID, transform: LayerTransform) {
        dragPreviewGeneration += 1
        clearPreviewAfterNextFrame = dragPreview != nil
        perform { $0.updateLayer(id: id) { $0.transform = transform } }
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
        stylePreview = nil
        history?.undo()
        rerender()
    }

    func redo() {
        discardDragPreview()
        stylePreview = nil
        history?.redo()
        rerender()
    }

    private func rerender() {
        guard let document = history?.current else {
            renderedImage = nil
            viewport = nil
            selection = nil
            cropRect = nil
            selectedLayerID = nil
            previewMove = nil
            dragPreview = nil
            editingTextLayerID = nil
            stylePreview = nil
            thumbnailCache = [:]
            return
        }
        // Thumbnails for layers that no longer exist are dead weight.
        if thumbnailCache.count != document.layers.count {
            let ids = Set(document.layers.map(\.id))
            thumbnailCache = thumbnailCache.filter { ids.contains($0.key) }
        }
        // Crop/resize/undo can change the canvas size; keep the camera in sync.
        if var vp = viewport, vp.documentSize != document.canvasSize {
            vp.documentSize = document.canvasSize
            viewport = vp.clamped()
            // A selection from the old canvas no longer means anything reliable.
            selection = nil
            // Same for a pending crop rect (undo/redo mid-crop): restart from
            // the full new canvas.
            if activeTool == .crop {
                cropRect = Crop.fitted(CGRect(origin: .zero, size: document.canvasSize), to: cropAspect)
            }
        }
        // Undo can remove the selected layer out from under us.
        if let id = selectedLayerID, document.layer(id: id) == nil {
            selectedLayerID = nil
        }
        // Same for a per-layer crop target: fall back to a document crop.
        if let id = cropTargetLayerID, document.layer(id: id) == nil {
            cropTargetLayerID = nil
            if activeTool == .crop {
                cropRect = Crop.fitted(CGRect(origin: .zero, size: document.canvasSize), to: cropAspect)
            }
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
