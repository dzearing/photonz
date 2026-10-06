import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A shadow's distance, direction, colour and opacity and a glow's colour and
/// opacity key like their size (task `a-shadow-s-offset-colour-and-softness-and-a-glow`).
///
/// Written before the model. Until this, only the SIZE of a shadow or a glow
/// could take keys, so a title could not lift off the page with a shadow
/// thrown further and further, or warm its glow from blue to orange.
@Suite("Shadow and glow keys")
struct ShadowGlowKeysTests {

    // MARK: - Fixtures

    /// Ten seconds, a title "Hello" with a drop shadow thrown 4 straight down
    /// (black, 40%), and a second title "World" with none.
    static func titles() -> (PhotonzDocument, shadowed: UUID, plain: UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        var hello = Layer(name: "Hello",
                          content: .text(TextContent(string: "Hello", fontSize: 48)),
                          frame: CGRect(x: 100, y: 700, width: 400, height: 80))
        hello.time = LayerTime(inMS: 0, outMS: 10_000)
        hello.style.shadows = [ShadowStyle(radius: 6, offset: CGSize(width: 0, height: 4),
                                           colorHex: "#000000", opacity: 0.4)]
        var world = Layer(name: "World",
                          content: .text(TextContent(string: "World", fontSize: 48)),
                          frame: CGRect(x: 100, y: 500, width: 400, height: 80))
        world.time = LayerTime(inMS: 0, outMS: 10_000)
        doc.layers = [hello, world]
        doc.durationMS = 10_000
        return (doc, hello.id, world.id)
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

    static let shadowValues: [MotionProperty] = [.shadowDistance, .shadowDirection, .shadowColor, .shadowOpacity]
    static let glowValues: [MotionProperty] = [.glowColor, .glowOpacity]

    // MARK: - What is offered

    @Test func aShadowOffersItsDistanceDirectionColourAndOpacity() {
        let (doc, shadowed, plain) = Self.titles()
        let offered = doc.layer(id: shadowed)?.keyableProperties ?? []
        for property in Self.shadowValues {
            #expect(offered.contains(.motion(property)), "\(property) offered on a shadowed title")
        }
        // A layer with no shadow is offered its size (a key brings one in),
        // and nothing about a shadow it has not got.
        let none = doc.layer(id: plain)?.keyableProperties ?? []
        #expect(none.contains(.motion(.shadow)))
        for property in Self.shadowValues {
            #expect(none.contains(.motion(property)) == false)
        }
    }

    @Test func aGlowOffersItsColourAndOpacityOnlyWhereThereIsOne() {
        var (doc, _, plain) = Self.titles()
        for property in Self.glowValues {
            #expect((doc.layer(id: plain)?.keyableProperties ?? []).contains(.motion(property)) == false)
        }
        doc.updateLayer(id: plain) { $0.style.effects.append(.glow(GlowEffect())) }
        let offered = doc.layer(id: plain)?.keyableProperties ?? []
        for property in Self.glowValues {
            #expect(offered.contains(.motion(property)))
        }
    }

    @Test func theyAreNamedReadAndGroupedAsEffects() {
        #expect(MotionProperty.shadowDistance.title == "Shadow distance")
        #expect(MotionProperty.shadowDirection.title == "Shadow direction")
        #expect(MotionProperty.shadowColor.title == "Shadow color")
        #expect(MotionProperty.shadowOpacity.title == "Shadow opacity")
        #expect(MotionProperty.glowColor.title == "Glow color")
        #expect(MotionProperty.glowOpacity.title == "Glow opacity")
        #expect(MotionProperty.shadowDistance.isLength)
        #expect(MotionProperty.shadowOpacity.isLength == false)
        #expect(MotionProperty.shadowDistance.format(.number(12)) == "12 pt")
        #expect(MotionProperty.shadowDirection.format(.number(90)) == "90°")
        #expect(MotionProperty.shadowOpacity.format(.number(40)) == "40%")
        #expect(MotionProperty.glowOpacity.format(.number(90)) == "90%")
        #expect(MotionProperty.glowColor.format(.color("#4DA3FF")) == "#4DA3FF")
        for property in Self.shadowValues + Self.glowValues {
            #expect(PropertyPicker.group(.motion(property)) == "Effects")
            #expect(MotionProperty.looks.contains(property), "\(property) is a look the panel edits")
        }
    }

    @Test func unkeyedTheyReadTheShadowAndGlowAsTheyAre() {
        var (doc, shadowed, _) = Self.titles()
        doc.updateLayer(id: shadowed) { $0.style.effects.append(.glow(GlowEffect())) }
        #expect(doc.keyedValue(layerID: shadowed, .motion(.shadowDistance), atDocumentTimeMS: 0) == .number(4))
        #expect(doc.keyedValue(layerID: shadowed, .motion(.shadowDirection), atDocumentTimeMS: 0) == .number(90))
        #expect(doc.keyedValue(layerID: shadowed, .motion(.shadowColor), atDocumentTimeMS: 0) == .color("#000000"))
        #expect(doc.keyedValue(layerID: shadowed, .motion(.shadowOpacity), atDocumentTimeMS: 0) == .number(40))
        #expect(doc.keyedValue(layerID: shadowed, .motion(.glowColor), atDocumentTimeMS: 0)
                == .color(GlowEffect.startingColorHex))
        let glowOpacity = Self.number(doc.keyedValue(layerID: shadowed, .motion(.glowOpacity), atDocumentTimeMS: 0))
        #expect(abs((glowOpacity ?? 0) - GlowEffect.startingOpacity * 100) < 0.001)
    }

