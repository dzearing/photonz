import Foundation
import PhotonzCore

// The Brush's side of the editor (Next, `next-brush`): a finished stroke lands
// in the document as one undo step, and the brush stays in hand for the next
// (`docs/design/brushes.md`).

extension EditorState {

    /// A stroke the canvas finished, in canvas points. One undo step.
    ///
    /// With a paint layer picked the stroke is added to it; otherwise it makes
    /// a new Paint layer just above whatever is picked (on top with nothing
    /// picked) and picks it, so the next stroke goes to the same layer
    /// (`PhotonzDocument.paintStroke`). The Brush stays in hand: it is the one
    /// making tool that does not hand back Select
    /// (`ArrowCaptionEntry.toolAfterLanding`).
    func addBrushStroke(_ stroke: BrushStroke) {
        guard !stroke.samples.isEmpty, document != nil else { return }
        let picked = selectedLayerID
        var landed: UUID?
        perform { landed = $0.paintStroke(stroke, onto: picked) }
        guard let landed, landed != picked else { return }
        finishCreating(landed, tool: ArrowCaptionEntry.toolAfterLanding(.brush, offersCaption: false))
    }

    /// What the next stroke is painted with: the armed brush, and the colour
    /// on the tool bar's swatch.
    var armedBrush: BrushSettings { annotationStyles.armedBrush }

    var armedBrushColorHex: String {
        annotationStyles.colorHex(for: .brush) ?? AnnotationStyles.defaultBrushColorHex
    }
}
