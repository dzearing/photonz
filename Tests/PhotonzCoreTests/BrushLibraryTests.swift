import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **Brushes are picked from tiles, grouped by kind.** The Library's Brushes
/// shelf and the chooser over the tool bar both read this one list, so a brush
/// added to the app turns up as a tile in both without a second list
/// (`brush-library.html`; the user, 2026-10-24: "There should also be a better
/// chooser than a dropdown without previewing").
///
/// Written before the code.
@Suite("Brushes are picked from a library of tiles")
struct BrushLibraryTests {

    // MARK: - Groups

    @Test func theGroupsAreTheMocksInItsOrder() {
        #expect(BrushGroup.allCases.map(\.title) == ["Sketch", "Ink", "Paint", "Airbrush", "Texture"])
        // The dock is narrow, so the mock shortens one chip there.
        #expect(BrushGroup.airbrush.chipTitle == "Air")
        #expect(BrushGroup.sketch.chipTitle == "Sketch")
    }

    @Test func everyBrushIsInExactlyOneGroupAndAllHoldsEveryBrush() {
        let all = BrushLibrary.brushes(in: nil)
        #expect(Set(all) == Set(BrushMedium.allCases))
        #expect(all.count == BrushMedium.allCases.count)
        let grouped = BrushGroup.allCases.flatMap { BrushLibrary.brushes(in: $0) }
        #expect(grouped.count == BrushMedium.allCases.count)
        #expect(Set(grouped) == Set(BrushMedium.allCases))
    }

    @Test func allIsOrderedByGroupThenTheOrderTheMediaAreOffered() {
        let all = BrushLibrary.brushes(in: nil)
        let groupIndex = all.map { BrushGroup.allCases.firstIndex(of: $0.group) ?? -1 }
        #expect(groupIndex == groupIndex.sorted())
        #expect(all.first == .pencil)
    }

    @Test func theMediaLandInTheGroupsAPainterWouldLookIn() {
        #expect(BrushMedium.pencil.group == .sketch)
        #expect(BrushMedium.charcoal.group == .sketch)
        #expect(BrushMedium.marker.group == .ink)
        #expect(BrushMedium.oil.group == .paint)
        #expect(BrushMedium.watercolour.group == .paint)
        #expect(BrushMedium.airbrush.group == .airbrush)
        #expect(BrushMedium.chalk.group == .texture)
        #expect(BrushMedium.crayon.group == .texture)
    }

    @Test func everyGroupHoldsAtLeastOneBrush() {
        for group in BrushGroup.allCases {
            #expect(!BrushLibrary.brushes(in: group).isEmpty, "\(group.title) is empty")
        }
    }

    // MARK: - Search

    @Test func searchFindsByNameAndByGroup() {
        #expect(BrushLibrary.brushes(in: nil, query: "oil") == [.oil])
        #expect(BrushLibrary.brushes(in: nil, query: "WATER") == [.watercolour])
        #expect(Set(BrushLibrary.brushes(in: nil, query: "paint")) == [.oil, .watercolour])
        #expect(BrushLibrary.brushes(in: nil, query: "   ") == BrushLibrary.brushes(in: nil))
        #expect(BrushLibrary.brushes(in: .ink, query: "oil").isEmpty)
    }

    // MARK: - What a tile says

    @Test func everyBrushHasAShortLineAboutIt() {
        for medium in BrushMedium.allCases {
            let line = medium.blurb
            #expect(!line.isEmpty)
            // The panel's budget for a line (UX-PATTERNS §4).
            #expect(line.count <= 40, "\(medium.title): \(line)")
            #expect(!line.contains("\u{2014}"), "no em dashes in copy")
        }
    }

    @Test func aTileIsNamedByAnIdThatSurvivesARename() {
        for medium in BrushMedium.allCases {
            let id = BrushLibrary.entryID(medium)
            #expect(id.hasPrefix("brush."))
            #expect(BrushLibrary.medium(forEntryID: id) == medium)
        }
        #expect(BrushLibrary.medium(forEntryID: "brush.nothing") == nil)
        #expect(BrushLibrary.medium(forEntryID: "pencil") == nil)
    }

    // MARK: - Keys in the chooser

    @Test func arrowsMoveAlongTheGridAndStopAtItsEdges() {
        // Eight tiles, three across:  0 1 2 / 3 4 5 / 6 7
        #expect(BrushLibrary.step(from: 0, .right, count: 8, columns: 3) == 1)
        #expect(BrushLibrary.step(from: 2, .right, count: 8, columns: 3) == 3)
        #expect(BrushLibrary.step(from: 7, .right, count: 8, columns: 3) == 7)
        #expect(BrushLibrary.step(from: 0, .left, count: 8, columns: 3) == 0)
        #expect(BrushLibrary.step(from: 3, .left, count: 8, columns: 3) == 2)
        #expect(BrushLibrary.step(from: 1, .down, count: 8, columns: 3) == 4)
        #expect(BrushLibrary.step(from: 4, .down, count: 8, columns: 3) == 7)
        // Down from a column the last row does not reach lands on the last tile.
        #expect(BrushLibrary.step(from: 5, .down, count: 8, columns: 3) == 7)
        #expect(BrushLibrary.step(from: 7, .down, count: 8, columns: 3) == 7)
        #expect(BrushLibrary.step(from: 4, .up, count: 8, columns: 3) == 1)
        #expect(BrushLibrary.step(from: 1, .up, count: 8, columns: 3) == 1)
        // Nothing highlighted yet: any arrow starts at the first tile.
        #expect(BrushLibrary.step(from: nil, .down, count: 8, columns: 3) == 0)
        #expect(BrushLibrary.step(from: nil, .right, count: 0, columns: 3) == nil)
        // A highlight past a shortened list comes back inside it.
        #expect(BrushLibrary.step(from: 9, .left, count: 3, columns: 3) == 1)
    }

