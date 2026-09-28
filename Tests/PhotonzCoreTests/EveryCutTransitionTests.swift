import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **One step puts a transition on every cut** (`DefaultTransition.swift`).
///
/// The transitions mock's Apply to every cut, and Premiere's Apply Default
/// Transitions to Selection: a screen recording with twenty cuts takes a
/// dissolve on each of them in one go rather than twenty. These pin which cuts
/// it reaches, what it leaves alone, and what it counts as skipped.
///
/// Written before the code, which is the rule for `PhotonzCore`.
@Suite("One step puts a transition on every cut")
struct EveryCutTransitionTests {

    /// The recording cut at 3s and at 4s, each later piece trimmed a little so
    /// both joins have spare either side, then the b-roll edit from
    /// `EditPointTransitionTests`: three cuts on the timeline.
    static func threeCuts() throws -> (doc: PhotonzDocument, take: UUID, broll: UUID) {
        var (doc, take, broll) = try EditPointTransitionTests.edit()
        let did1 = doc.splitClip(take, atMS: 3000)
        let did2 = doc.trimClipStart(take, ofPiece: 1, byMS: 500)
        let did3 = doc.splitClip(take, atMS: 5000)
        let did4 = doc.trimClipStart(take, ofPiece: 2, byMS: 500)
        #expect(did1 && did2 && did3 && did4)
        // Each trim took half a second out of the recording, which now ends
        // at 7s: the b-roll moves up to butt onto it again.
        doc.updateLayer(id: broll) {
            $0.time = LayerTime(inMS: 7000, outMS: 11_000, sourceInMS: 1500, sourceLengthMS: 6000)
        }
        #expect(doc.transitionCuts().count == 3)
        return (doc, take, broll)
    }

    @Test("Every cut on the timeline takes the transition, each one fitted to what it can pay for")
    func everyCut() throws {
        var (doc, _, _) = try Self.threeCuts()
        let places = doc.transitionCuts().map(\.place)
        let outcome = doc.putTransitionOnEveryCut(.dissolve)
        #expect(outcome.put == places)
        #expect(outcome.skipped == 0)
        for place in places {
            #expect(doc.documentCut(at: place)?.cut.transition?.kind == .dissolve)
        }
    }

    @Test("A cut with a transition already on it takes the new kind and keeps its length")
    func replacesAndKeepsLength() throws {
        var (doc, _, _) = try Self.threeCuts()
        let first = try #require(doc.transitionCuts().first).place
        let did = doc.setTransition(ClipTransition(kind: .dipToBlack, lengthMS: 300), at: first)
        #expect(did)
        _ = doc.putTransitionOnEveryCut(.dissolve)
        let now = try #require(doc.documentCut(at: first)?.cut.transition)
        #expect(now.kind == .dissolve)
        #expect(now.lengthMS == 300)
    }

    @Test("A cut already wearing exactly that transition counts as on, never as skipped")
    func alreadyOnIsNotSkipped() throws {
        var (doc, _, _) = try Self.threeCuts()
        let first = try #require(doc.transitionCuts().first)
        let fitted = try #require(first.cut.fitted(.dipToBlack))
        let did = doc.setTransition(fitted, at: first.place)
        #expect(did)
        let outcome = doc.putTransitionOnEveryCut(.dipToBlack)
        #expect(outcome.skipped == 0)
        #expect(outcome.put.count == 3)
        #expect(outcome.countLine == "On 3 cuts")
    }

    @Test("A cut that cannot pay for it is left as it was and counted as skipped")
    func skipsWhatCannotPay() throws {
        var (doc, take, broll) = try Self.threeCuts()
        // The edit point used right up to both ends of its recordings: no
        // spare either side of it.
        let did = doc.trimClipEnd(take, ofPiece: 2, byMS: 2000)
        #expect(did)
        doc.updateLayer(id: broll) {
            $0.time = LayerTime(inMS: 9000, outMS: 13_000, sourceInMS: 0, sourceLengthMS: 6000)
        }
        let edit = TimelineCutPlace.edit(outgoing: take, incoming: broll)
        let tight = try #require(doc.documentCut(at: edit)).cut
        guard tight.fitted(.dissolve) == nil else {
            Issue.record("the edit point still has spare: \(tight)")
            return
        }
        let outcome = doc.putTransitionOnEveryCut(.dissolve)
        #expect(outcome.skipped == 1)
        #expect(outcome.put.count == 2)
        #expect(!outcome.put.contains(edit))
        #expect(doc.documentCut(at: edit)?.cut.transition == nil)
    }

