import Foundation
import Testing
@testable import PhotonzCore

@Suite("The color picker's model")
struct ColorPickerModelTests {

    // MARK: - HSL and HSV round trips

    @Test func readsHSLOfAKnownColor() throws {
        // #7C4DFF, the mock's brand purple. Its hue is 255.8, not the 258 the
        // mock page writes by hand, and the arithmetic is what we go by.
        let hsl = try #require(RGBA(hex: "#7C4DFF")).hsl
        #expect(abs(hsl.hue - 255.8) < 0.5)
        #expect(abs(hsl.saturation - 1.0) < 0.01)
        #expect(abs(hsl.lightness - 0.65) < 0.01)
    }

    @Test func hslRoundTripsThroughRGB() throws {
        for hex in ["#7C4DFF", "#12C2E9", "#3ECF8E", "#0C0E14", "#FFFFFF", "#000000", "#808080"] {
            let color = try #require(RGBA(hex: hex))
            #expect(RGBA(hsl: color.hsl).hexString == hex.uppercased(), "\(hex)")
        }
    }

    @Test func hsvRoundTripsThroughRGB() throws {
        for hex in ["#7C4DFF", "#12C2E9", "#FF5D8F", "#0C0E14", "#FFFFFF", "#000000"] {
            let color = try #require(RGBA(hex: hex))
            #expect(RGBA(hsv: color.hsv).hexString == hex.uppercased(), "\(hex)")
        }
    }

    @Test func grayHasNoHueButStillReadsAsZeroSaturation() throws {
        let gray = try #require(RGBA(hex: "#808080"))
        #expect(gray.hsl.saturation == 0)
        #expect(abs(gray.hsl.lightness - 0.502) < 0.005)
    }

    // MARK: - PickerColor keeps the hue a flat color cannot hold

