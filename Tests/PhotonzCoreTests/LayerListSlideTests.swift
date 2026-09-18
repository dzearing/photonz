import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What the layers list's slide is keyed to, and what it is deliberately deaf
/// to. The rule exists because a search is retyped on every keystroke: keyed
/// to the results, one letter set a whole separated screenshot sliding.
struct LayerListSlideTests {

    private let whole: [LayerPanelRow]
    private let results: [LayerPanelRow]

    init() {
        let all = (0..<5).map { _ in
            LayerPanelRow(id: UUID(), depth: 0, isGroup: false, childCount: 0,
                          isExpanded: false, parentID: nil)
        }
        whole = all
        results = Array(all.prefix(2))
    }

    @Test func withNothingTypedTheKeyIsTheListItself() {
        #expect(LayerListSlide.key(shown: whole, whole: whole, isSearching: false) == whole)
    }

    @Test func aSearchIsKeyedToTheWholeListSoNarrowingItDoesNotSlide() {
        let typedOneLetter = LayerListSlide.key(shown: results, whole: whole, isSearching: true)
        let typedTwo = LayerListSlide.key(shown: Array(results.prefix(1)), whole: whole,
                                          isSearching: true)
        #expect(typedOneLetter == typedTwo)
    }

    @Test func startingAndClearingASearchDoesNotSlideEither() {
        let before = LayerListSlide.key(shown: whole, whole: whole, isSearching: false)
        let searching = LayerListSlide.key(shown: results, whole: whole, isSearching: true)
        let cleared = LayerListSlide.key(shown: whole, whole: whole, isSearching: false)
        #expect(before == searching)
        #expect(searching == cleared)
    }

    @Test func theListChangingShapeStillSlides() {
        let shorter = Array(whole.dropLast())
        #expect(LayerListSlide.key(shown: whole, whole: whole, isSearching: false)
                != LayerListSlide.key(shown: shorter, whole: shorter, isSearching: false))
        // ...and it slides while a search is showing too: a layer deleted out
        // from under the results is a change to the list, not to the query.
        #expect(LayerListSlide.key(shown: results, whole: whole, isSearching: true)
                != LayerListSlide.key(shown: results, whole: shorter, isSearching: true))
    }

    @Test func theWholeListIsNotWalkedWhileNothingIsTyped() {
        // The unfiltered rows cost a walk of the tree, and with nothing typed
        // the rows on screen ARE the whole list: asking for both would be one
        // walk per redraw for nothing.
        var walks = 0
        _ = LayerListSlide.key(shown: whole, whole: { walks += 1; return whole }(),
                               isSearching: false)
        #expect(walks == 0)
    }
}
