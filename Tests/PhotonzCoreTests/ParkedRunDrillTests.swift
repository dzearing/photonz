import Dispatch
import Foundation
import Testing

/// A drill for `Scripts/test.sh`'s watch for a parked run: a test that waits
/// for something that never comes, at 0% CPU, the shape the whole run took
/// from 2026-10-10. Off unless asked for, and only ever asked for by name:
///
/// ```
/// PHOTONZ_TEST_PARK_DRILL=1 PHOTONZ_TEST_QUIET_LIMIT=30 Scripts/test.sh --filter ParkedRunDrill
/// ```
///
/// The run must stop by itself, naming `aTestThatWaitsForNothing`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_TEST_PARK_DRILL"] == "1"))
struct ParkedRunDrillTests {

    @Test func aTestThatWaitsForNothing() {
        DispatchSemaphore(value: 0).wait()
    }
}
