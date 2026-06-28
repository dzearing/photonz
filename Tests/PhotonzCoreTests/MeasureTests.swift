import CoreGraphics
import Foundation
import PhotonzCore
import Testing

private func measureContent(mode: MeasureMode = .free,
                            unit: MeasureUnit = .points,
                            decimals: Int = 0) -> MeasureContent {
    MeasureContent(mode: mode, unit: unit, decimals: decimals)
}

// MARK: - Distance & units

@Suite("Measure distance")
struct MeasureDistanceTests {

    @Test func freeDistanceIsEuclidean() {
        var m = measureContent(mode: .free)
        m.start = CGPoint(x: 0, y: 0)
        m.end = CGPoint(x: 30, y: 40)
        #expect(m.rawDistance == 50) // 3-4-5
    }

    @Test func horizontalDistanceIgnoresVerticalOffset() {
        var m = measureContent(mode: .horizontal)
        m.start = CGPoint(x: 10, y: 5)
        m.end = CGPoint(x: 130, y: 90) // 85px lower, but horizontal mode ignores dy
        #expect(m.rawDistance == 120)
    }

    @Test func verticalDistanceIgnoresHorizontalOffset() {
        var m = measureContent(mode: .vertical)
        m.start = CGPoint(x: 10, y: 5)
        m.end = CGPoint(x: 200, y: 105)
        #expect(m.rawDistance == 100)
    }

    @Test func distanceIsAbsoluteRegardlessOfDragDirection() {
        var m = measureContent(mode: .horizontal)
        m.start = CGPoint(x: 130, y: 0)
        m.end = CGPoint(x: 10, y: 0) // dragged right-to-left
        #expect(m.rawDistance == 120)
    }
}

@Suite("Measure units")
struct MeasureUnitsTests {

    @Test func pointsDivideByPixelScale() {
        var m = measureContent(mode: .horizontal, unit: .points)
        m.start = .zero
        m.end = CGPoint(x: 200, y: 0)
        #expect(m.displayDistance(pixelScale: 2) == 100) // 200 bitmap px @2x == 100 pt
    }

    @Test func pixelsAreRawRegardlessOfScale() {
        var m = measureContent(mode: .horizontal, unit: .pixels)
        m.start = .zero
        m.end = CGPoint(x: 200, y: 0)
        #expect(m.displayDistance(pixelScale: 2) == 200)
    }

    @Test func pixelScaleOfZeroIsTreatedAsOne() {
        var m = measureContent(mode: .horizontal, unit: .points)
        m.start = .zero
        m.end = CGPoint(x: 200, y: 0)
        #expect(m.displayDistance(pixelScale: 0) == 200)
    }

    @Test func labelFormatsValueWithUnitSuffixAndDecimals() {
        var m = measureContent(mode: .horizontal, unit: .points, decimals: 0)
        m.start = .zero
        m.end = CGPoint(x: 201, y: 0)
        #expect(m.label(pixelScale: 2) == "100 pt") // 100.5 rounds to 100 at 0 decimals (banker's-free %f)

        var p = measureContent(mode: .horizontal, unit: .pixels, decimals: 1)
        p.start = .zero
        p.end = CGPoint(x: 201, y: 0)
        #expect(p.label(pixelScale: 2) == "201.0 px")
    }
}

// MARK: - Witness / dimension geometry

@Suite("Measure geometry")
struct MeasureGeometryTests {

    @Test func freeGeometryIsTheBareSegmentNoWitnessLines() {
        let g = MeasureContent.geometry(mode: .free,
                                        start: CGPoint(x: 0, y: 0),
                                        end: CGPoint(x: 40, y: 30))
        #expect(g.dimension == MeasureSegment(CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 30)))
        #expect(g.extensions.isEmpty)
        #expect(g.labelAnchor == CGPoint(x: 20, y: 15))
    }

    @Test func horizontalGeometryLevelsTheDimensionLineAndDropsAWitnessFromTheOffsetEnd() {
        // start is 20px above the dimension line (which sits at end.y); a witness
        // line connects the start reference down to the line.
        let g = MeasureContent.geometry(mode: .horizontal,
                                        start: CGPoint(x: 10, y: 0),
                                        end: CGPoint(x: 110, y: 20))
        #expect(g.dimension == MeasureSegment(CGPoint(x: 10, y: 20), CGPoint(x: 110, y: 20)))
        #expect(g.extensions == [MeasureSegment(CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 20))])
        #expect(g.labelAnchor == CGPoint(x: 60, y: 20))
    }

    @Test func horizontalGeometryWithAlignedPointsHasNoWitnessLines() {
        let g = MeasureContent.geometry(mode: .horizontal,
                                        start: CGPoint(x: 10, y: 50),
                                        end: CGPoint(x: 110, y: 50))
        #expect(g.dimension == MeasureSegment(CGPoint(x: 10, y: 50), CGPoint(x: 110, y: 50)))
        #expect(g.extensions.isEmpty)
    }

    @Test func verticalGeometryLevelsTheDimensionLineOntoTheEndColumn() {
        let g = MeasureContent.geometry(mode: .vertical,
                                        start: CGPoint(x: 0, y: 10),
                                        end: CGPoint(x: 30, y: 110))
        #expect(g.dimension == MeasureSegment(CGPoint(x: 30, y: 10), CGPoint(x: 30, y: 110)))
        #expect(g.extensions == [MeasureSegment(CGPoint(x: 0, y: 10), CGPoint(x: 30, y: 10))])
        #expect(g.labelAnchor == CGPoint(x: 30, y: 60))
    }
}

