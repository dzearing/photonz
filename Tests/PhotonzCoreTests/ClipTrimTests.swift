import Testing
import CoreGraphics
import Foundation
@testable import PhotonzCore

// Trimming a clip as a TOOL session (`docs/design/video-surface.md` §10).
//
// The session is held to one side while it runs, the way a crop rectangle is,
// and only lands on the document when it is committed. That is what makes
// Escape free: there is nothing to undo, because nothing was written.
@Suite("Trimming a clip")
struct ClipTrimTests {

    /// An eight second recording as one clip, nothing done to it yet.
    private func wholeRecording() -> Layer {
        let movie = MovieRef(pixelSize: CGSize(width: 1280, height: 800), durationMS: 8000)
        var clip = Layer(name: "Recording",
                         content: .image(movie.frameRef(atSourceMS: 0)),
                         frame: CGRect(x: 0, y: 0, width: 1280, height: 800))
        clip.movie = movie
        clip.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: 8000)
        return clip
    }

    @Test("a session opens on the whole clip, with no spare either side")
    func opensWhole() throws {
        let session = try #require(ClipTrimSession(layer: wholeRecording()))
        #expect(session.wholeLengthMS == 8000)
        #expect(session.keepInMS == 0)
        #expect(session.keepOutMS == 8000)
        #expect(session.keptMS == 8000)
        #expect(session.spareBeforeMS == 0)
        #expect(session.spareAfterMS == 0)
        #expect(session.isChanged == false)
        #expect(session.canReset == false)
    }

    @Test("a layer with no time cannot be trimmed")
    func needsTime() {
        var plain = Layer(name: "Arrow", content: .image(ImageRef(pixelSize: .zero)),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        plain.time = nil
        #expect(ClipTrimSession(layer: plain) == nil)
    }

    @Test("dragging the handles in leaves spare at each end")
    func dragsIn() throws {
        var session = try #require(ClipTrimSession(layer: wholeRecording()))
        session.dragIn(toMS: 2000)
        session.dragOut(toMS: 6000)
        #expect(session.keptMS == 4000)
        #expect(session.spareBeforeMS == 2000)
        #expect(session.spareAfterMS == 2000)
        #expect(session.isChanged)
        #expect(session.canReset)
    }

    @Test("the handles never cross, and never leave the recording")
    func handlesClamp() throws {
        var session = try #require(ClipTrimSession(layer: wholeRecording()))
        session.dragOut(toMS: 3000)
        session.dragIn(toMS: 5000)
        #expect(session.keepInMS == 3000 - LayerTime.shortestMS)
        session.dragIn(toMS: -400)
        #expect(session.keepInMS == 0)
        session.dragOut(toMS: 99_000)
        #expect(session.keepOutMS == 8000)
    }

    @Test("Reset gives the whole recording back without leaving the session")
    func resets() throws {
        var session = try #require(ClipTrimSession(layer: wholeRecording()))
        session.dragIn(toMS: 2000)
        session.dragOut(toMS: 6000)
        session.reset()
        #expect(session.keepInMS == 0)
        #expect(session.keepOutMS == 8000)
        #expect(session.canReset == false)
    }

    @Test("committing shortens the clip and reads later into the recording")
    func commits() throws {
        let clip = wholeRecording()
        var session = try #require(ClipTrimSession(layer: clip))
        session.dragIn(toMS: 2000)
        session.dragOut(toMS: 6000)
        let trimmed = try #require(session.applied(to: clip))
        let time = try #require(trimmed.time)
        // The clip stays where it was put and runs for what was kept.
        #expect(time.inMS == 0)
        #expect(time.outMS == 4000)
        #expect(time.sourceInMS == 2000)
        #expect(time.sourceLengthMS == 8000)
        // Nothing was thrown away: the frames either side are still reachable.
        #expect(time.spareBeforeMS == 2000)
        #expect(time.spareAfterMS == 2000)
    }

    @Test("a second session opens on what the first one left, spare and all")
    func cumulative() throws {
        let clip = wholeRecording()
        var first = try #require(ClipTrimSession(layer: clip))
        first.dragIn(toMS: 2000)
        first.dragOut(toMS: 6000)
        let trimmed = try #require(first.applied(to: clip))

        let second = try #require(ClipTrimSession(layer: trimmed))
        #expect(second.wholeLengthMS == 8000)
        #expect(second.keepInMS == 2000)
        #expect(second.keepOutMS == 6000)
        #expect(second.spareBeforeMS == 2000)
        #expect(second.spareAfterMS == 2000)
        #expect(second.canReset)
    }

    @Test("Reset on a trimmed clip puts the whole recording back")
    func resetsATrimmedClip() throws {
        let clip = wholeRecording()
        var first = try #require(ClipTrimSession(layer: clip))
        first.dragIn(toMS: 2000)
        first.dragOut(toMS: 6000)
        let trimmed = try #require(first.applied(to: clip))

        var second = try #require(ClipTrimSession(layer: trimmed))
        second.reset()
        let back = try #require(second.applied(to: trimmed))
        let time = try #require(back.time)
        #expect(time.inMS == 0)
        #expect(time.outMS == 8000)
        #expect(time.sourceInMS == 0)
    }

    @Test("a clip cut into pieces trims by what is on the timeline, pieces and all")
    func trimsACutClip() throws {
        var clip = wholeRecording()
        var pieces = try #require(clip.clipPieces)
        let didSplit = pieces.split(atMS: 3000)
        #expect(didSplit)
        clip.setClipPieces(pieces)
        let afterSplit = try #require(clip.clipPieces)
        #expect(afterSplit.count == 2)

        var session = try #require(ClipTrimSession(layer: clip))
        session.dragIn(toMS: 1000)
        session.dragOut(toMS: 7000)
        let trimmed = try #require(session.applied(to: clip))
        let time = try #require(trimmed.time)
        #expect(time.lengthMS == 6000)
        #expect(time.inMS == 0)
        let after = try #require(trimmed.clipPieces)
        #expect(after.count == 2)
        #expect(after.totalLengthMS == 6000)
        // The first piece now starts a second into the recording; the last one
        // gives a second back at the end.
        #expect(after.piece(at: 0)?.sourceInMS == 1000)
        #expect(after.piece(at: 1)?.sourceOutMS == 7000)
    }

    /// The recording cut at two and six seconds: three pieces, 2 + 4 + 2.
    private func cutInThree() throws -> Layer {
        var clip = wholeRecording()
        var pieces = try #require(clip.clipPieces)
        let first = pieces.split(atMS: 2000)
        let second = pieces.split(atMS: 6000)
        #expect(first && second)
        clip.setClipPieces(pieces)
        return clip
    }

    // The handles run over the whole clip, cuts and all, the way they did in
    // the recording window (`trim-catches-on-a-cut-walk`). A handle that lands
    // on a cut or past it throws away every piece wholly outside it. Until
    // 2026-09-26 the commit refused that outright and Trim did nothing at all.
    @Test("handles on both cuts keep exactly the middle piece")
    func handlesOnTheCutsKeepTheMiddle() throws {
        let clip = try cutInThree()
        var session = try #require(ClipTrimSession(layer: clip))
        session.dragIn(toMS: 2000)
        session.dragOut(toMS: 6000)
        let trimmed = try #require(session.applied(to: clip))
        let after = try #require(trimmed.clipPieces)
        #expect(after.count == 1)
        #expect(after.piece(at: 0)?.sourceInMS == 2000)
        #expect(after.piece(at: 0)?.sourceOutMS == 6000)
        #expect(trimmed.time?.lengthMS == 4000)
        #expect(trimmed.time?.inMS == 0)
    }

    @Test("a handle dragged past a cut drops the piece behind it and trims the next")
    func handlePastACut() throws {
        let clip = try cutInThree()
        var session = try #require(ClipTrimSession(layer: clip))
        session.dragIn(toMS: 3000)
        session.dragOut(toMS: 5000)
        let trimmed = try #require(session.applied(to: clip))
        let after = try #require(trimmed.clipPieces)
        #expect(after.count == 1)
        #expect(after.piece(at: 0)?.sourceInMS == 3000)
        #expect(after.piece(at: 0)?.sourceOutMS == 5000)
        #expect(trimmed.time?.lengthMS == 2000)
    }

    @Test("a handle a sliver short of a cut keeps no sliver of the piece before it")
    func noSliverAtACut() throws {
        let clip = try cutInThree()
        var session = try #require(ClipTrimSession(layer: clip))
        // One millisecond short of each cut: what is left of the outer pieces
        // is shorter than a piece may be, so they go rather than the trim
        // being refused.
        session.dragIn(toMS: 1999)
        session.dragOut(toMS: 6001)
        let trimmed = try #require(session.applied(to: clip))
        let after = try #require(trimmed.clipPieces)
        #expect(after.count == 1)
        #expect(after.piece(at: 0)?.sourceInMS == 2000)
        #expect(after.piece(at: 0)?.sourceOutMS == 6000)
    }

    @Test("a trim across cuts is still one edit that Reset and a second session can undo")
    func acrossCutsGivesBack() throws {
        let clip = try cutInThree()
        var session = try #require(ClipTrimSession(layer: clip))
        session.dragIn(toMS: 2000)
        session.dragOut(toMS: 6000)
        let trimmed = try #require(session.applied(to: clip))
        // What is thrown away is the pieces; the frames are still in the
        // recording, so a second session sees them as spare either side.
        let again = try #require(ClipTrimSession(layer: trimmed))
        #expect(again.spareBeforeMS == 2000)
        #expect(again.spareAfterMS == 2000)
        #expect(again.wholeLengthMS == 8000)
    }

    // A handle dragged by hand catches on a cut, the way a Premiere trim
    // snaps to an edit point, so landing exactly on one does not take a
    // steady hand (`trim-catches-on-a-cut-walk`).
    @Test("the session knows where the cuts are, in its own milliseconds")
    func knowsTheCuts() throws {
        let session = try #require(ClipTrimSession(layer: try cutInThree()))
        #expect(session.cutsMS == [2000, 6000])
        let whole = try #require(ClipTrimSession(layer: wholeRecording()))
        #expect(whole.cutsMS.isEmpty)
    }

    @Test("a handle near a cut catches on it, and one clear of it does not")
    func catchesNearACut() throws {
        let session = try #require(ClipTrimSession(layer: try cutInThree()))
        #expect(session.caught(1950, withinMS: 60) == 2000)
        #expect(session.caught(6040, withinMS: 60) == 6000)
        #expect(session.caught(1800, withinMS: 60) == 1800)
        // No tolerance is snapping switched off: the hand goes where it goes.
        #expect(session.caught(1950, withinMS: 0) == 1950)
    }

    @Test("the cuts are counted from where a previous trim left the clip")
    func cutsAfterATrim() throws {
        let clip = try cutInThree()
        var first = try #require(ClipTrimSession(layer: clip))
        first.dragIn(toMS: 1000)
        let trimmed = try #require(first.applied(to: clip))
        let again = try #require(ClipTrimSession(layer: trimmed))
        // A second left spare at the front, then a one second piece: the cut
        // is where it always was in the recording.
        #expect(again.cutsMS == [2000, 6000])
    }

    @Test("a trim the clip cannot take changes nothing")
    func refusesTheImpossible() throws {
        var clip = wholeRecording()
        clip.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: nil)
        let session = try #require(ClipTrimSession(layer: clip))
        // No recording behind it, so there is nothing spare to give back and
        // the whole extent is what is on the timeline.
        #expect(session.wholeLengthMS == 8000)
        #expect(session.spareAfterMS == 0)
    }

    @Test("committing to the document moves the document's own duration with it")
    func retimesTheDocument() throws {
        let movie = MovieRef(pixelSize: CGSize(width: 1280, height: 800), durationMS: 8000)
        var document = PhotonzDocument.recording(movie, name: "Recording")
        let clipID = try #require(document.allLayers.first(where: \.isClip)?.id)
        #expect(document.documentDurationMS == 8000)

        let clip = try #require(document.layer(id: clipID))
        var session = try #require(ClipTrimSession(layer: clip))
        session.dragIn(toMS: 2000)
        session.dragOut(toMS: 6000)
        let landed = document.applyTrim(session)
        #expect(landed)
        #expect(document.documentDurationMS == 4000)
        #expect(document.layer(id: clipID)?.time?.outMS == 4000)
    }

    @Test("an untouched session lands nothing on the document")
    func nothingToCommit() throws {
        let movie = MovieRef(pixelSize: CGSize(width: 1280, height: 800), durationMS: 8000)
        var document = PhotonzDocument.recording(movie, name: "Recording")
        let clipID = try #require(document.allLayers.first(where: \.isClip)?.id)
        let clip = try #require(document.layer(id: clipID))
        let session = try #require(ClipTrimSession(layer: clip))
        let landed = document.applyTrim(session)
        #expect(landed == false)
        #expect(document.documentDurationMS == 8000)
    }

    @Test("the clip a trim should open on is the topmost one under the playhead")
    func picksAClip() throws {
        let movie = MovieRef(pixelSize: CGSize(width: 1280, height: 800), durationMS: 8000)
        var document = PhotonzDocument.recording(movie, name: "Recording")
        let clipID = try #require(document.allLayers.first(where: \.isClip)?.id)
        #expect(document.clipToTrim(pickedLayerID: nil, atTimeMS: 1000) == clipID)
        #expect(document.clipToTrim(pickedLayerID: clipID, atTimeMS: 1000) == clipID)
        // A moment past the end of everything has no clip to offer.
        #expect(document.clipToTrim(pickedLayerID: nil, atTimeMS: 99_000) == nil)
    }
}

