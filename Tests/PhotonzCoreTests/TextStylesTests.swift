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
