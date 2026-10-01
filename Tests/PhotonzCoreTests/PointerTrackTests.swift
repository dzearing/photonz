import CoreGraphics
import Foundation
import PhotonzCore
import Testing

@Suite("Where the pointer went in a recording")
struct PointerTrackTests {

    // A 1512 x 982 point display at 2x, the primary one, so its frame starts
    // at the origin of the global space.
    private let display = CGRect(x: 0, y: 0, width: 1512, height: 982)

    // MARK: - Screen to recording pixels

    @Test func aWholeDisplayRecordingFlipsAndScales() {
        let space = PointerSpace(displayFrame: display,
                                 sourceRect: CGRect(origin: .zero, size: display.size),
                                 pixelSize: CGSize(width: 3024, height: 1964))
        // AppKit's global space counts up from the bottom; a recording's
        // pixels count down from the top.
        #expect(space.pixelPoint(forScreen: CGPoint(x: 0, y: 982)) == CGPoint(x: 0, y: 0))
        #expect(space.pixelPoint(forScreen: CGPoint(x: 100, y: 882)) == CGPoint(x: 200, y: 200))
        #expect(space.pixelPoint(forScreen: CGPoint(x: 1512, y: 0)) == CGPoint(x: 3024, y: 1964))
    }

    @Test func aRegionRecordingCountsFromTheRegionsCorner() {
        // The region overlay reports top-left points within the display.
        let region = CGRect(x: 300, y: 200, width: 400, height: 300)
        let space = PointerSpace(displayFrame: display, sourceRect: region,
                                 pixelSize: CGSize(width: 800, height: 600))
        // The region's top-left corner, in global (bottom-left) points.
        let corner = CGPoint(x: 300, y: 982 - 200)
        #expect(space.pixelPoint(forScreen: corner) == .zero)
        #expect(space.pixelPoint(forScreen: CGPoint(x: 350, y: 982 - 250)) == CGPoint(x: 100, y: 100))
        #expect(space.contains(pixel: CGPoint(x: 100, y: 100)))
        #expect(!space.contains(pixel: space.pixelPoint(forScreen: CGPoint(x: 10, y: 10))))
    }

    @Test func aSecondDisplayIsReadFromItsOwnFrame() {
        // A second display to the right of the first and higher up.
        let second = CGRect(x: 1512, y: 200, width: 1920, height: 1080)
        let space = PointerSpace(displayFrame: second,
                                 sourceRect: CGRect(origin: .zero, size: second.size),
                                 pixelSize: CGSize(width: 1920, height: 1080))
        #expect(space.pixelPoint(forScreen: CGPoint(x: 1512 + 10, y: 200 + 1080 - 20)) == CGPoint(x: 10, y: 20))
    }

    @Test func pixelsThatWereRoundedDownStillLineUp() {
        // 401 points at 2x would be 802, but a recorder that truncates an odd
        // backing size has to land the far edge on the far edge.
        let region = CGRect(x: 0, y: 0, width: 401, height: 301)
        let space = PointerSpace(displayFrame: display, sourceRect: region,
                                 pixelSize: CGSize(width: 801, height: 601))
        let far = space.pixelPoint(forScreen: CGPoint(x: 401, y: 982 - 301))
        #expect(abs(far.x - 801) < 0.001)
        #expect(abs(far.y - 601) < 0.001)
    }

    // MARK: - Taking it down while recording

    private func recording() -> PointerTrackRecording {
        PointerTrackRecording(space: PointerSpace(displayFrame: display,
                                                  sourceRect: CGRect(origin: .zero, size: display.size),
                                                  pixelSize: CGSize(width: 1512, height: 982)))
    }

    @Test func timesCountFromTheFirstFrame() {
        var take = recording()
        take.move(to: CGPoint(x: 10, y: 972), atHostSeconds: 100.0)
        take.press(.left, at: CGPoint(x: 10, y: 972), atHostSeconds: 101.25)
        take.release(.left, at: CGPoint(x: 10, y: 972), atHostSeconds: 101.35)
        let track = take.finished(firstFrameHostSeconds: 100.5)
        #expect(track.clicks.count == 1)
        #expect(track.clicks[0].downMS == 750)
        #expect(track.clicks[0].upMS == 850)
        #expect(track.clicks[0].button == .left)
        #expect(track.clicks[0].point == CGPoint(x: 10, y: 10))
        // The pointer was already there when the picture began.
        #expect(track.position(atMS: 0) == CGPoint(x: 10, y: 10))
    }

