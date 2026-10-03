import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A transition is put where the clips meet** (`TransitionTargets.swift`).
///
/// The user, 2026-10-03: "I expect to right click on a video clip, or on the
/// timeline itself, and insert some transition." Premiere answers both: a
/// transition asked of a clip goes at its ends, at the edit with the clip that
/// meets it, and a Cross Dissolve at an end that meets nothing fades from or
/// to black. These pin where each end of a clip sends a transition, which
/// kinds mean something at an end with nothing next to it, every place a tile
/// in the air can land, and the one-step answer when a cut cannot pay.
///
/// Written before the code, which is the rule for `PhotonzCore`.
@Suite("A transition goes where the clips meet")
struct TransitionTargetTests {

    // MARK: - A clip's two ends

    @Test("A clip butted onto another: its start is the edit with the clip before, its end fades to black")
    func endsOfTheSecondClip() throws {
        let (doc, take, broll) = try EditPointTransitionTests.edit()
        let ends = doc.transitionTargets(ofClip: broll, piece: 0)
        #expect(ends.map(\.target) == [.cut(.edit(outgoing: take, incoming: broll)), .fade(clip: broll, .out)])
        #expect(ends.map(\.atMS) == [8000, 12_000])
    }

    @Test("The first clip: its start fades from black, its end is the edit with the next clip")
    func endsOfTheFirstClip() throws {
        let (doc, take, broll) = try EditPointTransitionTests.edit()
        let ends = doc.transitionTargets(ofClip: take, piece: 0)
        #expect(ends.map(\.target) == [.fade(clip: take, .in), .cut(.edit(outgoing: take, incoming: broll))])
        #expect(ends.map(\.atMS) == [0, 8000])
    }

