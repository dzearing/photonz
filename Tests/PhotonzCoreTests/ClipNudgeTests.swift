import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **⌘← and ⌘→ nudge the picked clips a frame in time** (`ClipNudge.swift`),
/// Premiere's Nudge Clip Selection, five frames with ⇧.
///
/// A nudge is a small exact move, so it never runs one clip into another: it
/// stops at the clip next door on the same track, and at the start of the
/// document. A clip on a locked track stays where it is.
@Suite("Clip nudge")
struct ClipNudgeTests {

    static let frame = MovieRef.frameStepMS

    /// The two clips of `ClipsAcrossTracksTests.twoOnV1`, with a gap of
    /// `gapMS` between them: the first 0 to 3000, the second after it.
    static func twoOnV1(gapMS: Int) throws -> (doc: PhotonzDocument, first: UUID, second: UUID, v1: UUID) {
        var (doc, first, second, v1) = try ClipsAcrossTracksTests.twoOnV1()
        if gapMS != 0 {
            let moved = doc.moveClips([second], byMS: gapMS)
            #expect(moved)
        }
        return (doc, first, second, v1)
    }

    static func start(_ doc: PhotonzDocument, _ id: UUID) -> Int? { doc.layer(id: id)?.time?.inMS }

    // MARK: - A frame at a time

    @Test("A clip with room either side goes one frame later, then one earlier, by the frame length")
    func oneFrameEachWay() throws {
        var (doc, _, second, _) = try Self.twoOnV1(gapMS: 1000)
        #expect(Self.start(doc, second) == 4000)
        do { let moved = doc.nudgeClips([second], byFrames: 1); #expect(moved) }
        #expect(Self.start(doc, second) == 4000 + Self.frame)
        do { let moved = doc.nudgeClips([second], byFrames: -1); #expect(moved) }
        #expect(Self.start(doc, second) == 4000)
    }

    @Test("Five frames at once go five frame lengths, and the length of the clip does not change")
    func fiveFrames() throws {
        var (doc, _, second, _) = try Self.twoOnV1(gapMS: 1000)
        let length = try #require(doc.layer(id: second)?.time).lengthMS
        do { let moved = doc.nudgeClips([second], byFrames: 5); #expect(moved) }
        #expect(Self.start(doc, second) == 4000 + 5 * Self.frame)
        #expect(doc.layer(id: second)?.time?.lengthMS == length)
    }

    @Test("Several picked clips go together and keep the gap between them")
    func severalTogether() throws {
        var (doc, first, second, _) = try Self.twoOnV1(gapMS: 1000)
        do { let moved = doc.nudgeClips([first, second], byFrames: 3); #expect(moved) }
        #expect(Self.start(doc, first) == 3 * Self.frame)
        #expect(Self.start(doc, second) == 4000 + 3 * Self.frame)
    }

    @Test("Nothing picked, or ids that are not clips, change nothing")
    func nothingToNudge() throws {
        var (doc, _, _, _) = try Self.twoOnV1(gapMS: 1000)
        let before = doc
        do { let moved = doc.nudgeClips([], byFrames: 1); #expect(!moved) }
        do { let moved = doc.nudgeClips([UUID()], byFrames: 1); #expect(!moved) }
        #expect(doc == before)
    }

    // MARK: - It stops at an edge

    @Test("At the start of the document an earlier nudge does nothing")
    func stopsAtTheStart() throws {
        var (doc, first, _, _) = try Self.twoOnV1(gapMS: 1000)
        let before = doc
        do { let moved = doc.nudgeClips([first], byFrames: -1); #expect(!moved) }
        #expect(doc == before)
    }

    @Test("Two frames from the start, five earlier goes only the two")
    func partWayToTheStart() throws {
        var (doc, first, second, _) = try Self.twoOnV1(gapMS: 1000)
        do { let moved = doc.nudgeClips([first, second], byFrames: 2); #expect(moved) }
        do { let moved = doc.nudgeClips([first, second], byFrames: -5); #expect(moved) }
        #expect(Self.start(doc, first) == 0)
        #expect(Self.start(doc, second) == 4000)
    }

    @Test("Butted up against the clip before it on its track, an earlier nudge does nothing")
    func stopsAtTheClipBefore() throws {
        var (doc, _, second, _) = try Self.twoOnV1(gapMS: 0)
        let before = doc
        do { let moved = doc.nudgeClips([second], byFrames: -1); #expect(!moved) }
        #expect(doc == before)
    }

    @Test("A later nudge of the first clip stops where the second one starts")
    func stopsAtTheClipAfter() throws {
        var (doc, first, _, _) = try Self.twoOnV1(gapMS: 2 * Self.frame)
        do { let moved = doc.nudgeClips([first], byFrames: 5); #expect(moved) }
        #expect(Self.start(doc, first) == 2 * Self.frame)
        // Now butted up: nothing more.
        do { let moved = doc.nudgeClips([first], byFrames: 1); #expect(!moved) }
        #expect(Self.start(doc, first) == 2 * Self.frame)
    }

    @Test("Clips picked together do not stop each other")
    func pickedTogetherDoNotBlock() throws {
        var (doc, first, second, _) = try Self.twoOnV1(gapMS: 0)
        do { let moved = doc.nudgeClips([first, second], byFrames: 1); #expect(moved) }
        #expect(Self.start(doc, first) == Self.frame)
        #expect(Self.start(doc, second) == 3000 + Self.frame)
    }

    @Test("A clip on another track at the same time does not stop it")
    func otherTracksDoNotBlock() throws {
        var (doc, first, second, _) = try Self.twoOnV1(gapMS: 0)
        let v2 = doc.addTrack(.video, at: 0)
        do { let moved = doc.moveClip(second, toTrack: v2); #expect(moved) }
        // The second clip is on V2 now, right after the first in time.
        do { let moved = doc.nudgeClips([first], byFrames: 1); #expect(moved) }
        #expect(Self.start(doc, first) == Self.frame)
    }

    // MARK: - Locked tracks

    @Test("A clip on a locked track does not move")
    func lockedDoesNotMove() throws {
        var (doc, first, _, v1) = try Self.twoOnV1(gapMS: 1000)
        doc.updateTrack(v1) { $0.isLocked = true }
        let before = doc
        #expect(!doc.canNudgeClips([first]))
        do { let moved = doc.nudgeClips([first], byFrames: 1); #expect(!moved) }
        #expect(doc == before)
    }

    @Test("Picked with one on a locked track, the others move and it stays")
    func lockedStaysOthersMove() throws {
        var (doc, first, second, _) = try Self.twoOnV1(gapMS: 0)
        let v2 = doc.addTrack(.video, at: 0)
        do { let moved = doc.moveClip(second, toTrack: v2); #expect(moved) }
        doc.updateTrack(v2) { $0.isLocked = true }
        #expect(doc.canNudgeClips([first, second]))
        do { let moved = doc.nudgeClips([first, second], byFrames: 2); #expect(moved) }
        #expect(Self.start(doc, first) == 2 * Self.frame)
        #expect(Self.start(doc, second) == 3000)
    }

    @Test("Whether there is anything to nudge: a picked clip yes, nothing picked no")
    func canNudge() throws {
        let (doc, first, _, _) = try Self.twoOnV1(gapMS: 0)
        #expect(doc.canNudgeClips([first]))
        #expect(!doc.canNudgeClips([]))
        #expect(!doc.canNudgeClips([UUID()]))
    }
}