    @Test func draggingToBlackKeepsTheHueForTheWayBack() throws {
        var color = PickerColor(try #require(RGBA(hex: "#7C4DFF")))
        let hue = color.hue
        color.value = 0                     // dragged to the bottom of the square
        #expect(color.rgba.hexString == "#000000")
        color.value = 1                     // dragged back up
        #expect(color.hue == hue)
        #expect(color.rgba.hexString == "#7C4DFF")
    }

    @Test func seedingFromAHexGivesBackThatHex() throws {
        for hex in ["#7C4DFF", "#12C2E9", "#FFB36B", "#0C0E14"] {
            let color = PickerColor(try #require(RGBA(hex: hex)))
            #expect(color.hex == hex.uppercased())
        }
    }

    @Test func hexCarriesAlphaOnlyWhenItIsNotOpaque() throws {
        var color = PickerColor(try #require(RGBA(hex: "#7C4DFF")))
        #expect(color.hexWithAlpha == "#7C4DFF")
        color.alpha = 0.5
        #expect(color.hexWithAlpha == "#7C4DFF80")
        color.alpha = 0
        #expect(color.hexWithAlpha == "#7C4DFF00")
    }

    // MARK: - Channels

    @Test func hslChannelsReadTheNumbersAPersonWouldType() throws {
        let color = PickerColor(try #require(RGBA(hex: "#7C4DFF")))
        #expect(abs(color.value(of: .hue) - 256) < 1)
        #expect(abs(color.value(of: .saturation) - 100) < 1)
        #expect(abs(color.value(of: .lightness) - 65) < 1)
        #expect(color.value(of: .alpha) == 100)
    }

    @Test func rgbChannelsReadZeroTo255() throws {
        let color = PickerColor(try #require(RGBA(hex: "#7C4DFF")))
        #expect(color.value(of: .red) == 124)
        #expect(color.value(of: .green) == 77)
        #expect(color.value(of: .blue) == 255)
    }

    @Test func settingOneChannelLeavesTheOthersWhereTheyWere() throws {
        let color = PickerColor(try #require(RGBA(hex: "#7C4DFF")))
        let redder = color.setting(.red, to: 200)
        #expect(redder.value(of: .red) == 200)
        #expect(redder.value(of: .green) == 77)
        #expect(redder.value(of: .blue) == 255)
    }

    @Test func settingHueKeepsSaturationAndLightness() throws {
        let color = PickerColor(try #require(RGBA(hex: "#7C4DFF")))
        let turned = color.setting(.hue, to: 120)
        #expect(abs(turned.value(of: .hue) - 120) < 1)
        #expect(abs(turned.value(of: .saturation) - 100) < 2)
        #expect(abs(turned.value(of: .lightness) - 65) < 2)
    }

    @Test func channelsClampRatherThanWrap() throws {
        let color = PickerColor(try #require(RGBA(hex: "#7C4DFF")))
        #expect(color.setting(.saturation, to: 400).value(of: .saturation) == 100)
        #expect(color.setting(.red, to: -20).value(of: .red) == 0)
        #expect(color.setting(.alpha, to: 250).value(of: .alpha) == 100)
    }

    @Test func eachFormatOffersOneSliderPerChannel() {
        #expect(ColorFormat.hsl.channels == [.hue, .saturation, .lightness, .alpha])
        #expect(ColorFormat.rgb.channels == [.red, .green, .blue, .alpha])
        // Hex has no channels to slide, so it keeps hue and opacity and adds a field.
        #expect(ColorFormat.hex.channels == [.hue, .alpha])
    }

    // MARK: - Typing and pasting a color

    @Test func parsesEveryWayAColorUsuallyArrives() throws {
        let expected = try #require(RGBA(hex: "#7C4DFF")).hexString
        for text in ["#7C4DFF", "7c4dff", "  #7C4DFF  ",
                     "rgb(124, 77, 255)", "rgb(124 77 255)", "RGB(124,77,255)"] {
            let parsed = try #require(ColorText.parse(text), "\(text)")
            #expect(parsed.hexString == expected, "\(text)")
        }
    }

    @Test func parsesShorthandHex() throws {
        #expect(try #require(ColorText.parse("#F0C")).hexString == "#FF00CC")
        #expect(try #require(ColorText.parse("F0C")).hexString == "#FF00CC")
    }

    @Test func parsesHSLTheWayCSSWritesIt() throws {
        for text in ["hsl(256 100% 65%)", "hsl(256, 100%, 65%)", "HSL(256 100% 65%)"] {
            let hsl = try #require(ColorText.parse(text), "\(text)").hsl
            #expect(abs(hsl.hue - 256) < 1, "\(text)")
            #expect(abs(hsl.saturation - 1) < 0.01, "\(text)")
            #expect(abs(hsl.lightness - 0.65) < 0.01, "\(text)")
        }
    }

    @Test func parsesAnAlphaWhenOneIsGiven() throws {
        #expect(abs(try #require(ColorText.parse("#7C4DFF80")).a - 128.0 / 255.0) < 0.01)
        #expect(abs(try #require(ColorText.parse("rgba(124, 77, 255, 0.5)")).a - 0.5) < 0.01)
        #expect(abs(try #require(ColorText.parse("hsl(258 100% 65% / 50%)")).a - 0.5) < 0.01)
    }

    @Test func refusesWhatIsNotAColor() {
        for text in ["", "purple-ish", "#12345", "rgb(1,2)", "hsl()", "#GGGGGG"] {
            #expect(ColorText.parse(text) == nil, "\(text)")
        }
    }

    // MARK: - The derived swatch rows

    @Test func shadesAreNineStepsOfTheSameHue() throws {
        let base = try #require(RGBA(hex: "#7C4DFF"))
        let shades = ColorRamp.shades(of: base)
        #expect(shades.count == 9)
        for hex in shades {
            let hsl = try #require(RGBA(hex: hex)).hsl
            #expect(abs(hsl.hue - base.hsl.hue) < 2, "\(hex)")
        }
        // Light at the top, dark at the bottom, never repeating.
        let lightnesses = try shades.map { try #require(RGBA(hex: $0)).hsl.lightness }
        #expect(lightnesses == lightnesses.sorted(by: >))
        #expect(Set(shades).count == shades.count)
    }

    @Test func shadesOfAnyBaseAreTheSameNineSteps() throws {
        // Derived, never authored: the ramp does not depend on where the base sits.
        let a = try shades(of: "#7C4DFF").map { try #require(RGBA(hex: $0)).hsl.lightness }
        let b = try shades(of: "#3ECF8E").map { try #require(RGBA(hex: $0)).hsl.lightness }
        for (x, y) in zip(a, b) { #expect(abs(x - y) < 0.01) }
    }

    @Test func theCurrentColorIsMarkedInItsOwnRamp() throws {
        let base = try #require(RGBA(hex: "#7C4DFF"))
        let index = try #require(ColorRamp.nearestShadeIndex(of: base))
        #expect(index == 3)     // lightness 0.65
    }

    @Test func relatedColorsTurnTheHueAndKeepEverythingElse() throws {
        let base = try #require(RGBA(hex: "#7C4DFF"))
        let related = ColorRamp.related(to: base)
        #expect(related.count == 6)
        for hex in related {
            let hsl = try #require(RGBA(hex: hex)).hsl
            #expect(abs(hsl.lightness - base.hsl.lightness) < 0.02, "\(hex)")
            #expect(abs(hsl.saturation - base.hsl.saturation) < 0.02, "\(hex)")
        }
        #expect(!related.contains(base.hexString))
    }

    @Test func relatedHuesWrapPastZero() throws {
        let base = try #require(RGBA(hex: "#FF3B30"))     // hue ~4 degrees
        for hex in ColorRamp.related(to: base) {
            #expect(RGBA(hex: hex) != nil, "\(hex)")
        }
    }

    private func shades(of hex: String) throws -> [String] {
        ColorRamp.shades(of: try #require(RGBA(hex: hex)))
    }

    // MARK: - Contrast

    @Test func blackOnWhiteIsTheFullTwentyOne() throws {
        let reading = ContrastReading(of: try #require(RGBA(hex: "#000000")),
                                      on: try #require(RGBA(hex: "#FFFFFF")))
        #expect(abs(reading.ratio - 21) < 0.05)
        #expect(reading.grade == .aaa)
        #expect(reading.passes)
    }

    @Test func whiteOnWhiteFails() throws {
        let reading = ContrastReading(of: try #require(RGBA(hex: "#FFFFFF")),
                                      on: try #require(RGBA(hex: "#FFFFFF")))
        #expect(abs(reading.ratio - 1) < 0.001)
        #expect(reading.grade == .fail)
        #expect(!reading.passes)
    }

    @Test func gradesLandOnTheWCAGThresholds() throws {
        // #767676 on white is the canonical 4.5:1 boundary.
        let boundary = ContrastReading(of: try #require(RGBA(hex: "#767676")),
                                       on: try #require(RGBA(hex: "#FFFFFF")))
        #expect(abs(boundary.ratio - 4.54) < 0.05)
        #expect(boundary.grade == .aa)
        // A mid gray only clears the large-text bar.
        let large = ContrastReading(of: try #require(RGBA(hex: "#949494")),
                                    on: try #require(RGBA(hex: "#FFFFFF")))
        #expect(large.grade == .aaLarge)
        #expect(large.passes)
    }

    @Test func gradesReadAsWordsAPersonKnows() {
        #expect(ContrastReading.Grade.aaa.title == "AAA")
        #expect(ContrastReading.Grade.aa.title == "AA")
        #expect(ContrastReading.Grade.aaLarge.title == "AA Large")
        #expect(ContrastReading.Grade.fail.title == "Fail")
    }

    @Test func aTranslucentColorIsReadOverItsBackground() throws {
        // Half-transparent black on white reads as the gray you actually see,
        // not as black, because that is what is on the screen.
        var half = try #require(RGBA(hex: "#000000"))
        half.a = 0.5
        let reading = ContrastReading(of: half, on: try #require(RGBA(hex: "#FFFFFF")))
        #expect(reading.ratio < 21)
        #expect(abs(reading.ratio - ContrastReading(of: try #require(RGBA(hex: "#808080")),
                                                    on: try #require(RGBA(hex: "#FFFFFF"))).ratio) < 0.3)
    }
}
