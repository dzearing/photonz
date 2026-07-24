import CoreGraphics
import Foundation
import PhotonzCore
import Testing

private func measureContent(mode: MeasureMode = .horizontal,
                            unit: MeasureUnit = .pixels,
                            decimals: Int = 0) -> MeasureContent {
    MeasureContent(mode: mode, unit: unit, decimals: decimals)
}

// MARK: - Distance & units

@Suite("Measure distance")
struct MeasureDistanceTests {

    @Test func horizontalDistanceIgnoresVerticalOffset() {
        var m = measureContent(mode: .horizontal)
        m.start = CGPoint(x: 10, y: 5)
        m.end = CGPoint(x: 130, y: 90) // dy is ignored in horizontal mode
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

    @Test func dominantAxisPicksTheLongerSpan() {
        #expect(MeasureContent.dominantAxis(from: .zero, to: CGPoint(x: 40, y: 30)) == .horizontal)
        #expect(MeasureContent.dominantAxis(from: .zero, to: CGPoint(x: 30, y: 40)) == .vertical)
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
        #expect(m.label(pixelScale: 2) == "100 px") // 201 @2× → 100.5 → 100 at 0 decimals

        var p = measureContent(mode: .horizontal, unit: .pixels, decimals: 1)
        p.start = .zero
        p.end = CGPoint(x: 201, y: 0)
        #expect(p.label(pixelScale: 2) == "201.0 px")
    }
}

// MARK: - Caliper geometry (feet + head + label anchor)

@Suite("Caliper geometry")
struct CaliperGeometryTests {

    @Test func horizontalPlacesHeadAboveTheLeveledFeetWithAnchorAtHeadMidpoint() {
        let g = MeasureContent.caliperGeometry(mode: .horizontal,
                                               start: CGPoint(x: 10, y: 50),
                                               end: CGPoint(x: 110, y: 50), headOffset: 28)
        #expect(g.footA == CGPoint(x: 10, y: 50))
        #expect(g.footB == CGPoint(x: 110, y: 50))
        #expect(g.headA == CGPoint(x: 10, y: 78))
        #expect(g.headB == CGPoint(x: 110, y: 78))
        #expect(g.labelAnchor == CGPoint(x: 60, y: 78))
        #expect(g.path == [g.footA, g.headA, g.headB, g.footB])
    }

    @Test func feetAreLeveledOntoTheStartCrossAxis() {
        // end.y differs from start.y — the measuring line must stay horizontal.
        let g = MeasureContent.caliperGeometry(mode: .horizontal,
                                               start: CGPoint(x: 10, y: 50),
                                               end: CGPoint(x: 110, y: 90), headOffset: 28)
        #expect(g.footA.y == 50)
        #expect(g.footB.y == 50) // leveled, not 90
    }

    @Test func verticalPlacesHeadToTheSideWithAnchorCentered() {
        let g = MeasureContent.caliperGeometry(mode: .vertical,
                                               start: CGPoint(x: 50, y: 10),
                                               end: CGPoint(x: 50, y: 110), headOffset: 28)
        #expect(g.footA == CGPoint(x: 50, y: 10))
        #expect(g.footB == CGPoint(x: 50, y: 110))
        #expect(g.headA == CGPoint(x: 78, y: 10))
        #expect(g.headB == CGPoint(x: 78, y: 110))
        #expect(g.labelAnchor == CGPoint(x: 78, y: 60))
    }

    @Test func negativeHeadOffsetPutsTheHeadOnTheOppositeSide() {
        let up = MeasureContent.caliperGeometry(mode: .horizontal, start: .zero,
                                                end: CGPoint(x: 100, y: 0), headOffset: -28)
        #expect(up.headA.y == -28) // head above the feet line
        #expect(up.labelAnchor.y == -28)
    }

    @Test func labelAnchorMatchesGeometry() {
        var m = MeasureContent(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 80, y: 0),
                               headOffset: 20, mode: .horizontal)
        #expect(m.labelAnchor == CGPoint(x: 40, y: 20))
        #expect(m.headHandle == m.labelAnchor)
        m.headOffset = -20
        #expect(m.labelAnchor == CGPoint(x: 40, y: -20))
    }
}

// MARK: - Migration from the legacy measure model

@Suite("Measure migration")
struct MeasureMigrationTests {

    /// Builds legacy JSON by encoding a real caliper (so CGPoint uses the exact
    /// encoder format), then stripping `headOffset` and stamping the old
    /// `mode`/`form` keys — exactly what a pre-caliper document looks like.
    private func decodeLegacy(start: CGPoint, end: CGPoint, mode: String, form: String) throws -> MeasureContent {
        let seed = MeasureContent(start: start, end: end, headOffset: 0, mode: .horizontal)
        let encoded = try JSONEncoder().encode(seed)
        var obj = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        obj.removeValue(forKey: "headOffset")
        obj["mode"] = mode
        obj["form"] = form
        obj["capStyle"] = "ticks"
        let data = try JSONSerialization.data(withJSONObject: obj)
        return try JSONDecoder().decode(MeasureContent.self, from: data)
    }

