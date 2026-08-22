import CoreGraphics
import Foundation
import PhotonzCore
import Testing

@Suite("MeasureStyles")
struct MeasureStylesTests {

    @Test func defaultsAreTheRedlinerLook() {
        let s = MeasureStyles()
        #expect(s.strokeColorHex == "#FF3B30")   // red caliper
        #expect(s.chipColorHex == "#8C201A")     // darker red chip
        #expect(s.chipOpacity == 1)              // solid, so white text reads
        #expect(s.textColorHex == "#FFFFFF")
        #expect(s.strokeWidth == 2)
        #expect(s.labelSizePx == 20)
    }

    @Test func labelSizeIsStoredInPixelsAndSeedsTheScale() {
        var s = MeasureStyles()
        #expect(s.content.labelPointSize == 20)
        s.labelSizePx = 40
        #expect(s.content.labelScale == 40 / MeasureContent.labelFontSize)
        #expect(s.content.labelPointSize == 40)
    }

    @Test func contentSeedsANewCaliperWithEveryStoredField() {
        var s = MeasureStyles()
        s.strokeColorHex = "#111111"
        s.chipColorHex = "#222222"
        s.chipOpacity = 0.4
        s.textColorHex = "#333333"
        s.strokeWidth = 3
        s.unit = .pixels
        s.decimals = 2
        let c = s.content
        #expect(c.strokeColorHex == "#111111")
        #expect(c.chipColorHex == "#222222")
        #expect(c.chipOpacity == 0.4)
        #expect(c.textColorHex == "#333333")
        #expect(c.strokeWidth == 3)
        #expect(c.unit == .pixels)
        #expect(c.decimals == 2)
        #expect(c.showLabel)
    }

    @Test func effectsAreRememberedAlongsideTheColors() throws {
        // A drop shadow (or opacity, or blur) tuned on one caliper is what the
        // NEXT caliper starts with — the same deal AnnotationStyles gives shapes.
        var s = MeasureStyles()
        #expect(s.layerStyle == LayerStyle(), "a fresh measure has no effects")
        s.layerStyle = LayerStyle(opacity: 0.5, blurRadius: 2,
                                  shadow: ShadowStyle(radius: 8, opacity: 0.6))
        let back = try JSONDecoder().decode(MeasureStyles.self, from: JSONEncoder().encode(s))
        #expect(back.layerStyle == s.layerStyle)
        #expect(back.layerStyle.shadow?.radius == 8)
    }

    @Test func effectsDoNotLeakIntoTheContentTemplate() {
        // The style rides on the LAYER; the content template stays untouched.
        var s = MeasureStyles()
        s.layerStyle = LayerStyle(opacity: 0.25)
        #expect(s.content.strokeColorHex == s.strokeColorHex)
        #expect(s.layerStyle.opacity == 0.25)
    }

    @Test func stylesSurviveALaunchRoundTrip() throws {
        var s = MeasureStyles()
        s.layerStyle = LayerStyle(shadow: ShadowStyle())
        s.strokeColorHex = "#00FF00"
        s.chipColorHex = "#0000FF"
        s.chipOpacity = 0
        s.textColorHex = "#FFCC00"
        s.strokeWidth = 3
        s.labelSizePx = 32
        s.unit = .pixels
        s.decimals = 1
        let back = try JSONDecoder().decode(MeasureStyles.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }

    @Test func aPrefsBlobFromAnOlderBuildFillsInTheNewFields() throws {
        // Prefs written before a field existed must not wipe the whole style.
        let partial = Data(##"{"strokeColorHex":"#00FF00"}"##.utf8)
        let back = try JSONDecoder().decode(MeasureStyles.self, from: partial)
        #expect(back.strokeColorHex == "#00FF00")
        #expect(back.chipColorHex == MeasureStyles().chipColorHex)
        #expect(back.strokeWidth == MeasureStyles().strokeWidth)
        #expect(back.labelSizePx == MeasureStyles().labelSizePx)
        #expect(back.layerStyle == LayerStyle())
    }

    @Test func opacityAndLabelSizeAreClampedToTheirRanges() {
        var s = MeasureStyles()
        s.chipOpacity = 3
        #expect(s.chipOpacity == 1)
        s.chipOpacity = -1
        #expect(s.chipOpacity == 0)
        s.labelSizePx = 1000
        #expect(s.labelSizePx == MeasureContent.labelSizeRangePx.upperBound)
        s.labelSizePx = 0
        #expect(s.labelSizePx == MeasureContent.labelSizeRangePx.lowerBound)
    }

    @Test func absorbRemembersWhatTheInspectorChanged() {
        var s = MeasureStyles()
        var edited = s.content
        edited.strokeColorHex = "#123456"
        edited.chipOpacity = 0.25
        edited.labelScale = 2
        edited.unit = .pixels
        s.absorb(edited)
        #expect(s.strokeColorHex == "#123456")
        #expect(s.chipOpacity == 0.25)
        #expect(s.labelSizePx == 2 * MeasureContent.labelFontSize)
        #expect(s.unit == .pixels)
    }
}
