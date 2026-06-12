import AppKit
import PhotonzCore
import SwiftUI

/// The document canvas: a layer-backed NSView that draws the rendered composite
/// positioned by `Viewport`. All geometry decisions live in `Viewport`
/// (PhotonzCore, tested); this view only mirrors them into Core Animation.
struct CanvasView: NSViewRepresentable {
    let image: CGImage?
    let viewport: Viewport?
    let onViewSizeChange: (CGSize) -> Void
    let onViewportChange: (Viewport) -> Void

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView()
        view.onViewSizeChange = onViewSizeChange
        view.onViewportChange = onViewportChange
        return view
    }

    func updateNSView(_ view: CanvasNSView, context: Context) {
        view.onViewSizeChange = onViewSizeChange
        view.onViewportChange = onViewportChange
        view.apply(image: image, viewport: viewport)
    }
}

final class CanvasNSView: NSView {
    var onViewSizeChange: ((CGSize) -> Void) = { _ in }
    var onViewportChange: ((Viewport) -> Void) = { _ in }

    private let contentLayer = CALayer()
    private var lastReportedSize: CGSize = .zero
    /// The viewport currently on screen. Gesture handlers mutate from this and
    /// apply locally before notifying, so panning/zooming never waits a runloop
    /// tick for SwiftUI to echo the state back.
    private var viewport: Viewport?
    private var image: CGImage?

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
        apply(image: image, viewport: next)
        onViewportChange(next)
    }

    // MARK: Display

    func apply(image: CGImage?, viewport: Viewport?) {
        self.image = image
        self.viewport = viewport

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard let image, let viewport else {
            contentLayer.isHidden = true
            return
        }
        contentLayer.isHidden = false
        contentLayer.contents = image
        contentLayer.frame = viewport.documentFrameInView
        contentLayer.shadowPath = CGPath(rect: contentLayer.bounds, transform: nil)
        // Past 2× the user is inspecting pixels — show them squarely instead of smearing.
        contentLayer.magnificationFilter = viewport.zoom >= 2 ? .nearest : .linear
    }
}
