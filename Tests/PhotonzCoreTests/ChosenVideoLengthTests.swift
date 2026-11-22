import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A new video keeps the length it was given until something longer lands
/// on it** (`ChosenVideoLength.swift`).
///
/// File > New Video at ten seconds, a four second title page put on it, and
/// the video dropped to four seconds: the title was all there was on it, and
/// every edit that touches time wrote the length again as the end of the last
/// clip. The person chose ten, so ten is the floor. Something longer still
/// makes it longer, and taking that away goes back to ten, not four.
///
/// Written before the change, which is the rule for `PhotonzCore`.
@Suite("A new video keeps the length it was given")
struct ChosenVideoLengthTests {

    static let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    static func movie(seconds: Int) -> MovieRef {
        MovieRef(pixelSize: CGSize(width: 1920, height: 1080), durationMS: seconds * 1000)
    }

    static func tenSeconds() -> History {
        History(document: .emptyVideo(size: frame.size, lengthMS: 10_000))
    }

    @Test func aTitlePageOnATenSecondVideoLeavesItTenSecondsLong() throws {
        var history = Self.tenSeconds()
        var landed: InsertedTitle?
        history.perform { landed = $0.insertTitle(.midnight, atTimeMS: 0) }
        let id = try #require(landed?.layerID)
        let out = try #require(history.current.layer(id: id)?.time?.outMS)
        #expect(out < 10_000)
        #expect(history.current.durationMS == 10_000)
        #expect(history.current.documentDurationMS == 10_000)
    }

    @Test func aTitleDraggedLongerThanTheVideoGrowsItAndBackLeavesTen() throws {
        var history = Self.tenSeconds()
        var landed: InsertedTitle?
        history.perform { landed = $0.insertTitle(.midnight, atTimeMS: 0) }
        let id = try #require(landed?.layerID)
        history.perform { _ = $0.moveLayerEnd(id, toMS: 14_000) }
        #expect(history.current.durationMS == 14_000)
        history.perform { _ = $0.moveLayerEnd(id, toMS: 3_000) }
        #expect(history.current.durationMS == 10_000)
    }

    @Test func aLongerClipGrowsItAndDeletingItGoesBackToTenNotTheTitle() throws {
        var history = Self.tenSeconds()
        history.perform { _ = $0.insertTitle(.midnight, atTimeMS: 0) }
        var clip = UUID()
        history.perform { clip = $0.addClip(Self.movie(seconds: 15), name: "long", atMS: 0, frame: Self.frame) }
        #expect(history.current.durationMS == 15_000)
        history.perform { _ = $0.removeLayer(id: clip) }
        #expect(history.current.durationMS == 10_000)
    }

    @Test func aLongerClipTrimmedShortGoesBackToTen() throws {
        var history = Self.tenSeconds()
        var clip = UUID()
        history.perform { clip = $0.addClip(Self.movie(seconds: 15), name: "long", atMS: 0, frame: Self.frame) }
        #expect(history.current.durationMS == 15_000)
        history.perform { $0.updateLayer(id: clip) { $0.time = $0.time.map { LayerTime(inMS: $0.inMS, outMS: 4000, sourceInMS: $0.sourceInMS) } } }
        #expect(history.current.durationMS == 10_000)
    }

    @Test func theChosenLengthIsSavedWithTheDocument() throws {
        var doc = PhotonzDocument.emptyVideo(size: Self.frame.size, lengthMS: 10_000)
        _ = doc.insertTitle(.midnight, atTimeMS: 0)
        let data = try JSONEncoder().encode(doc)
        var opened = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(opened == doc)
        _ = opened.insertTitle(.midnight, atTimeMS: 0)
        #expect(opened.durationMS == 10_000)
    }

    @Test func aRecordingHasNoChosenLengthAndStillEndsWithItsLastClip() {
        // Not made with New Video: a recording is as long as what is in it.
        var doc = PhotonzDocument(canvasSize: Self.frame.size)
        doc.durationMS = 8000
        doc.addClip(Self.movie(seconds: 8), name: "rec", atMS: 0, frame: Self.frame)
        var history = History(document: doc)
        // A title over the middle of it, ending before the recording does.
        history.perform { _ = $0.insertTitle(.midnight, atTimeMS: 1000) }
        #expect(history.current.durationMS == 8000)
        let rec = history.current.layers.first { $0.name == "rec" }?.id
        history.perform { if let rec { _ = $0.removeLayer(id: rec) } }
        #expect((history.current.durationMS ?? 0) < 8000)
        #expect(history.current.chosenLengthMS == nil)
    }

    @Test func aDocumentWithoutTimeSavesNoChosenLength() throws {
        let doc = PhotonzDocument(canvasSize: Self.frame.size)
        let json = try #require(String(data: JSONEncoder().encode(doc), encoding: .utf8))
        #expect(!json.contains("chosenLength"))
    }
}
