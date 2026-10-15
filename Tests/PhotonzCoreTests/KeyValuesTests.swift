import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Clicking a key opens a small popover to type that key's value (task
/// `clicking-a-key-opens-the-same-overlay-to-set-tha`,
/// `docs/design/mocks/pages/video-animate.html`, THE KEY OVERLAY).
///
/// Written before the model: the picked keys read back as one row per keyed
/// value in its own units, Mixed where they differ; a value typed lands on
/// every picked key of that value and nothing else; Reset puts them at the
/// property's default.
@Suite("Key values")
struct KeyValuesTests {

    typealias Lanes = KeyLanesTests

    // MARK: - Reading

    @Test func oneOpacityKeyReadsAsOneRowInPercent() throws {
        let (doc, id) = Lanes.keyed()
        let refs = Lanes.refs(doc, id, .opacity, at: [5000])
        let rows = doc.keyValueRows(layerID: id, refs)
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.property == .opacity)
        #expect(row.title == "Opacity")
        #expect(row.unit == "%")
        #expect(row.value == .number(0))
    }

    @Test func keysThatDifferReadMixedAndKeysThatAgreeReadTheirValue() throws {
        let (doc, id) = Lanes.keyed()
        let differ = Lanes.refs(doc, id, .opacity, at: [3000, 5000])
        #expect(doc.keyValueRows(layerID: id, differ).first?.value == .mixed)
        // Scale 100 at 3s and opacity 100 at 3s are two rows, each its own.
        let both = Lanes.refs(doc, id, .scale, at: [3000]).union(Lanes.refs(doc, id, .opacity, at: [3000]))
        let rows = doc.keyValueRows(layerID: id, both)
        #expect(rows.map(\.property) == [.scale, .opacity])
        #expect(rows.map(\.value) == [.number(100), .number(100)])
    }

    @Test func eachValueReadsInItsOwnUnits() {
        #expect(MotionProperty.opacity.keyValueUnit == "%")
        #expect(MotionProperty.scale.keyValueUnit == "%")
        #expect(MotionProperty.rotation.keyValueUnit == "°")
        #expect(MotionProperty.rotationY.keyValueUnit == "°")
        #expect(MotionProperty.shadowDirection.keyValueUnit == "°")
        #expect(MotionProperty.cropLeft.keyValueUnit == "%")
        #expect(MotionProperty.blur.keyValueUnit == nil)
        #expect(MotionProperty.depth.keyValueUnit == nil)
        #expect(MotionProperty.position.keyValueUnit == nil)
    }

    @Test func aPositionKeyReadsAsAPointAndAColourKeyAsItsHex() throws {
        var (doc, id) = Lanes.withTitle()
        doc.startKeying(layerID: id, .motion(.position), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.point(CGPoint(x: 400, y: 200)), layerID: id, .motion(.position), atDocumentTimeMS: 6000)
        let refs = Lanes.refs(doc, id, .position, at: [6000])
        #expect(doc.keyValueRows(layerID: id, refs).first?.value == .point(x: 400, y: 200))
        // Two points that share X and not Y read X and Mixed.
        doc.setKeyedValue(.point(CGPoint(x: 400, y: 90)), layerID: id, .motion(.position), atDocumentTimeMS: 3000)
        let two = Lanes.refs(doc, id, .position, at: [3000, 6000])
        #expect(doc.keyValueRows(layerID: id, two).first?.value == .point(x: 400, y: nil))

        doc.startKeying(layerID: id, .motion(.color), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.color("#FF5D8F"), layerID: id, .motion(.color), atDocumentTimeMS: 6000)
        let colour = Lanes.refs(doc, id, .color, at: [6000])
        #expect(doc.keyValueRows(layerID: id, colour).first?.value == .color("#FF5D8F"))
    }

    // MARK: - Setting

    @Test func aTypedValueLandsOnThePickedKeyAndNowhereElse() throws {
        var (doc, id) = Lanes.keyed()
        let lane = try #require(Lanes.lane(doc, id, .opacity))
        let refs = Lanes.refs(doc, id, .opacity, at: [5000])
        let landed = doc.setKeyValues(layerID: id, refs, motionID: lane.motionID, .number(40))
        #expect(landed)
        #expect(Lanes.value(doc, id, .opacity, 5000) == 40)
        #expect(Lanes.value(doc, id, .opacity, 3000) == 100)
        #expect(Lanes.value(doc, id, .scale, 6000) == 200)
        // The key stays where it was in time.
        #expect(Lanes.lane(doc, id, .opacity)?.keys.map(\.documentMS) == [3000, 5000])
    }

    @Test func aTypedValueSetsEveryPickedKeyOfThatValue() throws {
        var (doc, id) = Lanes.keyed()
        let lane = try #require(Lanes.lane(doc, id, .opacity))
        let refs = Lanes.refs(doc, id, .opacity, at: [3000, 5000])
            .union(Lanes.refs(doc, id, .scale, at: [6000]))
        doc.setKeyValues(layerID: id, refs, motionID: lane.motionID, .number(55))
        #expect(Lanes.value(doc, id, .opacity, 3000) == 55)
        #expect(Lanes.value(doc, id, .opacity, 5000) == 55)
        // Scale is its own row: typing opacity leaves it alone.
        #expect(Lanes.value(doc, id, .scale, 6000) == 200)
        #expect(doc.keyValueRows(layerID: id, refs).first { $0.property == .opacity }?.value == .number(55))
    }

    @Test func aTypedValueIsKeptToWhatThePropertyCanBe() throws {
        var (doc, id) = Lanes.keyed()
        let opacity = try #require(Lanes.lane(doc, id, .opacity))
        doc.setKeyValues(layerID: id, Lanes.refs(doc, id, .opacity, at: [5000]), motionID: opacity.motionID,
                         .number(140))
        #expect(Lanes.value(doc, id, .opacity, 5000) == 100)
        let scale = try #require(Lanes.lane(doc, id, .scale))
        doc.setKeyValues(layerID: id, Lanes.refs(doc, id, .scale, at: [6000]), motionID: scale.motionID,
                         .number(-20))
        #expect(Lanes.value(doc, id, .scale, 6000) == 0)
    }

    @Test func oneAxisOfAPointSetsThatAxisOnly() throws {
        var (doc, id) = Lanes.withTitle()
        doc.startKeying(layerID: id, .motion(.position), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.point(CGPoint(x: 400, y: 200)), layerID: id, .motion(.position), atDocumentTimeMS: 6000)
        let lane = try #require(Lanes.lane(doc, id, .position))
        let refs = Lanes.refs(doc, id, .position, at: [6000])
        doc.setKeyValues(layerID: id, refs, motionID: lane.motionID, .x(560))
        #expect(doc.keyValueRows(layerID: id, refs).first?.value == .point(x: 560, y: 200))
        doc.setKeyValues(layerID: id, refs, motionID: lane.motionID, .y(500))
        #expect(doc.keyValueRows(layerID: id, refs).first?.value == .point(x: 560, y: 500))
    }

    @Test func aColourTypedAsHexLandsAndNonsenseDoesNot() throws {
        var (doc, id) = Lanes.withTitle()
        doc.startKeying(layerID: id, .motion(.color), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.color("#FF5D8F"), layerID: id, .motion(.color), atDocumentTimeMS: 6000)
        let lane = try #require(Lanes.lane(doc, id, .color))
        let refs = Lanes.refs(doc, id, .color, at: [6000])
        let landed1 = doc.setKeyValues(layerID: id, refs, motionID: lane.motionID, .color("00aaff"))
        #expect(landed1)
        #expect(doc.keyValueRows(layerID: id, refs).first?.value == .color("#00AAFF"))
        let landed2 = doc.setKeyValues(layerID: id, refs, motionID: lane.motionID, .color("purple"))
        #expect(!landed2)
        #expect(doc.keyValueRows(layerID: id, refs).first?.value == .color("#00AAFF"))
    }

    @Test func aValueOfTheWrongKindChangesNothing() throws {
        var (doc, id) = Lanes.keyed()
        let lane = try #require(Lanes.lane(doc, id, .opacity))
        let refs = Lanes.refs(doc, id, .opacity, at: [5000])
        let landed3 = doc.setKeyValues(layerID: id, refs, motionID: lane.motionID, .x(10))
        #expect(!landed3)
        let landed4 = doc.setKeyValues(layerID: id, refs, motionID: lane.motionID, .color("#FFFFFF"))
        #expect(!landed4)
        #expect(Lanes.value(doc, id, .opacity, 5000) == 0)
    }

    // MARK: - Reset

    @Test func resetPutsThePickedKeysAtThePropertysDefault() throws {
        var (doc, id) = Lanes.keyed()
        let refs = Lanes.refs(doc, id, .opacity, at: [5000]).union(Lanes.refs(doc, id, .scale, at: [6000]))
        #expect(doc.canResetKeyValues(layerID: id, refs))
        let landed5 = doc.resetKeyValues(layerID: id, refs)
        #expect(landed5)
        #expect(Lanes.value(doc, id, .opacity, 5000) == 100)
        #expect(Lanes.value(doc, id, .scale, 6000) == 100)
        // Already at the default: nothing left to reset.
        #expect(!doc.canResetKeyValues(layerID: id, refs))
    }

    @Test func eachValueResetsToWhatAnUntouchedLayerHas() {
        #expect(MotionProperty.opacity.keyValueDefault == .number(100))
        #expect(MotionProperty.scale.keyValueDefault == .number(100))
        #expect(MotionProperty.rotation.keyValueDefault == .number(0))
        #expect(MotionProperty.rotationX.keyValueDefault == .number(0))
        #expect(MotionProperty.depth.keyValueDefault == .number(0))
        #expect(MotionProperty.trimEnd.keyValueDefault == .number(100))
        #expect(MotionProperty.cropTop.keyValueDefault == .number(0))
        // No one value a position or a colour goes back to.
        #expect(MotionProperty.position.keyValueDefault == nil)
        #expect(MotionProperty.color.keyValueDefault == nil)
    }

    @Test func resetPutsAPositionKeyInTheMiddleOfTheCanvas() throws {
        var (doc, id) = Lanes.withTitle()
        doc.startKeying(layerID: id, .motion(.position), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.point(CGPoint(x: 10, y: 20)), layerID: id, .motion(.position), atDocumentTimeMS: 6000)
        let refs = Lanes.refs(doc, id, .position, at: [6000])
        #expect(doc.canResetKeyValues(layerID: id, refs))
        let reset = doc.resetKeyValues(layerID: id, refs)
        #expect(reset)
        let frame = try #require(doc.layer(id: id)?.frame)
        let middle = CGPoint(x: (doc.canvasSize.width - frame.width) / 2, y: (doc.canvasSize.height - frame.height) / 2)
        #expect(doc.keyValueRows(layerID: id, refs).first?.value == .point(x: Double(middle.x), y: Double(middle.y)))
        #expect(!doc.canResetKeyValues(layerID: id, refs))
    }

    @Test func aValueWithNoDefaultHasNothingToReset() throws {
        var (doc, id) = Lanes.withTitle()
        doc.startKeying(layerID: id, .motion(.color), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.color("#FF5D8F"), layerID: id, .motion(.color), atDocumentTimeMS: 6000)
        let refs = Lanes.refs(doc, id, .color, at: [6000])
        #expect(!doc.canResetKeyValues(layerID: id, refs))
        let landed6 = doc.resetKeyValues(layerID: id, refs)
        #expect(!landed6)
    }
}