    @Test func aClickBeforeThePictureBeganIsNotInIt() {
        var take = recording()
        take.press(.left, at: CGPoint(x: 10, y: 972), atHostSeconds: 99.9)
        take.release(.left, at: CGPoint(x: 10, y: 972), atHostSeconds: 100.0)
        take.press(.right, at: CGPoint(x: 20, y: 962), atHostSeconds: 100.2)
        let track = take.finished(firstFrameHostSeconds: 100.1)
        #expect(track.clicks.map(\.button) == [.right])
        #expect(track.clicks[0].downMS == 100)
        // Still held when it stopped: no release to report.
        #expect(track.clicks[0].upMS == nil)
    }

    @Test func aReleaseClosesTheLatestPressOfItsOwnButton() {
        var take = recording()
        take.press(.left, at: CGPoint(x: 1, y: 981), atHostSeconds: 1.0)
        take.press(.right, at: CGPoint(x: 2, y: 980), atHostSeconds: 1.1)
        take.release(.left, at: CGPoint(x: 3, y: 979), atHostSeconds: 1.2)
        take.release(.right, at: CGPoint(x: 3, y: 979), atHostSeconds: 1.3)
        let track = take.finished(firstFrameHostSeconds: 1.0)
        #expect(track.clicks.map(\.upMS) == [200, 300])
    }

    @Test func aPointerThatDidNotMoveIsWrittenOnce() {
        var take = recording()
        for i in 0..<60 { take.move(to: CGPoint(x: 50, y: 50), atHostSeconds: 10 + Double(i) / 60) }
        take.move(to: CGPoint(x: 60, y: 50), atHostSeconds: 11.0)
        let track = take.finished(firstFrameHostSeconds: 10)
        #expect(track.samples.count == 2)
    }

    @Test func noFirstFrameFallsBackToTheEarliestThingHeard() {
        var take = recording()
        take.move(to: CGPoint(x: 5, y: 977), atHostSeconds: 7.0)
        take.press(.left, at: CGPoint(x: 5, y: 977), atHostSeconds: 7.5)
        let track = take.finished(firstFrameHostSeconds: nil)
        #expect(track.clicks.first?.downMS == 500)
    }

    // MARK: - Reading it back

    @Test func positionsBetweenSamplesAreInBetween() {
        let track = PointerTrack(pixelSize: CGSize(width: 100, height: 100),
                                 samples: [PointerSample(ms: 0, x: 0, y: 0),
                                           PointerSample(ms: 100, x: 100, y: 50)],
                                 clicks: [])
        #expect(track.position(atMS: 50) == CGPoint(x: 50, y: 25))
        #expect(track.position(atMS: 500) == CGPoint(x: 100, y: 50))
        #expect(PointerTrack(pixelSize: .zero, samples: [], clicks: []).position(atMS: 0) == nil)
    }

    @Test func roundTripsThroughJSONCompactly() throws {
        var take = recording()
        for i in 0..<600 {
            take.move(to: CGPoint(x: Double(i), y: 500 + Double(i % 7)), atHostSeconds: Double(i) / 60)
        }
        take.press(.left, at: CGPoint(x: 300, y: 500), atHostSeconds: 5)
        take.release(.left, at: CGPoint(x: 300, y: 500), atHostSeconds: 5.1)
        let track = take.finished(firstFrameHostSeconds: 0)
        let data = try JSONEncoder().encode(track)
        let back = try JSONDecoder().decode(PointerTrack.self, from: data)
        #expect(back == track)
        // Ten seconds of a pointer moving every frame stays small.
        #expect(data.count < 600 * 24)
    }

    // MARK: - Beside the file

    @Test func theSidecarSitsBesideTheRecording() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("pointer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let movie = folder.appendingPathComponent("Recording 1.mp4")
        try Data().write(to: movie)
        #expect(PointerTrackSidecar.url(for: movie).lastPathComponent == "Recording 1.photonzpointer")
        #expect(PointerTrackSidecar.load(for: movie) == nil)

        let track = PointerTrack(pixelSize: CGSize(width: 10, height: 10),
                                 samples: [PointerSample(ms: 0, x: 1, y: 2)],
                                 clicks: [PointerClick(downMS: 5, upMS: 9, point: CGPoint(x: 1, y: 2), button: .left)])
        try PointerTrackSidecar.save(track, for: movie)
        #expect(PointerTrackSidecar.load(for: movie) == track)
    }

