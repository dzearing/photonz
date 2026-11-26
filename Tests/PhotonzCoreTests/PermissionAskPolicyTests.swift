import Foundation
import Testing
@testable import PhotonzCore

/// The one rule for raising a macOS permission dialog (2026-11-26: the loop's
/// probe left a stack of Screen Recording dialogs, one per launch without the
/// grant, and the person denied a dozen in a row while each next one came up).
@Suite("Permission asks are bounded")
struct PermissionAskPolicyTests {
    let empty = PermissionAskLedger()

    @Test("a granted permission is never asked for, by anyone")
    func grantedNeverAsks() {
        for asker in [PermissionAskPolicy.Asker.person, .unmannedProbe] {
            #expect(PermissionAskPolicy.decide(.screenRecording, granted: true, asker: asker,
                                               askedThisLaunch: [], ledger: empty) == .alreadyGranted)
        }
    }

    @Test("the person's app asks once per launch")
    func personOncePerLaunch() {
        #expect(PermissionAskPolicy.decide(.screenRecording, granted: false, asker: .person,
                                           askedThisLaunch: [], ledger: empty) == .ask)
        #expect(PermissionAskPolicy.decide(.screenRecording, granted: false, asker: .person,
                                           askedThisLaunch: [.screenRecording], ledger: empty) == .askedThisLaunch)
        // A ledger is the probe's memory; the person's next launch may ask again.
        let ledger = PermissionAskPolicy.recording(.screenRecording, at: "2026-11-26T12:00:00Z", in: empty)
        #expect(PermissionAskPolicy.decide(.screenRecording, granted: false, asker: .person,
                                           askedThisLaunch: [], ledger: ledger) == .ask)
    }

    @Test("the unmanned probe asks at most once, ever, whatever the answer was")
    func probeOnceEver() {
        #expect(PermissionAskPolicy.decide(.screenRecording, granted: false, asker: .unmannedProbe,
                                           askedThisLaunch: [], ledger: empty) == .ask)
        let ledger = PermissionAskPolicy.recording(.screenRecording, at: "2026-11-26T12:00:00Z", in: empty)
        #expect(PermissionAskPolicy.decide(.screenRecording, granted: false, asker: .unmannedProbe,
                                           askedThisLaunch: [], ledger: ledger)
                == .askedBefore(at: "2026-11-26T12:00:00Z"))
        // One service's ask says nothing about another's.
        #expect(PermissionAskPolicy.decide(.microphone, granted: false, asker: .unmannedProbe,
                                           askedThisLaunch: [], ledger: ledger) == .ask)
    }

    @Test("ten launches without the grant make exactly one ask")
    func tenLaunchesOneAsk() {
        var ledger = empty
        var asks = 0
        for launch in 0..<10 {
            let answer = PermissionAskPolicy.decide(.screenRecording, granted: false, asker: .unmannedProbe,
                                                    askedThisLaunch: [], ledger: ledger)
            if answer == .ask {
                asks += 1
                ledger = PermissionAskPolicy.recording(.screenRecording, at: "launch \(launch)", in: ledger)
            }
        }
        #expect(asks == 1)
    }

    @Test("recording keeps the first time asked")
    func keepsFirstAsk() {
        let once = PermissionAskPolicy.recording(.screenRecording, at: "first", in: empty)
        let twice = PermissionAskPolicy.recording(.screenRecording, at: "second", in: once)
        #expect(twice.askedAt[PermissionService.screenRecording.rawValue] == "first")
    }

    @Test("the ledger round-trips through JSON and reads an unreadable file as empty")
    func ledgerCodable() throws {
        let ledger = PermissionAskPolicy.recording(.microphone, at: "2026-11-26T12:00:00Z", in: empty)
        let data = try JSONEncoder().encode(ledger)
        #expect(PermissionAskLedger.read(data) == ledger)
        #expect(PermissionAskLedger.read(Data("not json".utf8)) == PermissionAskLedger())
        #expect(PermissionAskLedger.read(nil) == PermissionAskLedger())
    }
}
