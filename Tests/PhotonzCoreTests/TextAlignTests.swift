import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Where the words sit in their box (`docs/design/ui-building.md`, "Where the
/// words sit in their box"). Text has always been drawn from the top left,
/// which is invisible while the box hugs the words and wrong the moment the box
/// is told to fill something bigger.
@Suite("Words sit where the box says")
struct TextAlignTests {

    // MARK: - Building blocks

    private func label(_ string: String = "Button",
                       alignment: TextAlign? = nil,
                       verticalAlignment: TextVerticalAlign? = nil) -> Layer {
        let content = TextContent(string: string, fontSize: 14, colorHex: "#FFFFFF",
                                  alignment: alignment, verticalAlignment: verticalAlignment)
        return Layer(name: "Label", content: .text(content),
                     frame: CGRect(x: 40, y: 12, width: 48, height: 18))
    }

    /// A button-shaped group: a plate with a word on it.
    private func plate(_ label: Layer) -> PhotonzDocument {
        let back = Layer(name: "Background",
                         content: .image(ImageRef(pixelSize: CGSize(width: 128, height: 36))),
                         frame: CGRect(x: 0, y: 0, width: 128, height: 36))
        let group = Layer(name: "Button", content: .group(GroupContent(children: [back, label])),
                          frame: .zero)
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 200))
        document.layers = [group]
        return document
    }

    private func words(_ document: PhotonzDocument, _ id: UUID) -> TextContent? {
        document.layer(id: id)?.text
    }

    // MARK: - Nothing set is what every document already did

    @Test("Text with nothing set draws from the top left, exactly as it always has")
    func theDefaultIsTheOldRule() {
        let content = TextContent(string: "Hello")
        #expect(content.alignment == nil)
        #expect(content.usedAlignment == .left)
        #expect(content.usedVerticalAlignment == .top)
    }

    @Test("Text saved before alignment existed opens with none, and keeps none when saved again")
    func oldTextStillOpens() throws {
        let old = """
        {"string":"Hi","fontName":"SF Pro","fontSize":14,"colorHex":"#FFFFFF","weight":"regular"}
        """
        let content = try JSONDecoder().decode(TextContent.self, from: Data(old.utf8))
        #expect(content.alignment == nil)
        #expect(content.verticalAlignment == nil)
        let written = String(data: try JSONEncoder().encode(content), encoding: .utf8) ?? ""
        #expect(!written.contains("alignment"), "no key is written for words nobody has placed")
    }

    @Test("An alignment survives being saved and opened")
    func alignmentRoundTrips() throws {
        let content = TextContent(string: "Hi", alignment: .center, verticalAlignment: .bottom)
        let data = try JSONEncoder().encode(content)
        let back = try JSONDecoder().decode(TextContent.self, from: data)
        #expect(back.alignment == .center)
        #expect(back.verticalAlignment == .bottom)
    }

    // MARK: - Stretching text does something you can see

    @Test("A label told to stretch centres its word in the box it now fills")
    func stretchingCentresTheWords() {
        let text = label()
        var document = plate(text)
        document.setPlacement(id: text.id, horizontal: .stretch)
        #expect(document.layer(id: text.id)?.placement?.horizontal == .stretch)
        #expect(words(document, text.id)?.alignment == .center)
    }

    @Test("A label told to fill the height centres its lines down the box")
    func stretchingDownCentresTheLines() {
        let text = label()
        var document = plate(text)
        document.setPlacement(id: text.id, vertical: .stretch)
        #expect(words(document, text.id)?.verticalAlignment == .middle)
    }

    @Test("Words that were already placed by hand are left where they were put")
    func anExistingAlignmentWins() {
        let text = label(alignment: .right, verticalAlignment: .bottom)
        var document = plate(text)
        document.setPlacement(id: text.id, horizontal: .stretch)
        document.setPlacement(id: text.id, vertical: .stretch)
        #expect(words(document, text.id)?.alignment == .right)
        #expect(words(document, text.id)?.verticalAlignment == .bottom)
    }

    @Test("Coming off stretch leaves the words where stretching put them")
    func unstretchingKeepsTheWords() {
        let text = label()
        var document = plate(text)
        document.setPlacement(id: text.id, horizontal: .stretch)
        document.setPlacement(id: text.id, horizontal: .left)
        #expect(document.layer(id: text.id)?.placement?.horizontal == .left)
        #expect(words(document, text.id)?.alignment == .center,
                "the Align row is the user's now; changing the layout rule does not rewrite it")
    }

    @Test("Any other placement leaves the words alone")
    func onlyStretchMovesTheWords() {
        let text = label()
        var document = plate(text)
        for choice in HorizontalPlacement.allCases where choice != .stretch {
            document.setPlacement(id: text.id, horizontal: choice)
            #expect(words(document, text.id)?.alignment == nil)
        }
    }

    @Test("A picture told to stretch is still just a picture that stretches")
    func stretchingAPictureChangesOnlyItsPlacement() {
        let text = label()
        var document = plate(text)
        guard let back = document.layers.first?.children.first else {
            Issue.record("the plate lost its background")
            return
        }
        document.setPlacement(id: back.id, horizontal: .stretch)
        #expect(document.layer(id: back.id)?.placement?.horizontal == .stretch)
        if case .image = document.layer(id: back.id)?.content {} else {
            Issue.record("the background stopped being a picture")
        }
    }

    // MARK: - Setting it by hand

    @Test("Moving the words never moves the box")
    func alignmentLeavesTheBoxAlone() {
        let text = label()
        var document = plate(text)
        document.setPlacement(id: text.id, horizontal: .stretch)
        let box = document.layer(id: text.id)?.frame
        document.setTextAlignment(id: text.id, TextAlign.left)
        #expect(words(document, text.id)?.alignment == .left)
        #expect(document.layer(id: text.id)?.frame == box)
    }

    @Test("Both axes can be set, and each says its own name")
    func bothAxesAreSettable() {
        let text = label()
        var document = plate(text)
        document.setTextAlignment(id: text.id, TextAlign.right)
        document.setTextAlignment(id: text.id, TextVerticalAlign.bottom)
        #expect(words(document, text.id)?.alignment == .right)
        #expect(words(document, text.id)?.verticalAlignment == .bottom)
        #expect(TextAlign.center.title == "Center")
        #expect(TextVerticalAlign.middle.title == "Middle")
    }

    // MARK: - The button in the Library still reads right

    @Test("A stretched label stays centred in a button dragged wider")
    func aStretchedLabelStaysCentred() {
        let text = label()
        var document = plate(text)
        document.setPlacement(id: text.id, horizontal: .stretch)
        guard let button = document.layers.first else {
            Issue.record("the plate went missing")
            return
        }
        let wider = button.resized(to: CGRect(x: 0, y: 0, width: 256, height: 36))
        let stretched = wider.children.first { $0.name == "Label" }?.frame ?? .null
        // The box now spans everything the label's insets left it, and the word
        // is centred inside that box rather than pinned to its left edge.
        #expect(abs(stretched.minX - 40) < 0.001)
        #expect(abs(stretched.maxX - (256 - 40)) < 0.001)
        #expect(wider.children.first { $0.name == "Label" }?.text?.alignment == .center)
    }
}
