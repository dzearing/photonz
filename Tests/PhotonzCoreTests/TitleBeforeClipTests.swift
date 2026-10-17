import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A title page put in front of a clip, on the clip's own track**
/// (`TitleBeforeClip.swift`, task `insert-a-title-before-a-clip-on-its-track-and-ch`).
///
/// The user, 2026-10-17: "I select a clip, double click a title, it inserts it
/// on the same track as the selected clip before it and adjusts things. And I
/// can visually see the transition between them". So the page is a clip in
/// the sequence, like a recording, the clip and everything after it move along
/// to make room, and the join between them is an edit point with a real
/// transition on it, not a fade baked into the title.
///
/// Written before the model.
@Suite("A title page inserted before a clip")
struct TitleBeforeClipTests {

    static let take = MovieRef(pixelSize: CGSize(width: 1920, height: 1080), durationMS: 8000)
    static let broll = MovieRef(pixelSize: CGSize(width: 1920, height: 1080), durationMS: 6000)

    /// The recording on V1 from 0 to 8s and a voice on its own track from 2s.
    static func recording() -> (doc: PhotonzDocument, take: UUID, voice: UUID) {
        var doc = PhotonzDocument.recording(Self.take, name: "take")
        let take = doc.layers[0].id
        let voice = doc.addSound(SoundRef(durationMS: 2000), name: "voice", atMS: 2000)
        return (doc, take, voice)
    }

    /// Eight seconds used of a ten second recording, from 0 to 8s, with b-roll
    /// butted on from 8s to 12s: spare either side of the cut at 8s.
    static func twoClips() throws -> (doc: PhotonzDocument, take: UUID, broll: UUID, v1: UUID) {
        let long = MovieRef(pixelSize: CGSize(width: 1920, height: 1080), durationMS: 10_000)
        var doc = PhotonzDocument.recording(long, name: "take")
        let take = doc.layers[0].id
        doc.updateLayer(id: take) {
            $0.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: 10_000)
        }
        let v1 = try #require(doc.timelineTracks.first { $0.name == "V1" }?.id)
        var clip = Layer(name: "b-roll", content: .image(Self.broll.frameRef(atSourceMS: 1000)),
                         frame: CGRect(origin: .zero, size: Self.broll.pixelSize))
        clip.movie = Self.broll
        clip.time = LayerTime(inMS: 0, outMS: 4000, sourceInMS: 1000, sourceLengthMS: 6000)
        let landing = doc.clipLanding(kind: .video, lengthMS: 4000, atMS: 8000,
                                      over: .onto(v1), edit: .overwrite)
        let landed = doc.land(clip, at: landing)
        return (doc, take, try #require(landed), v1)
    }

    // MARK: - Where it lands

    @Test("In front of the recording: on V1 at its start, the recording and everything after move along")
    func landsOnTheClipsTrack() throws {
        var (doc, take, voice) = Self.recording()
        let v1 = try #require(doc.trackID(ofClip: take))
        #expect(doc.canInsertTitle(beforeClip: take))
        let landed = doc.insertTitle(.builtIn(.keynote), beforeClip: take)

        let inserted = try #require(landed)
        let page = try #require(doc.layer(id: inserted.layerID))
        #expect(doc.trackID(ofClip: inserted.layerID) == v1)
        #expect(page.time?.inMS == 0 && page.time?.outMS == 4000)
        // The whole recording plays, after the page: nothing of it is hidden.
        #expect(doc.layer(id: take)?.time?.inMS == 4000)
        #expect(doc.layer(id: take)?.time?.sourceInMS == 0)
        #expect(doc.layer(id: take)?.time?.lengthMS == 8000)
        // Everything after it keeps in step with the picture.
        #expect(doc.layer(id: voice)?.time?.inMS == 6000)
        #expect(doc.documentDurationMS == 12_000)
        #expect(doc.editPoints(onTrack: v1).map(\.atMS) == [4000])
    }

