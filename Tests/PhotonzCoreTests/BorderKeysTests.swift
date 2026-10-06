import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A border's width and colour key like any other value
/// (task `a-border-s-width-and-colour-key-like-any-other-v`).
///
/// Written before the model. A border is an entry in the Effects list, and
/// until this none of its settings could change over time: a picture could not
/// grow a frame as it landed, and a title's outline could not change colour.
@Suite("Border keys")
struct BorderKeysTests {

    // MARK: - Fixtures

    /// Ten seconds, a title "Hello" with a black 2pt border round its letters,
    /// and a second title "World" with none.
    static func titles() -> (PhotonzDocument, bordered: UUID, plain: UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        var hello = Layer(name: "Hello",
                          content: .text(TextContent(string: "Hello", fontSize: 48)),
                          frame: CGRect(x: 100, y: 700, width: 400, height: 80))
        hello.time = LayerTime(inMS: 0, outMS: 10_000)
        hello.style.effects = [.border(BorderEffect(width: 2, colorHex: "#000000"))]
        var world = Layer(name: "World",
                          content: .text(TextContent(string: "World", fontSize: 48)),
                          frame: CGRect(x: 100, y: 500, width: 400, height: 80))
        world.time = LayerTime(inMS: 0, outMS: 10_000)
        doc.layers = [hello, world]
        doc.durationMS = 10_000
        return (doc, hello.id, world.id)
    }

    static func line() -> Layer {
        var line = Layer(name: "Line",
                         content: .annotation(AnnotationContent(shape: .line, strokeWidth: 3, colorHex: "#FF0000",
                                                                start: .zero, end: CGPoint(x: 100, y: 0))),
                         frame: CGRect(x: 10, y: 10, width: 100, height: 10))
        line.time = LayerTime(inMS: 0, outMS: 10_000)
        return line
    }

    static func posed(_ doc: PhotonzDocument, _ id: UUID, at ms: Int) -> Layer? {
        doc.drawn(atTimeMS: ms).layer(id: id)
    }

    static func number(_ value: MotionValue?) -> Double? {
        if case let .number(number)? = value { return number }
        return nil
    }

    static func rgb(_ hex: String?) -> (r: Double, g: Double, b: Double)? {
        guard let hex, let colour = RGBA(hex: hex) else { return nil }
        return (colour.r, colour.g, colour.b)
    }

    static let borderValues: [MotionProperty] = [.borderWidth, .borderColor]

    // MARK: - What is offered

    @Test func everyPictureLayerIsOfferedABordersWidthAndColour() {
        // The video mock's catalogue lists Border width (still at 0) and
        // Border color for every layer, as the app already does for a
        // shadow's size: keying the width up from nothing brings a ring in.
        let (doc, bordered, plain) = Self.titles()
        for id in [bordered, plain] {
            let offered = doc.layer(id: id)?.keyableProperties ?? []
            for property in Self.borderValues {
                #expect(offered.contains(.motion(property)), "\(property) offered")
            }
        }
        #expect(doc.keyedValue(layerID: plain, .motion(.borderWidth), atDocumentTimeMS: 0) == .number(0))
        // Sound has no picture to put a ring round.
        let sound = Layer(name: "Sound", content: .sound(SoundRef(durationMS: 10_000)), frame: .zero)
        for property in Self.borderValues {
            #expect(sound.keyableProperties.contains(.motion(property)) == false)
        }
    }

