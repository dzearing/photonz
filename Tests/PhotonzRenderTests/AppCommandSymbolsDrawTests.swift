import AppKit
import PhotonzCore
import Testing

/// Ask's `/` list draws each row's icon by its SF Symbol name
/// (`AppCommandSymbols.swift`). A name the system does not know draws
/// nothing at all, so every name is checked against the system it runs on
/// (CI runs the oldest macOS the app supports).
@Suite("Ask: every / row's icon is a symbol the Mac can draw")
struct AppCommandSymbolsDrawTests {

    @Test("Every icon the / list wears names a real SF Symbol")
    func everyIconDraws() {
        let icons = Set(AskCommandList.all.map(\.symbol) + AppCommandID.allCases.map(\.symbol))
        let missing = icons.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) == nil }
        #expect(missing.isEmpty, "No such symbol: \(missing.sorted().joined(separator: ", "))")
    }
}
