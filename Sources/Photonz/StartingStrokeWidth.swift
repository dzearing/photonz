import CoreGraphics
import Foundation
import PhotonzCore

// The weight a freshly drawn line starts at, decided by the canvas it lands on
// (Next, `next-icon-frames`).
//
// The rule itself is `IconStrokeWeight` in PhotonzCore, where it is tested. All
// that is here is the release gate and the two shapes the call takes: the
// editor commits a shape and knows its style for certain, the canvas draws a
// draft and may have no style at all. Both go through the one rule, which is
// what keeps the line under your hand the same weight as the line that lands.
//
// With the flag off, every one of these hands back exactly what it was given,
// so the current release draws what it always drew.

/// The content and style a freshly drawn shape arrives in, for a caller that
/// may be holding no style.
@MainActor
func startingOutline(_ content: AnnotationContent, style: LayerStyle?,
                     drawnAt point: CGPoint, in document: PhotonzDocument?)
    -> (content: AnnotationContent, style: LayerStyle?) {
    guard Experiments.shared.iconFramesEnabled, let document else { return (content, style) }
    return document.startingOutline(content: content, style: style, drawnAt: point)
}

extension EditorState {

    /// The same, for the commit: a shape that is landing always has a style.
    func startingOutline(_ content: AnnotationContent, style: LayerStyle,
                         drawnAt point: CGPoint)
        -> (content: AnnotationContent, style: LayerStyle) {
        let started = Photonz.startingOutline(content, style: style,
                                              drawnAt: point, in: document)
        return (started.content, started.style ?? style)
    }

    /// The weight a path starts at, for the commit.
    func startingPathStrokeWidth(armed: CGFloat, drawnAt point: CGPoint) -> CGFloat {
        Photonz.startingPathStrokeWidth(armed: armed, drawnAt: point, in: document)
    }
}

/// The weight a path starts at.
///
/// Asked twice over one drawing — once by the canvas as the first anchor goes
/// down, once by the commit from the frame the finished path joins — and the
/// rule is written so the second ask hands back what the first one decided:
/// only the width every new path in the app ships with is the app's to change.
@MainActor
func startingPathStrokeWidth(armed: CGFloat = PathContent.defaultStrokeWidth,
                             drawnAt point: CGPoint,
                             in document: PhotonzDocument?) -> CGFloat {
    guard Experiments.shared.iconFramesEnabled, let document else { return armed }
    return document.startingStrokeWidth(armed: armed, drawnAt: point)
}
