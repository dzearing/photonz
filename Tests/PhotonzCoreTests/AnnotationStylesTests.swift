import CoreGraphics
import Foundation
import PhotonzCore
import Testing

@Suite("AnnotationStyles")
struct AnnotationStylesTests {

    // Defaults must match the 3.6 smart defaults: red strokes, yellow highlight.
    @Test func defaultsMatchSmartDefaults() {
        let styles = AnnotationStyles()
        for tool in Tool.allCases {
            #expect(styles.content(for: tool) == tool.defaultAnnotation)
        }
    }

    @Test func nonAnnotationToolsHaveNoContentOrColor() {
        let styles = AnnotationStyles()
        for tool in [Tool.select, .crop, .text] {
            #expect(styles.content(for: tool) == nil)
            #expect(styles.colorHex(for: tool) == nil)
        }
    }

    // Per-type colors: setting a color for one shape must NOT change the others
    // (the user wants each object type to remember its own settings).
    @Test func colorIsPerShape() {
        var styles = AnnotationStyles()
        styles.setColorHex("#007AFF", for: .arrow)
        #expect(styles.colorHex(for: .arrow) == "#007AFF")
        #expect(styles.content(for: .arrow)?.colorHex == "#007AFF")
        // Other shapes are untouched — still the red default.
        for tool in [Tool.line, .rectangle, .ellipse] {
            #expect(styles.colorHex(for: tool) == "#FF3B30")
        }
        #expect(styles.colorHex(for: .highlight) == "#FFD60A")
    }

    @Test func highlightColorIsIndependent() {
        var styles = AnnotationStyles()
        styles.setColorHex("#34C759", for: .highlight)
        #expect(styles.colorHex(for: .highlight) == "#34C759")
        #expect(styles.content(for: .highlight)?.colorHex == "#34C759")
        #expect(styles.colorHex(for: .arrow) == "#FF3B30")
    }

    @Test func settingColorForNonAnnotationToolIsIgnored() {
        var styles = AnnotationStyles()
        styles.setColorHex("#007AFF", for: .select)
        #expect(styles == AnnotationStyles())
    }

    // Per-type stroke width: setting one shape's width leaves the others at the
    // default.
    @Test func strokeWidthIsPerShape() {
        var styles = AnnotationStyles()
        styles.setStrokeWidth(8, forShape: .arrow)
        #expect(styles.content(for: .arrow)?.strokeWidth == 8)
        #expect(styles.strokeWidth(forShape: .arrow) == 8)
        for tool in [Tool.line, .rectangle, .ellipse] {
            #expect(styles.content(for: tool)?.strokeWidth == AnnotationContent.defaultStrokeWidth)
        }
    }

    // Per-type arrowhead scale (arrow-only knob).
    @Test func arrowheadScaleIsPerShapeAndDefaultsToOne() {
        var styles = AnnotationStyles()
        #expect(styles.arrowheadScale(forShape: .arrow) == 1.0)
        styles.setArrowheadScale(2.5, forShape: .arrow)
        #expect(styles.arrowheadScale(forShape: .arrow) == 2.5)
        #expect(styles.content(for: .arrow)?.arrowheadScale == 2.5)
    }

