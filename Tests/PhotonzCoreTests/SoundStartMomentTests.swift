import Foundation
@testable import PhotonzCore
import Testing

/// **The sound starts where the picture already is** (task
/// `find-out-whether-the-sound-plays-a-fifth-of-a-se`).
///
/// The playhead starts moving at the press; the sound engine is heard some
/// time later (starting, a safety lead, the output's own latency). Opening
/// the sound at the press's moment left it about 180 ms behind the picture
/// all the way through. It opens at the moment the playhead will have
/// reached when it is first heard.
@Suite("Where the sound opens when play is pressed")
struct SoundStartMomentTests {

    @Test("Heard 180 ms after the press at normal speed, it opens 180 ms on")
    func normalSpeed() {
        let ms = SoundStartMoment.documentMS(playheadMS: 10_000, playheadAtSeconds: 100.0,
                                             startsAtSeconds: 100.1, outputLatencySeconds: 0.08, rate: 1)
        #expect(ms == 10_180)
    }

    @Test("At double speed the playhead covers twice the document meanwhile")
    func doubleSpeed() {
        let ms = SoundStartMoment.documentMS(playheadMS: 10_000, playheadAtSeconds: 50.0,
                                             startsAtSeconds: 50.1, outputLatencySeconds: 0, rate: 2)
        #expect(ms == 10_200)
    }

    @Test("A playhead read after the clock started (a sound restarted mid-play) is carried on from its own start")
    func midPlay() {
        // The clock started at 10 s on the document, 4 s of wall time ago.
        let ms = SoundStartMoment.documentMS(playheadMS: 10_000, playheadAtSeconds: 96.0,
                                             startsAtSeconds: 100.05, outputLatencySeconds: 0.01, rate: 1)
        #expect(ms == 14_060)
    }

    @Test("Allowing for the picture reaching the screen after its moment, the sound opens that much earlier in the document")
    func pictureLag() {
        let ms = SoundStartMoment.documentMS(playheadMS: 10_000, playheadAtSeconds: 100.0,
                                             startsAtSeconds: 100.1, outputLatencySeconds: 0.08, rate: 1,
                                             pictureLagMS: 17)
        #expect(ms == 10_163)
        // At double speed the lag is wall time, so twice the document.
        let fast = SoundStartMoment.documentMS(playheadMS: 10_000, playheadAtSeconds: 50.0,
                                               startsAtSeconds: 50.1, outputLatencySeconds: 0, rate: 2,
                                               pictureLagMS: 17)
        #expect(fast == 10_166)
        #expect(SoundStartMoment.pictureLagMS == Double(MovieRef.frameStepMS) / 2)
    }

    @Test("Never before the playhead's own moment, whatever the clocks say")
    func neverBefore() {
        let ms = SoundStartMoment.documentMS(playheadMS: 10_000, playheadAtSeconds: 100.0,
                                             startsAtSeconds: 99.0, outputLatencySeconds: 0, rate: 1)
        #expect(ms == 10_000)
    }
}
