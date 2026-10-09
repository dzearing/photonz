import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A gap between clips**: picked with a click, closed with Delete or Ripple
/// Delete, the way Premiere and Final Cut close one (`TimelineGap.swift`).
///
/// Written before the code, which is the rule for `PhotonzCore`.
@Suite("Pick a gap on a track and close it")
struct TimelineGapTests {

    /// The talk from `MarkedStretchTests`, with 4.0s to 8.0s lifted out: two
    /// clips on one track and a four second gap between them.
    static func lifted() throws -> (doc: PhotonzDocument, head: UUID, tail: UUID, track: UUID,
                                    captions: [String: UUID]) {
        var (doc, head, captions) = MarkedStretchTests.talk()
        doc.liftStretch(fromMS: 4000, toMS: 8000)
        let track = try #require(doc.trackID(ofClip: head))
        let tail = try #require(doc.allLayers.first { $0.isClip && $0.id != head })
        return (doc, head, tail.id, track, captions)
    }

    // MARK: Finding one

    @Test("A moment between two clips on a track is in the gap between them")
    func findsTheGap() throws {
        let (doc, _, _, track, _) = try Self.lifted()
        let gap = try #require(doc.gap(onTrack: track, atMS: 5000))
        #expect(gap.trackID == track)
        #expect(gap.range == 4000..<8000)
        #expect(gap.lengthMS == 4000)
        // Any moment in it names the same gap, its first one included.
        #expect(doc.gap(onTrack: track, atMS: 4000) == gap)
        #expect(doc.gap(onTrack: track, atMS: 7999) == gap)
    }

