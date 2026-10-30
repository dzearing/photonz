import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A transition copies from one cut and pastes onto others**
/// (`TransitionClipboard.swift`).
///
/// Premiere's and Final Cut's way: tune a dissolve at one cut, copy it, pick
/// another cut (or several) and paste. Each gets the same kind, length, curve,
/// direction and blur, fitted to what that cut can pay for, and a cut that
/// cannot pay for the kind at all is left as it was and counted.
///
/// Written before the code, which is the rule for `PhotonzCore`.
@Suite("A transition copies from one cut and pastes onto others")
struct TransitionClipboardTests {

    /// A tuned dissolve: not the usual length, not the usual curve, blurred.
    static let tuned = ClipTransition(kind: .dissolve, lengthMS: 300, alignment: .across,
                                      curve: .easeInOut, direction: .right, motionBlur: true)

    @Test("Copy reads the transition on a cut, and nothing where the cut is hard")
    func copyReadsTheCut() throws {
        var (doc, _, _) = try EveryCutTransitionTests.threeCuts()
        let cuts = doc.transitionCuts().map(\.place)
        #expect(doc.copyTransition(at: cuts[0]) == nil)
        let set = doc.setTransition(Self.tuned, at: cuts[0])
        #expect(set)
        let copied = try #require(doc.copyTransition(at: cuts[0]))
        #expect(copied.transition == Self.tuned)
        #expect(copied.title == "Cross dissolve, 0.3s")
    }

    @Test("Pasted on another cut it is the same kind, length, curve, direction and blur")
    func pastesTheSame() throws {
        var (doc, _, _) = try EveryCutTransitionTests.threeCuts()
        let cuts = doc.transitionCuts().map(\.place)
        let set = doc.setTransition(Self.tuned, at: cuts[0])
        #expect(set)
        let copied = try #require(doc.copyTransition(at: cuts[0]))
        let outcome = doc.pasteTransition(copied, on: [cuts[1]])
        #expect(outcome.put == [cuts[1]])
        #expect(outcome.skipped == 0)
        let pasted = try #require(doc.documentCut(at: cuts[1])?.cut.transition)
        #expect(pasted == Self.tuned)
    }

    @Test("Pasted on several cuts at once, each takes it")
    func pastesOnSeveral() throws {
        var (doc, _, _) = try EveryCutTransitionTests.threeCuts()
        let cuts = doc.transitionCuts().map(\.place)
        let copied = CopiedTransition(Self.tuned)
        let outcome = doc.pasteTransition(copied, on: cuts)
        #expect(outcome.put == cuts)
        for place in cuts {
            #expect(doc.documentCut(at: place)?.cut.transition?.kind == .dissolve)
            #expect(doc.documentCut(at: place)?.cut.transition?.curve == .easeInOut)
            #expect(doc.documentCut(at: place)?.cut.transition?.lengthMS == 300)
        }
    }

    @Test("A cut that cannot pay for the whole length takes the longest it can")
    func shortensToFit() throws {
        var (doc, _, _) = try EveryCutTransitionTests.threeCuts()
        let cut = try #require(doc.transitionCuts().first)
        let long = CopiedTransition(ClipTransition(kind: .dissolve, lengthMS: 9000, curve: .easeIn))
        #expect(cut.cut.longestMS(of: .dissolve) < 9000)
        let outcome = doc.pasteTransition(long, on: [cut.place])
        #expect(outcome.put == [cut.place])
        let pasted = try #require(doc.documentCut(at: cut.place)?.cut.transition)
        #expect(pasted.lengthMS == cut.cut.longestMS(of: .dissolve))
        #expect(pasted.curve == .easeIn)
    }

    @Test("A cut with no spare takes the paste anyway, holding the edge frames")
    func refusesWhatCannotPay() throws {
        var (doc, take, broll) = try EveryCutTransitionTests.threeCuts()
        let did = doc.trimClipEnd(take, ofPiece: 2, byMS: 2000)
        #expect(did)
        doc.updateLayer(id: broll) {
            $0.time = LayerTime(inMS: 9000, outMS: 13_000, sourceInMS: 0, sourceLengthMS: 6000)
        }
        let edit = TimelineCutPlace.edit(outgoing: take, incoming: broll)
        let copied = CopiedTransition(Self.tuned)
        #expect(doc.transitionPastePlan(copied, on: edit).lands)
        let outcome = doc.pasteTransition(copied, on: [edit])
        #expect(outcome.put == [edit])
        #expect(outcome.skipped == 0)
        #expect(doc.documentCut(at: edit)?.cut.transition?.kind == .dissolve)
        #expect(doc.documentCut(at: edit)?.cut.holdsFrames == true)
        // A copied dip goes on the same cut too.
        let dip = CopiedTransition(ClipTransition(kind: .dipToBlack, lengthMS: 600))
        let dipped = doc.pasteTransition(dip, on: [edit])
        #expect(dipped.put == [edit])
    }

    @Test("A dip's hold is not copied: pasting never puts time in")
    func holdStaysBehind() throws {
        var (doc, take, broll) = try EveryCutTransitionTests.threeCuts()
        let edit = TimelineCutPlace.edit(outgoing: take, incoming: broll)
        let held = ClipTransition(kind: .dipToBlack, lengthMS: 600, holdMS: 500)
        let copied = CopiedTransition(held)
        #expect(copied.transition.holdMS == 0)
        let before = doc.timelineLengthMS
        _ = doc.pasteTransition(copied, on: [edit])
        #expect(doc.timelineLengthMS == before)
        #expect(doc.documentCut(at: edit)?.cut.transition?.kind == .dipToBlack)
    }

    @Test("A cut on a locked track is not touched")
    func lockedTrack() throws {
        var (doc, take, _) = try EveryCutTransitionTests.threeCuts()
        let cuts = doc.transitionCuts().map(\.place)
        let track = try #require(doc.trackID(ofClip: take))
        doc.materializeTracks()
        doc.updateTrack(track) { $0.isLocked = true }
        let outcome = doc.pasteTransition(CopiedTransition(Self.tuned), on: [cuts[0]])
        #expect(outcome.put.isEmpty)
        #expect(outcome.skipped == 1)
        #expect(doc.documentCut(at: cuts[0])?.cut.transition == nil)
    }

    @Test("It travels on the clipboard as itself")
    func codable() throws {
        let copied = CopiedTransition(Self.tuned)
        let data = try JSONEncoder().encode(copied)
        #expect(try JSONDecoder().decode(CopiedTransition.self, from: data) == copied)
        #expect(CopiedTransition.pasteboardType == "com.dzearing.photonz.transition")
    }

    @Test("The canvas says what was copied")
    func notice() {
        let note = CopyConfirmation(subject: .transitionCopied(CopiedTransition(Self.tuned)), shownAt: Date())
        #expect(note.title == "Copied")
        #expect(note.detail == "Cross dissolve, 0.3s")
    }
}
