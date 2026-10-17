import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Type set the way Apple sets a title: its own letter spacing, its own line
/// spacing and, where it wants one, a gradient running through the words that
/// can be slid across them over time (`video-titles-apple.html`).
@Suite("Title type setting")
struct TitleTypeSettingTests {

    private static let sunset = Paint(hex: "#0894FF", kind: .linear,
                                      stops: [GradientStop(hex: "#0894FF", position: 0),
                                              GradientStop(hex: "#FF2E54", position: 0.5),
                                              GradientStop(hex: "#F5F5F7", position: 1)],
                                      angle: 90)

    private static func headline() -> TextContent {
        TextContent(string: "Smart Redline", fontSize: 172, colorHex: "#F5F5F7", weight: .semibold)
    }

    // MARK: - Kept in the document

    @Test func textWrittenBeforeAnyOfThisReadsAsPlainType() throws {
        let old = ##"{"string":"Hi","fontName":"SF Pro","fontSize":24,"colorHex":"#FFFFFF"}"##
        let text = try JSONDecoder().decode(TextContent.self, from: Data(old.utf8))
        #expect(text.tracking == nil)
        #expect(text.lineHeight == nil)
        #expect(text.fill == nil)
        #expect(text.fillLength == nil)
        #expect(text.fillShift == nil)
        #expect(text.trackingPoints == 0)
        #expect(text.fillPaint == nil)
    }

    @Test func plainTypeWritesNothingNew() throws {
        let data = try JSONEncoder().encode(TextContent(string: "Hi"))
        let json = String(decoding: data, as: UTF8.self)
        for key in ["tracking", "lineHeight", "fill", "fillLength", "fillShift"] {
            #expect(!json.contains("\"\(key)\""), "\(key) is not written for text that never set it")
        }
    }

    @Test func spacingAndAGradientSurviveASave() throws {
        var text = Self.headline()
        text.tracking = -0.03
        text.lineHeight = 1.05
        text.fill = Self.sunset
        text.fillLength = 2.2
        text.fillShift = 1
        let back = try JSONDecoder().decode(TextContent.self, from: JSONEncoder().encode(text))
        #expect(back == text)
    }

    // MARK: - Letter spacing

    @Test func trackingIsAShareOfTheTypeSize() {
        var text = Self.headline()
        text.tracking = -0.03
        #expect(abs(text.trackingPoints - (-5.16)) < 0.001, "-3% of 172 points is 5.16 points tighter")
        text.fontSize = 100
        #expect(abs(text.trackingPoints - (-3)) < 0.001, "it scales with the type")
    }

    @Test func trackingAndLineSpacingAreKeptInRange() {
        var layer = Layer(name: "Title", content: .text(Self.headline()), frame: .zero)
        layer = TextBuilder.respaced(layer, tracking: -5)
        #expect(layer.text?.tracking == TextContent.trackingRange.lowerBound)
        layer = TextBuilder.respaced(layer, tracking: 0)
        #expect(layer.text?.tracking == nil, "no spacing is the face's own, which writes nothing")
        layer = TextBuilder.respaced(layer, lineHeight: 0.1)
        #expect(layer.text?.lineHeight == TextContent.lineHeightRange.lowerBound)
        layer = TextBuilder.respaced(layer, lineHeight: .some(nil))
        #expect(layer.text?.lineHeight == nil, "Auto is the face's own line spacing")
        layer = TextBuilder.respaced(layer, lineHeight: 1.06)
        #expect(layer.text?.lineHeight == 1.06)
        #expect(layer.text?.tracking == nil, "setting one leaves the other alone")
    }

