import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// What a video guide waits for, read off the document rather than wired into
/// every command that could do it (`TutorialDocumentChange.swift`).
///
/// The Video track asks a person to cut, trim, bring a clip in, key a title,
/// put a transition on a cut and retype a caption. Each of those has three or
/// four ways in (a key, a menu row, a right click, a drag), so an event per
/// command would be a dozen wires for every step. Every one of them lands in
/// the document through the same door, though, so the step asks one question
/// of the document before and after: did THIS kind of thing just happen?
///
/// Written before the code, which is the rule for `PhotonzCore`.
@Suite("Tutorials: what a video guide waits for, read off the document")
struct TutorialDocumentChangeTests {

    static let take = MovieRef(pixelSize: CGSize(width: 1280, height: 800), durationMS: 8000)
    static let broll = MovieRef(pixelSize: CGSize(width: 1280, height: 800), durationMS: 6000)

    static func recording() -> (doc: PhotonzDocument, clip: UUID) {
        let doc = PhotonzDocument.recording(Self.take, name: "Tutorial Sample")
        return (doc, doc.layers[0].id)
    }

    /// The recording with b-roll butted onto its end on V1, so there is a cut
    /// between two clips.
    static func twoClips() throws -> (doc: PhotonzDocument, take: UUID, broll: UUID) {
        var (doc, take) = Self.recording()
        let v1 = try #require(doc.timelineTracks.first { $0.name == "V1" }?.id)
        var clip = Layer(name: "b-roll", content: .image(Self.broll.frameRef(atSourceMS: 1000)),
                         frame: CGRect(origin: .zero, size: Self.broll.pixelSize))
        clip.movie = Self.broll
        clip.time = LayerTime(inMS: 0, outMS: 4000, sourceInMS: 1000, sourceLengthMS: 6000)
        let landing = doc.clipLanding(kind: .video, lengthMS: 4000, atMS: 8000,
                                      over: .onto(v1), edit: .overwrite)
        let landed = doc.land(clip, at: landing)
        let broll = try #require(landed)
        return (doc, take, broll)
    }

    static func title(_ words: String = "Hello") -> Layer {
        var layer = Layer(name: words, content: .text(TextContent(string: words, fontSize: 48)),
                          frame: CGRect(x: 100, y: 100, width: 300, height: 60))
        layer.time = LayerTime(inMS: 1000, outMS: 5000)
        return layer
    }

    static func cue(_ text: String, _ inMS: Int, _ outMS: Int) -> CaptionCue {
        let words = text.split(separator: " ").map(String.init)
        let step = (outMS - inMS) / max(1, words.count)
        return CaptionCue(words: words.enumerated().map { index, word in
            TranscribedWord(word, startMS: inMS + index * step, endMS: inMS + (index + 1) * step)
        }, inMS: inMS, outMS: outMS)
    }

    private func happened(_ trigger: TutorialTrigger, _ before: PhotonzDocument,
                          _ after: PhotonzDocument) -> Bool {
        TutorialDocumentChange.happened(trigger, from: before, to: after)
    }

    // MARK: Which triggers these are

    @Test("The seven video triggers are answered by the document, and nothing else is")
    func onlyTheDocumentTriggers() {
        let answered: [TutorialTrigger] = [.timeTakenOut, .clipCut, .clipAdded, .titleAdded,
                                           .keyAdded, .transitionAdded, .captionRetyped]
        for trigger in answered {
            #expect(trigger.isDocumentChange, "\(trigger)")
        }
        // A moment the app announces for itself is not asked of the document:
        // an edit is an edit, whatever it was.
        for trigger: TutorialTrigger in [.editMade, .undone, .layerSelected, .panelShown,
                                         .toolPicked(.text), .dialogOpened(.export)] {
            #expect(!trigger.isDocumentChange, "\(trigger)")
        }
        let (doc, _) = Self.recording()
        #expect(!happened(.editMade, doc, doc))
    }

    // MARK: Cutting it down

    @Test("Q takes time out, and so does throwing a piece away, and a cut alone does not")
    func timeTakenOut() {
        let (start, clip) = Self.recording()
        var trimmed = start
        let didRippleTrim = trimmed.rippleTrim(clip: clip, atMS: 2000, .start)
        #expect(didRippleTrim)
        #expect(happened(.timeTakenOut, start, trimmed))

        var cut = start
        let didSplitClip = cut.splitClip(clip, atMS: 3000)
        #expect(didSplitClip)
        #expect(!happened(.timeTakenOut, start, cut), "a cut throws nothing away")

        var thrown = cut
        let didRippleDeleteClipPiece = thrown.rippleDeleteClipPiece(clip, at: 1)
        #expect(didRippleDeleteClipPiece)
        #expect(happened(.timeTakenOut, cut, thrown))
        // And the other way round is not a trim: putting time back is undo.
        #expect(!happened(.timeTakenOut, trimmed, start))
    }