    @Test func legacyHorizontalBracketBecomesFeetPlusSignedOffset() throws {
        // Old bracket: start = head-side corner (0,0), end = opposite foot corner.
        let m = try decodeLegacy(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 200, y: 80),
                                 mode: "horizontal", form: "bracket")
        #expect(m.mode == .horizontal)
        #expect(m.start == CGPoint(x: 0, y: 80))
        #expect(m.end == CGPoint(x: 200, y: 80))
        #expect(m.headOffset == -80) // head sat above the feet
        #expect(m.rawDistance == 200)
    }

    @Test func legacyVerticalBracketBecomesFeetPlusSignedOffset() throws {
        let m = try decodeLegacy(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 80, y: 200),
                                 mode: "vertical", form: "bracket")
        #expect(m.mode == .vertical)
        #expect(m.start == CGPoint(x: 80, y: 0))
        #expect(m.end == CGPoint(x: 80, y: 200))
        #expect(m.headOffset == -80)
        #expect(m.rawDistance == 200)
    }

    @Test func legacyFreeLineBecomesADominantAxisCaliper() throws {
        let m = try decodeLegacy(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 40, y: 30),
                                 mode: "free", form: "line")
        #expect(m.mode == .horizontal) // dominant of (40, 30)
        #expect(m.start == CGPoint(x: 0, y: 0))
        #expect(m.end == CGPoint(x: 40, y: 30))
        #expect(m.headOffset == MeasureContent.defaultHeadOffset)
    }

    @Test func labelScaleDefaultsToOneAndDrivesTheEffectiveSize() {
        var m = measureContent(mode: .horizontal)
        #expect(m.labelScale == 1)
        #expect(m.labelPointSize == MeasureContent.labelFontSize)
        let base = m.estimatedLabelSize
        m.labelScale = 2
        #expect(m.labelPointSize == MeasureContent.labelFontSize * 2)
        #expect(m.estimatedLabelSize.height > base.height) // bigger label → bigger chip
    }

    @Test func labelScaleSurvivesEncodeAndRestyle() throws {
        var m = MeasureContent(mode: .horizontal, labelScale: 1.5)
        m.start = .zero; m.end = CGPoint(x: 100, y: 0)
        let back = try JSONDecoder().decode(MeasureContent.self, from: JSONEncoder().encode(m))
        #expect(back.labelScale == 1.5)

        let layer = MeasureBuilder.layer(content: measureContent(mode: .horizontal),
                                         from: .zero, to: CGPoint(x: 100, y: 0))
        let restyled = MeasureBuilder.restyled(layer, labelScale: 2.5)
        #expect(restyled.measure?.labelScale == 2.5)
    }

    @Test func payloadWithoutLabelScaleDecodesToOne() throws {
        // A caliper saved before the label-size slider omits `labelScale`.
        var m = MeasureContent(mode: .horizontal, labelScale: 3)
        m.start = .zero; m.end = CGPoint(x: 100, y: 0)
        var obj = try #require(try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(m)) as? [String: Any])
        obj.removeValue(forKey: "labelScale")
        let back = try JSONDecoder().decode(MeasureContent.self,
                                            from: JSONSerialization.data(withJSONObject: obj))
        #expect(back.labelScale == 1)
    }

    @Test func newCaliperPayloadRoundTrips() throws {
        let original = MeasureContent(start: CGPoint(x: 5, y: 7), end: CGPoint(x: 105, y: 7),
                                      headOffset: -24, mode: .horizontal, strokeWidth: 2,
                                      colorHex: "#123456", showLabel: false, unit: .points,
                                      decimals: 1)
        let data = try JSONEncoder().encode(original)
        let back = try JSONDecoder().decode(MeasureContent.self, from: data)
        #expect(back == original)
    }
}

// MARK: - Builder: frame, local feet, updates

@Suite("MeasureBuilder")
struct MeasureBuilderTests {

    @Test func layerFramePadsTheBoundingBoxAndStoresLocalFeet() {
        var m = measureContent(mode: .horizontal)
        m.showLabel = false // isolate the geometric frame from label reservation
        m.headOffset = 28
        let layer = MeasureBuilder.layer(content: m,
                                         from: CGPoint(x: 100, y: 100),
                                         to: CGPoint(x: 200, y: 100))
        guard let measure = layer.measure else { Issue.record("expected measure"); return }
        let pad = m.renderPadding
        // bbox spans feet (y=100) and head (y=128); x from 100..200.
        #expect(layer.frame.minX == 100 - pad)
        #expect(layer.frame.minY == 100 - pad)
        #expect(layer.frame.width == 100 + 2 * pad)
        #expect(layer.frame.height == 28 + 2 * pad)
        #expect(measure.start == CGPoint(x: pad, y: pad))
        #expect(measure.end == CGPoint(x: 100 + pad, y: pad))
        #expect(measure.headOffset == 28)
    }