    @Test func keyingTheWidthUpFromNothingBringsARingInInsideTheEdge() throws {
        var (doc, _, plain) = Self.titles()
        doc.startKeying(layerID: plain, .motion(.borderWidth), atDocumentTimeMS: 0, ease: .linear)
        doc.setKeyedValue(.number(12), layerID: plain, .motion(.borderWidth), atDocumentTimeMS: 1000, ease: .linear)
        #expect(Self.posed(doc, plain, at: 0)?.style.paintedBorders.isEmpty == true)
        let ring = try #require(Self.posed(doc, plain, at: 1000)?.style.borderEffects.first)
        #expect(abs(ring.width - 12) < 0.01)
        // Inside, so a picture that fills the frame shows it.
        #expect(ring.position == .inside)
        // And a colour key paints the ring the width key brought in.
        doc.startKeying(layerID: plain, .motion(.borderColor), atDocumentTimeMS: 0)
        doc.setKeyedValue(.color("#FF0000"), layerID: plain, .motion(.borderColor), atDocumentTimeMS: 0)
        #expect(Self.posed(doc, plain, at: 1000)?.style.borderEffects.first?.colorHex.uppercased() == "#FF0000")
        // Nothing stored: the title still has no border of its own.
        #expect(doc.layer(id: plain)?.style.borderEffects.isEmpty == true)
    }

    @Test func aLinesOwnStrokeAndItsBorderAreTwoDifferentRows() {
        var line = Self.line()
        // A line with no border keys its own stroke; its border reads nothing.
        #expect(line.keyableProperties.contains(.motion(.strokeWidth)))
        #expect(MotionProperty.borderWidth.current(of: line) == nil)
        line.style.effects = [.border(BorderEffect(width: 6, colorHex: "#00FF00"))]
        #expect(line.keyableProperties.contains(.motion(.strokeWidth)))
        #expect(line.keyableProperties.contains(.motion(.borderWidth)))
        #expect(MotionProperty.strokeWidth.current(of: line) == .number(3))
        #expect(MotionProperty.borderWidth.current(of: line) == .number(6))
        #expect(MotionProperty.strokeWidth.title == "Stroke width")
        #expect(MotionProperty.borderWidth.title == "Border width")
    }

    @Test func theyAreNamedReadAndGroupedAsEffects() {
        #expect(MotionProperty.borderWidth.title == "Border width")
        #expect(MotionProperty.borderColor.title == "Border color")
        #expect(MotionProperty.borderWidth.isLength)
        #expect(MotionProperty.borderColor.isLength == false)
        #expect(MotionProperty.borderWidth.format(.number(12)) == "12 pt")
        #expect(MotionProperty.borderColor.format(.color("#4DA3FF")) == "#4DA3FF")
        for property in Self.borderValues {
            #expect(PropertyPicker.group(.motion(property)) == "Effects")
            #expect(MotionProperty.looks.contains(property), "\(property) is a look the panel edits")
        }
    }

    @Test func unkeyedTheyReadTheFirstBorderAsItIs() {
        var (doc, id, _) = Self.titles()
        // A shadow ahead of it in the list does not confuse which entry is read.
        doc.updateLayer(id: id) {
            $0.style.effects.insert(.glow(GlowEffect()), at: 0)
            $0.style.effects.append(.border(BorderEffect(width: 9, colorHex: "#FFFFFF")))
        }
        #expect(doc.keyedValue(layerID: id, .motion(.borderWidth), atDocumentTimeMS: 0) == .number(2))
        #expect(doc.keyedValue(layerID: id, .motion(.borderColor), atDocumentTimeMS: 0) == .color("#000000"))
    }

    // MARK: - Keys move the picture

    @Test func aBorderGrowsBetweenItsKeys() throws {
        var (doc, id, _) = Self.titles()
        doc.setKeyedValue(.number(0), layerID: id, .motion(.borderWidth), atDocumentTimeMS: 0)
        let started = doc.startKeying(layerID: id, .motion(.borderWidth), atDocumentTimeMS: 0)
        #expect(started)
        doc.setKeyedValue(.number(12), layerID: id, .motion(.borderWidth), atDocumentTimeMS: 1000)
        #expect(doc.keyCount(layerID: id, .motion(.borderWidth)) == 2)

        let early = try #require(Self.posed(doc, id, at: 0)?.style.borderEffects.first)
        let late = try #require(Self.posed(doc, id, at: 1000)?.style.borderEffects.first)
        let middle = try #require(Self.posed(doc, id, at: 500)?.style.borderEffects.first)
        #expect(early.width < 0.01)
        #expect(abs(late.width - 12) < 0.01)
        #expect(middle.width > 0.5 && middle.width < 11.5)
        // Everything else about the ring is left as it was drawn.
        #expect(late.colorHex == "#000000")
        #expect(late.follows == .letters)
        // Nothing baked in: the stored border is still the one set.
        #expect(doc.layer(id: id)?.style.borderEffects.first?.width == 0)
    }