// MARK: - Builder: frame & local coords & remap on resize

@Suite("MeasureBuilder")
struct MeasureBuilderTests {

    @Test func layerFramePadsTheBoundingBoxAndStoresLocalEndpoints() {
        // showLabel off isolates the geometric frame from the label reservation.
        var m = measureContent(mode: .free)
        m.showLabel = false
        let layer = MeasureBuilder.layer(content: m,
                                         from: CGPoint(x: 100, y: 100),
                                         to: CGPoint(x: 200, y: 160))
        guard let measure = layer.measure else {
            Issue.record("expected measure content")
            return
        }
        let pad = m.renderPadding
        // Frame is the bbox of the two points inset by render padding.
        #expect(layer.frame.minX == 100 - pad)
        #expect(layer.frame.minY == 100 - pad)
        #expect(layer.frame.width == 100 + 2 * pad)
        #expect(layer.frame.height == 60 + 2 * pad)
        // Endpoints become layer-local.
        #expect(measure.start == CGPoint(x: pad, y: pad))
        #expect(measure.end == CGPoint(x: 100 + pad, y: 60 + pad))
    }

    @Test func labelReservationGrowsTheFrameForAShortMeasure() {
        // A tiny span whose bounding box is far narrower than its label plate:
        // the frame must widen to contain the centered label.
        let labelled = MeasureBuilder.layer(content: measureContent(mode: .horizontal),
                                            from: CGPoint(x: 100, y: 100), to: CGPoint(x: 110, y: 100))
        guard let m = labelled.measure else { Issue.record("expected measure"); return }
        #expect(labelled.frame.width >= m.estimatedLabelSize.width)

        var noLabelContent = measureContent(mode: .horizontal)
        noLabelContent.showLabel = false
        let bare = MeasureBuilder.layer(content: noLabelContent,
                                        from: CGPoint(x: 100, y: 100), to: CGPoint(x: 110, y: 100))
        #expect(bare.frame.width < labelled.frame.width)
    }

    @Test func updatingKeepsIdentityAndStyleButRebuildsLikeAFreshDrag() {
        var layer = MeasureBuilder.layer(content: measureContent(mode: .horizontal),
                                         from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        layer.name = "Gap A"
        layer.style.opacity = 0.5
        let moved = MeasureBuilder.updating(layer,
                                            start: CGPoint(x: 10, y: 10),
                                            end: CGPoint(x: 90, y: 10))
        let fresh = MeasureBuilder.layer(content: measureContent(mode: .horizontal),
                                         from: CGPoint(x: 10, y: 10), to: CGPoint(x: 90, y: 10))
        #expect(moved.id == layer.id)
        #expect(moved.name == "Gap A")
        #expect(moved.style.opacity == 0.5)
        #expect(moved.frame == fresh.frame)
        #expect(moved.measure?.start == fresh.measure?.start)
        #expect(moved.measure?.end == fresh.measure?.end)
        #expect(moved.measure?.mode == .horizontal) // mode survives
    }

    @Test func resizeRemapsEndpointsProportionallyIntoTheNewFrame() {
        let layer = MeasureBuilder.layer(content: measureContent(mode: .free),
                                         from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 100))
        let doubled = CGRect(x: layer.frame.minX, y: layer.frame.minY,
                             width: layer.frame.width * 2, height: layer.frame.height * 2)
        let resized = MeasureBuilder.resized(layer, to: doubled)
        // The measured span doubles with the frame.
        #expect((resized.measure?.rawDistance ?? 0).rounded() == 283) // 200*sqrt(2)
    }

    @Test func restyleAnchorsEndpointsInDocumentSpaceWhileChangingStyle() {
        let layer = MeasureBuilder.layer(content: measureContent(mode: .free),
                                         from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        let startDoc = layer.measureEndpoint(.start)
        let endDoc = layer.measureEndpoint(.end)
        let restyled = MeasureBuilder.restyled(layer, colorHex: "#00FF00", showLabel: false)
        #expect(restyled.measure?.colorHex == "#00FF00")
        #expect(restyled.measure?.showLabel == false)
        #expect(restyled.measureEndpoint(.start) == startDoc)
        #expect(restyled.measureEndpoint(.end) == endDoc)
    }
}

// MARK: - Document pixelScale

@Suite("Document pixelScale")
struct DocumentPixelScaleTests {

    @Test func defaultsToOne() {
        let doc = PhotonzDocument(canvasSize: CGSize(width: 10, height: 10))
        #expect(doc.pixelScale == 1)
    }

    @Test func survivesCodableRoundTrip() throws {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 10, height: 10))
        doc.pixelScale = 2
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.pixelScale == 2)
    }

    @Test func legacyPayloadWithoutPixelScaleDecodesToOne() throws {
        // Older documents predate pixelScale; strip the key and confirm decoding
        // still succeeds (back-compat), defaulting to 1.
        var doc = PhotonzDocument(canvasSize: CGSize(width: 10, height: 10))
        doc.pixelScale = 2
        let encoded = try JSONEncoder().encode(doc)
        var object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "pixelScale")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: stripped)
        #expect(back.pixelScale == 1)
    }
}
