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

    @Test func theMenuIsTheMocksThreeRowsInItsOrder() {
        #expect(LayersPanelHeader.MenuRow.allCases.map(\.title)
            == ["Group Selection", "Make Component", "Hide This Panel"])
        // A divider before Hide: the first two act on the layers, the last on
        // the window.
        #expect(LayersPanelHeader.MenuRow.allCases.map(\.startsSection) == [false, false, true])
    }

    @Test func eachRowCarriesTheKeyItsMenuBarTwinAnswersTo() {
        #expect(LayersPanelHeader.MenuRow.groupSelection.shortcut
            == .init(key: "g", modifiers: [.command]))
        #expect(LayersPanelHeader.MenuRow.makeComponent.shortcut
            == .init(key: "k", modifiers: [.option, .command]))
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
