import AppKit
import PhotonzCore

/// What a frame looks like on the canvas beyond the pixels it paints (Next,
/// `next-frames`).
///
/// Two pieces of chrome, and both are chrome: they are drawn by the canvas, not
/// by the renderer, so they sit above the picture, stay the same size at every
/// zoom, and never land in an export.
///
/// - **Its name, above its top left corner.** A screen with no label is a white
///   rectangle; the label is how a canvas of several screens stays readable.
/// - **A hairline at its edge.** A frame whose surface matches the canvas
///   behind it would otherwise have no edge at all, and the edge is the thing
///   the whole feature is about.
extension CanvasNSView {

    /// The distance from a frame's top edge to the baseline strip its name sits
    /// in. Close enough to belong to the frame, clear enough not to touch it.
    private static let frameLabelGap: CGFloat = 4
    private static let frameLabelHeight: CGFloat = 14

    func refreshFrameChrome() {
        guard framesEnabled, let viewport, let document, document.hasFrames else {
            frameChromeLayer.isHidden = true
            frameChromeLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
            frameEdgeLayer.isHidden = true
            return
        }
        frameChromeLayer.isHidden = false
        frameChromeLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

        let edges = CGMutablePath()
        for frame in document.frames {
            guard frame.isVisible, let bounds = document.canvasBounds(of: frame.id),
                  bounds.width > 0, bounds.height > 0 else { continue }
            let rect = viewRect(forDocRect: bounds, in: viewport)
            edges.addRect(rect.insetBy(dx: 0.5, dy: 0.5))

            let label = CATextLayer()
            label.string = frame.name
            label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            label.fontSize = 10
            // A neutral grey, NOT a theme label color: this text sits on the
            // picture, which may be white, dark, or a screenshot of anything,
            // and a label that follows the app's theme goes invisible on half
            // of them.
            label.foregroundColor = frame.id == selectedLayerID
                ? NSColor.controlAccentColor.cgColor
                : CGColor(gray: 0.45, alpha: 1)
            label.contentsScale = window?.backingScaleFactor ?? 2
            label.alignmentMode = .left
            label.truncationMode = .end
            // The label hangs above the frame's top left corner and is never
            // part of it: it does not move the frame, and clicking through it
            // reaches whatever is behind.
            let width = min(rect.width, 240)
            label.frame = CGRect(x: rect.minX,
                                 y: rect.minY - Self.frameLabelHeight - Self.frameLabelGap,
                                 width: max(width, 40), height: Self.frameLabelHeight)
            frameChromeLayer.addSublayer(label)
        }
        frameEdgeLayer.path = edges
        frameEdgeLayer.isHidden = edges.isEmpty
    }

    /// Whether frame chrome is drawn at all. A document with no frames in it
    /// never sees any of this, which is every screenshot anybody has taken.
    private var framesEnabled: Bool { Experiments.shared.framesEnabled }
}