    @Test func aBordersColourMovesSmoothlyBetweenItsKeys() throws {
        var (doc, id, _) = Self.titles()
        doc.startKeying(layerID: id, .motion(.borderColor), atDocumentTimeMS: 1000, ease: .linear)
        doc.setKeyedValue(.color("#FF0000"), layerID: id, .motion(.borderColor), atDocumentTimeMS: 3000, ease: .linear)
        let start = try #require(Self.rgb(Self.posed(doc, id, at: 1000)?.style.borderEffects.first?.colorHex))
        let end = try #require(Self.rgb(Self.posed(doc, id, at: 3000)?.style.borderEffects.first?.colorHex))
        let middle = try #require(Self.rgb(Self.posed(doc, id, at: 2000)?.style.borderEffects.first?.colorHex))
        #expect(start.r < 0.01)
        #expect(end.r > 0.99)
        #expect(middle.r > 0.2 && middle.r < 0.8, "half way, half red: \(middle.r)")
        #expect(middle.g < 0.01 && middle.b < 0.01)
        // The width is untouched.
        #expect(Self.posed(doc, id, at: 2000)?.style.borderEffects.first?.width == 2)
    }

    @Test func onlyTheFirstBorderIsKeyed() throws {
        var (doc, id, _) = Self.titles()
        doc.updateLayer(id: id) { $0.style.effects.append(.border(BorderEffect(width: 9, colorHex: "#FFFFFF"))) }
        doc.startKeying(layerID: id, .motion(.borderWidth), atDocumentTimeMS: 0)
        doc.setKeyedValue(.number(20), layerID: id, .motion(.borderWidth), atDocumentTimeMS: 0)
        let rings = try #require(Self.posed(doc, id, at: 0)?.style.borderEffects)
        #expect(rings.count == 2)
        #expect(abs(rings[0].width - 20) < 0.01)
        #expect(rings[1].width == 9)
    }

    @Test func aKeyedWidthPastTheEndsIsHeldToNoughtAndAbove() throws {
        var (doc, id, _) = Self.titles()
        doc.startKeying(layerID: id, .motion(.borderWidth), atDocumentTimeMS: 0)
        doc.setKeyedValue(.number(-5), layerID: id, .motion(.borderWidth), atDocumentTimeMS: 0)
        #expect(Self.posed(doc, id, at: 0)?.style.borderEffects.first?.width == 0)
    }

    @Test func aGrowthThickensTheBorderToo() throws {
        // The width is a length the growth multiplies, so a title grown to
        // twice its size wears its keyed border twice as thick, as it does
        // with an unkeyed one.
        var (doc, id, _) = Self.titles()
        doc.startKeying(layerID: id, .motion(.borderWidth), atDocumentTimeMS: 0)
        doc.setKeyedValue(.number(10), layerID: id, .motion(.borderWidth), atDocumentTimeMS: 0)
        doc.setKeyedValue(.number(200), layerID: id, .motion(.scale), atDocumentTimeMS: 0)
        let grown = try #require(Self.posed(doc, id, at: 0)?.style.borderEffects.first)
        #expect(abs(grown.width - 20) < 0.01)
    }

    // MARK: - The panel at a second moment

