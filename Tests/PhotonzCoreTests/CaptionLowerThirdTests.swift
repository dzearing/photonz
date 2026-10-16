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

    // MARK: - The plate's gradient in the Background well

    /// The violet ramp the mock draws, as the one colour picker reads a
    /// gradient: a straight run at the mock's 120 degrees, violet to lilac.
    func testTheBackgroundWellHoldsTheLowerThirdsWholeGradient() throws {
        let paint = try XCTUnwrap(CaptionLook.preset(.lowerThird).backgroundPaint)
        XCTAssertTrue(paint.isGradient)
        XCTAssertEqual(paint.kind, .linear)
        XCTAssertEqual(paint.angle, 120)
        XCTAssertEqual(paint.orderedStops.map(\.hex), ["#9A5CFFF0", "#C56CFFDB"])
        XCTAssertFalse(try XCTUnwrap(CaptionLook.preset(.caption).backgroundPaint).isGradient,
                       "the Caption plate is one flat colour")
        XCTAssertNil(CaptionLook.preset(.karaoke).backgroundPaint, "and Karaoke has none")
        XCTAssertEqual(CaptionLookControl.allCases.filter(\.holdsGradient), [.background],
                       "only the plate can be a gradient: words, glows and outlines are one colour")
    }

    /// Picking a colour in the picker changes the stop that is picked, so the
    /// other end is still lilac and the plate is still a gradient.
    func testChangingOneStopKeepsThePlateAGradient() throws {
        var look = CaptionLook.preset(.lowerThird)
        var paint = try XCTUnwrap(look.backgroundPaint)
        paint.stops[0].hex = "#5E2BD1F0"
        CaptionLookControl.background.set(.paint(paint), in: &look)
        let kept = try XCTUnwrap(look.backgroundPaint)
        XCTAssertTrue(kept.isGradient)
        XCTAssertEqual(kept.orderedStops.map(\.hex), ["#5E2BD1F0", "#C56CFFDB"])
        XCTAssertNotNil(look.backgroundHex, "a plate is still drawn")
        let layer = try captions(captioned(look: look))
        for cue in layer.children {
            guard case .text(let content) = cue.content else { return XCTFail() }
            XCTAssertEqual(content.platePaint?.orderedStops.map(\.hex), ["#5E2BD1F0", "#C56CFFDB"],
                           "every caption draws the ramp as changed")
        }
    }

    /// Whatever the picker can make of it (another angle, a third stop, a
    /// spreading ramp) is kept, saved and drawn, never quietly dropped.
    func testAnyGradientThePickerMakesIsKeptSavedAndDrawn() throws {
        var look = CaptionLook.preset(.lowerThird)
        let ramp = Paint(hex: "#1A1433", kind: .radial,
                         stops: [GradientStop(hex: "#FF4FD8", position: 0),
                                 GradientStop(hex: "#12C2E9", position: 0.5),
                                 GradientStop(hex: "#1A1433", position: 1)],
                         angle: 45, center: CGPoint(x: 0.2, y: 0.5))
        CaptionLookControl.background.set(.paint(ramp), in: &look)
        XCTAssertEqual(look.backgroundPaint, ramp)
        let data = try JSONEncoder().encode(look)
        XCTAssertEqual(try JSONDecoder().decode(CaptionLook.self, from: data), look)
        let layer = try captions(captioned(look: look))
        guard case .text(let content) = try XCTUnwrap(layer.children.first).content else { return XCTFail() }
        XCTAssertEqual(content.platePaint, ramp)
        let reread = try JSONDecoder().decode(TextContent.self, from: JSONEncoder().encode(content))
        XCTAssertEqual(reread.platePaint, ramp, "a caption saved with it draws it when opened")
    }

    /// The mock's own ramp is written the way it always was, so a look saved
    /// by this build reads the same in the one before it.
    func testTheMocksRampIsStillWrittenAsTwoColours() throws {
        let text = String(decoding: try JSONEncoder().encode(CaptionLook.preset(.lowerThird)), as: UTF8.self)
        XCTAssertTrue(text.contains("backgroundEndHex"))
        XCTAssertFalse(text.contains("backgroundGradient"))
    }

    func testPickingSolidOrNoneInThePickerMakesThePlateFlatOrBare() {
        var look = CaptionLook.preset(.lowerThird)
        CaptionLookControl.background.set(.paint(Paint(hex: "#202020")), in: &look)
        XCTAssertEqual(look.backgroundHex, "#202020")
        XCTAssertNil(look.backgroundEndHex)
        XCTAssertEqual(look.backgroundPaint, Paint(hex: "#202020"))
        CaptionLookControl.background.set(.paint(nil), in: &look)
        XCTAssertNil(look.backgroundPaint)
        XCTAssertNil(look.backgroundHex)
    }

    /// A flat colour dropped on the well is one colour, so the plate takes it.
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
