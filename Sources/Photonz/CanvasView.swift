import AppKit
import PhotonzCore
import PhotonzRender
import SwiftUI

/// Pre-rendered pieces for a cheap drag preview: the canvas composites
/// `sprite` over `underlay` in Core Animation, so per-mouse-move cost is pure
/// layer geometry — no Core Image.
struct DragPreview {
    let layerID: UUID
    /// The document composited with the dragged layer hidden.
    let underlay: CGImage
    /// The dragged layer rendered alone, padded by `padding` on every side.
    let sprite: CGImage
    /// Document points of shadow/blur padding baked into the sprite.
    let padding: CGFloat
    let blendMode: PhotonzCore.BlendMode
}

/// The document canvas: a layer-backed NSView that draws the rendered composite
/// positioned by `Viewport`. All geometry decisions live in `Viewport`
/// (PhotonzCore, tested); this view only mirrors them into Core Animation.
struct CanvasView: NSViewRepresentable {
    let image: CGImage?
    let viewport: Viewport?
    let document: PhotonzDocument?
    let selection: CGRect?
    /// Pending crop rect + aspect lock while the crop tool is active.
    let cropRect: CGRect?
    let cropAspect: CropAspect
    /// What the crop rect is confined to (canvas, or a layer's frame).
    let cropBounds: CGRect?
    let selectedLayerID: UUID?
    let selectedLayerFrame: CGRect?
    let dragPreview: DragPreview?
    let tool: Tool
    /// Styled content the active tool draws (color/width from the style
    /// popover), so the drag preview matches what commit will rasterize.
    let annotationContent: AnnotationContent?
    /// Current text style (string empty); the inline editor mirrors it so the
    /// draft matches what commit will rasterize.
    let textContent: TextContent?
    /// The active measure tool's style, mirrored into the in-flight preview.
    let measureContent: MeasureContent?
    let onViewSizeChange: (CGSize) -> Void
    let onViewportChange: (Viewport) -> Void
    let onSelectionChange: (CGRect?) -> Void
    let onCropRectChange: (CGRect) -> Void
    let onCropCommit: () -> Void
    let onSelectLayer: (UUID?) -> Void
    let onDragBegin: (UUID) -> Void
    let onFramePreview: (UUID, CGRect) -> Void
    let onFrameCommit: (UUID, CGRect) -> Void
    let onTransformPreview: (UUID, LayerTransform) -> Void
    let onTransformCommit: (UUID, LayerTransform) -> Void
    let onAnnotationCommit: (CGPoint, CGPoint) -> Void
    let onAnnotationEndpointsCommit: (UUID, CGPoint, CGPoint) -> Void
    let onZoomCalloutCommit: (CGPoint, CGPoint) -> Void
    let onMeasureCommit: (CGPoint, CGPoint, MeasureMode) -> Void
    let onMeasureEndpointPreview: (UUID, CGPoint, CGPoint) -> Void
    let onMeasureEndpointCommit: (UUID, CGPoint, CGPoint) -> Void
    let onToolChange: (Tool) -> Void
    let onTextEditBegin: (UUID?) -> Void
    let onTextCommit: (UUID?, CGPoint, String, CGFloat) -> Void
    let onTextCancel: () -> Void
    let onDeleteLayer: (UUID) -> Void
    let onDropImageURL: (URL) -> Void

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView()
        update(view)
        return view
    }

    func updateNSView(_ view: CanvasNSView, context: Context) {
        update(view)
        view.apply(image: image, viewport: viewport, document: document,
                   selection: selection, cropRect: cropRect, cropAspect: cropAspect,
                   cropBounds: cropBounds, selectedLayerID: selectedLayerID,
                   selectedLayerFrame: selectedLayerFrame, dragPreview: dragPreview,
                   tool: tool, annotationContent: annotationContent, textContent: textContent,
                   measureContent: measureContent)
    }

    private func update(_ view: CanvasNSView) {
        view.onViewSizeChange = onViewSizeChange
        view.onViewportChange = onViewportChange
        view.onSelectionChange = onSelectionChange
        view.onCropRectChange = onCropRectChange
        view.onCropCommit = onCropCommit
        view.onSelectLayer = onSelectLayer
        view.onDragBegin = onDragBegin
        view.onFramePreview = onFramePreview
        view.onFrameCommit = onFrameCommit
        view.onTransformPreview = onTransformPreview
        view.onTransformCommit = onTransformCommit
        view.onAnnotationCommit = onAnnotationCommit
        view.onAnnotationEndpointsCommit = onAnnotationEndpointsCommit
        view.onZoomCalloutCommit = onZoomCalloutCommit
        view.onMeasureCommit = onMeasureCommit
        view.onMeasureEndpointPreview = onMeasureEndpointPreview
        view.onMeasureEndpointCommit = onMeasureEndpointCommit
        view.onToolChange = onToolChange
        view.onTextEditBegin = onTextEditBegin
        view.onTextCommit = onTextCommit
        view.onTextCancel = onTextCancel
        view.onDeleteLayer = onDeleteLayer
        view.onDropImageURL = onDropImageURL
    }
}

final class CanvasNSView: NSView {
    var onViewSizeChange: ((CGSize) -> Void) = { _ in }
    var onViewportChange: ((Viewport) -> Void) = { _ in }
    var onSelectionChange: ((CGRect?) -> Void) = { _ in }
    var onCropRectChange: ((CGRect) -> Void) = { _ in }
    var onCropCommit: (() -> Void) = {}
    var onSelectLayer: ((UUID?) -> Void) = { _ in }
    var onDragBegin: ((UUID) -> Void) = { _ in }
    var onFramePreview: ((UUID, CGRect) -> Void) = { _, _ in }
    var onFrameCommit: ((UUID, CGRect) -> Void) = { _, _ in }
    var onTransformPreview: ((UUID, LayerTransform) -> Void) = { _, _ in }
    var onTransformCommit: ((UUID, LayerTransform) -> Void) = { _, _ in }
    var onAnnotationCommit: ((CGPoint, CGPoint) -> Void) = { _, _ in }
    var onAnnotationEndpointsCommit: ((UUID, CGPoint, CGPoint) -> Void) = { _, _, _ in }
    var onZoomCalloutCommit: ((CGPoint, CGPoint) -> Void) = { _, _ in }
    var onMeasureCommit: ((CGPoint, CGPoint, MeasureMode) -> Void) = { _, _, _ in }
    var onMeasureEndpointPreview: ((UUID, CGPoint, CGPoint) -> Void) = { _, _, _ in }
    var onMeasureEndpointCommit: ((UUID, CGPoint, CGPoint) -> Void) = { _, _, _ in }
    var onToolChange: ((Tool) -> Void) = { _ in }
    var onTextEditBegin: ((UUID?) -> Void) = { _ in }
    var onTextCommit: ((UUID?, CGPoint, String, CGFloat) -> Void) = { _, _, _, _ in }
    var onTextCancel: (() -> Void) = {}
    var onDeleteLayer: ((UUID) -> Void) = { _ in }
    /// A file (image) dropped onto the canvas — e.g. a history-overlay thumbnail
    /// or a Finder file. Handled here on the canvas NSView (which covers the
    /// document) rather than a SwiftUI `.dropDestination`, which doesn't reliably
    /// receive drops layered over an NSViewRepresentable.
    var onDropImageURL: ((URL) -> Void) = { _ in }

    private let contentLayer = CALayer()
    /// Floats the dragged layer's pre-rendered sprite over the underlay during
    /// drags — positioned in pure Core Animation, no per-move rendering.
    private let previewSpriteLayer = CALayer()
    /// Marching ants: a solid white stroke underneath…
    private let selectionBaseLayer = CAShapeLayer()
    /// …and animated black dashes on top, giving the classic alternating crawl.
    private let selectionAntsLayer = CAShapeLayer()
    /// Accent outline around the selected layer.
    private let layerOutlineLayer = CAShapeLayer()
    /// The eight resize handles on the selected layer's outline.
    private let handlesLayer = CAShapeLayer()
    /// Rotate knob: a circle floated off the layer's top edge plus its stem.
    private let rotateKnobLayer = CAShapeLayer()
    /// Snap guides shown while a move drag is captured by an edge/center.
    private let snapGuideLayer = CAShapeLayer()
    /// Crop mode chrome: dimmed surround (even-odd fill), thirds grid,
    /// border, and handles.
    private let cropDimLayer = CAShapeLayer()
    private let cropGridLayer = CAShapeLayer()
    private let cropBorderLayer = CAShapeLayer()
    private let cropHandlesLayer = CAShapeLayer()
    /// Live preview of an in-progress drag-to-create annotation.
    private let annotationPreviewLayer = CAShapeLayer()
    /// Arrowheads are filled but never stroked (matching the rasterizer), so
    /// they need their own shape layer under the stroked shaft.
    private let annotationPreviewHeadLayer = CAShapeLayer()
    /// A just-created zoom callout flying from its source box to its placed
    /// frame: the magnified sprite, plus the source outline and leader lines
    /// fading in underneath it.
    private let calloutFlightLayer = CALayer()
    private let calloutFlightOutlineLayer = CAShapeLayer()
    private let calloutFlightLeaderLayer = CAShapeLayer()
    /// The pre-commit composite, held on screen for the flight's duration so
    /// the baked-in callout doesn't show at its destination mid-flight.
    private var calloutHoldImage: CGImage?
    /// Invalidates a flight's completion cleanup when a newer flight starts.
    private var calloutFlightGeneration = 0
    private var lastReportedSize: CGSize = .zero
    /// The viewport currently on screen. Gesture handlers mutate from this and
    /// apply locally before notifying, so panning/zooming never waits a runloop
    /// tick for SwiftUI to echo the state back.
    private var viewport: Viewport?
    private var image: CGImage?
    /// Committed document (hit-testing source). Previews never land here.
    private var document: PhotonzDocument?
    /// Committed marquee selection in document coordinates.
    private var selection: CGRect?
    /// Pending crop rect (document coordinates), echoed from EditorState.
    private var cropRect: CGRect?
    /// Crop aspect lock, echoed from EditorState; drags constrain through it.
    private var cropAspect: CropAspect = .free
    /// Crop confinement (canvas, or the target layer's frame), echoed from
    /// EditorState. Nil falls back to the full document.
    private var cropBounds: CGRect?

