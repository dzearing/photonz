import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// **A box over the tracks, and a range on just the tracks it crosses**
/// (`TrackRange.swift`).
///
/// Final Cut and Premiere both draw a box when a drag starts in empty timeline
/// space: every clip it touches, on the tracks it crosses, is picked. Hold
/// Option (or take Final Cut's Range tool, R) and the same drag picks a stretch
/// of time on those tracks alone, which Delete, Shift-Delete, Cmd-T and the
/// right-click act on while every other track is left exactly as it was.
///
/// A recording cut with the blade is one layer in several pieces here, so a
/// box over part of it picks the pieces it touches, not the whole recording.
///
/// Written before the code, which is the rule for `PhotonzCore`.
@Suite("A box over the tracks, and a range on some of them")
struct TrackRangeTests {

    static func movie() -> MovieRef {
        MovieRef(pixelSize: CGSize(width: 1920, height: 1080), durationMS: 12_000)
    }

    /// A twelve second recording on V1, cut at 4s and 8s into three pieces,
    /// and music on its own track from 1s to 11s. The tracks are written down.
    static func edit() throws -> (doc: PhotonzDocument, clip: UUID, music: UUID, v1: UUID, audio: UUID) {
        var doc = PhotonzDocument.recording(movie(), name: "Talk")
        let clip = doc.layers[0].id
        let did1 = doc.splitClip(clip, atMS: 4000)
        #expect(did1)
        let did2 = doc.splitClip(clip, atMS: 8000)
        #expect(did2)
        let music = doc.addSound(SoundRef(durationMS: 10_000), name: "music", atMS: 1000)
        doc.materializeTracks()
        let v1 = try #require(doc.trackID(ofClip: clip))
        let audio = try #require(doc.trackID(ofClip: music))
        #expect(v1 != audio)
        #expect(doc.layer(id: clip)?.clipPieces?.count == 3)
        return (doc, clip, music, v1, audio)
    }

    static func span(_ doc: PhotonzDocument, _ id: UUID) -> Range<Int>? {
        doc.layer(id: id)?.time.map { $0.inMS..<$0.outMS }
    }

    /// Every clip on a track, left to right, as (in, out).
    static func spans(_ doc: PhotonzDocument, track: UUID) -> [Range<Int>] {
        doc.clipIDs(onTrack: track).compactMap { span(doc, $0) }.sorted { $0.lowerBound < $1.lowerBound }
    }

    // MARK: What is on a track

    @Test("The layers on a track are its clips and everything inside them")
    func layersOnTracks() throws {
        let (doc, clip, music, v1, audio) = try Self.edit()
        #expect(doc.layerIDs(onTracks: [v1]) == [clip])
        #expect(doc.layerIDs(onTracks: [audio]) == [music])
        #expect(doc.layerIDs(onTracks: [v1, audio]) == [clip, music])
        #expect(doc.layerIDs(onTracks: []).isEmpty)
    }

    @Test("A clip's own sound is drawn on an audio track, and a range over that track takes the clip")
    func linkedSoundTakesTheClip() throws {
        let sounding = MovieRef(pixelSize: CGSize(width: 100, height: 60), durationMS: 6000, hasSound: true)
        let doc = PhotonzDocument.recording(sounding, name: "Take")
        let clip = doc.layers[0].id
        let soundTrack = try #require(doc.linkedSoundTrackID(ofClip: clip))
        #expect(doc.layerIDs(onTracks: [soundTrack]) == [clip])
    }

    // MARK: Which tracks a box crosses

    @Test("A box crosses every row its top and bottom reach, and no other")
    func tracksCrossed() {
        let a = UUID(), b = UUID(), c = UUID()
        let rows = [TimelineMarquee.Row(trackID: a, minY: 0, maxY: 40),
                    TimelineMarquee.Row(trackID: b, minY: 44, maxY: 84),
                    TimelineMarquee.Row(trackID: c, minY: 88, maxY: 128)]
        #expect(TimelineMarquee.tracks(crossing: 10...20, rows: rows) == [a])
        #expect(TimelineMarquee.tracks(crossing: 30...50, rows: rows) == [a, b])
        #expect(TimelineMarquee.tracks(crossing: 60...200, rows: rows) == [b, c])
        // The gap between two rows is nobody's.
        #expect(TimelineMarquee.tracks(crossing: 41...43, rows: rows).isEmpty)
    }

    @Test("A box is the stretch between where the hand went down and where it is, either way")
    func boxStretch() {
        #expect(TimelineMarquee.stretch(fromMS: 2000, toMS: 5000, lengthMS: 10_000) == 2000..<5000)
        #expect(TimelineMarquee.stretch(fromMS: 5000, toMS: 2000, lengthMS: 10_000) == 2000..<5000)
        #expect(TimelineMarquee.stretch(fromMS: -300, toMS: 12_000, lengthMS: 10_000) == 0..<10_000)
        // A box with no width still touches the moment it stands on.
        #expect(TimelineMarquee.stretch(fromMS: 3000, toMS: 3000, lengthMS: 10_000) == 3000..<3001)
    }