// While a trim runs, the whole recording is on the timeline.
@Suite("A trim lays the whole recording out")
struct ClipTrimPreviewTests {

    private func trimmedDocument() throws -> (PhotonzDocument, UUID) {
        let movie = MovieRef(pixelSize: CGSize(width: 1280, height: 800), durationMS: 8000)
        var document = PhotonzDocument.recording(movie, name: "Recording")
        let clipID = try #require(document.allLayers.first(where: \.isClip)?.id)
        let clip = try #require(document.layer(id: clipID))
        var first = try #require(ClipTrimSession(layer: clip))
        first.dragIn(toMS: 2000)
        first.dragOut(toMS: 6000)
        _ = document.applyTrim(first)
        return (document, clipID)
    }

    @Test("opening a session on a trimmed clip puts every frame back on the strip")
    func opensTheWholeThing() throws {
        let (document, clipID) = try trimmedDocument()
        #expect(document.documentDurationMS == 4000)
        let clip = try #require(document.layer(id: clipID))
        let session = try #require(ClipTrimSession(layer: clip))
        let opened = document.openedForTrim(session)
        #expect(opened.documentDurationMS == 8000)
        let shown = try #require(opened.layer(id: clipID)?.time)
        #expect(shown.inMS == 0)
        #expect(shown.outMS == 8000)
        #expect(shown.sourceInMS == 0)
        // And the real document is untouched: nothing was written down.
        #expect(document.documentDurationMS == 4000)
    }

    @Test("a clip with nothing spare is laid out exactly as it already was")
    func nothingToOpen() throws {
        let movie = MovieRef(pixelSize: CGSize(width: 1280, height: 800), durationMS: 8000)
        let document = PhotonzDocument.recording(movie, name: "Recording")
        let clipID = try #require(document.allLayers.first(where: \.isClip)?.id)
        let clip = try #require(document.layer(id: clipID))
        let session = try #require(ClipTrimSession(layer: clip))
        #expect(document.openedForTrim(session).documentDurationMS == 8000)
    }
}
