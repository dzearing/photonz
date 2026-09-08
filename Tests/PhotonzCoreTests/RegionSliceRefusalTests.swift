import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

@Suite("Region slice refusal")
struct RegionSliceRefusalTests {
    private func picture(_ frame: CGRect) -> Layer {
        Layer(name: "Photo", content: .image(ImageRef(pixelSize: frame.size)), frame: frame)
    }

    private func box(_ frame: CGRect) -> Layer {
        Layer(name: "Rectangle",
              content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 4,
                                                     colorHex: "#FF3B30")),
              frame: frame)
    }

    private let frame = CGRect(x: 0, y: 0, width: 200, height: 100)

    // MARK: - Who refuses

    @Test func aPlainPictureNeverRefuses() {
        // Cutting a piece out of a photo is the thing that already works, and
        // it must keep working without a word on screen.
        #expect(RegionSliceRefusal.refusal(for: picture(frame), action: .cut) == nil)
        #expect(RegionSliceRefusal.refusal(for: picture(frame), action: .erase) == nil)
    }

    @Test func aShapeRefusesBecauseItIsNotPixels() {
        let refusal = RegionSliceRefusal.refusal(for: box(frame), action: .cut)
        #expect(refusal?.reason == .notPixels)
    }

    @Test func textRefusesTheSameWayAShapeDoes() {
        let text = Layer(name: "Heading", content: .text(TextContent(string: "Hello")), frame: frame)
        #expect(RegionSliceRefusal.refusal(for: text, action: .cut)?.reason == .notPixels)
    }

    @Test func aCroppedOrTurnedPictureRefusesAsAPicture() {
        // It IS pixels, so the words must not tell the person to go and find a
        // picture: the reason is the crop or the turn, not the content.
        var cropped = picture(frame)
        cropped.crop = CGRect(x: 0, y: 0, width: 0.5, height: 1)
        #expect(RegionSliceRefusal.refusal(for: cropped, action: .cut)?.reason == .adjustedPicture)

        var turned = picture(frame)
        turned.transform = LayerTransform(rotation: .pi / 8)
        #expect(RegionSliceRefusal.refusal(for: turned, action: .erase)?.reason == .adjustedPicture)
    }

    @Test func refusingAgreesWithWhatCanBeSliced() {
        // One rule, two callers: anything RegionTarget will slice must not
        // refuse, and anything it will not slice must.
        let layers = [picture(frame), box(frame)]
        for layer in layers {
            #expect(RegionTarget.canSlice(layer) == (RegionSliceRefusal.refusal(for: layer, action: .cut) == nil))
        }
    }

    // MARK: - What it says

    @Test func theTitleNamesTheKeyThatWasPressed() {
        #expect(RegionSliceRefusal(action: .cut, reason: .notPixels).title == "Cannot cut a piece out")
        #expect(RegionSliceRefusal(action: .erase, reason: .notPixels).title == "Cannot delete a piece")
    }

    @Test func theDetailSaysWhyAndWhatToDoInstead() {
        let cut = RegionSliceRefusal(action: .cut, reason: .notPixels)
        #expect(cut.detail == "Only a picture can have a piece taken out. Clear the marquee to cut the whole layer.")
        let erase = RegionSliceRefusal(action: .erase, reason: .notPixels)
        #expect(erase.detail.hasSuffix("Clear the marquee to delete the whole layer."))
    }

    @Test func aCroppedPictureIsToldWhatIsInTheWay() {
        let detail = RegionSliceRefusal(action: .cut, reason: .adjustedPicture).detail
        #expect(detail.contains("cropped or turned"))
        #expect(!detail.contains("Only a picture"))
    }

    @Test func nothingItSaysUsesAnEmDash() {
        for action in [RegionSliceRefusal.Action.cut, .erase] {
            for reason in [RegionSliceRefusal.Reason.notPixels, .adjustedPicture] {
                let refusal = RegionSliceRefusal(action: action, reason: reason)
                #expect(!refusal.title.contains("—"))
                #expect(!refusal.detail.contains("—"))
                #expect(!refusal.title.isEmpty)
                #expect(!refusal.detail.isEmpty)
            }
        }
    }

    // MARK: - It rides the notice pill

    @Test func theNoticePillCarriesTheRefusalWordForWord() {
        let refusal = RegionSliceRefusal(action: .cut, reason: .notPixels)
        let notice = CopyConfirmation(subject: .regionSliceRefused(refusal), shownAt: Date())
        #expect(notice.title == refusal.title)
        #expect(notice.detail == refusal.detail)
    }

    @Test func aRefusalStaysUpLongEnoughToRead() {
        // It is a sentence you might act on (clear the marquee, press Command
        // Z), so it gets the longer life the break notices get, not the 1.6
        // seconds a "Copied" glance gets.
        let notice = CopyConfirmation(subject: .regionSliceRefused(.init(action: .cut, reason: .notPixels)),
                                      shownAt: Date())
        #expect(notice.lifetime == CopyConfirmation.breakLifetime)
    }
}
