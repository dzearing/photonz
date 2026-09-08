import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

@Suite("Turn into a picture: the question asked first")
struct RasterizePromptTests {
    private let frame = CGRect(x: 0, y: 0, width: 120, height: 40)

    private func shape(_ name: String = "Rectangle") -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle)), frame: frame)
    }

    private func text(_ name: String = "Heading") -> Layer {
        Layer(name: name, content: .text(TextContent(string: "Hello")), frame: frame)
    }

    @Test func onlySomethingThatCanBeTurnedRaisesTheQuestion() {
        #expect(RasterizePrompt(layer: shape()) != nil)
        #expect(RasterizePrompt(layer: text()) != nil)
        let picture = Layer(name: "Photo", content: .image(ImageRef(pixelSize: frame.size)), frame: frame)
        #expect(RasterizePrompt(layer: picture) == nil)
        let measure = Layer(name: "Width", content: .measure(MeasureContent()), frame: frame)
        #expect(RasterizePrompt(layer: measure) == nil)
    }

    @Test func theQuestionNamesTheThingYouPicked() {
        #expect(RasterizePrompt(layer: shape("Card back"))?.title == "Turn \u{201C}Card back\u{201D} into a picture?")
        // A layer with no name of its own still asks a whole question.
        #expect(RasterizePrompt(layer: shape(""))?.title == "Turn this shape into a picture?")
        #expect(RasterizePrompt(layer: text(""))?.title == "Turn this text into a picture?")
    }

    @Test func theMessageSaysWhatIsGainedAndWhatIsLost() {
        let shapeMessage = RasterizePrompt(layer: shape())?.message ?? ""
        #expect(shapeMessage.contains("cut a piece out of it"))
        #expect(shapeMessage.contains("The shape stops being editable"))
        #expect(shapeMessage.contains("Undo"))

        // Text loses its words, not its outline, so it says so in its own noun.
        let textMessage = RasterizePrompt(layer: text())?.message ?? ""
        #expect(textMessage.contains("The words stop being editable"))
        #expect(!textMessage.contains("The shape stops"))
    }

    @Test func theButtonSaysWhatItDoes() {
        // Never "OK": the button is read on its own, so it carries the verb.
        #expect(RasterizePrompt(layer: shape())?.confirm == "Turn Into Picture")
        #expect(RasterizePrompt(layer: shape())?.cancel == "Cancel")
        #expect(RasterizePrompt.suppression == "Don't ask again")
    }

    @Test func theQuestionMatchesTheMenuItemThatRaisesIt() {
        // One name for one thing: the menu row, the button in the question and
        // the way out printed on the refusal pill all say the same words.
        #expect(RasterizePrompt.menuItem == "Turn Into Picture…")
        let confirm: String = RasterizePrompt(layer: shape())?.confirm ?? ""
        #expect(RasterizePrompt.menuItem.hasPrefix(confirm))
        #expect(RegionSliceRefusal(action: .erase, reason: .canBecomeAPicture)
            .detail.lowercased().contains("turn it into a picture"))
    }

    @Test func nothingItSaysUsesAnEmDash() {
        for layer in [shape(), text(), shape(""), text("")] {
            let prompt = RasterizePrompt(layer: layer)
            #expect(prompt != nil)
            for line in [prompt?.title, prompt?.message, prompt?.confirm, prompt?.cancel] {
                #expect(!(line ?? "").isEmpty)
                #expect(!(line ?? "").contains("—"))
            }
        }
        #expect(!RasterizePrompt.menuItem.contains("—"))
    }
}