@Suite("Key values placement")
struct KeyValuesPlacementTests {
    let window = CGRect(x: 0, y: 0, width: 1200, height: 800)
    let size = CGSize(width: 180, height: 70)

    @Test func itSitsAboveTheKeyCentredOnIt() {
        let key = CGRect(x: 600, y: 600, width: 14, height: 14)
        let frame = KeyValuesPlacement.frame(anchor: key, size: size, in: window)
        #expect(frame.midX == key.midX)
        #expect(frame.maxY == key.minY - KeyValuesPlacement.gap)
        #expect(!frame.intersects(key))
    }

    @Test func withNoRoomAboveItGoesBelowAndStillMissesTheKey() {
        let key = CGRect(x: 600, y: 30, width: 14, height: 14)
        let frame = KeyValuesPlacement.frame(anchor: key, size: size, in: window)
        #expect(frame.minY == key.maxY + KeyValuesPlacement.gap)
        #expect(!frame.intersects(key))
    }

    @Test func nearAnEdgeItSlidesInsideTheWindow() {
        let left = KeyValuesPlacement.frame(anchor: CGRect(x: 2, y: 600, width: 14, height: 14), size: size, in: window)
        #expect(left.minX == KeyValuesPlacement.margin)
        let right = KeyValuesPlacement.frame(anchor: CGRect(x: 1190, y: 600, width: 14, height: 14), size: size,
                                             in: window)
        #expect(right.maxX == window.maxX - KeyValuesPlacement.margin)
    }

