import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **Where the Captions track sits, and what that does to the picture**
/// (`DocumentTracks.swift`, `CaptionsDrawOnTop.swift`,
/// `docs/design/mocks/pages/video.html` TIMELINE MODEL).
///
/// The mock stacks the tracks Title, V1, V2, Captions, Audio: captions under
/// the picture, just over the sound. A Captions track is not a picture track,
/// though, and captions are read over everything wherever their row is listed,
/// the way Premiere's caption tracks and Resolve's subtitle tracks draw over
/// every video track. So moving the row changes where it is listed and nothing
/// about what you see.
@Suite("Captions track place")
struct CaptionsTrackPlaceTests {

    static let movie = MovieRef(pixelSize: CGSize(width: 1920, height: 1080),
                                durationMS: 6000, hasSound: true)

    static let heard: [TranscribedWord] = [
        TranscribedWord("Capture", startMS: 200, endMS: 700, confidence: 0.9),
        TranscribedWord("the", startMS: 700, endMS: 900, confidence: 0.9),
        TranscribedWord("screen.", startMS: 900, endMS: 1_500, confidence: 0.9),
    ]

    /// A recording with a title typed over it.
    static func titled() -> (doc: PhotonzDocument, recording: UUID, title: UUID) {
        var doc = PhotonzDocument.recording(Self.movie, name: "take")
        let recording = doc.layers[0].id
        var title = Layer(name: "Ship it", content: .text(TextContent(string: "Ship it")),
                          frame: CGRect(x: 600, y: 800, width: 700, height: 200))
        title.time = LayerTime(inMS: 0, outMS: 3000)
        doc.addLayer(title)
        return (doc, recording, title.id)
    }

    static func captioned() -> (doc: PhotonzDocument, recording: UUID, title: UUID, captions: UUID) {
        var (doc, recording, title) = titled()
        let captions = doc.landCaptions(CaptionCues.cues(from: heard)) ?? UUID()
        return (doc, recording, title, captions)
    }

    // MARK: - Where it is listed

    @Test("Captions written on a titled recording list under the picture and over the sound")
    func listedUnderThePicture() {
        let (doc, _, _, captions) = Self.captioned()
        #expect(doc.timelineTracks.map(\.name) == ["Title", "V1", "Captions", "Audio"])
        let row = doc.timelineTracks[2]
        #expect(row.kind == .captions)
        #expect(doc.clipIDs(onTrack: row.id) == [captions])
    }

    @Test("Captions written before the title still list under the picture")
    func titleTypedAfterwards() {
        var doc = PhotonzDocument.recording(Self.movie, name: "take")
        doc.landCaptions(CaptionCues.cues(from: Self.heard))
        var title = Layer(name: "Ship it", content: .text(TextContent(string: "Ship it")),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        title.time = LayerTime(inMS: 0, outMS: 3000)
        doc.addLayer(title)
        #expect(doc.timelineTracks.map(\.name) == ["Title", "V1", "Captions", "Audio"])
    }

    @Test("Captions written after the tracks were written down land under the last picture track")
    func landAfterTracksWereWritten() {
        var (doc, _, _) = Self.titled()
        doc.addTrack(.video)
        doc.landCaptions(CaptionCues.cues(from: Self.heard))
        #expect(doc.timelineTracks.map(\.name) == ["V2", "Title", "V1", "Captions", "Audio"])
    }

    @Test("Writing the tracks down keeps the Captions row where it is listed")
    func materializingKeepsThePlace() {
        var (doc, _, _, _) = Self.captioned()
        let before = doc.timelineTracks
        doc.materializeTracks()
        #expect(doc.timelineTracks == before)
    }

    @Test("A new empty Captions track lands over the sound, under the picture")
    func emptyCaptionsTrack() {
        var (doc, _, _) = Self.titled()
        let id = doc.addTrack(.captions)
        #expect(doc.timelineTracks.map(\.name) == ["Title", "V1", "Captions", "Audio"])
        #expect(doc.timelineTracks[2].id == id)
    }

    @Test("A Captions track somebody carried to the top stays at the top")
    func movedStaysPut() {
        var (doc, _, title, captions) = Self.captioned()
        let row = doc.timelineTracks[2].id
        let topRow = doc.timelineTracks[0].id
        do { let moved = doc.moveTrack(row, .above(topRow)); #expect(moved) }
        #expect(doc.timelineTracks.map(\.name) == ["Captions", "Title", "V1", "Audio"])
        // Another edit later leaves it where it was put.
        doc.updateLayer(id: title) { $0.time = LayerTime(inMS: 500, outMS: 2500) }
        doc.addTrack(.video)
        #expect(doc.timelineTracks.map(\.kind).firstIndex(of: .captions) == 1)
        #expect(doc.drawingOrder.last?.id == captions)
    }

    // MARK: - What is drawn on top

    @Test("Captions are drawn over the picture and the title wherever their row is listed")
    func drawnOnTop() {
        let (doc, recording, title, captions) = Self.captioned()
        #expect(doc.drawingOrder.map(\.id) == [recording, title, captions])
    }

    @Test("A title typed after the captions still draws under them")
    func laterTitleDrawsUnder() {
        var doc = PhotonzDocument.recording(Self.movie, name: "take")
        let captions = doc.landCaptions(CaptionCues.cues(from: Self.heard))
        var title = Layer(name: "Ship it", content: .text(TextContent(string: "Ship it")),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        title.time = LayerTime(inMS: 0, outMS: 3000)
        doc.addLayer(title)
        #expect(doc.layers.last?.id == title.id, "the stack itself is untouched")
        #expect(doc.drawingOrder.last?.id == captions)
    }

    @Test("Carrying the Captions row up or down changes nothing about what is drawn")
    func movingTheRowChangesNothingDrawn() {
        var (doc, _, _, _) = Self.captioned()
        let before = doc.drawingOrder.map(\.id)
        let row = doc.timelineTracks[2].id
        do { let moved = doc.moveTrack(row, .above(doc.timelineTracks[0].id)); #expect(moved) }
        #expect(doc.drawingOrder.map(\.id) == before)
        do { let moved = doc.moveTrack(row, .below(doc.timelineTracks[3].id)); #expect(moved) }
        #expect(doc.drawingOrder.map(\.id) == before)
    }

    @Test("Moving the row keeps the Captions layer at the top of the stack")
    func stackFollows() {
        var (doc, _, _, captions) = Self.captioned()
        let row = doc.timelineTracks[2].id
        do { let moved = doc.moveTrack(row, .below(doc.timelineTracks[3].id)); #expect(moved) }
        #expect(doc.layers.last?.id == captions)
    }

    @Test("A document with no captions draws its stack as it is")
    func noCaptionsNoChange() {
        let (doc, _, _) = Self.titled()
        #expect(doc.drawingOrder.map(\.id) == doc.layers.map(\.id))
    }

    @Test("A click where a caption and the title overlap picks the caption, the one on top")
    func clickPicksTheCaptionOnTop() throws {
        var doc = PhotonzDocument.recording(Self.movie, name: "take")
        doc.landCaptions(CaptionCues.cues(from: Self.heard))
        let box = try #require(doc.captionsLayers.first).frame
        var title = Layer(name: "Ship it", content: .text(TextContent(string: "Ship it")),
                          frame: box)
        title.time = LayerTime(inMS: 0, outMS: 3000)
        doc.addLayer(title)
        let point = CGPoint(x: box.midX, y: box.midY)
        let hit = doc.hidingWhatIsOffScreen(atTimeMS: 400).hitTest(point)
        #expect(hit?.isCaption == true)
    }
}
