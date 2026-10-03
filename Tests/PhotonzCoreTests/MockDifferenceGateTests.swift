import Foundation
import Testing

/// The queue refuses to call an app task done while an audit it wrote lists a
/// difference from the user's mock that names no card, task, dated answer or
/// written rule (2026-10-02 and 10-03: four audits in a row wrote differences
/// into `rough` with a reason and nothing else, so the mocks were undercut
/// quietly). The gate is node; this runs its drill, which builds a throwaway
/// queue, is refused, names a card and is let through.
@Suite("Done needs every difference from the mock settled")
struct MockDifferenceGateTests {

    @Test("A task whose audit lists an unsettled difference from the mock is refused done, and let through once the line names a card")
    func theQueueRefusesDoneOverAnUnsettledDifference() throws {
        let run = try FlagDefaultsReaderTests.runQueueScript("mock-diff-drill.mjs")
        let printed = String(decoding: run.out, as: UTF8.self)
        #expect(run.status == 0, "mock-diff-drill.mjs failed:\n\(printed)\(run.err)")
        #expect(printed.contains("PASS  done is refused while the audit lists a difference from the mock naming nothing"))
        #expect(printed.contains("PASS  the same task is let through once the line names an open card"))
    }
}
