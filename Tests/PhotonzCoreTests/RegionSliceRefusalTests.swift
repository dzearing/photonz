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
        #expect(RegionSliceRefusal.refusal(for: picture(frame), action: .fill) == nil)
    }

    @Test func aShapeRefusesTheFillKeyToo() {
        // The gap this closed: ⌘X and ⌫ both had an answer for a marquee over
        // a rectangle and ⌥⌫ did not, so the family disagreed about the same
        // marquee over the same layer.
        let refusal = RegionSliceRefusal.refusal(for: box(frame), action: .fill)
        #expect(refusal?.reason == .canBecomeAPicture)
        #expect(refusal?.action == .fill)
    }

    @Test func everyKeyRefusesTheSameLayersForTheSameReason() {
        // One rule for all three keys: what refuses and why can never depend
        // on which of them was pressed, only on the layer.
        var cropped = picture(frame)
        cropped.crop = CGRect(x: 0, y: 0, width: 0.5, height: 1)
        let layers = [picture(frame), box(frame), cropped,
                      Layer(name: "Width", content: .measure(MeasureContent()), frame: frame)]
        for layer in layers {
            let reasons = [RegionSliceRefusal.Action.cut, .erase, .fill].map {
                RegionSliceRefusal.refusal(for: layer, action: $0)?.reason
            }
            #expect(Set(reasons.map { String(describing: $0) }).count == 1)
        }
    }

    @Test func aShapeRefusesButSaysItCanBecomeAPicture() {
        // A shape is not pixels, but it is one command away from being some,
        // so the refusal points at that command instead of dead-ending.
        let refusal = RegionSliceRefusal.refusal(for: box(frame), action: .cut)
        #expect(refusal?.reason == .canBecomeAPicture)
    }

    @Test func textRefusesTheSameWayAShapeDoes() {
        let text = Layer(name: "Heading", content: .text(TextContent(string: "Hello")), frame: frame)
        #expect(RegionSliceRefusal.refusal(for: text, action: .cut)?.reason == .canBecomeAPicture)
    }

    @Test func aMeasurementHasNoWayForward() {
        // Nothing turns a live measurement into pixels, so its refusal must
        // not send someone hunting for a command that will not be there.
        let measure = Layer(name: "Width", content: .measure(MeasureContent()), frame: frame)
        #expect(RegionSliceRefusal.refusal(for: measure, action: .cut)?.reason == .notPixels)
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
        let layers = [picture(frame), box(frame),
                      Layer(name: "Heading", content: .text(TextContent(string: "Hi")), frame: frame)]
        for layer in layers {
            #expect(RegionTarget.canSlice(layer) == (RegionSliceRefusal.refusal(for: layer, action: .cut) == nil))
        }
    }

    // MARK: - What it says

    @Test func theTitleNamesTheKeyThatWasPressed() {
        #expect(RegionSliceRefusal(action: .cut, reason: .notPixels).title == "Cannot cut a piece out")
        #expect(RegionSliceRefusal(action: .erase, reason: .notPixels).title == "Cannot delete a piece")
        #expect(RegionSliceRefusal(action: .fill, reason: .notPixels).title == "Cannot fill a piece")
    }

    @Test func theDetailSaysWhyAndWhatToDoInstead() {
        let cut = RegionSliceRefusal(action: .cut, reason: .notPixels)
        #expect(cut.detail == "Only a picture can have a piece taken out. Clear the marquee to cut the whole layer.")
        let erase = RegionSliceRefusal(action: .erase, reason: .notPixels)
        #expect(erase.detail.hasSuffix("Clear the marquee to delete the whole layer."))
        // ⌥⌫ over a shape used to be the one key in the family that still did
        // nothing and said nothing. Its way out is the true one: with the
        // marquee gone, ⌥⌫ recolors the whole shape.
        let fill = RegionSliceRefusal(action: .fill, reason: .notPixels)
        #expect(fill.detail == "Only a picture can have a piece filled in. Clear the marquee to fill the whole layer.")
    }

    @Test func fillingSaysFilledInWhereCuttingSaysTakenOut() {
        // Same sentence, same two halves, one verb apart: nothing is taken out
        // of a layer by ⌥⌫, so the words must not say it is.
        for reason in [RegionSliceRefusal.Reason.notPixels, .canBecomeAPicture] {
            let fill = RegionSliceRefusal(action: .fill, reason: reason).detail
            #expect(fill.contains("filled in"))
            #expect(!fill.contains("taken out"))
            #expect(RegionSliceRefusal(action: .cut, reason: reason).detail.contains("taken out"))
        }
    }

    @Test func aShapeIsToldHowToBecomeAPicture() {
        // The half that was missing: the person is holding a marquee over a
        // rectangle and needs to know a picture is one command away.
        for action in [RegionSliceRefusal.Action.cut, .erase, .fill] {
            let detail = RegionSliceRefusal(action: action, reason: .canBecomeAPicture).detail
            #expect(detail.contains("Turn it into a picture"))
            #expect(detail.contains("Layer menu"))
        }
    }

    @Test func aCroppedPictureIsToldWhatIsInTheWay() {
        let detail = RegionSliceRefusal(action: .cut, reason: .adjustedPicture).detail
        #expect(detail.contains("cropped or turned"))
        #expect(!detail.contains("Only a picture"))
        let fill = RegionSliceRefusal(action: .fill, reason: .adjustedPicture).detail
        #expect(fill == "This picture is cropped or turned. Clear the marquee to fill the whole layer.")
    }

    @Test func nothingItSaysUsesAnEmDash() {
        for action in [RegionSliceRefusal.Action.cut, .erase, .fill] {
            for reason in [RegionSliceRefusal.Reason.notPixels, .adjustedPicture, .canBecomeAPicture] {
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
