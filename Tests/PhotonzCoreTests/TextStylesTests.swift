import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

@Suite("TextWeight & TextContent")
struct TextWeightTests {

    @Test func weightRoundTripsThroughCodable() throws {
        for weight in TextWeight.allCases {
            let content = TextContent(string: "Hi", weight: weight)
            let data = try JSONEncoder().encode(content)
            let decoded = try JSONDecoder().decode(TextContent.self, from: data)
            #expect(decoded == content)
        }
    }

    @Test func decodingLegacyContentWithoutWeightDefaultsToRegular() throws {
        // TextContent existed before `weight`; old payloads must still decode.
        let legacy = Data("""
        {"string":"Hi","fontName":"SF Pro","fontSize":24,"colorHex":"#FFFFFF"}
        """.utf8)
        let decoded = try JSONDecoder().decode(TextContent.self, from: legacy)
        #expect(decoded.weight == .regular)
        #expect(decoded.string == "Hi")
        #expect(decoded.fontSize == 24)
    }
}

@Suite("TextStyles")
struct TextStylesTests {

    @Test func defaultsMatchTextContentDefaults() {
        let styles = TextStyles()
        let content = styles.content()
        #expect(content == TextContent(string: ""))
    }

    @Test func contentCarriesStringAndStyle() {
        var styles = TextStyles()
        styles.fontName = "Helvetica Neue"
        styles.fontSize = 48
        styles.weight = .bold
        styles.colorHex = "#FF3B30"
        let content = styles.content(string: "Note")
        #expect(content.string == "Note")
        #expect(content.fontName == "Helvetica Neue")
        #expect(content.fontSize == 48)
        #expect(content.weight == .bold)
        #expect(content.colorHex == "#FF3B30")
    }

    @Test func adoptingContentPullsItsStyle() {
        // Re-editing an existing text layer seeds the picker with that layer's
        // style so the popover edits what the user sees.
        var styles = TextStyles()
        let content = TextContent(string: "old", fontName: "Georgia", fontSize: 64,
                                  colorHex: "#FFD60A", weight: .semibold)
        styles.adopt(content)
        #expect(styles.fontName == "Georgia")
        #expect(styles.fontSize == 64)
        #expect(styles.weight == .semibold)
        #expect(styles.colorHex == "#FFD60A")
    }

    @Test func pickerListsAreUsable() {
        #expect(!TextStyles.fonts.isEmpty)
        #expect(TextStyles.fontSizes.count >= 4)
        #expect(TextStyles.fontSizes == TextStyles.fontSizes.sorted())
        #expect(TextWeight.allCases.count >= 3)
        #expect(TextStyles.fonts.contains(TextStyles().fontName))
        #expect(TextStyles.fontSizes.contains(TextStyles().fontSize))
    }

    @Test func stylesRoundTripThroughCodable() throws {
        var styles = TextStyles()
        styles.fontSize = 96
        styles.weight = .medium
        let data = try JSONEncoder().encode(styles)
        let decoded = try JSONDecoder().decode(TextStyles.self, from: data)
        #expect(decoded == styles)
    }
}

@Suite("TextBuilder")
struct TextBuilderTests {

    @Test func layerFrameStartsAtClickPointWithNaturalSize() {
        let content = TextContent(string: "Hello")
        let layer = TextBuilder.layer(content: content, at: CGPoint(x: 40, y: 60),
                                      naturalSize: CGSize(width: 120, height: 30))
        #expect(layer.frame == CGRect(x: 40, y: 60, width: 120, height: 30))
        #expect(layer.name == "Text")
        guard case .text(let stored) = layer.content else {
            Issue.record("expected text content")
            return
        }
        #expect(stored == content)
    }

    @Test func degenerateNaturalSizeIsClampedToAPixel() {
        // An empty measurement must not produce an unrenderable zero-size frame.
        let layer = TextBuilder.layer(content: TextContent(string: ""),
                                      at: .zero, naturalSize: .zero)
        #expect(layer.frame.width >= 1)
        #expect(layer.frame.height >= 1)
    }
}

// 13.1: change a placed text element's font face/size/weight/color via the
// props panel — mirrors AnnotationBuilder.restyled. Frame is NOT touched here
// (the app re-measures via CoreText); identity and frame.origin survive.
@Suite("TextBuilder.restyled")
struct TextBuilderRestyledTests {

    private func textLayer(_ content: TextContent) -> Layer {
        TextBuilder.layer(content: content, at: CGPoint(x: 30, y: 50),
                          naturalSize: CGSize(width: 120, height: 40))
    }

    @Test func restyleChangesFontName() {
        let layer = textLayer(TextContent(string: "Hi", fontName: "SF Pro"))
        let out = TextBuilder.restyled(layer: layer, fontName: "Georgia")
        guard case .text(let c) = out.content else { Issue.record("expected text"); return }
        #expect(c.fontName == "Georgia")
        #expect(out.id == layer.id)
        #expect(out.frame.origin == layer.frame.origin)
    }

