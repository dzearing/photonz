import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// Animated charts you can drop into a video (task
/// `animated-charts-you-can-drop-into-a-video`).
///
/// Written before the code. A chart is a title: one group of ordinary layers
/// on the timeline whose parts come in on their own beats, restyled by the same
/// theme, font pair, energy and background knobs. What it adds is its data,
/// kept on the title so editing a number lays the chart out again, and a number
/// that counts up to the value its own words hold.
@Suite("Animated charts")
struct AnimatedChartTests {

    static let canvas = CGSize(width: 1920, height: 1080)

    static func placed(_ kind: ChartKind) throws -> (PhotonzDocument, UUID) {
        var doc = TitleRestyleTests.tenSeconds()
        let landed = doc.insertTitle(.chart(kind), atTimeMS: 2_000)
        let inserted = try #require(landed)
        return (doc, inserted.layerID)
    }

    static func piece(_ doc: PhotonzDocument, _ id: UUID, _ path: String) -> Layer? {
        TitleRestyleTests.piece(doc, id, path)
    }

    static func string(_ doc: PhotonzDocument, atMS ms: Int, _ id: UUID, _ path: String) -> String? {
        let drawn = doc.drawn(atTimeMS: ms)
        return drawn.layer(id: id).flatMap { TitleDesign.find(path, in: $0) }?.text?.string
    }

    // MARK: - Data in

    @Test("Pasted tab separated rows become label and value rows")
    func pastedTabs() {
        let rows = ChartSpec.rows(pasted: "Q1\t12\nQ2\t18.5\nQ3\t9\n")
        #expect(rows.map(\.label) == ["Q1", "Q2", "Q3"])
        #expect(rows.map(\.value) == [12, 18.5, 9])
    }

    @Test("Pasted comma separated rows drop a header and read money, percents and thousands")
    func pastedCommas() {
        let rows = ChartSpec.rows(pasted: "Region,Revenue\nNorth,\"$1,200\"\nSouth,850\nWest,42%\r\n")
        #expect(rows.map(\.label) == ["North", "South", "West"])
        #expect(rows.map(\.value) == [1200, 850, 42])
    }

    @Test("A pasted colour column colours its row")
    func pastedColour() {
        let rows = ChartSpec.rows(pasted: "Mac\t40\t#FF9500\nPhone\t60")
        #expect(rows[0].colorHex == "#FF9500")
        #expect(rows[1].colorHex == nil)
    }

    @Test("Nothing with a number in it is no rows")
    func pastedNothing() {
        #expect(ChartSpec.rows(pasted: "just words\nand more").isEmpty)
    }

    // MARK: - Numbers out

    @Test("A format writes prefix, thousands, decimals and suffix")
    func formats() {
        #expect(ChartNumberFormat(prefix: "$", decimals: 1).string(1234.5) == "$1,234.5")
        #expect(ChartNumberFormat(suffix: "%").string(42) == "42%")
        #expect(ChartNumberFormat().string(1_000_000) == "1,000,000")
        #expect(ChartNumberFormat(decimals: 2).string(-3.5) == "-3.50")
    }

    @Test("Every unit on offer is a prefix or a suffix")
    func units() {
        #expect(ChartNumberFormat.Unit.allCases.contains(.dollars))
        #expect(ChartNumberFormat(unit: .dollars).string(5) == "$5")
        #expect(ChartNumberFormat(unit: .percent).string(5) == "5%")
        #expect(ChartNumberFormat(unit: .none).unit == ChartNumberFormat.Unit.none)
    }

    // MARK: - Counting

    @Test("Words holding a number count from nought to it, keeping how it is written")
    func countsUp() {
        let count = TextCount(startMS: 1_000, lengthMS: 1_000, curve: .linear)
        #expect(count.string(for: "$1,240", atMS: 0) == "$0")
        #expect(count.string(for: "$1,240", atMS: 1_500) == "$620")
        #expect(count.string(for: "$1,240", atMS: 2_000) == "$1,240")
        #expect(count.string(for: "$1,240", atMS: 9_000) == "$1,240")
        #expect(count.string(for: "+18.5%", atMS: 1_500) == "+9.3%")
        #expect(count.string(for: "No number", atMS: 1_500) == "No number")
    }