    @Test("B makes a cut, and a trim that throws a whole end away does not")
    func clipCut() {
        let (start, clip) = Self.recording()
        var cut = start
        let didSplitClip = cut.splitClip(clip, atMS: 3000)
        #expect(didSplitClip)
        #expect(happened(.clipCut, start, cut))

        var trimmed = start
        let didRippleTrim = trimmed.rippleTrim(clip: clip, atMS: 2000, .start)
        #expect(didRippleTrim)
        #expect(!happened(.clipCut, start, trimmed))
        #expect(!happened(.clipCut, start, start))
    }

    // MARK: A second clip

    @Test("A clip let go on the timeline is a clip added; a cut in the first one is not")
    func clipAdded() throws {
        let (one, clip) = Self.recording()
        let (two, _, _) = try Self.twoClips()
        #expect(happened(.clipAdded, one, two))
        var cut = one
        cut.splitClip(clip, atMS: 3000)
        #expect(!happened(.clipAdded, one, cut))
        // A title is not a clip, even though it has an in and an out.
        var titled = one
        titled.layers.append(Self.title())
        #expect(!happened(.clipAdded, one, titled))
    }

    // MARK: A title that moves

    @Test("A text layer with words in it is a title; an empty one and a caption are not")
    func titleAdded() {
        let (start, _) = Self.recording()
        var titled = start
        titled.layers.append(Self.title("Launch day"))
        #expect(happened(.titleAdded, start, titled))

        // Clicking with the Text tool before typing anything is not a title yet.
        var empty = start
        empty.layers.append(Self.title(""))
        #expect(!happened(.titleAdded, start, empty))

        // Captions are text, and they arrive by themselves. Their landing must
        // never pass for the person having typed a title.
        var captioned = start
        captioned.landCaptions([Self.cue("hello there", 500, 2000)])
        #expect(captioned.hasCaptions)
        #expect(!happened(.titleAdded, start, captioned))
    }

    @Test("Clicking a diamond keys a value, and a second key at a later moment is another")
    func keyAdded() throws {
        var (start, _) = Self.recording()
        start.layers.append(Self.title())
        let id = try #require(start.layers.last?.id)
        var keyed = start
        let didStartKeying = keyed.startKeying(layerID: id, .motion(.position), atDocumentTimeMS: 1000)
        #expect(didStartKeying)
        #expect(happened(.keyAdded, start, keyed))

        var moved = keyed
        let didSetKeyedValue = moved.setKeyedValue(.point(CGPoint(x: 500, y: 300)), layerID: id,
                                    .motion(.position), atDocumentTimeMS: 3000)
        #expect(didSetKeyedValue)
        #expect(happened(.keyAdded, keyed, moved))
        #expect(!happened(.keyAdded, moved, moved))
    }

    // MARK: A transition

    @Test("A transition on the cut between two clips, or on a join inside one, is a transition added")
    func transitionAdded() throws {
        let (doc, take, broll) = try Self.twoClips()
        var dissolved = doc
        let place = TimelineCutPlace.edit(outgoing: take, incoming: broll)
        let cut = try #require(doc.documentCut(at: place)?.cut)
        let transition = try #require(cut.fitted(.dipToBlack))
        let didSetTransition = dissolved.setTransition(transition, at: place)
        #expect(didSetTransition)
        #expect(happened(.transitionAdded, doc, dissolved))
        #expect(!happened(.transitionAdded, dissolved, doc))

        // A join inside one clip carries one too.
        var (single, clip) = Self.recording()
        single.splitClip(clip, atMS: 4000)
        var joined = single
        let joinPlace = TimelineCutPlace.join(clip: clip, index: 1)
        let joinCut = try #require(single.documentCut(at: joinPlace)?.cut)
        let dip = try #require(joinCut.fitted(.dipToBlack))
        let didSetJoinTransition = joined.setTransition(dip, at: joinPlace)
        #expect(didSetJoinTransition)
        #expect(happened(.transitionAdded, single, joined))
    }

    // MARK: Captions

    @Test("Retyping a caption is a caption retyped; more captions arriving is not")
    func captionRetyped() throws {
        var (start, _) = Self.recording()
        start.landCaptions([Self.cue("hello there", 500, 2000), Self.cue("this is Photons", 2500, 4000)])
        let caption = try #require(start.captionLayers.last)
        var fixed = start
        let didSetCaptionText = fixed.setCaptionText(id: caption.id, to: "this is Photonz")
        #expect(didSetCaptionText)
        #expect(happened(.captionRetyped, start, fixed))

        // The machine hearing more words is not the person correcting one.
        var (fresh, _) = Self.recording()
        fresh.landCaptions([Self.cue("hello there", 500, 2000)])
        #expect(!happened(.captionRetyped, Self.recording().doc, fresh))
        #expect(!happened(.captionRetyped, start, start))
    }
}
