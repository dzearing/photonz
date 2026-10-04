import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A title page put at the very start of a recording plays BEFORE it, the way
/// a Premiere editor puts a title on V1 ahead of the clip with a dissolve at
/// the cut, rather than over its first seconds (task
/// `a-title-page-at-the-start-pushes-the-recording-a`).
///
/// Written before the model.
@Suite("A title page at the start pushes the recording")
struct TitlePageAtStartTests {

    static let take = MovieRef(pixelSize: CGSize(width: 1920, height: 1080), durationMS: 8000)

    /// The recording from 0 to 8s, and a voice on its own track from 2s.
    static func recording() -> (doc: PhotonzDocument, take: UUID, voice: UUID) {
        var doc = PhotonzDocument.recording(Self.take, name: "take")
        let take = doc.layers[0].id
        let voice = doc.addSound(SoundRef(durationMS: 2000), name: "voice", atMS: 2000)
        return (doc, take, voice)
    }

    @Test("At 0:00 over a recording, the recording starts as the page fades out")
    func pushesTheRecording() throws {
        var (doc, take, voice) = Self.recording()
        let landed = doc.insertTitle(.midnight, atTimeMS: 0)

        let inserted = try #require(landed)
        let page = try #require(doc.layer(id: inserted.layerID))
        let pageTime = try #require(page.time)
        let fadeOut = page.pictureFadeMS(.out)
        #expect(pageTime.inMS == 0 && pageTime.outMS == 4000)
        #expect(fadeOut > 0)
        // Title length less its fade out: the two overlap exactly for the
        // dissolve, so no frame of the recording plays hidden.
        #expect(doc.layer(id: take)?.time?.inMS == 4000 - fadeOut)
        #expect(doc.layer(id: take)?.time?.sourceInMS == 0)
        #expect(doc.layer(id: take)?.time?.lengthMS == 8000)
        // Everything else keeps in step with the picture.
        #expect(doc.layer(id: voice)?.time?.inMS == 2000 + 4000 - fadeOut)
        #expect(doc.documentDurationMS == 8000 + 4000 - fadeOut)
    }

    @Test("A saved page that slides off, with no fade, is followed by the recording at its end")
    func noFadeMeansNoOverlap() throws {
        var (doc, take, _) = Self.recording()
        let landed = doc.insertTitle(.midnight, atTimeMS: 0)

        let inserted = try #require(landed)
        doc.setPictureFade(inserted.layerID, .out, toMS: 0)
        let saved = try #require(doc.savedTitlePreset(layerID: inserted.layerID, name: "Mine"))
        var fresh = Self.recording()
        let again = fresh.doc.insertTitle(saved, atTimeMS: 0)

        #expect(again != nil)
        #expect(fresh.doc.layer(id: fresh.take)?.time?.inMS == saved.lengthMS)
        _ = take
    }

    @Test("Inserting anywhere else still lays the page over the recording")
    func elsewhereOverlays() throws {
        var (doc, take, voice) = Self.recording()
        let landed = doc.insertTitle(.midnight, atTimeMS: 3000)

        #expect(landed != nil)
        #expect(doc.layer(id: take)?.time?.inMS == 0)
        #expect(doc.layer(id: voice)?.time?.inMS == 2000)
    }

    @Test("A name card at 0:00 sits over the recording, it does not push it")
    func aNameCardOverlays() throws {
        var (doc, take, _) = Self.recording()
        let landed = doc.insertTitle(.bar, atTimeMS: 0)

        #expect(landed != nil)
        #expect(doc.layer(id: take)?.time?.inMS == 0)
    }

    @Test("A document whose first picture starts later is not pushed")
    func noRecordingAtTheStart() throws {
        var (doc, take, _) = Self.recording()
        doc.updateLayer(id: take) { $0.time = $0.time?.moved(toInMS: 1000) }
        let landed = doc.insertTitle(.midnight, atTimeMS: 0)

        #expect(landed != nil)
        #expect(doc.layer(id: take)?.time?.inMS == 1000)
    }

    @Test("A recording on a locked track stays put, and the page lies over it")
    func lockedTrackStays() throws {
        var (doc, take, voice) = Self.recording()
        let track = try #require(doc.trackID(ofClip: take))
        doc.updateTrack(track) { $0.isLocked = true }
        let landed = doc.insertTitle(.midnight, atTimeMS: 0)

        #expect(landed != nil)
        #expect(doc.layer(id: take)?.time?.inMS == 0)
        #expect(doc.layer(id: voice)?.time?.inMS == 2000)
    }

    @Test("A page let go at 0:00 from the Library pushes the recording too")
    func aDropPushesToo() throws {
        var (doc, take, _) = Self.recording()
        let preset = TitlePreset.builtIn(.midnight)
        let landing = doc.titleLanding(lengthMS: preset.lengthMS, atMS: 0, over: nil)
        let landed = doc.insertTitle(preset, atTimeMS: 0, landing: landing)

        let inserted = try #require(landed)
        let fadeOut = try #require(doc.layer(id: inserted.layerID)).pictureFadeMS(.out)
        #expect(doc.layer(id: take)?.time?.inMS == 4000 - fadeOut)
    }
}

