import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// An effect saved under a name, that any layer can wear, and that re-sets
/// everything wearing it when it is edited (`EffectStyles.swift`).
///
/// The third of the three kinds a style comes in. `ColorStyleTests` covers the
/// named paint and `TextStyleTests` the named text treatment; this one covers
/// the hard part neither of those has: an effect lives at a PLACE in a list
/// that can be added to, taken from and dragged around.
struct EffectStyleTests {

    // MARK: - Fixtures

    /// A box with an EMPTY Effects list: a shape asked for with a stroke gets
    /// that stroke as a Border in the list (`OutlineRetirement.swift`), and a
    /// list that already has something in it would move every place these tests
    /// name.
    private func box(_ name: String = "Card") -> Layer {
        var content = AnnotationContent(shape: .rectangle, start: .zero,
                                        end: CGPoint(x: 60, y: 30))
        content.strokeWidth = 0
        return Layer(name: name, content: .annotation(content),
                     frame: CGRect(x: 0, y: 0, width: 60, height: 30))
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: layers)
    }

    private let lift = LayerEffect.shadow(ShadowStyle(radius: 12,
                                                      offset: CGSize(width: 0, height: 4),
                                                      colorHex: "#102030", opacity: 0.4))
    private let halo = LayerEffect.glow(GlowEffect(colorHex: "#FF00AA", radius: 14))

    /// A layer already holding one effect at place zero.
    private func carded(_ name: String = "Card", _ effect: LayerEffect) -> Layer {
        var layer = box(name)
        layer.insertEffect(effect, at: 0)
        return layer
    }

    // MARK: - Saving one

    @Test func savingKeepsTheEffectAndPointsTheLayerAtIt() {
        let layer = carded("Card", lift)
        var doc = document([layer])
        let id = doc.saveEffectStyle(from: [layer.id], at: 0, name: "Card lift")
        #expect(id != nil)
        #expect(doc.effectStyles.count == 1)
        #expect(doc.effectStyles[0].name == "Card lift")
        #expect(doc.effectStyles[0].effect == lift)
        #expect(doc.layer(id: layer.id)?.effectStyleID(forEffectAt: 0) == id)
    }

    @Test func aStyleWithNoNameTakesTheKindItIs() {
        var doc = document([carded("Card", lift)])
        let first = doc.layers[0].id
        doc.saveEffectStyle(from: [first], at: 0)
        #expect(doc.effectStyles[0].name == "Shadow")
    }

    @Test func asecondUnnamedStyleOfTheSameKindCountsUp() {
        var doc = document([carded("A", lift), carded("B", lift)])
        doc.saveEffectStyle(from: [doc.layers[0].id], at: 0)
        doc.saveEffectStyle(from: [doc.layers[1].id], at: 0)
        #expect(doc.effectStyles.map(\.name) == ["Shadow", "Shadow 2"])
    }

    @Test func aGlowSavesUnderItsOwnWordRatherThanEffect() {
        var doc = document([carded("Card", halo)])
        doc.saveEffectStyle(from: [doc.layers[0].id], at: 0)
        #expect(doc.effectStyles[0].name == "Glow")
    }

    @Test func layersThatDisagreeHaveNothingToSave() {
        var doc = document([carded("A", lift), carded("B", halo)])
        let ids = doc.layers.map(\.id)
        #expect(doc.sharedEffect(layerIDs: ids, at: 0) == nil)
        #expect(doc.saveEffectStyle(from: ids, at: 0) == nil)
        #expect(doc.effectStyles.isEmpty)
    }

    @Test func savingFromSeveralThatAgreeDressesAllOfThem() {
        var doc = document([carded("A", lift), carded("B", lift)])
        let ids = doc.layers.map(\.id)
        let id = doc.saveEffectStyle(from: ids, at: 0, name: "Card lift")
        #expect(doc.layer(id: ids[0])?.effectStyleID(forEffectAt: 0) == id)
        #expect(doc.layer(id: ids[1])?.effectStyleID(forEffectAt: 0) == id)
        #expect(doc.effectStyleUsageCount(id: id!) == 2)
    }

    @Test func aLockedLayerIsNeverSavedFromAndNeverDressed() {
        var locked = carded("Locked", lift)
        locked.isLocked = true
        var doc = document([locked])
        #expect(doc.saveEffectStyle(from: [locked.id], at: 0) == nil)
    }

    // MARK: - Wearing one somewhere else

    @Test func addingTheNameToAnotherLayerGivesItTheSameEffect() {
        var doc = document([carded("A", lift), box("B")])
        let ids = doc.layers.map(\.id)
        let id = doc.saveEffectStyle(from: [ids[0]], at: 0, name: "Card lift")!
        #expect(doc.useEffectStyle(layerIDs: [ids[1]], styleID: id) == 1)
        let plain = doc.layer(id: ids[1])
        #expect(plain?.style.effects == [lift])
        #expect(plain?.effectStyleID(forEffectAt: 0) == id)
    }

    @Test func aCountableKindLandsAtTheFootSoTheRowsAboveHoldStill() {
        var doc = document([carded("A", lift)])
        let first = doc.layers[0].id
        var other = document([carded("B", halo)])
        // Save a shadow style in the first document, then use it in a layer
        // that already holds a glow: the glow keeps its place.
        let id = doc.saveEffectStyle(from: [first], at: 0, name: "Card lift")!
        other.effectStyles = doc.effectStyles
        let second = other.layers[0].id
        other.useEffectStyle(layerIDs: [second], styleID: id)
        #expect(other.layer(id: second)?.style.effects.map(\.kind) == [.glow, .shadow])
        #expect(other.layer(id: second)?.effectStyleID(forEffectAt: 1) == id)
    }

    @Test func aKindALayerCanOnlyHaveOneOfIsResetRatherThanAddedTwice() {
        var doc = document([carded("A", .blur(BlurEffect(radius: 20)))])
        let first = doc.layers[0].id
        let id = doc.saveEffectStyle(from: [first], at: 0, name: "Soft")!
        var target = carded("B", .blur(BlurEffect(radius: 3)))
        doc.layers.append(target)
        target = doc.layers[1]
        #expect(doc.useEffectStyle(layerIDs: [target.id], styleID: id) == 1)
        #expect(doc.layer(id: target.id)?.style.effects.count == 1)
        #expect(doc.layer(id: target.id)?.style.effects[0].blur?.radius == 20)
        #expect(doc.layer(id: target.id)?.effectStyleID(forEffectAt: 0) == id)
    }

    @Test func aRowOnlyTakesANameOfItsOwnKind() {
        var doc = document([carded("A", lift), carded("B", halo)])
        let ids = doc.layers.map(\.id)
        let id = doc.saveEffectStyle(from: [ids[0]], at: 0, name: "Card lift")!
        // The glow at place zero on B is left alone: a row titled Glow may
        // never quietly become a shadow.
        #expect(doc.bindEffectStyle(layerIDs: [ids[1]], at: 0, styleID: id) == false)
        #expect(doc.layer(id: ids[1])?.style.effects == [halo])
    }

    // MARK: - Editing the name changes everything wearing it

    @Test func editingTheStyleResetsEveryLayerWearingIt() {
        var doc = document([carded("A", lift), carded("B", lift)])
        let ids = doc.layers.map(\.id)
        let id = doc.saveEffectStyle(from: ids, at: 0, name: "Card lift")!
        let tighter = LayerEffect.shadow(ShadowStyle(radius: 2, offset: CGSize(width: 0, height: 1),
                                                     colorHex: "#000000", opacity: 0.8))
        #expect(doc.setEffectStyle(styleID: id, effect: tighter) == 2)
        #expect(doc.layer(id: ids[0])?.style.effect(at: 0) == tighter)
        #expect(doc.layer(id: ids[1])?.style.effect(at: 0) == tighter)
        // ...and both still wear the name afterwards.
        #expect(doc.layer(id: ids[0])?.effectStyleID(forEffectAt: 0) == id)
    }

    @Test func editingTheStyleIsOneUndoStep() {
        var doc = document([carded("A", lift), carded("B", lift)])
        let ids = doc.layers.map(\.id)
        let id = doc.saveEffectStyle(from: ids, at: 0, name: "Card lift")!
        var history = History(document: doc)
        let tighter = LayerEffect.shadow(ShadowStyle(radius: 2, colorHex: "#000000"))
        history.perform { $0.setEffectStyle(styleID: id, effect: tighter) }
        #expect(history.current.layer(id: ids[1])?.style.effect(at: 0) == tighter)
        history.undo()
        #expect(history.current.layer(id: ids[0])?.style.effect(at: 0) == lift)
        #expect(history.current.layer(id: ids[1])?.style.effect(at: 0) == lift)
    }

    @Test func aStyleNeverChangesTheKindItIs() {
        var doc = document([carded("A", lift)])
        let id = doc.saveEffectStyle(from: [doc.layers[0].id], at: 0, name: "Card lift")!
        #expect(doc.setEffectStyle(styleID: id, effect: halo) == 0)
        #expect(doc.effectStyle(id: id)?.effect == lift)
    }

    // MARK: - The list moving underneath

    @Test func aNameSlidesDownWhenSomethingIsAddedAboveIt() {
        var doc = document([carded("A", lift)])
        let first = doc.layers[0].id
        let id = doc.saveEffectStyle(from: [first], at: 0, name: "Card lift")!
        doc.updateLayer(id: first) { $0.insertEffect(.blur(BlurEffect()), at: 0) }
        #expect(doc.layer(id: first)?.effectStyleID(forEffectAt: 1) == id)
        #expect(doc.layer(id: first)?.effectStyleID(forEffectAt: 0) == nil)
    }

    @Test func aNameComesUpWhenSomethingAboveItIsTakenOut() {
        var layer = box()
        layer.insertEffect(.blur(BlurEffect()), at: 0)
        layer.insertEffect(lift, at: 1)
        var doc = document([layer])
        let id = doc.saveEffectStyle(from: [layer.id], at: 1, name: "Card lift")!
        doc.updateLayer(id: layer.id) { $0.removeEffect(at: 0) }
        #expect(doc.layer(id: layer.id)?.effectStyleID(forEffectAt: 0) == id)
    }

    @Test func aNameGoesWithTheRowItIsOn() {
        var doc = document([carded("A", lift)])
        let first = doc.layers[0].id
        doc.saveEffectStyle(from: [first], at: 0, name: "Card lift")
        doc.updateLayer(id: first) { $0.removeEffect(at: 0) }
        #expect(doc.layer(id: first)?.effectStyleBindings == nil)
        #expect(doc.effectStyles.count == 1)   // ...the shelf keeps it
    }

    @Test func aNameFollowsItsRowWhenTheRowIsDragged() {
        var layer = box()
        layer.insertEffect(lift, at: 0)
        layer.insertEffect(halo, at: 1)
        var doc = document([layer])
        let shadowStyle = doc.saveEffectStyle(from: [layer.id], at: 0, name: "Card lift")!
        doc.updateLayer(id: layer.id) { $0.moveEffect(from: 0, to: 1) }
        #expect(doc.layer(id: layer.id)?.effectStyleID(forEffectAt: 1) == shadowStyle)
        #expect(doc.layer(id: layer.id)?.effectStyleID(forEffectAt: 0) == nil)
    }

    @Test func aColourNameAndAnEffectNameOnOneRowMoveTogether() {
        var doc = document([carded("A", halo)])
        let first = doc.layers[0].id
        let colour = doc.addColorStyle(name: "Pink", paint: Paint(hex: "#FF00AA"))
        doc.bindColorStyle(layerIDs: [first], effectAt: 0, styleID: colour)
        // Binding the effect style takes the colour name off the same row, so
        // add a second effect and check the colour name on THAT row travels.
        doc.updateLayer(id: first) { $0.insertEffect(.blur(BlurEffect()), at: 0) }
        #expect(doc.layer(id: first)?.colorStyleID(forEffectAt: 1) == colour)
    }

    // MARK: - Letting go

    @Test func tuningTheEffectByHandLetsGoOfTheName() {
        var doc = document([carded("A", lift)])
        let first = doc.layers[0].id
        doc.saveEffectStyle(from: [first], at: 0, name: "Card lift")
        var history = History(document: doc)
        history.perform { $0.updateEffect(layerIDs: [first], at: 0) { $0.shadow?.radius = 30 } }
        #expect(history.current.layer(id: first)?.effectStyleID(forEffectAt: 0) == nil)
        #expect(history.current.layer(id: first)?.style.effect(at: 0)?.shadow?.radius == 30)
    }

    @Test func switchingTheEffectOffLetsGoOfTheNameToo() {
        var doc = document([carded("A", lift)])
        let first = doc.layers[0].id
        doc.saveEffectStyle(from: [first], at: 0, name: "Card lift")
        #expect(doc.reconcileEffectStyles() == 0)
        doc.updateEffect(layerIDs: [first], at: 0) { $0.isOn = false }
        #expect(doc.reconcileEffectStyles() == 1)
        #expect(doc.layer(id: first)?.effectStyleID(forEffectAt: 0) == nil)
    }

    @Test func unlinkKeepsTheEffectAndDropsTheName() {
        var doc = document([carded("A", lift)])
        let first = doc.layers[0].id
        doc.saveEffectStyle(from: [first], at: 0, name: "Card lift")
        doc.unbindEffectStyle(layerIDs: [first], at: 0)
        #expect(doc.layer(id: first)?.effectStyleID(forEffectAt: 0) == nil)
        #expect(doc.layer(id: first)?.style.effect(at: 0) == lift)
    }

    @Test func removingAStyleLeavesEveryLayerWearingWhatItHas() {
        var doc = document([carded("A", lift), carded("B", lift)])
        let ids = doc.layers.map(\.id)
        let id = doc.saveEffectStyle(from: ids, at: 0, name: "Card lift")!
        doc.deleteEffectStyle(id: id)
        #expect(doc.effectStyles.isEmpty)
        #expect(doc.layer(id: ids[0])?.style.effect(at: 0) == lift)
        #expect(doc.layer(id: ids[1])?.style.effect(at: 0) == lift)
        #expect(doc.layer(id: ids[0])?.effectStyleBindings == nil)
    }

    @Test func aFileNamingAStyleThatIsGoneLetsGoOnOpening() {
        var layer = carded("A", lift)
        layer.effectStyleBindings = [EffectStyleBinding(effectIndex: 0, styleID: UUID())]
        var doc = document([layer])
        #expect(doc.reconcileEffectStyles() == 1)
        #expect(doc.layer(id: layer.id)?.effectStyleBindings == nil)
    }

    // MARK: - Renaming

    @Test func renamingKeepsEverythingWearingIt() {
        var doc = document([carded("A", lift)])
        let first = doc.layers[0].id
        let id = doc.saveEffectStyle(from: [first], at: 0, name: "Card lift")!
        doc.renameEffectStyle(id: id, to: "Raised")
        #expect(doc.effectStyle(id: id)?.name == "Raised")
        #expect(doc.layer(id: first)?.effectStyleID(forEffectAt: 0) == id)
    }

    @Test func aBlankNameIsRefused() {
        var doc = document([carded("A", lift)])
        let id = doc.saveEffectStyle(from: [doc.layers[0].id], at: 0, name: "Card lift")!
        doc.renameEffectStyle(id: id, to: "   ")
        #expect(doc.effectStyle(id: id)?.name == "Card lift")
    }

    // MARK: - The shelf

    @Test func theShelfListsEveryStyleWithHowMuchLeansOnIt() {
        var doc = document([carded("A", lift), carded("B", lift)])
        let ids = doc.layers.map(\.id)
        doc.saveEffectStyle(from: ids, at: 0, name: "Card lift")
        let entries = doc.effectStyleLibraryEntries
        #expect(entries.count == 1)
        #expect(entries[0].scope == .styles)
        #expect(entries[0].name == "Card lift")
        #expect(entries[0].detail == "2 uses")
    }

    @Test func aStyleNobodyUsesSaysSo() {
        var doc = document([carded("A", lift)])
        let id = doc.saveEffectStyle(from: [doc.layers[0].id], at: 0, name: "Card lift")!
        doc.unbindEffectStyle(layerIDs: [doc.layers[0].id], at: 0)
        #expect(doc.effectStyleLibraryEntries[0].detail == "not used yet")
        #expect(doc.layersUsingEffectStyle(id: id).isEmpty)
    }

    // MARK: - What one row's Style control speaks for

    @Test func oneLayerWearingAStyleReadsAsThatStyle() {
        var doc = document([carded("A", lift)])
        let first = doc.layers[0].id
        let id = doc.saveEffectStyle(from: [first], at: 0, name: "Card lift")!
        let selection = doc.effectStyleSelection(layerIDs: [first], at: 0, kind: .shadow)
        #expect(selection.reading == .style(id))
        #expect(selection.boundStyleID == id)
        #expect(selection.savableEffect == nil)
    }

    @Test func layersSetTheSameWayWithNoNameOfferTheSaveButton() {
        let doc = document([carded("A", lift), carded("B", lift)])
        let selection = doc.effectStyleSelection(layerIDs: doc.layers.map(\.id),
                                                 at: 0, kind: .shadow)
        #expect(selection.reading == .own(lift))
        #expect(selection.savableEffect == lift)
        #expect(selection.unlinkNote == nil)
    }

    @Test func layersThatDisagreeReadAsMixedAndOfferNoSave() {
        var doc = document([carded("A", lift), carded("B", lift)])
        let ids = doc.layers.map(\.id)
        doc.updateEffect(layerIDs: [ids[1]], at: 0) { $0.shadow?.radius = 30 }
        let selection = doc.effectStyleSelection(layerIDs: ids, at: 0, kind: .shadow)
        #expect(selection.reading == .mixed)
        #expect(selection.savableEffect == nil)
    }

    @Test func aRowSpeakingForFewerLayersThanArePickedSaysHowMany() {
        let doc = document([carded("A", lift), box("B")])
        let selection = doc.effectStyleSelection(layerIDs: doc.layers.map(\.id),
                                                 at: 0, kind: .shadow)
        #expect(selection.count == 1)
        #expect(selection.selectionCount == 2)
    }

    @Test func aStyledRowWarnsBeforeItsSettingsAreTouched() {
        var doc = document([carded("A", lift)])
        let first = doc.layers[0].id
        doc.saveEffectStyle(from: [first], at: 0, name: "Card lift")
        let selection = doc.effectStyleSelection(layerIDs: [first], at: 0, kind: .shadow)
        #expect(selection.unlinkNote == "Changing any setting below takes this off the style.")
    }

    // MARK: - The file

    @Test func aDocumentWithNoEffectStylesWritesNoKey() throws {
        let doc = document([carded("A", lift)])
        let data = try JSONEncoder().encode(doc)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("effectStyles"))
        #expect(!json.contains("effectStyleBindings"))
    }

    @Test func aSavedStyleSurvivesTheRoundTrip() throws {
        var doc = document([carded("A", lift)])
        let first = doc.layers[0].id
        let id = doc.saveEffectStyle(from: [first], at: 0, name: "Card lift")!
        let data = try JSONEncoder().encode(doc)
        var back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.effectStyle(id: id)?.name == "Card lift")
        #expect(back.effectStyle(id: id)?.effect == lift)
        #expect(back.layer(id: first)?.effectStyleID(forEffectAt: 0) == id)
        #expect(back.reconcileEffectStyles() == 0)
    }

    // MARK: - The link break the app says out loud

    @Test func tuningAStyledEffectIsReportedAsALinkBreak() {
        var doc = document([carded("A", lift)])
        let first = doc.layers[0].id
        doc.saveEffectStyle(from: [first], at: 0, name: "Card lift")
        var history = History(document: doc)
        let report = history.perform {
            $0.updateEffect(layerIDs: [first], at: 0) { $0.shadow?.radius = 30 }
        }
        #expect(report.linkBreaks.breaks.contains { $0.kind == .effectStyle
                    && $0.source == "Card lift" && $0.count == 1 })
    }

    @Test func removingTheRowIsNotReportedAsALinkBreak() {
        var doc = document([carded("A", lift)])
        let first = doc.layers[0].id
        doc.saveEffectStyle(from: [first], at: 0, name: "Card lift")
        var history = History(document: doc)
        let report = history.perform { $0.removeEffect(layerIDs: [first], at: 0) }
        #expect(!report.linkBreaks.breaks.contains { $0.kind == .effectStyle })
    }

    @Test func removingTheStyleIsNotReportedAsALinkBreak() {
        var doc = document([carded("A", lift)])
        let first = doc.layers[0].id
        let id = doc.saveEffectStyle(from: [first], at: 0, name: "Card lift")!
        var history = History(document: doc)
        let report = history.perform { $0.deleteEffectStyle(id: id) }
        #expect(!report.linkBreaks.breaks.contains { $0.kind == .effectStyle })
    }
}