    @Test("The page has no fade out of its own: the join's transition is how it leaves")
    func noBakedFade() throws {
        var (doc, take, _) = Self.recording()
        let landed = doc.insertTitle(.builtIn(.keynote), beforeClip: take)

        let inserted = try #require(landed)
        #expect(doc.layer(id: inserted.layerID)?.pictureFadeMS(.out) == 0)
        // A page saved with a fade on it leaves it behind too.
        var fresh = Self.recording()
        var withFade = doc
        withFade.setPictureFade(inserted.layerID, .out, toMS: 500)
        let saved = try #require(withFade.savedTitlePreset(layerID: inserted.layerID, name: "Mine"))
        let landedAgain = fresh.doc.insertTitle(.saved(saved), beforeClip: fresh.take)
        let again = try #require(landedAgain)
        #expect(fresh.doc.layer(id: again.layerID)?.pictureFadeMS(.out) == 0)
    }

    @Test("The join is a cross dissolve on the cut, paid for by the page running on")
    func joinIsATransition() throws {
        var (doc, take, _) = Self.recording()
        let landed = doc.insertTitle(.builtIn(.keynote), beforeClip: take)

        let page = try #require(landed).layerID
        let place = TimelineCutPlace.edit(outgoing: page, incoming: take)
        let cut = try #require(doc.documentCut(at: place))
        #expect(cut.atMS == 4000)
        #expect(cut.outgoingName == "Title Page")
        // A title is drawn, not recorded: it can always run on.
        #expect(cut.cut.spareAfterOutMS == nil)
        let transition = try #require(cut.cut.drawnTransition)
        #expect(transition.kind == .dissolve)
        // The recording starts on its first frame, so it has nothing before
        // its in point: the dissolve sits after the cut, over the page's tail.
        #expect(transition.alignment == .after)
        #expect(transition.lengthMS >= ClipTransition.defaultLengthMS)
    }

    @Test("The join changes like any cut: a cube, a dip, or nothing at all")
    func joinChangesLikeAnyCut() throws {
        var (doc, take, _) = Self.recording()
        let landed = doc.insertTitle(.builtIn(.keynote), beforeClip: take)
        let page = try #require(landed).layerID
        let place = TimelineCutPlace.edit(outgoing: page, incoming: take)

        let cube = try #require(doc.documentCut(at: place)?.cut.fitted(.cube))
        let did1 = doc.setTransition(cube, at: place)
        #expect(did1)
        #expect(doc.documentCut(at: place)?.cut.drawnTransition?.kind == .cube)
        // Half way through the cube both sides are on screen: the page,
        // running on past its end, and the recording.
        let middle = 4000 + cube.lengthMS / 2
        let shown = doc.drawn(atTimeMS: middle)
        #expect(shown.layers.contains { $0.name == "Title Page" && $0.isVisible })
        #expect(shown.layers.contains { $0.id == take && $0.isVisible })

        // A dip needs no overlap and moves nothing.
        let dip = try #require(doc.documentCut(at: place)?.cut.fitted(.dipToBlack))
        let did2 = doc.setTransition(dip, at: place)
        #expect(did2)
        #expect(doc.layer(id: take)?.time?.inMS == 4000)

        // Delete: a straight cut, nothing moving and no gap.
        let did3 = doc.setTransition(nil, at: place)
        #expect(did3)
        #expect(doc.documentCut(at: place)?.cut.transition == nil)
        #expect(doc.layer(id: take)?.time?.inMS == 4000)
        #expect(doc.layer(id: page)?.time?.outMS == 4000)
    }

    @Test("Before a clip in the middle: the cut it took over keeps its transition, the new one dissolves")
    func beforeAClipInTheMiddle() throws {
        var (doc, take, broll, v1) = try Self.twoClips()
        let wipe = ClipTransition(kind: .wipe, lengthMS: 400, alignment: .across)
        let did4 = doc.setTransition(wipe, at: .edit(outgoing: take, incoming: broll))
        #expect(did4)
        let landed = doc.insertTitle(.builtIn(.keynote), beforeClip: broll)

        let page = try #require(landed).layerID
        #expect(doc.layer(id: page)?.time?.inMS == 8000)
        #expect(doc.layer(id: broll)?.time?.inMS == 12_000)
        #expect(doc.layer(id: broll)?.time?.sourceInMS == 1000)
        #expect(doc.editPoints(onTrack: v1).map(\.atMS) == [8000, 12_000])
        // The wipe was on the cut at 8s, and that cut is now the recording
        // into the page: it stays there rather than moving off with the clip.
        #expect(doc.documentCut(at: .edit(outgoing: take, incoming: page))?.cut.transition?.kind == .wipe)
        let join = try #require(doc.documentCut(at: .edit(outgoing: page, incoming: broll)))
        #expect(join.cut.drawnTransition?.kind == .dissolve)
    }