    // MARK: - Keys move the picture

    @Test func aShadowThrownFurtherLiftsTheTitleOffThePage() throws {
        var (doc, id, _) = Self.titles()
        doc.setKeyedValue(.number(2), layerID: id, .motion(.shadowDistance), atDocumentTimeMS: 0)
        let started = doc.startKeying(layerID: id, .motion(.shadowDistance), atDocumentTimeMS: 1000)
        #expect(started)
        doc.setKeyedValue(.number(30), layerID: id, .motion(.shadowDistance), atDocumentTimeMS: 3000)
        #expect(doc.keyCount(layerID: id, .motion(.shadowDistance)) == 2)

        let early = try #require(Self.posed(doc, id, at: 1000)?.style.shadows.first)
        let late = try #require(Self.posed(doc, id, at: 3000)?.style.shadows.first)
        let middle = try #require(Self.posed(doc, id, at: 2000)?.style.shadows.first)
        #expect(abs(early.distance - 2) < 0.01)
        #expect(abs(late.distance - 30) < 0.01)
        #expect(middle.distance > 2.5 && middle.distance < 29.5)
        // Thrown the way it already pointed: straight down.
        #expect(abs(late.offset.width) < 0.01)
        #expect(abs(late.offset.height - 30) < 0.01)
        // Nothing baked in: the stored shadow is still the one typed.
        #expect(abs((doc.layer(id: id)?.style.shadows.first?.distance ?? 0) - 2) < 0.01)
    }

    @Test func aShadowTurnsAboutTheTitleKeepingItsDistance() throws {
        var (doc, id, _) = Self.titles()
        doc.startKeying(layerID: id, .motion(.shadowDirection), atDocumentTimeMS: 0)
        doc.setKeyedValue(.number(0), layerID: id, .motion(.shadowDirection), atDocumentTimeMS: 2000)
        let late = try #require(Self.posed(doc, id, at: 2000)?.style.shadows.first)
        #expect(abs(late.offset.width - 4) < 0.01)
        #expect(abs(late.offset.height) < 0.01)
    }

    @Test func aShadowsColourMovesSmoothlyBetweenItsKeys() throws {
        var (doc, id, _) = Self.titles()
        doc.startKeying(layerID: id, .motion(.shadowColor), atDocumentTimeMS: 1000, ease: .linear)
        doc.setKeyedValue(.color("#FF0000"), layerID: id, .motion(.shadowColor), atDocumentTimeMS: 3000, ease: .linear)
        let start = try #require(Self.rgb(Self.posed(doc, id, at: 1000)?.style.shadows.first?.colorHex))
        let end = try #require(Self.rgb(Self.posed(doc, id, at: 3000)?.style.shadows.first?.colorHex))
        let middle = try #require(Self.rgb(Self.posed(doc, id, at: 2000)?.style.shadows.first?.colorHex))
        #expect(start.r < 0.01)
        #expect(end.r > 0.99)
        #expect(middle.r > 0.2 && middle.r < 0.8, "half way, half red: \(middle.r)")
        #expect(middle.g < 0.01 && middle.b < 0.01)
    }

