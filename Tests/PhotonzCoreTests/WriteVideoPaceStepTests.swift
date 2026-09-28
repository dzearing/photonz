import Foundation
@testable import PhotonzCore
import Testing

/// A walk can say how long writing a video may take, as a share of how long
/// the video runs, so a write that slows back down to longer than the film
/// fails the walk the day it happens.
@Suite("A walk can hold a video write to a pace")
struct WriteVideoPaceStepTests {

    @Test func aWriteCanBeHeldToAShareOfItsLength() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "writeVideo", "name": "a", "size": "p1080", "paceShare": 0.5 },
                     { "do": "writeVideo", "name": "b" } ] }
        """.utf8))
        guard case .writeVideo(_, _, _, _, _, _, _, _, _, _, _, _, _, let pace) = script.steps[0],
              case .writeVideo(_, _, _, _, _, _, _, _, _, _, _, _, _, let unpaced) = script.steps[1]
        else { Issue.record("writeVideo"); return }
        #expect(pace == 0.5)
        #expect(unpaced == nil)
    }

    @Test func theShareIsTheWriteOverTheRunningTime() {
        #expect(VideoWritePace.share(writtenMS: 80_000, runsSeconds: 320) == 0.25)
        #expect(VideoWritePace.share(writtenMS: 80_000, runsSeconds: 0) == nil)
        #expect(VideoWritePace.isWithin(0.5, writtenMS: 150_000, runsSeconds: 320))
        #expect(!VideoWritePace.isWithin(0.5, writtenMS: 170_000, runsSeconds: 320))
    }
}
