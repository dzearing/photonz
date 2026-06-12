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
    let onViewSizeChange: (CGSize) -> Void
    let onViewportChange: (Viewport) -> Void
    let onSelectionChange: (CGRect?) -> Void
    let onSelectLayer: (UUID?) -> Void
    let onDragBegin: (UUID) -> Void
    let onFramePreview: (UUID, CGRect) -> Void
    let onFrameCommit: (UUID, CGRect) -> Void
    let onAnnotationCommit: (CGPoint, CGPoint) -> Void
    let onAnnotationEndpointsCommit: (UUID, CGPoint, CGPoint) -> Void
    let onToolChange: (Tool) -> Void
    let onTextEditBegin: (UUID?) -> Void
    let onTextCommit: (UUID?, CGPoint, String, CGFloat) -> Void
    let onTextCancel: () -> Void

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView()
        update(view)
        return view
    }

    func updateNSView(_ view: CanvasNSView, context: Context) {
        update(view)
        view.apply(image: image, viewport: viewport, document: document,
                   selection: selection, selectedLayerID: selectedLayerID,
                   selectedLayerFrame: selectedLayerFrame, dragPreview: dragPreview,
                   tool: tool, annotationContent: annotationContent, textContent: textContent)
    }

    private func update(_ view: CanvasNSView) {
        view.onViewSizeChange = onViewSizeChange
        view.onViewportChange = onViewportChange
        view.onSelectionChange = onSelectionChange
        view.onSelectLayer = onSelectLayer
        view.onDragBegin = onDragBegin
        view.onFramePreview = onFramePreview
        view.onFrameCommit = onFrameCommit
        view.onAnnotationCommit = onAnnotationCommit
        view.onAnnotationEndpointsCommit = onAnnotationEndpointsCommit
        view.onToolChange = onToolChange
        view.onTextEditBegin = onTextEditBegin
        view.onTextCommit = onTextCommit
        view.onTextCancel = onTextCancel
    }
}

final class CanvasNSView: NSView {
    var onViewSizeChange: ((CGSize) -> Void) = { _ in }
    var onViewportChange: ((Viewport) -> Void) = { _ in }
    var onSelectionChange: ((CGRect?) -> Void) = { _ in }
    var onSelectLayer: ((UUID?) -> Void) = { _ in }
    var onDragBegin: ((UUID) -> Void) = { _ in }
    var onFramePreview: ((UUID, CGRect) -> Void) = { _, _ in }
    var onFrameCommit: ((UUID, CGRect) -> Void) = { _, _ in }
    var onAnnotationCommit: ((CGPoint, CGPoint) -> Void) = { _, _ in }
    var onAnnotationEndpointsCommit: ((UUID, CGPoint, CGPoint) -> Void) = { _, _, _ in }
    var onToolChange: ((Tool) -> Void) = { _ in }
    var onTextEditBegin: ((UUID?) -> Void) = { _ in }
    var onTextCommit: ((UUID?, CGPoint, String, CGFloat) -> Void) = { _, _, _, _ in }
    var onTextCancel: (() -> Void) = {}

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
    /// Snap guides shown while a move drag is captured by an edge/center.
    private let snapGuideLayer = CAShapeLayer()
    /// Live preview of an in-progress drag-to-create annotation.
    private let annotationPreviewLayer = CAShapeLayer()
    /// Arrowheads are filled but never stroked (matching the rasterizer), so
    /// they need their own shape layer under the stroked shaft.
    private let annotationPreviewHeadLayer = CAShapeLayer()
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
    /// Selected layer (committed state, echoed from AppState).
    private var selectedLayerID: UUID?
    /// Selected layer's frame in document coordinates (committed state).
    private var selectedLayerFrame: CGRect?
    /// Pre-rendered drag preview from AppState; arrives async after drag start
    /// and outlives the drag until the post-commit render lands.
    private var dragPreview: DragPreview?
    /// In-progress marquee (document coordinates). While set, it is what the
    /// ants display — same zero-latency-echo pattern as pan/zoom.
    private var marquee: MarqueeDrag?
    /// The active tool, echoed from AppState. Annotation tools reroute the
    /// pointer from hit-test/marquee into drag-to-create.
    private var tool: Tool = .select
    /// In-progress drag-to-create (document coordinates).
    private var annotationDrag: AnnotationDrag?
    /// Styled content for the active tool, echoed from AppState; the in-flight
    /// preview strokes with this so it matches the committed rasterization.
    private var annotationContent: AnnotationContent?
    /// The composite that was on screen when an annotation was committed. The
    /// preview shape stays up until a *different* image arrives, so the new
    /// annotation doesn't flash out while the re-render is in flight.
    private var annotationCommitImage: CGImage?
    /// Current text style, echoed from AppState; the inline editor restyles
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

