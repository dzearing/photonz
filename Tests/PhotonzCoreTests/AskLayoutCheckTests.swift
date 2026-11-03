import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// Ask looks over what it laid out before it hands back
/// (`docs/design/ask.md`, "Looking at a layout"): words it cannot read against
/// what is behind them are recoloured, a centred heading drifted off the
/// middle of what sits under it is centred, words stacked onto words are
/// parted, words off the canvas come back on, and what it could not mend is
/// said in one short sentence. It reads the finished document, so it works
/// for any request, never a stored one.
@Suite("Ask looks at a layout before it hands back")
struct AskLayoutCheckTests {

    static let canvas = CGSize(width: 1440, height: 900)

    static func words(_ string: String, _ frame: CGRect, colour: String = "#1C1C1E", size: CGFloat = 16,
                      align: TextAlign? = nil, name: String? = nil) -> Layer {
        var content = TextContent(string: string, fontSize: size, colorHex: colour)
        content.alignment = align
        return Layer(name: name ?? string, content: .text(content), frame: frame)
    }

    static func box(_ name: String, _ frame: CGRect, fill: String?) -> Layer {
        let content = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: "#000000", fillColorHex: fill)
        return Layer(name: name, content: .annotation(content), frame: frame)
    }

    static func review(_ layers: [Layer], before: [Layer] = []) -> (AskLayoutCheck.Review, PhotonzDocument) {
        let was = PhotonzDocument(canvasSize: canvas, layers: before)
        var after = PhotonzDocument(canvasSize: canvas, layers: before + layers)
        let review = AskLayoutCheck.review(after, before: was)
        AskLayoutCheck.apply(review, to: &after)
        return (review, after)
    }

    static func colour(_ name: String, in document: PhotonzDocument) -> String? {
        guard case .text(let content)? = document.layers.first(where: { $0.name == name })?.content else { return nil }
        return content.colorHex
    }

    static func reads(_ name: String, on ground: String, in document: PhotonzDocument) -> Bool {
        guard let ink = colour(name, in: document).flatMap({ RGBA(hex: $0) }), let back = RGBA(hex: ground) else { return false }
        return RGBA.lightnessContrast(text: ink, on: back) >= AgentNewComponent.leastWordLightness
    }

    static func frame(_ name: String, in document: PhotonzDocument) -> CGRect? {
        document.layers.first(where: { $0.name == name })?.frame
    }

    // MARK: Words that cannot be read

    @Test func darkWordsOnABlueButtonTurnWhite() {
        // The manager's run on 2026-10-24: add_shape fill #007AFF, then
        // add_text 'Choose Starter' with no colour, dark on blue.
        let (review, after) = Self.review([
            Self.box("Button", CGRect(x: 160, y: 592, width: 280, height: 48), fill: "#007AFF"),
            Self.words("Choose Starter", CGRect(x: 160, y: 606, width: 280, height: 20), align: .center),
        ])
        #expect(Self.colour("Choose Starter", in: after) == "#FFFFFF")
        #expect(review.sentence == nil)
    }

    @Test func whiteWordsOnTheWhiteCanvasTurnDark() {
        let (_, after) = Self.review([Self.words("Pricing", CGRect(x: 100, y: 100, width: 120, height: 40), colour: "#FFFFFF")])
        #expect(Self.reads("Pricing", on: "#FFFFFF", in: after))
    }

    @Test func readableWordsKeepTheirColour() {
        let (review, after) = Self.review([
            Self.box("Card", CGRect(x: 100, y: 100, width: 300, height: 400), fill: "#4F46E5"),
            Self.words("Pro", CGRect(x: 140, y: 140, width: 60, height: 24), colour: "#FFFFFF"),
            Self.words("Most popular", CGRect(x: 140, y: 110, width: 90, height: 16), colour: "#C7D2FE"),
        ])
        #expect(Self.colour("Pro", in: after) == "#FFFFFF")
        #expect(Self.colour("Most popular", in: after) == "#C7D2FE")
        #expect(review.fixes.isEmpty)
    }

    @Test func wordsAreReadAgainstTheTopmostFilledBoxUnderThem() {
        // White words on a white button that sits on an indigo card: the
        // button is what they are read against.
        let (_, after) = Self.review([
            Self.box("Card", CGRect(x: 100, y: 100, width: 300, height: 400), fill: "#4F46E5"),
            Self.box("Button", CGRect(x: 140, y: 420, width: 220, height: 48), fill: "#FFFFFF"),
            Self.words("Choose Pro", CGRect(x: 140, y: 434, width: 220, height: 20), colour: "#FFFFFF", align: .center),
        ])
        #expect(Self.colour("Choose Pro", in: after) != "#FFFFFF")
    }

    @Test func anOutlineIsLookedThrough() {
        let (_, after) = Self.review([
            Self.box("Card", CGRect(x: 100, y: 100, width: 300, height: 400), fill: "#111111"),
            Self.box("Ring", CGRect(x: 120, y: 120, width: 200, height: 100), fill: nil),
            Self.words("Hello", CGRect(x: 140, y: 140, width: 60, height: 24), colour: "#000000"),
        ])
        #expect(Self.reads("Hello", on: "#111111", in: after))
    }

    @Test func wordsOnAPictureAreLeftAlone() {
        // What a photo looks like under the words is not known here.
        let picture = Layer(name: "Photo", content: .image(ImageRef(pixelSize: CGSize(width: 10, height: 10))),
                            frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        let (review, after) = Self.review([
            picture,
            Self.words("Caption", CGRect(x: 40, y: 40, width: 80, height: 20), colour: "#FFFFFF"),
        ])
        #expect(Self.colour("Caption", in: after) == "#FFFFFF")
        #expect(review.fixes.isEmpty)
    }

    @Test func onlyWhatAskMadeIsTouched() {
        let theirs = Self.words("Theirs", CGRect(x: 100, y: 100, width: 80, height: 20), colour: "#FFFFFF")
        let (review, after) = Self.review([Self.words("Mine", CGRect(x: 100, y: 300, width: 80, height: 20))],
                                          before: [theirs])
        #expect(Self.colour("Theirs", in: after) == "#FFFFFF")
        #expect(review.fixes.isEmpty)
    }

    @Test func theDefaultInkOnABlueButtonIsWhite() {
        let document = PhotonzDocument(canvasSize: Self.canvas, layers: [
            Self.box("Button", CGRect(x: 160, y: 592, width: 280, height: 48), fill: "#007AFF"),
        ])
        #expect(AskLayoutCheck.defaultInk(at: CGRect(x: 200, y: 606, width: 100, height: 20), in: document) == "#FFFFFF")
        #expect(AskLayoutCheck.defaultInk(at: CGRect(x: 200, y: 106, width: 100, height: 20), in: document)
                == TextContent.agentDefaultColour)
    }

    @Test func darkWordsOnALightColourStayDark() {
        // White does not read on a light green, so dark words are right there.
        let (review, _) = Self.review([
            Self.box("Chip", CGRect(x: 100, y: 100, width: 200, height: 40), fill: "#A8E6A1"),
            Self.words("New", CGRect(x: 120, y: 110, width: 40, height: 20)),
        ])
        #expect(review.fixes.isEmpty)
    }

    // MARK: A centred heading

    @Test func aCentredHeadingDriftedOffTheRowUnderItIsCentred() {
        // The pricing walk on 2026-11-03: "Pricing" set centred at x 592 with
        // no width, so its box hugged its words left of the cards' middle.
        let cards = (0..<3).map { Self.box("Card \($0)", CGRect(x: 120 + CGFloat($0) * 420, y: 240, width: 360, height: 440), fill: "#F2F2F7") }
        let (review, after) = Self.review([
            Self.words("Pricing", CGRect(x: 592, y: 96, width: 160, height: 58), size: 48, align: .center),
            Self.words("Simple plans that grow with your team.", CGRect(x: 520, y: 160, width: 330, height: 22), align: .center),
        ] + cards)
        #expect(Self.frame("Pricing", in: after)?.midX == 720)
        #expect(Self.frame("Simple plans that grow with your team.", in: after)?.midX == 720)
        #expect(Self.frame("Pricing", in: after)?.minY == 96)
        #expect(review.notes.contains { $0.contains("centred Pricing") })
    }

    @Test func aCentredLabelIsCentredOnItsButton() {
        let (_, after) = Self.review([
            Self.box("Button", CGRect(x: 160, y: 592, width: 280, height: 48), fill: "#E5E7EB"),
            Self.words("Choose", CGRect(x: 250, y: 606, width: 80, height: 20), align: .center),
        ])
        #expect(Self.frame("Choose", in: after)?.midX == 300)
    }

    @Test func leftAlignedWordsAreNotCentred() {
        let (_, after) = Self.review([
            Self.box("Card", CGRect(x: 100, y: 100, width: 300, height: 400), fill: "#F2F2F7"),
            Self.words("Starter", CGRect(x: 140, y: 140, width: 70, height: 24)),
        ])
        #expect(Self.frame("Starter", in: after)?.minX == 140)
    }

    @Test func aHeadingFarFromTheMiddleIsMeantThere() {
        // A centred word over the left column of a wide row is not drifted:
        // a quarter of the row's width or more off its middle is left alone.
        let row = Self.box("Row", CGRect(x: 100, y: 300, width: 1200, height: 200), fill: "#F2F2F7")
        let (_, after) = Self.review([Self.words("Left", CGRect(x: 160, y: 200, width: 80, height: 30), align: .center), row])
        #expect(Self.frame("Left", in: after)?.minX == 160)
    }

    // MARK: Words on words

    @Test func wordsStackedOnWordsAreParted() {
        let (review, after) = Self.review([
            Self.box("Card", CGRect(x: 100, y: 100, width: 300, height: 400), fill: "#FFFFFF"),
            Self.words("$12", CGRect(x: 140, y: 140, width: 80, height: 53), size: 44),
            Self.words("per month", CGRect(x: 140, y: 180, width: 70, height: 17), size: 14),
            Self.words("For individuals", CGRect(x: 140, y: 200, width: 120, height: 17), size: 14),
        ])
        let price = Self.frame("$12", in: after) ?? .zero
        let per = Self.frame("per month", in: after) ?? .zero
        let line = Self.frame("For individuals", in: after) ?? .zero
        #expect(per.minY >= price.maxY)
        #expect(line.minY >= per.maxY)
        #expect(per.minX == 140)
        #expect(review.sentence == nil)
    }

    @Test func wordsThatCannotBePartedInsideTheirBoxAreOwnedUpTo() {
        // Parting would push the lower words out of the bottom of their card.
        let (review, after) = Self.review([
            Self.box("Card", CGRect(x: 100, y: 100, width: 300, height: 100), fill: "#FFFFFF"),
            Self.words("Top", CGRect(x: 140, y: 120, width: 80, height: 60)),
            Self.words("Under", CGRect(x: 140, y: 150, width: 80, height: 40)),
        ])
        #expect(Self.frame("Under", in: after)?.minY == 150)
        #expect(review.sentence == AskLayoutCheck.overlapSentence)
    }

    @Test func wordsSideBySideThatTouchAreOwnedUpTo() {
        let (review, _) = Self.review([
            Self.words("Left words", CGRect(x: 100, y: 100, width: 200, height: 20)),
            Self.words("Right words", CGRect(x: 250, y: 100, width: 200, height: 20)),
        ])
        #expect(review.sentence == AskLayoutCheck.overlapSentence)
    }

    // MARK: Off the canvas

    @Test func wordsHangingOffTheCanvasComeBackOn() {
        let (_, after) = Self.review([Self.words("Edge", CGRect(x: 1400, y: 880, width: 100, height: 30))])
        let frame = Self.frame("Edge", in: after) ?? .zero
        #expect(frame.maxX <= Self.canvas.width)
        #expect(frame.maxY <= Self.canvas.height)
    }

    @Test func aVideoIsLeftAlone() {
        let was = PhotonzDocument(canvasSize: Self.canvas)
        var after = was
        after.durationMS = 10_000
        after.layers = [Self.words("Title", CGRect(x: 600, y: 400, width: 200, height: 60), colour: "#FFFFFF", align: .center)]
        #expect(AskLayoutCheck.review(after, before: was).fixes.isEmpty)
    }

    // MARK: A clean layout

    @Test func aTidySectionIsLeftAsItWas() {
        let layers = [
            Self.words("Pricing", CGRect(x: 640, y: 96, width: 160, height: 58), size: 48, align: .center),
            Self.box("Card", CGRect(x: 120, y: 240, width: 1200, height: 440), fill: "#FFFFFF"),
            Self.words("Starter", CGRect(x: 160, y: 280, width: 80, height: 24)),
            Self.box("Button", CGRect(x: 160, y: 592, width: 280, height: 48), fill: "#E5E7EB"),
            Self.words("Choose", CGRect(x: 160, y: 606, width: 280, height: 20), align: .center),
        ]
        let (review, after) = Self.review(layers)
        #expect(review.fixes.isEmpty)
        #expect(review.sentence == nil)
        #expect(after.layers == layers)
    }
}
