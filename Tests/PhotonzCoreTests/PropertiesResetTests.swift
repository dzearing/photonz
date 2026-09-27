import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Reset to Defaults on the Properties menu (task
/// `the-properties-menu-puts-a-clip-back-the-way-it`, `video.html` `#propMenu`).
///
/// Written before the model. Premiere's Reset on Motion and Opacity, said in
/// this app's model: every key goes, the turn and the fade go, and the layer
/// sits at the place and size it holds without keys, which for a keyed layer is
/// where it was before anything animated it.
@Suite("Properties reset to defaults")
struct PropertiesResetTests {

    @Test func aKeyedTitleGoesBackToWhereItStarted() {
        var (doc, id) = PropertyKeysTests.withTitle()
        let start = doc.layer(id: id)?.frame
        doc.startKeying(layerID: id, .motion(.position), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.point(CGPoint(x: 600, y: 300)), layerID: id, .motion(.position),
                          atDocumentTimeMS: 6000)
        doc.setKeyedValue(.number(180), layerID: id, .motion(.scale), atDocumentTimeMS: 5000)
        doc.setKeyedValue(.number(40), layerID: id, .motion(.opacity), atDocumentTimeMS: 4000)
        doc.setKeyedValue(.number(30), layerID: id, .motion(.rotation), atDocumentTimeMS: 4000)
        #expect(doc.layer(id: id)?.hasPropertiesToReset == true)

        let reset = doc.resetPropertiesToDefaults(layerID: id)
        #expect(reset)

        let layer = doc.layer(id: id)
        #expect(layer?.motions == nil)
        #expect(layer?.frame == start)
        #expect(layer?.transform.rotation == 0)
        #expect(layer?.style.opacity == 1)
        for property in layer?.keyableProperties ?? [] {
            #expect(doc.keyCount(layerID: id, property) == 0)
        }
        #expect(PropertyKeysTests.number(doc.keyedValue(layerID: id, .motion(.scale),
                                                        atDocumentTimeMS: 6000)) == 100)
        #expect(layer?.hasPropertiesToReset == false)
    }

    @Test func aTurnAndAFadeSetWithoutKeysGoToo() {
        var (doc, id) = PropertyKeysTests.withTitle()
        doc.setKeyedValue(.number(55), layerID: id, .motion(.opacity), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.number(15), layerID: id, .motion(.rotation), atDocumentTimeMS: 3000)
        #expect(doc.layer(id: id)?.motions == nil)
        #expect(doc.layer(id: id)?.hasPropertiesToReset == true)

        let reset = doc.resetPropertiesToDefaults(layerID: id)
        #expect(reset)

        #expect(doc.layer(id: id)?.style.opacity == 1)
        #expect(doc.layer(id: id)?.transform.rotation == 0)
    }

    @Test func aFlipIsNotATurnAndStays() {
        var (doc, id) = PropertyKeysTests.withTitle()
        doc.updateLayer(id: id) { $0.transform.flipHorizontal = true }
        #expect(doc.layer(id: id)?.hasPropertiesToReset == false)
        let reset = doc.resetPropertiesToDefaults(layerID: id)
        #expect(!reset)
        #expect(doc.layer(id: id)?.transform.flipHorizontal == true)
    }

    @Test func aLayerAlreadyAtItsDefaultsIsLeftAlone() {
        var (doc, id) = PropertyKeysTests.withTitle()
        let before = doc
        let reset = doc.resetPropertiesToDefaults(layerID: id)
        #expect(!reset)
        #expect(doc == before)
    }

    @Test func theLookIsNotPartOfIt() {
        var (doc, id) = PropertyKeysTests.withTitle()
        doc.updateLayer(id: id) { $0.style.blurRadius = 6 }
        doc.setKeyedValue(.number(50), layerID: id, .motion(.opacity), atDocumentTimeMS: 3000)
        doc.resetPropertiesToDefaults(layerID: id)
        #expect(doc.layer(id: id)?.style.blurRadius == 6)
    }

    @Test func volumeGoesBackToFullWithNoKeys() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        var sound = Layer(name: "Music", content: .sound(SoundRef(durationMS: 10_000)), frame: .zero)
        sound.time = LayerTime(inMS: 1000, outMS: 9000, sourceLengthMS: 10_000)
        doc.layers = [sound]
        doc.durationMS = 10_000
        let id = sound.id
        doc.startKeying(layerID: id, .volume, atDocumentTimeMS: 2000)
        doc.setKeyedValue(.number(-12), layerID: id, .volume, atDocumentTimeMS: 5000)
        #expect(doc.layer(id: id)?.hasPropertiesToReset == true)

        let reset = doc.resetPropertiesToDefaults(layerID: id)
        #expect(reset)

        #expect(doc.keyCount(layerID: id, .volume) == 0)
        #expect(doc.layer(id: id)?.soundLevel?.gain ?? AudioLevel.unityGain == AudioLevel.unityGain)
        #expect(doc.layer(id: id)?.hasPropertiesToReset == false)
    }

    @Test func aMissingLayerChangesNothing() {
        var (doc, _) = PropertyKeysTests.withTitle()
        let reset = doc.resetPropertiesToDefaults(layerID: UUID())
        #expect(!reset)
    }
}
