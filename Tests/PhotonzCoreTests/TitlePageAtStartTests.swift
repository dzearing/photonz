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
