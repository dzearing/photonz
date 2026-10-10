import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Where the floating recording control (timer and Stop) sits. All in screen
/// points with y going up, the way the Mac lays out its screens.
@Suite("The recording control starts bottom left and stays where it is put")
struct RecordingControlPlacementTests {
    /// A 1512 x 982 laptop screen with a 33 pt menu bar and no Dock showing.
    let laptop = CGRect(x: 0, y: 0, width: 1512, height: 949)
    let size = RecordingControlPlacement.size
    let inset = RecordingControlPlacement.glassInset

    // MARK: The default spot

    @Test func neverMovedItSitsBottomLeftSixteenPointsInFromBothEdges() {
        let frame = RecordingControlPlacement.frame(spot: nil, visible: laptop)
        #expect(frame.size == size)
        // The glass the person sees is 16 pt in; the window has a little
        // clear padding around it.
        #expect(frame.minX + inset == 16)
        #expect(frame.minY + inset == 16)
    }

    @Test func theDefaultSitsAboveTheDock() {
        // A 70 pt Dock along the bottom: the visible area starts above it.
        let withDock = CGRect(x: 0, y: 70, width: 1512, height: 879)
        let frame = RecordingControlPlacement.frame(spot: nil, visible: withDock)
        #expect(frame.minY + inset == 86)
        #expect(frame.minX + inset == 16)
    }

    @Test func theDefaultFollowsAScreenThatIsNotAtTheOrigin() {
        let second = CGRect(x: 1512, y: -200, width: 1920, height: 1050)
        let frame = RecordingControlPlacement.frame(spot: nil, visible: second)
        #expect(frame.minX + inset == 1528)
        #expect(frame.minY + inset == -184)
    }

    // MARK: Remembering where it was let go

    @Test func aSpotIsRememberedFromItsNearestCorner() {
        // Let go near the top right.
        let frame = CGRect(x: 1200, y: 800, width: size.width, height: size.height)
        let spot = RecordingControlPlacement.spot(for: frame, visible: laptop)
        #expect(spot.corner == .topRight)
        #expect(spot.fromSide == Double(laptop.maxX - frame.maxX))
        #expect(spot.fromEnd == Double(laptop.maxY - frame.maxY))
    }

    @Test func everyCornerComesBackWhereItWasLeft() {
        let lefts: [CGRect] = [
            CGRect(x: 40, y: 30, width: size.width, height: size.height),     // bottom left
            CGRect(x: 1100, y: 60, width: size.width, height: size.height),   // bottom right
            CGRect(x: 90, y: 820, width: size.width, height: size.height),    // top left
            CGRect(x: 1250, y: 880, width: size.width, height: size.height),  // top right
        ]
        let corners: [RecordingControlSpot.Corner] = [.bottomLeft, .bottomRight, .topLeft, .topRight]
        for (frame, corner) in zip(lefts, corners) {
            let spot = RecordingControlPlacement.spot(for: frame, visible: laptop)
            #expect(spot.corner == corner)
            #expect(RecordingControlPlacement.frame(spot: spot, visible: laptop) == frame)
        }
    }

    @Test func onABiggerScreenItLandsTheSameDistanceFromTheSameCorner() {
        let frame = CGRect(x: 1200, y: 40, width: size.width, height: size.height)
        let spot = RecordingControlPlacement.spot(for: frame, visible: laptop)
        #expect(spot.corner == .bottomRight)
        let studio = CGRect(x: 0, y: 0, width: 2560, height: 1400)
        let there = RecordingControlPlacement.frame(spot: spot, visible: studio)
        #expect(studio.maxX - there.maxX == laptop.maxX - frame.maxX)
        #expect(there.minY - studio.minY == frame.minY - laptop.minY)
    }

    @Test func aSpotSurvivesBeingWrittenAndReadBack() throws {
        let spot = RecordingControlSpot(corner: .topLeft, fromSide: 120, fromEnd: 44)
        let data = try JSONEncoder().encode(spot)
        #expect(try JSONDecoder().decode(RecordingControlSpot.self, from: data) == spot)
    }

