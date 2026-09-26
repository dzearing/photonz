import CoreGraphics
import Foundation
import XCTest
@testable import PhotonzCore

// Captions as ONE layer (`Sources/PhotonzCore/CaptionLook.swift`).
//
// The user, 2026-09-25: "I expected a layer of type Captions which has its own
// properties, like a rectangle ... easy to position like any other layer. Its
// position shouldn't be some proprietary setting you set in the pane." So the
// Captions layer has an ordinary box that every cue fills, its own look, and
// no Bottom/Middle/Top setting. What is pinned here: where a fresh one lands,
// that moving or resizing the one box moves every caption, that each Captions
// layer is its own, and that a document saved as a group of cues opens as one.
final class CaptionsLayerTests: XCTestCase {

    private let heard: [TranscribedWord] = [
        TranscribedWord("Capture", startMS: 200, endMS: 700, confidence: 0.9),
        TranscribedWord("the", startMS: 700, endMS: 900, confidence: 0.9),
        TranscribedWord("screen.", startMS: 900, endMS: 1_500, confidence: 0.9),
        TranscribedWord("Design", startMS: 2_600, endMS: 3_100, confidence: 0.9),
        TranscribedWord("it.", startMS: 3_100, endMS: 3_600, confidence: 0.9),
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

    private func captionsLayer(_ document: PhotonzDocument) throws -> Layer {
        try XCTUnwrap(document.captionsLayers.first)
    }

    // MARK: - One layer

    func testCaptionsLandAsOneCaptionsLayerCarryingItsOwnLook() throws {
        let document = captioned(look: .preset(.karaoke))
        XCTAssertEqual(document.captionsLayers.count, 1)
        let layer = try captionsLayer(document)
        XCTAssertTrue(layer.isCaptionsLayer)
        XCTAssertEqual(layer.name, "Captions")
        XCTAssertEqual(layer.captionsLook, .preset(.karaoke), "the look lives on the layer")
        XCTAssertEqual(layer.children.count, CaptionCues.cues(from: heard).count,
                       "the transcript: every cue, with its words and times")
        XCTAssertEqual(ClipLine.kind(of: layer), "Captions")
    }

    func testAFreshCaptionsLayerSitsCentredInTheLowerThirdInsideTitleSafe() throws {
        let box = try captionsLayer(captioned()).frame
        XCTAssertEqual(box.midX, size.width / 2, accuracy: 0.5, "centred")
        XCTAssertGreaterThanOrEqual(box.minY, size.height * 2 / 3, "in the lower third")
        let safe = CGRect(origin: .zero, size: size)
            .insetBy(dx: size.width * CaptionLayers.titleSafeInset,
                     dy: size.height * CaptionLayers.titleSafeInset)
        XCTAssertTrue(safe.contains(box), "inside title-safe: \(box) in \(safe)")
    }

    func testEveryCueFillsTheLayersBox() throws {
        let document = captioned()
        let layer = try captionsLayer(document)
        for cue in document.captionLayers {
            XCTAssertEqual(document.canvasFrame(of: cue.id), layer.frame)
        }
        XCTAssertEqual(layer.localBounds, layer.frame, "the box you select is the box they fill")
    }

    // MARK: - An ordinary frame

    func testMovingTheBoxOnceMovesEveryCaption() throws {
        var document = captioned()
        let layer = try captionsLayer(document)
        let top = CGRect(x: layer.frame.minX, y: 120, width: layer.frame.width,
                         height: layer.frame.height)
        document.updateLayer(id: layer.id) { $0 = $0.resized(to: top) }
        for cue in document.captionLayers {
            XCTAssertEqual(document.canvasFrame(of: cue.id), top)
        }
    }

    func testResizingSetsTheWrapWidthAndKeepsTheType() throws {
        var document = captioned()
        let layer = try captionsLayer(document)
        let fontBefore = document.captionLayers[0].text?.fontSize
        let narrow = CGRect(x: 600, y: 700, width: 500, height: 200)
        document.updateLayer(id: layer.id) { $0 = $0.resized(to: narrow) }
        XCTAssertEqual(try captionsLayer(document).frame, narrow)
        for cue in document.captionLayers {
            XCTAssertEqual(cue.frame, CGRect(origin: .zero, size: narrow.size))
            XCTAssertEqual(cue.text?.fontSize, fontBefore, "a box is a wrap width, not a zoom")
        }
    }

    func testThereIsNoPositionSettingAnyMore() throws {
        let json = """
        {"preset":"caption","fontName":"SF Pro","weight":"semibold","colorHex":"#FFFFFF",
         "position":"top","alignment":"center"}
        """
        let look = try JSONDecoder().decode(CaptionLook.self, from: Data(json.utf8))
        XCTAssertEqual(look.fontName, "SF Pro", "an old look still opens")
        let encoded = try String(decoding: JSONEncoder().encode(look), as: UTF8.self)
        XCTAssertFalse(encoded.contains("position"))
    }

    // MARK: - Its own look

    func testALookDressesOnlyItsOwnLayerAndKeepsTheBox() throws {
        var document = captioned()
        let first = try captionsLayer(document)
        let copy = try XCTUnwrap(document.duplicateLayer(id: first.id))
        let moved = CGRect(x: 300, y: 150, width: 900, height: 140)
        document.updateLayer(id: copy.id) { $0 = $0.resized(to: moved) }

        var look = CaptionLook.preset(.caption)
        look.fontName = "Avenir Next"
        document.applyCaptionLook(look, toCaptions: copy.id)

        let dressed = try XCTUnwrap(document.layer(id: copy.id))
        XCTAssertEqual(dressed.captionsLook, look)
        XCTAssertEqual(dressed.frame, moved, "restyling never moves the box")
        XCTAssertTrue(dressed.children.allSatisfy { $0.text?.fontName == "Avenir Next" })
        XCTAssertTrue(dressed.children.allSatisfy { $0.frame.size == moved.size })
        let untouched = try XCTUnwrap(document.layer(id: first.id))
        XCTAssertTrue(untouched.children.allSatisfy { $0.text?.fontName == "SF Pro" },
                      "the other Captions layer keeps its own look")
        XCTAssertEqual(untouched.frame, first.frame, "and its own place")
    }

    func testBiggerTypeGrowsTheBoxUpFromItsFloorSoTwoLinesStillFit() throws {
        var document = captioned()
        let layer = try captionsLayer(document)
        var look = try XCTUnwrap(layer.captionsLook)
        look.fontSize = 64
        document.applyCaptionLook(look, toCaptions: layer.id)
        let box = try captionsLayer(document).frame
        XCTAssertEqual(box.height, CaptionLayers.band(in: size, lines: 2, fontSize: 64).height, accuracy: 0.5)
        XCTAssertEqual(box.maxY, layer.frame.maxY, accuracy: 0.5, "the words keep their floor")
        XCTAssertEqual(box.width, layer.frame.width, "the wrap width is the person's")
        XCTAssertTrue(document.captionLayers.allSatisfy { $0.frame.size == box.size })
    }

    func testSeveralCaptionsLayersArePositionedIndependently() throws {
        var document = captioned()
        let first = try captionsLayer(document)
        let copy = try XCTUnwrap(document.duplicateLayer(id: first.id))
        document.updateLayer(id: copy.id) {
            $0 = $0.resized(to: CGRect(x: 200, y: 100, width: 800, height: 120))
        }
        XCTAssertEqual(document.captionsLayers.count, 2)
        XCTAssertEqual(document.layer(id: first.id)?.frame, first.frame)
        XCTAssertEqual(document.layer(id: copy.id)?.frame.origin, CGPoint(x: 200, y: 100))
    }

    func testWritingAgainKeepsTheBoxAndTheLookSomebodyChose() throws {
        var document = captioned()
        let layer = try captionsLayer(document)
        let top = CGRect(x: 400, y: 110, width: 1_100, height: 160)
        document.updateLayer(id: layer.id) { $0 = $0.resized(to: top) }
        document.applyCaptionLook(.preset(.lowerThird), toCaptions: layer.id)

        document.landCaptions(CaptionCues.cues(from: heard))
        XCTAssertEqual(document.captionsLayers.count, 1, "written again, not laid over")
        let again = try captionsLayer(document)
        XCTAssertEqual(again.id, layer.id)
        XCTAssertEqual(again.frame, top)
        XCTAssertEqual(again.captionsLook, .preset(.lowerThird))
        XCTAssertTrue(again.children.allSatisfy { $0.frame.size == top.size })
    }

    func testClearingTakesTheWholeLayerAway() {
        var document = captioned()
        document.clearCaptions()
        XCTAssertTrue(document.captionsLayers.isEmpty)
        XCTAssertFalse(document.hasCaptions)
    }

    // MARK: - Opening an older document

    func testAGroupOfCuesSavedBeforeOpensAsOneCaptionsLayer() throws {
        // What the app wrote before: a group at the origin holding cues in
        // canvas space, the look on the document, placed by a Position.
        var legacy = PhotonzDocument(canvasSize: size)
        var clip = Layer(name: "Clip", content: .text(TextContent(string: "picture")),
                         frame: CGRect(origin: .zero, size: size))
        clip.time = LayerTime(inMS: 0, outMS: 6_000)
        legacy.addLayer(clip)
        let band = CGRect(x: 192, y: 108, width: 1_536, height: 126)
        let cues = CaptionCues.cues(from: heard).map { cue -> Layer in
            var layer = Layer(name: CaptionLayers.name(for: cue),
                              content: .text(TextContent(string: cue.text, fontName: "Menlo")),
                              frame: band)
            layer.time = LayerTime(inMS: cue.inMS, outMS: cue.outMS)
            layer.captionWords = cue.words
            return layer
        }
        legacy.addLayer(Layer(name: "Captions", content: .group(GroupContent(children: cues)),
                              frame: .zero))
        var look = CaptionLook.preset(.lowerThird)
        look.fontName = "Menlo"
        legacy.captionLook = look

        var data = try JSONEncoder().encode(legacy)
        // Stored the way an older build stored it: no look on the group.
        var text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("\"captions\""))
        text = text.replacingOccurrences(of: "\"fontName\":\"Menlo\",", with: "\"fontName\":\"Menlo\",\"position\":\"top\",")
        data = Data(text.utf8)

        let opened = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        XCTAssertEqual(opened.captionsLayers.count, 1)
        let layer = try captionsLayer(opened)
        XCTAssertEqual(layer.frame, band, "it stays where it was on the picture")
        XCTAssertEqual(layer.captionsLook?.fontName, "Menlo")
        XCTAssertEqual(layer.captionsLook?.preset, .lowerThird)
        XCTAssertEqual(opened.captionCues, legacy.captionCues, "same words, same times")
        for cue in opened.captionLayers {
            XCTAssertEqual(opened.canvasFrame(of: cue.id), band)
        }
    }

    func testACaptionsLayerSavesAndOpensUnchanged() throws {
        var document = captioned(look: .preset(.karaoke))
        let layer = try captionsLayer(document)
        document.updateLayer(id: layer.id) {
            $0 = $0.resized(to: CGRect(x: 100, y: 100, width: 700, height: 150))
        }
        let back = try JSONDecoder().decode(PhotonzDocument.self,
                                            from: JSONEncoder().encode(document))
        XCTAssertEqual(back.layers, document.layers)
    }
}