    /// In-progress crop-rect drag. `startRect` restores on Esc and on
    /// click-without-drag.
    private struct CropDrag {
        enum Kind {
            case resize(ResizeHandle)
            case move
            case define(anchor: CGPoint)
        }
        let kind: Kind
        let startRect: CGRect?
        var lastPoint: CGPoint
    }
    private var cropDrag: CropDrag?
    /// Selected layer (committed state, echoed from EditorState).
    private var selectedLayerID: UUID?
    /// Selected layer's frame in document coordinates (committed state).
    private var selectedLayerFrame: CGRect?
    /// Pre-rendered drag preview from EditorState; arrives async after drag start
    /// and outlives the drag until the post-commit render lands.
    private var dragPreview: DragPreview?
    /// In-progress marquee (document coordinates). While set, it is what the
    /// ants display — same zero-latency-echo pattern as pan/zoom.
    private var marquee: MarqueeDrag?
    /// The active tool, echoed from EditorState. Annotation tools reroute the
    /// pointer from hit-test/marquee into drag-to-create.
    private var tool: Tool = .select
    /// In-progress drag-to-create (document coordinates).
    private var annotationDrag: AnnotationDrag?
    /// Styled content for the active tool, echoed from EditorState; the in-flight
    /// preview strokes with this so it matches the committed rasterization.
    private var annotationContent: AnnotationContent?
    private var measureContent: MeasureContent?
    /// In-flight measure drag (reuses AnnotationDrag for the anchor/current pair).
    private var measureDrag: AnnotationDrag?
    /// In-flight resize of a placed measure by dragging one of its two corners.
    private var measureCornerDrag: MeasureCornerDrag?

    /// Dragging one corner of a placed measure; the opposite corner stays fixed.
    private struct MeasureCornerDrag {
        let layerID: UUID
        let endpoint: AnnotationEndpoint
        let fixed: CGPoint   // the opposite corner, document space
        let original: CGPoint // the dragged corner's pre-drag position (for Esc)
        var current: CGPoint
        /// The measure's endpoints with this drag applied (start, end).
        func endpoints() -> (start: CGPoint, end: CGPoint) {
            endpoint == .start ? (current, fixed) : (fixed, current)
        }
        /// The pre-drag endpoints, for restoring on cancel.
        func originalEndpoints() -> (start: CGPoint, end: CGPoint) {
            endpoint == .start ? (original, fixed) : (fixed, original)
        }
    }
    /// The composite that was on screen when an annotation was committed. The
    /// preview shape stays up until a *different* image arrives, so the new
    /// annotation doesn't flash out while the re-render is in flight.
    private var annotationCommitImage: CGImage?
    /// Current text style, echoed from EditorState; the inline editor restyles
    /// live when the font picker changes it. The string field is ignored.
    private var textContent: TextContent?

    /// In-progress inline text edit.
    private struct TextEditSession {
        /// Nil while placing a new text block; set when re-editing a layer.
        let layerID: UUID?
        /// The text frame's top-left in document coordinates.
        let origin: CGPoint
    }
    private var textSession: TextEditSession?
    /// The session's editor overlay, positioned/scaled to track the viewport.
    private var textEditor: NSTextView?
    /// The zoom `textEditor`'s font was last scaled for.
    private var textEditorZoom: CGFloat = 0
    /// The style `textEditor` was last configured with (string empty), so
    /// font-picker changes mid-edit restyle the draft exactly once.
    private var textEditorContent: TextContent?

    /// In-progress layer move.
    private struct MoveDrag {
        let layerID: UUID
        /// Pointer offset from the frame origin at grab time (doc coords).
        let grabOffset: CGPoint
        let size: CGSize
        let startOrigin: CGPoint
        var snapped: Snapping.Result
        /// Becomes true once the pointer travels past the click tolerance;
        /// a click that never moves selects without committing a move.
        var moved = false
    }
    private var moveDrag: MoveDrag?

    /// In-progress handle resize.
    private struct ResizeDrag {
        let layerID: UUID
        let handle: ResizeHandle
        let startFrame: CGRect
        var frame: CGRect
    }
    private var resizeDrag: ResizeDrag?

    /// True only between a move/resize COMMIT and the post-commit composite
    /// landing — the window in which the sprite must be held at the committed
    /// frame so it doesn't flash. A static click-select sets up a drag preview
    /// (for a possible drag) but must NOT hold the sprite: the sprite is a baked
    /// bitmap CALayer composites in gamma space, which renders semi-transparent
    /// effects (notably shadows) slightly differently than the linear-space CI
    /// composite — so a held sprite makes a selected layer's shadow visibly
    /// darker. Showing the real composite for a static selection avoids that.
    private var holdSpriteUntilRender = false

    /// In-progress rotate (knob) or skew (⌥-corner) drag.
    private struct TransformDragSession {
        enum Kind {
            case rotate(grabAngle: CGFloat)
            case skew(corner: ResizeHandle, grabPoint: CGPoint)
        }
        let layerID: UUID
        let kind: Kind
        let startTransform: LayerTransform
        let center: CGPoint
        let frameSize: CGSize
        var transform: LayerTransform
    }
    private var transformDrag: TransformDragSession?
    /// After a transform commit, the sprite keeps the final delta applied
    /// until the re-rendered composite lands (no flash-back).
    private var transformHold: (layerID: UUID, start: LayerTransform, transform: LayerTransform)?

    /// Maps a document point into the selected layer's untransformed frame
    /// space, so frame-handle hit-testing and resizing agree with where the
    /// (transformed) chrome draws.
    private func handleSpacePoint(_ p: CGPoint, layer: Layer?) -> CGPoint {
        guard let layer, !layer.transform.isIdentity else { return p }
        let center = CGPoint(x: layer.frame.midX, y: layer.frame.midY)
        return p.applying(layer.transform.affineTransform(around: center).inverted())
    }

    /// The resized frame for a handle drag: the standard opposite-anchor resize,
    /// plus — for text — width-only sizing with a re-wrapped height (the top edge
    /// stays put, the block grows downward), plus anchor compensation so the
    /// corner opposite the dragged handle stays fixed in screen space under any
    /// rotation/skew (a plain resize would swing it — the "resize after rotate"
    /// bug).
    private func resizedFrame(for layer: Layer?, start: CGRect, handle: ResizeHandle,
                             pointer p: CGPoint, preserveAspect: Bool) -> CGRect {
        let local = handleSpacePoint(p, layer: layer)
        var frame = Handles.resize(start, dragging: handle, to: local, preserveAspect: preserveAspect)
        if let layer, layer.resizeWidthOnly, case .text(let content) = layer.content {
            let w = max(frame.width, TextRasterizer.minimumTextWidth)
            let measured = TextRasterizer.naturalSize(content, maxWidth: w,
                                                      minWidth: TextRasterizer.minimumTextWidth)
            let minX = handle.movesMinX ? frame.maxX - w : frame.minX
            frame = CGRect(x: minX, y: start.minY, width: w, height: measured.height)
        }
        if let layer {
            frame = Handles.anchoredFrame(start: start, proposed: frame, handle: handle,
                                          transform: layer.transform)
        }
        return frame
    }

    /// The rotate knob's position in document coordinates: floated off the
    /// midpoint of the layer's (transformed) top edge, 18 screen points out.
    private func rotateKnobPoint(for layer: Layer, zoom: CGFloat) -> CGPoint? {
        let corners = layer.transformedCorners
        guard corners.count == 4, zoom > 0 else { return nil }
        let topMid = CGPoint(x: (corners[0].x + corners[1].x) / 2,
                             y: (corners[0].y + corners[1].y) / 2)
        let center = CGPoint(x: layer.frame.midX, y: layer.frame.midY)
        let dx = topMid.x - center.x
        let dy = topMid.y - center.y
        let length = hypot(dx, dy)
        guard length > 0 else { return CGPoint(x: topMid.x, y: topMid.y - 18 / zoom) }
        let offset = 18 / zoom
        return CGPoint(x: topMid.x + dx / length * offset, y: topMid.y + dy / length * offset)
    }

    /// In-progress endpoint drag on a selected line/arrow. The geometry lives
    /// in `AnnotationEndpointDrag` (core, tested); this wraps it with what the
    /// canvas needs for preview styling and Esc-cancel.
    private struct EndpointDragSession {
        let layerID: UUID
        /// The layer's content, for styling the vector preview.
        let content: AnnotationContent
        let originalStart: CGPoint
        let originalEnd: CGPoint
        var drag: AnnotationEndpointDrag
    }
    private var endpointDrag: EndpointDragSession?
    /// After an endpoint commit, the underlay + vector preview stay up until
    /// the re-rendered composite lands — the sprite can't represent the
    /// re-shaped layer, so this replaces the `previewedFrame` hold.
    private var endpointHoldLayerID: UUID?

    // Viewport math is top-left origin; flipping makes view coords match.
    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never

        contentLayer.contentsGravity = .resize
        contentLayer.minificationFilter = .linear
        contentLayer.shadowColor = CGColor(gray: 0, alpha: 1)
        contentLayer.shadowOpacity = 0.45
        contentLayer.shadowRadius = 24
        contentLayer.shadowOffset = .zero
        layer?.addSublayer(contentLayer)

        previewSpriteLayer.contentsGravity = .resize
        previewSpriteLayer.isHidden = true
        layer?.addSublayer(previewSpriteLayer)

        annotationPreviewLayer.isHidden = true
        annotationPreviewLayer.lineCap = .round
        annotationPreviewLayer.lineJoin = .round
        annotationPreviewLayer.fillColor = nil
        annotationPreviewHeadLayer.strokeColor = nil
        annotationPreviewLayer.addSublayer(annotationPreviewHeadLayer)
        layer?.addSublayer(annotationPreviewLayer)

