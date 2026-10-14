import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The tinted band between a zoom callout's two leader lines: the user,
/// 2026-10-13, "I'd like the area in between to be filled the line color but be
/// 10% opacity (configurable)."
@Suite("Zoom callout band")
struct ZoomCalloutBandTests {

    private func distance(_ p: CGPoint, toLineThrough a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        return abs((p.x - a.x) * dy - (p.y - a.y) * dx) / length
    }

    // MARK: The setting

    @Test func aNewCalloutTintsItsBandAtTenPercent() {
        let callout = ZoomCalloutContent(sourceRect: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(callout.fillOpacity == 0.1)
        #expect(ZoomCalloutContent.defaultFillOpacity == 0.1)
    }

    /// A saved document opens looking as it was saved: no band appears on a
    /// callout nobody tinted.
    @Test func aCalloutSavedBeforeTheBandOpensWithNone() throws {
        let old = #"{"sourceRect":[[0,0],[10,10]],"magnification":2,"shape":"circle"}"#
        let callout = try JSONDecoder().decode(ZoomCalloutContent.self, from: Data(old.utf8))
        #expect(callout.fillOpacity == 0)
        #expect(callout.shape == .circle)
    }

    @Test func fillOpacityRoundTripsAndStaysBetweenNoneAndAll() throws {
        var callout = ZoomCalloutContent(sourceRect: CGRect(x: 0, y: 0, width: 10, height: 10),
                                         fillOpacity: 0.35)
        let back = try JSONDecoder().decode(ZoomCalloutContent.self,
                                            from: JSONEncoder().encode(callout))
        #expect(back.fillOpacity == 0.35)
        callout.fillOpacity = 4
        #expect(callout.fillOpacity == 1)
        callout.fillOpacity = -1
        #expect(callout.fillOpacity == 0)
    }

    @Test func theToolRemembersTheFillForTheNextCallout() throws {
        var styles = CalloutStyles()
        #expect(styles.fillOpacity == ZoomCalloutContent.defaultFillOpacity)
        styles.fillOpacity = 0.25
        let back = try JSONDecoder().decode(CalloutStyles.self, from: JSONEncoder().encode(styles))
        #expect(back.fillOpacity == 0.25)
        // A memory written before the band existed reads as the default.
        let old = try JSONDecoder().decode(CalloutStyles.self,
                                           from: Data(#"{"shape":"circle"}"#.utf8))
        #expect(old.fillOpacity == ZoomCalloutContent.defaultFillOpacity)
    }

    @Test func aDrawnCalloutTakesTheFillItIsHanded() throws {
        let layer = try #require(ZoomCalloutBuilder.layer(
            from: CGPoint(x: 100, y: 100), to: CGPoint(x: 160, y: 140),
            canvas: CGSize(width: 800, height: 600), fillOpacity: 0.4))
        #expect(layer.zoomCallout?.fillOpacity == 0.4)
    }

    // MARK: Rectangle

    /// The band is the four ends of the two leader lines, in order round the
    /// outside, so its edges ARE the lines.
    @Test func aBoxBandIsBoundedByItsTwoLeaderLines() throws {
        let source = CGRect(x: 10, y: 40, width: 20, height: 20)
        let corners = Geometry.corners(of: CGRect(x: 100, y: 0, width: 80, height: 100))
        let lines = Geometry.leaderLines(source: source, calloutCorners: corners, shape: .rectangle)
        let band = Geometry.zoomCalloutBand(source: source, calloutCorners: corners, shape: .rectangle)
        #expect(lines.count == 2)
        #expect(band == [lines[0].from, lines[0].to, lines[1].to, lines[1].from])
        // The rectangle keeps the nearest-corner lines it has always had.
        let old = Geometry.leaderLines(source: source, calloutCorners: corners)
        #expect(lines.map { $0.from } == old.map { $0.from } && lines.map { $0.to } == old.map { $0.to })
    }

    // MARK: Circle

    /// A circle callout's lines are the two lines that just touch both
    /// circles, so they run from one round edge to the other instead of
    /// dangling off the corners of the boxes the circles sit in.
    @Test func circleLinesTouchBothCircles() throws {
        let source = CGRect(x: 0, y: 0, width: 40, height: 40)          // r 20, centre (20, 20)
        let callout = CGRect(x: 200, y: -40, width: 120, height: 120)   // r 60, centre (260, 20)
        let lines = Geometry.leaderLines(source: source, calloutCorners: Geometry.corners(of: callout),
                                         shape: .circle)
        try #require(lines.count == 2)
        let sc = CGPoint(x: 20, y: 20), cc = CGPoint(x: 260, y: 20)
        for line in lines {
            // Each end sits on its own circle...
            #expect(abs(hypot(line.from.x - sc.x, line.from.y - sc.y) - 20) < 0.1)
            #expect(abs(hypot(line.to.x - cc.x, line.to.y - cc.y) - 60) < 0.1)
            // ...and the line only touches each: its distance from each centre
            // is that circle's radius, within a tenth of a point.
            #expect(abs(distance(sc, toLineThrough: line.from, line.to) - 20) < 0.1)
            #expect(abs(distance(cc, toLineThrough: line.from, line.to) - 60) < 0.1)
        }
        // One above the centres, one below.
        #expect(Set(lines.map { $0.to.y < 20 }) == [true, false])
    }

    @Test func aCircleBandSitsOnItsTangentLines() throws {
        let source = CGRect(x: 0, y: 0, width: 40, height: 40)
        let corners = Geometry.corners(of: CGRect(x: 200, y: -40, width: 120, height: 120))
        let lines = Geometry.leaderLines(source: source, calloutCorners: corners, shape: .circle)
        let band = Geometry.zoomCalloutBand(source: source, calloutCorners: corners, shape: .circle)
        try #require(lines.count == 2)
        #expect(band == [lines[0].from, lines[0].to, lines[1].to, lines[1].from])
    }

    /// A turned circle callout is still a circle, so the lines still touch it.
    @Test func aTurnedCircleIsStillTouched() throws {
        let source = CGRect(x: 0, y: 0, width: 40, height: 40)
        let box = CGRect(x: 200, y: -40, width: 120, height: 120)
        let centre = CGPoint(x: box.midX, y: box.midY)
        let turn = CGAffineTransform(translationX: centre.x, y: centre.y)
            .rotated(by: .pi / 5).translatedBy(x: -centre.x, y: -centre.y)
        let turned = Geometry.corners(of: box).map { $0.applying(turn) }
        let lines = Geometry.leaderLines(source: source, calloutCorners: turned, shape: .circle)
        try #require(lines.count == 2)
        for line in lines {
            #expect(abs(distance(centre, toLineThrough: line.from, line.to) - 60) < 0.1)
        }
    }

    /// A circle on a box that is not square is a capsule, and the lines touch
    /// the capsule: no point of either outline lies outside the band's side.
    @Test func capsuleLinesNeverCutIntoEitherShape() throws {
        let source = CGRect(x: 0, y: 0, width: 60, height: 30)
        let corners = Geometry.corners(of: CGRect(x: 150, y: 80, width: 180, height: 90))
        let lines = Geometry.leaderLines(source: source, calloutCorners: corners, shape: .circle)
        try #require(lines.count == 2)
        let outline = Geometry.zoomCalloutOutline(corners: Geometry.corners(of: source), shape: .circle)
            + Geometry.zoomCalloutOutline(corners: corners, shape: .circle)
        for line in lines {
            let sides = outline.map { p -> CGFloat in
                (line.to.x - line.from.x) * (p.y - line.from.y)
                    - (line.to.y - line.from.y) * (p.x - line.from.x)
            }
            // Every outline point on one side of (or on) the line.
            let length = hypot(line.to.x - line.from.x, line.to.y - line.from.y)
            #expect(sides.allSatisfy { $0 / length > -0.01 } || sides.allSatisfy { $0 / length < 0.01 })
        }
    }

    @Test func aCircleInsideTheOtherHasNoLines() {
        let source = CGRect(x: 120, y: 120, width: 20, height: 20)
        let corners = Geometry.corners(of: CGRect(x: 0, y: 0, width: 400, height: 400))
        #expect(Geometry.leaderLines(source: source, calloutCorners: corners, shape: .circle).isEmpty)
        #expect(Geometry.zoomCalloutBand(source: source, calloutCorners: corners, shape: .circle).isEmpty)
    }

    @Test func boxTransformPutsTheUprightBoxOnItsCorners() throws {
        let box = CGRect(x: 10, y: 20, width: 80, height: 40)
        let turn = CGAffineTransform(rotationAngle: 0.4)
        let corners = Geometry.corners(of: box).map { $0.applying(turn) }
        let placed = try #require(Geometry.boxPlacement(corners: corners))
        #expect(abs(placed.size.width - 80) < 1e-9 && abs(placed.size.height - 40) < 1e-9)
        for (local, drawn) in zip(Geometry.corners(of: CGRect(origin: .zero, size: placed.size)), corners) {
            let mapped = local.applying(placed.transform)
            #expect(abs(mapped.x - drawn.x) < 1e-9 && abs(mapped.y - drawn.y) < 1e-9)
        }
    }
}
