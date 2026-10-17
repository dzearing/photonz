import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A clip can be colour graded from Add Effect
/// (task `a-clip-can-be-colour-graded-from-add-effect`).
///
/// Written before the model. The video mock puts a Warm grade in a clip's
/// Effects list and Color grade in the plus's menu, with Saturation keyable
/// from 0 to 300 percent at a still of 100; until this a recording could not
/// be warmed, cooled, brightened or saturated at all.
@Suite("Color grade")
struct ColorGradeTests {

    // MARK: - Fixtures

    /// Ten seconds and one clip-sized picture, "Clip", with nothing on it.
    static func clip() -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        var clip = Layer(name: "Clip",
                         content: .image(ImageRef(id: UUID(), pixelSize: CGSize(width: 1920, height: 1080))),
                         frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        clip.time = LayerTime(inMS: 0, outMS: 10_000)
        doc.layers = [clip]
        doc.durationMS = 10_000
        return (doc, clip.id)
    }

    static func posed(_ doc: PhotonzDocument, _ id: UUID, at ms: Int) -> Layer? {
        doc.drawn(atTimeMS: ms).layer(id: id)
    }

    static let gradeValues: [MotionProperty] = [.gradeTemperature, .gradeTint, .gradeExposure,
                                                .gradeContrast, .gradeSaturation]

    // MARK: - The effect

    @Test func itIsOnTheAddEffectMenuAsColorGrade() {
        #expect(AddableEffect.allCases.contains(.colorGrade))
        #expect(AddableEffect.colorGrade.title == "Color Grade")
        #expect(AddableEffect.colorGrade.kind == .colorGrade)
        #expect(EffectKind.colorGrade.title == "Color Grade")
        // The mock's reading at the end of the row.
        #expect(EffectKind.colorGrade.listReading == "adjust")
        #expect(EffectKind.shadow.listReading == nil)
        // One grade a layer: two would be one answer twice. It paints no
        // colour of its own, so it brings no colour row.
        #expect(EffectKind.colorGrade.isCountable == false)
        #expect(EffectKind.colorGrade.colorSlot == nil)
    }

    @Test func itArrivesLookingLikeSomethingAndWarm() throws {
        // A row that does nothing the moment it lands reads as broken: the
        // grade arrives as a gentle warm look, the mock's Warm grade.
        guard case let .colorGrade(grade) = AddableEffect.colorGrade.newEffect else {
            Issue.record("a colour grade arrives"); return
        }
        #expect(grade.isOn)
        #expect(grade.paints)
        #expect(grade.temperature > 0)
        #expect(grade.saturation >= 100)
    }

    @Test func everyValueAtItsMiddleIsNoGradeAtAll() {
        let neutral = ColorGradeEffect.neutral
        #expect(neutral.temperature == 0)
        #expect(neutral.tint == 0)
        #expect(neutral.exposure == 0)
        #expect(neutral.contrast == 0)
        #expect(neutral.saturation == 100)
        #expect(neutral.isNeutral)
        #expect(neutral.paints == false)
        var warm = neutral
        warm.temperature = 30
        #expect(warm.paints)
        warm.isOn = false
        #expect(warm.paints == false)
    }

    @Test func valuesAreHeldInsideTheirRanges() {
        let wild = ColorGradeEffect(temperature: 500, tint: -500, exposure: 20, contrast: -300, saturation: 900)
        #expect(wild.temperature == ColorGradeEffect.temperatureRange.upperBound)
        #expect(wild.tint == ColorGradeEffect.tintRange.lowerBound)
        #expect(wild.exposure == ColorGradeEffect.exposureRange.upperBound)
        #expect(wild.contrast == ColorGradeEffect.contrastRange.lowerBound)
        #expect(wild.saturation == ColorGradeEffect.saturationRange.upperBound)
        // The mock's Saturation runs 0 to 300.
        #expect(ColorGradeEffect.saturationRange == 0...300)
    }