    @Test("A track lists its gaps, and each is the one a moment in it finds")
    func listsTheGaps() throws {
        var (doc, head, tail, track, _) = try Self.lifted()
        doc.updateLayer(id: head) { $0.time = $0.time?.moved(toInMS: 1000) }
        let gaps = doc.gaps(onTrack: track)
        #expect(gaps.map(\.range) == [0..<1000, 5000..<8000])
        for gap in gaps { #expect(doc.gap(onTrack: track, atMS: gap.range.lowerBound) == gap) }
        _ = tail
    }

    @Test("On a clip, and after the last clip, there is no gap")
    func noGapOnAClipOrAfterTheEnd() throws {
        var (doc, _, _, track, _) = try Self.lifted()
        #expect(doc.gap(onTrack: track, atMS: 2000) == nil)
        #expect(doc.gap(onTrack: track, atMS: 9000) == nil)
        // A document longer than its last clip: the space after it is not a gap.
        _ = doc.addSound(SoundRef(durationMS: 20_000), name: "music", atMS: 0)
        #expect(doc.gap(onTrack: track, atMS: 15_000) == nil)
    }

    @Test("The space before the first clip on a track is a gap from 0:00")
    func gapBeforeTheFirstClip() throws {
        var (doc, clip, _) = MarkedStretchTests.talk()
        doc.updateLayer(id: clip) { $0.time = $0.time?.moved(toInMS: 2000) }
        let track = try #require(doc.trackID(ofClip: clip))
        #expect(doc.gap(onTrack: track, atMS: 500)?.range == 0..<2000)
    }

    @Test("The pauses between lines on a Captions track are not gaps")
    func captionsTrackHasNoGaps() throws {
        let (doc, _, _, _, captions) = try Self.lifted()
        let line = try #require(captions["before"])
        let track = try #require(doc.trackID(ofClip: line))
        #expect(doc.track(id: track)?.kind == .captions)
        #expect(doc.gap(onTrack: track, atMS: 3200) == nil)
    }

    // MARK: Closing it

    @Test("Closing the gap slides the next clip and its captions back by the gap's length")
    func closesTheGap() throws {
        var (doc, head, tail, track, captions) = try Self.lifted()
        let gap = try #require(doc.gap(onTrack: track, atMS: 5000))
        #expect(doc.canCloseGap(gap))
        let closed = doc.closeGap(gap)
        #expect(closed)
        #expect(doc.layer(id: head)?.time?.inMS == 0)
        #expect(doc.layer(id: tail)?.time?.inMS == 4000)
        #expect(doc.layer(id: tail)?.time?.outMS == 8000)
        #expect(doc.documentDurationMS == 8000)
        // Captions over the clip that moved, moved with it, words and all.
        let past = try #require(doc.layer(id: captions["past"] ?? UUID()))
        #expect(past.time?.inMS == 4000)
        #expect(past.time?.outMS == 5200)
        #expect(past.captionWords?.first?.startMS == 4000)
        let after = try #require(doc.layer(id: captions["after"] ?? UUID()))
        #expect(after.time?.inMS == 5500)
        #expect(after.captionWords?.last?.endMS == 7000)
        // Captions before the gap are where they were.
        #expect(doc.layer(id: captions["before"] ?? UUID())?.time?.inMS == 1000)
        #expect(doc.layer(id: captions["over"] ?? UUID())?.time?.outMS == 4000)
        // And the gap has gone.
        #expect(doc.gap(onTrack: track, atMS: 4000) == nil)
    }

    // MARK: The rest of the edit goes along

    @Test("A title and music that start after the gap move back with the picture")
    func titleAndMusicGoAlong() throws {
        var (doc, _, tail, track, _) = try Self.lifted()
        let title = MarkedStretchTests.title("Later", 10_000, 11_000)
        doc.addLayer(title)
        let music = doc.addSound(SoundRef(durationMS: 3000), name: "music", atMS: 9000)
        doc.materializeTracks()
        let gap = try #require(doc.gap(onTrack: track, atMS: 5000))
        let closed = doc.closeGap(gap)
        #expect(closed)
        #expect(doc.layer(id: tail)?.time?.inMS == 4000)
        #expect(doc.layer(id: title.id)?.time?.inMS == 6000)
        #expect(doc.layer(id: title.id)?.time?.outMS == 7000)
        #expect(doc.layer(id: music)?.time?.inMS == 5000)
        #expect(doc.documentDurationMS == 8000)
    }

    @Test("Music running across the gap, and a title inside it, stay where they are")
    func acrossAndInsideStay() throws {
        var (doc, _, tail, track, _) = try Self.lifted()
        let bed = doc.addSound(SoundRef(durationMS: 20_000), name: "bed", atMS: 0)
        let inside = MarkedStretchTests.title("Inside", 5000, 6000)
        doc.addLayer(inside)
        let gap = try #require(doc.gap(onTrack: track, atMS: 5000))
        let closed = doc.closeGap(gap)
        #expect(closed)
        #expect(doc.layer(id: tail)?.time?.inMS == 4000)
        #expect(doc.layer(id: bed)?.time?.inMS == 0)
        #expect(doc.layer(id: bed)?.time?.outMS == 20_000)
        #expect(doc.layer(id: inside.id)?.time?.inMS == 5000)
    }

    @Test("A song that would land on one still over the gap keeps it open, and names it")
    func songInTheWayRefuses() throws {
        var (doc, _, tail, track, _) = try Self.lifted()
        let first = doc.addSound(SoundRef(durationMS: 2000), name: "Intro", atMS: 5000)
        let second = doc.addSound(SoundRef(durationMS: 1000), name: "Sting", atMS: 9000)
        doc.materializeTracks()
        let audio = try #require(doc.trackID(ofClip: first))
        _ = doc.moveClip(second, toTrack: audio)
        #expect(doc.trackID(ofClip: second) == audio)
        let gap = try #require(doc.gap(onTrack: track, atMS: 5000))
        #expect(doc.gapCloseRefusal(gap) == .inTheWay("Intro"))
        #expect(doc.gapCloseRefusal(gap)?.reading == "Intro is in the way")
        let before = doc
        let closed = doc.closeGap(gap)
        #expect(!closed)
        #expect(doc == before)
        #expect(doc.layer(id: tail)?.time?.inMS == 8000)
    }

    @Test("Music on a locked track stays put, and the gap still closes")
    func lockedMusicStays() throws {
        var (doc, _, tail, track, _) = try Self.lifted()
        let music = doc.addSound(SoundRef(durationMS: 3000), name: "music", atMS: 9000)
        doc.materializeTracks()
        let audio = try #require(doc.trackID(ofClip: music))
        doc.updateTrack(audio) { $0.isLocked = true }
        let gap = try #require(doc.gap(onTrack: track, atMS: 5000))
        let closed = doc.closeGap(gap)
        #expect(closed)
        #expect(doc.layer(id: tail)?.time?.inMS == 4000)
        #expect(doc.layer(id: music)?.time?.inMS == 9000)
    }

    @Test("A locked title stays put, and the gap still closes")
    func lockedTitleStays() throws {
        var (doc, _, tail, track, _) = try Self.lifted()
        var title = MarkedStretchTests.title("Pinned", 10_000, 11_000)
        title.isLocked = true
        doc.addLayer(title)
        let gap = try #require(doc.gap(onTrack: track, atMS: 5000))
        let closed = doc.closeGap(gap)
        #expect(closed)
        #expect(doc.layer(id: tail)?.time?.inMS == 4000)
        #expect(doc.layer(id: title.id)?.time?.inMS == 10_000)
    }

    @Test("A gap between two sounds on one audio track closes the same way")
    func closesAGapBetweenSounds() throws {
        var doc = PhotonzDocument.recording(MarkedStretchTests.movie(), name: "Talk")
        let first = doc.addSound(SoundRef(durationMS: 2000), name: "one", atMS: 0)
        let second = doc.addSound(SoundRef(durationMS: 1000), name: "two", atMS: 5000)
        doc.materializeTracks()
        let track = try #require(doc.trackID(ofClip: first))
        _ = doc.moveClip(second, toTrack: track)
        #expect(doc.trackID(ofClip: second) == track)
        let gap = try #require(doc.gap(onTrack: track, atMS: 3000))
        #expect(gap.range == 2000..<5000)
        let closed = doc.closeGap(gap)
        #expect(closed)
        #expect(doc.layer(id: second)?.time?.inMS == 2000)
    }

    // MARK: When it cannot close

    @Test("A gap on a locked track does not close, and nothing changes")
    func lockedTrackRefuses() throws {
        var (doc, _, tail, track, _) = try Self.lifted()
        doc.updateTrack(track) { $0.isLocked = true }
        let gap = try #require(doc.gap(onTrack: track, atMS: 5000))
        #expect(!doc.canCloseGap(gap))
        let before = doc
        let closed = doc.closeGap(gap)
        #expect(!closed)
        #expect(doc == before)
        #expect(doc.layer(id: tail)?.time?.inMS == 8000)
    }

    @Test("Captions that would have to move on a locked Captions track keep the gap open")
    func lockedCaptionsRefuse() throws {
        var (doc, _, _, track, captions) = try Self.lifted()
        let captionsTrack = try #require(doc.trackID(ofClip: captions["after"] ?? UUID()))
        doc.materializeTracks()
        doc.updateTrack(captionsTrack) { $0.isLocked = true }
        let gap = try #require(doc.gap(onTrack: track, atMS: 5000))
        #expect(!doc.canCloseGap(gap))
    }

    @Test("A caption that would land on a caption still in the gap keeps the gap open")
    func captionCollisionRefuses() throws {
        var (doc, head, _) = MarkedStretchTests.talk()
        let track = try #require(doc.trackID(ofClip: head))
        // Lifted off the picture's track alone: the captions over it stay.
        doc.liftStretch(fromMS: 4000, toMS: 8000, onTracks: [track])
        let gap = try #require(doc.gap(onTrack: track, atMS: 5000))
        #expect(!doc.canCloseGap(gap))
        let before = doc
        let closed = doc.closeGap(gap)
        #expect(!closed)
        #expect(doc == before)
    }

    // MARK: Saying why

    /// A talk that speaks, lifted from 4.0s to 8.0s: its own sound is drawn
    /// on an Audio track under it, gap and all.
    static func liftedSpeaking() throws -> (doc: PhotonzDocument, tail: UUID, track: UUID, audio: UUID) {
        var doc = PhotonzDocument.recording(
            MovieRef(pixelSize: CGSize(width: 1920, height: 1080), durationMS: 12_000, hasSound: true),
            name: "Talk")
        doc.liftStretch(fromMS: 4000, toMS: 8000)
        doc.materializeTracks()
        let head = try #require(doc.allLayers.first { $0.isClip })
        let track = try #require(doc.trackID(ofClip: head.id))
        let tail = try #require(doc.allLayers.first { $0.isClip && $0.id != head.id })
        let audio = try #require(doc.tracks.first { $0.kind == .audio })
        #expect(doc.linkedSoundClipIDs(onTrack: audio.id).contains(tail.id))
        return (doc, tail.id, track, audio.id)
    }

    @Test("A gap that closes has nothing to say")
    func noRefusalWhenItCloses() throws {
        let (doc, _, track, _) = try Self.liftedSpeaking()
        let gap = try #require(doc.gap(onTrack: track, atMS: 5000))
        #expect(doc.canCloseGap(gap))
        #expect(doc.gapCloseRefusal(gap) == nil)
    }

    @Test("A locked track the clips have to move on is named")
    func lockedTrackIsNamed() throws {
        var (doc, _, _, track, _) = try Self.lifted()
        doc.materializeTracks()
        doc.updateTrack(track) { $0.isLocked = true }
        let gap = try #require(doc.gap(onTrack: track, atMS: 5000))
        #expect(doc.gapCloseRefusal(gap) == .locked("V1"))
        #expect(doc.gapCloseRefusal(gap)?.reading == "V1 is locked")
    }

    @Test("A clip whose own sound is on a locked track does not move, and the sound's track is named")
    func lockedSoundTrackKeepsTheGapOpen() throws {
        var (doc, tail, track, audio) = try Self.liftedSpeaking()
        doc.updateTrack(audio) { $0.isLocked = true }
        let gap = try #require(doc.gap(onTrack: track, atMS: 5000))
        #expect(!doc.canCloseGap(gap))
        #expect(doc.gapCloseRefusal(gap)?.reading == "Audio is locked")
        let before = doc
        let closed = doc.closeGap(gap)
        #expect(!closed)
        #expect(doc == before)
        #expect(doc.layer(id: tail)?.time?.inMS == 8000)
        // The same gap picked on the sound's own row says the same.
        let soundGap = try #require(doc.gap(onTrack: audio, atMS: 5000))
        #expect(doc.gapCloseRefusal(soundGap)?.reading == "Audio is locked")
    }

    @Test("Captions on a locked Captions track name that track")
    func lockedCaptionsTrackIsNamed() throws {
        var (doc, _, _, track, captions) = try Self.lifted()
        let captionsTrack = try #require(doc.trackID(ofClip: captions["after"] ?? UUID()))
        doc.materializeTracks()
        doc.updateTrack(captionsTrack) { $0.isLocked = true }
        let gap = try #require(doc.gap(onTrack: track, atMS: 5000))
        #expect(doc.gapCloseRefusal(gap)?.reading == "Captions is locked")
    }

    @Test("A locked clip that has to move is named")
    func lockedClipIsNamed() throws {
        var (doc, _, tail, track, _) = try Self.lifted()
        doc.updateLayer(id: tail) { $0.isLocked = true; $0.name = "Demo" }
        let gap = try #require(doc.gap(onTrack: track, atMS: 5000))
        #expect(doc.gapCloseRefusal(gap) == .locked("Demo"))
    }

    @Test("A caption landing on a caption still in the gap is what is in the way")
    func captionInTheWayIsNamed() throws {
        var (doc, head, _) = MarkedStretchTests.talk()
        let track = try #require(doc.trackID(ofClip: head))
        doc.liftStretch(fromMS: 4000, toMS: 8000, onTracks: [track])
        let gap = try #require(doc.gap(onTrack: track, atMS: 5000))
        #expect(doc.gapCloseRefusal(gap)?.reading == "A caption is in the way")
    }

    @Test("A long name is cut short so the line stays a label")
    func longNamesStayInTheBudget() {
        let locked = GapCloseRefusal.locked("A recording with a very long name indeed")
        let inTheWay = GapCloseRefusal.inTheWay("A recording with a very long name indeed")
        for refusal in [locked, inTheWay] {
            #expect(refusal.reading.count <= CopyBudget.chromeLine)
            #expect(CopyBudget.chromeFaults(refusal.reading).isEmpty)
        }
        #expect(locked.reading.hasSuffix("\u{2026} is locked"))
    }

    @Test("The notice says Not closed and what is in the way, inside the chrome budget")
    func theNoticeNamesIt() {
        let notice = CopyConfirmation(subject: .gapNotClosed(.locked("Audio")), shownAt: Date())
        #expect(notice.title == "Not closed")
        #expect(notice.detail == "Audio is locked")
        for line in [notice.title, notice.detail] {
            #expect(CopyBudget.chromeFaults(line).isEmpty)
        }
    }

    @Test("A gap that has since filled up, or moved, does not close")
    func staleGapRefuses() throws {
        var (doc, _, tail, track, _) = try Self.lifted()
        let gap = try #require(doc.gap(onTrack: track, atMS: 5000))
        doc.updateLayer(id: tail) { $0.time = $0.time?.moved(toInMS: 6000) }
        let closed = doc.closeGap(gap)
        #expect(!closed)
        #expect(doc.layer(id: tail)?.time?.inMS == 6000)
    }
}