    @Test("A count is saved with its text, and a frame drawn at a moment is never saved counting")
    func countIsCodable() throws {
        var text = TextContent(string: "42")
        text.count = TextCount(startMS: 0, lengthMS: 800, curve: .easeOut)
        let data = try JSONEncoder().encode(text)
        let back = try JSONDecoder().decode(TextContent.self, from: data)
        #expect(back.count == text.count)
        let old = try JSONDecoder().decode(TextContent.self, from: Data(##"{"string":"a","fontName":"SF Pro","fontSize":12,"colorHex":"#FFFFFF"}"##.utf8))
        #expect(old.count == nil)
    }

    // MARK: - Every kind lands

    @Test("Every chart kind lands as a title on the timeline, keeping its data", arguments: ChartKind.allCases)
    func everyKindLands(_ kind: ChartKind) throws {
        let (doc, id) = try Self.placed(kind)
        let title = try #require(doc.layer(id: id))
        #expect(title.isPlacedInTime)
        let recipe = try #require(doc.titleRecipe(layerID: id))
        #expect(recipe.chart?.kind == kind)
        #expect(doc.titlePartTimings(layerID: id).count >= 3)
        // Something visible on its first frame would be a chart that does not build.
        #expect(TitlePreset.chart(kind).kind == .chart)
    }

    @Test("Charts are on the shelf, filed in the catalog under Animated Charts")
    func onTheShelf() {
        let shelf = TitlePreset.shelf(saved: [])
        let charts = shelf.filter { $0.kind == .chart }
        #expect(charts.count == ChartKind.allCases.count)
        let catalog = VideoCatalog.assemble(titles: shelf, backgrounds: [], transitions: [], pictures: [],
                                            components: [])
        let filed = catalog.groups(category: .animatedCharts, query: "", builtForVideoOnly: true)
        #expect(filed.first?.items.count == ChartKind.allCases.count)
        #expect(TitlePreset(entryID: TitlePreset.chart(.donut).id, saved: []) == .chart(.donut))
    }

    @Test("Each chart's tile can be pictured and played")
    func tilesPlay() throws {
        for kind in ChartKind.allCases {
            let preset = TitlePreset.chart(kind)
            #expect(preset.preview(frame: Self.canvas, width: 320) != nil, "\(kind)")
            let reel = try #require(preset.reel(frame: Self.canvas, width: 160, fps: 10), "\(kind)")
            #expect(reel.pictures.count > 5)
        }
    }

    // MARK: - Building in

    @Test("A bar chart's bars arrive one after another, each growing up from its foot")
    func barsStagger() throws {
        let (doc, id) = try Self.placed(.bar)
        let rows = try #require(doc.titleRecipe(layerID: id)?.chart?.rows)
        var starts: [Int] = []
        for index in rows.indices {
            let bar = try #require(Self.piece(doc, id, "Bar \(index + 1)"))
            let crop = try #require(bar.motions?.first { $0.property == .cropTop })
            starts.append(crop.keyframes.map(\.atMS).min() ?? 0)
        }
        #expect(starts == starts.sorted())
        #expect(Set(starts).count == starts.count)
        // On the title's first frame nothing of any bar is showing.
        let first = doc.drawn(atTimeMS: 2_000)
        let bar = try #require(first.layer(id: id).flatMap { TitleDesign.find("Bar 1", in: $0) })
        #expect(bar.style.opacity < 0.05 || (bar.keyStill(.cropTop).flatMap { if case .number(let n) = $0 { n } else { nil } } ?? 0) > 95)
    }

    @Test("A horizontal bar chart's bars grow out to the right")
    func horizontalGrowsRight() throws {
        let (doc, id) = try Self.placed(.horizontalBar)
        let bar = try #require(Self.piece(doc, id, "Bar 1"))
        #expect(bar.motions?.contains { $0.property == .cropRight } == true)
    }

    @Test("A line chart's line draws itself on")
    func lineDraws() throws {
        let (doc, id) = try Self.placed(.line)
        let line = try #require(Self.piece(doc, id, "Line"))
        guard case .path(let path) = line.content else {
            Issue.record("the line is not a path")
            return
        }
        #expect(path.anchors.count == (doc.titleRecipe(layerID: id)?.chart?.rows.count ?? 0))
        #expect(line.motions?.contains { $0.property == .trimEnd } == true)
    }

    @Test("A donut's slices sweep round one after another")
    func donutSweeps() throws {
        let (doc, id) = try Self.placed(.donut)
        let rows = try #require(doc.titleRecipe(layerID: id)?.chart?.rows)
        var starts: [Int] = []
        for index in rows.indices {
            let slice = try #require(Self.piece(doc, id, "Slice \(index + 1)"))
            let trim = try #require(slice.motions?.first { $0.property == .trimEnd })
            starts.append(trim.keyframes.map(\.atMS).min() ?? 0)
        }
        #expect(starts == starts.sorted())
    }

    @Test("A big number counts up to its value as it arrives")
    func bigNumberCounts() throws {
        let (doc, id) = try Self.placed(.bigNumber)
        let spec = try #require(doc.titleRecipe(layerID: id)?.chart)
        let final = spec.format.string(spec.rows[0].value)
        let number = try #require(Self.piece(doc, id, "Number"))
        #expect(number.text?.string == final)
        #expect(number.text?.count != nil)
        let early = try #require(Self.string(doc, atMS: 2_250, id, "Number"))
        #expect(early != final)
        let arrived = 2_000 + doc.titleArrivalMS(layerID: id)
        #expect(Self.string(doc, atMS: arrived, id, "Number") == final)
        #expect(Self.piece(doc, id, "Delta")?.text?.string == spec.delta)
    }

    @Test("A comparison is two or three cards, each with a number that counts")
    func comparisonCards() throws {
        let (doc, id) = try Self.placed(.comparison)
        let spec = try #require(doc.titleRecipe(layerID: id)?.chart)
        #expect((2...3).contains(spec.rows.count))
        for index in spec.rows.indices {
            #expect(Self.piece(doc, id, "Card \(index + 1)") != nil)
            #expect(Self.piece(doc, id, "Number \(index + 1)")?.text?.count != nil)
        }
    }

    @Test("The timeline names a chart's parts for what they are")
    func partNames() throws {
        let (doc, id) = try Self.placed(.bar)
        let names = doc.titlePartTimings(layerID: id).map(\.name)
        #expect(names.contains("Bar 1"))
        #expect(names.contains("Background"))
        #expect(names.contains("Title"))
    }

    // MARK: - Editing it

    @Test("New rows lay the chart out again with one bar each, and pieces kept by name keep their ids")
    func editRows() throws {
        var (doc, id) = try Self.placed(.bar)
        let bar1 = try #require(Self.piece(doc, id, "Bar 1")?.id)
        let changed = doc.editChart(layerID: id) { spec in
            spec.rows = ChartSpec.rows(pasted: "A\t1\nB\t2\nC\t3\nD\t4\nE\t5")
        }
        #expect(changed)
        #expect(Self.piece(doc, id, "Bar 5") != nil)
        #expect(Self.piece(doc, id, "Bar 6") == nil)
        #expect(Self.piece(doc, id, "Bar 1")?.id == bar1)
        #expect(Self.piece(doc, id, "Value 5")?.text?.string == "5")
        #expect(Self.piece(doc, id, "Label 3")?.text?.string == "C")
        // The tallest bar is the biggest value.
        let five = try #require(Self.piece(doc, id, "Bar 5")?.frame.height)
        let one = try #require(Self.piece(doc, id, "Bar 1")?.frame.height)
        #expect(five > one * 4)
        #expect(doc.titlePartTimings(layerID: id).contains { $0.name == "Bar 5" })
    }

    @Test("A unit and decimals are written on every value")
    func editFormat() throws {
        var (doc, id) = try Self.placed(.bar)
        doc.editChart(layerID: id) { spec in
            spec.rows = [ChartRow(label: "A", value: 1.5), ChartRow(label: "B", value: 2)]
            spec.format = ChartNumberFormat(unit: .dollars, decimals: 1)
        }
        #expect(Self.piece(doc, id, "Value 1")?.text?.string == "$1.5")
        #expect(Self.piece(doc, id, "Value 2")?.text?.string == "$2.0")
    }

    @Test("A row's own colour paints its bar whatever the theme")
    func rowColour() throws {
        var (doc, id) = try Self.placed(.bar)
        doc.editChart(layerID: id) { $0.rows[1].colorHex = "#FF2D55" }
        doc.restyleTitle(layerID: id) { $0.theme = TitleTheme.curated[3] }
        #expect(Self.piece(doc, id, "Bar 2").map(TitleRestyler.ink) == "#FF2D55")
        #expect(Self.piece(doc, id, "Bar 1").map(TitleRestyler.ink) == TitleTheme.curated[3].accent)
    }

    @Test("A theme and a font pair restyle a chart like any title")
    func themes() throws {
        var (doc, id) = try Self.placed(.bar)
        let paper = try #require(TitleTheme.curated.first { $0.id == "paper" })
        let swiss = try #require(TitleFontPair.curated.first { $0.id == "swiss" })
        doc.restyleTitle(layerID: id) {
            $0.theme = paper
            $0.fonts = swiss
        }
        #expect(Self.piece(doc, id, "Title")?.text?.colorHex == paper.primary)
        #expect(Self.piece(doc, id, "Title")?.text?.fontName == swiss.display)
        #expect(Self.piece(doc, id, "Label 1")?.text?.fontName == swiss.text)
        #expect(Self.piece(doc, id, "Bar 1").map(TitleRestyler.ink) == paper.accent)
    }

    @Test("Words typed on the canvas are read back into the chart's data")
    func canvasEditsReadBack() throws {
        var (doc, id) = try Self.placed(.bar)
        let label = try #require(Self.piece(doc, id, "Label 2"))
        let value = try #require(Self.piece(doc, id, "Value 2"))
        doc.updateLayer(id: label.id) { layer in
            if case .text(var text) = layer.content { text.string = "Spring"; layer.content = .text(text) }
        }
        doc.updateLayer(id: value.id) { layer in
            if case .text(var text) = layer.content { text.string = "99"; layer.content = .text(text) }
        }
        doc.relayOutTitle(layerID: id)
        let spec = try #require(doc.titleRecipe(layerID: id)?.chart)
        #expect(spec.rows[1].label == "Spring")
        #expect(spec.rows[1].value == 99)
    }

    @Test("A chart's recipe survives saving")
    func recipeCodable() throws {
        let (doc, id) = try Self.placed(.donut)
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.titleRecipe(layerID: id)?.chart == doc.titleRecipe(layerID: id)?.chart)
    }

    @Test("Hiding the background leaves the chart's words throwing a shade to read over footage")
    func overFootage() throws {
        var (doc, id) = try Self.placed(.bar)
        doc.restyleTitle(layerID: id) { $0.showsBackground = false }
        let label = try #require(Self.piece(doc, id, "Label 1"))
        #expect(!label.style.shadows.isEmpty)
    }
}
