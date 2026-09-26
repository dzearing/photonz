import Foundation
import PhotonzCore

// The Pen's side of the editor (Next, `next-pen`): a finished path becomes one
// layer, and the chip under the canvas says what to do next.

extension EditorState {

    /// A path the Pen finished, in document coordinates. One undo step for the
    /// whole drawing, however many anchors went into it.
    ///
    /// The Pen ENDS LIKE EVERY OTHER TOOL THAT MAKES SOMETHING: the finished
    /// path is picked and Select is back in hand, so the arrow keys nudge it
    /// and the panels describe it without a trip to the tool bar
    /// (`ArrowCaptionEntry.toolAfterLanding`).
    ///
    /// This reverses "the pen stays in your hand for the next shape", which
    /// kept the Pen live on the reasoning that an icon is five or six shapes in
    /// a row. That reasoning is real and the app already answers it: P puts the
    /// Pen straight back, which is what the other ten drawing tools rely on, so
    /// five shapes cost five presses of P rather than one. Consistency across
    /// every tool beat the four presses saved in one of them, and the user ran
    /// into the inconsistency twice (2026-09-15: "after i create a shape, it
    /// doesn't select it and switch to V tool").
    ///
    /// What the sticky Pen landed alongside stays: a picked path shows its
    /// points under the Pen as well as under Select (`CanvasPathEdit`), so
    /// pressing P over a finished shape still reaches its anchors.
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
        addDrawnLayer(layer)
        finishCreating(layer.id,
                       tool: ArrowCaptionEntry.toolAfterLanding(activeTool,
                                                             offersCaption: false))
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

    /// The weight the Pen is armed with: what the next path's line comes out
    /// at, before the frame it lands on gets its say (`IconStrokeWeight`).
    ///
    /// Set a drawn path's Thickness and this is where that number was kept, so
    /// the next stroke of the same icon arrives at it. Like the ink, it is a
    /// preference rather than part of the picture.
    var armedPenStrokeWidth: CGFloat {
        annotationStyles.strokeWidth(for: .pen)
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
