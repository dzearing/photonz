import CoreGraphics
import Foundation
@testable import PhotonzRender
import Testing

/// Text reads asked for many at once on Swift's shared pool all come back.
///
/// The recogniser hands part of each read to a thread of its own, at the
/// priority of whoever asked. Asked from the shared pool, that is the priority
/// every pool thread runs at, and with every pool thread already waiting inside
/// a read there is no thread left to give it: sixteen reads at once on a
/// sixteen core Mac sat at 0% CPU for good (2026-10-12, measured with no other
/// work running). Run words reads every row of a screenshot that way, and the
/// whole test run hung in it every time from 2026-10-10.
///
/// If this regresses the test does not fail, it HANGS, taking every pool
/// thread with it. `Scripts/test.sh` notices a run that has gone quiet and
/// idle, names the test it is parked in and stops.
@Suite("Text reads on a full pool")
struct TextReadsOnAFullPoolTests {

    private static func capture(_ name: String) throws -> CGImage {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "png"))
        return try #require(ImageCodec.decode(try Data(contentsOf: url)))
    }

    @Test func twiceAsManyReadsAsThereAreCoresAllComeBack() async throws {
        let image = try Self.capture("settings-pane-2x")
        let alone = TextReader.words(in: image)
        let count = 2 * ProcessInfo.processInfo.activeProcessorCount
        let answers = await withTaskGroup(of: String?.self) { group in
            for _ in 0..<count { group.addTask { TextReader.words(in: image) } }
            var answers: [String?] = []
            for await answer in group { answers.append(answer) }
            return answers
        }
        #expect(answers.count == count)
        // Same picture, same words, however many were asked for at once.
        #expect(answers.allSatisfy { $0 == alone }, "\(Set(answers.map { $0 ?? "nil" }))")
    }
}