/// Once an opening page has pushed the recording, its dissolve stays over the
/// recording's start whatever its fade out becomes: a longer fade brings the
/// recording in earlier, a shorter one sends it later, and taking the page
/// away rippled leaves the recording at 0:00 (task
/// `an-opening-title-page-keeps-its-dissolve-onto-th`).
///
/// Written before the model.
@Suite("An opening title page keeps its dissolve")
struct OpeningTitleDissolveTests {

    static func opened() throws -> (doc: PhotonzDocument, page: UUID, take: UUID, voice: UUID) {
        var (doc, take, voice) = TitlePageAtStartTests.recording()
        let inserted = doc.insertTitle(.midnight, atTimeMS: 0)
        let landed = try #require(inserted)
        return (doc, landed.layerID, take, voice)
    }

    static func fadeStart(_ doc: PhotonzDocument, _ page: UUID) -> Int? {
        guard let layer = doc.layer(id: page), let time = layer.time else { return nil }
        return time.outMS - layer.pictureFadeMS(.out)
    }

    @Test("A longer fade out brings the recording in where the fade begins")
    func longerFadeBringsItIn() throws {
        var (doc, page, take, voice) = try Self.opened()
        let voiceBefore = try #require(doc.layer(id: voice)?.time?.inMS)
        let takeBefore = try #require(doc.layer(id: take)?.time?.inMS)

        let done = doc.setPictureFade(page, .out, toMS: 1000)
        #expect(done)

        #expect(doc.layer(id: page)?.time?.inMS == 0)
        #expect(doc.layer(id: page)?.time?.outMS == 4000)
        #expect(doc.layer(id: take)?.time?.inMS == 3000)
        #expect(Self.fadeStart(doc, page) == 3000)
        // Everything after moves with it.
        #expect(doc.layer(id: voice)?.time?.inMS == voiceBefore - (takeBefore - 3000))
        #expect(doc.layer(id: take)?.time?.lengthMS == 8000)
        #expect(doc.documentDurationMS == 3000 + 8000)
    }

    @Test("A shorter fade out sends the recording later, and none puts it at the page's end")
    func shorterFadeSendsItLater() throws {
        var (doc, page, take, _) = try Self.opened()

        let shorter = doc.setPictureFade(page, .out, toMS: 250)
        #expect(shorter)
        #expect(doc.layer(id: take)?.time?.inMS == 3750)

        let none = doc.setPictureFade(page, .out, toMS: 0)
        #expect(none)
        #expect(doc.layer(id: take)?.time?.inMS == 4000)

        // A straight cut out of the opening page: a fade put on it is a
        // dissolve into the recording, not a dip to black before it.
        let longer = doc.setPictureFade(page, .out, toMS: 1000)
        #expect(longer)
        #expect(doc.layer(id: take)?.time?.inMS == 3000)
    }

    @Test("A fade in on the page moves nothing")
    func fadeInMovesNothing() throws {
        var (doc, page, take, _) = try Self.opened()
        let before = try #require(doc.layer(id: take)?.time?.inMS)

        let done = doc.setPictureFade(page, .in, toMS: 1000)
        #expect(done)
        #expect(doc.layer(id: take)?.time?.inMS == before)
    }

    @Test("A page placed by hand elsewhere changes nothing else with its fade")
    func elsewhereChangesNothing() throws {
        var (doc, take, voice) = TitlePageAtStartTests.recording()
        let inserted = doc.insertTitle(.midnight, atTimeMS: 3000)

        let landed = try #require(inserted)

        let done = doc.setPictureFade(landed.layerID, .out, toMS: 1000)
        #expect(done)
        #expect(doc.layer(id: take)?.time?.inMS == 0)
        #expect(doc.layer(id: voice)?.time?.inMS == 2000)
    }

    @Test("A page at 0:00 laid over a recording that was not pushed moves nothing")
    func overlaidOpeningMovesNothing() throws {
        var (doc, take, _) = TitlePageAtStartTests.recording()
        let track = try #require(doc.trackID(ofClip: take))
        doc.updateTrack(track) { $0.isLocked = true }
        let inserted = doc.insertTitle(.midnight, atTimeMS: 0)
        let landed = try #require(inserted)
        doc.updateTrack(track) { $0.isLocked = false }

        let done = doc.setPictureFade(landed.layerID, .out, toMS: 1000)
        #expect(done)
        #expect(doc.layer(id: take)?.time?.inMS == 0)
    }

    @Test("A recording on a locked track stays where it is")
    func lockedRecordingStays() throws {
        var (doc, page, take, _) = try Self.opened()
        let before = try #require(doc.layer(id: take)?.time?.inMS)
        let track = try #require(doc.trackID(ofClip: take))
        doc.updateTrack(track) { $0.isLocked = true }

        let done = doc.setPictureFade(page, .out, toMS: 1000)
        #expect(done)
        #expect(doc.layer(id: take)?.time?.inMS == before)
    }

    @Test("Ripple Delete on the opening page puts the recording back at 0:00")
    func rippleDeleteClosesTheWholeStart() throws {
        var (doc, page, take, voice) = try Self.opened()

        let done = doc.rippleDeleteLayer(page)
        #expect(done)
        #expect(doc.layer(id: take)?.time?.inMS == 0)
        #expect(doc.layer(id: voice)?.time?.inMS == 2000)
        #expect(doc.documentDurationMS == 8000)
    }
}
