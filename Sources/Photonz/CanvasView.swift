import AppKit
import PhotonzCore
import SwiftUI

/// The document canvas: a layer-backed NSView that draws the rendered composite
/// positioned by `Viewport`. All geometry decisions live in `Viewport`
/// (PhotonzCore, tested); this view only mirrors them into Core Animation.
struct CanvasView: NSViewRepresentable {
    let image: CGImage?
    let viewport: Viewport?
    let selection: CGRect?
    let onViewSizeChange: (CGSize) -> Void
    let onViewportChange: (Viewport) -> Void
    let onSelectionChange: (CGRect?) -> Void

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView()
        update(view)
        return view
    }

    func updateNSView(_ view: CanvasNSView, context: Context) {
        update(view)
        view.apply(image: image, viewport: viewport, selection: selection)
    }

    private func update(_ view: CanvasNSView) {
        view.onViewSizeChange = onViewSizeChange
        view.onViewportChange = onViewportChange
        view.onSelectionChange = onSelectionChange
    }
}

final class CanvasNSView: NSView {
    var onViewSizeChange: ((CGSize) -> Void) = { _ in }
    var onViewportChange: ((Viewport) -> Void) = { _ in }
    var onSelectionChange: ((CGRect?) -> Void) = { _ in }

    private let contentLayer = CALayer()
    /// Marching ants: a solid white stroke underneath…
    private let selectionBaseLayer = CAShapeLayer()
    /// …and animated black dashes on top, giving the classic alternating crawl.
    private let selectionAntsLayer = CAShapeLayer()
    private var lastReportedSize: CGSize = .zero
    /// The viewport currently on screen. Gesture handlers mutate from this and
    /// apply locally before notifying, so panning/zooming never waits a runloop
    /// tick for SwiftUI to echo the state back.
    private var viewport: Viewport?
    private var image: CGImage?
    /// Committed selection in document coordinates.
    private var selection: CGRect?
    /// In-progress marquee (document coordinates). While set, it is what the
    /// ants display — same zero-latency-echo pattern as pan/zoom.
    private var marquee: MarqueeDrag?

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

        for shape in [selectionBaseLayer, selectionAntsLayer] {
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

    // MARK: Marquee selection

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let viewport else { return }
        window?.makeFirstResponder(self)
        let p = viewport.documentPoint(fromView: convert(event.locationInWindow, from: nil))
        marquee = MarqueeDrag(anchor: p)
        refreshSelectionDisplay()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let viewport, var drag = marquee else { return }
        drag.update(to: viewport.documentPoint(fromView: convert(event.locationInWindow, from: nil)))
        marquee = drag
        refreshSelectionDisplay(constrainSquare: event.modifierFlags.contains(.shift))
    }

    override func mouseUp(with event: NSEvent) {
        guard let viewport, let drag = marquee else { return }
        marquee = nil
        if drag.isClick(atZoom: viewport.zoom) {
            commitSelection(nil) // a plain click deselects
        } else {
            let square = event.modifierFlags.contains(.shift)
            let rect = drag.selectionRect(constrainSquare: square, in: viewport.documentSize)
            commitSelection(rect.map(Geometry.pixelAligned))
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            if marquee != nil || selection != nil {
                marquee = nil
                commitSelection(nil)
                return
            }
        }
        super.keyDown(with: event)
    }

    private func commitSelection(_ rect: CGRect?) {
        selection = rect
        refreshSelectionDisplay()
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
        apply(image: image, viewport: next, selection: selection)
        onViewportChange(next)
    }

    // MARK: Display

    func apply(image: CGImage?, viewport: Viewport?, selection: CGRect?) {
        self.image = image
        self.viewport = viewport
        // While the user is mid-drag the local marquee is the truth; don't let
        // an unrelated SwiftUI update echo a stale committed selection over it.
        if marquee == nil {
            self.selection = selection
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard let image, let viewport else {
            contentLayer.isHidden = true
            selectionBaseLayer.isHidden = true
            selectionAntsLayer.isHidden = true
            return
        }
        contentLayer.isHidden = false
        contentLayer.contents = image
        contentLayer.frame = viewport.documentFrameInView
        contentLayer.shadowPath = CGPath(rect: contentLayer.bounds, transform: nil)
        // Past 2× the user is inspecting pixels — show them squarely instead of smearing.
        contentLayer.magnificationFilter = viewport.zoom >= 2 ? .nearest : .linear

        refreshSelectionDisplayInsideTransaction()
    }

    private func refreshSelectionDisplay(constrainSquare: Bool = false) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        refreshSelectionDisplayInsideTransaction(constrainSquare: constrainSquare)
        CATransaction.commit()
    }

    private func refreshSelectionDisplayInsideTransaction(constrainSquare: Bool = false) {
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
        let topLeft = viewport.viewPoint(fromDocument: docRect.origin)
        // Half-point inset so the 1pt stroke lands crisply on pixel boundaries.
        let viewRect = CGRect(x: topLeft.x, y: topLeft.y,
                              width: docRect.width * viewport.zoom,
                              height: docRect.height * viewport.zoom)
            .insetBy(dx: 0.5, dy: 0.5)
        let path = CGPath(rect: viewRect, transform: nil)
        selectionBaseLayer.path = path
        selectionAntsLayer.path = path
        selectionBaseLayer.isHidden = false
        selectionAntsLayer.isHidden = false
    }
}