    @Test("Another default kind goes on the join when one is asked for")
    func askedForKind() throws {
        var (doc, take, _) = Self.recording()
        let landed = doc.insertTitle(.builtIn(.keynote), beforeClip: take, join: .dipToBlack)
        let page = try #require(landed).layerID
        let place = TimelineCutPlace.edit(outgoing: page, incoming: take)
        #expect(doc.documentCut(at: place)?.cut.transition?.kind == .dipToBlack)
    }

    // MARK: - When it does not

    @Test("Not before a name card's clip, a sound, a title, or a clip on a locked track")
    func refused() throws {
        var (doc, take, voice) = Self.recording()
        #expect(!doc.canInsertTitle(beforeClip: voice))
        let did5 = doc.insertTitle(.builtIn(.keynote), beforeClip: voice)
        #expect(did5 == nil)
        // A page made of the recording under it has nothing to show in
        // front of one: it is laid over the recording, as before.
        #expect(!TitlePreset.builtIn(.glass).goesInFrontOfAClip)
        #expect(TitlePreset.builtIn(.keynote).goesInFrontOfAClip)
        let overGlass = doc.insertTitle(.builtIn(.glass), beforeClip: take)
        #expect(overGlass == nil)
        // A name card is laid over the picture, never cut into it.
        let did6 = doc.insertTitle(.builtIn(.pill), beforeClip: take)
        #expect(did6 == nil)
        let landed = doc.insertTitle(.builtIn(.keynote), beforeClip: take)
        let page = try #require(landed).layerID
        // A title is not something another title goes in front of.
        #expect(!doc.canInsertTitle(beforeClip: page))
        let v1 = try #require(doc.trackID(ofClip: take))
        doc.updateTrack(v1) { $0.isLocked = true }
        #expect(!doc.canInsertTitle(beforeClip: take))
    }

    // MARK: - Let go on the clip's track

    @Test("A page let go on a recording's track is inserted there, pushing what is after it along")
    func dropOnTheTrackInserts() throws {
        var (doc, take, broll, v1) = try Self.twoClips()
        let landing = try #require(doc.titlePageSequenceLanding(lengthMS: 4000, atMS: 8000, over: .onto(v1)))
        #expect(landing.edit == .insert)
        #expect(landing.target == .onto(v1))
        let landed = doc.insertTitle(.builtIn(.keynote), atTimeMS: 8000, landing: landing)

        let page = try #require(landed).layerID
        #expect(doc.trackID(ofClip: page) == v1)
        #expect(doc.layer(id: page)?.time?.inMS == 8000)
        #expect(doc.layer(id: broll)?.time?.inMS == 12_000)
        #expect(doc.layer(id: take)?.time?.inMS == 0)
        #expect(doc.layer(id: page)?.pictureFadeMS(.out) == 0)
        // It meets b-roll, so the join dissolves, as an insert by a pick does.
        #expect(doc.documentCut(at: .edit(outgoing: page, incoming: broll))?.cut.transition?.kind == .dissolve)
    }

    @Test("Over a title track, an empty track or a locked one there is no sequence to insert into")
    func dropElsewhereIsAnOverlay() throws {
        var (doc, take, _, v1) = try Self.twoClips()
        let landed = doc.insertTitle(.builtIn(.pill), atTimeMS: 1000)
        let card = try #require(landed).layerID
        let titleTrack = try #require(doc.trackID(ofClip: card))
        #expect(doc.titlePageSequenceLanding(lengthMS: 4000, atMS: 1000, over: .onto(titleTrack)) == nil)
        #expect(doc.titlePageSequenceLanding(lengthMS: 4000, atMS: 1000, over: .newTrack(at: 0)) == nil)
        #expect(doc.titlePageSequenceLanding(lengthMS: 4000, atMS: 1000, over: nil) == nil)
        doc.updateTrack(v1) { $0.isLocked = true }
        #expect(doc.titlePageSequenceLanding(lengthMS: 4000, atMS: 8000, over: .onto(v1)) == nil)
        _ = take
    }
}