    @Test func itSavesAndOpensAsItWasWritten() throws {
        let effect = LayerEffect.colorGrade(ColorGradeEffect(temperature: 40, tint: -10, exposure: 0.5,
                                                             contrast: 20, saturation: 130, isOn: false))
        let data = try JSONEncoder().encode(effect)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"kind\":\"colorGrade\""))
        #expect(try JSONDecoder().decode(LayerEffect.self, from: data) == effect)
        // A grade written with only some values opens with the rest at their
        // middles.
        let sparse = #"{"kind":"colorGrade","colorGrade":{"temperature":25}}"#
        let opened = try JSONDecoder().decode(LayerEffect.self, from: Data(sparse.utf8))
        #expect(opened == .colorGrade(ColorGradeEffect(temperature: 25)))
    }

    @Test func theLayerReadsTheGradeThatPaints() {
        var style = LayerStyle()
        #expect(style.colorGrade == nil)
        style.effects = [.colorGrade(.neutral)]
        #expect(style.colorGrade == nil, "a grade at its middles paints nothing")
        style.effects = [.colorGrade(ColorGradeEffect(saturation: 150))]
        #expect(style.colorGrade?.saturation == 150)
        style.updateColorGradeEffect(at: 0) { $0.isOn = false }
        #expect(style.colorGrade == nil)
        #expect(style.colorGradeEffect(at: 0)?.saturation == 150)
    }

    @Test func addingOneThroughTheDocumentPutsItOnThePickedLayer() {
        var (doc, id) = Self.clip()
        #expect(doc.addEffect(.colorGrade, layerIDs: [id]) == 1)
        #expect(doc.layer(id: id)?.style.effects.first?.kind == .colorGrade)
        // A second is refused: one grade a layer.
        #expect(doc.addEffect(.colorGrade, layerIDs: [id]) == 0)
        #expect(doc.layer(id: id)?.style.effects.count == 1)
    }

    // MARK: - Keys

    @Test func theFiveValuesAreNamedAndGroupedAsEffects() {
        #expect(MotionProperty.gradeTemperature.title == "Temperature")
        #expect(MotionProperty.gradeTint.title == "Tint")
        #expect(MotionProperty.gradeExposure.title == "Exposure")
        #expect(MotionProperty.gradeContrast.title == "Contrast")
        #expect(MotionProperty.gradeSaturation.title == "Saturation")
        #expect(MotionProperty.gradeSaturation.format(.number(150)) == "150%")
        #expect(MotionProperty.gradeSaturation.keyValueUnit == "%")
        #expect(MotionProperty.gradeSaturation.keyValueDefault == .number(100))
        #expect(MotionProperty.gradeTemperature.keyValueDefault == .number(0))
        for property in Self.gradeValues {
            #expect(PropertyPicker.group(.motion(property)) == "Effects")
            #expect(MotionProperty.looks.contains(property), "\(property) is a look the panel edits")
            #expect(property.isLength == false)
        }
    }

    @Test func saturationIsOfferedOnEveryPictureAndTheRestOnceThereIsAGrade() throws {
        // The mock's catalogue offers Saturation on every picture at a still
        // of 100; the other four arrive with the grade they belong to.
        var (doc, id) = Self.clip()
        let bare = try #require(doc.layer(id: id)?.keyableProperties)
        #expect(bare.contains(.motion(.gradeSaturation)))
        #expect(doc.keyedValue(layerID: id, .motion(.gradeSaturation), atDocumentTimeMS: 0) == .number(100))
        for property in Self.gradeValues where property != .gradeSaturation {
            #expect(bare.contains(.motion(property)) == false, "\(property) waits for a grade")
        }
        doc.updateLayer(id: id) { $0.style.effects = [.colorGrade(ColorGradeEffect(temperature: 30))] }
        let graded = try #require(doc.layer(id: id)?.keyableProperties)
        for property in Self.gradeValues {
            #expect(graded.contains(.motion(property)), "\(property) offered on a graded clip")
        }
        #expect(doc.keyedValue(layerID: id, .motion(.gradeTemperature), atDocumentTimeMS: 0) == .number(30))
        // Sound has no picture to grade.
        let sound = Layer(name: "Sound", content: .sound(SoundRef(durationMS: 10_000)), frame: .zero)
        #expect(sound.keyableProperties.contains(.motion(.gradeSaturation)) == false)
    }

    @Test func temperatureMovesBetweenItsKeys() throws {
        var (doc, id) = Self.clip()
        doc.updateLayer(id: id) { $0.style.effects = [.colorGrade(.neutral)] }
        doc.startKeying(layerID: id, .motion(.gradeTemperature), atDocumentTimeMS: 0, ease: .linear)
        doc.setKeyedValue(.number(80), layerID: id, .motion(.gradeTemperature),
                          atDocumentTimeMS: 2000, ease: .linear)
        #expect(Self.posed(doc, id, at: 0)?.style.colorGrade == nil, "neutral at the first key")
        let middle = try #require(Self.posed(doc, id, at: 1000)?.style.colorGradeEffect(at: 0))
        let late = try #require(Self.posed(doc, id, at: 2000)?.style.colorGradeEffect(at: 0))
        #expect(abs(middle.temperature - 40) < 0.5)
        #expect(abs(late.temperature - 80) < 0.01)
        // Nothing baked in.
        #expect(doc.layer(id: id)?.style.colorGradeEffect(at: 0)?.temperature == 0)
    }

    @Test func keyingSaturationOnAClipWithNoGradeBringsOneIn() throws {
        var (doc, id) = Self.clip()
        doc.startKeying(layerID: id, .motion(.gradeSaturation), atDocumentTimeMS: 0, ease: .linear)
        doc.setKeyedValue(.number(0), layerID: id, .motion(.gradeSaturation),
                          atDocumentTimeMS: 1000, ease: .linear)
        #expect(Self.posed(doc, id, at: 0)?.style.colorGrade == nil)
        let grey = try #require(Self.posed(doc, id, at: 1000)?.style.colorGrade)
        #expect(grey.saturation == 0)
        #expect(grey.temperature == 0 && grey.exposure == 0)
        #expect(doc.layer(id: id)?.style.effects.isEmpty == true, "the stored clip has no grade of its own")
    }

    @Test func keyedValuesAreHeldInsideTheirRanges() {
        var (doc, id) = Self.clip()
        doc.updateLayer(id: id) { $0.style.effects = [.colorGrade(.neutral)] }
        doc.startKeying(layerID: id, .motion(.gradeExposure), atDocumentTimeMS: 0)
        doc.setKeyedValue(.number(50), layerID: id, .motion(.gradeExposure), atDocumentTimeMS: 0)
        #expect(Self.posed(doc, id, at: 0)?.style.colorGrade?.exposure == ColorGradeEffect.exposureRange.upperBound)
    }

    @Test func aPanelEditOnAKeyedValueKeysItAtThePlayhead() throws {
        var (doc, id) = Self.clip()
        doc.updateLayer(id: id) { $0.style.effects = [.colorGrade(.neutral)] }
        doc.startKeying(layerID: id, .motion(.gradeContrast), atDocumentTimeMS: 0, ease: .linear)
        doc.editLooks(layerIDs: [id], atDocumentTimeMS: 4000) { doc in
            _ = doc.updateLayerStyles(layerIDs: [id]) { $0.updateColorGradeEffect(at: 0) { $0.contrast = 50 } }
        }
        #expect(doc.keyCount(layerID: id, .motion(.gradeContrast)) == 2)
        #expect(Self.posed(doc, id, at: 4000)?.style.colorGrade?.contrast == 50)
        #expect(doc.layer(id: id)?.style.colorGradeEffect(at: 0)?.contrast == 0)
    }

    @Test func itNamesItselfWhenSavedAsAStyle() {
        let text = EffectStyleNaming.effectText(.colorGrade(ColorGradeEffect(temperature: 20, saturation: 110)))
        #expect(text.hasPrefix("Color grade"))
    }
}
