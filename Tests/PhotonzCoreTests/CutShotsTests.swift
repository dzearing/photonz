import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **The transition tiles at a cut play between YOUR two clips**
/// (`CutShots.swift`).
///
/// The user, 2026-10-29: picking how one clip becomes the next should happen
/// at the cut, from tiles that preview with the two real clips, and say what
/// happens between them rather than what one clip does on its own. These pin
/// which frame of which recording each side of a cut shows, and the words
/// that name both sides.
///
/// Written before the code, which is the rule for `PhotonzCore`.
@Suite("The tiles at a cut show the two clips that meet there")
struct CutShotsTests {

    // MARK: - Which frames

    @Test("Between two recordings: the last frame of the one going out, the first of the one coming in")
    func betweenTwoRecordings() throws {
        let (doc, take, broll) = try EditPointTransitionTests.edit()
        let shots = try #require(doc.cutShots(at: .edit(outgoing: take, incoming: broll)))
        // take plays 0 to 8s of its file; b-roll starts 1.5s into its own.
        #expect(shots.outgoing?.movie == EditPointTransitionTests.take)
        #expect(shots.outgoing?.sourceMS == 7999)
        #expect(shots.incoming?.movie == EditPointTransitionTests.broll)
        #expect(shots.incoming?.sourceMS == 1500)
    }

    @Test("At a cut inside one clip: both sides read the same recording, either side of what was cut out")
    func insideOneClip() throws {
        let (doc, clip) = try DefaultTransitionTests.recordingCutAtThree()
        let shots = try #require(doc.cutShots(at: .join(clip: clip, index: 1)))
        // Cut at 3s, and the second piece's first second trimmed away.
        #expect(shots.outgoing?.sourceMS == 2999)
        #expect(shots.incoming?.sourceMS == 4000)
        #expect(shots.outgoing?.movie == shots.incoming?.movie)
    }

    @Test("Where there is no cut there are no shots")
    func noCut() throws {
        let (doc, take, broll) = try EditPointTransitionTests.edit()
        #expect(doc.cutShots(at: .edit(outgoing: broll, incoming: take)) == nil)
        #expect(doc.cutShots(at: .join(clip: take, index: 1)) == nil)
    }

    // MARK: - Naming both sides

    @Test("A tile's words say what happens between the two clips, both of them by name")
    func betweenTheTwo() throws {
        let (doc, take, broll) = try EditPointTransitionTests.edit()
        let cut = try #require(doc.documentCut(at: .edit(outgoing: take, incoming: broll)))
        #expect(ClipTransitionCopy.between(.cube, at: cut) == "Cube: take turns into b-roll")
        #expect(ClipTransitionCopy.between(.dipToBlack, at: cut) == "Dip to black: take turns into b-roll")
    }

    @Test("Inside one clip the two sides are the same clip, so the words say it is the cut inside it")
    func betweenTwoPiecesOfOne() throws {
        let (doc, clip) = try DefaultTransitionTests.recordingCutAtThree()
        let cut = try #require(doc.documentCut(at: .join(clip: clip, index: 1)))
        #expect(ClipTransitionCopy.between(.cube, at: cut) == "Cube at the cut inside take")
    }

    @Test("The picker's top names the two sides, outgoing first")
    func sides() throws {
        let (doc, take, broll) = try EditPointTransitionTests.edit()
        let cut = try #require(doc.documentCut(at: .edit(outgoing: take, incoming: broll)))
        #expect(ClipTransitionCopy.sides(cut) == "take \u{2192} b-roll")
        let (joined, clip) = try DefaultTransitionTests.recordingCutAtThree()
        let join = try #require(joined.documentCut(at: .join(clip: clip, index: 1)))
        #expect(ClipTransitionCopy.sides(join) == "take, at 0:03")
    }
}
