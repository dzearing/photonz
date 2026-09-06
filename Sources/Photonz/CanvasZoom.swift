import AppKit
import PhotonzCore
import PhotonzRender
import SwiftUI

// Panning and zooming: scroll, pinch, double-tap and the viewport commit they
// all end in. Split out of CanvasView.swift; `CanvasNSView`'s stored
// properties still live there.

extension CanvasNSView {
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
        pinch(magnification: event.magnification,
              anchorInView: convert(event.locationInWindow, from: nil))
    }

    /// One nudge of a pinch: the zoom moves by `magnification`, keeping the
    /// point under the fingers where it is. The gesture and a scripted walk
    /// both come through here, so what a walk drives is exactly what a
    /// trackpad drives — which is the only way a fault that only shows WHILE
    /// the zoom is moving can be caught by anything but a person.
    func pinch(magnification: CGFloat, anchorInView anchor: CGPoint) {
        guard let viewport, magnification.isFinite else { return }
        commit(viewport.zoomed(to: viewport.zoom * (1 + magnification), anchorInView: anchor))
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
    func performWindowTitleBarAction() {
        WindowTitleBarAction.perform(on: window)
    }

    /// The canvas moved its own camera: a pinch, a scroll, a zoom command.
    ///
    /// It goes STRAIGHT to `applyViewport` and never back through `apply`.
    /// `apply` takes everything the canvas is showing as arguments and half of
    /// them carry defaults, so re-entering it with only the camera quietly
    /// reset the rest to those defaults — and the grid was one of them. Every
    /// pinch and every two-finger scroll therefore blew the grid away for as
    /// long as the fingers kept moving, and it came back only when the next
    /// SwiftUI pass handed the settings in again. That is the "grid disappears
    /// when you zoom" report of 2026-09-05, and it took the group context and
    /// the canvas selection with it. A camera move must not be able to say
    /// anything about the rest of the world, so now it cannot.
    private func commit(_ next: Viewport) {
        applyViewport(next)
        onViewportChange(next)
    }

    /// Redraw for a new camera and nothing else. Same picture, same document,
    /// same selection: only where they land on the screen changes, so this is
    /// the part of `apply` that depends on the viewport, and no more.
    func applyViewport(_ next: Viewport) {
        viewport = next
        // Zooming changes what sits under a resting pointer, so the grab cue
        // has to agree with the new arrangement rather than the old one.
        refreshGrabCursor()
        guard let image else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        contentLayer.isHidden = false
        contentLayer.contents = calloutHoldImage ?? image
        contentLayer.frame = next.documentFrameInView
        contentLayer.shadowPath = CGPath(rect: contentLayer.bounds, transform: nil)
        // Past 2x the user is inspecting pixels — show them squarely instead
        // of smearing, exactly as `apply` decides it.
        contentLayer.magnificationFilter = next.zoom >= 2 ? .nearest : .linear
        refreshOverlaysInsideTransaction()
    }
}
