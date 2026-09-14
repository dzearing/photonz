import Foundation
import PhotonzCore

// The Pen's side of the editor (Next, `next-pen`): a finished path becomes one
// layer, and the chip under the canvas says what to do next.

extension EditorState {

    /// A path the Pen finished, in document coordinates. One undo step for the
    /// whole drawing, however many anchors went into it.
    ///
    /// The Pen STAYS IN HAND, which is the one place it parts company with
    /// every other drawing tool in the app (`finishCreating`). Those draw one
    /// thing per errand, so handing back to Select is the ending that saves a
    /// press; the Pen draws an icon, which is five or six shapes in a row, and
    /// handing back after each one turns five drawings into five drawings and
    /// five presses of P. Illustrator, Figma and Sketch all keep it, so the
    /// habit people arrive with is the one that works here.
    ///
    /// The new layer is still PICKED, so the shape can be repainted in the
    /// Appearance panel without putting the Pen down first, and Escape with
    /// nothing being drawn puts the Pen down and hands it to Select with that
    /// pick intact (`CanvasNSView.penKeyDown`) — the old ending, one press
    /// away, for when the icon is finished.
    func addPath(_ content: PathContent) {
        guard content.anchors.count >= 2 else { return }
        // The canvas already drew it at this weight, read from the frame the
        // first anchor landed on; asked again here from the frame the finished
        // path actually JOINS, which is the one `addLayerDrawnOnFrame` is about
        // to hand it to. The same answer every ordinary time, and the right one
        // for a path that wandered onto a different canvas on its way round.
        var content = content
        content.strokeWidth = startingPathStrokeWidth(
            armed: content.strokeWidth,
            drawnAt: CGPoint(x: content.bounds.midX, y: content.bounds.midY))
        let layer = PenSession.layer(from: content)
        perform { $0.addLayerDrawnOnFrame(layer) }
        finishCreating(layer.id, tool: .pen)
    }

    /// The ink the Pen is armed with on the tool bar: what the next path comes
    /// out in, edge and inside alike.
    ///
    /// The canvas reads it as the first anchor goes down, so the line under
    /// your hand is the line that lands. It is a preference rather than part of
    /// the picture, which is why it lives with the other tools' remembered
    /// colours and not in the document.
    var armedPenPaint: Paint {
        annotationStyles.paint(for: .pen) ?? Paint(hex: PathContent.defaultColorHex)
    }

    /// The line on the chip under the canvas while the Pen is in hand. Live
    /// state, never in the document.
    var penHintText: String {
        penHint ?? PenSession.hint(for: PenSession())
    }

    /// Whether that chip is up: only with the Pen in hand, and only in a
    /// release that has a Pen.
    var showsPenHint: Bool {
        Experiments.shared.penEnabled && activeTool == .pen
    }
}
