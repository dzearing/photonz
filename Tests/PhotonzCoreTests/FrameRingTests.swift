import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The ring a picked clip wears once it has been pushed in on
/// (`PhotonzDocument.frameRing`, `docs/design/mocks/pages/video-zoom-wt.html`
/// `#frameRing`).
///
/// At 220% a recording's own box is more than twice the size of the frame, so
/// an outline round the box hung out on empty canvas with a handle on it while
/// the picture itself was cut off at the frame (seen 2026-10-11 on
/// `framing-a-zoom-keys-its-centre-walk`). The walkthrough rings the frame.
@Suite("A pushed-in clip is ringed on the frame")
struct FrameRingTests {

    typealias Clip = ClipReframeTests

    /// The box the canvas would outline at `ms`: the layer as posed then.
    static func drawnBox(_ id: UUID, in document: PhotonzDocument, atMS ms: Int) -> CGRect? {
        document.posedForCanvas(atTimeMS: ms).layer(id: id)?.drawnBounds()
    }

    /// A whole-frame recording pushed in to 220%, arriving at 5s.
    static func pushedIn() -> (PhotonzDocument, UUID) {
        let clip = Clip.clip()
        var document = Clip.document(clip)
        let frame = clip.frame
        let region = CGRect(x: frame.midX - frame.width / 4.4, y: frame.midY - frame.height / 4.4,
                            width: frame.width / 2.2, height: frame.height / 2.2)
        let pushed = document.punchIn(layerID: clip.id, onRegion: region, atTimeMS: 5000)
        #expect(pushed)
        return (document, clip.id)
    }

    @Test("At 220% the ring is the frame, not the magnified box")
    func ringsTheFrameWhenPushedIn() throws {
        let (document, id) = Self.pushedIn()
        let box = try #require(Self.drawnBox(id, in: document, atMS: 5000))
        // The premise: the box really has grown past the frame.
        #expect(box.width > 2000)
        let ring = try #require(document.frameRing(layerID: id, drawnBox: box))
        #expect(ring == CGRect(origin: .zero, size: document.canvasSize))
    }

