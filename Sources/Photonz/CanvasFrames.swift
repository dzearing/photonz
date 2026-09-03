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
///   The name is also the frame's handle: what a click on it does lives in
///   `CanvasNames.swift`, next to the component name that behaves the same way.
/// - **A hairline at its edge.** A frame whose surface matches the canvas
///   behind it would otherwise have no edge at all, and the edge is the thing
///   the whole feature is about.
extension CanvasNSView {

    // MARK: Drawing

    func refreshFrameChrome() {
        guard framesEnabled, let viewport, let document, document.hasFrames else {
            frameChromeLayer.isHidden = true
            frameChromeLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
            frameEdgeLayer.isHidden = true
            layoutCanvasNameField()
            return
        }
        frameChromeLayer.isHidden = false
        frameChromeLayer.sublayers?.forEach { $0.removeFromSuperlayer() }

        let edges = CGMutablePath()
        for frame in document.frames {
            guard frame.isVisible, let bounds = document.canvasBounds(of: frame.id),
                  bounds.width > 0, bounds.height > 0 else { continue }
            edges.addRect(viewRect(forDocRect: bounds, in: viewport).insetBy(dx: 0.5, dy: 0.5))
        }

        // Names come from the one stacked list, so a screen whose corner is
        // crowded prints its name on the line the list gave it rather than on
        // top of whatever else wanted that spot. A frame promoted to a
        // component is not in this list at all: it wears the component's mark
        // and name in the same place, so a box never carries two names.
        for chip in canvasNameChips() where chip.kind == .screen {
            // The frame being renamed has a field standing where its name was.
            if chip.layer.id == canvasRenameID { continue }
            let label = CATextLayer()
            label.string = chip.layer.name
            label.font = Self.nameLabelFont
            label.fontSize = Self.nameLabelFont.pointSize
            // A neutral grey, NOT a theme label color: this text sits on the
            // picture, which may be white, dark, or a screenshot of anything,
            // and a label that follows the app's theme goes invisible on half
            // of them. The accent means "this name is live": the frame is
            // selected, or the pointer is resting on the name, which is the
            // only hint anywhere that the name can be clicked.
            label.foregroundColor = isNameLabelLive(chip.layer.id)
                ? NSColor.controlAccentColor.cgColor
                : CGColor(gray: 0.45, alpha: 1)
            label.contentsScale = window?.backingScaleFactor ?? 2
            label.alignmentMode = .left
            label.truncationMode = .end
            // The label hangs above the frame's top left corner and is never
            // part of it: it does not move the frame, and clicking through it
            // reaches whatever is behind.
            label.frame = CanvasNameLabels.box(for: chip.label)
            frameChromeLayer.addSublayer(label)
        }
        frameEdgeLayer.path = edges
        frameEdgeLayer.isHidden = edges.isEmpty
        layoutCanvasNameField()
    }

    /// Whether frame chrome is drawn at all. A document with no frames in it
    /// never sees any of this, which is every screenshot anybody has taken.
    var framesEnabled: Bool { Experiments.shared.framesEnabled }
}