    @Test("A piece of a cut clip: the joins either side of it, and the clip's own ends past them")
    func endsOfAPiece() throws {
        let (doc, clip) = try DefaultTransitionTests.recordingCutAtThree()
        #expect(doc.transitionTargets(ofClip: clip, piece: 0).map(\.target)
                == [.fade(clip: clip, .in), .cut(.join(clip: clip, index: 1))])
        #expect(doc.transitionTargets(ofClip: clip, piece: 1).map(\.target)
                == [.cut(.join(clip: clip, index: 1)), .fade(clip: clip, .out)])
    }

    // MARK: - What each kind does at an end that meets nothing

    @Test("Cross dissolve and Dip to black at a free end fade the picture; the rest need a clip on both sides")
    func freeEnds() throws {
        let (doc, take, _) = try EditPointTransitionTests.edit()
        #expect(ClipTransitionKind.dissolve.fadesAtAFreeEnd)
        #expect(ClipTransitionKind.dipToBlack.fadesAtAFreeEnd)
        for kind in [ClipTransitionKind.dipToWhite, .push, .wipe, .blurThrough] {
            #expect(!kind.fadesAtAFreeEnd)
            #expect(doc.transitionPlan(kind, on: .fade(clip: take, .in)) == .refused(.needsTwoClips(kind)))
        }
        #expect(doc.transitionPlan(.dissolve, on: .fade(clip: take, .in))
                == .fade(clip: take, .in, lengthMS: TransitionTargetPlan.fadeLengthMS))
    }

    @Test("A free end already fading keeps the length it has")
    func keepsAFade() throws {
        var (doc, take, _) = try EditPointTransitionTests.edit()
        let faded = doc.setPictureFade(take, .in, toMS: 250)
        #expect(faded)
        #expect(doc.transitionPlan(.dipToBlack, on: .fade(clip: take, .in)) == .fade(clip: take, .in, lengthMS: 250))
    }

    @Test("A clip too short for the usual fade gets the longest that fits")
    func shortClip() throws {
        var (doc, take, _) = try EditPointTransitionTests.edit()
        doc.updateLayer(id: take) {
            $0.time = LayerTime(inMS: 0, outMS: 600, sourceInMS: 0, sourceLengthMS: 10_000)
        }
        #expect(doc.transitionPlan(.dissolve, on: .fade(clip: take, .in)) == .fade(clip: take, .in, lengthMS: 500))
    }

    @Test("At a cut the plan is the cut's own: fitted, or refused for want of spare frames")
    func atACut() throws {
        let (doc, take, broll) = try EditPointTransitionTests.edit()
        let place = TimelineCutPlace.edit(outgoing: take, incoming: broll)
        #expect(doc.transitionPlan(.dissolve, on: .cut(place)) == .put(ClipTransition(kind: .dissolve), at: place))

        let (bare, a, b) = try Self.untrimmed()
        let edit = TimelineCutPlace.edit(outgoing: a, incoming: b)
        #expect(bare.transitionPlan(.dissolve, on: .cut(edit)) == .refused(.noSpare(.dissolve)))
        // A dip spends nothing, so it is always the way through.
        #expect(bare.transitionPlan(.dipToBlack, on: .cut(edit)) == .put(ClipTransition(kind: .dipToBlack), at: edit))
    }

    // MARK: - Putting it on

    @Test("Add Transition on a clip puts it at both ends as one edit: the edit, and a fade where it meets nothing")
    func putAtBothEnds() throws {
        var (doc, take, broll) = try EditPointTransitionTests.edit()
        let outcome = doc.putTransition(.dissolve, on: doc.transitionTargets(ofClip: broll, piece: 0).map(\.target))
        #expect(outcome.put.count == 2)
        #expect(outcome.refused.isEmpty)
        #expect(doc.documentCut(at: .edit(outgoing: take, incoming: broll))?.cut.transition?.kind == .dissolve)
        #expect(doc.layer(id: broll)?.pictureFadeMS(.out) == TransitionTargetPlan.fadeLengthMS)
        #expect(doc.layer(id: broll)?.pictureFadeMS(.in) == 0)
    }

    @Test("An end that cannot take it is left as it was, and counted as refused with its reason")
    func refusedEnd() throws {
        var (doc, take, broll) = try EditPointTransitionTests.edit()
        let outcome = doc.putTransition(.push, on: doc.transitionTargets(ofClip: broll, piece: 0).map(\.target))
        #expect(outcome.put == [.cut(.edit(outgoing: take, incoming: broll))])
        #expect(outcome.refused == [.needsTwoClips(.push)])
        #expect(doc.layer(id: broll)?.pictureFade == nil)
    }

    // MARK: - A tile in the air

    @Test("Every place a tile can land: each cut, and each end of a recording that meets nothing")
    func spots() throws {
        let (doc, take, broll) = try EditPointTransitionTests.edit()
        #expect(doc.transitionSpots().map(\.target) == [
            .fade(clip: take, .in), .cut(.edit(outgoing: take, incoming: broll)), .fade(clip: broll, .out),
        ])
        #expect(doc.transitionSpots().map(\.atMS) == [0, 8000, 12_000])
        #expect(Set(doc.transitionSpots().compactMap(\.trackID)) == [try #require(doc.trackID(ofClip: take))])
    }

    @Test("Let go near a clip's free end, a dissolve fades it; near the edit, it goes on the edit; mid clip, nothing")
    func dropTargets() throws {
        let (doc, take, broll) = try EditPointTransitionTests.edit()
        let track = try #require(doc.trackID(ofClip: take))
        #expect(doc.transitionDropSpot(atMS: 11_900, onTrack: track, reachMS: 300)?.target == .fade(clip: broll, .out))
        #expect(doc.transitionDropSpot(atMS: 8100, onTrack: track, reachMS: 300)?.target
                == .cut(.edit(outgoing: take, incoming: broll)))
        #expect(doc.transitionDropSpot(atMS: 4000, onTrack: track, reachMS: 300) == nil)
        #expect(doc.transitionDropSpot(atMS: 8000, onTrack: UUID(), reachMS: 300) == nil)
    }

    @Test("Nothing on a locked track is a place to land")
    func locked() throws {
        var (doc, take, _) = try EditPointTransitionTests.edit()
        let track = try #require(doc.trackID(ofClip: take))
        doc.updateTrack(track) { $0.isLocked = true }
        #expect(doc.transitionSpots().isEmpty)
        #expect(doc.transitionTargets(ofClip: take, piece: 0).isEmpty)
    }

    // MARK: - The way through a refusal

    @Test("A cut with no spare frames is offered the nearest kind it can take: a dip, which spends none")
    func nearestThatWorks() throws {
        let (bare, a, b) = try Self.untrimmed()
        let edit = TimelineCutPlace.edit(outgoing: a, incoming: b)
        #expect(bare.nearestTransition(to: .dissolve, at: edit) == .dipToBlack)
        #expect(bare.nearestTransition(to: .push, at: edit) == .dipToBlack)
        // White asked for and refused only when white itself cannot go on,
        // which never happens: a dip always fits.
        let (doc, take, broll) = try EditPointTransitionTests.edit()
        #expect(doc.nearestTransition(to: .dissolve, at: .edit(outgoing: take, incoming: broll)) == .dissolve)
    }

    /// Two recordings butted together, both played from their first frame to
    /// their last: no spare either side of the edit at 4s.
    static func untrimmed() throws -> (doc: PhotonzDocument, a: UUID, b: UUID) {
        let movie = MovieRef(pixelSize: CGSize(width: 100, height: 60), durationMS: 4000)
        var doc = PhotonzDocument.recording(movie, name: "a")
        let a = doc.layers[0].id
        let v1 = try #require(doc.timelineTracks.first { $0.name == "V1" }?.id)
        var clip = Layer(name: "b", content: .image(movie.frameRef(atSourceMS: 0)),
                         frame: CGRect(origin: .zero, size: movie.pixelSize))
        clip.movie = movie
        clip.time = LayerTime(inMS: 0, outMS: 4000, sourceInMS: 0, sourceLengthMS: 4000)
        let landing = doc.clipLanding(kind: .video, lengthMS: 4000, atMS: 4000, over: .onto(v1), edit: .overwrite)
        let landed = doc.land(clip, at: landing)
        let b = try #require(landed)
        #expect(doc.editPoints(onTrack: v1).map(\.atMS) == [4000])
        return (doc, a, b)
    }
}

