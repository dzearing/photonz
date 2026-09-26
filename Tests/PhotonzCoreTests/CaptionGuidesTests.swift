import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// What the captions mock draws round the captions and not in them
/// (`CaptionGuides.swift`, `pages/video-captions.html`): the title-safe and
/// action-safe guides over the picture, the AUTO · EN badge, and the bar over
/// the Captions track. Written before the code.
@Suite("Safe-area guides, the Auto badge and the Caption track bar")
struct CaptionGuidesTests {

    static let hd = CGSize(width: 1920, height: 1080)

    // MARK: - Safe areas

    @Test func titleSafeIsNinetyPerCentOfThePictureCentred() {
        let rect = SafeAreaGuide.title.rect(in: Self.hd)
        #expect(abs(rect.width - 1728) < 0.01)
        #expect(abs(rect.height - 972) < 0.01)
        #expect(abs(rect.midX - 960) < 0.01 && abs(rect.midY - 540) < 0.01)
    }

    @Test func actionSafeIsNinetyThreePerCentAndHoldsTitleSafe() {
        let action = SafeAreaGuide.action.rect(in: Self.hd)
        #expect(abs(action.width - 1920 * 0.93) < 0.01)
        #expect(abs(action.height - 1080 * 0.93) < 0.01)
        #expect(action.contains(SafeAreaGuide.title.rect(in: Self.hd)))
    }

    @Test func theGuidesAreLabelledAsTheMockLabelsThem() {
        #expect(SafeAreaGuide.action.label == "Action safe · 93%")
        #expect(SafeAreaGuide.title.label == "Title safe · 90%")
        #expect(SafeAreaGuide.allCases == [.action, .title], "outer first, the order they are drawn")
    }

    @Test func aFreshCaptionsLayerSitsInsideTitleSafe() {
        let font = CaptionLayers.fontSize(in: Self.hd)
        let box = CaptionLayers.defaultBox(in: Self.hd, fontSize: font)
        #expect(SafeAreaGuide.title.rect(in: Self.hd).contains(box))
    }

    // MARK: - The Auto badge

    @Test func theBadgeSaysAutoAndTheLanguage() {
        #expect(CaptionBadge.text(language: "en-US") == "Auto · en")
        #expect(CaptionBadge.text(language: "es_MX") == "Auto · es")
        #expect(CaptionBadge.text(language: "ja") == "Auto · ja")
        #expect(CaptionBadge.text(language: "") == "Auto")
    }

    // MARK: - The Caption track bar

    @Test func theBarReadsThePlayheadOverTheLength() {
        #expect(CaptionTrackBar.time(atMS: 1_300, ofMS: 6_000) == "1.30s / 6.00s")
        #expect(CaptionTrackBar.time(atMS: 0, ofMS: 125_400) == "0.00s / 125.40s")
    }

    @Test func theActiveWordIsTheOneBeingSaid() {
        let words = [
            TranscribedWord("Capture", startMS: 200, endMS: 700, confidence: 0.9),
            TranscribedWord("the", startMS: 700, endMS: 900, confidence: 0.9),
            TranscribedWord("screen.", startMS: 900, endMS: 1_500, confidence: 0.9),
        ]
        #expect(CaptionTrackBar.word(atMS: 750, in: words)?.text == "the")
        #expect(CaptionTrackBar.word(atMS: 700, in: words)?.text == "the", "a word starts where the last ends")
        #expect(CaptionTrackBar.word(atMS: 100, in: words) == nil)
        #expect(CaptionTrackBar.word(atMS: 1_500, in: words) == nil)
    }

    @Test func theBarsWordsAreLabelsNotSentences() {
        for label in [CaptionTrackBar.title, CaptionTrackBar.mode, CaptionTrackBar.activeWord,
                      SafeAreaGuide.title.label, SafeAreaGuide.action.label] {
            #expect(label.count <= 30)
            #expect(!label.contains("."))
        }
    }

    // MARK: - Reset

    static func captioned() -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: hd)
        var clip = Layer(name: "Clip", content: .text(TextContent(string: "picture")),
                         frame: CGRect(origin: .zero, size: hd))
        clip.time = LayerTime(inMS: 0, outMS: 6_000)
        document.addLayer(clip)
        document.landCaptions(CaptionCues.cues(from: [
            TranscribedWord("Capture", startMS: 200, endMS: 700, confidence: 0.9),
            TranscribedWord("the", startMS: 700, endMS: 900, confidence: 0.9),
            TranscribedWord("screen.", startMS: 900, endMS: 1_500, confidence: 0.9),
        ]))
        return document
    }

    @Test func resetPutsTheLookAndTheBoxBackAndKeepsTheWords() throws {
        var document = Self.captioned()
        let layer = try #require(document.captionsLayers.first)
        let fresh = layer.frame
        let words = document.captionCues.map(\.text)
        document.applyCaptionLook(.preset(.karaoke), toCaptions: layer.id)
        document.updateLayer(id: layer.id) { $0.frame = CGRect(x: 40, y: 40, width: 600, height: 200) }

        document.resetCaptions(layer.id)

        let reset = try #require(document.layer(id: layer.id))
        #expect(reset.captionsLook == .standard)
        #expect(reset.frame == fresh)
        #expect(reset.children.allSatisfy { $0.frame.size == fresh.size }, "every cue fills the box again")
        #expect(document.captionCues.map(\.text) == words, "the words are not touched")
    }

    @Test func resetOnAnythingElseDoesNothing() {
        var document = Self.captioned()
        let before = document
        document.resetCaptions(UUID())
        #expect(document == before)
    }
}
