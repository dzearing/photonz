import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

@Suite("TitleLook")
struct TitleLookTests {

    @Test func aTitleIsWhiteBoldAndSerifLikeTheMock() {
        let styles = TitleLook.styles(in: CGSize(width: 1280, height: 720))
        #expect(styles.colorHex == "#FFFFFF")
        #expect(styles.weight == .bold)
        #expect(styles.fontName == "Georgia")
        #expect(TextStyles.fonts.contains(styles.fontName))
    }

    @Test func aTitleIsATenthOfThePictureTall() {
        #expect(TitleLook.fontSize(in: CGSize(width: 1280, height: 720)) == 72)
        #expect(TitleLook.fontSize(in: CGSize(width: 1920, height: 1080)) == 108)
        // A portrait recording is sized by its height too.
        #expect(TitleLook.fontSize(in: CGSize(width: 1080, height: 1920)) == 192)
    }

    @Test func aTitleIsAlwaysBiggerThanTheCaptionsUnderIt() {
        for size in [CGSize(width: 1280, height: 720), CGSize(width: 640, height: 360),
                     CGSize(width: 3840, height: 2160)] {
            #expect(TitleLook.fontSize(in: size) > CaptionLayers.fontSize(in: size))
        }
    }

    @Test func aTinyPictureStillGetsAReadableTitle() {
        #expect(TitleLook.fontSize(in: CGSize(width: 160, height: 90)) == 24)
        #expect(TitleLook.fontSize(in: .zero) == 24)
    }

    @Test func theStylesHoldNoSavedStyle() {
        #expect(TitleLook.styles(in: CGSize(width: 1280, height: 720)).styleID == nil)
    }

    @Test func lightWordsGetTheMocksSoftDarkShadowSizedToThem() {
        let shadow = TitleLook.shadow(forColorHex: "#FFFFFF", fontSize: 72)
        #expect(shadow.colorHex == "#000000")
        // The mock: text-shadow 0 2px 12px rgba(0,0,0,.4) on 26px words, so a
        // blur of about a quarter of the type and a drop of about a thirteenth.
        #expect(abs(shadow.radius - 72 * 6 / 26) < 0.5)
        #expect(abs(shadow.offset.height - 72 * 2 / 26) < 0.5)
        #expect(shadow.offset.width == 0)
        #expect(shadow.opacity > 0.3 && shadow.opacity < 0.7)
    }

    @Test func darkWordsGetALightShadowInstead() {
        #expect(TitleLook.shadow(forColorHex: "#101010", fontSize: 72).colorHex == "#FFFFFF")
    }

    @Test func aTitleWearsTheMocksSoftShadowFirst() {
        let shadows = TitleLook.shadows(forColorHex: "#FFFFFF", fontSize: 72)
        #expect(shadows.first == TitleLook.shadow(forColorHex: "#FFFFFF", fontSize: 72))
    }

    /// White words over a white card in a screen recording: the soft shadow
    /// alone leaves the letters' edges the same colour as the card. A tight dark
    /// edge right against the letters keeps them readable, and on dark footage
    /// it is dark on dark, so the title looks as it always did there.
    @Test func aTitleAlsoWearsATightEdgeThatHoldsItOnALightFrame() {
        let shadows = TitleLook.shadows(forColorHex: "#FFFFFF", fontSize: 80)
        #expect(shadows.count == 2)
        let edge = shadows[1]
        #expect(edge.colorHex == "#000000")
        #expect(edge.offset == .zero)
        // Tight: far narrower than the soft shadow, and scaled to the type.
        #expect(edge.radius < shadows[0].radius / 4)
        #expect(edge.radius > 0)
        #expect(abs(TitleLook.shadows(forColorHex: "#FFFFFF", fontSize: 160)[1].radius
                    - edge.radius * 2) < 0.01)
        // Strong enough to draw a line, not a haze.
        #expect(edge.opacity >= 0.7)
        #expect(edge.kind == .drop)
        #expect(edge.isOn)
    }

    @Test func darkWordsGetALightEdgeInstead() {
        let shadows = TitleLook.shadows(forColorHex: "#101010", fontSize: 72)
        #expect(shadows.allSatisfy { $0.colorHex == "#FFFFFF" })
    }

    @Test func recolouringATitleTurnsItsEdgeToOpposeTheNewWords() {
        var layer = TextBuilder.layer(content: TextContent(string: "Ship", fontSize: 80, colorHex: "#FFFFFF"),
                                      at: .zero, naturalSize: CGSize(width: 200, height: 90))
        layer.style.shadows = TitleLook.shadows(forColorHex: "#FFFFFF", fontSize: 80)
        let dark = TextBuilder.restyled(layer: layer, colorHex: "#101010", keepsShadowShapes: true)
        #expect(dark.style.shadows.count == 2)
        #expect(dark.style.shadows.allSatisfy { $0.colorHex == "#FFFFFF" })
        // Only the colour turns: the soft shadow stays soft and the edge
        // stays the edge, rather than either becoming a callout's small halo.
        #expect(dark.style.shadows[0].radius == layer.style.shadows[0].radius)
        #expect(dark.style.shadows[1].radius == layer.style.shadows[1].radius)
    }

    @Test func recolouringACalloutStillRefreshesItsHalo() {
        let layer = TextBuilder.layer(content: TextContent(string: "Save", colorHex: "#FFFFFF"),
                                      at: .zero, naturalSize: CGSize(width: 60, height: 30))
        for keeps in [false, true] {
            let dark = TextBuilder.restyled(layer: layer, colorHex: "#101010", keepsShadowShapes: keeps)
            #expect(dark.style.shadows == [TextBuilder.autoContrastShadow(forColorHex: "#101010")])
        }
    }
}
