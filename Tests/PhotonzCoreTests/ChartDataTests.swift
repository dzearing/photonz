import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// A chart is your data, given to it the obvious way, and it moves when your
/// numbers do (task `a-chart-is-your-data-given-to-it-the-obvious-way`).
///
/// Written before the code. A table pasted from a spreadsheet or read out of a
/// CSV file becomes a chart; a chart holds more than one set of numbers along
/// its clip and moves from one to the next; negative numbers are drawn on the
/// other side of a visible zero line.
@Suite("Chart data")
struct ChartDataTests {

    // MARK: - Reading a table

    @Test("A spreadsheet's copy is labels, a header and number columns")
    func readsTabs() throws {
        let table = try #require(ChartTable.reading("Quarter\t2025\t2026\nQ1\t12\t15\nQ2\t18\t21\nQ3\t9\t30\nQ4\t24\t27\n"))
        #expect(table.labels == ["Q1", "Q2", "Q3", "Q4"])
        #expect(table.series.map(\.name) == ["2025", "2026"])
        #expect(table.series[0].values == [12, 18, 9, 24])
        #expect(table.series[1].values == [15, 21, 30, 27])
        #expect(table.isClearlyATable)
    }

    @Test("A CSV's quoted fields keep their commas, and money, thousands and percents read as numbers")
    func readsCSV() throws {
        let csv = "Region,\"Revenue, USD\"\n\"North, East\",\"$1,200\"\nSouth,$850\nWest,\"$2,050.50\"\r\n"
        let table = try #require(ChartTable.reading(csv))
        #expect(table.labels == ["North, East", "South", "West"])
        #expect(table.series.first?.name == "Revenue, USD")
        #expect(table.series.first?.values == [1200, 850, 2050.5])
        #expect(table.unit == .dollars)
        #expect(table.decimals == 2)
    }

    @Test("Percents are the unit when every value says so")
    func readsPercents() throws {
        let table = try #require(ChartTable.reading("A,40%\nB,25.5%\nC,-10%"))
        #expect(table.series[0].values == [40, 25.5, -10])
        #expect(table.unit == .percent)
        #expect(table.decimals == 1)
    }

    @Test("A negative written in brackets, or with a true minus, is negative")
    func readsNegatives() {
        #expect(ChartSpec.number(in: "(25)") == -25)
        #expect(ChartSpec.number(in: "\u{2212}3.5") == -3.5)
        #expect(ChartSpec.number(in: "-$1,000") == -1000)
        #expect(ChartSpec.number(in: "$-1,000") == -1000)
    }

    @Test("Semicolons separate cells where a spreadsheet writes them")
    func readsSemicolons() throws {
        let table = try #require(ChartTable.reading("Mon;3\nTue;5"))
        #expect(table.labels == ["Mon", "Tue"])
        #expect(table.series[0].values == [3, 5])
    }

    @Test("Words, a single number or one row are not clearly a table")
    func notTables() {
        #expect(ChartTable.reading("just some words\nmore words")?.isClearlyATable != true)
        #expect(ChartTable.reading("42")?.isClearlyATable != true)
        #expect(ChartTable.reading("Q1\t12")?.isClearlyATable != true)
        #expect(ChartTable.reading("12\n18\n20")?.isClearlyATable != true)
        #expect(ChartTable.reading("https://example.com, a link\nand, words")?.isClearlyATable != true)
    }