    @Test func restyleChangesFontSize() {
        let layer = textLayer(TextContent(string: "Hi", fontSize: 24))
        let out = TextBuilder.restyled(layer: layer, fontSize: 48)
        guard case .text(let c) = out.content else { Issue.record("expected text"); return }
        #expect(c.fontSize == 48)
        #expect(out.id == layer.id)
    }

    @Test func restyleChangesWeight() {
        let layer = textLayer(TextContent(string: "Hi", weight: .regular))
        let out = TextBuilder.restyled(layer: layer, weight: .bold)
        guard case .text(let c) = out.content else { Issue.record("expected text"); return }
        #expect(c.weight == .bold)
    }

    @Test func restyleOnlyAppliesProvidedParams() {
        let original = TextContent(string: "Hi", fontName: "Georgia", fontSize: 32,
                                   colorHex: "#FF3B30", weight: .semibold)
        let layer = textLayer(original)
        let out = TextBuilder.restyled(layer: layer, fontSize: 64)
        guard case .text(let c) = out.content else { Issue.record("expected text"); return }
        #expect(c.fontName == "Georgia")
        #expect(c.fontSize == 64)
        #expect(c.weight == .semibold)
        #expect(c.colorHex == "#FF3B30")
    }

    @Test func colorChangeRefreshesAutoContrastShadow() {
        // White text → dark shadow. Recolor to black → shadow must flip light.
        let layer = textLayer(TextContent(string: "Hi", colorHex: "#FFFFFF"))
        #expect(layer.style.shadow?.colorHex == "#000000")
        let out = TextBuilder.restyled(layer: layer, colorHex: "#000000")
        guard case .text(let c) = out.content else { Issue.record("expected text"); return }
        #expect(c.colorHex == "#000000")
        #expect(out.style.shadow == TextBuilder.autoContrastShadow(forColorHex: "#000000"))
        #expect(out.style.shadow?.colorHex == "#FFFFFF")
    }

    @Test func noColorChangeLeavesShadowUntouched() {
        let layer0 = textLayer(TextContent(string: "Hi", colorHex: "#FFFFFF"))
        // Give the layer a custom (non-auto) shadow to prove it's preserved.
        var layer = layer0
        var custom = ShadowStyle()
        custom.radius = 9
        custom.colorHex = "#123456"
        layer.style.shadow = custom
        let out = TextBuilder.restyled(layer: layer, fontSize: 48)
        #expect(out.style.shadow == custom)
    }

    @Test func nonTextLayerPassesThroughUnchanged() {
        let annotation = Layer(name: "Box",
                               content: .annotation(AnnotationContent(shape: .rectangle)),
                               frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        let out = TextBuilder.restyled(layer: annotation, fontName: "Georgia",
                                       fontSize: 99, weight: .bold, colorHex: "#00FF00")
        #expect(out == annotation)
    }
}

// 3.6 smart default: text always gets a shadow that contrasts with its own
// color, so callouts stay legible on busy/matching backgrounds.
@Suite("Auto-contrast text shadow")
struct AutoContrastShadowTests {

    @Test func luminanceBasics() {
        #expect(RGBA(hex: "#FFFFFF")!.relativeLuminance > 0.99)
        #expect(RGBA(hex: "#000000")!.relativeLuminance < 0.01)
        #expect(RGBA(hex: "#FFD60A")!.relativeLuminance > 0.5) // yellow reads light
        #expect(RGBA(hex: "#007AFF")!.relativeLuminance < 0.5) // blue reads dark
    }

    @Test func lightTextGetsADarkShadowAndViceVersa() {
        #expect(TextBuilder.autoContrastShadow(forColorHex: "#FFFFFF").colorHex == "#000000")
        #expect(TextBuilder.autoContrastShadow(forColorHex: "#FFD60A").colorHex == "#000000")
        #expect(TextBuilder.autoContrastShadow(forColorHex: "#000000").colorHex == "#FFFFFF")
        #expect(TextBuilder.autoContrastShadow(forColorHex: "#FF3B30").colorHex == "#FFFFFF")
    }

    @Test func shadowIsSubtleButPresent() {
        let shadow = TextBuilder.autoContrastShadow(forColorHex: "#FFFFFF")
        #expect(shadow.opacity > 0.3 && shadow.opacity < 1)
        #expect(shadow.radius > 0 && shadow.radius <= 4)
    }

    @Test func newTextLayersCarryTheShadow() {
        let content = TextContent(string: "Hi") // default white
        let layer = TextBuilder.layer(content: content, at: .zero,
                                      naturalSize: CGSize(width: 40, height: 20))
        #expect(layer.style.shadow == TextBuilder.autoContrastShadow(forColorHex: content.colorHex))
    }
}
