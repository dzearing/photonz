import CoreGraphics
import Foundation
import PhotonzCore
import Testing

@Suite("MeasureStyles")
struct MeasureStylesTests {

    @Test func defaultsAreTheBlueRedlinerLook() {
        // Sampled from the user's screenshot of 2026-10-13: mid blue caliper
        // and ring, a dark navy chip, white numbers.
        let s = MeasureStyles()
        #expect(s.strokeColorHex == "#3774D5")   // blue caliper
        #expect(s.chipColorHex == "#233963")     // dark navy chip
        #expect(s.content.chipBorderColorHex == "#3774D5") // ringed in the caliper's blue
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
        s.snapsToCenters = false
        let back = try JSONDecoder().decode(MeasureStyles.self, from: JSONEncoder().encode(s))
        #expect(back == s)
        #expect(!back.snapsToCenters)
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
        #expect(back.snapsToCenters, "older prefs adopt the mock's default")
    }

    @Test func snapOptionDefaultsToEdgesAndCenters() {
        // The mock's tool options row reads `Snap: Edges and centers`.
        #expect(MeasureStyles().snapsToCenters)
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

// MARK: - One shared look (every mode, every role)

@Suite("MeasureStyles share one look across modes")
struct MeasureStylesSharedLookTests {

    private func ink(_ c: MeasureContent) -> [String?] {
        [c.strokeColorHex, c.chipColorHex, c.textColorHex, c.chipBorderColorHex,
         String(describing: c.chipOpacity)]
    }

    @Test func everyRoleStartsInTheSameBlueSet() {
        let s = MeasureStyles()
        #expect(s.colors == MeasureColors.standard)
        #expect(ink(s.content(for: .size)) == ink(s.content(for: .spacing)))
        #expect(MeasureColors.standard.strokeColorHex == "#3774D5")
        #expect(MeasureColors.standard.chipColorHex == "#233963")
        #expect(MeasureColors.standard.textColorHex == "#FFFFFF")
        #expect(MeasureColors.standard.chipBorderColorHex == "#3774D5")
    }

    @Test func aSizeCaliperRecolouredIsWhatTheNextGapStartsWith() {
        var s = MeasureStyles()
        var width = s.content(for: .size)
        width.strokeColorHex = "#34C759"
        width.chipColorHex = "#0B3D1A"
        width.chipBorderColorHex = "#34C759"
        width.textColorHex = "#EEEEEE"
        s.absorb(width)
        let gap = s.content(for: .spacing)
        #expect(gap.role == .spacing)
        #expect(gap.strokeColorHex == "#34C759")
        #expect(gap.chipColorHex == "#0B3D1A")
        #expect(gap.chipBorderColorHex == "#34C759")
        #expect(gap.textColorHex == "#EEEEEE")
        #expect(s.content.strokeColorHex == "#34C759", "and a Distance too")
    }

    @Test func aGapRecolouredIsWhatTheNextSizeStartsWith() {
        var s = MeasureStyles()
        var gap = s.content(for: .spacing)
        gap.strokeColorHex = "#AF52DE"
        s.absorb(gap)
        #expect(s.content(for: .size).strokeColorHex == "#AF52DE")
        #expect(s.sizeBoxColorHex == "#AF52DE", "the box follows the shared ink until picked")
    }

    @Test func theRoleNeverDecidesTheColours() {
        var s = MeasureStyles()
        s.strokeColorHex = "#123456"
        s.role = .spacing
        #expect(s.content.strokeColorHex == "#123456")
        s.role = .size
        #expect(s.content.strokeColorHex == "#123456")
    }

    @Test func theSharedLookSurvivesALaunch() throws {
        var s = MeasureStyles()
        s.colors.strokeColorHex = "#101010"
        s.colors.chipBorderColorHex = nil
        s.role = .spacing
        let back = try JSONDecoder().decode(MeasureStyles.self, from: JSONEncoder().encode(s))
        #expect(back == s)
        #expect(back.colors.chipBorderColorHex == nil, "a ring switched off stays off")
    }

    // MARK: Moving a memory from the per-role build

    private func decode(_ json: String) throws -> MeasureStyles {
        try JSONDecoder().decode(MeasureStyles.self, from: Data(json.utf8))
    }

    private let red = ##"{"strokeColorHex":"#FF3B30","chipColorHex":"#8C201A","chipOpacity":1,"textColorHex":"#FFFFFF","chipBorderColorHex":"#FF3B30"}"##
    private let blue = ##"{"strokeColorHex":"#0A84FF","chipColorHex":"#1B3A66","chipOpacity":1,"textColorHex":"#FFFFFF","chipBorderColorHex":"#0A84FF"}"##
    private let green = ##"{"strokeColorHex":"#34C759","chipColorHex":"#0B3D1A","chipOpacity":1,"textColorHex":"#FFFFFF","chipBorderColorHex":"#34C759"}"##

    @Test func nobodyWhoNeverTunedAColourKeepsTheOldRedOrBlue() throws {
        let s = try decode(##"{"role":"size","sizeColors":\##(red),"spacingColors":\##(blue)}"##)
        #expect(s.colors == MeasureColors.standard)
        let t = try decode(##"{"role":"spacing","sizeColors":\##(red),"spacingColors":\##(blue)}"##)
        #expect(t.colors == MeasureColors.standard)
    }

    @Test func theLastUsedRolesTunedSetBecomesTheSharedOne() throws {
        let s = try decode(##"{"role":"spacing","sizeColors":\##(red),"spacingColors":\##(green)}"##)
        #expect(s.colors.strokeColorHex == "#34C759")
        let t = try decode(##"{"role":"size","sizeColors":\##(green),"spacingColors":\##(blue)}"##)
        #expect(t.colors.strokeColorHex == "#34C759")
    }

    @Test func aTunedSetIsKeptEvenWhenTheOtherRoleWasUsedLast() throws {
        // Size tuned, then a Gap made: the role says Spacing, whose set was
        // never touched, so the only set anybody chose is the one that moves.
        let s = try decode(##"{"role":"spacing","sizeColors":\##(green),"spacingColors":\##(blue)}"##)
        #expect(s.colors.strokeColorHex == "#34C759")
    }

    @Test func aPreRolesMemoryMovesAcrossToo() throws {
        let untouched = try decode(##"{"strokeColorHex":"#FF3B30","chipColorHex":"#8C201A"}"##)
        #expect(untouched.colors == MeasureColors.standard)
        let tuned = try decode(##"{"strokeColorHex":"#00FF00","chipColorHex":"#003300"}"##)
        #expect(tuned.colors.strokeColorHex == "#00FF00")
        #expect(tuned.colors.chipColorHex == "#003300")
    }

    @Test func aBoxLeftOnTheOldRedFollowsTheNewInk() throws {
        let s = try decode(##"{"role":"size","sizeColors":\##(red),"sizeBoxColor":"#FF3B30"}"##)
        #expect(s.sizeBoxColorPick == nil)
        #expect(s.sizeBoxColorHex == MeasureColors.standard.strokeColorHex)
        let picked = try decode(##"{"role":"size","sizeColors":\##(red),"sizeBoxColor":"#123456"}"##)
        #expect(picked.sizeBoxColorHex == "#123456")
    }

    @Test func aSharedMemoryIsReadAsWritten() throws {
        // Once moved, the shared set is the only one read: a stray old key
        // beside it changes nothing.
        let s = try decode(##"{"role":"size","colors":\##(green),"sizeColors":\##(blue)}"##)
        #expect(s.colors.strokeColorHex == "#34C759")
    }

    @Test func colourSetsClampChipOpacity() {
        var c = MeasureColors.standard
        c.chipOpacity = 7
        #expect(c.chipOpacity == 1)
        c.chipOpacity = -1
        #expect(c.chipOpacity == 0)
    }
}
