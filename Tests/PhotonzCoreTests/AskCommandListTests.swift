import Foundation
@testable import PhotonzCore
import Testing

/// Typing / in Ask's composer turns it into the command list
/// (`agent-generate-wt.html`, UX-PATTERNS D6): every menu command by name,
/// filtered as you type, and Return runs the one picked.
@Suite("Ask: / lists the commands you can run")
struct AskCommandListTests {

    private func runnable(_: AskCommandEntry) -> Bool { true }

    @Test("Only words starting with / are a command search")
    func queryNeedsASlash() {
        #expect(AskCommandList.query(in: "make it red") == nil)
        #expect(AskCommandList.query(in: "") == nil)
        #expect(AskCommandList.query(in: "/") == "")
        #expect(AskCommandList.query(in: "  /Flip ") == "flip")
    }

    @Test("Every entry is a call the command's own checker accepts, or one that asks the person")
    func everyEntryCanBeCarriedOut() {
        for entry in AskCommandList.all {
            guard let command = AppCommandTable.command(entry.call.id) else {
                Issue.record("\(entry.id) names no command")
                continue
            }
            if command.title.hasSuffix("\u{2026}") { continue }
            let missing = command.options.filter { $0.required && entry.call.options[$0.name] == nil }
            #expect(missing.isEmpty, "\(entry.id) would do nothing: it leaves out \(missing.map(\.name))")
            let checked = AppCommandTable.call(command.name, arguments: .object(entry.call.options))
            if case .failure(let problem) = checked { Issue.record("\(entry.id): \(problem)") }
        }
    }

    @Test("A command with no arguments is one row, in its menu's words")
    func plainCommandIsOneRow() throws {
        let rows = AskCommandList.all.filter { $0.call.id == .bringToFront }
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.title == AppCommandTable.command(.bringToFront)?.title)
        #expect(row.apiName == "bring_to_front")
    }

    @Test("A command that needs a choice is a row for each choice")
    func choicesAreRows() {
        let align = AskCommandList.all.filter { $0.call.id == .align }
        #expect(align.count == LayerAlignment.allCases.count)
        #expect(align.contains { $0.title == "Align Left" })
        let speeds = AskCommandList.all.filter { $0.call.id == .setSpeed }
        #expect(speeds.count == AppCommandTable.speeds.count)
        #expect(speeds.contains { $0.title == "Speed 50%" && $0.call.integer("percent") == 50 })
    }

    @Test("A command a person answers in a sheet keeps its one row, with nothing filled in")
    func sheetCommandsAskThePerson() throws {
        let rows = AskCommandList.all.filter { $0.call.id == .canvasSize }
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.call.options.isEmpty)
    }

    @Test("Ids are unique, so a row can be found again")
    func idsAreUnique() {
        let ids = AskCommandList.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("Nearly every command in the table is reachable")
    func coversTheTable() {
        let listed = Set(AskCommandList.all.map(\.call.id))
        let left = AppCommandTable.all.map(\.id).filter { !listed.contains($0) }
        // What is left needs a value no row can hold: a length, a word, a name
        // from this document.
        #expect(left.count <= 8, "left out: \(left)")
    }

    @Test("Filtering ignores case and matches the menu's words or the API name")
    func filtering() {
        let byTitle = AskCommandList.matching("FLIP", canRun: runnable)
        #expect(byTitle.rows.contains { $0.call.id == .flipHorizontal })
        let byName = AskCommandList.matching("bring_to", canRun: runnable)
        #expect(byName.rows.first?.call.id == .bringToFront)
        #expect(AskCommandList.matching("zzzz", canRun: runnable).rows.isEmpty)
    }

    @Test("A title that starts with the words comes before one that only contains them")
    func startsWithComesFirst() throws {
        let rows = AskCommandList.matching("add", canRun: runnable).rows
        let first = try #require(rows.first)
        #expect(first.title.lowercased().hasPrefix("add"))
    }

    @Test("What can run now comes first, and only that can be highlighted")
    func runnableFirst() {
        let list = AskCommandList.matching("flip") { $0.call.id == .flipVertical }
        #expect(list.rows.first?.call.id == .flipVertical)
        #expect(list.runnableCount == 1)
        #expect(list.rows.count > 1)
        #expect(list.picked?.call.id == .flipVertical)
        let moved = list.moved(by: 1)
        #expect(moved.picked?.call.id == .flipVertical)
    }

    @Test("With nothing that can run, nothing is picked and Return has nothing to do")
    func nothingRunnableNothingPicked() {
        let list = AskCommandList.matching("flip") { _ in false }
        #expect(!list.rows.isEmpty)
        #expect(list.picked == nil)
        #expect(list.moved(by: 1).picked == nil)
    }

    @Test("Arrows move the pick and stop at the ends")
    func arrowsStopAtTheEnds() {
        var list = AskCommandList.matching("", canRun: runnable)
        #expect(list.highlight == 0)
        list = list.moved(by: -1)
        #expect(list.highlight == 0)
        list = list.moved(by: 2)
        #expect(list.highlight == 2)
        list = list.moved(by: 100_000)
        #expect(list.highlight == list.runnableCount - 1)
    }
}
