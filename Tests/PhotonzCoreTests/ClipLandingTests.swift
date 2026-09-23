import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A clip let go on the timeline** (`ClipLanding.swift`): a second
/// recording or a sound dropped at a moment and onto a track, the way an
/// editor brings b-roll in.
///
/// Overwrite is what a plain drop does, as in Premiere: whatever was on that
/// track under the new clip makes room by being trimmed, split or taken away.
/// Insert (⌘ held) pushes what comes after along instead. Either way nothing
/// is copied: a clip split in two is two layers reading the same file.
@Suite("Landing a clip on the timeline")
struct ClipLandingTests {

    static let take = MovieRef(pixelSize: CGSize(width: 100, height: 100), durationMS: 8000, hasSound: true)
    static let broll = MovieRef(pixelSize: CGSize(width: 100, height: 100), durationMS: 4000, hasSound: true)

    /// An eight second recording on V1, a title from 5s to 7s on V2 and
    /// fourteen seconds of music under both.
    static func edit() -> (doc: PhotonzDocument, take: UUID, title: UUID, music: UUID) {
        var doc = PhotonzDocument.recording(Self.take, name: "take")
        let take = doc.layers[0].id
        var title = Layer(name: "Hello", content: .text(TextContent(string: "Hello")),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        title.time = LayerTime(inMS: 5000, outMS: 7000)
        doc.addLayer(title)
        let music = doc.addSound(SoundRef(durationMS: 14000), name: "music", atMS: 0)
        return (doc, take, title.id, music)
    }

    static func clip(_ movie: MovieRef = broll, name: String = "b-roll") -> Layer {
        var layer = Layer(name: name, content: .image(movie.frameRef(atSourceMS: 0)),
                          frame: CGRect(origin: .zero, size: movie.pixelSize))
        layer.movie = movie
        layer.time = LayerTime(inMS: 0, outMS: movie.durationMS, sourceInMS: 0,
                               sourceLengthMS: movie.durationMS)
        return layer
    }

    static func track(named name: String, in doc: PhotonzDocument) -> UUID? {
        doc.timelineTracks.first { $0.name == name }?.id
    }

    static func times(on track: UUID, in doc: PhotonzDocument) -> [(String, Int, Int, Int)] {
        doc.clipIDs(onTrack: track).compactMap { doc.layer(id: $0) }
            .compactMap { layer in layer.time.map { (layer.name, $0.inMS, $0.outMS, $0.sourceInMS) } }
            .sorted { $0.1 < $1.1 }
    }

    // MARK: - Where it would land

    @Test("A recording let go over V1 at a moment lands on V1 at that moment")
    func landingReadsTheMomentAndTheTrack() throws {
        let (doc, _, _, _) = Self.edit()
        let v1 = try #require(Self.track(named: "V1", in: doc))
        let landing = doc.clipLanding(kind: .video, lengthMS: 4000, atMS: 8000,
                                      over: .onto(v1), edit: .overwrite)
        #expect(landing.target == .onto(v1))
        #expect(landing.startMS == 8000)
        #expect(landing.lengthMS == 4000)
        #expect(landing.allowed)
        #expect(landing.trackName == "V1")
    }

    @Test("A sound let go over a picture track lands on the nearest sound track instead")
    func soundOverPictureGoesToSound() throws {
        let (doc, _, _, _) = Self.edit()
        let v1 = try #require(Self.track(named: "V1", in: doc))
        let audio = try #require(Self.track(named: "Audio", in: doc))
        let landing = doc.clipLanding(kind: .audio, lengthMS: 3000, atMS: 2500,
                                      over: .onto(v1), edit: .overwrite)
        #expect(landing.target == .onto(audio))
        #expect(landing.startMS == 2500)
        #expect(landing.trackName == "Audio")
    }

    @Test("A sound with no sound track to go to makes one under the picture")
    func soundMakesATrack() throws {
        let doc = PhotonzDocument.recording(Self.take, name: "take")
        let v1 = try #require(Self.track(named: "V1", in: doc))
        let landing = doc.clipLanding(kind: .audio, lengthMS: 3000, atMS: 1000,
                                      over: .onto(v1), edit: .overwrite)
        #expect(landing.target == .newTrack(at: 1))
        #expect(landing.trackName == "Audio")
        #expect(landing.allowed)
    }

    @Test("A locked track takes nothing, and says it is the lock")
    func lockedTrackRefuses() throws {
        var (doc, _, _, _) = Self.edit()
        let v1 = try #require(Self.track(named: "V1", in: doc))
        doc.updateTrack(v1) { $0.isLocked = true }
        let landing = doc.clipLanding(kind: .video, lengthMS: 4000, atMS: 2000,
                                      over: .onto(v1), edit: .overwrite)
        #expect(!landing.allowed)
        #expect(landing.isLocked)
        let before = doc
        let landed = doc.land(Self.clip(), at: landing)
        #expect(landed == nil)
        #expect(doc == before)
    }

    @Test("A moment before the start is the start")
    func momentIsNeverNegative() throws {
        let (doc, _, _, _) = Self.edit()
        let v1 = try #require(Self.track(named: "V1", in: doc))
        let landing = doc.clipLanding(kind: .video, lengthMS: 4000, atMS: -300,
                                      over: .onto(v1), edit: .overwrite)
        #expect(landing.startMS == 0)
    }

    // MARK: - Overwrite

    @Test("Let go at the end of the recording, b-roll butts onto it on V1 and the document grows")
    func buttsOnAtTheEnd() throws {
        var (doc, take, _, _) = Self.edit()
        let v1 = try #require(Self.track(named: "V1", in: doc))
        let landing = doc.clipLanding(kind: .video, lengthMS: 4000, atMS: 8000,
                                      over: .onto(v1), edit: .overwrite)
        let idLanded = doc.land(Self.clip(), at: landing)
        let id = try #require(idLanded)
        #expect(doc.trackID(ofClip: id) == v1)
        #expect(doc.trackID(ofClip: take) == v1)
        #expect(Self.times(on: v1, in: doc).map(\.0) == ["take", "b-roll"])
        #expect(doc.layer(id: id)?.time?.inMS == 8000)
        #expect(doc.layer(id: id)?.time?.outMS == 12000)
        #expect(doc.documentDurationMS == 14000)
        #expect(doc.editPoints(onTrack: v1).map(\.atMS) == [8000])
    }

    @Test("Overwrite in the middle splits the recording round the new clip, reading the same file")
    func overwriteSplits() throws {
        var (doc, take, _, _) = Self.edit()
        let v1 = try #require(Self.track(named: "V1", in: doc))
        let landing = doc.clipLanding(kind: .video, lengthMS: 2000, atMS: 3000,
                                      over: .onto(v1), edit: .overwrite)
        var short = Self.clip()
        short.time = LayerTime(inMS: 0, outMS: 2000, sourceInMS: 0, sourceLengthMS: 4000)
        let idLanded = doc.land(short, at: landing)
        let id = try #require(idLanded)
        let times = Self.times(on: v1, in: doc)
        #expect(times.map(\.0) == ["take", "b-roll", "take"])
        #expect(times.map(\.1) == [0, 3000, 5000])
        #expect(times.map(\.2) == [3000, 5000, 8000])
        // The right half reads the file from five seconds in: nothing moved.
        #expect(times.map(\.3) == [0, 0, 5000])
        #expect(doc.layer(id: take)?.time?.outMS == 3000)
        #expect(doc.layer(id: id) != nil)
        let halves = doc.clipIDs(onTrack: v1).compactMap { doc.layer(id: $0) }.filter { $0.name == "take" }
        #expect(halves.allSatisfy { $0.movie == Self.take })
        #expect(doc.editPoints(onTrack: v1).map(\.atMS) == [3000, 5000])
        // Nothing else moved, and the document is as long as it was.
        #expect(doc.documentDurationMS == 14000)
    }

    @Test("Overwrite over the tail trims it, and over a whole clip takes it away")
    func overwriteTrimsAndRemoves() throws {
        var (doc, take, _, _) = Self.edit()
        let v1 = try #require(Self.track(named: "V1", in: doc))
        let first = doc.clipLanding(kind: .video, lengthMS: 4000, atMS: 6000,
                                    over: .onto(v1), edit: .overwrite)
        let brollLanded = doc.land(Self.clip(), at: first)
        let broll = try #require(brollLanded)
        #expect(doc.layer(id: take)?.time?.outMS == 6000)
        // A second clip let go right over the first takes its place.
        let second = doc.clipLanding(kind: .video, lengthMS: 4000, atMS: 6000,
                                     over: .onto(v1), edit: .overwrite)
        let outroLanded = doc.land(Self.clip(name: "outro"), at: second)
        let outro = try #require(outroLanded)
        #expect(doc.layer(id: broll) == nil)
        #expect(Self.times(on: v1, in: doc).map(\.0) == ["take", "outro"])
        #expect(doc.layer(id: outro)?.time?.inMS == 6000)
    }

    @Test("A cut recording split by an overwrite keeps its pieces on each side")
    func overwriteKeepsPieces() throws {
        var (doc, take, _, _) = Self.edit()
        let didSplit = doc.splitClip(take, atMS: 2000)
        #expect(didSplit)
        let v1 = try #require(Self.track(named: "V1", in: doc))
        var short = Self.clip()
        short.time = LayerTime(inMS: 0, outMS: 1000, sourceInMS: 0, sourceLengthMS: 4000)
        let landing = doc.clipLanding(kind: .video, lengthMS: 1000, atMS: 4000,
                                      over: .onto(v1), edit: .overwrite)
        let landed = doc.land(short, at: landing)
        #expect(landed != nil)
        let left = try #require(doc.layer(id: take))
        #expect(left.clipPieces?.count == 2)
        #expect(left.time?.outMS == 4000)
        let right = try #require(doc.clipIDs(onTrack: v1).compactMap { doc.layer(id: $0) }
            .first { $0.name == "take" && $0.id != take })
        #expect(right.time?.inMS == 5000)
        #expect(right.clipPieces?.sourceMS(atMS: 0) == 5000)
    }

