import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **One key puts the usual transition on the cut at the playhead**
/// (`DefaultTransition.swift`).
///
/// Premiere's ⌘D and Final Cut's ⌘T: stand on a cut, press the key, and the
/// default transition is on it. ⌘D is Photoshop's Deselect here, so the key is
/// Final Cut's. These pin which cut the key finds, what it puts there, and
/// when it says no.
///
/// Written before the code, which is the rule for `PhotonzCore`.
@Suite("One key puts the default transition on the cut at the playhead")
struct DefaultTransitionTests {

    static let take = EditPointTransitionTests.take
    static let broll = EditPointTransitionTests.broll

    // MARK: - The key

    @Test("Command T is Apply Default Transition wherever the keyboard is, and plain T is not")
    func theKey() {
        let press = TimelineKeyPress(key: .letter("t"), modifiers: .command)
        #expect(TimelineKeys.command(for: press, timelineFocused: true) == .applyDefaultTransition)
        #expect(TimelineKeys.command(for: press, timelineFocused: false) == .applyDefaultTransition)
        // T alone is the Text tool, and ⌥⌘T is Show Timing.
        #expect(TimelineKeys.command(for: TimelineKeyPress(key: .letter("t")), timelineFocused: true) == nil)
        #expect(TimelineKeys.command(for: TimelineKeyPress(key: .letter("t"), modifiers: [.command, .option]),
                                     timelineFocused: true) == nil)
        // ⌘D stays Photoshop's Deselect.
        #expect(TimelineKeys.command(for: TimelineKeyPress(key: .letter("d"), modifiers: .command),
                                     timelineFocused: true) == nil)
    }

    @Test("Cross dissolve is the default until somebody picks another")
    func crossDissolveFirst() {
        #expect(ClipTransitionKind.usualDefault == .dissolve)
        #expect(ClipTransitionKind(storedDefault: nil) == .dissolve)
        #expect(ClipTransitionKind(storedDefault: "garbage") == .dissolve)
        #expect(ClipTransitionKind(storedDefault: ClipTransitionKind.push.rawValue) == .push)
    }

    // MARK: - Which cut

    /// A recording cut in two at 3s, with the second piece's first second
    /// trimmed off, so both sides of the join have spare frames.
    static func recordingCutAtThree() throws -> (doc: PhotonzDocument, clip: UUID) {
        var doc = PhotonzDocument.recording(Self.take, name: "take")
        let id = doc.layers[0].id
        let did1 = doc.splitClip(id, atMS: 3000)
        #expect(did1)
        let did2 = doc.trimClipStart(id, ofPiece: 1, byMS: 1000)
        #expect(did2)
        return (doc, id)
    }

    @Test("The cut nearest the playhead, inside a clip or between two, within reach")
    func nearestCut() throws {
        let (doc, take, broll) = try EditPointTransitionTests.edit()
        // The edit point is at 8s.
        #expect(doc.transitionCuts().map(\.place) == [.edit(outgoing: take, incoming: broll)])
        let near = doc.defaultTransitionPlan(.dissolve, picked: nil, atMS: 7700, reachMS: 500)
        #expect(near == .put(ClipTransition(kind: .dissolve), at: .edit(outgoing: take, incoming: broll)))
        let far = doc.defaultTransitionPlan(.dissolve, picked: nil, atMS: 6000, reachMS: 500)
        #expect(far == .refused(.noCutNearby))

        let (joined, clip) = try Self.recordingCutAtThree()
        #expect(joined.transitionCuts().map(\.place) == [.join(clip: clip, index: 1)])
        let onIt = joined.defaultTransitionPlan(.dissolve, picked: nil, atMS: 3000, reachMS: 500)
        #expect(onIt == .put(ClipTransition(kind: .dissolve), at: .join(clip: clip, index: 1)))
    }

    @Test("Of two cuts in reach, the nearer one")
    func nearerOfTwo() throws {
        var (doc, clip) = try Self.recordingCutAtThree()
        let did3 = doc.splitClip(clip, atMS: 4000)
        #expect(did3)
        let did4 = doc.trimClipStart(clip, ofPiece: 2, byMS: 500)
        #expect(did4)
        let cuts = doc.transitionCuts()
        #expect(cuts.map(\.atMS) == [3000, 4000])
        let plan = doc.defaultTransitionPlan(.dipToBlack, picked: nil, atMS: 3700, reachMS: 1000)
        guard case .put(_, let place) = plan else {
            Issue.record("expected a cut, got \(plan)")
            return
        }
        #expect(place == .join(clip: clip, index: 2))
    }

    @Test("A cut that is picked wins over the one nearest the playhead")
    func pickedWins() throws {
        var (doc, clip) = try Self.recordingCutAtThree()
        let did5 = doc.splitClip(clip, atMS: 4000)
        #expect(did5)
        let did6 = doc.trimClipStart(clip, ofPiece: 2, byMS: 500)
        #expect(did6)
        let plan = doc.defaultTransitionPlan(.dipToBlack, picked: .join(clip: clip, index: 1),
                                             atMS: 6000, reachMS: 200)
        #expect(plan == .put(ClipTransition(kind: .dipToBlack), at: .join(clip: clip, index: 1)))
    }

    @Test("A cut on a locked track is left alone")
    func lockedTrack() throws {
        var (doc, clip) = try Self.recordingCutAtThree()
        let track = try #require(doc.trackID(ofClip: clip))
        doc.materializeTracks()
        doc.updateTrack(track) { $0.isLocked = true }
        #expect(doc.isClipOnLockedTrack(clip))
        #expect(doc.defaultTransitionPlan(.dissolve, picked: nil, atMS: 3000, reachMS: 500)
                == .refused(.noCutNearby))
        #expect(doc.defaultTransitionPlan(.dissolve, picked: .join(clip: clip, index: 1),
                                          atMS: 3000, reachMS: 500) == .refused(.noCutNearby))
    }

    @Test("A sound clip's cuts take no transition, so the key does not find them")
    func notOnSound() throws {
        var (doc, clip) = try Self.recordingCutAtThree()
        doc.updateLayer(id: clip) { $0.movie = nil }
        #expect(doc.transitionCuts().isEmpty)
    }

    // MARK: - What goes on

    @Test("The length already on the cut is kept, the usual length otherwise, never past what it can pay for")
    func lengths() throws {
        var (doc, take, broll) = try EditPointTransitionTests.edit()
        let place = TimelineCutPlace.edit(outgoing: take, incoming: broll)
        let cut = try #require(doc.documentCut(at: place)).cut
        #expect(cut.fitted(.dissolve) == ClipTransition(kind: .dissolve, lengthMS: ClipTransition.defaultLengthMS))
        let did7 = doc.setTransition(ClipTransition(kind: .dipToBlack, lengthMS: 3500), at: place)
        #expect(did7)
        let dipped = try #require(doc.documentCut(at: place)).cut
        // 3.5s of dip, but a dissolve here can spend no more than 3s.
        #expect(dipped.fitted(.dissolve) == ClipTransition(kind: .dissolve, lengthMS: 3000))
        #expect(dipped.fitted(.dipToWhite) == ClipTransition(kind: .dipToWhite, lengthMS: 3500))
    }

    @Test("With no spare frames a cross dissolve is refused, and says which one")
    func noSpare() throws {
        var (doc, take, broll) = try EditPointTransitionTests.edit()
        // Both sides used right up to the ends of their recordings.
        doc.updateLayer(id: take) {
            $0.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 2000, sourceLengthMS: 10_000)
        }
        let place = TimelineCutPlace.edit(outgoing: take, incoming: broll)
        let cut = try #require(doc.documentCut(at: place)).cut
        #expect(cut.spareAfterOutMS == 0)
        #expect(cut.fitted(.dissolve) == nil)
        #expect(doc.defaultTransitionPlan(.dissolve, picked: nil, atMS: 8000, reachMS: 500)
                == .refused(.noSpare(.dissolve)))
        // A dip needs none.
        #expect(doc.defaultTransitionPlan(.dipToBlack, picked: nil, atMS: 8000, reachMS: 500)
                == .put(ClipTransition(kind: .dipToBlack), at: place))
    }

    @Test("What the refusals say, in plain words")
    func refusalWords() {
        #expect(DefaultTransitionRefusal.noCutNearby.detail == "There is no cut at the playhead")
        #expect(DefaultTransitionRefusal.noSpare(.dissolve).detail
                == "Cross dissolve needs spare frames either side of this cut")
    }
}
