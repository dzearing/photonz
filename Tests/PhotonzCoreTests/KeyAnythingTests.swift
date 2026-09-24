import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Keyframe anything (task `keyframe-anything-and-see-and-shape-the-keys-on`).
///
/// Written before the model. What the three slices before it left: the crop,
/// keyed the way Premiere's Crop effect keys it (four edges, each a percent of
/// the picture), a glow's size, the ease a NEW key is given (the mock's Easing
/// dropdown on the timeline bar), and the bar's "Playhead Opacity 100% @ 4.12s"
/// readout.
@Suite("Keyframe anything")
struct KeyAnythingTests {

    // MARK: - Fixtures

    /// Ten seconds, a 1600 x 900 picture drawn at 800 x 450, and a title.
    static func withPicture() -> (PhotonzDocument, picture: UUID, title: UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        var picture = Layer(name: "Shot",
                            content: .image(ImageRef(pixelSize: CGSize(width: 1600, height: 900))),
                            frame: CGRect(x: 100, y: 100, width: 800, height: 450))
        picture.time = LayerTime(inMS: 0, outMS: 10_000)
        var title = Layer(name: "Hello",
                          content: .text(TextContent(string: "Hello", fontSize: 48)),
                          frame: CGRect(x: 100, y: 700, width: 400, height: 80))
        title.time = LayerTime(inMS: 0, outMS: 10_000)
        doc.layers = [picture, title]
        doc.durationMS = 10_000
        return (doc, picture.id, title.id)
    }

    static func posed(_ doc: PhotonzDocument, _ id: UUID, at ms: Int) -> Layer? {
        doc.moved(toMotionTimeMS: ms).layer(id: id)
    }

    static func close(_ a: CGFloat, _ b: CGFloat, _ slack: CGFloat = 0.01) -> Bool { abs(a - b) <= slack }

    // MARK: - Crop, the way Premiere keys it

    @Test func aPictureOffersItsFourCropEdgesAndATitleDoesNot() {
        let (doc, picture, title) = Self.withPicture()
        let offered = doc.layer(id: picture)?.keyableProperties ?? []
        for edge in [MotionProperty.cropLeft, .cropTop, .cropRight, .cropBottom] {
            #expect(offered.contains(.motion(edge)))
        }
        let words = doc.layer(id: title)?.keyableProperties ?? []
        #expect(words.contains(.motion(.cropLeft)) == false)
    }

    @Test func anUnkeyedCropReadsNothingCutAway() {
        let (doc, picture, _) = Self.withPicture()
        #expect(doc.keyedValue(layerID: picture, .motion(.cropLeft), atDocumentTimeMS: 1000) == .number(0))
        #expect(MotionProperty.cropLeft.format(.number(25)) == "25%")
        #expect(MotionProperty.cropLeft.title == "Crop left")
    }

    @Test func aKeyedLeftCropCutsThePictureAwayWithoutMovingWhatIsKept() {
        var (doc, picture, _) = Self.withPicture()
        let started = doc.startKeying(layerID: picture, .motion(.cropLeft), atDocumentTimeMS: 0)
        #expect(started)
        doc.setKeyedValue(.number(25), layerID: picture, .motion(.cropLeft), atDocumentTimeMS: 4000)
        guard let at4 = Self.posed(doc, picture, at: 4000) else { Issue.record("no layer"); return }
        // A quarter of 800pt gone off the left, the right edge where it was.
        #expect(Self.close(at4.frame.minX, 300))
        #expect(Self.close(at4.frame.maxX, 900))
        #expect(Self.close(at4.frame.height, 450))
        // And a quarter of the 1600 pixels gone from the same side, so the
        // pixels still showing sit exactly where they were drawn.
        #expect(Self.close(at4.crop?.minX ?? -1, 400))
        #expect(Self.close(at4.crop?.width ?? -1, 1200))
        // Halfway there at 2s, eased: somewhere strictly between.
        let at2 = Self.posed(doc, picture, at: 2000)?.frame.minX ?? 0
        #expect(at2 > 100 && at2 < 300)
        // The stored layer is untouched: a key is not a baked crop.
        #expect(doc.layer(id: picture)?.crop == nil)
        #expect(doc.layer(id: picture)?.frame == CGRect(x: 100, y: 100, width: 800, height: 450))
    }

