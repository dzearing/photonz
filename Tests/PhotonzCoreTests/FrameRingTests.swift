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
}
