import CoreGraphics
import Foundation
import PhotonzCore
import Testing

private let clip = CGRect(x: 0, y: 0, width: 1280, height: 800)
private let box = CGRect(x: 100, y: 100, width: 640, height: 400)

private func hit(_ x: CGFloat, _ y: CGFloat, reach: CGFloat = 10) -> ZoomBoxHit? {
    ZoomBoxHit.at(CGPoint(x: x, y: y), box: box, clip: clip, reach: reach)
}

@Suite("What a press takes hold of while a zoom's box is up")
struct ZoomBoxHitTests {

    @Test func eachCornerIsItsOwnResize() {
        #expect(hit(100, 100) == .corner(.topLeft))
        #expect(hit(740, 100) == .corner(.topRight))
        #expect(hit(740, 500) == .corner(.bottomRight))
        #expect(hit(100, 500) == .corner(.bottomLeft))
    }

    @Test func aCornerReachesJustOutsideTheBox() {
        #expect(hit(93, 94) == .corner(.topLeft))
        #expect(hit(85, 100) == .beside)
    }

    @Test func insideTheBoxCarriesIt() {
        #expect(hit(400, 300) == .body)
        // An edge is not a handle: the box keeps the frame's shape, so it only
        // resizes from a corner.
        #expect(hit(400, 100) == .body)
    }

    @Test func onTheClipBesideTheBoxDrawsItAgain() {
        #expect(hit(1000, 700) == .beside)
    }

    @Test func offTheClipIsNotTheBoxs() {
        #expect(hit(1400, 300) == nil)
        #expect(hit(-30, -30) == nil)
    }

    @Test func aCornerOfTheClipStillReachesABoxCornerOnIt() {
        let full = CGRect(x: 0, y: 0, width: 1280, height: 800)
        #expect(ZoomBoxHit.at(CGPoint(x: -6, y: -6), box: full, clip: clip, reach: 10) == .corner(.topLeft))
    }

    @Test func theOppositeCornerIsTheOneThatStaysPut() {
        #expect(ZoomBoxHit.corner(.topLeft).anchor(of: box) == CGPoint(x: 740, y: 500))
        #expect(ZoomBoxHit.corner(.topRight).anchor(of: box) == CGPoint(x: 100, y: 500))
        #expect(ZoomBoxHit.corner(.bottomRight).anchor(of: box) == CGPoint(x: 100, y: 100))
        #expect(ZoomBoxHit.corner(.bottomLeft).anchor(of: box) == CGPoint(x: 740, y: 100))
        #expect(ZoomBoxHit.body.anchor(of: box) == nil)
    }

    @Test func thePointerSaysWhatThePressTakes() {
        #expect(ZoomBoxHit.corner(.topLeft).cue == .resize(.topLeft))
        #expect(ZoomBoxHit.corner(.bottomLeft).cue == .resize(.bottomLeft))
        #expect(ZoomBoxHit.body.cue == .grab)
        #expect(ZoomBoxHit.beside.cue == nil)
    }

    @Test func theNearestCornerWinsOnATinyBox() {
        let tiny = CGRect(x: 100, y: 100, width: 8, height: 5)
        #expect(ZoomBoxHit.at(CGPoint(x: 107, y: 104), box: tiny, clip: clip, reach: 10) == .corner(.bottomRight))
        #expect(ZoomBoxHit.at(CGPoint(x: 101, y: 101), box: tiny, clip: clip, reach: 10) == .corner(.topLeft))
    }
}

@Suite("Walks can ask whether a zoom is picked")
struct ZoomPickedWalkActionTests {

    @Test func bothClaimsAreActionsTheEditorAnswers() {
        #expect(PlaytestAction(rawValue: "expectZoomPicked")?.drivesTheTimeline == true)
        #expect(PlaytestAction(rawValue: "expectZoomLetGo")?.drivesTheTimeline == true)
        #expect(PlaytestAction(rawValue: "zoomAddAtPlayhead")?.drivesTheTimeline == true)
    }

    @Test func thePointerBesideTheBoxIsAClaimAWalkMayMake() {
        #expect(PlaytestScript.pointerCueNames.contains("draw"))
    }

    @Test func aClickThatPutsTheBoxBackUpIsAClaimAWalkMayMake() {
        #expect(PlaytestScript.pointerCueNames.contains("frame"))
    }
}

@Suite("Walks can check what a scrub across a zoom shows")
struct ZoomScrubWalkActionTests {

    @Test func theScrubClaimsAreActionsTheEditorAnswers() {
        #expect(PlaytestAction(rawValue: "expectZoomScrubMatchesExport")?.drivesTheTimeline == true)
        #expect(PlaytestAction(rawValue: "expectZoomEasesFrameByFrame")?.drivesTheTimeline == true)
        #expect(PlaytestAction(rawValue: "expectZoomBoxDown")?.drivesTheTimeline == true)
    }
}
