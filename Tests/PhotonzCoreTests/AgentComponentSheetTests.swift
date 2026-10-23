import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// A sheet of components laid out as a table (the user, 2026-10-20: "there is
/// no table, no alignment, no titles"): every labelled row on the canvas is one
/// table, with a header naming each state once over its column, the
/// components' names down the left, each look centred in its cell on one grid
/// and the same gap between every pair of rows. A look whose state is not its
/// column's keeps its own name under it.
@Suite("Agent add_component: labelled rows make one table")
struct AgentComponentSheetTests {

    static let measure = AgentComponentTests.measure

    /// A component of one box, `width` by `height`, with these looks.
    static func row(_ name: String, x: Int = 40, y: Int, width: Int = 80, height: Int = 32,
                    looks: [String], labels: Bool = true) -> String {
        let rest = looks.dropFirst().map { #"{"name": "\#($0)", "changes": [{"part": "Back", "opacity": 0.5}]}"# }
        return """
            {"name": "\(name)", "x": \(x), "y": \(y), "labels": \(labels), "firstLook": "\(looks[0])",
             "parts": [{"name": "Back", "shape": "rectangle", "x": 0, "y": 0, "width": \(width), "height": \(height)}],
             "looks": [\(rest.joined(separator: ", "))]}
            """
    }

    static let states = ["Default", "Hover", "Pressed", "Disabled"]

    static func add(_ json: String, to document: inout PhotonzDocument) throws -> AgentMadeComponent {
        try document.agentAddComponent(try AgentComponentTests.spec(json), measure: measure).get()
    }

    static func boxes(_ made: AgentMadeComponent, in document: PhotonzDocument) -> [CGRect] {
        made.looks.compactMap { document.canvasBounds(of: $0.layer) }
    }

    static func words(in document: PhotonzDocument) -> [Layer] {
        document.layers.filter { $0.text != nil }
    }

    static func blank() -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024), layers: [])
    }

    @Test("One row: its states named once above their columns, nothing under the looks")
    func headerRow() throws {
        var document = Self.blank()
        let made = try Self.add(Self.row("Button", y: 100, looks: Self.states), to: &document)
        let looks = Self.boxes(made, in: document)
        let words = Self.words(in: document)
        #expect(Set(words.compactMap(\.text?.string)) == Set(["Button"] + Self.states))
        for (state, look) in zip(Self.states, looks) {
            let header = try #require(words.first { $0.text?.string == state })
            #expect(header.frame.maxY <= look.minY - AgentNewComponent.headerGap, "\(state) is a header above its look")
            #expect(abs(header.frame.midX - look.midX) <= 1, "\(state) is centred over its look")
        }
        let headers = words.filter { Self.states.contains($0.text?.string ?? "") }
        #expect(Set(headers.map(\.frame.minY)).count == 1, "the headers are one row")
        #expect(made.sheet?.headers == [Self.states])
        let name = try #require(words.first { $0.text?.string == "Button" })
        #expect(name.frame.minX == 40)
        #expect(abs(name.frame.midY - looks[0].midY) <= 1, "the row's name is level with its looks")
        #expect(headers.allSatisfy { $0.text?.fontSize == AgentNewComponent.labelSize })
    }

    @Test("Rows share one grid: each column's looks share a centre, the gaps between rows are equal")
    func oneGrid() throws {
        var document = Self.blank()
        let button = try Self.add(Self.row("Button", y: 100, width: 120, looks: Self.states), to: &document)
        let field = try Self.add(Self.row("Field", y: 200, width: 240, height: 40, looks: Self.states), to: &document)
        let check = try Self.add(Self.row("Checkbox", y: 300, width: 20, height: 20, looks: Self.states), to: &document)
        let rows = [button, field, check].map { Self.boxes($0, in: document) }
        for column in 0..<4 {
            let centres = rows.map { $0[column].midX }
            #expect(centres.allSatisfy { abs($0 - centres[0]) <= 1 }, "column \(column): \(centres)")
        }
        // Steps between columns are one size.
        let steps = zip(rows[0].dropFirst(), rows[0]).map { ($0.midX - $1.midX).rounded() }
        #expect(Set(steps).count == 1, "\(steps)")
        // Equal gaps down: the bottom of one row's looks to the top of the next.
        let gaps = zip(rows.dropFirst(), rows).map { next, last in
            (next.map(\.minY).min() ?? 0) - (last.map(\.maxY).max() ?? 0)
        }
        #expect(gaps.allSatisfy { $0 == AgentNewComponent.rowGap }, "\(gaps)")
        // Headers are set once for the whole table, not once per row.
        let headers = Self.words(in: document).filter { $0.text?.string == "Hover" }
        #expect(headers.count == 1)
        // The row names line up on one edge.
        let names = Self.words(in: document).filter { ["Button", "Field", "Checkbox"].contains($0.text?.string ?? "") }
        #expect(Set(names.map(\.frame.minX)).count == 1)
    }

    @Test("Rows whose originals the editor parked in the Library, leaving copies on the canvas, are still one table")
    func parkedRows() throws {
        var document = Self.blank()
        var copies: [[UUID]] = []
        for (index, name) in ["Button", "Field", "Toggle"].enumerated() {
            let made = try Self.add(Self.row(name, y: 100 + index * 60, looks: Self.states), to: &document)
            // What History does after every edit in the app.
            let moved = document.parkOriginals()
            copies.append(made.looks.map { moved[$0.layer] ?? $0.layer })
        }
        #expect(document.layers.allSatisfy { !$0.isMainComponent })
        // Every copy that is still a row is laid out again by the last call.
        let rows = copies.map { $0.compactMap { document.canvasBounds(of: $0) } }
        #expect(rows.map(\.count) == [4, 4, 4])
        let tops = rows.map { $0.map(\.minY).min() ?? 0 }
        #expect(tops[0] < tops[1] && tops[1] < tops[2], "\(tops)")
        let gaps = zip(rows.dropFirst(), rows).map { next, last in
            (next.map(\.minY).min() ?? 0) - (last.map(\.maxY).max() ?? 0)
        }
        #expect(gaps.allSatisfy { $0 == AgentNewComponent.rowGap }, "\(gaps)")
        for column in 0..<4 {
            let centres = rows.map { $0[column].midX }
            #expect(centres.allSatisfy { abs($0 - centres[0]) <= 1 }, "column \(column): \(centres)")
        }
        let strings = Self.words(in: document).compactMap(\.text?.string)
        #expect(strings.count == Set(strings).count, "\(strings.sorted())")
    }

    @Test("The table fills the canvas's width, with the same margin on both sides")
    func evenMargins() throws {
        var document = Self.blank()
        let made = try Self.add(Self.row("Button", y: 100, looks: Self.states), to: &document)
        let sheet = try #require(made.sheet)
        #expect(sheet.frame.minX == 40)
        #expect(abs(sheet.frame.maxX - 1400) < 0.001, "\(sheet.frame.maxX - 1400)")
        let looks = Self.boxes(made, in: document)
        #expect(looks.last.map { $0.maxX <= 1400 } == true)
    }

    @Test("A row whose states are not the table's starts a header row of its own; every look sits under its own state")
    func otherStates() throws {
        var document = Self.blank()
        let button = try Self.add(Self.row("Button", y: 100, looks: Self.states), to: &document)
        let toggle = try Self.add(Self.row("Toggle", y: 200, looks: ["Off", "On", "Disabled"]), to: &document)
        let badge = try Self.add(Self.row("Badge", y: 300, looks: ["Default", "Hover"]), to: &document)
        let switcher = try Self.add(Self.row("Switch", y: 400, looks: ["Off", "On"]), to: &document)
        let words = Self.words(in: document)
        let headers = words.filter { $0.name.hasSuffix(" Header") }
        func headed(_ made: AgentMadeComponent) -> [String] {
            Self.boxes(made, in: document).map { look in
                headers.filter { $0.frame.maxY <= look.minY && abs($0.frame.midX - look.midX) <= 1 }
                    .max { $0.frame.minY < $1.frame.minY }?.text?.string ?? "none"
            }
        }
        #expect(headed(button) == Self.states)
        #expect(headed(toggle) == ["Off", "On", "Disabled"])
        #expect(headed(badge) == ["Default", "Hover"])
        #expect(headed(switcher) == ["Off", "On"])
        // Rows that share their states sit together under one header row.
        let tops = [button, badge, toggle, switcher].map { Self.boxes($0, in: document).map(\.minY).min() ?? 0 }
        #expect(tops == tops.sorted(), "Button and Badge, then Toggle and Switch: \(tops)")
        #expect(headers.filter { $0.text?.string == "Off" }.count == 1)
        #expect(headers.filter { $0.text?.string == "Default" }.count == 1)
        // Both header rows are on the one grid.
        let columns = Set(headers.map { $0.frame.midX.rounded() })
        #expect(columns.count == 4, "\(columns.sorted())")
        // No state is named under a look.
        #expect(words.allSatisfy { !($0.name.hasPrefix("Toggle ") && $0.name != "Toggle Label") })
        #expect(toggle.labels.count == 1, "its name only")
    }

    @Test("Laying the table out again leaves one set of words: no header or caption twice")
    func noWordsTwice() throws {
        var document = Self.blank()
        for (index, name) in ["A", "B", "C", "D"].enumerated() {
            _ = try Self.add(Self.row(name, y: 100 + index * 100, looks: Self.states), to: &document)
        }
        let strings = Self.words(in: document).compactMap(\.text?.string)
        #expect(strings.count == Set(strings).count, "\(strings.sorted())")
        #expect(strings.count == 4 + 4)
    }

    @Test("Headers and names never touch: a column is at least as wide as its widest header")
    func roomForWords() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 1024), layers: [])
        _ = try Self.add(Self.row("Checkbox", x: 0, y: 0, width: 22, height: 22,
                                  looks: ["Unchecked", "Indeterminate"]), to: &document)
        let headers = Self.words(in: document).filter { $0.name.hasSuffix("Header") }.map(\.frame).sorted { $0.minX < $1.minX }
        #expect(headers.count == 2)
        #expect(headers[0].maxX + 8 <= headers[1].minX, "\(headers)")
    }

    @Test("Components with no labels are no part of the table and stay where they were put")
    func unlabelledStay() throws {
        var document = Self.blank()
        let loose = try Self.add(Self.row("Loose", x: 900, y: 700, looks: ["Default", "Hover"], labels: false), to: &document)
        #expect(loose.sheet == nil)
        _ = try Self.add(Self.row("Button", y: 100, looks: Self.states), to: &document)
        #expect(Self.boxes(loose, in: document).map(\.minX) == [900, 1004])
        #expect(Self.boxes(loose, in: document).map(\.minY) == [700, 700])
    }

    @Test("Words the person or the model set on the canvas are left alone")
    func otherWordsStay() throws {
        var document = Self.blank()
        var title = Layer(name: "Title", content: .text(TextContent(string: "Base Components", fontSize: 32)),
                          frame: CGRect(x: 40, y: 32, width: 300, height: 40))
        title.name = "Base Components"
        document.addLayer(title)
        _ = try Self.add(Self.row("Button", y: 100, looks: Self.states), to: &document)
        _ = try Self.add(Self.row("Field", y: 200, looks: Self.states), to: &document)
        let kept = try #require(document.layer(id: title.id))
        #expect(kept.frame.origin == CGPoint(x: 40, y: 32))
        // The table starts below the title, where the first row was asked for.
        let top = Self.words(in: document).filter { $0.name.hasSuffix("Header") }.map(\.frame.minY).min()
        #expect(top == 100)
    }

    @Test("Rows share a header when most of their states are its and they fit its columns; headers run in the order states mostly come")
    func sections() {
        let sections = PhotonzDocument.sheetSections([
            ["Default", "Hover", "Pressed", "Disabled"],
            ["Off", "On", "Disabled"],
            ["Default", "Focused", "Disabled"],
            ["default", "hover", "disabled"],
            ["Off", "On"],
            ["Selected", "Unselected"],
        ])
        #expect(sections.map(\.rows) == [[0, 3], [1, 4], [2], [5]])
        #expect(sections.map(\.headers) == [["Default", "Hover", "Pressed", "Disabled"], ["Off", "On", "Disabled"],
                                             ["Default", "Focused", "Disabled"], ["Selected", "Unselected"]])
        #expect(sections[0].cells == [[0, 1, 2, 3], [0, 1, 3]], "names match whatever their case")
        #expect(sections[1].cells == [[0, 1, 2], [0, 1]])
        // A row that adds a state still fits when the grid has room for it.
        let wide = PhotonzDocument.sheetSections([["Default", "Hover", "Pressed", "Disabled", "Focused"],
                                                  ["Default", "Focused"]])
        #expect(wide.count == 1)
        #expect(wide[0].headers == ["Default", "Hover", "Pressed", "Focused", "Disabled"])
        #expect(wide[0].cells == [[0, 1, 2, 4, 3], [0, 3]])
    }
}
