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
}
