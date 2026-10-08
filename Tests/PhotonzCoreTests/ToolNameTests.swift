import Foundation
import PhotonzCore
import Testing

/// The T tool is the Title tool on a video and the Text tool on a picture: a
/// video editor looks for a title tool by that name (`video-title-wt.html`:
/// "Pick up the Title tool", its tooltip "Title / Text (T)"), while a
/// screenshot's tool has always been Text.
@Suite("Tool names")
struct ToolNameTests {

    @Test("A document with time calls the T tool Title")
    func titleInTime() {
        #expect(ToolName.text(inTime: true) == "Title")
    }

    @Test("A picture still calls it Text")
    func textInAPicture() {
        #expect(ToolName.text(inTime: false) == "Text")
    }

    @Test("Its tooltip on a video says both names, the mock's words")
    func tipInTime() {
        #expect(ToolName.textTip(inTime: true) == "Title / Text")
        #expect(ToolName.textTip(inTime: false) == "Text")
    }

    @Test("Every other tool keeps its one name in both documents")
    func othersUnchanged() {
        for tool in Tool.allCases where tool != .text {
            #expect(ToolName.renamed(tool, inTime: true) == nil)
        }
        #expect(ToolName.renamed(.text, inTime: true) == "Title")
        #expect(ToolName.renamed(.text, inTime: false) == nil)
    }

    @Test("The video title guide asks for the Title tool, as the bar names it")
    func guideSaysTitle() {
        let step = TutorialGuides.aTitleThatMoves.steps.first { $0.anchor == .tool(.text) }
        #expect(step?.title == "Pick the \(ToolName.text(inTime: true)) tool")
    }
}