    @Test func labelReservationGrowsTheFrameForAShortMeasure() {
        let labelled = MeasureBuilder.layer(content: measureContent(mode: .horizontal),
                                            from: CGPoint(x: 100, y: 100), to: CGPoint(x: 110, y: 100))
        guard let m = labelled.measure else { Issue.record("expected measure"); return }
        #expect(labelled.frame.width >= m.estimatedLabelSize.width)

        var noLabel = measureContent(mode: .horizontal)
        noLabel.showLabel = false
        let bare = MeasureBuilder.layer(content: noLabel,
                                        from: CGPoint(x: 100, y: 100), to: CGPoint(x: 110, y: 100))
        #expect(bare.frame.width < labelled.frame.width)
    }

    @Test func updatingKeepsIdentityStyleAndHeadOffsetButRebuildsLikeAFreshDrag() {
        var content = measureContent(mode: .horizontal)
        content.headOffset = 30
        var layer = MeasureBuilder.layer(content: content, from: CGPoint(x: 0, y: 0),
                                         to: CGPoint(x: 100, y: 0))
        layer.name = "Gap A"
        layer.style.opacity = 0.5
        let moved = MeasureBuilder.updating(layer, start: CGPoint(x: 10, y: 10),
                                            end: CGPoint(x: 90, y: 10))
        #expect(moved.id == layer.id)
        #expect(moved.name == "Gap A")
        #expect(moved.style.opacity == 0.5)
        #expect(moved.measure?.headOffset == 30) // head offset survives an endpoint move
        #expect(moved.measure?.mode == .horizontal)
        #expect(moved.measure?.rawDistance == 80)
    }

    @Test func updatingWithHeadOffsetRepositionsTheHeadOnly() {
        let layer = MeasureBuilder.layer(content: measureContent(mode: .horizontal),
                                         from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        let start = layer.measureEndpoint(.start)!
        let end = layer.measureEndpoint(.end)!
        let deeper = MeasureBuilder.updating(layer, start: start, end: end, headOffset: 60)
        #expect(deeper.measure?.headOffset == 60)
        #expect(deeper.measureEndpoint(.start) == start) // feet unchanged in doc space
        #expect(deeper.measureEndpoint(.end) == end)
    }

    @Test func resizeScalesTheSpanAndHeadOffsetWithTheFrame() {
        let layer = MeasureBuilder.layer(content: measureContent(mode: .horizontal),
                                         from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0))
        let doubled = CGRect(x: layer.frame.minX, y: layer.frame.minY,
                             width: layer.frame.width * 2, height: layer.frame.height * 2)
        let resized = MeasureBuilder.resized(layer, to: doubled)
        #expect((resized.measure?.rawDistance ?? 0).rounded() == 200) // span doubles
        #expect((resized.measure?.headOffset ?? 0) > (layer.measure?.headOffset ?? 0)) // grows
    }

    @Test func caliperIsSelectableByClickingTheLabelChip() {
        // Feet at y=200 (x 100..200), head +28 below → chip centered at (150, 228).
        let layer = MeasureBuilder.layer(content: measureContent(mode: .horizontal),
                                         from: CGPoint(x: 100, y: 200), to: CGPoint(x: 200, y: 200))
        guard let m = layer.measure else { Issue.record("expected measure"); return }
        let anchorLocal = m.labelAnchor
        let chipDoc = CGPoint(x: layer.frame.minX + anchorLocal.x, y: layer.frame.minY + anchorLocal.y)
        // Clicking the chip background (not on a stroke) selects the caliper.
        #expect(layer.contains(canvasPoint: chipDoc, zoom: 1))
        // Far from the caliper and its chip: no hit.
        #expect(!layer.contains(canvasPoint: CGPoint(x: 150, y: 320), zoom: 1))
    }

    @Test func chipFootprintIsHittableOnlyWithTheLabelOn() {
        func layer(showLabel: Bool) -> Layer {
            var content = measureContent(mode: .horizontal)
            content.showLabel = showLabel
            return MeasureBuilder.layer(content: content,
                                        from: CGPoint(x: 100, y: 200), to: CGPoint(x: 200, y: 200))
        }
        let on = layer(showLabel: true)
        // A point off every stroke (14px past the head line) but inside the chip box.
        let anchor = on.measure!.labelAnchor
        let probe = CGPoint(x: on.frame.minX + anchor.x, y: on.frame.minY + anchor.y + 14)
        #expect(on.contains(canvasPoint: probe, zoom: 1), "the chip footprint is selectable when labelled")
        #expect(!layer(showLabel: false).contains(canvasPoint: probe, zoom: 1),
                "with no label there's no oversized chip box — only the strokes are hittable")
    }

    @Test func restyleAnchorsFeetInDocumentSpaceWhileChangingStyle() {
        let layer = MeasureBuilder.layer(content: measureContent(mode: .horizontal),
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
