import CoreGraphics
import Foundation
import PhotonzCore

// The weight a freshly drawn line starts at, decided by the canvas it lands on
// (Next, `next-icon-frames`).
//
// The rule itself is `IconStrokeWeight` in PhotonzCore, where it is tested. All
// that is here is the release gate and the three shapes the call takes: the
// editor commits a shape and knows its style for certain, the canvas draws a
// draft and may have no style at all, and the tool bar's Width row asks the
// same question with no drawing in progress at all. All three go through the
// one rule, which is what keeps the number you read, the line under your hand
// and the line that lands the same weight.
//
// With the flag off, every one of these hands back exactly what it was given,
// so the current release draws what it always drew.

/// The content and style a freshly drawn shape arrives in, for a caller that
/// may be holding no style.
@MainActor
func startingOutline(_ content: AnnotationContent, style: LayerStyle?,
                     chosen: Bool, drawnAt point: CGPoint, in document: PhotonzDocument?)
    -> (content: AnnotationContent, style: LayerStyle?) {
    guard Experiments.shared.iconFramesEnabled, let document else { return (content, style) }
    return document.startingOutline(content: content, style: style,
                                    chosen: chosen, drawnAt: point)
}

extension EditorState {

    /// The same, for the commit: a shape that is landing always has a style.
    func startingOutline(_ content: AnnotationContent, style: LayerStyle,
                         drawnAt point: CGPoint)
        -> (content: AnnotationContent, style: LayerStyle) {
        let started = Photonz.startingOutline(content, style: style,
                                              chosen: annotationStyles
                                                  .strokeWidthWasChosen(forShape: content.shape),
                                              drawnAt: point, in: document)
        return (started.content, started.style ?? style)
    }

    /// The weight a path starts at, for the commit.
    func startingPathStrokeWidth(armed: CGFloat, drawnAt point: CGPoint) -> CGFloat {
        Photonz.startingPathStrokeWidth(armed: armed,
                                        chosen: annotationStyles.strokeWidthWasChosen(for: .pen),
                                        drawnAt: point, in: document)
    }

    /// Whether the weight the tool in hand is armed with is one somebody asked
    /// for. Echoed to the canvas so a draft is drawn by the same rule the
    /// commit will use.
    var armedStrokeWidthIsChosen: Bool {
        annotationStyles.strokeWidthWasChosen(for: activeTool)
    }

    /// The weight the tool in hand would REALLY draw at right now: the weight
    /// it is armed with, after the icon frame being worked in has had its say.
    ///
    /// This is what the tool bar's Width row reads. Without it the row showed
    /// the armed weight while the line landed thinner, so on a 24 pixel frame
    /// the row said 4 and the line came out at 2 — a box you can type into
    /// saying one number and delivering another.
    ///
    /// The frame it asks about is the one being drawn in, which is the frame
    /// the icon previews strip is already showing (`iconPreviewFrameID`), so
    /// the number in the row and the pictures beside it are about one icon. Off
    /// an icon frame there is nothing to decide and the armed weight is the
    /// answer, exactly as before.
    ///
    /// With NOTHING picked the pointer says which icon instead
    /// (`pointerIconFrameID`). That case was left out at first and it is the
    /// one that draws: pick nothing, hold the Pen over a 24 pixel frame and
    /// draw, and the line lands at 2 because the drawing asks about the point
    /// it is landing on, while the row had nothing to ask and went on reading
    /// the armed 4.
    var startedStrokeWidth: CGFloat {
        let armed = annotationStyles.strokeWidth(for: activeTool)
        guard Experiments.shared.iconFramesEnabled, let document else { return armed }
        return document.startingStrokeWidth(armed: armed,
                                            chosen: armedStrokeWidthIsChosen,
                                            picked: selectedLayerID,
                                            pointerIn: pointerIconFrameID)
    }
}

/// The weight a path starts at.
///
/// Asked twice over one drawing — once by the canvas as the first anchor goes
/// down, once by the commit from the frame the finished path joins — and the
/// rule is written so the second ask hands back what the first one decided:
/// only a weight nobody has chosen is the app's to change.
@MainActor
func startingPathStrokeWidth(armed: CGFloat = PathContent.defaultStrokeWidth,
                             chosen: Bool,
                             drawnAt point: CGPoint,
                             in document: PhotonzDocument?) -> CGFloat {
    guard Experiments.shared.iconFramesEnabled, let document else { return armed }
    return document.startingStrokeWidth(armed: armed, chosen: chosen, drawnAt: point)
}
