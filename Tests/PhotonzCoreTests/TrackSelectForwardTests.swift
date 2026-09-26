import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **Track Select Forward** (`TrackSelectForward.swift`): Premiere's A.
///
/// A click on a clip with the tool picks that clip and every clip that starts
/// at or after it, on every track, and ⇧-click keeps it to the one track. The
/// lot then slides as one, which is how a gap is opened or closed in the
/// middle of an edit without touching anything before it.
@Suite("Track Select Forward")
struct TrackSelectForwardTests {

    static let movie = MovieRef(pixelSize: CGSize(width: 100, height: 100),
                                durationMS: 6000, hasSound: true)

    static func title(_ name: String, _ inMS: Int, _ outMS: Int) -> Layer {
        var title = Layer(name: name, content: .text(TextContent(string: name)),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        title.time = LayerTime(inMS: inMS, outMS: outMS)
        return title
    }

    /// A recording from nought, a title at one second, a second title at four
    /// on the SAME track as the first, and music from nought.
    static func edit() -> (doc: PhotonzDocument, recording: UUID, first: UUID, second: UUID,
                           music: UUID) {
        var doc = PhotonzDocument.recording(Self.movie, name: "take")
        let recording = doc.layers[0].id
        let first = Self.title("Hello", 1000, 3000)
        doc.addLayer(first)
        let music = doc.addSound(SoundRef(durationMS: 5000), name: "music", atMS: 0)
        let second = Self.title("Bye", 4000, 5000)
        doc.addLayer(second)
        let titleTrack = doc.trackID(ofClip: first.id)!
        let moved = doc.moveClip(second.id, toTrack: titleTrack)
        #expect(moved)
        return (doc, recording, first.id, second.id, music)
    }

    // MARK: - The pick

    @Test("A click picks the clip and everything starting at or after it, on every track")
    func picksForwardOnEveryTrack() {
        let (doc, _, first, second, _) = Self.edit()
        let picked = doc.clipsForward(from: first, onItsTrackOnly: false)
        #expect(picked.first == first)
        #expect(Set(picked) == [first, second])
    }

    @Test("From the very first clip it picks the whole edit")
    func fromTheStartPicksEverything() {
        let (doc, recording, first, second, music) = Self.edit()
        let picked = doc.clipsForward(from: recording, onItsTrackOnly: false)
        #expect(picked.first == recording)
        #expect(Set(picked) == [recording, first, second, music])
    }

    @Test("A clip that starts at the same moment as the clicked one comes too")
    func sameStartComes() {
        let (doc, recording, _, _, music) = Self.edit()
        #expect(Set(doc.clipsForward(from: music, onItsTrackOnly: false)).isSuperset(of: [recording, music]))
    }

    @Test("⇧ keeps the pick to the clicked clip's own track")
    func onItsTrackOnly() {
        var (doc, _, first, second, _) = Self.edit()
        // Something later on another track, which the one-track pick leaves.
        let late = doc.addSound(SoundRef(durationMS: 1000), name: "sting", atMS: 3500)
        #expect(Set(doc.clipsForward(from: first, onItsTrackOnly: false)) == [first, second, late])
        #expect(Set(doc.clipsForward(from: first, onItsTrackOnly: true)) == [first, second])
    }

    @Test("Nothing on a locked track is picked, since nothing there can move")
    func lockedTracksAreLeft() {
        var (doc, recording, first, second, music) = Self.edit()
        doc.updateTrack(doc.trackID(ofClip: second)!) { $0.isLocked = true }
        let picked = Set(doc.clipsForward(from: recording, onItsTrackOnly: false))
        #expect(picked == [recording, music])
        #expect(!picked.contains(first))
    }

    @Test("A click on something that is not a clip on the timeline picks nothing")
    func notAClip() {
        let (doc, _, _, _, _) = Self.edit()
        #expect(doc.clipsForward(from: UUID(), onItsTrackOnly: false).isEmpty)
    }

    // MARK: - The move

    @Test("The picked clips slide by the same amount and the document grows to hold them")
    func movesTogether() {
        var (doc, recording, first, second, _) = Self.edit()
        let moved = doc.moveClips([first, second], byMS: 1500)
        #expect(moved)
        #expect(doc.layer(id: first)?.time?.inMS == 2500)
        #expect(doc.layer(id: first)?.time?.outMS == 4500)
        #expect(doc.layer(id: second)?.time?.inMS == 5500)
        #expect(doc.layer(id: second)?.time?.outMS == 6500)
        // What was not picked stays where it was.
        #expect(doc.layer(id: recording)?.time?.inMS == 0)
    }

    @Test("A move left stops when the earliest picked clip reaches the start")
    func stopsAtTheStart() {
        var (doc, _, first, second, _) = Self.edit()
        let moved = doc.moveClips([first, second], byMS: -5000)
        #expect(moved)
        #expect(doc.layer(id: first)?.time?.inMS == 0)
        #expect(doc.layer(id: second)?.time?.inMS == 3000)
    }

    @Test("A move of nothing changes nothing")
    func zeroMove() {
        var (doc, _, first, second, _) = Self.edit()
        let still = doc.moveClips([first, second], byMS: 0)
        let none = doc.moveClips([], byMS: 500)
        #expect(!still)
        #expect(!none)
    }

    // MARK: - The drag

    @Test("A bar dragged with others along stops where the earliest of them reaches the start")
    func dragLimitCountsTheOthers() {
        let pieces = ClipPieces(single: LayerTime(inMS: 2000, outMS: 3000))
        let alone = ClipBarDrag(grab: .body, pieces: pieces, clipStartMS: 2000)
        #expect(alone.landing(byMS: -1800).clipStartMS == 200)
        let together = ClipBarDrag(grab: .body, pieces: pieces, clipStartMS: 2000,
                                   alongStartsMS: [500, 4000])
        #expect(together.limits.least == -500)
        #expect(together.landing(byMS: -1800).movedMS == -500)
        // And S part way through keeps what is along.
        #expect(together.snapping(withinMS: 40).limits.least == -500)
    }

    @Test("The edges a group can catch on leave out every clip in the group")
    func edgesExcludeTheGroup() {
        let (doc, _, first, second, _) = Self.edit()
        let edges = doc.clipBarEdges(excluding: [first, second], playheadMS: nil)
        #expect(!edges.contains { $0.name == "Hello" || $0.name == "Bye" })
        #expect(edges.contains { $0.name == "take" })
    }

    // MARK: - The tool

    @Test("The timeline has three tools, Select first")
    func tools() {
        #expect(TimelineTool.allCases == [.select, .trackSelectForward, .blade])
    }

    @Test("A opens a tucked-away timeline, because the tool works on it")
    func aOpensTheTimeline() {
        #expect(TimelineKeyCommand.trackSelectForwardTool.opensTheTimeline)
    }

    // MARK: - The walk step

    @Test("A walk presses a clip with the timeline's tool in hand and carries it")
    func dragClipStep() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "dragClip", "clip": "b-roll", "byMS": 2000, "modifiers": ["shift"] },
                     { "do": "dragClip", "clip": "b-roll" } ] }
        """.utf8))
        #expect(script.steps[0] == .dragClip(clip: "b-roll", byMS: 2000, modifiers: [.shift]))
        // No distance is a click.
        #expect(script.steps[1] == .dragClip(clip: "b-roll", byMS: 0, modifiers: []))
        #expect(script.steps[0].name == "dragClip")
        #expect(PlaytestStep.names.contains("dragClip"))
    }
}
