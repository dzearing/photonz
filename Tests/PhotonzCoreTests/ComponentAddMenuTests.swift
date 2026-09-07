import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// The Add menu on an original: the list an author reads once, while deciding
/// what a copy may change (`docs/design/ui-building.md`, step C6).
///
/// It is built here, in one place, rather than in the panel, because the one
/// thing it has to be is unambiguous: a menu offering the same words twice is a
/// menu you cannot choose from, and that is a property of the WHOLE list, not
/// of any one row. Tested where the whole list exists.
struct ComponentAddMenuTests {

    private func box(_ name: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 start: .zero,
                                                                 end: CGPoint(x: rect.width, y: rect.height))),
              frame: rect)
    }

    private func text(_ name: String, _ string: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .text(TextContent(string: string)), frame: rect)
    }

    /// The button of the whole-path walk: a rounded box with an unnamed text
    /// layer saying "Save" on it, grouped and made a component.
    private func saveButton() -> (doc: PhotonzDocument, componentID: UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024),
                                  layers: [box("Rectangle", CGRect(x: 0, y: 0, width: 360, height: 120)),
                                           text(TextBuilder.defaultLayerName, "Save",
                                                CGRect(x: 140, y: 50, width: 80, height: 20))])
        let group = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Save button")!
        let componentID = doc.makeComponent(id: group.id)!
        return (doc, componentID)
    }

    private func labels(_ doc: PhotonzDocument, _ componentID: UUID) -> [String] {
        ComponentAddMenu.sections(for: doc.componentPropertyCandidates(componentID: componentID))
            .flatMap { $0.rows.map(\.label) }
    }

    /// The bug this menu was rebuilt for: a text layer is offered twice, once
    /// to make its words adjustable and once to let a copy hide it, and both
    /// rows read "Text “Save”". Whichever you pick, you cannot have known.
    @Test func noTwoRowsReadTheSame() {
        let c = saveButton()
        let rows = labels(c.doc, c.componentID)
        #expect(rows.count == Set(rows).count, "the Add menu reads: \(rows.joined(separator: " | "))")
    }

    /// And the two rows for that one layer say which is which, in so many
    /// words, so the row is still unambiguous read on its own: in the log of a
    /// walk, under a pointer, out loud.
    @Test func theWordingRowAndTheHideRowSayWhatTheyGive() {
        let c = saveButton()
        let rows = labels(c.doc, c.componentID)
        #expect(rows.contains("Text \u{201C}Save\u{201D} \u{00B7} Wording"))
        #expect(rows.contains("Text \u{201C}Save\u{201D} \u{00B7} Show or hide"))
        #expect(!rows.contains("Text \u{201C}Save\u{201D}"))
    }

    /// Every row of every section reads the same way: the part, then what a
    /// copy would get to change about it. The colour and number rows already
    /// did, and this is the grammar the rest now borrows.
    @Test func everyRowNamesThePartAndThenWhatChanges() {
        let c = saveButton()
        #expect(labels(c.doc, c.componentID) == [
            "Text \u{201C}Save\u{201D} \u{00B7} Wording",
            "Rectangle \u{00B7} Show or hide",
            "Text \u{201C}Save\u{201D} \u{00B7} Show or hide",
            "Rectangle \u{00B7} Outline",
            "Text \u{201C}Save\u{201D} \u{00B7} Text",
            "Rectangle \u{00B7} Corner radius",
            "Rectangle \u{00B7} Thickness",
        ])
    }

    /// The sections stay: the menu is grouped by what a knob does, and a
    /// section with nothing left to offer is not on the menu at all.
    @Test func sectionsCarryTheirKindsPlainName() {
        let c = saveButton()
        let sections = ComponentAddMenu.sections(for: c.doc.componentPropertyCandidates(componentID: c.componentID))
        #expect(sections.map(\.title) == ["Wording", "Show or hide", "Color", "Number"])
        #expect(!sections.contains { $0.rows.isEmpty })
    }

    /// Two text layers nobody named are told apart by what they say, in every
    /// section they appear in and not only under Wording.
    @Test func twoUnnamedTextLayersAreTellableApartEverywhere() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                  layers: [text(TextBuilder.defaultLayerName, "Save",
                                                CGRect(x: 0, y: 0, width: 80, height: 20)),
                                           text(TextBuilder.defaultLayerName, "Cancel",
                                                CGRect(x: 0, y: 30, width: 80, height: 20))])
        let group = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Bar")!
        let componentID = doc.makeComponent(id: group.id)!
        let rows = labels(doc, componentID)
        #expect(rows.count == Set(rows).count, "the Add menu reads: \(rows.joined(separator: " | "))")
        #expect(rows.contains("Text \u{201C}Save\u{201D} \u{00B7} Text"))
        #expect(rows.contains("Text \u{201C}Cancel\u{201D} \u{00B7} Text"))
    }

    /// A group with alternatives in it offers a choice, and that row says so
    /// too, so it cannot be mistaken for the row that hides the same group.
    @Test func aChoiceRowSaysItIsAChoice() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400),
                                  layers: [box("On", CGRect(x: 0, y: 0, width: 40, height: 20)),
                                           box("Off", CGRect(x: 0, y: 0, width: 40, height: 20)),
                                           box("Edge", CGRect(x: 0, y: 40, width: 40, height: 20))])
        let control = doc.groupLayers(ids: Set(doc.layers.prefix(2).map(\.id)), name: "Control")!
        let main = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Row")!
        let componentID = doc.makeComponent(id: main.id)!
        let rows = labels(doc, componentID)
        #expect(rows.count == Set(rows).count, "the Add menu reads: \(rows.joined(separator: " | "))")
        #expect(rows.contains("Control \u{00B7} Choice"))
        #expect(rows.contains("Control \u{00B7} Show or hide"))
        _ = control
    }

    /// Each row carries the knob picking it would make, so the panel does not
    /// have to work any of that out a second time.
    @Test func aRowCarriesTheKnobItWouldMake() {
        let c = saveButton()
        let sections = ComponentAddMenu.sections(for: c.doc.componentPropertyCandidates(componentID: c.componentID))
        let outline = sections.first { $0.kind == .color }?.rows.first { $0.label.hasSuffix("Outline") }
        #expect(outline?.kind == .color)
        #expect(outline?.slot == .stroke)
        #expect(outline?.numberSlot == nil)
        let radius = sections.first { $0.kind == .number }?.rows.first { $0.label.hasSuffix("Corner radius") }
        #expect(radius?.numberSlot == .cornerRadius)
        let wording = sections.first { $0.kind == .text }?.rows.first
        #expect(wording?.slot == nil)
        #expect(wording?.numberSlot == nil)
    }

    /// Nothing left to expose is an empty menu, not a menu of empty sections.
    @Test func nothingLeftIsNoSections() {
        #expect(ComponentAddMenu.sections(for: []).isEmpty)
    }
}
