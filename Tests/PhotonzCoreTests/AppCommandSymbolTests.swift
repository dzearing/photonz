@testable import PhotonzCore
import Testing

/// Ask's `/` list gives every row its own icon, as the mock's `ASK_CMDS` does
/// (`agent-generate-wt.html`), so the list reads at a glance. Until 2026-11-10
/// every row in an area wore that area's one icon: forty timeline rows, one
/// film strip.
@Suite("Ask: each / row wears its own icon")
struct AppCommandSymbolTests {

    @Test("Two commands share an icon only when they share their words")
    func iconsAreTheCommandsOwn() {
        var byIcon: [String: [AppCommand]] = [:]
        for command in AppCommandTable.all { byIcon[command.id.symbol, default: []].append(command) }
        for (icon, commands) in byIcon where Set(commands.map(\.title)).count > 1 {
            Issue.record("\(icon) is worn by \(commands.map(\.title).joined(separator: ", "))")
        }
    }

    @Test("No area's rows all wear one icon")
    func noAreaSharesOneIcon() {
        for area in AppCommand.Area.allCases {
            let rows = AskCommandList.all.filter { $0.area == area }
            guard rows.count > 1 else { continue }
            let icons = Set(rows.map(\.symbol))
            #expect(icons.count > rows.count / 2,
                    "\(area): \(rows.count) rows wear only \(icons.count) icons")
        }
    }

    @Test("Every icon is a symbol name, not a blank")
    func everyIconIsAName() {
        for entry in AskCommandList.all {
            let icon = entry.symbol
            #expect(!icon.isEmpty && icon == icon.lowercased() && !icon.contains(" "),
                    "\(entry.title) wears \(icon)")
        }
    }

    @Test("Each Align row shows the edge it lines up,")
    func choiceRowsShowTheirChoice() {
        let align = AskCommandList.all.filter { $0.call.id == .align }
        #expect(align.count == LayerAlignment.allCases.count)
        #expect(Set(align.map(\.symbol)).count == align.count)
        let left = align.first { $0.call.options["edge"]?.stringValue == LayerAlignment.left.rawValue }
        #expect(left?.symbol == "align.horizontal.left")

        let space = AskCommandList.all.filter { $0.call.id == .spaceEvenly }
        #expect(space.count == LayerDistribution.allCases.count)
        #expect(Set(space.map(\.symbol)).count == space.count)
    }

    @Test("A row with nothing to choose wears its command's icon")
    func plainRowWearsCommandIcon() throws {
        let row = try #require(AskCommandList.all.first { $0.call.id == .splitAtPlayhead })
        #expect(row.symbol == AppCommandID.splitAtPlayhead.symbol)
    }
}