/// **A refused transition offers the one that fits** (`CanvasNoticeAction`).
@Suite("A transition a cut cannot pay for offers the one it can")
struct TransitionWayThroughTests {

    @Test func theButtonNamesTheKindItPutsOn() throws {
        let place = TimelineCutPlace.edit(outgoing: UUID(), incoming: UUID())
        let action = CanvasNoticeAction.putTransition(.dipToBlack, at: place)
        #expect(action.label == "Use Dip to black")
        #expect(action.presentation == .button)
        #expect(action.shortcutHint == nil)
        #expect(action.layerIDs == [place.arrivingClip])
    }

    @Test func theNoticeSaysWhyAndStaysUpLongEnoughToPress() {
        let place = TimelineCutPlace.edit(outgoing: UUID(), incoming: UUID())
        let notice = CopyConfirmation(subject: .defaultTransitionRefused(.noSpare(.dissolve)), shownAt: Date(),
                                      action: .putTransition(.dipToBlack, at: place))
        #expect(notice.detail.contains("needs spare frames"))
        #expect(notice.lifetime == CopyConfirmation.actionLifetime)
    }

    @Test func aCutSkippedWhileTheOtherEndTookItSaysWhichAndWhy() {
        let notice = CopyConfirmation(subject: .transitionCutSkipped(atMS: 15_500), shownAt: Date())
        #expect(notice.title == "1 cut skipped")
        #expect(notice.detail == "No spare frames at 0:15")
        #expect(notice.lifetime == CopyConfirmation.breakLifetime)
    }

    @Test func aFreeEndRefusalSaysItNeedsTwoClips() {
        #expect(DefaultTransitionRefusal.needsTwoClips(.push).detail == "Push needs a clip on both sides")
    }
}
