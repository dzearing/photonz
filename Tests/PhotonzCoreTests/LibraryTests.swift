import Foundation
import PhotonzCore
import Testing

@Suite("Library")
struct LibraryTests {

    private func item(_ name: String, _ scope: LibraryScope = .media) -> LibraryEntry {
        LibraryEntry(id: name, scope: scope, name: name, detail: "")
    }

    // MARK: Scopes

    @Test func offersTheFourScopesInOrder() {
        #expect(LibraryScope.allCases == [.media, .components, .styles, .systems])
        #expect(LibraryScope.media.title == "Media")
        #expect(LibraryScope.components.title == "Components")
        #expect(LibraryScope.styles.title == "Styles")
        #expect(LibraryScope.systems.title == "Systems")
    }

    @Test func segmentLabelsStayShortEnoughForANarrowPanel() {
        for scope in LibraryScope.allCases {
            #expect(scope.segmentTitle.count <= 8)
            #expect(scope.segmentTitle.isEmpty == false)
        }
    }

    @Test func eachScopeNamesOneItemForTheInspectorHeader() {
        #expect(LibraryScope.media.itemTitle == "Media")
        #expect(LibraryScope.components.itemTitle == "Component")
        #expect(LibraryScope.styles.itemTitle == "Style")
        #expect(LibraryScope.systems.itemTitle == "System")
    }

    @Test func everyScopeCarriesItsOwnSearchPlaceholderAndEmptyCopy() {
        for scope in LibraryScope.allCases {
            #expect(scope.searchPlaceholder.isEmpty == false)
            #expect(scope.emptyMessage.isEmpty == false)
            // Plain human copy: no em dashes anywhere a person reads (repo rule).
            #expect(scope.emptyMessage.contains("\u{2014}") == false)
            #expect(scope.searchPlaceholder.contains("\u{2014}") == false)
        }
    }

    @Test func emptyCopySaysWhyItIsEmptyUnlessASearchIsOn() {
        let scope = LibraryScope.components
        #expect(scope.emptyMessage(searching: "") == scope.emptyMessage)
        #expect(scope.emptyMessage(searching: "   ") == scope.emptyMessage)
        let searching = scope.emptyMessage(searching: "card")
        #expect(searching != scope.emptyMessage)
        #expect(searching.isEmpty == false)
    }

    @Test func scopesRoundTripThroughTheirStoredNames() {
        for scope in LibraryScope.allCases {
            #expect(LibraryScope(rawValue: scope.rawValue) == scope)
        }
        #expect(LibraryScope(rawValue: "nope") == nil)
    }

    // MARK: Search

    @Test func anEmptyQueryKeepsEveryItem() {
        let items = [item("Card"), item("Button")]
        #expect(LibrarySearch.filter(items, query: "") == items)
        #expect(LibrarySearch.filter(items, query: "   \n") == items)
    }

    @Test func matchingIgnoresCaseAndSurroundingSpace() {
        #expect(LibrarySearch.matches(name: "Primary Button", query: "button"))
        #expect(LibrarySearch.matches(name: "Primary Button", query: "  BUTTON "))
        #expect(LibrarySearch.matches(name: "Primary Button", query: "prim"))
        #expect(LibrarySearch.matches(name: "Primary Button", query: "zzz") == false)
    }

    @Test func matchingIgnoresAccents() {
        #expect(LibrarySearch.matches(name: "Café card", query: "cafe"))
        #expect(LibrarySearch.matches(name: "Cafe card", query: "café"))
    }

    @Test func everyWordOfTheQueryHasToAppearSomewhereInTheName() {
        #expect(LibrarySearch.matches(name: "Screenshot 2026-09-02 at 9.41", query: "screenshot 9.41"))
        // Order does not matter, so typing the words you remember still finds it.
        #expect(LibrarySearch.matches(name: "Screenshot 2026-09-02 at 9.41", query: "9.41 screenshot"))
        #expect(LibrarySearch.matches(name: "Screenshot 2026-09-02 at 9.41", query: "screenshot nope") == false)
    }

    @Test func filteringKeepsTheOriginalOrder() {
        let items = [item("Ghost button"), item("Card"), item("Primary button")]
        let hits = LibrarySearch.filter(items, query: "button")
        #expect(hits.map(\.name) == ["Ghost button", "Primary button"])
    }

    @Test func filteringSearchesTheDetailLineToo() {
        let dated = LibraryEntry(id: "1", scope: .media, name: "Screenshot", detail: "Yesterday · PNG")
        #expect(LibrarySearch.filter([dated], query: "png").count == 1)
        #expect(LibrarySearch.filter([dated], query: "gif").isEmpty)
    }

    // MARK: Items

    @Test func itemsAreIdentifiedByTheirIdAlone() {
        let a = LibraryEntry(id: "x", scope: .media, name: "One", detail: "")
        let b = LibraryEntry(id: "x", scope: .media, name: "One", detail: "")
        #expect(a == b)
        #expect(a.id == b.id)
    }

    @Test func itemsOfAScopeAreTheOnesTheScopeShows() {
        let mixed = [item("A", .media), item("B", .components), item("C", .media)]
        #expect(LibrarySearch.filter(mixed, scope: .media, query: "").map(\.name) == ["A", "C"])
        #expect(LibrarySearch.filter(mixed, scope: .styles, query: "").isEmpty)
        #expect(LibrarySearch.filter(mixed, scope: .media, query: "c").map(\.name) == ["C"])
    }
}

@Suite("Library naming")
struct LibraryNamingTests {

    private let taken = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func aCaptureTheAppNamedItselfIsCaptionedByWhenItWasTaken() {
        let caption = LibraryNaming.caption(fileName: "Screenshot 2026-06-21 at 10.30.45",
                                            takenAt: taken, now: taken.addingTimeInterval(3600))
        #expect(caption == "1 hour ago")
    }

    @Test func soIsARecording() {
        #expect(LibraryNaming.isDefaultCaptureName("Recording 2026-06-21 at 10.30.45"))
        #expect(LibraryNaming.isDefaultCaptureName("Screenshot 2026-06-21 at 10.30.45 (2)"))
    }

    @Test func aNameSomeoneChoseIsKept() {
        #expect(LibraryNaming.isDefaultCaptureName("Settings pane") == false)
        #expect(LibraryNaming.isDefaultCaptureName("Screenshots of the week") == false)
        #expect(LibraryNaming.isDefaultCaptureName("Screenshot") == false)
        let caption = LibraryNaming.caption(fileName: "Settings pane",
                                            takenAt: taken, now: taken.addingTimeInterval(3600))
        #expect(caption == "Settings pane")
    }
}