    // On an open graph the key is a point on a curve: the popover keeps off
    // the line as well as the point, so the segment about to be shaped stays
    // in sight.

    let point = CGRect(x: 600, y: 600, width: 14, height: 14)
    var centre: CGPoint { CGPoint(x: point.midX, y: point.midY) }

    /// A line through the point, sampled the way the graph draws it.
    func line(_ from: CGPoint, _ to: CGPoint) -> [CGPoint] {
        (0...20).map { step in
            let t = CGFloat(step) / 20
            return CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
        }
    }

    func expectClear(_ frame: CGRect, of lines: [[CGPoint]]) {
        #expect(KeyValuesPlacement.covered(frame, by: lines) == 0)
        #expect(!frame.intersects(point))
        #expect(window.insetBy(dx: KeyValuesPlacement.margin, dy: KeyValuesPlacement.margin).contains(frame))
    }

    @Test func coveredMeasuresHowMuchLineIsUnderTheFrame() {
        let frame = CGRect(x: 100, y: 100, width: 100, height: 50)
        #expect(KeyValuesPlacement.covered(frame, by: [line(CGPoint(x: 0, y: 300), CGPoint(x: 400, y: 300))]) == 0)
        let across = KeyValuesPlacement.covered(frame, by: [line(CGPoint(x: 0, y: 125), CGPoint(x: 400, y: 125))])
        #expect(abs(across - (100 + 2 * KeyValuesPlacement.clearance)) < 0.001)
        #expect(KeyValuesPlacement.covered(frame, by: []) == 0)
    }

