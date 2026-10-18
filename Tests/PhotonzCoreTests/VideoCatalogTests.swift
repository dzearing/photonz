import Foundation
import PhotonzCore
import Testing

@Suite("Video catalog")
struct VideoCatalogTests {

    private func picture(_ name: String) -> LibraryEntry {
        LibraryEntry(id: UUID().uuidString, scope: .media, name: name, detail: "1 layer")
    }

    private func component(_ name: String) -> LibraryEntry {
        LibraryEntry(id: UUID().uuidString, scope: .components, name: name, detail: "Starter")
    }

    private var everything: VideoCatalog {
        VideoCatalog.assemble(titles: TitlePreset.shelf(saved: []),
                              backgrounds: LiveLook.allCases,
                              transitions: ClipTransitionKind.allCases,
                              pictures: [picture("Logo")],
                              components: [component("Badge"), component("Button")])
    }

    // MARK: Which pivots a document gets

    @Test func aVideoGetsMediaAndTheCatalogOnly() {
        #expect(LibraryScope.scopes(hasTime: true) == [.media, .catalog])
        #expect(!LibraryScope.scopes(hasTime: true).contains(.styles))
        #expect(!LibraryScope.scopes(hasTime: true).contains(.systems))
    }

    @Test func aPictureKeepsItsFourPivotsAndNoCatalog() {
        #expect(LibraryScope.scopes(hasTime: false) == [.media, .components, .styles, .systems])
    }

    @Test func aStoredPivotTheDocumentDoesNotOfferFallsToTheNearestOne() {
        // A shelf left on Components or Styles in a picture opens a video on
        // its catalog, and the catalog left behind opens a picture on
        // Components: the nearest thing to what was being browsed.
        #expect(LibraryScope.resolved(.components, hasTime: true) == .catalog)
        #expect(LibraryScope.resolved(.styles, hasTime: true) == .catalog)
        #expect(LibraryScope.resolved(.systems, hasTime: true) == .catalog)
        #expect(LibraryScope.resolved(.media, hasTime: true) == .media)
        #expect(LibraryScope.resolved(.catalog, hasTime: false) == .components)
        #expect(LibraryScope.resolved(.styles, hasTime: false) == .styles)
    }

    @Test func theCatalogPivotHasShortHumanCopy() {
        #expect(LibraryScope.catalog.segmentTitle.count <= 8)
        #expect(LibraryScope.catalog.title == "Catalog")
        #expect(!LibraryScope.catalog.emptyMessage.contains("\u{2014}"))
    }

    // MARK: Every item is filed under its kind

    @Test func titlesSplitIntoTitlePagesAndNameCards() {
        let catalog = everything
        let pages = catalog.items.filter { $0.category == .titlePages }
        let cards = catalog.items.filter { $0.category == .nameCards }
        #expect(pages.count == BuiltInTitle.presets(of: .titlePage).count)
        #expect(cards.count == BuiltInTitle.presets(of: .nameCard).count)
        // A title keeps its shelf id, so picking it opens the same section and
        // a drag carries the same preset as before.
        #expect(pages.first?.id == TitlePreset.builtIn(.keynote).id)
    }

    @Test func backgroundsTransitionsAndPicturesHaveTheirOwnCategories() {
        let catalog = everything
        #expect(catalog.items.filter { $0.category == .backgrounds }.count == LiveLook.allCases.count)
        #expect(catalog.items.filter { $0.category == .transitions }.count == ClipTransitionKind.allCases.count)
        #expect(catalog.items.filter { $0.category == .logos }.map(\.entry.name) == ["Logo"])
    }

    @Test func everyItemButAComponentIsBuiltForVideo() {
        for item in everything.items {
            #expect(item.builtForVideo == (item.category != .components), "\(item.entry.name)")
        }
    }

    @Test func itemsCarryTheirKindAsTheirDetail() {
        let cube = everything.items.first { $0.id == VideoCatalog.transitionID(.cube) }
        #expect(cube?.entry.name == "Cube")
        #expect(cube?.entry.detail == "Transition")
        let aurora = everything.items.first { $0.id == VideoCatalog.backgroundID(.aurora) }
        #expect(aurora?.entry.detail == "Background")
        #expect(VideoCatalog.transition(id: VideoCatalog.transitionID(.cube)) == .cube)
        #expect(VideoCatalog.background(id: VideoCatalog.backgroundID(.aurora)) == .aurora)
        #expect(VideoCatalog.background(id: "title.builtIn.keynote") == nil)
    }

    // MARK: Categories and counts

    @Test func onlyCategoriesWithSomethingInThemAreShown() {
        let counts = everything.categories(builtForVideoOnly: true)
        #expect(counts.map(\.category) == [.titlePages, .nameCards, .backgrounds, .transitions, .logos])
        #expect(counts.first { $0.category == .backgrounds }?.count == LiveLook.allCases.count)
        // Nothing ships under these yet, so they are not chips to click into
        // an empty shelf.
        #expect(!counts.contains { $0.category == .animatedCharts })
        #expect(!counts.contains { $0.category == .endCards })
    }

    @Test func componentsAppearOnlyWithBuiltForVideoOff() {
        let on = everything.categories(builtForVideoOnly: true)
        let off = everything.categories(builtForVideoOnly: false)
        #expect(!on.contains { $0.category == .components })
        #expect(off.last?.category == .components)
        #expect(off.last?.count == 2)
        #expect(VideoCatalogCategory.components.title == "Components")
        #expect(VideoCatalogCategory.components.note == "for mockups")
    }