    // MARK: - The sample stroke a tile paints

    private let tile = CGSize(width: 150, height: 46)

    @Test func theSampleStrokeIsTheSameEveryTime() {
        for medium in BrushMedium.allCases {
            let settings = BrushSettings(medium: medium)
            let a = BrushSample.stroke(settings: settings, colorHex: "#ff5d8f", in: tile)
            let b = BrushSample.stroke(settings: settings, colorHex: "#ff5d8f", in: tile)
            #expect(a == b)
        }
    }

    @Test func eachBrushHasItsOwnFixedSeed() {
        let seeds = BrushMedium.allCases.map {
            BrushSample.stroke(settings: BrushSettings(medium: $0), colorHex: "#000000", in: tile).seed
        }
        #expect(Set(seeds).count == seeds.count)
    }

    @Test func theSampleIsPaintedWithTheBrushItIsAbout() {
        var settings = BrushSettings(medium: .marker, mode: .smudge)
        settings.set("flow", to: 85)
        settings.set("tip", to: 1)
        let stroke = BrushSample.stroke(settings: settings, colorHex: "#12c2e9", in: tile)
        #expect(stroke.settings.medium == .marker)
        #expect(stroke.settings.value("flow") == 85)
        #expect(stroke.settings.value("tip") == 1)
        #expect(stroke.colorHex == "#12c2e9")
        // A sample always shows what the brush lays down, never a smudge of nothing.
        #expect(stroke.settings.mode == .paint)
    }

    @Test func theSampleStaysInsideItsTile() {
        for medium in BrushMedium.allCases {
            for size in [1.0, 14, 120, 500] {
                var settings = BrushSettings(medium: medium)
                settings.set("size", to: size)
                let stroke = BrushSample.stroke(settings: settings, colorHex: "#000000", in: tile)
                let points = stroke.samples.map(\.point)
                #expect(points.count >= 20)
                let box = CGRect(origin: .zero, size: tile)
                #expect(points.allSatisfy { box.contains($0) })
                // Its tip fits the tile's height, so the stroke reads as a line.
                #expect(stroke.settings.size <= tile.height * 0.5, "\(medium) at \(size)")
                #expect(stroke.settings.size >= 1)
            }
        }
    }

    @Test func aSmallBrushKeepsItsOwnSize() {
        var settings = BrushSettings(medium: .pencil)
        settings.set("size", to: 3)
        #expect(BrushSample.stroke(settings: settings, colorHex: "#000000", in: tile).settings.size == 3)
    }

    @Test func theSampleRunsAcrossTheTile() {
        let stroke = BrushSample.stroke(settings: BrushSettings(medium: .oil), colorHex: "#000000", in: tile)
        let xs = stroke.samples.map(\.point.x)
        #expect((xs.min() ?? 0) < tile.width * 0.15)
        #expect((xs.max() ?? 0) > tile.width * 0.85)
        // Time runs forward, so an airbrush sprays it as a steady pass.
        let times = stroke.samples.map(\.ms)
        #expect(times == times.sorted())
    }

    @Test func aDarkColourIsShownOnPaperAndALightOneOnTheDarkWell() {
        #expect(!BrushSample.wellIsDark(forColorHex: "#000000"))
        #expect(!BrushSample.wellIsDark(forColorHex: "#12243a"))
        #expect(BrushSample.wellIsDark(forColorHex: "#ffffff"))
        #expect(BrushSample.wellIsDark(forColorHex: "#ff5d8f"))
        #expect(BrushSample.wellIsDark(forColorHex: "#f6c453"))
        // Something unreadable falls back to the mock's dark well.
        #expect(BrushSample.wellIsDark(forColorHex: "nonsense"))
    }
}

/// **Brushes are a Library scope.** The Library's shelf in a picture has a
/// Brushes pivot beside Media, Components, Styles and Systems while the brush
/// exists in the release; a video, which has no brush, never offers it
/// (`brush-library.html`: "the Library group, scope Brushes").
@Suite("Brushes are a shelf of the Library")
struct BrushLibraryScopeTests {

    @Test func aPictureWithTheBrushGetsABrushesPivotAfterComponents() {
        #expect(LibraryScope.scopes(hasTime: false, brushes: true)
                == [.media, .components, .brushes, .styles, .systems])
        #expect(LibraryScope.scopes(hasTime: false) == [.media, .components, .styles, .systems])
    }

    @Test func aVideoNeverOffersBrushes() {
        #expect(LibraryScope.scopes(hasTime: true, brushes: true) == [.media, .catalog])
        #expect(LibraryScope.resolved(.brushes, hasTime: true, brushes: true) == .catalog)
    }

    @Test func brushesLeftPickedFallBackWhenTheBrushIsNotThere() {
        #expect(LibraryScope.resolved(.brushes, hasTime: false, brushes: true) == .brushes)
        #expect(LibraryScope.resolved(.brushes, hasTime: false) == .components)
    }

    @Test func theScopeSaysItsWords() {
        #expect(LibraryScope.brushes.title == "Brushes")
        #expect(LibraryScope.brushes.segmentTitle == "Brushes")
        #expect(LibraryScope.brushes.itemTitle == "Brush")
        #expect(LibraryScope.brushes.searchPlaceholder == "Search brushes")
    }
}
