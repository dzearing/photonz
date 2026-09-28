import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A transition tile let go over the timeline lands on the cut under it**
/// (`DefaultTransition.swift`).
///
/// Premiere's Effects panel: drag Cross Dissolve out of Video Transitions and
/// let go on an edit point. Here the tile comes out of the panel's Transitions
/// group, and these pin which cut it lands on: the nearest one on the track
/// under the pointer, within a short reach, never one on a locked track.
///
/// Written before the code, which is the rule for `PhotonzCore`.
@Suite("A transition tile dropped on the timeline lands on the cut under it")
struct TransitionDropTests {

    @Test("Let go near a cut on its own track, the transition goes on that cut")
    func onTheCut() throws {
        let (doc, take, broll) = try EditPointTransitionTests.edit()
        let track = try #require(doc.trackID(ofClip: broll))
        // The edit point is at 8s.
        let plan = doc.transitionDropPlan(.push, atMS: 7900, onTrack: track, reachMS: 300)
        #expect(plan == .put(ClipTransition(kind: .push), at: .edit(outgoing: take, incoming: broll)))
    }

    @Test("Let go too far from any cut, nothing goes on")
    func tooFar() throws {
        let (doc, _, broll) = try EditPointTransitionTests.edit()
        let track = try #require(doc.trackID(ofClip: broll))
        #expect(doc.transitionDropPlan(.dissolve, atMS: 6000, onTrack: track, reachMS: 300)
                == .refused(.noCutNearby))
    }

    @Test("A cut on another track is not the one under the pointer")
    func otherTrack() throws {
        let (doc, take, broll) = try EditPointTransitionTests.edit()
        #expect(doc.transitionDropPlan(.dissolve, atMS: 8000, onTrack: UUID(), reachMS: 300)
                == .refused(.noCutNearby))
        // Between two tracks, where no one track is under the pointer, any
        // picture track's cut in reach will do.
        #expect(doc.transitionDropPlan(.dissolve, atMS: 8000, onTrack: nil, reachMS: 300)
                == .put(ClipTransition(kind: .dissolve), at: .edit(outgoing: take, incoming: broll)))
    }

    @Test("A join inside a recording counts as a cut on the recording's track")
    func joinInsideAClip() throws {
        let (doc, clip) = try DefaultTransitionTests.recordingCutAtThree()
        let track = try #require(doc.trackID(ofClip: clip))
        #expect(doc.transitionDropPlan(.dipToBlack, atMS: 3100, onTrack: track, reachMS: 300)
                == .put(ClipTransition(kind: .dipToBlack), at: .join(clip: clip, index: 1)))
    }

    @Test("Of two cuts in reach, the nearer one")
    func nearer() throws {
        var (doc, clip) = try DefaultTransitionTests.recordingCutAtThree()
        let did1 = doc.splitClip(clip, atMS: 4000)
        let did2 = doc.trimClipStart(clip, ofPiece: 2, byMS: 500)
        #expect(did1 && did2)
        let track = try #require(doc.trackID(ofClip: clip))
        let plan = doc.transitionDropPlan(.dissolve, atMS: 3600, onTrack: track, reachMS: 1000)
        guard case .put(_, let place) = plan else {
            Issue.record("expected a cut, got \(plan)")
            return
        }
        #expect(place == .join(clip: clip, index: 2))
    }

    @Test("A cut on a locked track takes nothing")
    func locked() throws {
        var (doc, clip) = try DefaultTransitionTests.recordingCutAtThree()
        let track = try #require(doc.trackID(ofClip: clip))
        doc.materializeTracks()
        doc.updateTrack(track) { $0.isLocked = true }
        #expect(doc.transitionDropPlan(.dissolve, atMS: 3000, onTrack: track, reachMS: 300)
                == .refused(.noCutNearby))
    }

    @Test("A cut that cannot pay for the tile says so rather than taking it")
    func noSpare() throws {
        var (doc, take, broll) = try EditPointTransitionTests.edit()
        // Both sides used right up to the ends of their recordings.
        doc.updateLayer(id: take) {
            $0.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 2000, sourceLengthMS: 10_000)
        }
        doc.updateLayer(id: broll) {
            $0.time = LayerTime(inMS: 8000, outMS: 12_000, sourceInMS: 0, sourceLengthMS: 6000)
        }
        let track = try #require(doc.trackID(ofClip: broll))
        #expect(doc.transitionDropPlan(.dissolve, atMS: 8000, onTrack: track, reachMS: 300)
                == .refused(.noSpare(.dissolve)))
        // A dip needs none.
        #expect(doc.transitionDropPlan(.dipToBlack, atMS: 8000, onTrack: track, reachMS: 300)
                == .put(ClipTransition(kind: .dipToBlack), at: .edit(outgoing: take, incoming: broll)))
    }
}