    @Test("Nothing to put on anywhere changes nothing")
    func nothingToDo() throws {
        var doc = PhotonzDocument.recording(EditPointTransitionTests.take, name: "take")
        let before = doc
        let outcome = doc.putTransitionOnEveryCut(.dissolve)
        #expect(outcome.put.isEmpty)
        #expect(outcome.skipped == 0)
        #expect(doc == before)
    }

    @Test("A cut on a locked track is not touched and not counted")
    func lockedTrack() throws {
        var (doc, take, _) = try Self.threeCuts()
        let track = try #require(doc.trackID(ofClip: take))
        doc.materializeTracks()
        doc.updateTrack(track) { $0.isLocked = true }
        let outcome = doc.putTransitionOnEveryCut(.dissolve)
        #expect(outcome.put.isEmpty)
        #expect(outcome.skipped == 0)
    }

    // MARK: - Among the clips picked

    @Test("Among picked clips: the joins inside them and the edits between two of them")
    func amongPicked() throws {
        let (doc, take, broll) = try Self.threeCuts()
        let both = doc.transitionCuts(among: [take, broll]).map(\.place)
        #expect(both.count == 3)
        #expect(both.contains(.edit(outgoing: take, incoming: broll)))
        // One clip alone: its own joins, never the edit to a clip not picked.
        let one = doc.transitionCuts(among: [take]).map(\.place)
        #expect(one == [.join(clip: take, index: 1), .join(clip: take, index: 2)])
        #expect(doc.transitionCuts(among: [broll]).isEmpty)
    }

    @Test("Putting it on the picked clips leaves every other cut alone")
    func onlyPicked() throws {
        var (doc, take, broll) = try Self.threeCuts()
        let outcome = doc.putTransitionOnEveryCut(.push, among: [take])
        #expect(outcome.put == [.join(clip: take, index: 1), .join(clip: take, index: 2)])
        #expect(doc.documentCut(at: .edit(outgoing: take, incoming: broll))?.cut.transition == nil)
    }

    // MARK: - What the canvas says

    @Test("What the canvas says after, in plain words")
    func words() {
        #expect(EveryCutOutcome(put: [.join(clip: UUID(), index: 1)], skipped: 0).countLine == "On 1 cut")
        let places = (1...12).map { TimelineCutPlace.join(clip: UUID(), index: $0) }
        #expect(EveryCutOutcome(put: places, skipped: 0).countLine == "On 12 cuts")
        #expect(EveryCutOutcome(put: places, skipped: 3).countLine == "On 12 cuts, 3 skipped")
        #expect(EveryCutOutcome(put: [], skipped: 2).countLine == "2 cuts have no spare frames")
        #expect(EveryCutOutcome(put: [], skipped: 1).countLine == "1 cut has no spare frames")
        #expect(EveryCutOutcome(put: [], skipped: 0).countLine == "There are no cuts")
    }

    @Test("The canvas names the transition and the count, and stays up longer when cuts were skipped")
    func notice() {
        let places = (1...4).map { TimelineCutPlace.join(clip: UUID(), index: $0) }
        let clean = CopyConfirmation(subject: .transitionOnEveryCut(.dissolve, EveryCutOutcome(put: places, skipped: 0)),
                                     shownAt: Date())
        #expect(clean.title == "Cross dissolve")
        #expect(clean.detail == "On 4 cuts")
        let skipped = CopyConfirmation(subject: .transitionOnEveryCut(.dissolve, EveryCutOutcome(put: places, skipped: 2)),
                                       shownAt: Date())
        #expect(skipped.detail == "On 4 cuts, 2 skipped")
        #expect(skipped.lifetime > clean.lifetime)
        let none = CopyConfirmation(subject: .transitionOnEveryCut(.push, EveryCutOutcome(put: [], skipped: 3)),
                                    shownAt: Date())
        #expect(none.title == "No transition added")
        #expect(none.detail == "3 cuts have no spare frames")
    }
}
