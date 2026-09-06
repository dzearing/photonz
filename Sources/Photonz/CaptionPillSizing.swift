import CoreGraphics
import PhotonzCore
import PhotonzRender

/// The one place the app asks how big an arrow's caption pill really is.
///
/// The document model can only GUESS: `AnnotationContent.estimatedCaptionSize`
/// multiplies a character count by a nominal glyph width, because PhotonzCore
/// is pure and cannot lay out type. The guess is deliberately generous — 63pt
/// wide for a two letter label that measures 55, 408pt for a sentence that
/// measures 245 — which is right for reserving room in a frame and wrong for
/// anything a person can see or touch.
///
/// So every decision the hand can feel takes the measurement instead: where a
/// dropped label lands, how close to the edge of the picture it may sit, and
/// what you can pick it up by. Everything else keeps the estimate.
extension Layer {
    /// This arrow's caption pill as MEASURED, or nil when it has no label.
    var measuredCaptionPillSize: CGSize? {
        annotation?.measuredCaptionPillSize
    }
}

extension AnnotationContent {
    /// This caption's pill as MEASURED, or nil when there is no label.
    var measuredCaptionPillSize: CGSize? {
        guard hasCaption else { return nil }
        return CaptionMetrics.pillSize(for: caption ?? "", in: self)
    }
}
