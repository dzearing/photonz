import AppKit
import PhotonzCore
import SwiftUI

/// The document canvas: a layer-backed NSView that draws the rendered composite
/// positioned by `Viewport`. All geometry decisions live in `Viewport`
/// (PhotonzCore, tested); this view only mirrors them into Core Animation.
struct CanvasView: NSViewRepresentable {
    let image: CGImage?
    let viewport: Viewport?
    let document: PhotonzDocument?
    let selection: CGRect?
    let selectedLayerFrame: CGRect?
    let onViewSizeChange: (CGSize) -> Void
    let onViewportChange: (Viewport) -> Void
    let onSelectionChange: (CGRect?) -> Void
    let onSelectLayer: (UUID?) -> Void
    let onMovePreview: (UUID, CGPoint) -> Void
    let onMoveCommit: (UUID, CGPoint) -> Void

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView()
        update(view)
        return view
    }

    func updateNSView(_ view: CanvasNSView, context: Context) {
        update(view)
        view.apply(image: image, viewport: viewport, document: document,
                   selection: selection, selectedLayerFrame: selectedLayerFrame)
    }

    private func update(_ view: CanvasNSView) {
        view.onViewSizeChange = onViewSizeChange
        view.onViewportChange = onViewportChange
        view.onSelectionChange = onSelectionChange
        view.onSelectLayer = onSelectLayer
        view.onMovePreview = onMovePreview
        view.onMoveCommit = onMoveCommit
    }
}

final class CanvasNSView: NSView {
    var onViewSizeChange: ((CGSize) -> Void) = { _ in }
    var onViewportChange: ((Viewport) -> Void) = { _ in }
    var onSelectionChange: ((CGRect?) -> Void) = { _ in }
    var onSelectLayer: ((UUID?) -> Void) = { _ in }
    var onMovePreview: ((UUID, CGPoint) -> Void) = { _, _ in }
    var onMoveCommit: ((UUID, CGPoint) -> Void) = { _, _ in }

    private let contentLayer = CALayer()
    /// Marching ants: a solid white stroke underneath…
    private let selectionBaseLayer = CAShapeLayer()
    /// …and animated black dashes on top, giving the classic alternating crawl.
    private let selectionAntsLayer = CAShapeLayer()
    /// Accent outline around the selected layer.
    private let layerOutlineLayer = CAShapeLayer()
    /// Snap guides shown while a move drag is captured by an edge/center.
    private let snapGuideLayer = CAShapeLayer()
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
    /// Selected layer's frame in document coordinates (committed state).
    private var selectedLayerFrame: CGRect?
    /// In-progress marquee (document coordinates). While set, it is what the
    /// ants display — same zero-latency-echo pattern as pan/zoom.
    private var marquee: MarqueeDrag?

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

        for shape in [selectionBaseLayer, selectionAntsLayer, layerOutlineLayer, snapGuideLayer] {
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
        window?.makeFirstResponder(self)
        let p = viewport.documentPoint(fromView: convert(event.locationInWindow, from: nil))
        if let hit = document?.hitTest(p) {
            onSelectLayer(hit.id)
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
        if var drag = moveDrag {
            let proposed = CGPoint(x: p.x - drag.grabOffset.x, y: p.y - drag.grabOffset.y)
            if !drag.moved {
                let travel = hypot(proposed.x - drag.startOrigin.x, proposed.y - drag.startOrigin.y)
                drag.moved = travel * viewport.zoom >= 4
            }
            if drag.moved {
                drag.snapped = Snapping.snapFrameOrigin(proposed, size: drag.size,
                                                        canvas: viewport.documentSize,
                                                        zoom: viewport.zoom)
                onMovePreview(drag.layerID, drag.snapped.origin)
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
        if let drag = moveDrag {
            moveDrag = nil
            if drag.moved {
                selectedLayerFrame = CGRect(origin: drag.snapped.origin, size: drag.size)
                onMoveCommit(drag.layerID, drag.snapped.origin)
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
        if event.keyCode == 53 { // Esc, in priority order: cancel drag → ants → layer
            if let drag = moveDrag {
                moveDrag = nil
                selectedLayerFrame = CGRect(origin: drag.startOrigin, size: drag.size)
                // Committing the start origin is a History no-op but resets the preview render.
                onMoveCommit(drag.layerID, drag.startOrigin)
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
        apply(image: image, viewport: next, document: document,
              selection: selection, selectedLayerFrame: selectedLayerFrame)
        onViewportChange(next)
    }

    // MARK: Display

    func apply(image: CGImage?, viewport: Viewport?, document: PhotonzDocument?,
               selection: CGRect?, selectedLayerFrame: CGRect?) {
        self.image = image
        self.viewport = viewport
        self.document = document
        // While the user is mid-drag the local state is the truth; don't let an
        // unrelated SwiftUI update echo stale committed values over it.
        if marquee == nil {
            self.selection = selection
        }
        if moveDrag == nil {
            self.selectedLayerFrame = selectedLayerFrame
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard let image, let viewport else {
            contentLayer.isHidden = true
            selectionBaseLayer.isHidden = true
            selectionAntsLayer.isHidden = true
            layerOutlineLayer.isHidden = true
            snapGuideLayer.isHidden = true
            return
        }
        contentLayer.isHidden = false
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
        if let moveDrag {
            frame = CGRect(origin: moveDrag.snapped.origin, size: moveDrag.size)
        } else {
            frame = selectedLayerFrame
        }
        guard let viewport, let frame else {
            layerOutlineLayer.isHidden = true
            snapGuideLayer.isHidden = true
            return
        }
        layerOutlineLayer.path = CGPath(rect: viewRect(forDocRect: frame, in: viewport), transform: nil)
        layerOutlineLayer.isHidden = false

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

    private func viewRect(forDocRect r: CGRect, in viewport: Viewport) -> CGRect {
        let topLeft = viewport.viewPoint(fromDocument: r.origin)
        return CGRect(x: topLeft.x, y: topLeft.y,
                      width: r.width * viewport.zoom, height: r.height * viewport.zoom)
    }
}
