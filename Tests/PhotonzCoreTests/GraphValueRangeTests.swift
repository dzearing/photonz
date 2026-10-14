import Foundation
import PhotonzCore
import Testing

/// An open value graph zooms its value range (task
/// `the-value-graph-zooms-its-value-range-and-the-ti`). Written before the
/// model: the value under the pointer stays where it is drawn, closer in is a
/// narrower range, and there is a limit either way so the line never vanishes.
@Suite("Graph value range")
struct GraphValueRangeTests {

    static let fit = GraphValueRange(low: 100, high: 200)

    @Test func readsTheValueAtAFractionDownFromTheTop() {
        #expect(Self.fit.value(atFractionFromTop: 0) == 200)
        #expect(Self.fit.value(atFractionFromTop: 1) == 100)
        #expect(Self.fit.value(atFractionFromTop: 0.25) == 175)
    }

    @Test func zoomingInNarrowsTheRangeAboutTheAnchor() {
        let zoomed = Self.fit.zoomed(by: 2, about: 150, fit: Self.fit)
        #expect(zoomed.low == 125)
        #expect(zoomed.high == 175)
    }

    @Test func theAnchorKeepsItsPlaceOnScreen() {
        // 175 is a quarter of the way down; zoomed about it, it still is.
        let zoomed = Self.fit.zoomed(by: 4, about: 175, fit: Self.fit)
        #expect(abs(zoomed.fraction(of: 175) - 0.25) < 1e-9)
        #expect(abs(zoomed.span - 25) < 1e-9)
    }

    @Test func zoomingOutWidensIt() {
        let zoomed = Self.fit.zoomed(by: 0.5, about: 150, fit: Self.fit)
        #expect(zoomed.low == 50)
        #expect(zoomed.high == 250)
    }

    @Test func goesNoCloserThanAHundredthOfTheFit() {
        let zoomed = Self.fit.zoomed(by: 10_000, about: 150, fit: Self.fit)
        #expect(abs(zoomed.span - 1) < 1e-9)
        #expect(abs(zoomed.fraction(of: 150) - 0.5) < 1e-9)
    }

    @Test func goesNoFurtherOutThanTwentyFits() {
        let zoomed = Self.fit.zoomed(by: 0.0001, about: 150, fit: Self.fit)
        #expect(abs(zoomed.span - 2000) < 1e-9)
    }

    @Test func aFlatLineStillZooms() {
        // One value all the way along: the fit has no height, so the range
        // is measured against the value itself.
        let flat = GraphValueRange(low: 50, high: 50)
        let zoomed = flat.zoomed(by: 0.5, about: 50, fit: flat)
        #expect(zoomed.span > 0)
        #expect(abs(zoomed.fraction(of: 50) - 0.5) < 1e-9)
    }

    @Test func aNonsenseFactorLeavesItAlone() {
        #expect(Self.fit.zoomed(by: 0, about: 150, fit: Self.fit) == Self.fit)
        #expect(Self.fit.zoomed(by: .nan, about: 150, fit: Self.fit) == Self.fit)
    }

    @Test func theWheelZoomsInOneWayAndOutTheOther() {
        #expect(GraphValueRange.wheelFactor(deltaY: 20) > 1)
        #expect(GraphValueRange.wheelFactor(deltaY: -20) < 1)
        #expect(GraphValueRange.wheelFactor(deltaY: 0) == 1)
    }
}