    @Test("A sound let go on the Audio track overwrites the music under it only")
    func soundOverwritesSound() throws {
        var (doc, _, _, music) = Self.edit()
        let audio = try #require(Self.track(named: "Audio", in: doc))
        let landing = doc.clipLanding(kind: .audio, lengthMS: 2000, atMS: 4000,
                                      over: .onto(audio), edit: .overwrite)
        let sound = Layer.sound(SoundRef(durationMS: 2000), name: "swoosh",
                                time: LayerTime(inMS: 0, outMS: 2000, sourceLengthMS: 2000))
        let idLanded = doc.land(sound, at: landing)
        let id = try #require(idLanded)
        #expect(doc.layer(id: id)?.time?.inMS == 4000)
        #expect(doc.layer(id: music)?.time?.outMS == 4000)
        #expect(Self.times(on: audio, in: doc).map(\.0) == ["music", "swoosh", "music"])
    }

    // MARK: - Insert

    @Test("Insert splits the recording and pushes the rest of it, and what starts later, along")
    func insertPushes() throws {
        var (doc, take, title, music) = Self.edit()
        let v1 = try #require(Self.track(named: "V1", in: doc))
        let landing = doc.clipLanding(kind: .video, lengthMS: 4000, atMS: 3000,
                                      over: .onto(v1), edit: .insert)
        #expect(landing.edit == .insert)
        let idLanded = doc.land(Self.clip(), at: landing)
        let id = try #require(idLanded)
        let times = Self.times(on: v1, in: doc)
        #expect(times.map(\.0) == ["take", "b-roll", "take"])
        #expect(times.map(\.1) == [0, 3000, 7000])
        #expect(times.map(\.2) == [3000, 7000, 12000])
        #expect(times.map(\.3) == [0, 0, 3000])
        #expect(doc.layer(id: take)?.time?.outMS == 3000)
        #expect(doc.layer(id: id)?.time?.inMS == 3000)
        // The title started after the insert, so it went with the picture under it.
        #expect(doc.layer(id: title)?.time?.inMS == 9000)
        // The music was already playing, and plays on where it was.
        #expect(doc.layer(id: music)?.time?.inMS == 0)
        #expect(doc.layer(id: music)?.time?.outMS == 14000)
        #expect(doc.documentDurationMS == 14000)
    }

