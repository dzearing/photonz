import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A dip reads as a fade** (`ClipTransitions.swift`).
///
/// At four tenths of a second a dip spent a fifth of a second going down and a
/// fifth coming up, six frames each way, and the user saw two hard cuts: "it
/// just goes to black and then to the new clip". Premiere and Final Cut both
/// put a second on a new transition, and the transition mock's dip reads
/// 1.0s, half a second out and half a second in. These pin that a NEW dip gets
/// that second, that a dissolve keeps the length it had, and that the Length
/// menu says how a dip's length splits.
///
/// Written before the code, which is the rule for `PhotonzCore`.
@Suite("A dip is long enough to read as a fade")
struct DipLengthTests {

    @Test("A new dip is a second long, half out and half in; the kinds that overlap keep four tenths")
    func defaults() {
        #expect(ClipTransitionKind.dipToBlack.defaultLengthMS == 1000)
        #expect(ClipTransitionKind.dipToWhite.defaultLengthMS == 1000)
        #expect(ClipTransitionKind.dissolve.defaultLengthMS == ClipTransition.defaultLengthMS)
        #expect(ClipTransitionKind.push.defaultLengthMS == ClipTransition.defaultLengthMS)
        let dip = ClipTransition(kind: .dipToBlack)
        #expect(dip.lengthMS == 1000)
        #expect(dip.beforeMS == 500)
        #expect(dip.afterMS == 500)
        #expect(ClipTransition(kind: .dissolve).lengthMS == ClipTransition.defaultLengthMS)
        // A length somebody asked for is the length.
        #expect(ClipTransition(kind: .dipToWhite, lengthMS: 400).lengthMS == 400)
    }

    @Test("Putting a dip on a bare cut fits a second; changing what is there keeps its length")
    func fitted() throws {
        var (doc, take, broll) = try EditPointTransitionTests.edit()
        let place = TimelineCutPlace.edit(outgoing: take, incoming: broll)
        let bare = try #require(doc.documentCut(at: place)).cut
        #expect(bare.fitted(.dipToBlack)?.lengthMS == 1000)
        #expect(bare.fitted(.dipToWhite)?.lengthMS == 1000)
        #expect(bare.fitted(.dissolve)?.lengthMS == ClipTransition.defaultLengthMS)
        let did = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 600), at: place)
        #expect(did)
        let dissolved = try #require(doc.documentCut(at: place)).cut
        #expect(dissolved.fitted(.dipToBlack)?.lengthMS == 600)
    }

    @Test("Halfway down at a quarter of a second before the cut, black on it, halfway up a quarter after")
    func ramp() {
        let dip = ClipTransition(kind: .dipToBlack)
        #expect(ClipTransition.dipAmount(atMS: 4500, cutAtMS: 5000, dip) == 0)
        #expect(abs(ClipTransition.dipAmount(atMS: 4750, cutAtMS: 5000, dip) - 0.5) < 1e-9)
        #expect(ClipTransition.dipAmount(atMS: 5000, cutAtMS: 5000, dip) == 1)
        #expect(abs(ClipTransition.dipAmount(atMS: 5250, cutAtMS: 5000, dip) - 0.5) < 1e-9)
        #expect(ClipTransition.dipAmount(atMS: 5500, cutAtMS: 5000, dip) == 0)
    }

    @Test("The Length menu says how long a dip takes to go out and come back in")
    func lengthChoice() {
        #expect(ClipTransitionCopy.lengthChoice(1000, of: .dipToBlack) == "1.0s, 0.5s out and 0.5s in")
        #expect(ClipTransitionCopy.lengthChoice(2000, of: .dipToWhite) == "2.0s, 1.0s out and 1.0s in")
        #expect(ClipTransitionCopy.lengthChoice(1500, of: .dipToBlack) == "1.5s, 0.75s out and 0.75s in")
        #expect(ClipTransitionCopy.lengthChoice(600, of: .dissolve) == "0.6s")
        for ms in ClipTransition.lengthStopsMS {
            #expect(ClipTransitionCopy.lengthChoice(ms, of: .dipToBlack).count <= 40)
        }
    }
}