    @Test func aShadowsOpacityFades() throws {
        var (doc, id, _) = Self.titles()
        doc.startKeying(layerID: id, .motion(.shadowOpacity), atDocumentTimeMS: 0)
        doc.setKeyedValue(.number(100), layerID: id, .motion(.shadowOpacity), atDocumentTimeMS: 2000)
        let end = try #require(Self.posed(doc, id, at: 2000)?.style.shadows.first)
        let middle = try #require(Self.posed(doc, id, at: 1000)?.style.shadows.first)
        #expect(abs(end.opacity - 1) < 0.001)
        #expect(middle.opacity > 0.4 && middle.opacity < 1)
        // A typed opacity past either end is held to it.
        doc.setKeyedValue(.number(140), layerID: id, .motion(.shadowOpacity), atDocumentTimeMS: 2000)
        #expect(Self.posed(doc, id, at: 2000)?.style.shadows.first?.opacity == 1)
    }

    @Test func aGlowChangesColourAndFades() throws {
        var (doc, id, _) = Self.titles()
        doc.updateLayer(id: id) { $0.style.effects.append(.glow(GlowEffect(colorHex: "#0000FF", opacity: 1))) }
        doc.startKeying(layerID: id, .motion(.glowColor), atDocumentTimeMS: 0, ease: .linear)
        doc.setKeyedValue(.color("#FF8000"), layerID: id, .motion(.glowColor), atDocumentTimeMS: 2000, ease: .linear)
        doc.startKeying(layerID: id, .motion(.glowOpacity), atDocumentTimeMS: 0)
        doc.setKeyedValue(.number(0), layerID: id, .motion(.glowOpacity), atDocumentTimeMS: 2000)

        let end = try #require(Self.posed(doc, id, at: 2000)?.style.glowEffects.first)
        #expect(end.colorHex.uppercased() == "#FF8000")
        #expect(end.opacity == 0)
        let middle = try #require(Self.posed(doc, id, at: 1000)?.style.glowEffects.first)
        let mix = try #require(Self.rgb(middle.colorHex))
        #expect(mix.r > 0.2 && mix.r < 0.8)
        #expect(mix.b > 0.2 && mix.b < 0.8)
        #expect(middle.opacity > 0 && middle.opacity < 1)
        // The glow's own size and softness are untouched.
        #expect(middle.size == GlowEffect.startingSize)
        #expect(middle.radius == GlowEffect.startingRadius)
    }

    @Test func aGrowthThrowsTheShadowFurtherToo() throws {
        // The distance is a length the growth multiplies, so a title grown to
        // twice its size throws its keyed shadow twice as far, as it does with
        // an unkeyed one.
        var (doc, id, _) = Self.titles()
        doc.startKeying(layerID: id, .motion(.shadowDistance), atDocumentTimeMS: 0)
        doc.setKeyedValue(.number(10), layerID: id, .motion(.shadowDistance), atDocumentTimeMS: 0)
        doc.setKeyedValue(.number(200), layerID: id, .motion(.scale), atDocumentTimeMS: 0)
        let grown = try #require(Self.posed(doc, id, at: 0)?.style.shadows.first)
        #expect(abs(grown.distance - 20) < 0.01)
    }

    // MARK: - The panel at a second moment