    @Test("Insert at the very start pushes everything that starts there along, music included")
    func insertAtStart() throws {
        var (doc, take, _, music) = Self.edit()
        let v1 = try #require(Self.track(named: "V1", in: doc))
        let landing = doc.clipLanding(kind: .video, lengthMS: 4000, atMS: 0,
                                      over: .onto(v1), edit: .insert)
        let landed = doc.land(Self.clip(), at: landing)
        #expect(landed != nil)
        #expect(doc.layer(id: take)?.time?.inMS == 4000)
        #expect(Self.times(on: v1, in: doc).map(\.0) == ["b-roll", "take"])
        // The music starts where the b-roll went in, so it waits for it too.
        #expect(doc.layer(id: music)?.time?.inMS == 4000)
        #expect(doc.documentDurationMS == 18000)
    }

    @Test("Insert leaves a locked track exactly where it was")
    func insertSkipsLockedTracks() throws {
        var (doc, _, title, _) = Self.edit()
        let v2 = try #require(Self.track(named: "V2", in: doc))
        let v1 = try #require(Self.track(named: "V1", in: doc))
        doc.updateTrack(v2) { $0.isLocked = true }
        let landing = doc.clipLanding(kind: .video, lengthMS: 4000, atMS: 3000,
                                      over: .onto(v1), edit: .insert)
        let landed = doc.land(Self.clip(), at: landing)
        #expect(landed != nil)
        #expect(doc.layer(id: title)?.time?.inMS == 5000)
    }