        for shape in [selectionBaseLayer, selectionAntsLayer, layerOutlineLayer, snapGuideLayer, handlesLayer] {
            shape.fillColor = nil
            shape.lineWidth = 1
            shape.isHidden = true
            layer?.addSublayer(shape)
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

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
        // The text tool places a new block wherever you click.
        if tool == .text {
            beginTextSession(layerID: nil, at: p)
            return
        }
        // Drawing tools own the pointer: every drag creates a new annotation.
        if tool.createsAnnotationByDrag {
            annotationDrag = AnnotationDrag(anchor: p)
            refreshAnnotationPreview(constrained: event.modifierFlags.contains(.shift))
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
        if let id = selectedLayerID, let frame = selectedLayerFrame,
           selectedLayer?.allowsFrameResize ?? true,
           let handle = Handles.hit(at: p, frame: frame, zoom: viewport.zoom) {
            resizeDrag = ResizeDrag(layerID: id, handle: handle, startFrame: frame, frame: frame)
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
        if var drag = annotationDrag {
            drag.update(to: p)
            annotationDrag = drag
            refreshAnnotationPreview(constrained: event.modifierFlags.contains(.shift))
        } else if var session = endpointDrag {
            session.drag.update(to: p)
            endpointDrag = session
            refreshEndpointPreview(constrained: event.modifierFlags.contains(.shift))
            refreshOverlays()
        } else if var drag = resizeDrag {
            drag.frame = Handles.resize(drag.startFrame, dragging: drag.handle, to: p,
                                        preserveAspect: event.modifierFlags.contains(.shift))
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
        if let drag = annotationDrag {
            annotationDrag = nil
            if drag.isClick(atZoom: viewport.zoom) {
                clearAnnotationPreview()
            } else {
                // Leave the preview shape up until the re-rendered composite
                // (which includes the new layer) lands — no flash.
                annotationCommitImage = image
                let shape = tool.annotationShape ?? .line
                onAnnotationCommit(drag.anchor,
                                   drag.end(constrained: event.modifierFlags.contains(.shift), shape: shape))
            }
        } else if let session = endpointDrag {
            endpointDrag = nil
            let (start, end) = session.drag.endpoints(constrained: event.modifierFlags.contains(.shift))
            // Same no-flash hold as drag-to-create: the vector preview (over
            // the underlay) stands in until the re-rendered composite lands.
            annotationCommitImage = image
            endpointHoldLayerID = session.layerID
            onAnnotationEndpointsCommit(session.layerID, start, end)
            refreshOverlays()
        } else if let drag = resizeDrag {
            resizeDrag = nil
            if drag.frame != drag.startFrame {
                selectedLayerFrame = drag.frame
                onFrameCommit(drag.layerID, drag.frame)
            }
            refreshOverlays()
        } else if let drag = moveDrag {
            moveDrag = nil
            if drag.moved {
                let frame = CGRect(origin: drag.snapped.origin, size: drag.size)
                selectedLayerFrame = frame
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
        if event.keyCode == 53 { // Esc, in priority order: cancel drag → ants → layer → tool
            if annotationDrag != nil {
                annotationDrag = nil
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

    private func commit(_ next: Viewport) {
        apply(image: image, viewport: next, document: document, selection: selection,
              selectedLayerID: selectedLayerID, selectedLayerFrame: selectedLayerFrame,
              dragPreview: dragPreview, tool: tool, annotationContent: annotationContent,
              textContent: textContent)
        onViewportChange(next)
    }

    // MARK: Display

    func apply(image: CGImage?, viewport: Viewport?, document: PhotonzDocument?,
               selection: CGRect?, selectedLayerID: UUID?, selectedLayerFrame: CGRect?,
               dragPreview: DragPreview?, tool: Tool, annotationContent: AnnotationContent?,
               textContent: TextContent?) {
        self.annotationContent = annotationContent
        self.textContent = textContent
        if tool != self.tool {
            self.tool = tool
            // A tool switch mid-drag abandons the draft annotation/endpoint edit.
            annotationDrag = nil
            endpointDrag = nil
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
        // While the user is mid-drag the local state is the truth; don't let an
        // unrelated SwiftUI update echo stale committed values over it.
        if marquee == nil {
            self.selection = selection
        }
        if moveDrag == nil, resizeDrag == nil {
            self.selectedLayerFrame = selectedLayerFrame
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard let image, let viewport else {
            contentLayer.isHidden = true
            previewSpriteLayer.isHidden = true
            selectionBaseLayer.isHidden = true
            selectionAntsLayer.isHidden = true
            layerOutlineLayer.isHidden = true
            snapGuideLayer.isHidden = true
            handlesLayer.isHidden = true
            annotationPreviewLayer.isHidden = true
            if textSession != nil {
                DispatchQueue.main.async { [weak self] in self?.cancelTextSession() }
            }
            return
        }
        contentLayer.isHidden = false
        // refreshPreviewSprite (below) swaps in the underlay + floated sprite
        // while a drag preview is active; the full render replaces both after.
        contentLayer.contents = image
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
        refreshPreviewSprite()
        refreshTextEditorDisplay()
    }

    /// The frame the drag preview should float at, or nil when the preview
    /// isn't applicable (no preview, or it belongs to another layer).
    private var previewedFrame: CGRect? {
        guard let dragPreview else { return nil }
        if let resizeDrag, resizeDrag.layerID == dragPreview.layerID { return resizeDrag.frame }
        if let moveDrag, moveDrag.layerID == dragPreview.layerID {
            return CGRect(origin: moveDrag.snapped.origin, size: moveDrag.size)
        }
        // Drag ended but the post-commit render hasn't landed yet: hold the
        // sprite at the committed frame so nothing flashes.
        if moveDrag == nil, resizeDrag == nil, selectedLayerID == dragPreview.layerID {
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
        previewSpriteLayer.frame = viewRect(forDocRect: padded, in: viewport)
        switch dragPreview.blendMode {
        case .normal: previewSpriteLayer.compositingFilter = nil
        case .multiply: previewSpriteLayer.compositingFilter = "multiplyBlendMode"
        case .screen: previewSpriteLayer.compositingFilter = "screenBlendMode"
        }
        previewSpriteLayer.isHidden = false
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
            return
        }
        let selectedLayer = selectedLayerID.flatMap { id in document?.layer(id: id) }
        let dragInFlight = moveDrag != nil || resizeDrag != nil
            || endpointDrag != nil || endpointHoldLayerID != nil

        if selectedLayer?.hasEndpointHandles == true {
            // A line/arrow is its stroke; a rectangle outline around the
            // padded frame reads as a phantom box. Round endpoint handles
            // replace the whole frame chrome.
            layerOutlineLayer.isHidden = true
            if !dragInFlight, let layer = selectedLayer {
                let handles = CGMutablePath()
                for endpoint in AnnotationEndpoint.allCases {
                    guard let dp = layer.annotationEndpoint(endpoint) else { continue }
                    let p = viewport.viewPoint(fromDocument: dp)
                    handles.addEllipse(in: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
                }
                handlesLayer.path = handles
                handlesLayer.isHidden = false
            } else {
                handlesLayer.isHidden = true
            }
        } else {
            let outlineRect = viewRect(forDocRect: frame, in: viewport)
            layerOutlineLayer.path = CGPath(rect: outlineRect, transform: nil)
            layerOutlineLayer.isHidden = false

            // Handles: 8pt squares in view space, hidden while a drag is in
            // flight and for layers that don't frame-resize (text).
            if !dragInFlight, selectedLayer?.allowsFrameResize ?? true {
                let handles = CGMutablePath()
                for handle in ResizeHandle.allCases {
                    let p = viewport.viewPoint(fromDocument: Handles.point(for: handle, in: frame))
                    handles.addRect(CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
                }
                handlesLayer.path = handles
                handlesLayer.isHidden = false
            } else {
                handlesLayer.isHidden = true
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
        if tool.createsAnnotationByDrag {
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

    /// In-flight drag-to-create: preview the active tool's styled content.
    private func refreshAnnotationPreview(constrained: Bool) {
        guard let drag = annotationDrag,
              let content = annotationContent ?? tool.defaultAnnotation else {
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
            path.move(to: start)
            path.addLine(to: end)
            // Head geometry in document space (its minimum size is in doc
            // points), then mapped to view coords.
            let head = Geometry.arrowhead(start: docStart, end: docEnd,
                                          strokeWidth: content.strokeWidth)
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

    // MARK: Inline text editing

    /// Opens the inline editor at `origin` (document coords). For a re-edit,
    /// the editor takes over the layer's string and style; AppState hides the
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

        let editor = NSTextView()
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
        editor.textContainer?.widthTracksTextView = true
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

    /// Positions the editor over the session origin and sizes it: wrap width
    /// runs to the canvas's right edge (commit re-measures with the same
    /// width), height hugs the laid-out text.
    private func layoutTextEditor() {
        guard let editor = textEditor, let viewport, let session = textSession else { return }
        let topLeft = viewport.viewPoint(fromDocument: session.origin)
        let docWidth = max(viewport.documentSize.width - session.origin.x, 20)
        let width = docWidth * viewport.zoom
        var height = (editor.font?.pointSize ?? 20) * 1.4
        if let container = editor.textContainer, let layoutManager = editor.layoutManager {
            container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: container)
            height = max(height, layoutManager.usedRect(for: container).height + 2)
        }
        editor.frame = CGRect(x: topLeft.x, y: topLeft.y, width: width, height: ceil(height))
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
        let maxWidth = max((viewport?.documentSize.width ?? .greatestFiniteMagnitude) - session.origin.x, 20)
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
