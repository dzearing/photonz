import Foundation
import PhotonzCore
import Testing

/// The Component insert tool (Next, `next-components`): the UI entry mock's
/// `tComp`, between Frame and the shapes in the Design tool bar
/// (`ui-entry-wt.html` step 4, UX-PATTERNS D4 "UI design"). Pick it, click the
/// canvas, and a copy of a component lands centred on the click.
@Suite("Component insert tool")
struct ComponentToolTests {

    // MARK: The tool

    @Test("It makes something, so it hands back to Select with the copy picked")
    func createsLayers() {
        #expect(Tool.component.createsLayers)
        #expect(ArrowCaptionEntry.toolAfterLanding(.component, offersCaption: false) == .select)
    }

    @Test("It puts no colour on the picture, draws no annotation and owns its own clicks")
    func plainPlacingTool() {
        #expect(Tool.component.colorControl == .hidden)
        #expect(Tool.component.annotationShape == nil)
        #expect(!Tool.component.createsAnnotationByDrag)
        #expect(!Tool.component.doubleClickOnEmptyCanvasZoomsWindow)
        #expect(!Tool.component.preservesLayerSelection)
        #expect(!Tool.component.isRegionSelectionTool)
    }

    @Test("It answers to N, a letter no other tool and no Photoshop tool claims")
    func key() {
        #expect(Tool.component.shortcutKey == "n")
        #expect(Tool.component.shortcutHint == "N")
        #expect(Tool.allCases.filter { $0.shortcutKey == "n" } == [.component])
        // Crop keeps Photoshop's C.
        #expect(Tool.crop.shortcutKey == "c")
    }

    // MARK: The bar

    @Test("It joins the end of the drawing family, after the Pen, so no learned slot moves")
    func joinsTheEndOfTheDrawingFamily() {
        let without = ToolBarLayout.bar(withFrame: true, withLens: true, withPen: true)
        let with = ToolBarLayout.bar(withFrame: true, withLens: true, withPen: true,
                                     withComponent: true)
        #expect(with.families[0] == without.families[0])
        #expect(with.families[2] == without.families[2])
        #expect(with.families[1] == without.families[1] + [.tool(.component)])
        #expect(without.entry(for: .component) == nil)
        #expect(with.entry(for: .component) == .tool(.component))
    }

    @Test("Design puts it straight after Frame, as the mock draws it")
    func designStripHasIt() {
        let design = WindowModes.mode("design")?.toolStrip ?? []
        #expect(design.count == 4)
        #expect(design[1] == [.tool(.frame), .tool(.component), .group(.shapes),
                              .tool(.pen), .tool(.text)])
    }

    @Test("A release without components leaves the strip's slot out rather than drawing it dead")
    func leftOutWithoutComponents() {
        let bar = ToolBarLayout.bar(withFrame: true, withLens: true, withPen: true)
        let fold = ToolBarFold(bar, strip: WindowModes.mode("design")?.toolStrip ?? [],
                               room: .greatestFiniteMagnitude,
                               metrics: .init(slot: 28, gap: 4, hairline: 5, more: 28))
        #expect(!fold.shownEntries.contains(.tool(.component)))
        #expect(!fold.folded.contains(.tool(.component)))
    }

    // MARK: Its setting

    @Test("Its capsule carries one setting: which component it places")
    func setting() {
        #expect(ToolSettingsBar.settings(for: .component, availability: .all) == [.component])
        #expect(ToolSettingsBar.settings(for: .component, availability: .none) == [.component])
        #expect(ToolSetting.component.title == "Component")
    }

    // MARK: Which component a click places

    private let button = UUID()
    private let card = UUID()
    private let toggle = UUID()

    @Test("The component picked in the Library wins")
    func libraryPickWins() {
        let chosen = ComponentToolChoice.component(libraryPick: card, remembered: toggle,
                                                   offered: [button, card, toggle])
        #expect(chosen == card)
    }

    @Test("With nothing picked in the Library, the one it placed last")
    func rememberedNext() {
        let chosen = ComponentToolChoice.component(libraryPick: nil, remembered: toggle,
                                                   offered: [button, card, toggle])
        #expect(chosen == toggle)
    }

    @Test("A pick or memory naming something no longer on offer is passed over")
    func staleIsPassedOver() {
        let gone = UUID()
        #expect(ComponentToolChoice.component(libraryPick: gone, remembered: toggle,
                                              offered: [button, toggle]) == toggle)
        #expect(ComponentToolChoice.component(libraryPick: gone, remembered: gone,
                                              offered: [button, toggle]) == button)
    }

    @Test("First time, nothing picked: the first component on offer, so a click always places one")
    func firstOnOffer() {
        #expect(ComponentToolChoice.component(libraryPick: nil, remembered: nil,
                                              offered: [button, card]) == button)
    }

    @Test("With no components at all, a click places nothing")
    func nothingToPlace() {
        #expect(ComponentToolChoice.component(libraryPick: nil, remembered: nil,
                                              offered: []) == nil)
    }
}