    // MARK: - A new track

    @Test("Let go between two tracks, the clip lands on a new track made there")
    func newTrackBetween() throws {
        var (doc, _, _, _) = Self.edit()
        let landing = doc.clipLanding(kind: .video, lengthMS: 4000, atMS: 1000,
                                      over: .newTrack(at: 1), edit: .overwrite)
        #expect(landing.trackName == "V3")
        let idLanded = doc.land(Self.clip(), at: landing)
        let id = try #require(idLanded)
        let track = try #require(doc.trackID(ofClip: id))
        #expect(doc.timelineTracks.map(\.id).firstIndex(of: track) == 1)
        #expect(doc.track(id: track)?.name == "V3")
    }

    @Test("A clip on a track under another is further back in the picture")
    func landingRestacks() throws {
        var (doc, _, title, _) = Self.edit()
        let v1 = try #require(Self.track(named: "V1", in: doc))
        let landing = doc.clipLanding(kind: .video, lengthMS: 4000, atMS: 8000,
                                      over: .onto(v1), edit: .overwrite)
        let idLanded = doc.land(Self.clip(), at: landing)
        let id = try #require(idLanded)
        let order = doc.layers.map(\.id)
        let b = try #require(order.firstIndex(of: id))
        let t = try #require(order.firstIndex(of: title))
        #expect(b < t)
    }

    // MARK: - Snapping

    @Test("A start let go near the end of a clip snaps onto it, and so does an end near a start")
    func snapsToEdges() {
        let edges = [0, 8000, 14000]
        #expect(ClipLanding.snapped(startMS: 8120, lengthMS: 4000, to: edges, withinMS: 200) == 8000)
        #expect(ClipLanding.snapped(startMS: 9900, lengthMS: 4000, to: edges, withinMS: 200) == 10000)
        #expect(ClipLanding.snapped(startMS: 5000, lengthMS: 4000, to: edges, withinMS: 200) == 5000)
        #expect(ClipLanding.snapped(startMS: -40, lengthMS: 4000, to: edges, withinMS: 200) == 0)
    }

    @Test("The edges a clip snaps to are where the clips on the timeline start and end")
    func edgesOfTheTimeline() {
        let (doc, _, _, _) = Self.edit()
        #expect(doc.timelineEdgesMS == [0, 5000, 7000, 8000, 14000])
    }

    // MARK: - Edit points

    @Test("Two clips that meet have an edit point; a gap between them has none")
    func editPoints() throws {
        var (doc, take, _, _) = Self.edit()
        let v1 = try #require(Self.track(named: "V1", in: doc))
        #expect(doc.editPoints(onTrack: v1).isEmpty)
        let gap = doc.clipLanding(kind: .video, lengthMS: 4000, atMS: 9000,
                                  over: .onto(v1), edit: .overwrite)
        let laterLanded = doc.land(Self.clip(), at: gap)
        let later = try #require(laterLanded)
        #expect(doc.editPoints(onTrack: v1).isEmpty)
        let didMove = doc.moveClip(later, toInMS: 8000)
        #expect(didMove)
        let points = doc.editPoints(onTrack: v1)
        #expect(points.count == 1)
        #expect(points.first?.outgoing == take)
        #expect(points.first?.incoming == later)
        #expect(points.first?.atMS == 8000)
    }

    // MARK: - What it says

    @Test("A clip let go on the timeline says the track and the moment, not the playhead")
    func landedNoticeSaysWhere() {
        let clip = CopyConfirmation(subject: .landedOnTrack(name: "outro", track: "V1", atMS: 16000,
                                                           isSound: false), shownAt: Date())
        #expect(clip.title == "Clip added")
        #expect(clip.detail == "outro is on V1 at 0:16")
        let sound = CopyConfirmation(subject: .landedOnTrack(name: "music", track: "Audio", atMS: 4000,
                                                            isSound: true), shownAt: Date())
        #expect(sound.title == "Sound added")
    }
}
