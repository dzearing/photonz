import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// Two different questions share one string while a caption is being typed,
/// and answering both with the same answer is what put the caret in the wrong
/// place.
///
/// HOW THE DRAFT IS LAID OUT — one line left along the bubble, several lines
/// centred on each other — is a question about the text ON SCREEN, newline and
/// all. HOW BIG THE BUBBLE IS is a question about the text that will COMMIT,
/// which is trimmed, so a bare trailing Return cannot make the bubble grow a
/// line it is about to throw away.
///
/// Asking the committed text how to lay the draft out is the reported bug:
/// type "Hello", press Return, and the field is still left aligned because
/// "Hello\n" commits as "Hello", so the caret drops to the bubble's left edge.
/// Type one character and the answer flips to centred and the character lands
/// in the middle, a good 17 points from where the caret had been sitting.
@Suite("Caption draft layout")
struct CaptionDraftLayoutTests {

    private func arrow(fontSize: CGFloat = 20) -> AnnotationContent {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        content.captionFontSize = fontSize
        content.caption = ""
        return content
    }

    @Test("a draft with no line break in it is laid out on one line")
    func oneLineDraft() {
        #expect(CaptionMetrics.draftIsMultiLine("Hello") == false)
        #expect(CaptionMetrics.draftIsMultiLine("") == false)
        #expect(CaptionMetrics.draftIsMultiLine("  Hello  ") == false)
    }

    /// The whole bug in one assertion: a bare trailing Return IS a second line
    /// as far as the field is concerned, even though it commits as one.
    @Test("a bare trailing Return makes the draft a two line draft")
    func trailingReturnIsTwoLines() {
        #expect(CaptionMetrics.draftIsMultiLine("Hello\n"))
        #expect(CaptionMetrics.committedText("Hello\n") == "Hello",
                "the committed text still trims it, which is what keeps the bubble one line")
    }

    @Test("a draft with words on both lines is a two line draft")
    func realSecondLine() {
        #expect(CaptionMetrics.draftIsMultiLine("Hello\nX"))
        #expect(CaptionMetrics.draftIsMultiLine("Hello\nX\nY"))
    }

    /// ...and the measurements do NOT follow the draft, which is the trap in
    /// fixing the caret: the bubble must not grow a line on a bare Return.
    @Test("a bare trailing Return leaves the bubble exactly the size it was")
    func trailingReturnDoesNotResizeTheBubble() {
        let content = arrow()
        let typed = CaptionMetrics.pillSize(for: "Hello", in: content)
        let returned = CaptionMetrics.pillSize(for: "Hello\n", in: content)
        #expect(typed == returned, "\(typed) became \(returned) on a bare Return")
        #expect(CaptionMetrics.textSize(for: "Hello\n", fontSize: content.captionFontSize)
                == CaptionMetrics.textSize(for: "Hello", fontSize: content.captionFontSize))
        #expect(CaptionMetrics.textInset(for: "Hello\n", in: content)
                == CaptionMetrics.textInset(for: "Hello", in: content),
                "and the words do not slide sideways either")
    }

    /// Typing the first character of the second line is what the caret was
    /// promising, so the bubble it lands in must be the one that was on screen
    /// a keystroke earlier, one line taller and no wider.
    @Test("the second line's first character grows the bubble by a line and nothing else")
    func firstCharacterOfTheSecondLine() {
        let content = arrow()
        let before = CaptionMetrics.pillSize(for: "Hello\n", in: content)
        let after = CaptionMetrics.pillSize(for: "Hello\nX", in: content)
        #expect(after.width == before.width, "a narrow second line must not widen the bubble")
        #expect(after.height > before.height, "it must gain the line it was promised")
    }
}
