import Foundation
import Testing
@testable import PhotonzCore

/// A fade that plays as a jump has to be MEASURED, not looked at: a dip of a
/// fifth of a second each way is six frames, and a picture of any one of them
/// looks like a fade. `measureFade` with `smooth` reads the brightness at a
/// run of evenly spaced moments and fails where two neighbours are further
/// apart than a third of everything the run covers (`FadeRamp`).
@Suite("A fade measured as a ramp, not a jump")
struct FadeRampTests {

    @Test("A steady ramp down and back up passes")
    func steadyRamp() {
        let down = (0...9).map { (ms: 6500 + $0 * 55, value: 0.3 - Double($0) * 0.033) }
        let up = (1...9).map { (ms: 7000 + $0 * 55, value: Double($0) * 0.033) }
        #expect(FadeRamp.jumps(in: down + up).isEmpty)
    }

    @Test("A picture that holds and then drops to black is a jump, and the jump is named")
    func hardCut() {
        let readings = [(ms: 6500, value: 0.3), (ms: 6600, value: 0.3), (ms: 6700, value: 0.29),
                        (ms: 6800, value: 0.0), (ms: 6900, value: 0.0)]
        let jumps = FadeRamp.jumps(in: readings)
        #expect(jumps.count == 1)
        #expect(jumps.first?.fromMS == 6700)
        #expect(jumps.first?.toMS == 6800)
    }

    @Test("Readings out of order are put in order first, and a flat run has nothing to jump")
    func ordering() {
        #expect(FadeRamp.jumps(in: [(ms: 2, value: 0.5), (ms: 1, value: 0.5)]).isEmpty)
        let shuffled = [(ms: 300, value: 0.0), (ms: 100, value: 0.3), (ms: 200, value: 0.29)]
        #expect(FadeRamp.jumps(in: shuffled).map(\.fromMS) == [200])
    }

    @Test("A measureFade step says whether it has to be smooth, and is not unless it says so")
    func step() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "measureFade", "name": "dip", "atMS": [1, 2, 3], "smooth": true },
                     { "do": "measureFade", "name": "fade", "atMS": [1, 2] } ] }
        """.utf8))
        guard case .measureFade(let name, let atMS, let within, let smooth) = script.steps[0],
              case .measureFade(_, _, _, let plain) = script.steps[1] else {
            Issue.record("measureFade"); return
        }
        #expect(name == "dip")
        #expect(atMS == [1, 2, 3])
        #expect(within == 0.03)
        #expect(smooth)
        #expect(!plain)
    }
}