    @Test func changingAKeyedShadowInThePanelAtASecondMomentAddsAKey() throws {
        var (doc, id, _) = Self.titles()
        doc.startKeying(layerID: id, .motion(.shadowDistance), atDocumentTimeMS: 1000)
        doc.startKeying(layerID: id, .motion(.shadowColor), atDocumentTimeMS: 1000)
        doc.startKeying(layerID: id, .motion(.shadowOpacity), atDocumentTimeMS: 1000)
        // The Effects panel's own edits, as its Distance, colour well and
        // Opacity slider make them.
        doc.editLooks(layerIDs: [id], atDocumentTimeMS: 3000) { document in
            document.updateLayer(id: id) { layer in
                layer.style.updateShadow(at: 0) {
                    $0.setDistance(30)
                    $0.colorHex = "#FF0000"
                    $0.opacity = 1
                }
            }
        }
        #expect(doc.keyCount(layerID: id, .motion(.shadowDistance)) == 2)
        #expect(doc.keyCount(layerID: id, .motion(.shadowColor)) == 2)
        #expect(doc.keyCount(layerID: id, .motion(.shadowOpacity)) == 2)
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.shadowDistance), atDocumentTimeMS: 3000))
                .map { abs($0 - 30) < 0.01 } == true)
        #expect(doc.keyedValue(layerID: id, .motion(.shadowColor), atDocumentTimeMS: 3000) == .color("#FF0000"))
        #expect(doc.keyedValue(layerID: id, .motion(.shadowOpacity), atDocumentTimeMS: 3000) == .number(100))
        // The first key still holds what the shadow was, and the layer keeps
        // its own shadow underneath.
        #expect(doc.keyedValue(layerID: id, .motion(.shadowColor), atDocumentTimeMS: 1000) == .color("#000000"))
        let stored = try #require(doc.layer(id: id)?.style.shadows.first)
        #expect(abs(stored.distance - 4) < 0.01)
        #expect(stored.colorHex == "#000000")
        #expect(abs(stored.opacity - 0.4) < 0.001)
    }

    @Test func thePanelReadsAKeyedShadowAtThePlayhead() throws {
        var (doc, id, _) = Self.titles()
        doc.startKeying(layerID: id, .motion(.shadowDistance), atDocumentTimeMS: 0, ease: .linear)
        doc.setKeyedValue(.number(24), layerID: id, .motion(.shadowDistance), atDocumentTimeMS: 2000)
        let reading = try #require(doc.lookPosed(layerIDs: [id], atDocumentTimeMS: 1000)
            .layer(id: id)?.style.shadows.first)
        #expect(reading.distance > 4.5 && reading.distance < 23.5)
    }

    // MARK: - Lanes, easing, copy and paste

    @Test func eachKeyedValueHasItsOwnLaneAndTakesAnEase() throws {
        var (doc, id, _) = Self.titles()
        doc.updateLayer(id: id) { $0.style.effects.append(.glow(GlowEffect())) }
        for property in Self.shadowValues + Self.glowValues {
            doc.startKeying(layerID: id, .motion(property), atDocumentTimeMS: 1000)
        }
        let lanes = doc.keyLanes(layerID: id)
        for property in Self.shadowValues + Self.glowValues {
            #expect(lanes.contains { $0.property == property }, "\(property) has a lane")
        }
        let distance = try #require(lanes.first { $0.property == .shadowDistance })
        doc.easeKeys(layerID: id, Set(distance.keys.map(\.ref)), .hold)
        #expect(doc.layer(id: id)?.keyedMotion(.shadowDistance)?.keyframes.first?.ease == .hold)
    }

    @Test func copiedShadowKeysPasteOntoAnotherLayerWithAShadowAndNotOneWithout() throws {
        var (doc, from, plain) = Self.titles()
        doc.startKeying(layerID: from, .motion(.shadowColor), atDocumentTimeMS: 1000)
        doc.setKeyedValue(.color("#FF0000"), layerID: from, .motion(.shadowColor), atDocumentTimeMS: 3000)
        let lane = try #require(doc.keyLanes(layerID: from).first { $0.property == .shadowColor })
        let copied = try #require(doc.copyKeys(layerID: from, Set(lane.keys.map(\.ref))))
        #expect(copied.properties == [.shadowColor])
        #expect(doc.canPasteKeys(copied, layerID: plain) == false)

        doc.updateLayer(id: plain) { $0.style.shadows = [ShadowStyle()] }
        #expect(doc.canPasteKeys(copied, layerID: plain))
        let landed = doc.pasteKeys(copied, layerID: plain, atDocumentMS: 5000)
        #expect(landed.count == 2)
        #expect(doc.keyedValue(layerID: plain, .motion(.shadowColor), atDocumentTimeMS: 5000) == .color("#000000"))
        #expect(doc.keyedValue(layerID: plain, .motion(.shadowColor), atDocumentTimeMS: 7000) == .color("#FF0000"))
    }

    @Test func theyRoundTripThroughTheFile() throws {
        var (doc, id, _) = Self.titles()
        doc.startKeying(layerID: id, .motion(.shadowDistance), atDocumentTimeMS: 0)
        doc.startKeying(layerID: id, .motion(.shadowColor), atDocumentTimeMS: 0)
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.layer(id: id)?.keyedMotion(.shadowDistance) != nil)
        #expect(back.layer(id: id)?.keyedMotion(.shadowColor) != nil)
    }
}
