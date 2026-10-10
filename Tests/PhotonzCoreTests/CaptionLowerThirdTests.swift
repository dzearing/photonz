import CoreGraphics
import Foundation
import XCTest
@testable import PhotonzCore

// The Lower third caption style (`Sources/PhotonzCore/CaptionLook.swift`,
// `docs/design/mocks/pages/video-captions.html`, STYLES.B).
//
// The mock draws a lower third low on the LEFT, inside title safe, no wider
// than about two thirds of the picture, on its own violet plate, in bold.
// Picking it used to change only the weight and the plate's darkness and leave
// the words centred where they were. What is pinned here: where picking it puts
// the Captions layer, that the person's own font and size survive, that the
// plate is the mock's, and that picking another style puts the box back.
final class CaptionLowerThirdTests: XCTestCase {

    private let heard: [TranscribedWord] = [
        TranscribedWord("Capture", startMS: 200, endMS: 700, confidence: 0.9),
        TranscribedWord("the", startMS: 700, endMS: 900, confidence: 0.9),
        TranscribedWord("screen.", startMS: 900, endMS: 1_500, confidence: 0.9),
    ]

    private let size = CGSize(width: 1920, height: 1080)

    private func captioned(look: CaptionLook? = nil) -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: size)
        var clip = Layer(name: "Clip", content: .text(TextContent(string: "picture")),
                         frame: CGRect(origin: .zero, size: size))
        clip.time = LayerTime(inMS: 0, outMS: 6_000)
        document.addLayer(clip)
        document.landCaptions(CaptionCues.cues(from: heard), look: look)
        return document
    }

    private func captions(_ document: PhotonzDocument) throws -> Layer {
        try XCTUnwrap(document.captionsLayers.first)
    }

    /// The title-safe guide drawn over the picture: the line the mock hangs a
    /// lower third's plate from.
    private var safe: CGRect { SafeAreaGuide.title.rect(in: size) }

    // MARK: - The look

    func testTheLowerThirdIsBoldOnTheMocksVioletPlate() {
        let look = CaptionLook.preset(.lowerThird)
        XCTAssertEqual(look.weight, .bold, "the mock's 700")
        XCTAssertEqual(look.backgroundHex, "#9A5CFFF0", "rgba(154,92,255,.94)")
        XCTAssertEqual(look.backgroundEndHex, "#C56CFFDB", "to rgba(197,108,255,.86)")
        XCTAssertEqual(look.alignment, .left)
        XCTAssertNil(look.activeHex, "the mock lights no word in a lower third")
        XCTAssertEqual(look.colorHex, "#FFFFFF")
        XCTAssertNil(CaptionLook.preset(.caption).backgroundEndHex, "every other plate is flat")
    }

    func testEveryCaptionCarriesThePlatesTwoColours() throws {
        let layer = try captions(captioned(look: .preset(.lowerThird)))
        for cue in layer.children {
            guard case .text(let content) = cue.content else { return XCTFail() }
            XCTAssertEqual(content.plateHex, "#9A5CFFF0")
            XCTAssertEqual(content.plateEndHex, "#C56CFFDB")
        }
    }

    func testPickingABackgroundColourMakesThePlateFlat() {
        var look = CaptionLook.preset(.lowerThird)
        CaptionLookControl.background.set(.colour("#202020"), in: &look)
        XCTAssertEqual(look.backgroundHex, "#202020")
        XCTAssertNil(look.backgroundEndHex)
        look = .preset(.lowerThird)
        CaptionLookControl.background.set(.colour(nil), in: &look)
        XCTAssertNil(look.backgroundEndHex, "no plate, no second colour")
    }

    func testALookSavedBeforeTheGradientOpensFlat() throws {
        var look = CaptionLook.preset(.caption)
        look.backgroundEndHex = nil
        let data = try JSONEncoder().encode(look)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("backgroundEnd"))
        XCTAssertEqual(try JSONDecoder().decode(CaptionLook.self, from: data), look)
        let lower = try JSONDecoder().decode(CaptionLook.self,
                                             from: JSONEncoder().encode(CaptionLook.preset(.lowerThird)))
        XCTAssertEqual(lower, .preset(.lowerThird))
    }

    // MARK: - Where it sits

    func testPickingLowerThirdMovesTheCaptionsLowLeftInsideTitleSafe() throws {
        var document = captioned()
        let layer = try captions(document)
        let centred = layer.frame
        document.applyCaptionLook(.preset(.lowerThird), toCaptions: layer.id)
        let box = try captions(document).frame
        XCTAssertEqual(box.minX, safe.minX, accuracy: 0.5, "its plate on the title-safe guide's left edge")
        XCTAssertEqual(box.maxY, centred.maxY, accuracy: 0.5, "on the same floor the captions sat on")
        XCTAssertEqual(box.width, size.width * CaptionLayers.lowerThirdWidth, accuracy: 0.5)
        XCTAssertLessThan(box.midX, size.width / 2, "left of centre")
        XCTAssertGreaterThanOrEqual(box.minY, size.height * 2 / 3, "in the lower third")
        XCTAssertTrue(safe.contains(box), "inside title safe: \(box) in \(safe)")
        XCTAssertTrue(try captions(document).children.allSatisfy { $0.frame.size == box.size },
                      "every cue fills the moved box")
    }

    func testFreshCaptionsWrittenInLowerThirdLandLowLeft() throws {
        let box = try captions(captioned(look: .preset(.lowerThird))).frame
        XCTAssertEqual(box.minX, safe.minX, accuracy: 0.5)
        XCTAssertEqual(box.width, size.width * CaptionLayers.lowerThirdWidth, accuracy: 0.5)
        XCTAssertTrue(safe.contains(box))
    }

    func testThePersonsOwnFontAndSizeComeAlong() throws {
        var mine = CaptionLook.preset(.caption)
        mine.fontName = "Menlo"
        mine.fontSize = 60
        var document = captioned(look: mine)
        let layer = try captions(document)
        var lower = CaptionLook.preset(.lowerThird)
        lower.fontName = mine.fontName
        lower.fontSize = mine.fontSize
        document.applyCaptionLook(lower, toCaptions: layer.id)
        let moved = try captions(document)
        XCTAssertEqual(moved.frame.minX, safe.minX, accuracy: 0.5)
        for cue in moved.children {
            guard case .text(let content) = cue.content else { return XCTFail() }
            XCTAssertEqual(content.fontName, "Menlo")
            XCTAssertEqual(content.fontSize, 60)
        }
        XCTAssertGreaterThanOrEqual(moved.frame.height,
                                    CaptionLayers.band(in: size, lines: 2, fontSize: 60).height - 0.5,
                                    "room for two lines of the person's own size")
    }

    func testSwitchingBackPutsTheCaptionsWhereTheyWere() throws {
        var document = captioned()
        let layer = try captions(document)
        let centred = layer.frame
        document.applyCaptionLook(.preset(.lowerThird), toCaptions: layer.id)
        document.applyCaptionLook(.preset(.caption), toCaptions: layer.id)
        XCTAssertEqual(try captions(document).frame, centred)
    }

    func testABoxSomebodyMovedComesBackToWhereTheyPutIt() throws {
        var document = captioned()
        let layer = try captions(document)
        let mine = CGRect(x: 400, y: 110, width: 1_100, height: 160)
        document.updateLayer(id: layer.id) { $0 = $0.reboxingCaptions(to: mine) }
        document.applyCaptionLook(.preset(.lowerThird), toCaptions: layer.id)
        XCTAssertNotEqual(try captions(document).frame, mine)
        document.applyCaptionLook(.preset(.karaoke), toCaptions: layer.id)
        let back = try captions(document).frame
        XCTAssertEqual(back.minX, mine.minX, accuracy: 0.5)
        XCTAssertEqual(back.width, mine.width, accuracy: 0.5)
        XCTAssertEqual(back.maxY, mine.maxY, accuracy: 0.5, "on the floor it had, sized for its type")
    }

    func testTuningTheLowerThirdLeavesItsBoxAlone() throws {
        var document = captioned(look: .preset(.lowerThird))
        let layer = try captions(document)
        let nudged = layer.frame.offsetBy(dx: 40, dy: -30)
        document.updateLayer(id: layer.id) { $0 = $0.reboxingCaptions(to: nudged) }
        var look = CaptionLook.preset(.lowerThird)
        look.colorHex = "#FFE06A"
        document.applyCaptionLook(look, toCaptions: layer.id)
        XCTAssertEqual(try captions(document).frame, nudged, "a colour is not a move")
    }

    func testLowerThirdWrittenFromScratchGoesBackToTheStandardBand() throws {
        var document = captioned(look: .preset(.lowerThird))
        let layer = try captions(document)
        document.applyCaptionLook(.preset(.caption), toCaptions: layer.id)
        let font = CaptionLook.preset(.caption).resolvedFontSize(in: size)
        XCTAssertEqual(try captions(document).frame, CaptionLayers.defaultBox(in: size, fontSize: font))
    }

    func testWhereItCameFromIsSaved() throws {
        var document = captioned()
        let layer = try captions(document)
        let centred = layer.frame
        document.applyCaptionLook(.preset(.lowerThird), toCaptions: layer.id)
        var opened = try JSONDecoder().decode(PhotonzDocument.self, from: JSONEncoder().encode(document))
        opened.applyCaptionLook(.preset(.caption), toCaptions: layer.id)
        XCTAssertEqual(try captions(opened).frame, centred)
    }

    func testOtherStylesNeverMoveTheBox() throws {
        var document = captioned()
        let layer = try captions(document)
        let mine = CGRect(x: 400, y: 110, width: 1_100, height: 160)
        document.updateLayer(id: layer.id) { $0 = $0.reboxingCaptions(to: mine) }
        document.applyCaptionLook(.preset(.caption), toCaptions: layer.id)
        XCTAssertEqual(try captions(document).frame.minX, mine.minX)
        XCTAssertEqual(try captions(document).frame.width, mine.width)
    }
}
