import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The text tool holding a saved style, so the NEXT block typed follows the
/// name instead of merely matching the type behind it.
///
/// The colour half of the same idea is `ToolColorStyleArmingTests`: a tool
/// remembers a name beside the paint it stood for, and the document has the
/// last word every time something is drawn.
@Suite("The text tool holding a style")
struct ToolTextStyleArmingTests {

    private let heading = TextTreatment(fontName: "Georgia", fontSize: 32,
                                        weight: .bold, colorHex: "#112233")

    private func text(_ string: String = "Hello",
                      treatment: TextTreatment) -> Layer {
        Layer(name: "Text",
              content: .text(TextContent(string: string, fontName: treatment.fontName,
                                         fontSize: treatment.fontSize,
                                         colorHex: treatment.colorHex,
                                         weight: treatment.weight)),
              frame: CGRect(x: 0, y: 0, width: 120, height: 40))
    }

    private func document() -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: [])
    }

    // MARK: - Picking a style up and putting it down

    @Test func armingTakesOnTheTypeAndTheNameBehindIt() {
        var styles = TextStyles()
        let id = UUID()
        styles.arm(heading, styleID: id)
        #expect(styles.styleID == id)
        #expect(styles.treatment == heading)
        #expect(styles.content(string: "Hi") == TextContent(string: "Hi", fontName: "Georgia",
                                                            fontSize: 32, colorHex: "#112233",
                                                            weight: .bold))
    }

    @Test func settingTheTypeByHandLetsGoOfTheName() {
        // The same rule the Style row promises in words before the click:
        // changing the font, size, weight or colour takes text off its style.
        for change in [{ (s: inout TextStyles) in s.fontName = "SF Pro" },
                       { (s: inout TextStyles) in s.fontSize = 48 },
                       { (s: inout TextStyles) in s.weight = .regular },
                       { (s: inout TextStyles) in s.colorHex = "#FF3B30" }] {
            var styles = TextStyles()
            styles.arm(heading, styleID: UUID())
            change(&styles)
            #expect(styles.styleID == nil)
        }
    }

    @Test func settingTheTypeToWhatItAlreadyIsKeepsTheName() {
        // Panels write their bindings back constantly; a set that changes
        // nothing must not quietly drop the style.
        var styles = TextStyles()
        let id = UUID()
        styles.arm(heading, styleID: id)
        styles.fontName = heading.fontName
        styles.fontSize = heading.fontSize
        styles.weight = heading.weight
        styles.colorHex = heading.colorHex
        #expect(styles.styleID == id)
    }

    @Test func lettingGoKeepsTheTypeItWasSetIn() {
        var styles = TextStyles()
        styles.arm(heading, styleID: UUID())
        styles.letGoOfStyle()
        #expect(styles.styleID == nil)
        #expect(styles.treatment == heading)
    }

    @Test func adoptingTextTakesOnTheStyleItWears() {
        // Re-editing a heading arms the tool with the heading's style, so the
        // next block typed carries on where that one left off.
        var styles = TextStyles()
        let id = UUID()
        let layer = text(treatment: heading)
        styles.adopt(layer.text!, styleID: id)
        #expect(styles.styleID == id)
        #expect(styles.treatment == heading)
    }

    @Test func adoptingTextOfItsOwnLetsGo() {
        var styles = TextStyles()
        styles.arm(heading, styleID: UUID())
        styles.adopt(TextContent(string: "plain"))
        #expect(styles.styleID == nil)
    }

    @Test func settingWordsInATreatmentLeavesTheWordsAlone() {
        var content = TextContent(string: "Hello")
        content.alignment = .center
        content.setTreatment(heading)
        #expect(content.string == "Hello")
        #expect(content.alignment == .center)
        #expect(TextTreatment(content) == heading)
    }

    // MARK: - The document has the last word

    @Test func theTypeComesFromTheDocumentRatherThanTheCopyTheToolHolds() {
        var doc = document()
        let id = doc.addTextStyle(name: "Heading", treatment: heading)
        var styles = TextStyles()
        styles.arm(heading, styleID: id)
        // Somebody edits the style after the tool picked it up.
        var grown = heading
        grown.fontSize = 48
        _ = doc.setTextStyle(styleID: id, treatment: grown)
        #expect(doc.armedTextTreatment(styles) == grown)
    }

    @Test func aToolHoldingNothingAsksTheDocumentNothing() {
        let doc = document()
        #expect(doc.armedTextTreatment(TextStyles()) == nil)
    }

    @Test func aDocumentThatNeverHeardOfTheStyleHasNoTypeToGive() {
        // The held id is a preference: it outlives the document it came from.
        let doc = document()
        var styles = TextStyles()
        styles.arm(heading, styleID: UUID())
        #expect(doc.armedTextTreatment(styles) == nil)
    }

    // MARK: - The block that comes out

    @Test func aFreshBlockWearsTheStyleTheToolHolds() throws {
        var doc = document()
        let id = doc.addTextStyle(name: "Heading", treatment: heading)
        var styles = TextStyles()
        styles.arm(heading, styleID: id)
        let worn = doc.wearingArmedTextStyle(text(treatment: heading), styles: styles)
        #expect(worn.textStyleID == id)
        #expect(worn.textTreatment == heading)
    }

    @Test func aBlockIsSetInTheStyleAsItIsNow() throws {
        // Type the tool picked up an hour ago is not what the name means now.
        var doc = document()
        let id = doc.addTextStyle(name: "Heading", treatment: heading)
        var styles = TextStyles()
        styles.arm(heading, styleID: id)
        var grown = heading
        grown.fontSize = 48
        _ = doc.setTextStyle(styleID: id, treatment: grown)
        let worn = doc.wearingArmedTextStyle(text(treatment: heading), styles: styles)
        #expect(worn.textTreatment == grown)
    }

    @Test func aBlockFromAToolHoldingNothingIsUntouched() {
        var doc = document()
        _ = doc.addTextStyle(name: "Heading", treatment: heading)
        let plain = text(treatment: heading)
        #expect(doc.wearingArmedTextStyle(plain, styles: TextStyles()) == plain)
    }

    @Test func aBlockTypedInAnotherDocumentIsUntouched() {
        let doc = document()
        var styles = TextStyles()
        styles.arm(heading, styleID: UUID())
        let plain = text(treatment: heading)
        #expect(doc.wearingArmedTextStyle(plain, styles: styles) == plain)
    }

    @Test func aShapeIsNotDressedByATextStyle() {
        var doc = document()
        let id = doc.addTextStyle(name: "Heading", treatment: heading)
        var styles = TextStyles()
        styles.arm(heading, styleID: id)
        let box = Layer(name: "Box",
                        content: .annotation(AnnotationContent(shape: .rectangle)),
                        frame: CGRect(x: 0, y: 0, width: 60, height: 30))
        #expect(doc.wearingArmedTextStyle(box, styles: styles) == box)
    }

    @Test func theBlockSurvivesTheSafetyNetThatBreaksStaleClaims() {
        // `reconcileTextStyles` runs after every edit and lets go of any text
        // that has drifted from its style. A block dressed as it is typed has
        // not drifted, so its name must survive the very next edit.
        var doc = document()
        let id = doc.addTextStyle(name: "Heading", treatment: heading)
        var styles = TextStyles()
        styles.arm(heading, styleID: id)
        doc.addLayer(doc.wearingArmedTextStyle(text(treatment: heading), styles: styles))
        #expect(doc.reconcileTextStyles() == 0)
        #expect(doc.layers.last?.textStyleID == id)
    }

    @Test func aStyleEditReachesTheBlockTypedAfterIt() {
        // The whole point: a block that merely MATCHED would stay 32pt.
        var doc = document()
        let id = doc.addTextStyle(name: "Heading", treatment: heading)
        var styles = TextStyles()
        styles.arm(heading, styleID: id)
        doc.addLayer(doc.wearingArmedTextStyle(text(treatment: heading), styles: styles))
        var grown = heading
        grown.fontSize = 48
        #expect(doc.setTextStyle(styleID: id, treatment: grown) == 1)
        #expect(doc.layers.last?.textTreatment == grown)
    }

    // MARK: - What the preference writes

    @Test func prefsWrittenBeforeStylesExistedStillDecode() throws {
        let legacy = Data("""
        {"fontName":"Georgia","fontSize":32,"weight":"bold","colorHex":"#112233"}
        """.utf8)
        let decoded = try JSONDecoder().decode(TextStyles.self, from: legacy)
        #expect(decoded.styleID == nil)
        #expect(decoded.treatment == heading)
    }

    @Test func theHeldNameRidesThroughAnEncodeAndBack() throws {
        var styles = TextStyles()
        let id = UUID()
        styles.arm(heading, styleID: id)
        let decoded = try JSONDecoder().decode(TextStyles.self,
                                               from: JSONEncoder().encode(styles))
        #expect(decoded == styles)
        #expect(decoded.styleID == id)
    }

    @Test func aToolHoldingNothingWritesWhatItAlwaysWrote() throws {
        let data = try JSONEncoder().encode(TextStyles())
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["styleID"] == nil)
    }
}