    @Test func respacingIsOneUndoStep() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        let layer = Layer(name: "Title", content: .text(Self.headline()),
                          frame: CGRect(x: 0, y: 0, width: 900, height: 200))
        doc.layers = [layer]
        var history = History(document: doc)
        history.perform { document in
            document.updateLayer(id: layer.id) { $0 = TextBuilder.respaced($0, tracking: -0.028, lineHeight: 1.04) }
        }
        #expect(history.current.layer(id: layer.id)?.text?.tracking == -0.028)
        #expect(history.current.layer(id: layer.id)?.text?.lineHeight == 1.04)
        history.undo()
        #expect(history.current.layer(id: layer.id)?.text?.tracking == nil)
        #expect(history.current.layer(id: layer.id)?.text?.lineHeight == nil)
    }

    // MARK: - Measuring without CoreText

    @Test func theEstimateFollowsTheLineSpacing() {
        var text = TextContent(string: "One\nTwo", fontSize: 100)
        let natural = TextMeasurement.estimated(text, .greatestFiniteMagnitude).height
        text.lineHeight = 1.5
        let loose = TextMeasurement.estimated(text, .greatestFiniteMagnitude).height
        #expect(loose > natural)
        #expect(abs(loose - (300 + TextMeasurement.slack)) < 1, "two lines at one and a half times 100")
    }

    @Test func theEstimateFollowsTheLetterSpacing() {
        var text = TextContent(string: "Redline", fontSize: 100)
        let natural = TextMeasurement.estimated(text, .greatestFiniteMagnitude).width
        text.tracking = 0.1
        let wide = TextMeasurement.estimated(text, .greatestFiniteMagnitude).width
        #expect(abs((wide - natural) - 70) < 1, "seven letters each ten points further apart")
    }

    // MARK: - A gradient through the words

    @Test func textTakesAGradientThroughTheColorRow() {
        #expect(ColorSlot.text.acceptsGradient)
        var layer = Layer(name: "Title", content: .text(Self.headline()), frame: .zero)
        layer.setPaint(Self.sunset, for: .text)
        #expect(layer.text?.fillPaint == Self.sunset)
        #expect(layer.paint(for: .text)?.isGradient == true)
        #expect(layer.text?.colorHex == Self.sunset.hex,
                "the flat colour is the ramp's own stand-in, so a contrast reading still has one")
    }

    @Test func paintingTheWordsOneColourTakesTheGradientAway() {
        var layer = Layer(name: "Title", content: .text(Self.headline()), frame: .zero)
        layer.setPaint(Self.sunset, for: .text)
        layer.setPaint(Paint(hex: "#FF0000"), for: .text)
        #expect(layer.text?.fillPaint == nil)
        #expect(layer.text?.colorHex == "#FF0000")
        // Even the ramp's own stand-in colour, picked flat, is flat.
        layer.setPaint(Self.sunset, for: .text)
        layer.setPaint(Paint(hex: Self.sunset.hex), for: .text)
        #expect(layer.text?.fillPaint == nil)
    }

    @Test func anythingThatRecoloursTheWordsWins() {
        // A title restyle, a saved colour or a colour key writes the flat
        // colour alone; the words then wear that colour, not a stale ramp.
        var text = Self.headline()
        text.fill = Self.sunset
        text.colorHex = Self.sunset.hex
        #expect(text.fillPaint != nil)
        text.colorHex = "#00FF00"
        #expect(text.fillPaint == nil)
    }

    @Test func theRampRunsAcrossEachLinesOwnBox() {
        var text = Self.headline()
        text.fill = Self.sunset
        let line = CGRect(x: 100, y: 40, width: 500, height: 180)
        #expect(text.fillBox(forLine: line) == line, "a ramp as long as the words, sitting on them")
        // The mock's Gradient Word: a ramp 220% of the words, slid by the
        // CSS background-position rule.
        text.fillLength = 2.2
        text.fillShift = 0
        #expect(text.fillBox(forLine: line) == CGRect(x: 100, y: 40, width: 1100, height: 180),
                "at nought the ramp's start sits on the first letter")
        text.fillShift = 1
        let end = text.fillBox(forLine: line)
        #expect(abs(end.minX - (100 - 600)) < 0.001, "at one the ramp's end sits on the last letter")
        #expect(abs(end.maxX - line.maxX) < 0.001)
    }

    // MARK: - Sliding it over time

    @Test func theGradientPositionKeysOnWordsWithAGradient() {
        var (doc, id) = Self.withTitle()
        #expect(doc.layer(id: id)?.keyableProperties.contains(.motion(.gradientShift)) == false,
                "flat words have no ramp to slide")
        doc.updateLayer(id: id) { $0.setPaint(Self.sunset, for: .text) }
        #expect(doc.layer(id: id)?.keyableProperties.contains(.motion(.gradientShift)) == true)
        doc.startKeying(layerID: id, .motion(.gradientShift), atDocumentTimeMS: 2000)
        doc.setKeyedValue(.number(100), layerID: id, .motion(.gradientShift), atDocumentTimeMS: 2000)
        doc.startKeying(layerID: id, .motion(.gradientShift), atDocumentTimeMS: 4000)
        doc.setKeyedValue(.number(0), layerID: id, .motion(.gradientShift), atDocumentTimeMS: 4000)
        let early = doc.drawn(atTimeMS: 2000).layer(id: id)?.text
        let late = doc.drawn(atTimeMS: 5000).layer(id: id)?.text
        #expect(early?.fillShift == 1)
        #expect(late?.fillShift == 0)
        let middle = doc.drawn(atTimeMS: 3000).layer(id: id)?.text?.fillShift ?? -1
        #expect(middle > 0 && middle < 1, "the colours are partway across the words")
    }

    @Test func slidingARampAsLongAsTheWordsGivesItRoomToSlide() {
        var layer = Layer(name: "Title", content: .text(Self.headline()), frame: .zero)
        layer.setPaint(Self.sunset, for: .text)
        let moved = MotionProperty.gradientShift.applied(.number(50), to: layer, authored: layer)
        #expect(moved.text?.fillShift == 0.5)
        #expect(moved.text?.fillLength == 2, "a ramp exactly the words' length has nowhere to slide")
        var long = layer
        long.content = .text({ var t = layer.text!; t.fillLength = 2.2; return t }())
        #expect(MotionProperty.gradientShift.applied(.number(150), to: long, authored: long).text?.fillShift == 1)
        #expect(MotionProperty.gradientShift.applied(.number(0), to: long, authored: long).text?.fillLength == 2.2)
    }

    @Test func theGradientPositionReadsAsAPercent() {
        #expect(MotionProperty.gradientShift.title == "Gradient position")
        #expect(MotionProperty.gradientShift.format(.number(40)) == "40%")
        #expect(PropertyPicker.group(.motion(.gradientShift)) == "Text")
    }

    // MARK: - Re-wording keeps how it is set

    @Test func rewordingKeepsTheSetting() {
        var existing = Self.headline()
        existing.tracking = -0.03
        existing.lineHeight = 1.05
        existing.fill = Self.sunset
        existing.colorHex = Self.sunset.hex
        existing.fillLength = 2.2
        var typed = TextContent(string: "Smarter Redline", fontSize: 172, colorHex: Self.sunset.hex)
        typed.keepSetting(of: existing)
        #expect(typed.tracking == -0.03)
        #expect(typed.lineHeight == 1.05)
        #expect(typed.fillPaint == Self.sunset)
        #expect(typed.fillLength == 2.2)
        // A colour chosen while typing is a new colour: the ramp goes.
        var recoloured = TextContent(string: "Smarter", fontSize: 172, colorHex: "#FF0000")
        recoloured.keepSetting(of: existing)
        #expect(recoloured.tracking == -0.03)
        #expect(recoloured.fillPaint == nil)
    }

    // MARK: - What the panel's boxes say

    @Test func trackingReadsAsAPercentOfTheSize() {
        #expect(TextSpacing.trackingShowing(StyleReading(value: -0.028, isMixed: false)) == .number("-2.8"))
        #expect(TextSpacing.trackingShowing(StyleReading(value: 0, isMixed: false)) == .number("0"))
        #expect(TextSpacing.trackingShowing(StyleReading(value: 0.16, isMixed: false)) == .number("16"))
        #expect(TextSpacing.trackingShowing(StyleReading(value: 0.1, isMixed: true)) == .standIn("Mixed"))
        #expect(abs(TextSpacing.tracking(percent: -2.8) - (-0.028)) < 0.000_001)
    }

    @Test func leadingReadsAsAPercentOrAuto() {
        #expect(TextSpacing.leadingShowing(StyleReading<CGFloat?>(value: .some(nil), isMixed: false))
                == .standIn("Auto"), "the face's own spacing, as Photoshop says it")
        #expect(TextSpacing.leadingShowing(StyleReading<CGFloat?>(value: 1.06, isMixed: false)) == .number("106"))
        #expect(TextSpacing.leadingShowing(StyleReading<CGFloat?>(value: 1.025, isMixed: false)) == .number("102.5"))
        #expect(TextSpacing.leadingShowing(StyleReading<CGFloat?>(value: 1.0, isMixed: true)) == .standIn("Mixed"))
        #expect(TextSpacing.leadingShowing(StyleReading<CGFloat?>(value: nil, isMixed: false)) == .nothing)
        #expect(TextSpacing.lineHeight(percent: 106) == 1.06)
    }

    // MARK: - New York

    @Test func newYorkIsOnTheFontList() {
        #expect(TextStyles.fonts.contains("New York"))
    }

    private static func withTitle() -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        var title = Layer(name: "Hello", content: .text(TextContent(string: "Hello", fontSize: 48)),
                          frame: CGRect(x: 100, y: 100, width: 400, height: 80))
        title.time = LayerTime(inMS: 2000, outMS: 8000)
        doc.layers = [title]
        doc.durationMS = 10_000
        return (doc, title.id)
    }
}
