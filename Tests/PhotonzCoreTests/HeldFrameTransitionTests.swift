import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A transition at two clips that touch always goes on** (the user,
/// 2026-10-29: "If I have two clips that are butt up against each other, and I
/// have a cube transition, wouldn't it just pause the frame on one? And then
/// pause the frame on the other and rotate the view, and then play the other
/// one when the transition's done?").
///
/// Spare footage still pays where there is some. Where there is none, the
/// outgoing clip holds its last frame and the incoming one its first, the way
/// Premiere fills a transition with insufficient media with repeated frames.
@Suite("A transition at two clips that touch holds frames rather than refusing")
struct HeldFrameTransitionTests {

    /// Nine seconds recorded and every frame used, then six recorded and read
    /// from their first frame: no spare footage on either side of the cut.
    static let first = MovieRef(pixelSize: CGSize(width: 100, height: 60), durationMS: 9147)
    static let second = MovieRef(pixelSize: CGSize(width: 100, height: 60), durationMS: 6000)

    /// `first` on V1 from 0 to its end, `second` butted onto it: one edit
    /// point at 9.147s with nothing spare either side. `secondSourceIn` reads
    /// the second recording from later, which gives its side some spare.
    static func touching(secondSourceIn: Int = 0, firstOut: Int = 9147) throws
        -> (doc: PhotonzDocument, first: UUID, second: UUID, place: TimelineCutPlace) {
        var doc = PhotonzDocument.recording(Self.first, name: "Recording one")
        let first = doc.layers[0].id
        doc.updateLayer(id: first) {
            $0.time = LayerTime(inMS: 0, outMS: firstOut, sourceInMS: 0, sourceLengthMS: 9147)
        }
        let v1 = try #require(doc.timelineTracks.first { $0.name == "V1" }?.id)
        var clip = Layer(name: "Recording two", content: .image(Self.second.frameRef(atSourceMS: secondSourceIn)),
                         frame: CGRect(origin: .zero, size: Self.second.pixelSize))
        clip.movie = Self.second
        let length = 6000 - secondSourceIn
        clip.time = LayerTime(inMS: 0, outMS: length, sourceInMS: secondSourceIn, sourceLengthMS: 6000)
        let landing = doc.clipLanding(kind: .video, lengthMS: length, atMS: firstOut,
                                      over: .onto(v1), edit: .overwrite)
        let landed = doc.land(clip, at: landing)
        let second = try #require(landed)
        #expect(doc.editPoints(onTrack: v1).map(\.atMS) == [firstOut])
        return (doc, first, second, .edit(outgoing: first, incoming: second))
    }

    static let overlapping: [ClipTransitionKind] = ClipTransitionKind.allCases.filter(\.needsOverlap)

    // MARK: - It goes on

    @Test("Every kind goes on a cut with no spare footage either side, at its usual length, across the cut")
    func everyKindFits() throws {
        let (doc, _, _, place) = try Self.touching()
        let cut = try #require(doc.documentCut(at: place)).cut
        #expect(cut.spareAfterOutMS == 0)
        #expect(cut.spareBeforeInMS == 0)
        for kind in ClipTransitionKind.allCases {
            let fitted = try #require(cut.fitted(kind), "\(kind) was refused")
            #expect(fitted.lengthMS == kind.defaultLengthMS)
            #expect(fitted.alignment == .across)
            #expect(cut.canAfford(kind))
        }
    }

    @Test("Every door puts it on: the menu's targets, the key, a tile let go, a paste")
    func everyDoor() throws {
        for kind in Self.overlapping {
            var (doc, first, second, place) = try Self.touching()
            #expect(doc.transitionPlan(kind, on: .cut(place)).lands)
            #expect(doc.defaultTransitionPlan(kind, picked: place, atMS: 0, reachMS: 0)
                    == .put(ClipTransition(kind: kind, alignment: .across), at: place))
            if case .put = doc.transitionDropPlan(kind, atMS: 9147, onTrack: nil, reachMS: 500) {} else {
                Issue.record("a \(kind) tile let go on the cut was refused")
            }
            let copied = CopiedTransition(ClipTransition(kind: kind, lengthMS: 800))
            #expect(doc.transitionPastePlan(copied, on: place).lands)
            // A right click on either clip aims at the cut, and it lands.
            for clip in [first, second] {
                let targets = doc.transitionTargets(ofClip: clip, piece: 0).map(\.target)
                #expect(targets.contains(.cut(place)))
            }
            let outcome = doc.putTransition(kind, on: [.cut(place)])
            #expect(outcome.put == [.cut(place)])
            #expect(outcome.refused.isEmpty)
            #expect(doc.documentCut(at: place)?.cut.transition?.kind == kind)
        }
    }

    @Test("A clip whose one end meets the next and whose other end meets nothing puts a cube on the cut")
    func clipMenuOnTheFirstClip() throws {
        var (doc, first, _, place) = try Self.touching()
        let targets = doc.transitionTargets(ofClip: first, piece: 0).map(\.target)
        let outcome = doc.putTransition(.cube, on: targets)
        #expect(outcome.put == [.cut(place)])
        // The free start cannot take a cube, and that is the one refusal: it
        // is never the headline once the cut took it.
        #expect(outcome.refused == [.needsTwoClips(.cube)])
        #expect(outcome.headline == nil)
        #expect(TransitionTargetOutcome(put: [], refused: [.needsTwoClips(.cube)]).headline
                == .needsTwoClips(.cube))
    }

    @Test("Putting it on moves nothing on the timeline")
    func nothingMoves() throws {
        var (doc, _, _, place) = try Self.touching()
        let before = doc.layers.map(\.time)
        let did = doc.setTransition(ClipTransition(kind: .cube, lengthMS: 800), at: place)
        #expect(did)
        #expect(doc.layers.map(\.time) == before)
    }

    // MARK: - What it holds

    @Test("With no spare, each side holds its edge frame for its half of the transition")
    func holdsBothEdges() throws {
        var (doc, _, _, place) = try Self.touching()
        let did = doc.setTransition(ClipTransition(kind: .cube, lengthMS: 800), at: place)
        #expect(did)
        let cut = try #require(doc.documentCut(at: place)).cut
        #expect(cut.heldFromOutgoingMS == 400)
        #expect(cut.heldFromIncomingMS == 400)
        #expect(cut.spentFromOutgoingMS == 0)
        #expect(cut.spentFromIncomingMS == 0)
        #expect(cut.holdsFrames)
        // Before the cut the second recording is on its first frame; after
        // it the first recording is on its last.
        let early = doc.movieFrames(atTimeMS: 8947)
        #expect(early.contains { $0.movie == Self.second && $0.sourceMS < 40 })
        let late = doc.movieFrames(atTimeMS: 9347)
        #expect(late.contains { $0.movie == Self.first && $0.sourceMS > 9147 - 80 })
        // And the picture is drawn as two pictures half way through.
        let shown = doc.drawn(atTimeMS: 9147).layers.filter(\.isVisible)
        #expect(shown.count >= 2)
    }

    @Test("Spare footage pays where there is some, and only the rest is held, side by side")
    func spareFirstThenHeld() throws {
        // The second recording read from 0.1s: a tenth of a second spare
        // before it, none after the first.
        var (doc, _, _, place) = try Self.touching(secondSourceIn: 100)
        let did = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 600), at: place)
        #expect(did)
        let cut = try #require(doc.documentCut(at: place)).cut
        #expect(cut.spentFromIncomingMS == 100)
        #expect(cut.heldFromIncomingMS == 200)
        #expect(cut.spentFromOutgoingMS == 0)
        #expect(cut.heldFromOutgoingMS == 300)
        #expect(ClipTransitionCopy.paidWith(cut) == "0.0s + 0.1s of spare, 0.5s held")
    }

    @Test("Where footage can pay for all of it, it does and nothing is held")
    func footageFirst() throws {
        // Two seconds spare after the first, none before the second: it sits
        // after the cut, the way it always did, and holds nothing.
        let (doc, _, _, place) = try Self.touching(firstOut: 7147)
        let cut = try #require(doc.documentCut(at: place)).cut
        let fitted = try #require(cut.fitted(.cube))
        #expect(fitted.alignment == .after)
        #expect(fitted.lengthMS == 800)
        var placed = doc
        let did = placed.setTransition(fitted, at: place)
        #expect(did)
        let now = try #require(placed.documentCut(at: place)).cut
        #expect(now.holdsFrames == false)
        #expect(ClipTransitionCopy.paidWith(now) == "0.8s of spare after")
    }

    @Test("Only clips too short to hold it are refused, and the line says that, not spare frames")
    func onlyTooShortRefuses() throws {
        // A first clip of 0.15s and a second of 0.05s: no placement leaves
        // a tenth of a second on either side.
        var (doc, _, second, place) = try Self.touching(firstOut: 150)
        doc.updateLayer(id: second) { $0.time = LayerTime(inMS: 150, outMS: 200, sourceInMS: 0, sourceLengthMS: 6000) }
        let cut = try #require(doc.documentCut(at: place)).cut
        #expect(cut.fitted(.cube) == nil)
        #expect(doc.transitionPlan(.cube, on: .cut(place)) == .refused(.tooShort(.cube)))
        #expect(DefaultTransitionRefusal.tooShort(.cube).detail == "The clips here are too short for Cube")
    }

    // MARK: - Shortening the cut instead

    @Test("Shortening the cut is still offered where the transition holds frames, to play real footage instead")
    func shorteningStillOffered() throws {
        var (doc, _, _, place) = try Self.touching()
        let did = doc.setTransition(ClipTransition(kind: .cube, lengthMS: 800), at: place)
        #expect(did)
        let cut = try #require(doc.documentCut(at: place)).cut
        let offer = try #require(cut.shorteningOffer(defaultKind: .dissolve))
        #expect(offer.transition.kind == .cube)
        #expect(offer.totalMS == 800)
        // And taking it trims 0.4s off each side and plays the cube on real
        // footage, nothing held.
        var trial = doc
        #expect(trial.shortenCut(offer, at: place) == place)
        let after = try #require(trial.documentCut(at: place)).cut
        #expect(after.atMS == 8747)
        #expect(after.transition?.kind == .cube)
        #expect(after.holdsFrames == false)
        #expect(ClipTransitionCopy.paidWith(cut) == "0.8s of held frames")
    }

    // MARK: - Two clips on one track never sit on top of each other

    @Test("A clip slid over the next on its own track covers it, the way Premiere's drag overwrites")
    func slideOverwrites() throws {
        var (doc, first, second, _) = try Self.touching()
        let v1 = try #require(doc.trackID(ofClip: first))
        // The user's own move: the second slid back to 8.176s, over the
        // first's last second.
        let did = doc.moveClip(second, toInMS: 8176)
        #expect(did)
        doc.overwriteUnder(second)
        #expect(doc.layer(id: first)?.time?.outMS == 8176)
        #expect(doc.layer(id: second)?.time?.inMS == 8176)
        #expect(doc.editPoints(onTrack: v1).map(\.atMS) == [8176])
        // Now there is spare after the first's new end, and a cut to put a
        // cube on.
        let cut = try #require(doc.documentCut(at: .edit(outgoing: first, incoming: second))).cut
        #expect(cut.spareAfterOutMS == 971)
    }

    @Test("A clip slid onto the middle of a longer one splits it round itself, and one wholly covered goes")
    func slideSplitsAndCovers() throws {
        var (doc, first, second, _) = try Self.touching()
        let v1 = try #require(doc.trackID(ofClip: first))
        let did = doc.moveClip(second, toInMS: 1000)
        #expect(did)
        doc.overwriteUnder(second)
        let spans = doc.clipIDs(onTrack: v1).compactMap { doc.layer(id: $0)?.time }
            .map { [$0.inMS, $0.outMS] }.sorted { $0[0] < $1[0] }
        #expect(spans == [[0, 1000], [1000, 7000], [7000, 9147]])
        // Nothing on that track overlaps anything else.
        #expect(doc.clipsOverlapOnATrack == false)
    }

    @Test("A clip on another track is never touched by an overwrite")
    func otherTracksUntouched() throws {
        var (doc, first, second, _) = try Self.touching()
        let before = doc.layer(id: first)?.time
        let did = doc.moveClipToNewTrack(second, at: 0) != nil
        #expect(did)
        let slid = doc.moveClip(second, toInMS: 1000)
        #expect(slid)
        doc.overwriteUnder(second)
        #expect(doc.layer(id: first)?.time == before)
    }
}
