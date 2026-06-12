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

    // One color for stroke shapes, a separate one for highlight: picking blue
    // for arrows must not turn highlights blue (and vice versa).
    @Test func strokeColorIsSharedAcrossStrokeTools() {
        var styles = AnnotationStyles()
        styles.setColorHex("#007AFF", for: .arrow)
        for tool in [Tool.arrow, .line, .rectangle, .ellipse] {
            #expect(styles.colorHex(for: tool) == "#007AFF")
            #expect(styles.content(for: tool)?.colorHex == "#007AFF")
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

    @Test func strokeWidthFlowsIntoStrokeContent() {
        var styles = AnnotationStyles()
        styles.strokeWidth = 8
        for tool in [Tool.arrow, .line, .rectangle, .ellipse] {
            #expect(styles.content(for: tool)?.strokeWidth == 8)
        }
    }

    // Highlight is a filled box — stroke width must not apply to it.
    @Test func strokeWidthDoesNotApplyToHighlight() {
        var styles = AnnotationStyles()
        styles.strokeWidth = 12
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

    // The UI builds itself from these; they must be valid and selectable.
    @Test func palettesAreValid() {
        #expect(AnnotationStyles.swatches.count >= 6)
        #expect(Set(AnnotationStyles.swatches).count == AnnotationStyles.swatches.count)
        for hex in AnnotationStyles.swatches {
            #expect(RGBA(hex: hex) != nil)
        }
        // Both defaults must be reachable from the swatch row.
        #expect(AnnotationStyles.swatches.contains(AnnotationStyles().strokeColorHex))
        #expect(AnnotationStyles.swatches.contains(AnnotationStyles().highlightColorHex))

        #expect(AnnotationStyles.strokeWidths.count >= 3)
        #expect(AnnotationStyles.strokeWidths == AnnotationStyles.strokeWidths.sorted())
        #expect(AnnotationStyles.strokeWidths.allSatisfy { $0 > 0 })
        #expect(AnnotationStyles.strokeWidths.contains(AnnotationStyles().strokeWidth))
    }

    // Settings survive app restarts via Codable round-trip.
    @Test func codableRoundTrip() throws {
        var styles = AnnotationStyles()
        styles.setColorHex("#AF52DE", for: .line)
        styles.setColorHex("#FF9500", for: .highlight)
        styles.strokeWidth = 6
        let data = try JSONEncoder().encode(styles)
        let decoded = try JSONDecoder().decode(AnnotationStyles.self, from: data)
        #expect(decoded == styles)
    }
}