    @Test func theFourEdgesAreIndependentAndCannotCross() {
        var (doc, picture, _) = Self.withPicture()
        for edge in [MotionProperty.cropLeft, .cropRight, .cropTop, .cropBottom] {
            doc.setKeyedValue(.number(0), layerID: picture, .motion(edge), atDocumentTimeMS: 0)
        }
        doc.setKeyedValue(.number(10), layerID: picture, .motion(.cropTop), atDocumentTimeMS: 0)
        doc.setKeyedValue(.number(20), layerID: picture, .motion(.cropBottom), atDocumentTimeMS: 0)
        doc.setKeyedValue(.number(70), layerID: picture, .motion(.cropLeft), atDocumentTimeMS: 0)
        doc.setKeyedValue(.number(70), layerID: picture, .motion(.cropRight), atDocumentTimeMS: 0)
        guard let posed = Self.posed(doc, picture, at: 0) else { Issue.record("no layer"); return }
        #expect(Self.close(posed.frame.minY, 145))
        #expect(Self.close(posed.frame.maxY, 460))
        // Left and right asked for more than the whole width between them:
        // something is always left to draw, never a negative box.
        #expect(posed.frame.width >= 1)
        #expect((posed.crop?.width ?? 0) > 0)
    }

    @Test func aCroppedPictureGrowsAboutItsOwnMiddleNotTheCutOne() {
        // Premiere crops the picture, then scales it about its anchor: the
        // picture's middle, wherever the crop is. So the right half of a
        // picture cropped by half from the left, grown to 200%, keeps its right
        // edge at the grown picture's right edge.
        var (doc, picture, _) = Self.withPicture()
        doc.setKeyedValue(.number(50), layerID: picture, .motion(.cropLeft), atDocumentTimeMS: 0)
        doc.setKeyedValue(.number(200), layerID: picture, .motion(.scale), atDocumentTimeMS: 0)
        guard let posed = Self.posed(doc, picture, at: 0) else { Issue.record("no layer"); return }
        // Uncropped 100...900 grown about 500 is -300...1300; the left half
        // cut away leaves 500...1300.
        #expect(Self.close(posed.frame.minX, 500))
        #expect(Self.close(posed.frame.maxX, 1300))
        // Growing is not cropping: the same pixels are kept.
        #expect(Self.close(posed.crop?.minX ?? -1, 800))
        #expect(Self.close(posed.crop?.width ?? -1, 800))
    }

    @Test func typingACropNobodyHasKeyedStartsKeyingIt() {
        // A crop has no value of its own to hold (like scale), so a number
        // typed into its row is a first key, not a baked cut.
        var (doc, picture, _) = Self.withPicture()
        doc.setKeyedValue(.number(30), layerID: picture, .motion(.cropRight), atDocumentTimeMS: 2000)
        #expect(doc.keyCount(layerID: picture, .motion(.cropRight)) == 1)
        #expect(doc.keyedValue(layerID: picture, .motion(.cropRight), atDocumentTimeMS: 2000) == .number(30))
    }

    @Test func stoppingACropKeepsTheCutItHasAtThePlayhead() {
        var (doc, picture, _) = Self.withPicture()
        doc.setKeyedValue(.number(0), layerID: picture, .motion(.cropLeft), atDocumentTimeMS: 0)
        doc.setKeyedValue(.number(50), layerID: picture, .motion(.cropLeft), atDocumentTimeMS: 4000)
        let started = doc.stopKeying(layerID: picture, .motion(.cropLeft), atDocumentTimeMS: 4000)
        #expect(started)
        let stored = doc.layer(id: picture)
        #expect(stored?.motions == nil)
        #expect(Self.close(stored?.frame.minX ?? 0, 500))
        #expect(Self.close(stored?.crop?.minX ?? 0, 800))
        // And the row reads nothing cut away again: the cut is the picture now.
        #expect(doc.keyedValue(layerID: picture, .motion(.cropLeft), atDocumentTimeMS: 4000) == .number(0))
    }

    @Test func theCanvasHandlesSitRoundTheWholePictureNotTheCrop() {
        // Premiere's box stays round the whole clip when it is cropped, and a
        // drag on a cropped picture must move the picture, never bake the cut
        // into its box.
        var (doc, picture, _) = Self.withPicture()
        doc.setKeyedValue(.point(CGPoint(x: 100, y: 100)), layerID: picture,
                          .motion(.position), atDocumentTimeMS: 0)
        doc.setKeyedValue(.number(40), layerID: picture, .motion(.cropLeft), atDocumentTimeMS: 0)
        let posed = doc.posedForCanvas(atTimeMS: 0).layer(id: picture)
        #expect(posed?.frame == CGRect(x: 100, y: 100, width: 800, height: 450))
    }

    @Test func anImageCroppedByHandKeepsItsCutWhenItGrows() {
        // Grown about its middle, a picture cropped with the Crop tool shows
        // the same pixels bigger: the cut is in the picture's own pixels, which
        // growing the box does not change.
        var (doc, picture, _) = Self.withPicture()
        doc.updateLayer(id: picture) { $0.cropContent(to: CGRect(x: 100, y: 100, width: 400, height: 450)) }
        let cut = doc.layer(id: picture)?.crop
        doc.setKeyedValue(.number(200), layerID: picture, .motion(.scale), atDocumentTimeMS: 0)
        #expect(Self.posed(doc, picture, at: 0)?.crop == cut)
    }