    @Test func changingAKeyedBorderInThePanelAtASecondMomentAddsAKey() throws {
        var (doc, id, _) = Self.titles()
        doc.startKeying(layerID: id, .motion(.borderWidth), atDocumentTimeMS: 1000)
        doc.startKeying(layerID: id, .motion(.borderColor), atDocumentTimeMS: 1000)
        // The Effects panel's own edits, as its Width slider and colour well
        // make them.
        doc.editLooks(layerIDs: [id], atDocumentTimeMS: 3000) { document in
            document.updateLayer(id: id) { layer in
                layer.style.updateBorderEffect(at: 0) {
                    $0.width = 12
                    $0.colorHex = "#FF0000"
                }
            }
        }
        #expect(doc.keyCount(layerID: id, .motion(.borderWidth)) == 2)
        #expect(doc.keyCount(layerID: id, .motion(.borderColor)) == 2)
        #expect(doc.keyedValue(layerID: id, .motion(.borderWidth), atDocumentTimeMS: 3000) == .number(12))
        #expect(doc.keyedValue(layerID: id, .motion(.borderColor), atDocumentTimeMS: 3000) == .color("#FF0000"))
        #expect(doc.keyedValue(layerID: id, .motion(.borderColor), atDocumentTimeMS: 1000) == .color("#000000"))
        let stored = try #require(doc.layer(id: id)?.style.borderEffects.first)
        #expect(stored.width == 2)
        #expect(stored.colorHex == "#000000")
    }

    @Test func thePanelReadsAKeyedBorderAtThePlayhead() throws {
        var (doc, id, _) = Self.titles()
        doc.startKeying(layerID: id, .motion(.borderWidth), atDocumentTimeMS: 0, ease: .linear)
        doc.setKeyedValue(.number(22), layerID: id, .motion(.borderWidth), atDocumentTimeMS: 2000)
        let reading = try #require(doc.lookPosed(layerIDs: [id], atDocumentTimeMS: 1000)
            .layer(id: id)?.style.borderEffects.first)
        #expect(reading.width > 2.5 && reading.width < 21.5)
    }

    // MARK: - Lanes, easing, copy and paste

    @Test func eachKeyedValueHasItsOwnLaneAndTakesAnEase() throws {
        var (doc, id, _) = Self.titles()
        for property in Self.borderValues {
            doc.startKeying(layerID: id, .motion(property), atDocumentTimeMS: 1000)
        }
        let lanes = doc.keyLanes(layerID: id)
        for property in Self.borderValues {
            #expect(lanes.contains { $0.property == property }, "\(property) has a lane")
        }
        let width = try #require(lanes.first { $0.property == .borderWidth })
        doc.easeKeys(layerID: id, Set(width.keys.map(\.ref)), .hold)
        #expect(doc.layer(id: id)?.keyedMotion(.borderWidth)?.keyframes.first?.ease == .hold)
    }

    @Test func copiedBorderKeysPasteOntoAnotherTitle() throws {
        var (doc, from, plain) = Self.titles()
        doc.startKeying(layerID: from, .motion(.borderWidth), atDocumentTimeMS: 1000)
        doc.setKeyedValue(.number(12), layerID: from, .motion(.borderWidth), atDocumentTimeMS: 3000)
        let lane = try #require(doc.keyLanes(layerID: from).first { $0.property == .borderWidth })
        let copied = try #require(doc.copyKeys(layerID: from, Set(lane.keys.map(\.ref))))
        #expect(copied.properties == [.borderWidth])
        // Any picture can take them, as with a shadow's size: they bring a
        // ring in where there is none.
        #expect(doc.canPasteKeys(copied, layerID: plain))
        let landed = doc.pasteKeys(copied, layerID: plain, atDocumentMS: 5000)
        #expect(landed.count == 2)
        #expect(doc.keyedValue(layerID: plain, .motion(.borderWidth), atDocumentTimeMS: 7000) == .number(12))
    }

    @Test func theyRoundTripThroughTheFile() throws {
        var (doc, id, _) = Self.titles()
        doc.startKeying(layerID: id, .motion(.borderWidth), atDocumentTimeMS: 0)
        doc.startKeying(layerID: id, .motion(.borderColor), atDocumentTimeMS: 0)
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.layer(id: id)?.keyedMotion(.borderWidth) != nil)
        #expect(back.layer(id: id)?.keyedMotion(.borderColor) != nil)
    }
}