    @Test func aRecordingASaveHasRewrittenDoesNotLoadAStaleTrack() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("pointer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let movie = folder.appendingPathComponent("Recording 2.mp4")
        try Data().write(to: movie)
        try PointerTrackSidecar.save(PointerTrack(pixelSize: CGSize(width: 1, height: 1), samples: [], clicks: []),
                                     for: movie)
        let original = VideoOriginals.url(for: movie)
        try FileManager.default.createDirectory(at: original.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data().write(to: original)
        // The track is in the original's time; the file is not the original
        // any more, so the clicks would land on the wrong frames.
        #expect(PointerTrackSidecar.load(for: movie) == nil)
    }

    @Test func anOldDocumentWithNoClicksReadsBackTheSame() throws {
        let movie = MovieRef(pixelSize: CGSize(width: 640, height: 480), durationMS: 5000)
        let doc = PhotonzDocument.recording(movie, name: "Old")
        let data = try JSONEncoder().encode(doc)
        #expect(!String(decoding: data, as: UTF8.self).contains("addedClicks"))
        #expect(try JSONDecoder().decode(PhotonzDocument.self, from: data) == doc)
    }
}

@Suite("Adding a click by hand")
struct AddedClickTests {

    private func document() -> (PhotonzDocument, UUID) {
        let movie = MovieRef(pixelSize: CGSize(width: 640, height: 480), durationMS: 8000)
        let doc = PhotonzDocument.recording(movie, name: "Take")
        return (doc, doc.layers[0].id)
    }

    @Test func aClickLandsOnTheFrameUnderThePlayheadWhereThePictureWasClicked() throws {
        var (doc, id) = document()
        let maybe = doc.addClick(toClip: id, atMS: 2500, canvasPoint: CGPoint(x: 120, y: 80))
        let added = try #require(maybe)
        #expect(added.downMS == 2500)
        #expect(added.point == CGPoint(x: 120, y: 80))
        #expect(added.button == .left)
        #expect(doc.layer(id: id)?.addedClicks == [added])
    }

    @Test func aClipMovedAlongTheTimelineCountsFromItsOwnStart() throws {
        var (doc, id) = document()
        doc.updateLayer(id: id) { $0.time = $0.time?.moved(toInMS: 1000) }
        let maybe = doc.addClick(toClip: id, atMS: 2500, canvasPoint: CGPoint(x: 10, y: 10))
        let added = try #require(maybe)
        // 1.5 s into the clip, 1.5 s into the recording.
        #expect(added.downMS == 1500)
    }

    @Test func aClipMovedOnTheCanvasMapsThePointIntoItsPicture() throws {
        var (doc, id) = document()
        // Shown at half size, moved 100 across.
        doc.updateLayer(id: id) { $0.frame = CGRect(x: 100, y: 0, width: 320, height: 240) }
        let maybe = doc.addClick(toClip: id, atMS: 0, canvasPoint: CGPoint(x: 150, y: 50))
        let added = try #require(maybe)
        #expect(added.point == CGPoint(x: 100, y: 100))
    }

    @Test func refusedOffThePictureOrOutsideTheClip() {
        var (doc, id) = document()
        #expect(doc.addClick(toClip: id, atMS: 9000, canvasPoint: CGPoint(x: 10, y: 10)) == nil)
        #expect(doc.addClick(toClip: id, atMS: 100, canvasPoint: CGPoint(x: 700, y: 10)) == nil)
        #expect(doc.addClick(toClip: UUID(), atMS: 100, canvasPoint: CGPoint(x: 10, y: 10)) == nil)
        #expect(doc.layer(id: id)?.addedClicks == nil)
    }

    @Test func recordedAndAddedClicksReadAsOneListInTime() {
        let recorded = PointerTrack(pixelSize: CGSize(width: 640, height: 480), samples: [],
                                    clicks: [PointerClick(downMS: 3000, upMS: 3080, point: .zero, button: .left)])
        let added = [PointerClick(downMS: 1000, upMS: nil, point: CGPoint(x: 5, y: 5), button: .left)]
        let all = PointerClick.all(recorded: recorded, added: added)
        #expect(all.map(\.downMS) == [1000, 3000])
        #expect(PointerClick.all(recorded: nil, added: nil).isEmpty)
    }

    @Test func aDuplicatedClipKeepsItsAddedClicks() throws {
        var (doc, id) = document()
        _ = doc.addClick(toClip: id, atMS: 100, canvasPoint: CGPoint(x: 1, y: 1))
        let copy = try #require(doc.layer(id: id)).duplicated()
        #expect(copy.addedClicks?.count == 1)
    }
}