    // MARK: What a box picks

    @Test("A box over the middle of a cut recording picks only the piece it touches")
    func boxPicksAPiece() throws {
        let (doc, clip, _, v1, _) = try Self.edit()
        #expect(doc.marqueePicks(within: 5000..<6000, onTracks: [v1]) == [TimelinePick(layerID: clip, piece: 1)])
    }

    @Test("A box that touches every piece picks the whole clip")
    func boxPicksTheWholeClip() throws {
        let (doc, clip, _, v1, _) = try Self.edit()
        #expect(doc.marqueePicks(within: 3000..<9000, onTracks: [v1]) == [TimelinePick(layerID: clip, piece: nil)])
    }

    @Test("A box across two tracks picks on both, and a piece it only meets at the edge is not touched")
    func boxAcrossTwoTracks() throws {
        let (doc, clip, music, v1, audio) = try Self.edit()
        let picks = doc.marqueePicks(within: 4000..<6000, onTracks: [v1, audio])
        #expect(Set(picks) == [TimelinePick(layerID: clip, piece: 1), TimelinePick(layerID: music, piece: nil)])
    }

    @Test("A box over the tracks it does not cross picks nothing there")
    func boxOnOneTrackLeavesTheOther() throws {
        let (doc, _, music, _, audio) = try Self.edit()
        #expect(doc.marqueePicks(within: 0..<12_000, onTracks: [audio]) == [TimelinePick(layerID: music, piece: nil)])
        // Before the music starts there is nothing on its track to touch.
        #expect(doc.marqueePicks(within: 0..<900, onTracks: [audio]).isEmpty)
    }

    @Test("Nothing on a locked track is picked")
    func boxSparesLockedTracks() throws {
        var (doc, _, _, _, audio) = try Self.edit()
        doc.updateTrack(audio) { $0.isLocked = true }
        #expect(doc.marqueePicks(within: 0..<12_000, onTracks: [audio]).isEmpty)
    }

    @Test("A pick's span is where it sits on the document's clock")
    func pickSpans() throws {
        let (doc, clip, music, _, _) = try Self.edit()
        #expect(doc.span(of: TimelinePick(layerID: clip, piece: 1)) == 4000..<8000)
        #expect(doc.span(of: TimelinePick(layerID: music, piece: nil)) == 1000..<11_000)
        #expect(doc.span(of: TimelinePick(layerID: clip, piece: 7)) == nil)
    }

    // MARK: A range on some tracks: Lift

    @Test("Lift on one track leaves a gap there and every other track exactly as it was")
    func liftOnOneTrack() throws {
        var (doc, clip, music, _, audio) = try Self.edit()
        let was = try #require(doc.layer(id: clip))
        let did3 = doc.liftStretch(fromMS: 4000, toMS: 6000, onTracks: [audio])
        #expect(did3)
        #expect(doc.layer(id: clip) == was)
        #expect(Self.spans(doc, track: audio) == [1000..<4000, 6000..<11_000])
        #expect(doc.layer(id: music) != nil)
    }

    @Test("Lift over a track with nothing in the stretch does nothing")
    func liftOverNothing() throws {
        var (doc, _, _, _, audio) = try Self.edit()
        let did4 = doc.liftStretch(fromMS: 11_500, toMS: 12_000, onTracks: [audio])
        #expect(!did4)
        #expect(!doc.canTakeOutStretch(fromMS: 11_500, toMS: 12_000, onTracks: [audio]))
        #expect(doc.canTakeOutStretch(fromMS: 11_500, toMS: 12_000, onTracks: nil))
    }

    // MARK: A range on some tracks: Extract

    @Test("Extract on one track closes the gap on that track alone")
    func extractOnOneTrack() throws {
        var (doc, clip, music, v1, _) = try Self.edit()
        let did5 = doc.extractStretch(fromMS: 4000, toMS: 6000, onTracks: [v1])
        #expect(did5)
        #expect(Self.span(doc, clip) == 0..<10_000)
        #expect(Self.span(doc, music) == 1000..<11_000)
        #expect(doc.layer(id: clip)?.clipPieces?.count == 3)
    }

