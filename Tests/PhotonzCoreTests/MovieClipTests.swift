import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A clip is a layer that points at a recording (`docs/design/video.md`).
///
/// Written before the model, which is the rule for `PhotonzCore`. The whole
/// point of this file is the one invariant `CLAUDE.md` puts above the rest:
/// **pixel data never lives in the document model.** A clip layer carries a
/// reference to a file, a place in it and a length, and the frame it shows at a
/// moment is worked out here and fetched somewhere else entirely.
@Suite("A clip is a layer with a recording behind it")
struct MovieClipTests {

    static func movie(durationMS: Int = 8000) -> MovieRef {
        MovieRef(id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                 pixelSize: CGSize(width: 1920, height: 1080),
                 durationMS: durationMS)
    }

    // MARK: - The reference itself

    @Test("A movie reference is a file's identity, its size and its length, and no pixels")
    func referenceCarriesNoPixels() throws {
        let ref = Self.movie()
        let written = try JSONEncoder().encode(ref)
        let read = try JSONDecoder().decode(MovieRef.self, from: written)
        #expect(read == ref)
        // Said plainly: the only things on it are the three a renderer needs to
        // ask somebody else for a frame.
        let json = try #require(try JSONSerialization.jsonObject(with: written) as? [String: Any])
        #expect(Set(json.keys) == ["id", "pixelSize", "durationMS"])
    }

    @Test("Frames are asked for on a grid, so scrubbing lands on ones already fetched")
    func framesAreQuantized() {
        let ref = Self.movie()
        // Everything inside one frame's worth of time is the same frame.
        #expect(ref.frameSourceMS(atSourceMS: 0) == 0)
        #expect(ref.frameSourceMS(atSourceMS: MovieRef.frameStepMS - 1) == 0)
        #expect(ref.frameSourceMS(atSourceMS: MovieRef.frameStepMS) == MovieRef.frameStepMS)
        // And it never asks for a frame past the last one there is.
        #expect(ref.frameSourceMS(atSourceMS: 99_000) <= ref.durationMS)
        #expect(ref.frameSourceMS(atSourceMS: -50) == 0)
    }

    @Test("The same frame of the same recording is always the same reference")
    func frameRefsAreStable() {
        let ref = Self.movie()
        #expect(ref.frameRef(atSourceMS: 1000) == ref.frameRef(atSourceMS: 1000))
        #expect(ref.frameRef(atSourceMS: 1000) == ref.frameRef(atSourceMS: 1000 + 1))
        #expect(ref.frameRef(atSourceMS: 1000) != ref.frameRef(atSourceMS: 2000))
        #expect(ref.frameRef(atSourceMS: 1000).pixelSize == ref.pixelSize)
    }

    @Test("Two recordings never share a frame reference")
    func frameRefsAreNotSharedBetweenMovies() {
        let a = Self.movie()
        let b = MovieRef(pixelSize: CGSize(width: 1920, height: 1080), durationMS: 8000)
        #expect(a.frameRef(atSourceMS: 1000) != b.frameRef(atSourceMS: 1000))
    }

    // MARK: - A recording opened as a document

    @Test("Opening a recording makes an ordinary document with one clip in it")
    func recordingBecomesADocument() {
        let doc = PhotonzDocument.recording(Self.movie(), name: "Tutorial Sample")
        #expect(doc.canvasSize == CGSize(width: 1920, height: 1080))
        #expect(doc.layers.count == 1)
        let clip = doc.layers[0]
        #expect(clip.name == "Tutorial Sample")
        #expect(clip.movie == Self.movie())
        #expect(clip.time == LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: 8000))
        // It is a document with time, so a timeline belongs to it.
        #expect(doc.hasTime)
        #expect(doc.documentDurationMS == 8000)
    }

    @Test("A clip is an ordinary layer: it can be named, hidden, reordered and styled")
    func clipIsAnOrdinaryLayer() {
        var doc = PhotonzDocument.recording(Self.movie(), name: "Take 1")
        let id = doc.layers[0].id
        doc.updateLayer(id: id) { $0.name = "The good bit" }
        doc.updateLayer(id: id) { $0.isVisible = false }
        doc.updateLayer(id: id) { $0.style.opacity = 0.5 }
        doc.updateLayer(id: id) { $0.style.cornerRadius = 12 }
        let clip = doc.layer(id: id)
        #expect(clip?.name == "The good bit")
        #expect(clip?.isVisible == false)
        #expect(clip?.style.opacity == 0.5)
        #expect(clip?.style.cornerRadius == 12)
        // ...and it is still a clip through all of it.
        #expect(clip?.movie != nil)
    }