    @Test("Framed off to one side, the ring still sits on the frame")
    func ringsTheFrameWhenOffCentre() throws {
        let (document, id) = Self.pushedIn()
        // 220% of a 1280 x 720 box, slid so the shot is the top left corner.
        let box = CGRect(x: 0, y: 0, width: 2816, height: 1584)
        let ring = try #require(document.frameRing(layerID: id, drawnBox: box))
        #expect(ring == CGRect(origin: .zero, size: document.canvasSize))
        let farRight = box.offsetBy(dx: -1536, dy: -864)
        #expect(document.frameRing(layerID: id, drawnBox: farRight)
                == CGRect(origin: .zero, size: document.canvasSize))
    }

    @Test("Before the push the clip is outlined as it always was")
    func noRingAtTheWideShot() throws {
        let (document, id) = Self.pushedIn()
        let box = try #require(Self.drawnBox(id, in: document, atMS: 0))
        #expect(document.frameRing(layerID: id, drawnBox: box) == nil)
    }

    @Test("A clip never pushed in keeps its usual outline")
    func noRingWhenUntouched() {
        let clip = Clip.clip()
        let document = Clip.document(clip)
        #expect(document.frameRing(layerID: clip.id, drawnBox: clip.drawnBounds()) == nil)
    }

    @Test("A picture grown inside the frame keeps its outline and handles")
    func noRingWhenTheGrownPictureStaysInside() {
        var clip = Clip.clip()
        clip.frame = CGRect(x: 100, y: 100, width: 320, height: 180)
        let document = Clip.document(clip)
        let grown = CGRect(x: 60, y: 80, width: 400, height: 225)
        #expect(document.frameRing(layerID: clip.id, drawnBox: grown) == nil)
    }

    @Test("A picture-in-picture grown past the edge is ringed where it shows")
    func ringsWhatShowsOfAPictureInPicture() throws {
        var clip = Clip.clip()
        clip.frame = CGRect(x: 900, y: 500, width: 320, height: 180)
        let document = Clip.document(clip)
        let grown = CGRect(x: 820, y: 455, width: 640, height: 360)
        let ring = try #require(document.frameRing(layerID: clip.id, drawnBox: grown))
        #expect(ring == CGRect(x: 820, y: 455, width: 460, height: 265))
    }

    @Test("A picture slid partly off the canvas at its own size is not ringed")
    func noRingForASlideAtFullSize() {
        let clip = Clip.clip()
        let document = Clip.document(clip)
        let slid = clip.frame.offsetBy(dx: -300, dy: 0)
        #expect(document.frameRing(layerID: clip.id, drawnBox: slid) == nil)
    }

    @Test("A title or shape is never ringed, however big")
    func titlesAreNeverRinged() {
        let title = Layer(name: "Title", content: .text(TextContent(string: "Hello")),
                          frame: CGRect(x: 0, y: 0, width: 200, height: 60))
        let document = PhotonzDocument(canvasSize: CGSize(width: 1280, height: 720),
                                       layers: [Clip.clip(), title])
        let huge = CGRect(x: -400, y: -400, width: 3000, height: 2000)
        #expect(document.frameRing(layerID: title.id, drawnBox: huge) == nil)
    }

    // MARK: - A click outside the ring

    @Test("Every clip pushed in past the frame is ringed, picked or not")
    func ringsForEveryPushedInClip() {
        let (document, id) = Self.pushedIn()
        let shown = document.posedForCanvas(atTimeMS: 5000)
        #expect(document.frameRings(shown: shown)
                == [id: CGRect(origin: .zero, size: document.canvasSize)])
        #expect(document.frameRings(shown: document.posedForCanvas(atTimeMS: 0)).isEmpty)
    }

    @Test("A click on the empty canvas past the frame lets go of a pushed-in clip")
    func clickPastTheFrameMissesThePushedInClip() {
        let (document, id) = Self.pushedIn()
        let shown = document.posedForCanvas(atTimeMS: 5000)
        let rings = document.frameRings(shown: shown)
        let outside = CGPoint(x: -20, y: 400)
        // The premise: the magnified box reaches out there.
        #expect(shown.hitTest(outside)?.id == id)
        #expect(shown.cutOffAtTheFrame(rings, at: outside).hitTest(outside) == nil)
        #expect(shown.cutOffAtTheFrame(rings, at: outside)
                .selectionTarget(at: outside, inside: nil) == nil)
    }

    @Test("A click on the picture inside the frame still picks the clip")
    func clickInsideTheFramePicksThePushedInClip() {
        let (document, id) = Self.pushedIn()
        let shown = document.posedForCanvas(atTimeMS: 5000)
        let rings = document.frameRings(shown: shown)
        let inside = CGPoint(x: 300, y: 300)
        #expect(shown.cutOffAtTheFrame(rings, at: inside).hitTest(inside)?.id == id)
    }

    @Test("Past the frame, a click reaches what is drawn under the pushed-in clip")
    func clickPastTheFrameReachesWhatIsUnder() {
        let (pushed, id) = Self.pushedIn()
        let under = Layer(name: "Backdrop", content: .image(ImageRef(pixelSize: CGSize(width: 1480, height: 920))),
                          frame: CGRect(x: -100, y: -100, width: 1480, height: 920))
        var document = pushed
        document.layers.insert(under, at: 0)
        let shown = document.posedForCanvas(atTimeMS: 5000)
        let rings = document.frameRings(shown: shown)
        let outside = CGPoint(x: -20, y: 400)
        #expect(shown.hitTest(outside)?.id == id)
        #expect(shown.cutOffAtTheFrame(rings, at: outside).hitTest(outside)?.id == under.id)
    }

    @Test("A clip slid off the canvas at its own size is still clicked where it hangs")
    func slidAtFullSizeStillTakesTheClick() {
        var clip = Clip.clip()
        clip.frame = clip.frame.offsetBy(dx: -300, dy: 0)
        let document = Clip.document(clip)
        let rings = document.frameRings(shown: document)
        #expect(rings.isEmpty)
        let hanging = CGPoint(x: -100, y: 300)
        #expect(document.cutOffAtTheFrame(rings, at: hanging).hitTest(hanging)?.id == clip.id)
    }
}