    // MARK: Pulled back inside

    @Test func aSpotOffTheScreenIsPulledBackInside() {
        // Remembered 900 pt from the right on a big screen, then shown on a
        // small one: it would hang off the left edge.
        let spot = RecordingControlSpot(corner: .bottomRight, fromSide: 1400, fromEnd: -30)
        let small = CGRect(x: 0, y: 0, width: 1280, height: 777)
        let frame = RecordingControlPlacement.frame(spot: spot, visible: small)
        #expect(small.contains(frame))
        #expect(frame.minX == small.minX)
        #expect(frame.minY == small.minY)
    }

    @Test func aSpotUnderTheMenuBarIsPulledBelowIt() {
        let spot = RecordingControlSpot(corner: .topLeft, fromSide: 300, fromEnd: -20)
        let frame = RecordingControlPlacement.frame(spot: spot, visible: laptop)
        #expect(frame.maxY == laptop.maxY)
        #expect(frame.minX == 300)
    }

    @Test func clampingLeavesASpotAlreadyInsideAlone() {
        let frame = CGRect(x: 500, y: 400, width: size.width, height: size.height)
        #expect(RecordingControlPlacement.clamped(frame, into: laptop) == frame)
    }

    // MARK: Recording a region

    @Test func aRegionInTheTopLeftCornerOfTheDisplayIsTurnedIntoScreenPoints() {
        // The region overlay reports points from the display's top left.
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let region = CGRect(x: 100, y: 50, width: 400, height: 300)
        let onScreen = RecordingControlPlacement.screenRect(ofRegion: region, screenFrame: screen)
        #expect(onScreen == CGRect(x: 100, y: 982 - 350, width: 400, height: 300))
    }

    @Test func aRegionAwayFromTheControlLeavesItWhereItIs() {
        let region = CGRect(x: 700, y: 500, width: 400, height: 300)
        let plain = RecordingControlPlacement.frame(spot: nil, visible: laptop)
        #expect(RecordingControlPlacement.frame(spot: nil, visible: laptop, region: region) == plain)
    }

    @Test func aRegionOverTheControlPushesItToTheNearestSideOutsideIt() {
        // A region over the bottom left corner, wider than it is tall: the
        // shortest way out is up, over the region's top edge.
        let region = CGRect(x: 0, y: 0, width: 900, height: 200)
        let frame = RecordingControlPlacement.frame(spot: nil, visible: laptop, region: region)
        #expect(!frame.intersects(region))
        #expect(frame.minY == region.maxY + RecordingControlPlacement.regionGap)
        // It moved straight up, not sideways too.
        #expect(frame.minX == RecordingControlPlacement.frame(spot: nil, visible: laptop).minX)
    }

    @Test func aTallRegionPushesItSideways() {
        let region = CGRect(x: 0, y: 0, width: 300, height: 949)
        let frame = RecordingControlPlacement.frame(spot: nil, visible: laptop, region: region)
        #expect(!frame.intersects(region))
        #expect(frame.minX == region.maxX + RecordingControlPlacement.regionGap)
    }

    @Test func aRegionInTheMiddleSendsItToWhicheverEdgeIsClosest() {
        // The control remembered just inside the region's left edge.
        let region = CGRect(x: 400, y: 200, width: 700, height: 500)
        let spot = RecordingControlPlacement.spot(
            for: CGRect(x: 410, y: 400, width: size.width, height: size.height), visible: laptop)
        let frame = RecordingControlPlacement.frame(spot: spot, visible: laptop, region: region)
        #expect(!frame.intersects(region))
        #expect(frame.maxX == region.minX - RecordingControlPlacement.regionGap)
        #expect(frame.minY == 400)
    }

    @Test func aRegionCoveringTheWholeScreenLeavesItWhereItWas() {
        // Nowhere outside it to go: it stays put, and it is left out of the
        // picture either way.
        let frame = RecordingControlPlacement.frame(spot: nil, visible: laptop, region: laptop)
        #expect(frame == RecordingControlPlacement.frame(spot: nil, visible: laptop))
    }
}