    // Highlight is a filled box — stroke width must not apply to it.
    @Test func strokeWidthDoesNotApplyToHighlight() {
        var styles = AnnotationStyles()
        styles.setStrokeWidth(12, forShape: .highlight)
        #expect(Tool.highlight.usesStrokeWidth == false)
        #expect(styles.content(for: .highlight)?.strokeWidth
            == Tool.highlight.defaultAnnotation?.strokeWidth)
        for tool in [Tool.arrow, .line, .rectangle, .ellipse] {
            #expect(tool.usesStrokeWidth)
        }
        for tool in [Tool.select, .crop, .text] {
            #expect(tool.usesStrokeWidth == false)
        }
    }

    // Shape routing and tool routing land in the same per-shape bucket.
    @Test func shapeRoutingMatchesToolRouting() {
        var styles = AnnotationStyles()
        styles.setColorHex("#007AFF", forShape: .arrow)
        #expect(styles.colorHex(for: .arrow) == "#007AFF")
        #expect(styles.colorHex(forShape: .arrow) == "#007AFF")
        // A different shape keeps its own bucket.
        #expect(styles.colorHex(forShape: .line) == "#FF3B30")
        styles.setColorHex("#34C759", forShape: .highlight)
        #expect(styles.colorHex(forShape: .highlight) == "#34C759")
        #expect(styles.colorHex(forShape: .rectangle) == "#FF3B30")
    }

    // The UI builds itself from these; they must be valid and selectable.
    @Test func palettesAreValid() {
        #expect(AnnotationStyles.swatches.count >= 6)
        #expect(Set(AnnotationStyles.swatches).count == AnnotationStyles.swatches.count)
        for hex in AnnotationStyles.swatches {
            #expect(RGBA(hex: hex) != nil)
        }
        // Both defaults must be reachable from the swatch row.
        #expect(AnnotationStyles.swatches.contains(AnnotationStyles().colorHex(forShape: .arrow)))
        #expect(AnnotationStyles.swatches.contains(AnnotationStyles().colorHex(forShape: .highlight)))

        #expect(AnnotationStyles.strokeWidths.count >= 3)
        #expect(AnnotationStyles.strokeWidths == AnnotationStyles.strokeWidths.sorted())
        #expect(AnnotationStyles.strokeWidths.allSatisfy { $0 > 0 })
        #expect(AnnotationStyles.strokeWidths.contains(AnnotationStyles().strokeWidth(forShape: .arrow)))
    }

    // Per-type effects (shadow/opacity/…) are remembered per shape, so a new
    // object of that type inherits the last one's look.
    @Test func layerStyleIsPerShape() {
        var styles = AnnotationStyles()
        #expect(styles.layerStyle(forShape: .arrow).shadow == nil)
        var arrowStyle = LayerStyle()
        arrowStyle.shadow = ShadowStyle()
        styles.setLayerStyle(arrowStyle, forShape: .arrow)
        #expect(styles.layerStyle(forShape: .arrow).shadow != nil)
        // Other shapes keep their (shadowless) default.
        #expect(styles.layerStyle(forShape: .line).shadow == nil)
    }

    // Per-type settings survive app restarts via Codable round-trip.
    @Test func codableRoundTrip() throws {
        var styles = AnnotationStyles()
        styles.setColorHex("#AF52DE", for: .line)
        styles.setColorHex("#FF9500", for: .highlight)
        styles.setStrokeWidth(6, forShape: .line)
        styles.setStrokeWidth(10, forShape: .arrow)
        styles.setArrowheadScale(1.8, forShape: .arrow)
        var arrowStyle = LayerStyle()
        arrowStyle.shadow = ShadowStyle(radius: 8, offset: CGSize(width: 2, height: 3), spread: 4)
        styles.setLayerStyle(arrowStyle, forShape: .arrow)
        let data = try JSONEncoder().encode(styles)
        let decoded = try JSONDecoder().decode(AnnotationStyles.self, from: data)
        #expect(decoded == styles)
    }

    // Old single-bucket prefs migrate: the shared stroke color/width seed every
    // stroke shape; the highlight color seeds highlight.
    @Test func migratesLegacySharedFormat() throws {
        let legacy = """
        {"strokeColorHex":"#007AFF","highlightColorHex":"#FF9500","strokeWidth":8,"arrowheadScale":2.0}
        """.data(using: .utf8)!
        let styles = try JSONDecoder().decode(AnnotationStyles.self, from: legacy)
        for shape in [AnnotationShape.arrow, .line, .rectangle, .ellipse] {
            #expect(styles.colorHex(forShape: shape) == "#007AFF")
            #expect(styles.strokeWidth(forShape: shape) == 8)
        }
        #expect(styles.colorHex(forShape: .highlight) == "#FF9500")
        #expect(styles.arrowheadScale(forShape: .arrow) == 2.0)
    }
}