    // MARK: - An effect's amount

    @Test func aGlowsSizeIsKeyableOnlyWhereThereIsAGlow() {
        var (doc, _, title) = Self.withPicture()
        let before = doc.layer(id: title)?.keyableProperties ?? []
        #expect(before.contains(.motion(.glow)) == false)
        doc.updateLayer(id: title) { $0.style.effects.append(.glow(GlowEffect())) }
        #expect((doc.layer(id: title)?.keyableProperties ?? []).contains(.motion(.glow)))
        #expect(doc.keyedValue(layerID: title, .motion(.glow), atDocumentTimeMS: 0)
                == .number(Double(GlowEffect.startingSize)))
        // Unkeyed, a typed size is simply the glow's own.
        doc.setKeyedValue(.number(0), layerID: title, .motion(.glow), atDocumentTimeMS: 0)
        #expect(doc.layer(id: title)?.style.glowEffects.first?.size == 0)
        let started = doc.startKeying(layerID: title, .motion(.glow), atDocumentTimeMS: 0)
        #expect(started)
        doc.setKeyedValue(.number(30), layerID: title, .motion(.glow), atDocumentTimeMS: 4000)
        let glowAt4 = Self.posed(doc, title, at: 4000)?.style.glowEffects.first?.size
        #expect(glowAt4 == 30)
        #expect(MotionProperty.glow.title == "Glow size")
    }

    // MARK: - The ease a new key is given

    @Test func aNewKeyTakesTheEaseAskedFor() {
        var (doc, _, title) = Self.withPicture()
        doc.startKeying(layerID: title, .motion(.opacity), atDocumentTimeMS: 0, ease: .linear)
        doc.setKeyedValue(.number(0), layerID: title, .motion(.opacity), atDocumentTimeMS: 2000, ease: .hold)
        let keys = doc.layer(id: title)?.keyedMotion(.opacity)?.keyframes ?? []
        #expect(keys.map(\.ease) == [.linear, .hold])
        // Rewriting a key that is already there keeps the ease it had.
        doc.setKeyedValue(.number(50), layerID: title, .motion(.opacity), atDocumentTimeMS: 2000, ease: .easeIn)
        #expect(doc.layer(id: title)?.keyedMotion(.opacity)?.keyframes.last?.ease == .hold)
        // A linear key into a linear key runs at an even pace.
        doc.setKeyedValue(.number(0), layerID: title, .motion(.opacity), atDocumentTimeMS: 2000)
        let half = doc.keyedValue(layerID: title, .motion(.opacity), atDocumentTimeMS: 1000)
        #expect(half == .number(50) || {
            if case let .number(value)? = half { return abs(value - 50) < 0.5 }
            return false
        }())
    }

    @Test func aBezierNewKeyStartsWithHandles() {
        var (doc, _, title) = Self.withPicture()
        doc.startKeying(layerID: title, .motion(.scale), atDocumentTimeMS: 0, ease: .bezier)
        let key = doc.layer(id: title)?.keyedMotion(.scale)?.keyframes.first
        #expect(key?.ease == .bezier)
        #expect(key?.handles != nil)
    }

    // MARK: - The timeline bar's readout

    @Test func theReadoutNamesTheValueAndItsReadingAtThePlayhead() {
        var (doc, _, title) = Self.withPicture()
        #expect(doc.keyReadout(layerID: title, preferring: nil, atDocumentTimeMS: 0) == nil)
        doc.setKeyedValue(.number(100), layerID: title, .motion(.scale), atDocumentTimeMS: 0)
        doc.startKeying(layerID: title, .motion(.opacity), atDocumentTimeMS: 0)
        // The value asked for, when it is keyed.
        #expect(doc.keyReadout(layerID: title, preferring: .motion(.opacity), atDocumentTimeMS: 0)
                == "Opacity 100%")
        // Otherwise the first keyed value in the panel's order.
        #expect(doc.keyReadout(layerID: title, preferring: .motion(.blur), atDocumentTimeMS: 0)
                == "Scale 100%")
        // A length says the panel's own unit word.
        doc.startKeying(layerID: title, .motion(.blur), atDocumentTimeMS: 0)
        #expect(doc.keyReadout(layerID: title, preferring: .motion(.blur), atDocumentTimeMS: 0)
                == "Blur 0 \(DocumentUnit.word)")
        #expect(PhotonzDocument.playheadSeconds(4120) == "4.12s")
    }
}
