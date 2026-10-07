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
        guard case .writeVideo(_, _, _, _, _, _, _, _, _, _, _, _, _, let pace, _, _) = script.steps[0],
              case .writeVideo(_, _, _, _, _, _, _, _, _, _, _, _, _, let unpaced, _, _) = script.steps[1]
        else { Issue.record("writeVideo"); return }
        #expect(pace == 0.5)
        #expect(unpaced == nil)
    }

    @Test func aWriteCanClaimItCopiedThePieces() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "writeVideo", "name": "a", "piecesCopied": true },
                     { "do": "writeVideo", "name": "b", "piecesCopied": false },
                     { "do": "writeVideo", "name": "c" } ] }
        """.utf8))
        let claims: [Bool?] = script.steps.compactMap {
            guard case .writeVideo(_, _, _, _, _, _, _, _, _, _, _, _, _, _, let claim, _) = $0 else { return nil }
            return .some(claim)
        }
        #expect(claims == [true, false, nil])
    }

    @Test func aWriteCanBeDrawnWhereItCouldBeCopied() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "writeVideo", "name": "a", "drawn": true },
                     { "do": "writeVideo", "name": "b" } ] }
        """.utf8))
        let drawn: [Bool] = script.steps.compactMap {
            guard case .writeVideo(_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, let drawn) = $0 else { return nil }
            return drawn
        }
        #expect(drawn == [true, false])
    }

    @Test func theShareIsTheWriteOverTheRunningTime() {
        #expect(VideoWritePace.share(writtenMS: 80_000, runsSeconds: 320) == 0.25)
        #expect(VideoWritePace.share(writtenMS: 80_000, runsSeconds: 0) == nil)
        #expect(VideoWritePace.isWithin(0.5, writtenMS: 150_000, runsSeconds: 320))
        #expect(!VideoWritePace.isWithin(0.5, writtenMS: 170_000, runsSeconds: 320))
    }
}
