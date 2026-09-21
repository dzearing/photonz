import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

@Suite("Region target")
struct RegionTargetTests {
    private func picture(_ name: String, _ frame: CGRect,
                         locked: Bool = false) -> Layer {
        Layer(name: name,
              content: .image(ImageRef(pixelSize: frame.size)),
              frame: frame, isLocked: locked)
    }

    private func box(_ name: String, _ frame: CGRect) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 4,
                                                    colorHex: "#FF3B30")), frame: frame)
    }

    private let region = CGRect(x: 100, y: 100, width: 200, height: 100)

    // MARK: - The layer you picked is the one it acts on

    @Test func aRegionActsOnThePickedLayerAndNoOther() {
        let bottom = picture("Bottom", CGRect(x: 0, y: 0, width: 400, height: 400))
        let top = picture("Top", CGRect(x: 50, y: 50, width: 300, height: 300))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                  layers: [bottom, top])
        #expect(RegionTarget.id(picked: top.id, hit: nil, region: region, in: doc) == top.id)
        #expect(RegionTarget.id(picked: bottom.id, hit: nil, region: region, in: doc) == bottom.id)
    }

    @Test func theLayerUnderThePointerNeverBeatsTheLayerYouPicked() {
        // The bucket hands in the layer it was clicked on. A region says WHERE,
        // and the pick says WHAT, so clicking inside the marquee over some
        // other layer still paints the one you picked. Fill, delete, copy and
        // move all come through here, which is what makes them agree.
        let picked = picture("Picked", CGRect(x: 0, y: 0, width: 400, height: 400))
        let other = picture("Other", CGRect(x: 100, y: 100, width: 200, height: 200))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                  layers: [picked, other])
        #expect(RegionTarget.id(picked: picked.id, hit: other.id, region: region, in: doc)
                == picked.id)
    }

    @Test func aPickedLayerThatCannotBeSlicedTakesTheOpNowhereElse() {
        // A rectangle is not pixels, so a region cannot be cut out of it. The
        // op does nothing rather than wandering off and cutting a hole in the
        // picture underneath, which is a layer nobody picked.
        let background = picture("Background", CGRect(x: 0, y: 0, width: 400, height: 400),
                                 locked: true)
        let rectangle = box("Rectangle", CGRect(x: 50, y: 50, width: 300, height: 300))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                  layers: [background, rectangle])
        #expect(RegionTarget.id(picked: rectangle.id, hit: nil, region: region, in: doc) == nil)
    }

    @Test func aCroppedOrTurnedPictureIsNotSliceableEither() {
        // The region path maps into the bitmap through the layer's frame, and
        // that mapping lies the moment the layer is cropped or turned.
        let frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        var cropped = picture("Cropped", frame)
        cropped.crop = CGRect(x: 10, y: 10, width: 100, height: 100)
        var turned = picture("Turned", frame)
        turned.transform = LayerTransform(rotation: .pi / 8)
        let doc = PhotonzDocument(canvasSize: frame.size, layers: [cropped, turned])
        #expect(RegionTarget.id(picked: cropped.id, hit: nil, region: region, in: doc) == nil)
        #expect(RegionTarget.id(picked: turned.id, hit: nil, region: region, in: doc) == nil)
    }

    // MARK: - With nothing picked

    @Test func withNothingPickedTheLayerUnderThePointerTakesIt() {
        let background = picture("Background", CGRect(x: 0, y: 0, width: 400, height: 400),
                                 locked: true)
        let photo = picture("Photo", CGRect(x: 100, y: 100, width: 200, height: 200))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                  layers: [background, photo])
        #expect(RegionTarget.id(picked: nil, hit: photo.id, region: region, in: doc) == photo.id)
    }

    @Test func withNothingPickedAndNoPointerTheLockedBackgroundTakesIt() {
        // ⌫ has no pointer to hand in. Clearing to the background colour is
        // what the locked Background is for, so that one layer answers when
        // nothing else has been named.
        let background = picture("Background", CGRect(x: 0, y: 0, width: 400, height: 400),
                                 locked: true)
        let photo = picture("Photo", CGRect(x: 100, y: 100, width: 200, height: 200))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                  layers: [background, photo])
        #expect(RegionTarget.id(picked: nil, hit: nil, region: region, in: doc) == background.id)
    }

    @Test func aLockedBackgroundTheRegionDoesNotReachTakesNothing() {
        let background = picture("Background", CGRect(x: 0, y: 0, width: 80, height: 80),
                                 locked: true)
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                  layers: [background])
        #expect(RegionTarget.id(picked: nil, hit: nil, region: region, in: doc) == nil)
    }

    @Test func withNothingPickedAndNoBackgroundThereIsNothingToActOn() {
        let photo = picture("Photo", CGRect(x: 100, y: 100, width: 200, height: 200))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: [photo])
        #expect(RegionTarget.id(picked: nil, hit: nil, region: region, in: doc) == nil)
    }

    // MARK: - Odds and ends

    @Test func aPickThatIsNotInTheDocumentIsNoPickAtAll() {
        let background = picture("Background", CGRect(x: 0, y: 0, width: 400, height: 400),
                                 locked: true)
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                  layers: [background])
        #expect(RegionTarget.id(picked: UUID(), hit: nil, region: region, in: doc)
                == background.id)
    }

    @Test func aPickedLayerInsideAGroupIsFoundAndUsed() {
        let inner = picture("Inner", CGRect(x: 100, y: 100, width: 200, height: 200))
        let group = Layer(name: "Group",
                          content: .group(GroupContent(children: [inner], isFrame: false)),
                          frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: [group])
        #expect(RegionTarget.id(picked: inner.id, hit: nil, region: region, in: doc) == inner.id)
    }

    @Test func canSliceAnswersForTheLayerOnItsOwn() {
        let photo = picture("Photo", CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(RegionTarget.canSlice(photo))
        #expect(!RegionTarget.canSlice(box("Rectangle", CGRect(x: 0, y: 0, width: 10, height: 10))))
    }

    // MARK: - Several layers picked at once

    // The marquee said WHERE, and two rows were picked in the list, so the one
    // picture the marquee is over is the one it acts on. Before this, a
    // multi-pick read as no pick at all: the op fell all the way through to
    // the locked Background and quietly filled it with the background colour,
    // so pressing Delete over a picture you had picked changed nothing you
    // could see and said nothing either (`turn-two-shapes-into-pictures-walk`,
    // 2026-09-20).
    @Test func withSeveralPickedTheMarqueePicksTheOneItIsOver() {
        let left = picture("Left", CGRect(x: 50, y: 50, width: 200, height: 200))
        let right = picture("Right", CGRect(x: 500, y: 50, width: 200, height: 200))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 400),
                                  layers: [left, right])
        #expect(RegionTarget.id(picked: nil, multi: [left.id, right.id],
                                hit: nil, region: region, in: doc) == left.id)
    }

    @Test func withSeveralPickedOverTheMarqueeItActsOnNoneOfThem() {
        // Two pictures under one band is a question the band cannot answer, so
        // it acts on neither rather than guessing one.
        let lower = picture("Lower", CGRect(x: 0, y: 0, width: 400, height: 400))
        let upper = picture("Upper", CGRect(x: 50, y: 50, width: 300, height: 300))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                  layers: [lower, upper])
        #expect(RegionTarget.id(picked: nil, multi: [lower.id, upper.id],
                                hit: nil, region: region, in: doc) == nil)
    }

    @Test func aMultiPickNeverWandersToTheBackground() {
        // The Background answers for a marquee with NOTHING picked. With rows
        // picked it must not: a hole in a layer nobody chose is worse than
        // nothing happening.
        let background = picture("Background", CGRect(x: 0, y: 0, width: 400, height: 400),
                                 locked: true)
        let one = box("Rectangle", CGRect(x: 50, y: 50, width: 100, height: 100))
        let two = box("Rectangle 2", CGRect(x: 250, y: 50, width: 100, height: 100))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                  layers: [background, one, two])
        #expect(RegionTarget.id(picked: nil, multi: [one.id, two.id],
                                hit: nil, region: region, in: doc) == nil)
        // ...and with nothing picked at all the Background still answers.
        #expect(RegionTarget.id(picked: nil, hit: nil, region: region, in: doc) == background.id)
    }

    @Test func theSubjectOfARefusalIsTheOnePickedLayerTheMarqueeIsOver() {
        // A shape among several picked rows: the marquee cannot slice it, and
        // the refusal has to name it rather than going quiet.
        let shape = box("Rectangle", CGRect(x: 50, y: 50, width: 200, height: 200))
        let far = box("Rectangle 2", CGRect(x: 500, y: 50, width: 200, height: 200))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 400),
                                  layers: [shape, far])
        #expect(RegionTarget.subject(picked: nil, multi: [shape.id, far.id],
                                     region: region, in: doc) == shape.id)
        #expect(RegionTarget.id(picked: nil, multi: [shape.id, far.id],
                                hit: nil, region: region, in: doc) == nil)
    }

    @Test func aSinglePickIsTheSubjectWhereverTheMarqueeIs() {
        let away = box("Rectangle", CGRect(x: 600, y: 300, width: 50, height: 50))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 400), layers: [away])
        #expect(RegionTarget.subject(picked: away.id, multi: [], region: region, in: doc)
                == away.id)
    }
}
