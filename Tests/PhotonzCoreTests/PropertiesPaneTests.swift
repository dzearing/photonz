import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The Properties pane beside a clip, a title or a sound
/// (`docs/design/mocks/pages/video.html`, `renderProps`): one clip line, then
/// only what is animating, with a picker for the rest.
///
/// Written before `PropertiesPane.swift`.
@Suite("The Properties pane's clip line and property picker")
struct PropertiesPaneTests {

    // MARK: - Fixtures

    static func clip(speed: Int = 100) -> Layer {
        var layer = Layer(name: "Sample Talk",
                          content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#000000")),
                          frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        layer.movie = MovieRef(pixelSize: CGSize(width: 1920, height: 1080), durationMS: 20000, hasSound: true)
        layer.time = LayerTime(inMS: 2000, outMS: 14900, sourceInMS: 0, sourceLengthMS: 20000)
        return layer
    }

    static func title() -> Layer {
        var layer = Layer(name: "Ship it faster",
                          content: .text(TextContent(string: "Ship it faster")),
                          frame: CGRect(x: 10, y: 10, width: 200, height: 40))
        layer.time = LayerTime(inMS: 1000, outMS: 4000)
        return layer
    }

    static func sound() -> Layer {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        let id = doc.addSound(SoundRef(durationMS: 4000), name: "music", atMS: 0)
        return doc.layer(id: id) ?? Layer(name: "missing", content: .text(TextContent(string: "")),
                                          frame: .zero)
    }

    // MARK: - The clip line

    @Test func aClipSaysItsNameInOutLengthAndSpeed() throws {
        let line = try #require(ClipLine(layer: Self.clip()))
        #expect(line.name == "Sample Talk")
        #expect(line.inText == "2.0s")
        #expect(line.outText == "14.9s")
        #expect(line.lengthText == "12.9s")
        #expect(line.speedText == "1.0x")
        #expect(line.reading == "2.0s \u{2192} 14.9s \u{00B7} 12.9s \u{00B7} 1.0x")
    }

    @Test func aPieceOfACutClipSaysThePieceNotTheWholeClip() throws {
        var layer = Self.clip()
        layer.setClipPieces(ClipPieces(pieces: [ClipPiece(sourceInMS: 0, lengthMS: 5000),
                                                ClipPiece(sourceInMS: 5000, lengthMS: 2000, speedPercent: 400)]))
        let line = try #require(ClipLine(layer: layer, piece: 1))
        #expect(line.inText == "7.0s")
        #expect(line.outText == "9.0s")
        #expect(line.lengthText == "2.0s")
        #expect(line.speedText == "4.0x")
    }

    @Test func aSpeedThatIsNotATenthKeepsItsDigits() {
        #expect(ClipLine.speedText(percent: 25) == "0.25x")
        #expect(ClipLine.speedText(percent: 50) == "0.5x")
        #expect(ClipLine.speedText(percent: 3000) == "30.0x")
        #expect(ClipLine.speedText(percent: 0) == "held")
    }

    @Test func aTitleSaysWhenItIsOnScreen() throws {
        let line = try #require(ClipLine(layer: Self.title()))
        #expect(line.inText == "1.0s")
        #expect(line.outText == "4.0s")
        #expect(line.lengthText == "3.0s")
        #expect(line.speedText == "1.0x")
    }

    @Test func aTitleIsNamedByItsWordsTheWayTheTimelineNamesIt() throws {
        var layer = Self.title()
        layer.name = "Text"
        let line = try #require(ClipLine(layer: layer))
        #expect(line.name == "Ship it faster")
    }

    @Test func aLayerWithNoTimeHasNoClipLine() {
        var layer = Self.title()
        layer.time = nil
        #expect(ClipLine(layer: layer) == nil)
    }

    @Test func theKindChipNamesWhatIsPicked() {
        #expect(ClipLine.kind(of: Self.clip()) == "Clip")
        #expect(ClipLine.kind(of: Self.title()) == "Title")
        #expect(ClipLine.kind(of: Self.sound()) == "Audio")
    }

    @Test func aShapeDrawnOnAVideoIsAGraphicNotAClip() {
        // Premiere's word for a shape or a picture on the timeline.
        var shape = Layer(name: "Rectangle",
                          content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#FF3B30")),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 60))
        shape.time = LayerTime(inMS: 1000, outMS: 3000)
        #expect(ClipLine.kind(of: shape) == "Graphic")
    }

    // MARK: - Animating, and the picker for the rest

    @Test func theCountSaysHowManyOfHowMany() {
        #expect(PropertyPicker.countText(keyed: 0, of: 15) == "nothing yet")
        #expect(PropertyPicker.countText(keyed: 2, of: 9) == "2 of 9 properties")
        #expect(PropertyPicker.countText(keyed: 1, of: 1) == "1 of 1 property")
    }

    @Test func everyPropertyHasAGroup() {
        let all: [KeyedProperty] = MotionProperty.allCases.map { .motion($0) } + [.volume]
        for property in all {
            #expect(!PropertyPicker.group(property).isEmpty)
        }
        #expect(PropertyPicker.group(.motion(.position)) == "Transform")
        #expect(PropertyPicker.group(.motion(.opacity)) == "Appearance")
        #expect(PropertyPicker.group(.motion(.blur)) == "Effects")
        #expect(PropertyPicker.group(.motion(.cropLeft)) == "Crop")
        #expect(PropertyPicker.group(.volume) == "Levels")
    }

    @Test func thePickerOffersOnlyWhatIsNotAnimatingInGroups() {
        let all: [KeyedProperty] = [.motion(.position), .motion(.scale), .motion(.opacity), .motion(.blur)]
        let groups = PropertyPicker.groups(all: all, keyed: [.motion(.scale)], query: "")
        #expect(groups.map(\.title) == ["Transform", "Appearance", "Effects"])
        #expect(groups[0].properties == [.motion(.position)])
    }

    @Test func thePickerFindsByNameIgnoringCase() {
        let all: [KeyedProperty] = [.motion(.position), .motion(.scale), .motion(.opacity)]
        let groups = PropertyPicker.groups(all: all, keyed: [], query: "  OPAC ")
        #expect(groups.map(\.title) == ["Appearance"])
        #expect(PropertyPicker.groups(all: all, keyed: [], query: "zzz").isEmpty)
    }

    @Test func thePickerSaysWhyItIsEmpty() {
        #expect(PropertyPicker.emptyText(query: "") == "Every property is already animating.")
        #expect(PropertyPicker.emptyText(query: "zz") == "Nothing matches \u{201C}zz\u{201D}.")
    }
}
