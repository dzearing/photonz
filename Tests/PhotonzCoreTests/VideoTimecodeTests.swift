import Foundation
import PhotonzCore
import Testing

/// Time on a video, read in frames where an editor expects frames: Premiere
/// shows `00:00:04:12` where Photonz said `0:04`, and a transition of twelve
/// frames where Photonz said `0.4s`. Seconds stay the default; View >
/// Timecode reads every readout in hours, minutes, seconds and frames, at the
/// timeline's thirty frames a second.
@Suite("Video time reads in frames")
struct VideoTimecodeTests {

    // MARK: A moment

    @Test("A moment reads as the frame it is in: 4.4 seconds is 00:00:04:12")
    func momentReadsItsFrame() {
        #expect(VideoTimecode.moment(4400) == "00:00:04:12")
        #expect(VideoTimecode.moment(0) == "00:00:00:00")
        #expect(VideoTimecode.moment(-50) == "00:00:00:00")
        // Inside a frame is still that frame, never the next.
        #expect(VideoTimecode.moment(4432) == "00:00:04:12")
        #expect(VideoTimecode.moment(4434) == "00:00:04:13")
        #expect(VideoTimecode.moment(3_723_000) == "01:02:03:00")
    }

    @Test("Every whole second is frame 00 of that second, never 29 of the one before")
    func wholeSecondsAreFrameZero() {
        for second in 0..<120 {
            #expect(VideoTimecode.moment(second * 1000).hasSuffix(":00"))
        }
    }

    // MARK: A length

    @Test("A length reads in whole frames: 0.4 seconds is twelve frames")
    func lengthReadsWholeFrames() {
        #expect(VideoTimecode.length(400) == "00:00:00:12")
        #expect(VideoTimecode.length(800) == "00:00:00:24")
        #expect(VideoTimecode.length(1200) == "00:00:01:06")
        #expect(VideoTimecode.frames(inLengthMS: 33) == 1)
        #expect(VideoTimecode.frames(inLengthMS: 0) == 0)
    }

    @Test("A length of whole frames comes back the same number of frames")
    func wholeFramesRoundTrip() {
        for frames in 0...400 {
            #expect(VideoTimecode.frames(inLengthMS: VideoTimecode.lengthMS(ofFrames: frames)) == frames)
        }
        #expect(VideoTimecode.lengthMS(ofFrames: 12) == 400)
    }

    @Test("A length snaps to the nearest whole frame")
    func lengthSnapsToWholeFrames() {
        #expect(VideoTimecode.wholeFrames(410) == 400)
        #expect(VideoTimecode.wholeFrames(420) == 434)
        #expect(VideoTimecode.wholeFrames(400) == 400)
    }

    // MARK: Which way a readout reads

    @Test("Seconds, the default, reads a moment as the transport always has, and timecode reads frames")
    func displayPicksTheReading() {
        #expect(VideoTimeDisplay.defaultValue == .seconds)
        #expect(VideoTimeDisplay.seconds.moment(4400) == "0:04")
        #expect(VideoTimeDisplay.timecode.moment(4400) == "00:00:04:12")
        #expect(VideoTimeDisplay.seconds.length(400) == "0.4s")
        #expect(VideoTimeDisplay.timecode.length(400) == "00:00:00:12")
    }

    // MARK: Typed lengths

    @Test("Twelve frames typed as 12f, as 00:00:00:12 or, with timecode on, as a bare 12 are the same length")
    func typedFramesAgree() {
        let ms = VideoTimecode.lengthMS(ofFrames: 12)
        #expect(VideoTimecode.parseLength("00:00:00:12") == ms)
        #expect(VideoTimecode.parseLength("12", bareNumberIsFrames: true) == ms)
        #expect(VideoTimecode.parseLength("12f") == nil, "frames with a unit are FreezeLength's, not timecode's")
        #expect(VideoTimecode.parseLength("00:00:04:12") == VideoTimecode.lengthMS(ofFrames: 132))
        // Right-aligned like Premiere's field: seconds and frames, or minutes,
        // seconds and frames.
        #expect(VideoTimecode.parseLength("4:12", bareNumberIsFrames: true) == VideoTimecode.lengthMS(ofFrames: 132))
        #expect(VideoTimecode.parseLength("1:00:00", bareNumberIsFrames: true) == 60_000)
        // A frame past the last of a second is not a frame.
        #expect(VideoTimecode.parseLength("00:00:00:30") == nil)
        #expect(VideoTimecode.parseLength("") == nil)
        #expect(VideoTimecode.parseLength("12") == nil, "a bare number is seconds unless timecode is on")
    }

