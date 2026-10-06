import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Keys on a layer with several shadows move the shadow you picked
/// (task `keys-on-a-layer-with-several-shadows-move-the-sh`).
///
/// Written before the model. A title comes with two shadows and Add Effect
/// puts a third at the foot of its Effects list, yet every shadow key moved
/// only the FIRST shadow: someone who added a shadow and keyed its distance
/// saw a different shadow move and their own stay put. Glows and borders
/// had the same fault. A keyed effect value now says which of its kind it
/// belongs to, counting from the first, and a document saved before it says
/// nothing, which is the first, so it plays exactly as it did.
@Suite("Keys on several shadows, glows and borders")
struct KeysOnSeveralEffectsTests {

    // MARK: - Fixtures

    /// Ten seconds and a title with three shadows, thrown 2, 4 and 6 down.
    static func title() -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        var title = Layer(name: "Hello",
                          content: .text(TextContent(string: "Hello", fontSize: 48)),
                          frame: CGRect(x: 100, y: 700, width: 400, height: 80))
        title.time = LayerTime(inMS: 0, outMS: 10_000)
        title.style.shadows = [2, 4, 6].map {
            ShadowStyle(radius: 3, offset: CGSize(width: 0, height: $0), colorHex: "#000000", opacity: 0.4)
        }
        doc.layers = [title]
        doc.durationMS = 10_000
        return (doc, title.id)
    }

    static func shadows(_ doc: PhotonzDocument, _ id: UUID, at ms: Int) -> [ShadowStyle] {
        doc.drawn(atTimeMS: ms).layer(id: id)?.style.shadows ?? []
    }

    static func distances(_ doc: PhotonzDocument, _ id: UUID, at ms: Int) -> [Double] {
        shadows(doc, id, at: ms).map { (Double($0.distance) * 100).rounded() / 100 }
    }

    // MARK: - What is offered, and what it is called

    @Test func everyShadowOffersItsOwnValues() {
        let (doc, id) = Self.title()
        let offered = doc.layer(id: id)?.keyableProperties ?? []
        for effect in 0..<3 {
            for property: MotionProperty in [.shadow, .shadowDistance, .shadowDirection, .shadowColor, .shadowOpacity] {
                #expect(offered.contains(.motion(property, effect: effect)), "\(property) of shadow \(effect + 1)")
            }
        }
        #expect(offered.contains(.motion(.shadowDistance, effect: 3)) == false)
        // The first shadow is the one every key before this meant.
        #expect(KeyedProperty.motion(.shadowDistance) == .motion(.shadowDistance, effect: 0))
    }

    @Test func eachValueSaysWhichShadowItBelongsTo() throws {
        let (doc, id) = Self.title()
        let layer = try #require(doc.layer(id: id))
        #expect(KeyedProperty.motion(.shadowDistance, effect: 2).title(on: layer) == "Shadow 3 distance")
        #expect(KeyedProperty.motion(.shadow, effect: 1).title(on: layer) == "Shadow 2 size")
        #expect(KeyedProperty.motion(.shadowColor, effect: 0).title(on: layer) == "Shadow 1 color")
        #expect(KeyedProperty.motion(.opacity).title(on: layer) == "Opacity")
        // A lone shadow is simply the shadow, the way its Effects row reads.
        var lone = layer
        lone.style.shadows = [ShadowStyle(radius: 3)]
        #expect(KeyedProperty.motion(.shadowDistance).title(on: lone) == "Shadow distance")
        #expect(KeyedProperty.motion(.shadow).title(on: lone) == "Shadow size")
    }

    @Test func glowsAndBordersAreNumberedTheSameWay() throws {
        var (doc, id) = Self.title()
        doc.updateLayer(id: id) { layer in
            layer.style.effects.append(.glow(GlowEffect()))
            layer.style.effects.append(.glow(GlowEffect()))
            layer.style.effects.append(.border(BorderEffect(width: 2, position: .inside)))
            layer.style.effects.append(.border(BorderEffect(width: 4, position: .outside)))
        }
        let layer = try #require(doc.layer(id: id))
        #expect(layer.keyableProperties.contains(.motion(.glowColor, effect: 1)))
        #expect(layer.keyableProperties.contains(.motion(.borderWidth, effect: 1)))
        #expect(layer.keyableProperties.contains(.motion(.borderWidth, effect: 2)) == false)
        #expect(KeyedProperty.motion(.glowColor, effect: 1).title(on: layer) == "Glow 2 color")
        #expect(KeyedProperty.motion(.glow, effect: 0).title(on: layer) == "Glow 1 size")
        #expect(KeyedProperty.motion(.borderWidth, effect: 1).title(on: layer) == "Border 2 width")
    }

    @Test func thePickerFindsAShadowByItsNumber() throws {
        let (doc, id) = Self.title()
        let layer = try #require(doc.layer(id: id))
        let groups = PropertyPicker.groups(all: layer.keyableProperties, keyed: [], query: "shadow 3",
                                           title: { $0.title(on: layer) })
        let found = groups.flatMap(\.properties)
        #expect(found.count == 5)
        #expect(found.allSatisfy {
            if case let .motion(_, effect) = $0 { return effect == 2 }
            return false
        })
    }

    // MARK: - Keys move the shadow you picked

    @Test func keyingShadowThreesDistanceMovesShadowThreeOnly() {
        var (doc, id) = Self.title()
        let third = KeyedProperty.motion(.shadowDistance, effect: 2)
        #expect(doc.keyedValue(layerID: id, third, atDocumentTimeMS: 0) == .number(6))
        let started = doc.startKeying(layerID: id, third, atDocumentTimeMS: 0)
        #expect(started)
        doc.setKeyedValue(.number(30), layerID: id, third, atDocumentTimeMS: 1000)
        #expect(Self.distances(doc, id, at: 0) == [2, 4, 6])
        #expect(Self.distances(doc, id, at: 1000) == [2, 4, 30])
        let between = Self.distances(doc, id, at: 500)
        #expect(between.prefix(2) == [2, 4])
        #expect(between.count == 3 && between[2] > 6 && between[2] < 30)
        // Its own diamond, and nobody else's.
        #expect(doc.keyCount(layerID: id, third) == 2)
        #expect(doc.keyCount(layerID: id, .motion(.shadowDistance)) == 0)
        #expect(doc.keyDiamond(layerID: id, .motion(.shadowDistance), atDocumentTimeMS: 1000) == .dormant)
        // The stored title keeps its own shadows.
        #expect(doc.layer(id: id)?.style.shadows.map(\.distance) == [2, 4, 6])
    }

    @Test func twoShadowsKeyedAtOnceEachKeepTheirOwnKeys() {
        var (doc, id) = Self.title()
        let first = KeyedProperty.motion(.shadowOpacity, effect: 0)
        let third = KeyedProperty.motion(.shadowOpacity, effect: 2)
        doc.startKeying(layerID: id, first, atDocumentTimeMS: 0)
        doc.startKeying(layerID: id, third, atDocumentTimeMS: 0)
        doc.setKeyedValue(.number(0), layerID: id, first, atDocumentTimeMS: 1000)
        doc.setKeyedValue(.number(100), layerID: id, third, atDocumentTimeMS: 1000)
        let late = Self.shadows(doc, id, at: 1000).map { ($0.opacity * 100).rounded() }
        #expect(late == [0, 40, 100])
        #expect(doc.layer(id: id)?.motions?.count == 2)
    }

    @Test func aSizeKeyOnALaterShadowNeverBringsInAnother() {
        var (doc, id) = Self.title()
        doc.updateLayer(id: id) { $0.style.shadows = [] }
        // Only the first can be brought in by a key; nothing to address after it.
        #expect(doc.layer(id: id)?.keyableProperties.contains(.motion(.shadow)) == true)
        #expect(doc.layer(id: id)?.keyableProperties.contains(.motion(.shadow, effect: 1)) == false)
        let started = doc.startKeying(layerID: id, .motion(.shadow, effect: 1), atDocumentTimeMS: 0)
        #expect(started == false)
    }

    @Test func stoppingKeysOnShadowThreeLeavesItsValueOnShadowThree() {
        var (doc, id) = Self.title()
        let third = KeyedProperty.motion(.shadowDistance, effect: 2)
        doc.startKeying(layerID: id, third, atDocumentTimeMS: 0)
        doc.setKeyedValue(.number(30), layerID: id, third, atDocumentTimeMS: 1000)
        let stopped = doc.stopKeying(layerID: id, third, atDocumentTimeMS: 1000)
        #expect(stopped)
        #expect(doc.layer(id: id)?.style.shadows.map(\.distance) == [2, 4, 30])
        #expect(doc.layer(id: id)?.motions == nil)
    }

    // MARK: - The Effects list at a second moment

    @Test func changingAKeyedLaterShadowInTheListAddsAKeyToThatShadow() {
        var (doc, id) = Self.title()
        let third = KeyedProperty.motion(.shadowDistance, effect: 2)
        doc.startKeying(layerID: id, third, atDocumentTimeMS: 0)
        // At two seconds, the Effects list's Shadow 3 Distance is dragged to 50.
        doc.editLooks(layerIDs: [id], atDocumentTimeMS: 2000) { document in
            document.updateLayer(id: id) { $0.style.updateShadow(at: 2) { $0.setDistance(50) } }
        }
        #expect(doc.keyCount(layerID: id, third) == 2)
        #expect(doc.keyCount(layerID: id, .motion(.shadowDistance)) == 0)
        #expect(Self.distances(doc, id, at: 2000) == [2, 4, 50])
        #expect(Self.distances(doc, id, at: 0) == [2, 4, 6])
        #expect(doc.layer(id: id)?.style.shadows.map(\.distance) == [2, 4, 6])
    }

    @Test func theListReadsALaterShadowAtThePlayhead() {
        var (doc, id) = Self.title()
        let third = KeyedProperty.motion(.shadowDistance, effect: 2)
        doc.startKeying(layerID: id, third, atDocumentTimeMS: 0)
        doc.setKeyedValue(.number(30), layerID: id, third, atDocumentTimeMS: 1000)
        let posed = doc.lookPosed(layerIDs: [id], atDocumentTimeMS: 1000).layer(id: id)
        #expect(posed?.style.shadows.map(\.distance) == [2, 4, 30])
    }

    @Test func aSecondBorderKeysItsOwnWidth() {
        var (doc, id) = Self.title()
        doc.updateLayer(id: id) { layer in
            layer.style.effects.append(.border(BorderEffect(width: 2, position: .inside)))
            layer.style.effects.append(.border(BorderEffect(width: 4, position: .outside)))
        }
        let second = KeyedProperty.motion(.borderWidth, effect: 1)
        doc.startKeying(layerID: id, second, atDocumentTimeMS: 0)
        doc.setKeyedValue(.number(12), layerID: id, second, atDocumentTimeMS: 1000)
        let widths = doc.drawn(atTimeMS: 1000).layer(id: id)?.style.borderEffects.map(\.width)
        #expect(widths == [2, 12])
    }

    @Test func aSecondGlowKeysItsOwnColour() {
        var (doc, id) = Self.title()
        doc.updateLayer(id: id) { layer in
            layer.style.effects.append(.glow(GlowEffect()))
            layer.style.effects.append(.glow(GlowEffect()))
        }
        let second = KeyedProperty.motion(.glowColor, effect: 1)
        doc.startKeying(layerID: id, second, atDocumentTimeMS: 0)
        doc.setKeyedValue(.color("#FF8800"), layerID: id, second, atDocumentTimeMS: 1000)
        let colours = doc.drawn(atTimeMS: 1000).layer(id: id)?.style.glowEffects.map(\.colorHex)
        #expect(colours == [GlowEffect.startingColorHex, "#FF8800"])
    }

    // MARK: - Keys travel with their shadow

    @Test func removingAnEarlierShadowCarriesTheKeysWithTheirShadow() {
        var (doc, id) = Self.title()
        let third = KeyedProperty.motion(.shadowDistance, effect: 2)
        doc.startKeying(layerID: id, third, atDocumentTimeMS: 0)
        doc.setKeyedValue(.number(30), layerID: id, third, atDocumentTimeMS: 1000)
        // Shadow 1 is taken out: the keyed shadow is now the second.
        doc.removeEffect(layerIDs: [id], at: 0)
        #expect(doc.keyCount(layerID: id, .motion(.shadowDistance, effect: 1)) == 2)
        #expect(Self.distances(doc, id, at: 1000) == [4, 30])
    }

    @Test func removingTheKeyedShadowTakesItsKeysWithIt() {
        var (doc, id) = Self.title()
        let third = KeyedProperty.motion(.shadowDistance, effect: 2)
        doc.startKeying(layerID: id, third, atDocumentTimeMS: 0)
        doc.removeEffect(layerIDs: [id], at: 2)
        #expect(doc.layer(id: id)?.motions == nil)
    }

    @Test func draggingAShadowUpTheListCarriesItsKeys() {
        var (doc, id) = Self.title()
        let third = KeyedProperty.motion(.shadowDistance, effect: 2)
        doc.startKeying(layerID: id, third, atDocumentTimeMS: 0)
        doc.setKeyedValue(.number(30), layerID: id, third, atDocumentTimeMS: 1000)
        doc.moveEffect(layerIDs: [id], from: 2, to: 0)
        #expect(doc.keyCount(layerID: id, .motion(.shadowDistance, effect: 0)) == 2)
        #expect(Self.distances(doc, id, at: 1000) == [30, 2, 4])
    }

    // MARK: - Lanes and the stretch between keys

    @Test func aLaneSaysWhichShadowItKeys() {
        var (doc, id) = Self.title()
        doc.startKeying(layerID: id, .motion(.shadowDistance, effect: 2), atDocumentTimeMS: 0)
        #expect(doc.keyLanes(layerID: id).map(\.title) == ["Shadow 3 distance"])
    }

    @Test func theStretchCurveIsShadowThreesOwn() {
        var (doc, id) = Self.title()
        let third = KeyedProperty.motion(.shadowDistance, effect: 2)
        doc.startKeying(layerID: id, third, atDocumentTimeMS: 0)
        doc.setKeyedValue(.number(30), layerID: id, third, atDocumentTimeMS: 1000)
        #expect(doc.stretchCurve(layerID: id, .shadowDistance, atDocumentTimeMS: 500) == nil)
        #expect(doc.stretchCurve(layerID: id, .shadowDistance, effect: 2, atDocumentTimeMS: 500) != nil)
        doc.curveStretch(layerID: id, .shadowDistance, effect: 2, atDocumentTimeMS: 500, .linear)
        #expect(doc.stretchCurve(layerID: id, .shadowDistance, effect: 2, atDocumentTimeMS: 500) == .linear)
    }

    // MARK: - Saved documents

    @Test func aKeyWrittenBeforeThisStillMovesTheFirstShadow() throws {
        let (doc, id) = Self.title()
        var made = LayerMotion.keyed(.shadowDistance, atMS: 0, value: .number(2))
        made = made.settingKey(atMS: 1000, value: .number(20))
        let data = try JSONEncoder().encode(made)
        let json = try #require(String(data: data, encoding: .utf8))
        // Nothing new is written for the first shadow...
        #expect(json.contains("effect") == false)
        // ...so a file from before reads back as the first shadow's keys.
        let read = try JSONDecoder().decode(LayerMotion.self, from: data)
        #expect(read.effect == nil)
        var saved = doc
        saved.updateLayer(id: id) { $0.motions = [read] }
        #expect(Self.distances(saved, id, at: 1000) == [20, 4, 6])
    }

    @Test func aLaterShadowsKeysSurviveSaving() throws {
        var (doc, id) = Self.title()
        let third = KeyedProperty.motion(.shadowDistance, effect: 2)
        doc.startKeying(layerID: id, third, atDocumentTimeMS: 0)
        let motion = try #require(doc.layer(id: id)?.motions?.first)
        let read = try JSONDecoder().decode(LayerMotion.self, from: JSONEncoder().encode(motion))
        #expect(read.effect == 2)
        #expect(read == motion)
    }
}
