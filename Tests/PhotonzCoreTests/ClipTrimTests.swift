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

// The fast lane (`docs/design/video-surface.md` §10.3).
@Suite("A fresh recording opens with Trim in hand")
struct ClipTrimFastLaneTests {

    private func movie() -> MovieRef {
        MovieRef(pixelSize: CGSize(width: 1280, height: 800), durationMS: 8000)
    }

    @Test("one clip, never edited")
    func freshRecording() {
        #expect(PhotonzDocument.recording(movie(), name: "Recording").opensWithTrimInHand)
    }

    @Test("a screenshot never does")
    func screenshot() {
        let document = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [])
        #expect(document.opensWithTrimInHand == false)
    }

    @Test("a recording somebody has already trimmed opens the ordinary way")
    func alreadyTrimmed() throws {
        var document = PhotonzDocument.recording(movie(), name: "Recording")
        let clipID = try #require(document.allLayers.first(where: \.isClip)?.id)
        let clip = try #require(document.layer(id: clipID))
        var session = try #require(ClipTrimSession(layer: clip))
        session.dragOut(toMS: 6000)
        _ = document.applyTrim(session)
        #expect(document.opensWithTrimInHand == false)
    }

    @Test("a recording that has been cut into pieces opens the ordinary way")
    func alreadyCut() throws {
        var document = PhotonzDocument.recording(movie(), name: "Recording")
        let clipID = try #require(document.allLayers.first(where: \.isClip)?.id)
        let didSplit = document.splitClip(clipID, atMS: 3000)
        #expect(didSplit)
        #expect(document.opensWithTrimInHand == false)
    }
}