    @Test("Extract on a track pulls a later clip on it back, and leaves a later clip elsewhere")
    func extractMovesOnlyItsTrack() throws {
        var (doc, clip, music, v1, audio) = try Self.edit()
        // Trim the music to 1s..3s and put a sting at 9s on the same track.
        let did6 = doc.liftStretch(fromMS: 3000, toMS: 11_000, onTracks: [audio])
        #expect(did6)
        let sting = doc.addSound(SoundRef(durationMS: 1000), name: "sting", atMS: 9000)
        doc.updateLayer(id: sting) { $0.trackID = audio }
        #expect(doc.trackID(ofClip: sting) == audio)
        let did7 = doc.extractStretch(fromMS: 4000, toMS: 6000, onTracks: [audio])
        #expect(did7)
        #expect(Self.span(doc, sting) == 7000..<8000)
        #expect(Self.span(doc, music) == 1000..<3000)
        #expect(Self.span(doc, clip) == 0..<12_000)
        #expect(doc.trackID(ofClip: clip) == v1)
    }

    // MARK: A range on some tracks: cuts and transitions

    @Test("Split at Range Edges on one track cuts only the clips on it")
    func splitOnOneTrack() throws {
        var (doc, clip, music, _, audio) = try Self.edit()
        let cuts8 = doc.splitEveryClip(atEdgesOf: 2000..<6000, onTracks: [audio])
        #expect(cuts8 == 2)
        #expect(doc.layer(id: clip)?.clipPieces?.count == 3)
        #expect((doc.layer(id: music)?.clipPieces?.count ?? 1) == 3)
    }

    @Test("The cuts inside a range on some tracks are only the cuts on those tracks")
    func transitionCutsOnSomeTracks() throws {
        let (doc, _, _, v1, audio) = try Self.edit()
        let everywhere = doc.transitionCuts(within: 3000..<9000)
        #expect(everywhere.count == 2)
        #expect(doc.transitionCuts(within: 3000..<9000, onTracks: [v1]).count == 2)
        #expect(doc.transitionCuts(within: 3000..<9000, onTracks: [audio]).isEmpty)
    }

    // MARK: Acting on picks

    @Test("Delete on picked pieces takes each out and leaves its gap")
    func liftPicks() throws {
        var (doc, clip, music, v1, _) = try Self.edit()
        let picks = [TimelinePick(layerID: clip, piece: 0), TimelinePick(layerID: clip, piece: 2)]
        let did9 = doc.liftPicks(picks)
        #expect(did9)
        #expect(Self.spans(doc, track: v1) == [4000..<8000])
        #expect(Self.span(doc, music) == 1000..<11_000)
    }

    @Test("Delete on two pieces side by side leaves one gap")
    func liftNeighbouringPicks() throws {
        var (doc, clip, _, v1, _) = try Self.edit()
        let did10 = doc.liftPicks([TimelinePick(layerID: clip, piece: 1), TimelinePick(layerID: clip, piece: 2)])
        #expect(did10)
        #expect(Self.spans(doc, track: v1) == [0..<4000])
    }

    @Test("Delete on a whole picked clip and a piece of another takes both, across tracks")
    func liftAcrossTracks() throws {
        var (doc, clip, music, v1, _) = try Self.edit()
        let did11 = doc.liftPicks([TimelinePick(layerID: music, piece: nil), TimelinePick(layerID: clip, piece: 1)])
        #expect(did11)
        #expect(doc.layer(id: music) == nil)
        #expect(Self.spans(doc, track: v1) == [0..<4000, 8000..<12_000])
    }

    @Test("Ripple Delete on a picked piece closes the gap on its own track only")
    func rippleDeletePicks() throws {
        var (doc, clip, music, v1, _) = try Self.edit()
        let did12 = doc.rippleDeletePicks([TimelinePick(layerID: clip, piece: 1)])
        #expect(did12)
        #expect(Self.spans(doc, track: v1) == [0..<8000])
        #expect(doc.layer(id: clip)?.clipPieces?.count == 2)
        #expect(Self.span(doc, music) == 1000..<11_000)
    }

    @Test("Ripple Delete on pieces of two tracks closes each track's own gap")
    func rippleDeleteAcrossTracks() throws {
        var (doc, clip, music, v1, _) = try Self.edit()
        let did13 = doc.rippleDeletePicks([TimelinePick(layerID: clip, piece: 0), TimelinePick(layerID: clip, piece: 2)])
        #expect(did13)
        #expect(Self.spans(doc, track: v1) == [0..<4000])
        #expect(Self.span(doc, music) == 1000..<11_000)
    }

    // MARK: R

    @Test("R takes Final Cut's Range tool while the timeline has the keyboard, and only then")
    func rangeKey() {
        #expect(TimelineKeys.command(for: TimelineKeyPress(key: .letter("r")), timelineFocused: true) == .rangeTool)
        #expect(TimelineKeys.command(for: TimelineKeyPress(key: .letter("r")), timelineFocused: false) == nil)
        #expect(TimelineKeyCommand.rangeTool.startsAnEdit)
        #expect(!TimelineKeys.leavesToTheCanvas("r"))
    }
}