    @Test("A recording cut in the old window arrives as one clip with its pieces")
    func aCutRecordingArrivesWhole() {
        var cuts = VideoCutList(duration: 8)
        _ = cuts.split(atTimeline: 2)
        let doc = PhotonzDocument.recording(Self.movie(), name: "Take 1", cutList: cuts)
        // D18 §3: a split adds a piece to a clip, never a second clip.
        #expect(doc.layers.count == 1)
        #expect(doc.layers[0].clipPieces?.count == 2)
        #expect(doc.documentDurationMS == 8000)
    }

    // MARK: - Which frame is on screen at a moment

    @Test("A clip shows the frame of the file the playhead is over")
    func theFrameUnderThePlayhead() {
        let movie = Self.movie()
        let doc = PhotonzDocument.recording(movie, name: "Take 1")
        let clip = doc.layers[0]
        #expect(clip.movieFrameSourceMS(atTimeMS: 0) == 0)
        // Rounded to the frame grid, because that is the frame that gets
        // fetched: four seconds in is the 121st frame, which starts at 3993.
        #expect(clip.movieFrameSourceMS(atTimeMS: 4000) == movie.frameSourceMS(atSourceMS: 4000))
        #expect(clip.movieFrameSourceMS(atTimeMS: 4000) == 3993)
        // Off the end of the clip there is no frame of it to show.
        #expect(clip.movieFrameSourceMS(atTimeMS: 9000) == nil)
    }

    @Test("A clip placed later in the timeline reads from its own start, not the document's")
    func aClipPlacedLaterReadsItsOwnFile() {
        var doc = PhotonzDocument.recording(Self.movie(), name: "Take 1")
        doc.updateLayer(id: doc.layers[0].id) {
            $0.time = LayerTime(inMS: 3000, outMS: 5000, sourceInMS: 1000, sourceLengthMS: 8000)
        }
        let clip = doc.layers[0]
        #expect(clip.movieFrameSourceMS(atTimeMS: 3000) == 990)
        #expect(clip.movieFrameSourceMS(atTimeMS: 4000) == 1980)
        #expect(clip.movieFrameSourceMS(atTimeMS: 2999) == nil)
    }

    @Test("A frame held shows the same frame however long it is held for")
    func aHeldFrameHolds() {
        var doc = PhotonzDocument.recording(Self.movie(), name: "Take 1")
        let id = doc.layers[0].id
        let held = doc.holdFrame(id, atMS: 2000, forMS: 1000)
        #expect(held)
        let clip = doc.layer(id: id)
        #expect(clip?.movieFrameSourceMS(atTimeMS: 2100) == clip?.movieFrameSourceMS(atTimeMS: 2900))
    }

    // MARK: - What the renderer is handed

    @Test("The document drawn at a moment hands the renderer the frame, not the poster")
    func drawnAtAMomentSwapsTheFrameIn() {
        let movie = Self.movie()
        let doc = PhotonzDocument.recording(movie, name: "Take 1")
        let shown = doc.drawn(atTimeMS: 4000)
        guard case .image(let ref) = shown.layers[0].content else {
            Issue.record("a clip draws as a picture")
            return
        }
        #expect(ref == movie.frameRef(atSourceMS: 4000))
    }

    @Test("Asking what a moment needs names every frame that has to be fetched for it")
    func framesNeededForAMoment() {
        let movie = Self.movie()
        var doc = PhotonzDocument.recording(movie, name: "Take 1")
        let id = doc.layers[0].id
        let wanted = doc.movieFrames(atTimeMS: 4000)
        #expect(wanted.count == 1)
        #expect(wanted[0].movie == movie)
        #expect(wanted[0].sourceMS == movie.frameSourceMS(atSourceMS: 4000))
        #expect(wanted[0].ref == movie.frameRef(atSourceMS: 4000))
        #expect(wanted[0].layerID == id)
        // A moment the clip is not on screen for needs nothing fetched.
        doc.updateLayer(id: id) { $0.time = LayerTime(inMS: 0, outMS: 1000, sourceLengthMS: 8000) }
        #expect(doc.movieFrames(atTimeMS: 4000).isEmpty)
    }

    @Test("A layer hidden by hand asks for no frames, because nothing draws it")
    func aHiddenClipNeedsNoFrames() {
        var doc = PhotonzDocument.recording(Self.movie(), name: "Take 1")
        doc.updateLayer(id: doc.layers[0].id) { $0.isVisible = false }
        #expect(doc.movieFrames(atTimeMS: 4000).isEmpty)
    }

    // MARK: - The rule everything else rests on

    @Test("A document with no clips in it is untouched by any of this")
    func nothingChangesForADocumentWithoutTime() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [Layer(name: "Box",
                            content: .annotation(AnnotationContent(shape: .rectangle,
                                                                   colorHex: "#0C0E14")),
                            frame: CGRect(x: 0, y: 0, width: 40, height: 40))]
        #expect(!doc.hasTime)
        #expect(doc.movieFrames(atTimeMS: 4000).isEmpty)
        #expect(doc.drawn(atTimeMS: 4000).layers == doc.layers)
    }
}
