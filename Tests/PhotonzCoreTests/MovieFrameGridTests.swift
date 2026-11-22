import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// **The grid frames are fetched on is thirty frames a second exactly.**
///
/// It was 33ms a step, which against a 30fps recording's 33.33ms frames put
/// every whole second a hair short of the frame that starts there: 10s was
/// grid moment 9999ms, frame 299 (2026-10-19). The real decode of a clip is
/// `WholeSecondFrameTests`; these are the arithmetic, out to an hour.
@Suite("The frame grid is thirty frames a second exactly")
struct MovieFrameGridTests {

    static let movie = MovieRef(pixelSize: CGSize(width: 64, height: 16), durationMS: 3_600_500)

    @Test("Every whole second out to an hour is the frame that starts there, at that very moment")
    func wholeSeconds() {
        for second in 0...3600 {
            let ms = second * 1000
            #expect(Self.movie.frameIndex(atSourceMS: ms) == second * 30, "\(second)s")
            #expect(Self.movie.frameSourceMS(atSourceMS: ms) == ms, "\(second)s")
        }
    }

    @Test("A moment is the frame of a 30fps recording showing at it")
    func everyMoment() {
        for ms in 0..<40_000 {
            // Frame k of a 30fps recording shows from k/30 s up to (k+1)/30 s.
            #expect(Self.movie.frameIndex(atSourceMS: ms) == ms * 30 / 1000, "\(ms)ms")
        }
    }

    @Test("A moment at or past the end of the file is its last frame, never one it does not have")
    func theEnd() {
        // Ten seconds at 30fps is frames 0 to 299; frame 300 would start
        // exactly where the file ends.
        let ten = MovieRef(pixelSize: CGSize(width: 64, height: 16), durationMS: 10_000)
        #expect(ten.frameIndex(atSourceMS: 9999) == 299)
        #expect(ten.frameIndex(atSourceMS: 10_000) == 299)
        #expect(ten.frameIndex(atSourceMS: 99_000) == 299)
        #expect(ten.frameSourceMS(atSourceMS: 10_000) == 9967)
    }

    @Test("A grid frame's moment is the first whole millisecond inside it, and comes back to the same frame")
    func roundTrip() {
        for frame in 0...108_000 {
            let ms = MovieRef.gridMS(ofFrame: frame)
            #expect(MovieRef.gridFrame(atMS: ms) == frame)
            #expect(ms * 3 >= frame * 100 && ms * 3 < frame * 100 + 3, "frame \(frame) at \(ms)ms")
            if ms > 0 { #expect(MovieRef.gridFrame(atMS: ms - 1) == frame - 1) }
        }
    }

    @Test("Stepping a frame on or back always lands on the next or the last frame")
    func stepping() {
        for ms in stride(from: 0, through: 700_000, by: 7) {
            let frame = MovieRef.gridFrame(atMS: ms)
            #expect(MovieRef.gridFrame(atMS: MovieRef.gridMS(steppedFrom: ms, byFrames: 1)) == frame + 1)
            #expect(MovieRef.gridFrame(atMS: MovieRef.gridMS(steppedFrom: ms, byFrames: 5)) == frame + 5)
            if frame > 0 {
                #expect(MovieRef.gridFrame(atMS: MovieRef.gridMS(steppedFrom: ms, byFrames: -1)) == frame - 1)
            }
        }
        #expect(MovieRef.gridMS(steppedFrom: 10_000, byFrames: 1) == 10_034)
        #expect(MovieRef.gridMS(steppedFrom: 10_000, byFrames: -1) == 9967)
        #expect(MovieRef.gridMS(steppedFrom: 0, byFrames: -1) == 0)
    }

    @Test("A key frame is filed under the grid frame it starts")
    func keyFrames() {
        let keys = MovieKeyFrames(sourceMS: [0, 1000, 9967, 10_000, 600_000])
        #expect(keys.frames == [0, 30, 299, 300, 18_000])
    }

    @Test("A movie export runs at thirty frames a second and photographs each grid frame once")
    func export() {
        #expect(DocumentVideoExport.movieFPS == 30)
        let plan = DocumentVideoExport.plan(durationMS: 20_000, canvasSize: CGSize(width: 64, height: 16),
                                            format: .mp4, quality: .high)
        #expect(plan.frameCount == 600)
        for index in 0..<plan.frameCount {
            #expect(MovieRef.gridFrame(atMS: plan.timeMS(at: index)) == index, "picture \(index)")
        }
    }
}