    @Test func aDocumentWithNoPicturesHasNoLogoCategory() {
        let catalog = VideoCatalog.assemble(titles: TitlePreset.shelf(saved: []), backgrounds: [],
                                            transitions: [], pictures: [], components: [])
        #expect(catalog.categories(builtForVideoOnly: true).map(\.category) == [.titlePages, .nameCards])
    }

    // MARK: What the shelf shows

    @Test func allShowsEveryCategoryInItsOwnGroup() {
        let groups = everything.groups(category: nil, query: "", builtForVideoOnly: true)
        #expect(groups.map(\.category) == [.titlePages, .nameCards, .backgrounds, .transitions, .logos])
    }

    @Test func aCategoryShowsOnlyItsOwnItems() {
        let groups = everything.groups(category: .nameCards, query: "", builtForVideoOnly: true)
        #expect(groups.map(\.category) == [.nameCards])
        #expect(groups.first?.items.allSatisfy { $0.category == .nameCards } == true)
    }

    @Test func aHiddenCategoryShowsNothingRatherThanComponentsWithTheFilterOn() {
        #expect(everything.groups(category: .components, query: "", builtForVideoOnly: true).isEmpty)
        #expect(everything.groups(category: .components, query: "", builtForVideoOnly: false).count == 1)
    }

    @Test func searchRunsAcrossEveryCategoryWhateverIsPicked() {
        let groups = everything.groups(category: .titlePages, query: "light", builtForVideoOnly: true)
        let names = groups.flatMap(\.items).map(\.entry.name)
        // Light Leak is a title page, Light Rays and Light Leaks are backgrounds.
        #expect(names.contains("Light Leak"))
        #expect(names.contains("Light Rays"))
        #expect(Set(groups.map(\.category)) == [.titlePages, .backgrounds])
    }

    @Test func searchFindsItemsByTheirKind() {
        let groups = everything.groups(category: nil, query: "transition", builtForVideoOnly: true)
        #expect(groups.map(\.category) == [.transitions])
        #expect(groups.first?.items.count == ClipTransitionKind.allCases.count)
        let cards = everything.groups(category: nil, query: "name card", builtForVideoOnly: true)
        #expect(cards.map(\.category) == [.nameCards])
    }

    @Test func searchCountsAreWhatTheSearchFound() {
        let counts = everything.categories(builtForVideoOnly: true, query: "cube")
        #expect(counts.map(\.category) == [.transitions])
        #expect(counts.first?.count == 1)
    }

    @Test func searchLeavesComponentsOutWhileTheFilterIsOn() {
        #expect(everything.groups(category: nil, query: "badge", builtForVideoOnly: true).isEmpty)
        #expect(everything.groups(category: nil, query: "badge", builtForVideoOnly: false)
            .map(\.category) == [.components])
    }

    // MARK: The remembered category

    @Test func aRememberedCategoryStandsWhileItHasItems() {
        let shown = everything.categories(builtForVideoOnly: true).map(\.category)
        #expect(VideoCatalog.resolvedCategory("nameCards", shown: shown) == .nameCards)
        // Gone (components with the filter back on, or a typo): All.
        #expect(VideoCatalog.resolvedCategory("components", shown: shown) == nil)
        #expect(VideoCatalog.resolvedCategory("", shown: shown) == nil)
        #expect(VideoCatalog.resolvedCategory("nope", shown: shown) == nil)
    }

    @Test func categoryNamesAreShortEnoughForAChip() {
        for category in VideoCatalogCategory.allCases {
            #expect(category.title.count <= 16, "\(category.title)")
            #expect(!category.title.contains("\u{2014}"))
        }
    }

    // MARK: A background off the catalog

    @Test func aBackgroundLandsFullFrameOnAGfxTrackForFiveSeconds() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080), layers: [])
        document.durationMS = 8_000
        let landing = document.backgroundLanding(atMS: 2_000, over: nil)
        #expect(landing.trackName == "Gfx")
        #expect(landing.lengthMS == VideoCatalog.backgroundLengthMS)
        let landed = document.landBackground(.aurora, at: landing)
        let id = try #require(landed)
        let layer = try #require(document.layer(id: id))
        #expect(layer.name == "Aurora")
        #expect(layer.time?.inMS == 2_000)
        #expect(layer.time?.outMS == 7_000)
        #expect(layer.frame == CGRect(x: 0, y: 0, width: 1920, height: 1080))
        guard case .annotation(let content) = layer.content else {
            Issue.record("a background is a filled rectangle")
            return
        }
        #expect(content.fill?.kind == .live)
        #expect(content.fill?.live?.look == .aurora)
        #expect(document.trackID(ofClip: id) != nil)
    }

    @Test func everyBackgroundHasItsOwnColours() {
        // Ten tiles in one palette read as one tile ten times.
        let grounds = Set(LiveLook.allCases.map { VideoCatalog.backgroundPaint($0).stops.map(\.hex) })
        #expect(grounds.count > 1)
        for look in LiveLook.allCases {
            #expect(VideoCatalog.backgroundPaint(look).live?.look == look)
        }
    }
}