    @Test("A freeze typed in frames or in timecode gives the same length, with timecode on or off")
    func freezeLengthReadsTimecode() {
        let twelve = VideoTimecode.lengthMS(ofFrames: 12)
        #expect(FreezeLength.parse("00:00:00:12") == twelve)
        #expect(FreezeLength.parse("00:00:00:12", display: .timecode) == twelve)
        #expect(FreezeLength.parse("12", display: .timecode) == twelve)
        #expect(FreezeLength.parse("12f", display: .timecode) == twelve)
        #expect(FreezeLength.parse("12f") == twelve)
        // Seconds stays what it was: a bare number is seconds, a colon is
        // minutes and seconds.
        #expect(FreezeLength.parse("12") == 12_000)
        #expect(FreezeLength.parse("1:30") == 90_000)
        #expect(FreezeLength.text(2000, display: .timecode) == "00:00:02:00")
    }

    // MARK: The ruler

    @Test("With timecode on the ruler reads timecode, on whole frames, at every zoom")
    func rulerReadsTimecode() {
        let fit = MotionStripRuler(documentMS: 15_000)
        let fitTicks = fit.ticks(display: .timecode)
        #expect(fitTicks.map(\.label).first == "00:00:00:00")
        #expect(fitTicks.allSatisfy { $0.label.count == 11 })
        let closest = MotionStripRuler(documentMS: 8000, zoom: TimelineZoom(scale: 64, startMS: 3900))
        let near = closest.ticks(display: .timecode)
        #expect(near.count >= 3)
        for tick in near {
            // Each label is the frame its line stands on.
            #expect(tick.label == VideoTimecode.moment(Int(tick.ms)))
            #expect(Double(VideoTimecode.lengthMS(ofFrames: MovieRef.gridFrame(atMS: Int(tick.ms)))) == tick.ms)
        }
        // Seconds is the ruler as it was.
        #expect(fit.ticks(display: .seconds) == fit.secondTicks)
        #expect(closest.tickMS(across: 3900...4100, display: .timecode)
                == closest.ticks(display: .timecode).map(\.ms).filter { (3900...4100).contains($0) })
    }

    @Test("The timeline bar's window reads in timecode with the rest")
    func zoomReadingReadsTimecode() {
        let zoom = TimelineZoom(scale: 8, startMS: 3000)
        #expect(zoom.reading(documentMS: 8000, display: .timecode) == "00:00:03:00 to 00:00:04:00")
        #expect(zoom.reading(documentMS: 8000) == "0:03 to 0:04")
    }

    // MARK: A transition's length

    @Test("A transition's bubble and its Length row say the same frames")
    func transitionReadsFrames() {
        #expect(ClipTransitionCopy.dragReadout(800, stop: nil, fine: false, display: .timecode) == "00:00:00:24")
        #expect(ClipTransitionCopy.dragReadout(800, stop: .longest, fine: true, display: .timecode) == "00:00:00:24 max")
        #expect(ClipTransitionCopy.length(800, display: .timecode) == "00:00:00:24")
        #expect(ClipTransitionCopy.length(800, display: .seconds) == "0.8s")
        #expect(ClipTransitionCopy.dragReadout(800, stop: nil, fine: false) == "0.8s")
        #expect(ClipTransitionCopy.short(800, display: .timecode) == "24f")
        #expect(ClipTransitionCopy.short(800, display: .seconds) == "0.8s")
    }

    @Test("With timecode on, a dragged transition lands on whole frames")
    func dragLandsOnWholeFrames() {
        let hand = ClipTransitionEdgeDrag(startedAtMS: 400, grabbedLeadingEdge: false,
                                          alignment: .after, longestMS: 3000)
        let free = hand.landing(travelledMS: 17)
        #expect(free.lengthMS == 417)
        let framed = hand.landing(travelledMS: 17, wholeFrames: true)
        #expect(framed.lengthMS == 434)
        #expect(VideoTimecode.wholeFrames(framed.lengthMS) == framed.lengthMS)
        // A stop still holds it where the stop is.
        #expect(hand.landing(travelledMS: 5000, wholeFrames: true).stop == .longest)
    }
}