    @Test("A header with no numbers names the chart; no header leaves it untitled")
    func headerTitles() throws {
        let titled = ChartSpec(table: try #require(ChartTable.reading("Region\tSignups\nNorth\t4\nSouth\t6")))
        #expect(titled.title == "Signups")
        #expect(titled.rows.map(\.label) == ["North", "South"])
        let bare = ChartSpec(table: try #require(ChartTable.reading("North\t4\nSouth\t6")))
        #expect(bare.title == "")
        #expect(bare.kind == .bar)
    }

    @Test("A table with two number columns is a chart that changes from the first to the second")
    func twoColumnsAreTwoSets() throws {
        let spec = ChartSpec(table: try #require(ChartTable.reading("Quarter,2025,2026\nQ1,12,15\nQ2,18,21")))
        #expect(spec.title == "2025")
        #expect(spec.rows.map(\.value) == [12, 18])
        let steps = try #require(spec.steps)
        #expect(steps.count == 1)
        #expect(steps[0].values == [15, 21])
        #expect(steps[0].title == "2026")
        #expect(steps[0].atMS > 2_500)
        #expect(spec.clipLengthMS >= steps[0].atMS + 2_000)
    }

    @Test("The old paste of rows still reads the way it did")
    func rowsPastedStillWork() {
        #expect(ChartSpec.rows(pasted: "Q1\t12\nQ2\t18.5").map(\.value) == [12, 18.5])
        #expect(ChartSpec.rows(pasted: "Mac\t40\t#FF9500\nPhone\t60")[0].colorHex == "#FF9500")
    }

    // MARK: - Sets of numbers over time

    static func twoSets() -> ChartSpec {
        var spec = ChartSpec(kind: .bar, title: "Signups",
                             rows: [ChartRow(label: "Q1", value: 10), ChartRow(label: "Q2", value: 40)])
        spec.steps = [ChartStep(atMS: 3_000, values: [30, 20], title: "Signups 2026")]
        return spec
    }

    @Test("Before a change its numbers are the first set, after it the second, and between them in between")
    func valuesOverTime() {
        let spec = Self.twoSets()
        #expect(spec.shown(atMS: 0).rows.map(\.value) == [10, 40])
        #expect(spec.shown(atMS: 3_000 - ChartSpec.changeMS).rows.map(\.value) == [10, 40])
        #expect(spec.shown(atMS: 3_000).rows.map(\.value) == [30, 20])
        #expect(spec.shown(atMS: 5_000).rows.map(\.value) == [30, 20])
        let middle = spec.shown(atMS: 3_000 - ChartSpec.changeMS / 2).rows.map(\.value)
        #expect(middle[0] > 10 && middle[0] < 30)
        #expect(middle[1] < 40 && middle[1] > 20)
        #expect(spec.shown(atMS: 5_000).title == "Signups 2026")
        #expect(spec.shown(atMS: 0).title == "Signups")
    }

    @Test("The set at a moment is the one whose change has begun")
    func setAtAMoment() {
        let spec = Self.twoSets()
        #expect(spec.setIndex(atMS: 0) == 0)
        #expect(spec.setIndex(atMS: 2_950) == 1)
        #expect(spec.setIndex(atMS: 9_000) == 1)
        #expect(spec.setCount == 2)
    }

    @Test("A set always has a number for every row")
    func setsMatchRows() {
        var spec = Self.twoSets()
        spec.rows.append(ChartRow(label: "Q3", value: 5))
        let tidy = spec.tidied
        #expect(tidy.steps?[0].values == [30, 20, 5])
        spec.rows.removeLast(2)
        #expect(spec.tidied.steps?[0].values == [30])
    }

    @Test("A set written before sets existed reads back as a chart of one set")
    func oldChartsDecode() throws {
        let json = #"{"kind":"bar","title":"T","rows":[{"label":"A","value":1}],"format":{"prefix":"","suffix":"","decimals":0}}"#
        let spec = try JSONDecoder().decode(ChartSpec.self, from: Data(json.utf8))
        #expect(spec.steps == nil)
        #expect(spec.setCount == 1)
    }

    // MARK: - On the timeline

    static func placed(_ spec: ChartSpec) throws -> (PhotonzDocument, UUID) {
        var doc = TitleRestyleTests.tenSeconds()
        let landed = doc.insertTitle(chart: spec.kind, spec: spec, atTimeMS: 1_000)
        let inserted = try #require(landed)
        return (doc, inserted.layerID)
    }

    static func bar(_ doc: PhotonzDocument, _ id: UUID, _ index: Int, atMS ms: Int) -> CGRect? {
        doc.drawn(atTimeMS: ms).layer(id: id).flatMap { TitleDesign.find("Bar \(index)", in: $0) }?.frame
    }

    @Test("The visual bar: each bar ends the change at its new value within 1% of the axis, and is between halfway")
    func barsMoveToTheirNewValues() throws {
        let (doc, id) = try Self.placed(Self.twoSets())
        // The chart's own clock starts at 1s on the document's.
        let before = try #require(Self.bar(doc, id, 2, atMS: 1_000 + 2_500 - ChartSpec.changeMS))
        let after1 = try #require(Self.bar(doc, id, 1, atMS: 1_000 + 3_200))
        let after2 = try #require(Self.bar(doc, id, 2, atMS: 1_000 + 3_200))
        // The axis is the biggest number the chart ever shows (40), so a
        // bar's height per unit is Q2's first height over 40.
        let perUnit = before.height / 40
        let axis = perUnit * 40
        #expect(abs(after1.height - perUnit * 30) <= axis * 0.01)
        #expect(abs(after2.height - perUnit * 20) <= axis * 0.01)
        // Bars stand on the same baseline throughout.
        #expect(abs(after1.maxY - before.maxY) < 1)
        let half = try #require(Self.bar(doc, id, 2, atMS: 1_000 + 3_000 - ChartSpec.changeMS / 2))
        #expect(half.height < before.height - 1)
        #expect(half.height > after2.height + 1)
        // The value over it counts with it.
        let value = doc.drawn(atTimeMS: 1_000 + 3_200).layer(id: id).flatMap { TitleDesign.find("Value 1", in: $0) }
        #expect(value?.text?.string == "30")
    }

    @Test("A set added at a moment of the chart, edited and taken away again")
    func editingSets() throws {
        var (doc, id) = try Self.placed(ChartSpec.sample(.bar))
        let added = doc.addChartSet(layerID: id, atMS: 4_000)
        let index = try #require(added)
        #expect(index == 1)
        #expect(doc.chartSpec(layerID: id)?.steps?.first?.values == ChartSpec.sample(.bar).rows.map(\.value))
        let typed = doc.editChart(layerID: id, set: 1) { $0[0] = 99 }
        #expect(typed)
        #expect(doc.chartSpec(layerID: id)?.steps?.first?.values.first == 99)
        // The first set is the rows themselves.
        let first = doc.editChart(layerID: id, set: 0) { $0[0] = 7 }
        #expect(first)
        #expect(doc.chartSpec(layerID: id)?.rows.first?.value == 7)
        // A second set at the same moment is refused.
        let again = doc.addChartSet(layerID: id, atMS: 4_000)
        #expect(again == nil)
        let removed = doc.removeChartSet(layerID: id, set: 1)
        #expect(removed)
        #expect(doc.chartSpec(layerID: id)?.steps == nil)
    }

    @Test("Adding a row adds a number to every set, and the chart is laid out from the first")
    func rowsAcrossSets() throws {
        var (doc, id) = try Self.placed(Self.twoSets())
        doc.editChart(layerID: id) { $0.rows.append(ChartRow(label: "Q3", value: 15)) }
        #expect(doc.chartSpec(layerID: id)?.steps?.first?.values.count == 3)
        #expect(TitleRestyleTests.piece(doc, id, "Bar 3") != nil)
    }

    @Test("A chart pasted with several sets is long enough to show them all")
    func longEnoughForItsSets() throws {
        let table = try #require(ChartTable.reading("Q,2023,2024,2025,2026\nA,1,2,3,4\nB,4,3,2,1"))
        let spec = ChartSpec(table: table)
        #expect(spec.steps?.count == 3)
        let (doc, id) = try Self.placed(spec)
        let time = try #require(doc.layer(id: id)?.time)
        let last = try #require(spec.steps?.last?.atMS)
        #expect(time.lengthMS >= last + 1_500)
    }

    // MARK: - Negative numbers

    @Test("A negative bar runs down from a visible zero line, to scale with the positive bars")
    func negativeBars() throws {
        let spec = ChartSpec(kind: .bar, title: "Change",
                             rows: [ChartRow(label: "A", value: 40), ChartRow(label: "B", value: -25),
                                    ChartRow(label: "C", value: 60)])
        let (doc, id) = try Self.placed(spec)
        let a = try #require(TitleRestyleTests.piece(doc, id, "Bar 1")?.frame)
        let b = try #require(TitleRestyleTests.piece(doc, id, "Bar 2")?.frame)
        let c = try #require(TitleRestyleTests.piece(doc, id, "Bar 3")?.frame)
        let zero = try #require(TitleRestyleTests.piece(doc, id, "Baseline")?.frame)
        #expect(abs(a.maxY - zero.minY) <= 2)
        #expect(abs(b.minY - zero.minY) <= 2)
        #expect(b.maxY > zero.maxY)
        let perUnit = c.height / 60
        #expect(abs(a.height - perUnit * 40) <= 2)
        #expect(abs(b.height - perUnit * 25) <= 2)
        // Its number reads below it.
        let value = try #require(TitleRestyleTests.piece(doc, id, "Value 2")?.frame)
        #expect(value.minY >= b.maxY)
        #expect(TitleRestyleTests.piece(doc, id, "Value 2")?.text?.string == "-25")
    }

    @Test("A negative horizontal bar runs left from the zero line")
    func negativeHorizontalBars() throws {
        let spec = ChartSpec(kind: .horizontalBar, title: "Change",
                             rows: [ChartRow(label: "A", value: 40), ChartRow(label: "B", value: -25)])
        let (doc, id) = try Self.placed(spec)
        let a = try #require(TitleRestyleTests.piece(doc, id, "Bar 1")?.frame)
        let b = try #require(TitleRestyleTests.piece(doc, id, "Bar 2")?.frame)
        #expect(abs(b.maxX - a.minX) <= 2)
        #expect(abs(b.width - a.width * 25 / 40) <= 2)
    }

    @Test("A line's point below nought sits below its zero line")
    func negativeLine() throws {
        let spec = ChartSpec(kind: .line, title: "Change",
                             rows: [ChartRow(label: "A", value: 40), ChartRow(label: "B", value: -25),
                                    ChartRow(label: "C", value: 60)])
        let (doc, id) = try Self.placed(spec)
        let dot = try #require(TitleRestyleTests.piece(doc, id, "Dot 2")?.frame)
        let zero = try #require(TitleRestyleTests.piece(doc, id, "Baseline")?.frame)
        #expect(dot.midY > zero.midY + 10)
        let up = try #require(TitleRestyleTests.piece(doc, id, "Dot 1")?.frame)
        #expect(up.midY < zero.midY - 10)
    }

    @Test("A big number counts to a negative with its minus sign")
    func negativeBigNumber() throws {
        let spec = ChartSpec(kind: .bigNumber, title: "", rows: [ChartRow(label: "Churn", value: -12)])
        let (doc, id) = try Self.placed(spec)
        let arrived = 1_000 + doc.titleArrivalMS(layerID: id)
        let drawn = doc.drawn(atTimeMS: arrived).layer(id: id).flatMap { TitleDesign.find("Number", in: $0) }
        #expect(drawn?.text?.string == "-12")
    }

    @Test("Each row's swatch is the colour it is drawn in")
    func rowColours() throws {
        let (doc, id) = try Self.placed(ChartSpec.sample(.donut))
        let colours = doc.chartRowColours(layerID: id)
        #expect(colours.count == 4)
        #expect(Set(colours).count == 4)
        #expect(colours[0] == ChartKind.donut.theme.accent)
    }

    // MARK: - Every motion is the data

    @Test("Nothing in a chart moves for decoration: words fade, data grows, counts and draws", arguments: ChartKind.allCases)
    func motionIsData(_ kind: ChartKind) {
        let design = ChartPen.design(.sample(kind))
        let decorative: Set<TitleBuildKind> = [.rise, .springPop, .scaleFrom, .swingIn, .flipUp, .tiltSettle,
                                               .flyInFromDepth, .blurIn]
        for part in design.parts {
            #expect(!decorative.contains(part.in?.kind ?? .fade), "\(kind) \(part.path) comes in by \(String(describing: part.in?.kind))")
            #expect(part.hold.kind == .none, "\(kind) \(part.path) holds by \(part.hold.kind)")
        }
    }
}
