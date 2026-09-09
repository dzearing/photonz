import CoreGraphics
import Foundation
import PhotonzCore
import Testing

@Suite("Annotation fill color")
struct AnnotationFillTests {

    @Test func fillRoundTripsThroughCodable() throws {
        var content = AnnotationContent(shape: .rectangle, fillColorHex: "#34C759")
        content.end = CGPoint(x: 40, y: 30)
        let data = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode(AnnotationContent.self, from: data)
        #expect(decoded == content)
        #expect(decoded.fillColorHex == "#34C759")
    }

    @Test func legacyPayloadsDecodeWithNoFill() throws {
        // Pre-fill documents omit the key entirely.
        let legacy = AnnotationContent(shape: .ellipse)
        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(legacy)) as? [String: Any] ?? [:]
        json.removeValue(forKey: "fillColorHex")
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(AnnotationContent.self, from: data)
        #expect(decoded.fillColorHex == nil)
    }

    @Test func restyledSetsClearsAndKeepsFill() {
        let layer = AnnotationBuilder.layer(
            content: AnnotationContent(shape: .rectangle),
            from: .zero, to: CGPoint(x: 100, y: 80))

        let filled = AnnotationBuilder.restyled(layer, fillColorHex: "#007AFF")
        #expect(filled.annotation?.fillColorHex == "#007AFF")

        // Unrelated restyles keep the fill.
        let recolored = AnnotationBuilder.restyled(filled, colorHex: "#000000")
        #expect(recolored.annotation?.fillColorHex == "#007AFF")

        // Explicit nil-inside clears it.
        let cleared = AnnotationBuilder.restyled(filled, fillColorHex: .some(nil))
        #expect(cleared.annotation?.fillColorHex == nil)
    }

    @Test func stylesRememberCornerRadiusAndSeedNewRectangles() throws {
        var styles = AnnotationStyles()
        #expect(!styles.cornerRadii(forShape: .rectangle).isRound, "sharp by default")

        styles.setCornerRadii(14, forShape: .rectangle)
        #expect(styles.content(for: .rectangle)?.cornerRadii == 14,
                "the next rectangle reuses the last-touched radius")

        let decoded = try JSONDecoder().decode(AnnotationStyles.self,
                                               from: JSONEncoder().encode(styles))
        #expect(decoded.cornerRadii(forShape: .rectangle) == 14)

        // ...and the four a card with a rounded top was given, so a segmented
        // control is three shapes in a row rather than twelve typed numbers.
        let top = CornerRadii(topLeft: 8, topRight: 8, bottomRight: 0, bottomLeft: 0)
        styles.setCornerRadii(top, forShape: .rectangle)
        #expect(styles.content(for: .rectangle)?.cornerRadii == top)
        let again = try JSONDecoder().decode(AnnotationStyles.self,
                                             from: JSONEncoder().encode(styles))
        #expect(again.cornerRadii(forShape: .rectangle) == top)
    }

    @Test func stylesRememberFillPerShapeAndSeedNewContent() throws {
        var styles = AnnotationStyles()
        // Rectangle/ellipse draw SOLID by default (fill = the shape color);
        // stroke-only shapes have no interior fill (17.13).
        #expect(styles.fillColorHex(forShape: .rectangle) == "#FF3B30", "boxes fill by default")
        #expect(styles.fillColorHex(forShape: .ellipse) == "#FF3B30")
        #expect(styles.fillColorHex(forShape: .arrow) == nil, "strokes have no fill")

        styles.setFillColorHex("#FFD60A", forShape: .rectangle)
        #expect(styles.content(for: .rectangle)?.fillColorHex == "#FFD60A")
        #expect(styles.content(for: .ellipse)?.fillColorHex == "#FF3B30", "fill is per-shape")

        // Clearing to nil (outline-only) works and it all survives Codable.
        styles.setFillColorHex(nil, forShape: .rectangle)
        let decoded = try JSONDecoder().decode(AnnotationStyles.self,
                                               from: JSONEncoder().encode(styles))
        #expect(decoded == styles)
        #expect(decoded.fillColorHex(forShape: .rectangle) == nil)
    }

    @Test func toolKeyedFillMirrorsShapeFill() {
        var styles = AnnotationStyles()
        #expect(styles.fillColorHex(for: .rectangle) == "#FF3B30")
        #expect(styles.fillColorHex(for: .arrow) == nil)
        styles.setFillColorHex("#00FF00", for: .rectangle)
        #expect(styles.fillColorHex(forShape: .rectangle) == "#00FF00")
        // Non-annotation tools no-op / read nil.
        #expect(styles.fillColorHex(for: .select) == nil)
    }
}
