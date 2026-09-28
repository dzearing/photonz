import AVFoundation
import CoreGraphics
import Foundation
@testable import PhotonzMedia
import Testing

/// **Reading a recording front to back hands over the frame each moment asks
/// for.**
///
/// A video export asks for every frame of a recording in order, and seeking to
/// each one on its own cost more than the frame is on screen for. The stream
/// reads the file once instead. These check it by the frame number painted into
/// every frame of the test clip (`TestClip`), so a stream that hands over the
/// frame next door fails rather than passing on "a picture came back".
@Suite("A recording read in one pass hands over the right frames", .serialized)
struct MovieFrameStreamTests {

    /// The source frame nearest a moment, which is what seeking with half a
    /// frame of slop either way lands on.
    static func nearestFrame(toMS ms: Int) -> Int {
        Int((Double(ms) * Double(TestClip.fps) / 1000).rounded())
    }

    @Test("Every moment of the grid, in order, gets the frame nearest it")
    func inOrder() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let url = dir.appendingPathComponent("two-seconds.mp4")
        try await TestClip.write(to: url, seconds: 2)

        let stream = try #require(await MovieFrameStream(url: url))
        for step in 0..<58 {
            let ms = step * 33
            let frame = try #require(stream.frame(atMS: ms), "no frame at \(ms)ms")
            let code = try #require(TestClip.frameCode(of: frame))
            #expect(abs(code.index - Self.nearestFrame(toMS: ms)) <= 0,
                    "\(ms)ms showed frame \(code.index), wanted \(Self.nearestFrame(toMS: ms))")
        }
    }

    @Test("The same moment twice is the same frame, not the one after it")
    func sameMomentTwice() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let url = dir.appendingPathComponent("one-second.mp4")
        try await TestClip.write(to: url, seconds: 1)

        let stream = try #require(await MovieFrameStream(url: url))
        let first = try #require(stream.frame(atMS: 330).flatMap(TestClip.frameCode(of:)))
        let again = try #require(stream.frame(atMS: 330).flatMap(TestClip.frameCode(of:)))
        #expect(first.index == 10)
        #expect(again.index == 10)
    }

    @Test("Going back, or jumping far ahead, still lands on the right frame")
    func jumps() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let url = dir.appendingPathComponent("six-seconds.mp4")
        try await TestClip.write(to: url, seconds: 6)

        let stream = try #require(await MovieFrameStream(url: url))
        // Pieces carried into another order ask for a later stretch first,
        // then an earlier one, then far ahead again.
        for ms in [3000, 3033, 3066, 990, 1023, 5280, 66, 5313] {
            let frame = try #require(stream.frame(atMS: ms), "no frame at \(ms)ms")
            let code = try #require(TestClip.frameCode(of: frame))
            #expect(code.index == Self.nearestFrame(toMS: ms),
                    "\(ms)ms showed frame \(code.index), wanted \(Self.nearestFrame(toMS: ms))")
        }
    }

    @Test("Past the end of the recording is its last frame")
    func pastTheEnd() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let url = dir.appendingPathComponent("one-second.mp4")
        try await TestClip.write(to: url, seconds: 1)

        let stream = try #require(await MovieFrameStream(url: url))
        let code = try #require(stream.frame(atMS: 1_400).flatMap(TestClip.frameCode(of:)))
        #expect(code.index == 29)
    }

    @Test("The frame comes out at the recording's own size")
    func fullSize() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let url = dir.appendingPathComponent("sized.mp4")
        try await TestClip.write(to: url, seconds: 1, size: CGSize(width: 320, height: 200))

        let stream = try #require(await MovieFrameStream(url: url))
        let frame = try #require(stream.frame(atMS: 0))
        #expect(frame.width == 320)
        #expect(frame.height == 200)
    }

    @Test("A file that is not a recording gives no stream")
    func notARecording() async throws {
        let dir = TestClip.makeScratchDirectory()
        defer { TestClip.cleanUp(dir) }
        let url = dir.appendingPathComponent("nothing.mp4")
        try Data("not a movie".utf8).write(to: url)
        #expect(await MovieFrameStream(url: url) == nil)
    }
}
