import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The tool you are holding remembers a PAINT, not a flat color — so a run of
/// shapes can all come out gradient without painting each one afterwards.
@Suite("The tool in your hand can be armed with a gradient")
struct ToolPaintTests {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private func ramp(_ hex: String, kind: Paint.Kind = .linear) -> Paint {
        var paint = Paint(hex: hex)
        paint.becoming(kind)
        return paint
    }

    // MARK: - Arming a tool

    @Test func aShapeStartsOutFlat() {
        let styles = AnnotationStyles()
        #expect(styles.paint(forShape: .rectangle).isGradient == false)
        #expect(styles.paint(forShape: .rectangle).hex == "#FF3B30")
    }

    @Test func armingTheOutlineCarriesIntoTheNextShape() {
        var styles = AnnotationStyles()
        styles.setPaint(ramp("#3366FF"), forShape: .rectangle)
        let content = styles.content(for: .rectangle)
        #expect(content?.paint.isGradient == true)
        #expect(content?.paint.kind == .linear)
        #expect(content?.colorHex == "#3366FF", "the flat color it stands for is still the one you picked")
    }

    @Test func armingTheFillCarriesIntoTheNextShape() {
        var styles = AnnotationStyles()
        styles.setFillPaint(ramp("#34C759", kind: .radial), forShape: .ellipse)
        let content = styles.content(for: .ellipse)
        #expect(content?.fill?.isGradient == true)
        #expect(content?.fill?.kind == .radial)
        #expect(content?.fillColorHex == "#34C759")
    }

    @Test func armingOneShapesFillNeverArmsAnothers() {
        var styles = AnnotationStyles()
        styles.setFillPaint(ramp("#34C759"), forShape: .ellipse)
        #expect(styles.fillPaint(forShape: .ellipse)?.isGradient == true)
        #expect(styles.fillPaint(forShape: .rectangle)?.isGradient == false)
    }

    @Test func armingOneShapeLeavesTheOthersFlat() {
        var styles = AnnotationStyles()
        styles.setPaint(ramp("#3366FF"), forShape: .arrow)
        #expect(styles.paint(forShape: .arrow).isGradient)
        for shape in [AnnotationShape.line, .rectangle, .ellipse, .highlight] {
            #expect(styles.paint(forShape: shape).isGradient == false)
        }
    }

    // MARK: - Reaching it by the tool you are holding

    @Test func theToolKeyedWayInFindsTheSameGradient() {
        var styles = AnnotationStyles()
        styles.setPaint(ramp("#AF52DE"), for: .ellipse)
        #expect(styles.paint(for: .ellipse)?.isGradient == true)
        #expect(styles.paint(for: .ellipse)?.hex == "#AF52DE")
        styles.setFillPaint(ramp("#FF9500"), for: .ellipse)
        #expect(styles.fillPaint(for: .ellipse)?.isGradient == true)
    }

    @Test func aToolThatDrawsNothingIsUntouched() {
        var styles = AnnotationStyles()
        styles.setPaint(ramp("#3366FF"), for: .select)
        styles.setFillPaint(ramp("#3366FF"), for: .crop)
        #expect(styles == AnnotationStyles())
        #expect(styles.paint(for: .select) == nil)
        #expect(styles.fillPaint(for: .text) == nil)
    }

    @Test func clearingTheFillStillMeansNoInterior() {
        var styles = AnnotationStyles()
        styles.setFillPaint(nil, forShape: .rectangle)
        #expect(styles.fillPaint(forShape: .rectangle) == nil)
        #expect(styles.content(for: .rectangle)?.fill == nil)
    }

    // MARK: - Picking a flat color after a gradient

    @Test func pickingAFlatColorPutsTheToolBackToFlat() {
        var styles = AnnotationStyles()
        styles.setPaint(ramp("#3366FF"), forShape: .rectangle)
        styles.setColorHex("#FFD60A", forShape: .rectangle)
        #expect(styles.paint(forShape: .rectangle).isGradient == false)
        #expect(styles.colorHex(forShape: .rectangle) == "#FFD60A")

        styles.setFillPaint(ramp("#3366FF"), forShape: .rectangle)
        styles.setFillColorHex("#000000", forShape: .rectangle)
        #expect(styles.fillPaint(forShape: .rectangle)?.isGradient == false)
        #expect(styles.fillColorHex(forShape: .rectangle) == "#000000")
    }

    // MARK: - Between launches

    @Test func aGradientToolSurvivesALaunch() throws {
        var styles = AnnotationStyles()
        styles.setPaint(ramp("#3366FF", kind: .angular), forShape: .line)
        styles.setFillPaint(ramp("#34C759", kind: .radial), forShape: .rectangle)
        let reopened = try decoder.decode(AnnotationStyles.self, from: encoder.encode(styles))
        #expect(reopened == styles)
        #expect(reopened.paint(forShape: .line).kind == .angular)
        #expect(reopened.paint(forShape: .line).stops.count == 2)
        #expect(reopened.fillPaint(forShape: .rectangle)?.kind == .radial)
    }

    /// Prefs that have never held a gradient keep writing the bare hex strings
    /// they always wrote, so a build without gradients reads them back.
    @Test func flatToolsStillWriteTheBareHexTheyAlwaysDid() throws {
        let data = try encoder.encode(AnnotationStyles())
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let shapes = try #require(json["shapes"] as? [String: Any])
        let rectangle = try #require(shapes["rectangle"] as? [String: Any])
        #expect(rectangle["colorHex"] as? String == "#FF3B30")
        #expect(rectangle["fillColorHex"] as? String == "#FF3B30")
    }

    /// And prefs written before gradients existed open unchanged.
    @Test func prefsWrittenBeforeGradientsOpenUnchanged() throws {
        let legacy = """
        {"shapes":{"rectangle":{"colorHex":"#112233","strokeWidth":6,"arrowheadScale":1,\
        "fillColorHex":"#445566","cornerRadius":4,"captionFontSize":20}}}
        """
        let styles = try decoder.decode(AnnotationStyles.self, from: Data(legacy.utf8))
        #expect(styles.paint(forShape: .rectangle) == Paint(hex: "#112233"))
        #expect(styles.fillPaint(forShape: .rectangle) == Paint(hex: "#445566"))
        #expect(styles.colorHex(forShape: .rectangle) == "#112233")
    }

    // MARK: - Restyling a shape already on the canvas

    @Test func restylingWithAPaintReachesTheShape() {
        let layer = Layer(name: "Rectangle",
                          content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 colorHex: "#FF3B30",
                                                                 start: CGPoint(x: 0, y: 0),
                                                                 end: CGPoint(x: 100, y: 60),
                                                                 fillColorHex: "#FF3B30")),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 60))
        let outlined = AnnotationBuilder.restyled(layer, paint: ramp("#3366FF"))
        #expect(outlined.annotation?.paint.isGradient == true)
        #expect(outlined.annotation?.fill?.isGradient == false, "the fill is left where it was")

        let filled = AnnotationBuilder.restyled(outlined, fill: .some(ramp("#34C759", kind: .radial)))
        #expect(filled.annotation?.fill?.kind == .radial)
        #expect(filled.annotation?.paint.isGradient == true, "and the outline is left where it was")

        let cleared = AnnotationBuilder.restyled(filled, fill: .some(nil))
        #expect(cleared.annotation?.fill == nil)
    }
}