        calloutFlightLeaderLayer.fillColor = nil
        calloutFlightLeaderLayer.lineCap = .round
        calloutFlightOutlineLayer.fillColor = nil
        calloutFlightLayer.contentsGravity = .resize
        calloutFlightLayer.masksToBounds = true
        for flightLayer in [calloutFlightLeaderLayer, calloutFlightOutlineLayer, calloutFlightLayer] {
            flightLayer.isHidden = true
            layer?.addSublayer(flightLayer)
        }

        for shape in [selectionBaseLayer, selectionAntsLayer, layerOutlineLayer, snapGuideLayer, handlesLayer] {
            shape.fillColor = nil
            shape.lineWidth = 1
            shape.isHidden = true
            layer?.addSublayer(shape)
        }
        // Crop chrome stacks above the composite and the selection chrome
        // (which is hidden in crop mode anyway).
        cropDimLayer.fillColor = CGColor(gray: 0, alpha: 0.55)
        cropDimLayer.fillRule = .evenOdd
        cropGridLayer.fillColor = nil
        cropGridLayer.strokeColor = CGColor(gray: 1, alpha: 0.35)
        cropGridLayer.lineWidth = 1
        cropBorderLayer.fillColor = nil
        cropBorderLayer.strokeColor = CGColor(gray: 1, alpha: 1)
        cropBorderLayer.lineWidth = 2
        cropHandlesLayer.fillColor = CGColor(gray: 1, alpha: 1)
        cropHandlesLayer.strokeColor = CGColor(gray: 0, alpha: 0.4)
        cropHandlesLayer.lineWidth = 1
        for cropLayer in [cropDimLayer, cropGridLayer, cropBorderLayer, cropHandlesLayer] {
            cropLayer.isHidden = true
            layer?.addSublayer(cropLayer)
        }

        selectionBaseLayer.strokeColor = CGColor(gray: 1, alpha: 1)
        selectionAntsLayer.strokeColor = CGColor(gray: 0, alpha: 1)
        selectionAntsLayer.lineDashPattern = [4, 4]
        let crawl = CABasicAnimation(keyPath: "lineDashPhase")
        crawl.fromValue = 0
        crawl.toValue = 8
        crawl.duration = 0.4
        crawl.repeatCount = .infinity
        selectionAntsLayer.add(crawl, forKey: "marchingAnts")

