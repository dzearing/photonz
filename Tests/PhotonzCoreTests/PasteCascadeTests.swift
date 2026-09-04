import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Pasting the same copied layer twice used to land both copies in exactly the
/// same spot: the picture looked unchanged and only the layers list showed that
/// anything had happened. Each paste of one clipboard payload now steps further
/// along, so you can see what you just made.
@Suite("Repeated pastes step along")
struct PasteCascadeTests {

    private let canvas = CGSize(width: 800, height: 600)
    private let source = CGRect(x: 100, y: 100, width: 120, height: 60)

    /// Where the first paste of a copied layer belongs: one step off it.
    private var firstRung: CGRect { PasteCascade.stepped(source) }

    private func next(after previous: CGRect?, landingAt first: CGRect? = nil) -> CGRect {
        PasteCascade.frame(landingAt: first ?? firstRung, after: previous, canvas: canvas)
    }

    @Test func theFirstPasteStepsOffTheLayerItCameFrom() {
        #expect(next(after: nil) == CGRect(x: 116, y: 116, width: 120, height: 60))
    }

    @Test func theSecondPasteStepsPastTheFirst() {
        let first = next(after: nil)
        let second = next(after: first)
        #expect(second == CGRect(x: 132, y: 132, width: 120, height: 60))
        #expect(second != first)
    }

    @Test func everyPasteInARunLandsSomewhereNew() {
        var landings: [CGRect] = []
        var previous: CGRect?
        for _ in 0..<6 {
            let landing = next(after: previous)
            landings.append(landing)
            previous = landing
        }
        #expect(Set(landings.map(\.origin.x)).count == landings.count)
    }

    /// The ladder is anchored to the layer the copy came from, so a run of six
    /// pastes stays beside it rather than marching off across the picture.
    @Test func theLadderStaysNearTheLayerItCameFrom() {
        var previous: CGRect?
        for _ in 0..<6 { previous = next(after: previous) }
        let last = previous ?? .zero
        #expect(last.origin.x - source.origin.x <= 96)
        #expect(last.origin.y - source.origin.y <= 96)
    }

    /// Undoing a paste takes that copy away, so the caller stops passing it and
    /// the next paste is free to land where the undone one was, instead of
    /// leaving a hole in the ladder.
    @Test func aPasteAfterAnUndoReusesTheSpotTheUndoneOneHad() {
        let first = next(after: nil)
        let second = next(after: first)
        #expect(next(after: first) == second)
    }

    /// A copy dragged somewhere else does not drag the ladder with it: the next
    /// paste still lands beside the layer everything is being copied from.
    @Test func movingACopyDoesNotMoveWhereTheNextPasteLands() {
        let first = next(after: nil)
        #expect(next(after: first) == CGRect(x: 132, y: 132, width: 120, height: 60))
    }

    // MARK: A picture pasted from outside

    /// Nothing in the document is under it, so the first one lands dead centre
    /// exactly as it always has, and only the next one steps.
    @Test func aPictureFromOutsideKeepsItsCentredFirstLanding() {
        let centred = CGRect(x: 340, y: 270, width: 120, height: 60)
        #expect(next(after: nil, landingAt: centred) == centred)
        #expect(next(after: centred, landingAt: centred)
                == CGRect(x: 356, y: 286, width: 120, height: 60))
    }

    // MARK: Staying on the picture

    @Test func aLadderThatWalksOffTheCanvasStartsOver() {
        let first = CGRect(x: 776, y: 576, width: 120, height: 60)
        let previous = CGRect(x: 800, y: 600, width: 120, height: 60) // just off the edge
        #expect(next(after: previous, landingAt: first) == first)
    }

    /// A layer that was already off the picture has no better spot to offer, so
    /// the ladder keeps stepping rather than snapping back to a place it never
    /// was.
    @Test func aSourceOffTheCanvasStillJustSteps() {
        let first = CGRect(x: 2016, y: 2016, width: 120, height: 60)
        #expect(next(after: nil, landingAt: first) == first)
        #expect(next(after: first, landingAt: first)
                == CGRect(x: 2032, y: 2032, width: 120, height: 60))
    }
}