    @Test func aLineThatMissesTheSpotAboveChangesNothing() {
        // A closed row: the line runs flat through the keys.
        let flat = [line(CGPoint(x: 0, y: centre.y), CGPoint(x: 1200, y: centre.y))]
        let frame = KeyValuesPlacement.frame(anchor: point, size: size, in: window, clearOf: flat)
        #expect(frame == KeyValuesPlacement.frame(anchor: point, size: size, in: window))
        #expect(frame.midX == point.midX)
        #expect(frame.maxY == point.minY - KeyValuesPlacement.gap)
    }

    @Test func onARisingCurveItStaysAboveAndOffTheSegmentLeavingThePoint() {
        let lines = [line(CGPoint(x: 300, y: 680), centre), line(centre, CGPoint(x: 900, y: 520))]
        let frame = KeyValuesPlacement.frame(anchor: point, size: size, in: window, clearOf: lines)
        expectClear(frame, of: lines)
        #expect(frame.maxY <= point.minY)
        // The plain spot above would have covered the line leaving the point.
        #expect(KeyValuesPlacement.covered(KeyValuesPlacement.frame(anchor: point, size: size, in: window),
                                           by: lines) > 0)
    }

    @Test func onAFallingCurveItStaysAboveAndOffTheSegmentArrivingAtThePoint() {
        let lines = [line(CGPoint(x: 300, y: 520), centre), line(centre, CGPoint(x: 900, y: 680))]
        let frame = KeyValuesPlacement.frame(anchor: point, size: size, in: window, clearOf: lines)
        expectClear(frame, of: lines)
        #expect(frame.maxY <= point.minY)
    }

    @Test func inAValleyItGoesBelowThePoint() {
        let lines = [line(CGPoint(x: 300, y: 450), centre), line(centre, CGPoint(x: 900, y: 450))]
        let frame = KeyValuesPlacement.frame(anchor: point, size: size, in: window, clearOf: lines)
        expectClear(frame, of: lines)
        #expect(frame.minY >= point.maxY)
    }

    @Test func aHandleLineIsKeptClearToo() {
        // A flat curve, and the point's leaving handle pulled up and right.
        let lines = [line(CGPoint(x: 0, y: centre.y), CGPoint(x: 1200, y: centre.y)),
                     line(centre, CGPoint(x: centre.x + 60, y: centre.y - 60))]
        let frame = KeyValuesPlacement.frame(anchor: point, size: size, in: window, clearOf: lines)
        expectClear(frame, of: lines)
    }

    @Test func whereNothingIsClearItTakesTheLeastCoveredSpotAndNeverTheKey() {
        // Lines every way out of the point.
        let lines = stride(from: 0.0, to: 360.0, by: 15.0).map { degrees -> [CGPoint] in
            let radians = degrees * .pi / 180
            return line(centre, CGPoint(x: centre.x + 500 * cos(radians), y: centre.y + 500 * sin(radians)))
        }
        let frame = KeyValuesPlacement.frame(anchor: point, size: size, in: window, clearOf: lines)
        #expect(!frame.intersects(point))
        #expect(window.contains(frame))
    }
}