        layerOutlineLayer.strokeColor = NSColor.controlAccentColor.cgColor
        layerOutlineLayer.lineWidth = 2
        snapGuideLayer.strokeColor = NSColor.systemYellow.cgColor
        handlesLayer.fillColor = CGColor(gray: 1, alpha: 1)
        handlesLayer.strokeColor = NSColor.controlAccentColor.cgColor
        rotateKnobLayer.fillColor = CGColor(gray: 1, alpha: 1)
        rotateKnobLayer.strokeColor = NSColor.controlAccentColor.cgColor
        rotateKnobLayer.lineWidth = 1
        rotateKnobLayer.isHidden = true
        layer?.addSublayer(rotateKnobLayer)

        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Drag destination (drop an image to add it as a layer)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedURL(sender) != nil ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedURL(sender) != nil ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = droppedURL(sender) else { return false }
        onDropImageURL(url)
        return true
    }

    private func droppedURL(_ sender: NSDraggingInfo) -> URL? {
        sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true])?.first as? URL
    }

    override func layout() {
        super.layout()
        if bounds.size != lastReportedSize {
            lastReportedSize = bounds.size
            onViewSizeChange(bounds.size)
        }
    }

    // MARK: Pointer: layer move or marquee

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let viewport else { return }
        // A click outside the inline text editor commits it; the click is
        // swallowed so committing never doubles as starting something else.
        if textSession != nil {
            commitTextSession()
            return
        }
        window?.makeFirstResponder(self)
        let p = viewport.documentPoint(fromView: convert(event.locationInWindow, from: nil))
        // Double-click the window background — the matte OR the locked base image,
        // i.e. anywhere that isn't an editable layer — performs the standard
        // window zoom. `.hiddenTitleBar` leaves no real title bar to double-click,
        // and on an image that fills the window the matte alone wasn't reachable,
        // so this makes "double-click the bg to maximize" work everywhere. Editable
        // layers (text/annotations) stay double-click-to-edit.
        if event.clickCount == 2, document?.hitTest(p, zoom: viewport.zoom) == nil {
            performWindowTitleBarAction()
            return
        }
        // The text tool places a new block wherever you click.
        if tool == .text {
            beginTextSession(layerID: nil, at: p)
            return
        }
        // Crop mode owns the pointer: handles resize, inside moves, outside
        // draws a fresh rect. Double-click inside commits.
        if tool == .crop {
            if event.clickCount == 2, let rect = cropRect, rect.contains(p) {
                cropDrag = nil
                onCropCommit()
                return
            }
            if let rect = cropRect,
               let handle = Handles.hit(at: p, frame: rect, zoom: viewport.zoom, screenTolerance: 8) {
                cropDrag = CropDrag(kind: .resize(handle), startRect: rect, lastPoint: p)
            } else if let rect = cropRect, rect.contains(p) {
                cropDrag = CropDrag(kind: .move, startRect: rect, lastPoint: p)
            } else {
                cropDrag = CropDrag(kind: .define(anchor: p), startRect: cropRect, lastPoint: p)
            }
            return
        }
        // Drawing tools own the pointer: every drag creates a new annotation
        // (or, for the zoom tool, defines the callout's source box).
        if tool.createsAnnotationByDrag || tool == .zoomCallout {
            annotationDrag = AnnotationDrag(anchor: p)
            refreshAnnotationPreview(constrained: event.modifierFlags.contains(.shift))
            return
        }
        // The measure tool drags two reference points; ⇧ locks to the dominant axis.
        if tool == .measure {
            measureDrag = AnnotationDrag(anchor: p)
            refreshMeasurePreview(constrained: event.modifierFlags.contains(.shift))
            return
        }
        // Double-click on a text layer re-opens it for inline editing. Checked
        // before handles: on a small text layer the handle hit zones cover the
        // whole frame and would eat the double-click.
        if event.clickCount == 2, let hit = document?.hitTest(p, zoom: viewport.zoom),
           case .text = hit.content {
            beginTextSession(layerID: hit.id, at: hit.frame.origin)
            return
        }
        // Handles take priority over moves: they extend past the layer's frame.
        // Lines/arrows expose their endpoints; everything else (that resizes)
        // gets the eight frame handles.
        let selectedLayer = selectedLayerID.flatMap { id in document?.layer(id: id) }
        if let id = selectedLayerID, let layer = selectedLayer, let content = layer.annotation,
           let endpoint = AnnotationEndpoints.hit(at: p, layer: layer, zoom: viewport.zoom),
           let drag = AnnotationEndpointDrag(layer: layer, endpoint: endpoint),
           let start = layer.annotationEndpoint(.start), let end = layer.annotationEndpoint(.end) {
            endpointDrag = EndpointDragSession(layerID: id, content: content,
                                               originalStart: start, originalEnd: end, drag: drag)
            onDragBegin(id)
            refreshEndpointPreview(constrained: event.modifierFlags.contains(.shift))
            refreshOverlays()
            return
        }
        // A placed measure resizes by dragging either of its two corners; the
        // opposite corner stays fixed and the gap/label update live.
        if let id = selectedLayerID, let layer = selectedLayer, layer.measure != nil,
           let endpoint = AnnotationEndpoints.hit(at: p, layer: layer, zoom: viewport.zoom),
           let fixed = layer.measureEndpoint(endpoint == .start ? .end : .start),
           let original = layer.measureEndpoint(endpoint) {
            measureCornerDrag = MeasureCornerDrag(layerID: id, endpoint: endpoint, fixed: fixed,
                                                  original: original, current: p)
            refreshOverlays()
            return
        }
        // Rotate knob, floated off the selected layer's top edge.
        if let id = selectedLayerID, let layer = selectedLayer, !layer.hasEndpointHandles,
           let knob = rotateKnobPoint(for: layer, zoom: viewport.zoom),
           hypot(p.x - knob.x, p.y - knob.y) * viewport.zoom <= 8 {
            let center = CGPoint(x: layer.frame.midX, y: layer.frame.midY)
            transformDrag = TransformDragSession(
                layerID: id, kind: .rotate(grabAngle: TransformDrag.pointerAngle(p, around: center)),
                startTransform: layer.transform, center: center,
                frameSize: layer.frame.size, transform: layer.transform)
            onDragBegin(id)
            refreshOverlays()
            return
        }
        // Frame handles. The pointer maps through the layer's inverse
        // transform so handles on a rotated/skewed layer hit where they draw.
        // ⌥ on a corner skews instead of resizing.
        if let id = selectedLayerID, let frame = selectedLayerFrame,
           selectedLayer?.allowsFrameResize ?? true,
           let handle = Handles.hit(at: handleSpacePoint(p, layer: selectedLayer),
                                    frame: frame, zoom: viewport.zoom) {
            if event.modifierFlags.contains(.option), handle.isCorner, let layer = selectedLayer {
                transformDrag = TransformDragSession(
                    layerID: id, kind: .skew(corner: handle, grabPoint: p),
                    startTransform: layer.transform,
                    center: CGPoint(x: layer.frame.midX, y: layer.frame.midY),
                    frameSize: layer.frame.size, transform: layer.transform)
            } else {
                resizeDrag = ResizeDrag(layerID: id, handle: handle, startFrame: frame, frame: frame)
            }
            onDragBegin(id)
            refreshOverlays()
            return
        }
        if let hit = document?.hitTest(p, zoom: viewport.zoom) {
            onSelectLayer(hit.id)
            onDragBegin(hit.id)
            selectedLayerFrame = hit.frame
            moveDrag = MoveDrag(layerID: hit.id,
                                grabOffset: CGPoint(x: p.x - hit.frame.origin.x,
                                                    y: p.y - hit.frame.origin.y),
                                size: hit.frame.size,
                                startOrigin: hit.frame.origin,
                                snapped: Snapping.Result(origin: hit.frame.origin))
        } else {
            if selectedLayerFrame != nil {
                selectedLayerFrame = nil
                onSelectLayer(nil)
            }
            marquee = MarqueeDrag(anchor: p)
        }
        refreshOverlays()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let viewport else { return }
        let p = viewport.documentPoint(fromView: convert(event.locationInWindow, from: nil))
        if var drag = cropDrag {
            let bounds = cropBounds ?? CGRect(origin: .zero, size: viewport.documentSize)
            switch drag.kind {
            case .resize(let handle):
                guard let start = drag.startRect else { break }
                cropRect = Crop.resize(start, dragging: handle, to: p,
                                       aspect: cropAspect, bounds: bounds)
            case .move:
                if let rect = cropRect {
                    cropRect = Crop.moved(rect, by: CGPoint(x: p.x - drag.lastPoint.x,
                                                            y: p.y - drag.lastPoint.y),
                                          in: bounds)
                }
            case .define(let anchor):
                // An empty drag (a stray click) keeps the existing rect.
                cropRect = Crop.dragRect(anchor: anchor, current: p, aspect: cropAspect,
                                         bounds: bounds) ?? drag.startRect
            }
            drag.lastPoint = p
            cropDrag = drag
            refreshOverlays()
        } else if var drag = annotationDrag {
            drag.update(to: p)
            annotationDrag = drag
            refreshAnnotationPreview(constrained: event.modifierFlags.contains(.shift))
        } else if var drag = measureDrag {
            drag.update(to: p)
            measureDrag = drag
            refreshMeasurePreview(constrained: event.modifierFlags.contains(.shift))
        } else if var corner = measureCornerDrag {
            corner.current = p
            measureCornerDrag = corner
            // Live re-render so the gap value updates as the corner moves.
            let (start, end) = corner.endpoints()
            onMeasureEndpointPreview(corner.layerID, start, end)
            refreshOverlays()
        } else if var session = endpointDrag {
            session.drag.update(to: p)
            endpointDrag = session
            refreshEndpointPreview(constrained: event.modifierFlags.contains(.shift))
            refreshOverlays()
        } else if var session = transformDrag {
            switch session.kind {
            case .rotate(let grabAngle):
                session.transform.rotation = TransformDrag.rotation(
                    from: session.startTransform.rotation, grabAngle: grabAngle,
                    currentAngle: TransformDrag.pointerAngle(p, around: session.center),
                    snapped: event.modifierFlags.contains(.shift))
            case .skew(let corner, let grabPoint):
                session.transform = TransformDrag.skewed(
                    session.startTransform, corner: corner,
                    by: CGPoint(x: p.x - grabPoint.x, y: p.y - grabPoint.y),
                    frameSize: session.frameSize)
            }
            transformDrag = session
            onTransformPreview(session.layerID, session.transform)
            refreshOverlays()
        } else if var drag = resizeDrag {
            let layer = document?.layer(id: drag.layerID)
            drag.frame = resizedFrame(for: layer, start: drag.startFrame, handle: drag.handle,
                                      pointer: p, preserveAspect: event.modifierFlags.contains(.shift))
            resizeDrag = drag
            onFramePreview(drag.layerID, drag.frame)
            refreshOverlays()
        } else if var drag = moveDrag {
            let proposed = CGPoint(x: p.x - drag.grabOffset.x, y: p.y - drag.grabOffset.y)
            if !drag.moved {
                let travel = hypot(proposed.x - drag.startOrigin.x, proposed.y - drag.startOrigin.y)
                drag.moved = travel * viewport.zoom >= 4
            }
            if drag.moved {
                drag.snapped = Snapping.snapFrameOrigin(proposed, size: drag.size,
                                                        canvas: viewport.documentSize,
                                                        zoom: viewport.zoom)
                onFramePreview(drag.layerID, CGRect(origin: drag.snapped.origin, size: drag.size))
            }
            moveDrag = drag
            refreshOverlays()
        } else if var drag = marquee {
            drag.update(to: p)
            marquee = drag
            refreshOverlays(constrainSquare: event.modifierFlags.contains(.shift))
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let viewport else { return }
        if cropDrag != nil {
            cropDrag = nil
            if let rect = cropRect { onCropRectChange(rect) }
            refreshOverlays()
        } else if let drag = annotationDrag {
            annotationDrag = nil
            if drag.isClick(atZoom: viewport.zoom) {
                clearAnnotationPreview()
            } else if tool == .zoomCallout {
                clearAnnotationPreview()
                let end = drag.end(constrained: event.modifierFlags.contains(.shift), shape: .rectangle)
                // Build the same layer EditorState will commit, to drive the
                // flight animation from source box to placed frame.
                if let layer = ZoomCalloutBuilder.layer(from: drag.anchor, to: end,
                                                        canvas: viewport.documentSize) {
                    beginCalloutFlight(for: layer)
                    onZoomCalloutCommit(drag.anchor, end)
                }
            } else {
                // Leave the preview shape up until the re-rendered composite
                // (which includes the new layer) lands — no flash.
                annotationCommitImage = image
                let shape = tool.annotationShape ?? .line
                onAnnotationCommit(drag.anchor,
                                   drag.end(constrained: event.modifierFlags.contains(.shift), shape: shape))
            }
        } else if let drag = measureDrag {
            measureDrag = nil
            if drag.isClick(atZoom: viewport.zoom) {
                clearAnnotationPreview()
            } else {
                // Hold the vector preview until the composite with the new measure
                // lands (the same no-flash trick the annotation path uses).
                annotationCommitImage = image
                let mode = measureModeForCommit(anchor: drag.anchor, current: drag.current,
                                                constrained: event.modifierFlags.contains(.shift))
                onMeasureCommit(drag.anchor, drag.current, mode)
            }
        } else if let corner = measureCornerDrag {
            measureCornerDrag = nil
            let (start, end) = corner.endpoints()
            onMeasureEndpointCommit(corner.layerID, start, end)
            refreshOverlays()
        } else if let session = endpointDrag {
            endpointDrag = nil
            let (start, end) = session.drag.endpoints(constrained: event.modifierFlags.contains(.shift))
            // Same no-flash hold as drag-to-create: the vector preview (over
            // the underlay) stands in until the re-rendered composite lands.
            annotationCommitImage = image
            endpointHoldLayerID = session.layerID
            onAnnotationEndpointsCommit(session.layerID, start, end)
            refreshOverlays()
        } else if let session = transformDrag {
            transformDrag = nil
            if session.transform != session.startTransform {
                // Hold the sprite at the final transform until the post-commit
                // composite lands — otherwise it flashes back.
                transformHold = (session.layerID, session.startTransform, session.transform)
                onTransformCommit(session.layerID, session.transform)
            }
            refreshOverlays()
        } else if let drag = resizeDrag {
            resizeDrag = nil
            if drag.frame != drag.startFrame {
                selectedLayerFrame = drag.frame
                holdSpriteUntilRender = true
                onFrameCommit(drag.layerID, drag.frame)
            }
            refreshOverlays()
        } else if let drag = moveDrag {
            moveDrag = nil
            if drag.moved {
                let frame = CGRect(origin: drag.snapped.origin, size: drag.size)
                selectedLayerFrame = frame
                holdSpriteUntilRender = true
                onFrameCommit(drag.layerID, frame)
            }
            refreshOverlays()
        } else if let drag = marquee {
            marquee = nil
            if drag.isClick(atZoom: viewport.zoom) {
                commitSelection(nil) // a plain click deselects
            } else {
                let square = event.modifierFlags.contains(.shift)
                let rect = drag.selectionRect(constrainSquare: square, in: viewport.documentSize)
                commitSelection(rect.map(Geometry.pixelAligned))
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        if tool == .crop, event.keyCode == 36 || event.keyCode == 76 { // ⏎ / keypad ⏎
            cropDrag = nil
            onCropCommit()
            return
        }
        // Enter / Return edits the selected text layer's content (same as a
        // double-click). Only when idle — while the inline editor is up the
        // NSTextView owns Return (newline).
        if event.keyCode == 36 || event.keyCode == 76,
           moveDrag == nil, resizeDrag == nil, transformDrag == nil,
           let id = selectedLayerID, let layer = document?.layer(id: id), !layer.isLocked,
           case .text = layer.content {
            beginTextSession(layerID: id, at: layer.frame.origin)
            return
        }
        // Delete / forward-delete removes the selected (unlocked) layer.
        if event.keyCode == 51 || event.keyCode == 117,
           let id = selectedLayerID, let layer = document?.layer(id: id), !layer.isLocked {
            onDeleteLayer(id)
            return
        }
        // Arrow keys nudge the selected layer (1pt, ⇧ for 10pt).
        if let delta = Nudge.delta(keyCode: event.keyCode,
                                   large: event.modifierFlags.contains(.shift)),
           moveDrag == nil, resizeDrag == nil, transformDrag == nil,
           let id = selectedLayerID, let layer = document?.layer(id: id), !layer.isLocked {
            let frame = layer.frame.offsetBy(dx: delta.dx, dy: delta.dy)
            selectedLayerFrame = frame
            onFrameCommit(id, frame)
            refreshOverlays()
            return
        }
        if event.keyCode == 53 { // Esc, in priority order: cancel drag → ants → layer → tool
            if let drag = cropDrag {
                cropDrag = nil
                cropRect = drag.startRect
                refreshOverlays()
                return
            }
            if annotationDrag != nil || measureDrag != nil {
                annotationDrag = nil
                measureDrag = nil
                clearAnnotationPreview()
                return
            }
            if let session = endpointDrag {
                endpointDrag = nil
                clearAnnotationPreview()
                // Committing the original endpoints is a History no-op but
                // resets the preview render, like the resize-drag cancel.
                onAnnotationEndpointsCommit(session.layerID, session.originalStart, session.originalEnd)
                refreshOverlays()
                return
            }
            if let corner = measureCornerDrag {
                measureCornerDrag = nil
                let (start, end) = corner.originalEndpoints()
                onMeasureEndpointCommit(corner.layerID, start, end) // History no-op; restores render
                refreshOverlays()
                return
            }
            if let session = transformDrag {
                transformDrag = nil
                // Committing the start transform is a History no-op but resets
                // the preview render.
                onTransformCommit(session.layerID, session.startTransform)
                refreshOverlays()
                return
            }
            if let drag = resizeDrag {
                resizeDrag = nil
                selectedLayerFrame = drag.startFrame
                // Committing the start frame is a History no-op but resets the preview render.
                onFrameCommit(drag.layerID, drag.startFrame)
                refreshOverlays()
                return
            }
            if let drag = moveDrag {
                moveDrag = nil
                let frame = CGRect(origin: drag.startOrigin, size: drag.size)
                selectedLayerFrame = frame
                onFrameCommit(drag.layerID, frame)
                refreshOverlays()
                return
            }
            if marquee != nil || selection != nil {
                marquee = nil
                commitSelection(nil)
                return
            }
            if selectedLayerFrame != nil {
                selectedLayerFrame = nil
                onSelectLayer(nil)
                refreshOverlays()
                return
            }
            if tool != .select {
                onToolChange(.select)
                return
            }
        }
        super.keyDown(with: event)
    }

    private func commitSelection(_ rect: CGRect?) {
        selection = rect
        refreshOverlays()
        onSelectionChange(rect)
    }

    // MARK: Gestures

    /// Two-finger scroll pans. Deltas already arrive in natural-scrolling
    /// orientation, and view coords are flipped, so they apply directly.
    override func scrollWheel(with event: NSEvent) {
        guard let viewport else { return }
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        commit(viewport.panned(by: CGPoint(x: event.scrollingDeltaX * scale,
                                           y: event.scrollingDeltaY * scale)))
    }

    /// Pinch zooms around the cursor.
    override func magnify(with event: NSEvent) {
        guard let viewport else { return }
        let anchor = convert(event.locationInWindow, from: nil)
        commit(viewport.zoomed(to: viewport.zoom * (1 + event.magnification), anchorInView: anchor))
    }

    /// Two-finger double-tap: toggle between fit and 100% at the cursor.
    override func smartMagnify(with event: NSEvent) {
        guard let viewport else { return }
        let fit = Viewport.fit(documentSize: viewport.documentSize, in: viewport.viewSize)
        if abs(viewport.zoom - fit.zoom) < 0.001 {
            let anchor = convert(event.locationInWindow, from: nil)
            commit(viewport.zoomed(to: viewport.zoom >= 1 ? 2 : 1, anchorInView: anchor))
        } else {
            commit(fit)
        }
    }

    /// Mirrors the system "Double-click a window's title bar to" preference for
    /// a double-click on the empty surround (we hide the real title bar).
    private func performWindowTitleBarAction() {
        guard let window else { return }
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize":
            window.performMiniaturize(nil)
        case "None":
            break
        default: // "Maximize" (Zoom) is the modern default.
            window.performZoom(nil)
        }
    }

    private func commit(_ next: Viewport) {
        apply(image: image, viewport: next, document: document, selection: selection,
              cropRect: cropRect, cropAspect: cropAspect, cropBounds: cropBounds,
              selectedLayerID: selectedLayerID, selectedLayerFrame: selectedLayerFrame,
              dragPreview: dragPreview, tool: tool, annotationContent: annotationContent,
              textContent: textContent, measureContent: measureContent)
        onViewportChange(next)
    }

    // MARK: Display

    func apply(image: CGImage?, viewport: Viewport?, document: PhotonzDocument?,
               selection: CGRect?, cropRect: CGRect?, cropAspect: CropAspect,
               cropBounds: CGRect?, selectedLayerID: UUID?, selectedLayerFrame: CGRect?,
               dragPreview: DragPreview?, tool: Tool, annotationContent: AnnotationContent?,
               textContent: TextContent?, measureContent: MeasureContent?) {
        self.annotationContent = annotationContent
        self.textContent = textContent
        self.measureContent = measureContent
        self.cropAspect = cropAspect
        self.cropBounds = cropBounds
        if tool != self.tool {
            self.tool = tool
            // A tool switch mid-drag abandons the draft annotation/endpoint edit.
            annotationDrag = nil
            measureDrag = nil
            measureCornerDrag = nil
            endpointDrag = nil
            cropDrag = nil
            transformDrag = nil
            transformHold = nil
            clearAnnotationPreview()
            // …but a typed text draft is worth keeping: commit it. Deferred a
            // tick because this runs inside a SwiftUI update.
            if textSession != nil {
                DispatchQueue.main.async { [weak self] in self?.commitTextSession() }
            }
            window?.invalidateCursorRects(for: self)
        }
        // Undo while editing can delete the layer behind the editor.
        if let session = textSession, let layerID = session.layerID,
           let document, document.layer(id: layerID) == nil {
            DispatchQueue.main.async { [weak self] in self?.cancelTextSession() }
        }
        // The post-commit composite (a different image) now includes the new
        // annotation layer; the held preview shape can come down.
        if annotationCommitImage != nil, image !== annotationCommitImage {
            clearAnnotationPreview()
        }
        self.image = image
        self.viewport = viewport
        self.document = document
        self.selectedLayerID = selectedLayerID
        self.dragPreview = dragPreview
        // The post-commit composite has landed once the preview is cleared; the
        // sprite hold is no longer needed (and must not linger over a selection).
        if dragPreview == nil { holdSpriteUntilRender = false }
        // The held delta is only needed while the sprite is still floating.
        if let hold = transformHold, dragPreview?.layerID != hold.layerID {
            transformHold = nil
        }
        // While the user is mid-drag the local state is the truth; don't let an
        // unrelated SwiftUI update echo stale committed values over it.
        if marquee == nil {
            self.selection = selection
        }
        if cropDrag == nil {
            self.cropRect = cropRect
        }
        if moveDrag == nil, resizeDrag == nil {
            self.selectedLayerFrame = selectedLayerFrame
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard let image, let viewport else {
            endCalloutFlight()
            contentLayer.isHidden = true
            previewSpriteLayer.isHidden = true
            selectionBaseLayer.isHidden = true
            selectionAntsLayer.isHidden = true
            layerOutlineLayer.isHidden = true
            snapGuideLayer.isHidden = true
            handlesLayer.isHidden = true
            rotateKnobLayer.isHidden = true
            annotationPreviewLayer.isHidden = true
            cropDimLayer.isHidden = true
            cropGridLayer.isHidden = true
            cropBorderLayer.isHidden = true
            cropHandlesLayer.isHidden = true
            if textSession != nil {
                DispatchQueue.main.async { [weak self] in self?.cancelTextSession() }
            }
            return
        }
        contentLayer.isHidden = false
        // refreshPreviewSprite (below) swaps in the underlay + floated sprite
        // while a drag preview is active; the full render replaces both after.
        // A callout flight holds the pre-commit composite so the baked-in
        // callout doesn't show at its destination before the sprite lands.
        contentLayer.contents = calloutHoldImage ?? image
        contentLayer.frame = viewport.documentFrameInView
        contentLayer.shadowPath = CGPath(rect: contentLayer.bounds, transform: nil)
        // Past 2× the user is inspecting pixels — show them squarely instead of smearing.
        contentLayer.magnificationFilter = viewport.zoom >= 2 ? .nearest : .linear

        refreshOverlaysInsideTransaction()
    }

    private func refreshOverlays(constrainSquare: Bool = false) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        refreshOverlaysInsideTransaction(constrainSquare: constrainSquare)
        CATransaction.commit()
    }

    private func refreshOverlaysInsideTransaction(constrainSquare: Bool = false) {
        refreshMarqueeDisplay(constrainSquare: constrainSquare)
        refreshLayerSelectionDisplay()
        refreshCropDisplay()
        refreshPreviewSprite()
        refreshTextEditorDisplay()
    }

    /// Crop chrome: dimmed surround (even-odd: document frame minus the crop
    /// rect), rule-of-thirds grid, white border, eight handles.
    private func refreshCropDisplay() {
        guard tool == .crop, let viewport, let rect = cropRect else {
            cropDimLayer.isHidden = true
            cropGridLayer.isHidden = true
            cropBorderLayer.isHidden = true
            cropHandlesLayer.isHidden = true
            return
        }
        let rectInView = viewRect(forDocRect: rect, in: viewport)

        // For a per-layer crop the dim covers just the layer's frame — only
        // that layer's pixels outside the rect go away.
        let dim = CGMutablePath()
        if let cropBounds {
            dim.addRect(viewRect(forDocRect: cropBounds, in: viewport))
        } else {
            dim.addRect(viewport.documentFrameInView)
        }
        dim.addRect(rectInView)
        cropDimLayer.path = dim

        let grid = CGMutablePath()
        for line in Crop.thirdsLines(in: rect) {
            grid.move(to: viewport.viewPoint(fromDocument: line.from))
            grid.addLine(to: viewport.viewPoint(fromDocument: line.to))
        }
        cropGridLayer.path = grid

        cropBorderLayer.path = CGPath(rect: rectInView, transform: nil)

        let handles = CGMutablePath()
        for handle in ResizeHandle.allCases {
            let p = viewport.viewPoint(fromDocument: Handles.point(for: handle, in: rect))
            handles.addRect(CGRect(x: p.x - 4.5, y: p.y - 4.5, width: 9, height: 9))
        }
        cropHandlesLayer.path = handles

        cropDimLayer.isHidden = false
        cropGridLayer.isHidden = false
        cropBorderLayer.isHidden = false
        cropHandlesLayer.isHidden = false
    }

    /// The frame the drag preview should float at, or nil when the preview
    /// isn't applicable (no preview, or it belongs to another layer).
    private var previewedFrame: CGRect? {
        guard let dragPreview else { return nil }
        // Only float the sprite once a drag is genuinely under way. On mere
        // mouse-DOWN (or before the move threshold) the frame hasn't changed, so
        // showing the sprite would needlessly swap the live composite for the
        // gamma-composited bitmap — which shifts semi-transparent effects like
        // shadows. Keep the real composite until the layer actually moves/resizes.
        if let resizeDrag, resizeDrag.layerID == dragPreview.layerID,
           resizeDrag.frame != resizeDrag.startFrame {
            return resizeDrag.frame
        }
        if let moveDrag, moveDrag.layerID == dragPreview.layerID, moveDrag.moved {
            return CGRect(origin: moveDrag.snapped.origin, size: moveDrag.size)
        }
        // Drag ended but the post-commit render hasn't landed yet: hold the
        // sprite at the committed frame so nothing flashes. Only after a real
        // commit — never for a static selection (see `holdSpriteUntilRender`).
        if moveDrag == nil, resizeDrag == nil, holdSpriteUntilRender,
           selectedLayerID == dragPreview.layerID {
            return selectedLayerFrame
        }
        return nil
    }

    private func refreshPreviewSprite() {
        // Endpoint drags re-shape the layer per move — a stretched sprite
        // can't represent that, so the vector preview draws over the underlay
        // alone (during the drag and through the post-commit hold).
        if let dragPreview, let holdID = endpointDrag?.layerID ?? endpointHoldLayerID,
           holdID == dragPreview.layerID {
            contentLayer.contents = dragPreview.underlay
            previewSpriteLayer.isHidden = true
            return
        }
        guard let viewport, let dragPreview, let frame = previewedFrame else {
            previewSpriteLayer.isHidden = true
            if let image, !contentLayer.isHidden { contentLayer.contents = image }
            return
        }
        contentLayer.contents = dragPreview.underlay
        previewSpriteLayer.contents = dragPreview.sprite
        let padded = frame.insetBy(dx: -dragPreview.padding, dy: -dragPreview.padding)
        let spriteRect = viewRect(forDocRect: padded, in: viewport)
        // Bounds + position instead of frame: a rotate/skew drag floats the
        // sprite with a delta transform (set below), and CALayer.frame is
        // undefined under a non-identity transform.
        previewSpriteLayer.bounds = CGRect(origin: .zero, size: spriteRect.size)
        previewSpriteLayer.position = CGPoint(x: spriteRect.midX, y: spriteRect.midY)
        previewSpriteLayer.setAffineTransform(spriteDeltaTransform(for: dragPreview.layerID))
        switch dragPreview.blendMode {
        case .normal: previewSpriteLayer.compositingFilter = nil
        case .multiply: previewSpriteLayer.compositingFilter = "multiplyBlendMode"
        case .screen: previewSpriteLayer.compositingFilter = "screenBlendMode"
        }
        previewSpriteLayer.isHidden = false
    }

    /// What a rotate/skew drag adds on top of the sprite bitmap (which was
    /// rendered with the start transform baked in): current ∘ start⁻¹, the
    /// linear parts only — CALayer applies it about the sprite's center,
    /// which coincides with the layer's transform center.
    private func spriteDeltaTransform(for layerID: UUID) -> CGAffineTransform {
        let session: (start: LayerTransform, current: LayerTransform)?
        if let transformDrag, transformDrag.layerID == layerID {
            session = (transformDrag.startTransform, transformDrag.transform)
        } else if let transformHold, transformHold.layerID == layerID {
            session = (transformHold.start, transformHold.transform)
        } else {
            session = nil
        }
        guard let session, session.start != session.current else { return .identity }
        return session.start.affineTransform(around: .zero).inverted()
            .concatenating(session.current.affineTransform(around: .zero))
    }

    private func refreshMarqueeDisplay(constrainSquare: Bool) {
        let docRect: CGRect?
        if let viewport, let marquee {
            docRect = marquee.selectionRect(constrainSquare: constrainSquare, in: viewport.documentSize)
        } else {
            docRect = selection
        }
        guard let viewport, let docRect else {
            selectionBaseLayer.isHidden = true
            selectionAntsLayer.isHidden = true
            return
        }
        // Half-point inset so the 1pt stroke lands crisply on pixel boundaries.
        let path = CGPath(rect: viewRect(forDocRect: docRect, in: viewport).insetBy(dx: 0.5, dy: 0.5),
                          transform: nil)
        selectionBaseLayer.path = path
        selectionAntsLayer.path = path
        selectionBaseLayer.isHidden = false
        selectionAntsLayer.isHidden = false
    }

    private func refreshLayerSelectionDisplay() {
        let frame: CGRect?
        if let resizeDrag {
            frame = resizeDrag.frame
        } else if let moveDrag {
            frame = CGRect(origin: moveDrag.snapped.origin, size: moveDrag.size)
        } else {
            frame = selectedLayerFrame
        }
        guard let viewport, let frame else {
            layerOutlineLayer.isHidden = true
            snapGuideLayer.isHidden = true
            handlesLayer.isHidden = true
            rotateKnobLayer.isHidden = true
            return
        }
        let selectedLayer = selectedLayerID.flatMap { id in document?.layer(id: id) }
        let dragInFlight = moveDrag != nil || resizeDrag != nil || transformDrag != nil
            || endpointDrag != nil || endpointHoldLayerID != nil || measureCornerDrag != nil

        if selectedLayer?.hasEndpointHandles == true {
            // A line/arrow is its stroke; a rectangle outline around the
            // padded frame reads as a phantom box. Round endpoint handles
            // replace the whole frame chrome. A measure additionally gets a
            // dotted selection box so it reads as selected and resizable.
            rotateKnobLayer.isHidden = true
            if let layer = selectedLayer, layer.measure != nil {
                let box = CGMutablePath()
                box.addLines(between: [
                    viewport.viewPoint(fromDocument: CGPoint(x: frame.minX, y: frame.minY)),
                    viewport.viewPoint(fromDocument: CGPoint(x: frame.maxX, y: frame.minY)),
                    viewport.viewPoint(fromDocument: CGPoint(x: frame.maxX, y: frame.maxY)),
                    viewport.viewPoint(fromDocument: CGPoint(x: frame.minX, y: frame.maxY)),
                ])
                box.closeSubpath()
                layerOutlineLayer.path = box
                layerOutlineLayer.lineDashPattern = [3, 3]
                layerOutlineLayer.isHidden = false
            } else {
                layerOutlineLayer.isHidden = true
                layerOutlineLayer.lineDashPattern = nil
            }
            if !dragInFlight, let layer = selectedLayer {
                let handles = CGMutablePath()
                for endpoint in AnnotationEndpoint.allCases {
                    guard let dp = layer.editEndpoint(endpoint) else { continue }
                    let p = viewport.viewPoint(fromDocument: dp)
                    handles.addEllipse(in: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
                }
                handlesLayer.path = handles
                handlesLayer.isHidden = false
            } else {
                handlesLayer.isHidden = true
            }
        } else {
            // The outline (and handle placement) follows the layer's
            // transform — the in-flight one during a rotate/skew drag.
            let activeTransform = transformDrag?.transform ?? selectedLayer?.transform ?? .identity
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let docToHandle = activeTransform.isIdentity
                ? CGAffineTransform.identity
                : activeTransform.affineTransform(around: center)
            func chromePoint(_ docPoint: CGPoint) -> CGPoint {
                viewport.viewPoint(fromDocument: docPoint.applying(docToHandle))
            }

            let outline = CGMutablePath()
            outline.addLines(between: [
                chromePoint(CGPoint(x: frame.minX, y: frame.minY)),
                chromePoint(CGPoint(x: frame.maxX, y: frame.minY)),
                chromePoint(CGPoint(x: frame.maxX, y: frame.maxY)),
                chromePoint(CGPoint(x: frame.minX, y: frame.maxY)),
            ])
            outline.closeSubpath()
            layerOutlineLayer.path = outline
            layerOutlineLayer.lineDashPattern = nil
            layerOutlineLayer.isHidden = false

            // Handles: 8pt squares in view space, hidden while a drag is in
            // flight and for layers that don't frame-resize (text).
            if !dragInFlight, selectedLayer?.allowsFrameResize ?? true {
                let handles = CGMutablePath()
                for handle in ResizeHandle.allCases {
                    let p = chromePoint(Handles.point(for: handle, in: frame))
                    handles.addRect(CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
                }
                handlesLayer.path = handles
                handlesLayer.isHidden = false
            } else {
                handlesLayer.isHidden = true
            }

            // Rotate knob with its stem, off the (transformed) top edge.
            if !dragInFlight, let layer = selectedLayer,
               let knob = rotateKnobPoint(for: layer, zoom: viewport.zoom) {
                let knobInView = viewport.viewPoint(fromDocument: knob)
                let topMid = chromePoint(CGPoint(x: frame.midX, y: frame.minY))
                let path = CGMutablePath()
                path.move(to: topMid)
                path.addLine(to: knobInView)
                path.addEllipse(in: CGRect(x: knobInView.x - 5, y: knobInView.y - 5,
                                           width: 10, height: 10))
                rotateKnobLayer.path = path
                rotateKnobLayer.isHidden = false
            } else {
                rotateKnobLayer.isHidden = true
            }
        }

        // Guides span the whole document so the alignment target is obvious.
        let guides = CGMutablePath()
        let docFrame = viewport.documentFrameInView
        if let x = moveDrag?.snapped.guideX {
            let vx = viewport.viewPoint(fromDocument: CGPoint(x: x, y: 0)).x
            guides.move(to: CGPoint(x: vx, y: docFrame.minY))
            guides.addLine(to: CGPoint(x: vx, y: docFrame.maxY))
        }
        if let y = moveDrag?.snapped.guideY {
            let vy = viewport.viewPoint(fromDocument: CGPoint(x: 0, y: y)).y
            guides.move(to: CGPoint(x: docFrame.minX, y: vy))
            guides.addLine(to: CGPoint(x: docFrame.maxX, y: vy))
        }
        snapGuideLayer.path = guides
        snapGuideLayer.isHidden = guides.isEmpty
    }

    // MARK: Annotation drag preview

    override func resetCursorRects() {
        if tool.createsAnnotationByDrag || tool == .crop || tool == .zoomCallout || tool == .measure {
            addCursorRect(bounds, cursor: .crosshair)
        } else if tool == .text {
            addCursorRect(bounds, cursor: .iBeam)
        }
    }

    private func clearAnnotationPreview() {
        annotationCommitImage = nil
        endpointHoldLayerID = nil
        annotationPreviewLayer.isHidden = true
        annotationPreviewLayer.path = nil
        annotationPreviewHeadLayer.path = nil
    }

    /// What the zoom tool's drag box previews with: a rectangle in the
    /// callout's border style, so the box that flies out matches the draft.
    private var calloutDraftContent: AnnotationContent {
        let style = ZoomCalloutBuilder.defaultStyle
        return AnnotationContent(shape: .rectangle, strokeWidth: max(1, style.borderWidth / 2),
                                 colorHex: style.borderColorHex)
    }

    /// In-flight drag-to-create: preview the active tool's styled content.
    private func refreshAnnotationPreview(constrained: Bool) {
        let draft = tool == .zoomCallout ? calloutDraftContent : nil
        guard let drag = annotationDrag,
              let content = annotationContent ?? draft ?? tool.defaultAnnotation else {
            clearAnnotationPreview()
            return
        }
        displayAnnotationPreview(content: content, docStart: drag.anchor,
                                 docEnd: drag.end(constrained: constrained, shape: content.shape))
    }

    /// In-flight endpoint drag: preview the selected layer's content with the
    /// dragged endpoint applied.
    private func refreshEndpointPreview(constrained: Bool) {
        guard let session = endpointDrag else {
            clearAnnotationPreview()
            return
        }
        let (docStart, docEnd) = session.drag.endpoints(constrained: constrained)
        displayAnnotationPreview(content: session.content, docStart: docStart, docEnd: docEnd)
    }

    /// Draws an annotation as vector shapes in view coordinates — faithful to
    /// the rasterizer so the held preview swaps invisibly for the real
    /// composite after commit.
    private func displayAnnotationPreview(content: AnnotationContent,
                                          docStart: CGPoint, docEnd: CGPoint) {
        guard let viewport else {
            clearAnnotationPreview()
            return
        }
        let start = viewport.viewPoint(fromDocument: docStart)
        let end = viewport.viewPoint(fromDocument: docEnd)
        let strokeWidth = content.strokeWidth * viewport.zoom
        let rgba = RGBA(hex: content.colorHex) ?? RGBA(r: 1, g: 0, b: 0)
        let color = CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
        let box = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                         width: abs(end.x - start.x), height: abs(end.y - start.y))

        let path = CGMutablePath()
        let headPath = CGMutablePath()
        var fill: CGColor?
        var stroke: CGColor? = color
        var compositing: Any?
        switch content.shape {
        case .line:
            path.move(to: start)
            path.addLine(to: end)
        case .arrow:
            // Stop the shaft inside the head (doc space → view space) so its cap
            // doesn't poke past the tip, matching the rasterizer.
            let shaftEndDoc = Geometry.arrowShaftEnd(start: docStart, end: docEnd,
                                                     strokeWidth: content.strokeWidth,
                                                     scale: content.arrowheadScale)
            path.move(to: start)
            path.addLine(to: viewport.viewPoint(fromDocument: shaftEndDoc))
            // Head geometry in document space (its minimum size is in doc
            // points), then mapped to view coords.
            let head = Geometry.arrowhead(start: docStart, end: docEnd,
                                          strokeWidth: content.strokeWidth,
                                          scale: content.arrowheadScale)
            headPath.addLines(between: head.map { viewport.viewPoint(fromDocument: $0) })
            headPath.closeSubpath()
        case .rectangle, .ellipse:
            let inset = box.insetBy(dx: strokeWidth / 2, dy: strokeWidth / 2)
            if inset.width > 0, inset.height > 0 {
                if content.shape == .rectangle {
                    path.addRect(inset)
                } else {
                    path.addEllipse(in: inset)
                }
            }
        case .highlight:
            path.addRect(box)
            fill = color
            stroke = nil
            compositing = "multiplyBlendMode"
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        annotationPreviewLayer.path = path
        annotationPreviewLayer.strokeColor = stroke
        annotationPreviewLayer.fillColor = fill
        annotationPreviewLayer.lineWidth = strokeWidth
        annotationPreviewLayer.compositingFilter = compositing
        annotationPreviewHeadLayer.path = headPath
        annotationPreviewHeadLayer.fillColor = color
        annotationPreviewLayer.isHidden = false
        CATransaction.commit()
    }

    /// The mode a committed measure gets. A bracket measures its dominant axis
    /// (⇧ flips which axis is the gap). A straight line is free unless ⇧ locks it
    /// to the dominant axis.
    private func measureModeForCommit(anchor: CGPoint, current: CGPoint, constrained: Bool) -> MeasureMode {
        let style = measureContent ?? MeasureContent()
        if style.form == .bracket {
            let axis = MeasureContent.bracketAxis(start: anchor, end: current)
            guard constrained else { return axis }
            return axis == .vertical ? .horizontal : .vertical
        }
        guard constrained else { return .free }
        return abs(current.x - anchor.x) >= abs(current.y - anchor.y) ? .horizontal : .vertical
    }

    /// In-flight measure drag: preview the strokes (line+witness, or the bracket
    /// path). The label plate is added on commit. Reuses the annotation preview
    /// shape layer.
    private func refreshMeasurePreview(constrained: Bool) {
        guard let drag = measureDrag, let viewport else {
            clearAnnotationPreview()
            return
        }
        var style = measureContent ?? MeasureContent()
        let mode = measureModeForCommit(anchor: drag.anchor, current: drag.current, constrained: constrained)
        let path = CGMutablePath()
        if style.form == .bracket {
            style.mode = mode
            style.start = drag.anchor
            style.end = drag.current
            let pts = style.bracketGeometry().path.map { viewport.viewPoint(fromDocument: $0) }
            if let first = pts.first {
                path.move(to: first)
                for p in pts.dropFirst() { path.addLine(to: p) }
            }
        } else {
            let geo = MeasureContent.geometry(mode: mode, start: drag.anchor, end: drag.current)
            func add(_ seg: MeasureSegment) {
                path.move(to: viewport.viewPoint(fromDocument: seg.a))
                path.addLine(to: viewport.viewPoint(fromDocument: seg.b))
            }
            add(geo.dimension)
            geo.extensions.forEach(add)
        }
        let rgba = RGBA(hex: style.colorHex) ?? RGBA(r: 1, g: 0.23, b: 0.19)
        let color = CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        annotationPreviewLayer.path = path
        annotationPreviewLayer.strokeColor = color
        annotationPreviewLayer.fillColor = nil
        annotationPreviewLayer.lineWidth = max(1, style.strokeWidth * viewport.zoom)
        annotationPreviewLayer.compositingFilter = nil
        annotationPreviewHeadLayer.path = nil
        annotationPreviewLayer.isHidden = false
        CATransaction.commit()
    }

    // MARK: Zoom-callout creation flight

    /// Animates a just-committed callout from its source box to its placed
    /// frame: the sprite is the on-screen composite cropped to the source
    /// region (the pixels the callout magnifies), growing into the styled box
    /// while the source outline and leader lines fade in underneath. The
    /// pre-commit composite holds on screen for the duration; the baked render
    /// (already landed by then) is revealed when the flight ends.
    private func beginCalloutFlight(for calloutLayer: Layer) {
        guard let viewport, let image, let callout = calloutLayer.zoomCallout,
              viewport.documentSize.width > 0, viewport.documentSize.height > 0 else { return }
        let scaleX = CGFloat(image.width) / viewport.documentSize.width
        let scaleY = CGFloat(image.height) / viewport.documentSize.height
        let cropRect = CGRect(x: callout.sourceRect.minX * scaleX,
                              y: callout.sourceRect.minY * scaleY,
                              width: callout.sourceRect.width * scaleX,
                              height: callout.sourceRect.height * scaleY)
        guard let sprite = image.cropping(to: cropRect) else { return }

        calloutHoldImage = image
        calloutFlightGeneration += 1
        let generation = calloutFlightGeneration

        let zoom = viewport.zoom
        let style = calloutLayer.style
        let magnification = max(callout.magnification, 0.01)
        let startFrame = viewRect(forDocRect: callout.sourceRect, in: viewport)
        let endFrame = viewRect(forDocRect: calloutLayer.frame, in: viewport)
        let rgba = RGBA(hex: style.borderColorHex) ?? RGBA(r: 1, g: 0, b: 0)
        let borderColor = CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)

        // Chrome that fades in: source outline + leader lines, matching what
        // the renderer bakes (ZoomCalloutOverlayRasterizer's styling).
        let sourceRadius = (style.cornerRadius / magnification) * zoom
        let outlinePath = CGPath(roundedRect: startFrame,
                                 cornerWidth: sourceRadius, cornerHeight: sourceRadius,
                                 transform: nil)
        let leaderPath = CGMutablePath()
        for line in Geometry.leaderLines(source: callout.sourceRect, callout: calloutLayer.frame) {
            leaderPath.move(to: viewport.viewPoint(fromDocument: line.from))
            leaderPath.addLine(to: viewport.viewPoint(fromDocument: line.to))
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        calloutFlightLayer.contents = sprite
        calloutFlightLayer.frame = startFrame
        calloutFlightLayer.borderColor = borderColor
        calloutFlightLayer.borderWidth = style.borderWidth * zoom
        calloutFlightLayer.cornerRadius = sourceRadius
        calloutFlightLayer.isHidden = false
        calloutFlightOutlineLayer.path = outlinePath
        calloutFlightOutlineLayer.strokeColor = borderColor
        calloutFlightOutlineLayer.lineWidth = style.borderWidth * zoom
        calloutFlightOutlineLayer.opacity = 0
        calloutFlightOutlineLayer.isHidden = false
        calloutFlightLeaderLayer.path = leaderPath
        calloutFlightLeaderLayer.strokeColor = borderColor.copy(alpha: 0.6 * borderColor.alpha)
        calloutFlightLeaderLayer.lineWidth = style.borderWidth * zoom
        calloutFlightLeaderLayer.opacity = 0
        calloutFlightLeaderLayer.isHidden = false
        CATransaction.commit()

        // The sprite springs into place (slight overshoot reads as the box
        // "landing"); the chrome fades in on a plain ease-out underneath.
        let startBounds = CGRect(origin: .zero, size: startFrame.size)
        let endBounds = CGRect(origin: .zero, size: endFrame.size)
        func spring(_ keyPath: String, from: Any?, to: Any?) -> CASpringAnimation {
            let animation = CASpringAnimation(perceptualDuration: 0.45, bounce: 0.25)
            animation.keyPath = keyPath
            animation.fromValue = from
            animation.toValue = to
            return animation
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.calloutFlightGeneration == generation else { return }
            self.endCalloutFlight()
        }
        calloutFlightLayer.add(spring("position",
                                      from: NSValue(point: CGPoint(x: startFrame.midX, y: startFrame.midY)),
                                      to: NSValue(point: CGPoint(x: endFrame.midX, y: endFrame.midY))),
                               forKey: "position")
        calloutFlightLayer.add(spring("bounds",
                                      from: NSValue(rect: startBounds),
                                      to: NSValue(rect: endBounds)),
                               forKey: "bounds")
        calloutFlightLayer.add(spring("cornerRadius",
                                      from: sourceRadius,
                                      to: style.cornerRadius * zoom),
                               forKey: "cornerRadius")
        func fadeIn() -> CABasicAnimation {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.35
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            return fade
        }
        calloutFlightOutlineLayer.add(fadeIn(), forKey: "opacity")
        calloutFlightLeaderLayer.add(fadeIn(), forKey: "opacity")
        CATransaction.setDisableActions(true)
        calloutFlightLayer.position = CGPoint(x: endFrame.midX, y: endFrame.midY)
        calloutFlightLayer.bounds = endBounds
        calloutFlightLayer.cornerRadius = style.cornerRadius * zoom
        calloutFlightOutlineLayer.opacity = 1
        calloutFlightLeaderLayer.opacity = 1
        CATransaction.commit()
    }

    /// Tears the flight down and reveals the latest composite (which has the
    /// callout baked in at its destination).
    private func endCalloutFlight() {
        guard calloutHoldImage != nil || !calloutFlightLayer.isHidden else { return }
        calloutHoldImage = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for flightLayer in [calloutFlightLayer, calloutFlightOutlineLayer, calloutFlightLeaderLayer] {
            flightLayer.isHidden = true
            flightLayer.removeAllAnimations()
        }
        calloutFlightLayer.contents = nil
        contentLayer.contents = image
        CATransaction.commit()
    }

    // MARK: Inline text editing

    /// Opens the inline editor at `origin` (document coords). For a re-edit,
    /// the editor takes over the layer's string and style; EditorState hides the
    /// layer underneath via `onTextEditBegin`.
    private func beginTextSession(layerID: UUID?, at origin: CGPoint) {
        guard textSession == nil else { return }
        var style = textContent ?? TextContent(string: "")
        var string = ""
        if let layerID, let layer = document?.layer(id: layerID),
           case .text(let existing) = layer.content {
            string = existing.string
            style = existing
            style.string = ""
            // The editor replaces the selection chrome.
            selectedLayerFrame = nil
            onSelectLayer(nil)
        }
        textSession = TextEditSession(layerID: layerID, origin: origin)

        let editor = InlineTextView()
        editor.onCommit = { [weak self] in self?.commitTextSession() }
        editor.isRichText = false
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isVerticallyResizable = false
        editor.isHorizontallyResizable = false
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        // The container wraps at an explicit cap (layoutTextEditor) while the
        // editor frame hugs the typed text, so the box grows with content instead
        // of spanning to the canvas edge.
        editor.textContainer?.widthTracksTextView = false
        editor.wantsLayer = true
        editor.layer?.borderColor = NSColor.controlAccentColor.cgColor
        editor.layer?.borderWidth = 1
        editor.layer?.cornerRadius = 2
        editor.delegate = self
        editor.string = string
        addSubview(editor)
        textEditor = editor
        textEditorZoom = 0 // force the style pass below to apply
        styleTextEditor(with: style)
        window?.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: string.utf16.count, length: 0))
        onTextEditBegin(layerID)
        refreshOverlays()
    }

    /// Applies font/color to the editor, scaled to the current zoom so the
    /// draft is the same apparent size as the rasterized layer will be.
    /// `content.string` is ignored.
    private func styleTextEditor(with content: TextContent) {
        guard let editor = textEditor, let viewport else { return }
        var stored = content
        stored.string = ""
        textEditorContent = stored
        textEditorZoom = viewport.zoom

        var scaled = stored
        scaled.fontSize = content.fontSize * viewport.zoom
        // The rasterizer picks the face (family + weight); reuse it via its
        // PostScript name so the draft and the final render match.
        let ctFont = TextRasterizer.font(for: scaled)
        let font = NSFont(name: CTFontCopyPostScriptName(ctFont) as String, size: scaled.fontSize)
            ?? NSFont.systemFont(ofSize: scaled.fontSize)
        let rgba = RGBA(hex: content.colorHex) ?? RGBA(r: 1, g: 1, b: 1)
        let color = NSColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
        editor.font = font
        editor.textColor = color
        editor.insertionPointColor = color
        editor.typingAttributes = [.font: font, .foregroundColor: color]
        if let storage = editor.textStorage, storage.length > 0 {
            storage.addAttributes([.font: font, .foregroundColor: color],
                                  range: NSRange(location: 0, length: storage.length))
        }
        layoutTextEditor()
    }

    /// The wrap cap (document points) for a text block placed at `origin`: the
    /// box wraps at 60% of the canvas, but never past the right edge and never
    /// below the minimum width. The committed frame re-measures with the same cap.
    private func textWrapWidth(origin: CGPoint) -> CGFloat {
        guard let viewport else { return TextRasterizer.minimumTextWidth }
        let toEdge = viewport.documentSize.width - origin.x
        let cap = viewport.documentSize.width * 0.6
        return max(min(toEdge, cap), TextRasterizer.minimumTextWidth)
    }

    /// Positions the editor over the session origin and sizes it: the box wraps
    /// at `textWrapWidth` but its frame HUGS the laid-out text (floored at the
    /// minimum width), so it grows with what you type instead of spanning to the
    /// canvas edge. Height hugs the laid-out text.
    private func layoutTextEditor() {
        guard let editor = textEditor, let viewport, let session = textSession else { return }
        let topLeft = viewport.viewPoint(fromDocument: session.origin)
        let capView = textWrapWidth(origin: session.origin) * viewport.zoom
        let minView = TextRasterizer.minimumTextWidth * viewport.zoom
        var contentWidth = minView
        var height = (editor.font?.pointSize ?? 20) * 1.4
        if let container = editor.textContainer, let layoutManager = editor.layoutManager {
            container.containerSize = NSSize(width: capView, height: .greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container)
            // Hug the longest laid-out line (+ caret slack), floored at the
            // minimum and capped at the wrap width.
            contentWidth = min(capView, max(minView, ceil(used.width) + 3))
            height = max(height, used.height + 2)
        }
        editor.frame = CGRect(x: topLeft.x, y: topLeft.y, width: contentWidth, height: ceil(height))
    }

    /// Keeps the editor glued to the document while panning/zooming, and
    /// restyles it when the font picker changes the style mid-edit.
    private func refreshTextEditorDisplay() {
        guard textSession != nil, let viewport else { return }
        if let content = textContent, content != textEditorContent || viewport.zoom != textEditorZoom {
            styleTextEditor(with: content)
        } else {
            layoutTextEditor()
        }
    }

    private func commitTextSession() {
        guard let session = textSession, let editor = textEditor else { return }
        let string = editor.string
        // Same wrap cap the live editor used, so layout doesn't shift on commit.
        let maxWidth = textWrapWidth(origin: session.origin)
        teardownTextSession()
        onTextCommit(session.layerID, session.origin, string, maxWidth)
    }

    private func cancelTextSession() {
        guard textSession != nil else { return }
        teardownTextSession()
        onTextCancel()
    }

    private func teardownTextSession() {
        textSession = nil
        textEditorContent = nil
        textEditorZoom = 0
        guard let editor = textEditor else { return }
        textEditor = nil
        if let responder = window?.firstResponder as? NSView, responder.isDescendant(of: editor) {
            window?.makeFirstResponder(self)
        }
        editor.removeFromSuperview()
    }

    private func viewRect(forDocRect r: CGRect, in viewport: Viewport) -> CGRect {
        let topLeft = viewport.viewPoint(fromDocument: r.origin)
        return CGRect(x: topLeft.x, y: topLeft.y,
                      width: r.width * viewport.zoom, height: r.height * viewport.zoom)
    }
}

extension CanvasNSView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        layoutTextEditor()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // Esc abandons the draft (a re-edited layer reappears unchanged).
        // NSTextView routes Esc to completion in some states, so catch both.
        if commandSelector == #selector(NSResponder.cancelOperation(_:))
            || commandSelector == #selector(NSTextView.complete(_:)) {
            cancelTextSession()
            return true
        }
        return false
    }
}

/// The inline text editor. A plain `NSTextView` treats Return as a newline; this
/// subclass commits the edit on **⌘Return** (and keypad ⌘Enter) via `onCommit`,
/// leaving plain Return to insert a line break.
private final class InlineTextView: NSTextView {
    var onCommit: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 36 || event.keyCode == 76), event.modifierFlags.contains(.command) {
            onCommit()
            return
        }
        super.keyDown(with: event)
    }
}
