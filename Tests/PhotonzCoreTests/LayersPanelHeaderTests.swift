import Foundation
import Testing
@testable import PhotonzCore

/// The Layers group's header as both component mocks draw it
/// (`component-configure-wt.html` `#gLayersH`, `components.html` `#layerMenu`):
/// a count, the Make Component button and a panel menu of three rows.
@Suite struct LayersPanelHeaderTests {
    @Test func theCountIsEveryLayerAndNothingForAnEmptyDocument() {
        #expect(LayersPanelHeader.countChip(layerCount: 5) == "5")
        // An empty group says so by being empty, like every other count chip.
        #expect(LayersPanelHeader.countChip(layerCount: 0) == nil)
    }

    @Test func theButtonIsNamedForTheCommandWithItsKey() {
        // The Layer menu's own words, so the tooltip and the menu bar agree.
        #expect(LayersPanelHeader.makeComponent == "Make Component")
        #expect(LayersPanelHeader.makeComponentHelp == "Make Component (\u{2325}\u{2318}K)")
    }

    @Test func theMenuIsTheMocksRowsInItsOrder() {
        // The icon rows as `icon-draw-wt.html` draws the same menu: Mirror
        // Across Center and Center on the Artboard under Group Selection, then
        // a divider and the two that remake a shape's outline.
        // Stack Selection first, where `ui-autolayout.html` `#layerMenu` puts
        // its "Wrap in auto-layout", in the menu bar's words.
        #expect(LayersPanelHeader.MenuRow.allCases.map(\.title)
            == ["Stack Selection", "Group Selection", "Mirror Across Center", "Center on the Artboard",
                "Union", "Outline Stroke", "Make Component", "Hide This Panel"])
        // Dividers before Union, before Make Component, and before Hide, which
        // acts on the window rather than the layers.
        #expect(LayersPanelHeader.MenuRow.allCases.map(\.startsSection)
            == [false, false, false, false, true, false, true, true])
    }

    @Test func eachRowCarriesTheKeyItsMenuBarTwinAnswersTo() {
        #expect(LayersPanelHeader.MenuRow.groupSelection.shortcut
            == .init(key: "g", modifiers: [.command]))
        // One modifier off grouping, as Layer > Stack Selection has it.
        #expect(LayersPanelHeader.MenuRow.stackSelection.shortcut
            == .init(key: "g", modifiers: [.control, .command]))
        #expect(LayersPanelHeader.MenuRow.makeComponent.shortcut
            == .init(key: "k", modifiers: [.option, .command]))
        // The mock's keys for Union and Outline Stroke.
        #expect(LayersPanelHeader.MenuRow.union.shortcut
            == .init(key: "u", modifiers: [.option, .command]))
        #expect(LayersPanelHeader.MenuRow.outlineStroke.shortcut
            == .init(key: "o", modifiers: [.shift, .command]))
        // The mock prints Option Command C for Center on the Artboard, but that
        // is Canvas Size, as it is in Photoshop, so the row borrows no key.
        #expect(LayersPanelHeader.MenuRow.centerOnArtboard.shortcut == nil)
        // Show Panel's Option Command L is a setting with a checkmark in the
        // View menu; here the row only ever hides, so it borrows no key.
        #expect(LayersPanelHeader.MenuRow.hidePanel.shortcut == nil)
    }

    @Test func theHideRowSaysTheAppsOneWordForThePanel() {
        #expect(LayersPanelHeader.MenuRow.hidePanel.title.hasSuffix(PanelCopy.noun))
    }

    @Test func everyWordFitsTheChromeBudget() {
        let words = LayersPanelHeader.MenuRow.allCases.map(\.title)
            + [LayersPanelHeader.makeComponentHelp, LayersPanelHeader.menuName]
        for word in words { #expect(word.count <= 30, "\(word)") }
    }
}
