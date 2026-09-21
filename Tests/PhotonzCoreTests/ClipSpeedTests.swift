import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What a speed MEANS, as opposed to what it does to the numbers
/// (`ClipPiecesTests` owns that): which speeds are on offer, what the sound
/// does at each of them, and what a retimed stretch does about frames.
///
/// Every sentence the panel says is made here, so the words are tested rather
/// than typed into a view where nothing can check them.
struct ClipSpeedTests {

    /// Ten seconds of recording as one piece, the way a clip opens.
    static func recording() -> ClipPieces {
        ClipPieces(pieces: [ClipPiece(sourceInMS: 0, lengthMS: 10_000)],
                   sourceLengthMS: 10_000)
    }

    // MARK: - The speeds on offer

    @Test func theStopsRunFromAQuarterToThirtyTimes() {
        #expect(ClipSpeed.stops.first == 25)
        #expect(ClipSpeed.stops.last == 3000)
        #expect(ClipSpeed.stops.contains(ClipPiece.asRecordedPercent))
        // Every one of them is a speed the model will actually take, which is
        // what stops the panel offering a stop that silently clamps to another.
        for stop in ClipSpeed.stops {
            #expect(stop >= ClipPiece.slowestPercent)
            #expect(stop <= ClipPiece.fastestPercent)
        }
        #expect(ClipSpeed.stops == ClipSpeed.stops.sorted())
    }

    /// The goal this whole feature was asked for by: a two minute wait becomes
    /// four seconds. That is thirty times, so thirty times has to be reachable
    /// or the feature does not do the thing it was asked for.
    @Test func aTwoMinuteWaitCanBecomeFourSeconds() {
        var clip = ClipPieces(pieces: [ClipPiece(sourceInMS: 0, lengthMS: 120_000)],
                              sourceLengthMS: 120_000)
        let did = clip.setSpeed(ofPiece: 0, percent: 3000)
        #expect(did)
        #expect(clip.piece(at: 0)!.speedPercent == 3000)
        #expect(clip.totalLengthMS == 4000)
        // ...and it still reads the whole two minutes.
        #expect(clip.piece(at: 0)!.sourceOutMS == 120_000)
    }

    @Test func aSpeedIsNamedTheWayPeopleSayIt() {
        #expect(ClipSpeed.title(100) == "Normal")
        #expect(ClipSpeed.title(50) == "Half Speed")
        #expect(ClipSpeed.title(25) == "Quarter Speed")
        #expect(ClipSpeed.title(200) == "2x Speed")
        #expect(ClipSpeed.title(3000) == "30x Speed")
        // A speed nobody offered but somebody reached anyway still has a name.
        #expect(ClipSpeed.title(62) == "62% Speed")
        #expect(ClipSpeed.title(250) == "2.5x Speed")
    }

    // MARK: - What happens to the sound

    @Test func insideTheBandTheSoundPlaysAndGoesWithThePicture() {
        #expect(ClipSpeed.sound(atPercent: 100) == .asRecorded)
        #expect(ClipSpeed.sound(atPercent: 150) == .pitchedUp)
        #expect(ClipSpeed.sound(atPercent: 200) == .pitchedUp)
        #expect(ClipSpeed.sound(atPercent: 75) == .pitchedDown)
        #expect(ClipSpeed.sound(atPercent: 50) == .pitchedDown)
        for percent in [50, 75, 100, 150, 200] {
            #expect(ClipSpeed.sound(atPercent: percent).plays)
        }
    }

    @Test func pastTheBandTheSoundStops() {
        #expect(ClipSpeed.sound(atPercent: 201) == .silentTooFast)
        #expect(ClipSpeed.sound(atPercent: 3000) == .silentTooFast)
        #expect(ClipSpeed.sound(atPercent: 49) == .silentTooSlow)
        #expect(ClipSpeed.sound(atPercent: 25) == .silentTooSlow)
        #expect(ClipSpeed.sound(atPercent: 3000).plays == false)
        #expect(ClipSpeed.sound(atPercent: 25).plays == false)
    }

    @Test func aPieceOutsideTheBandContributesNothingToTheMix() {
        var clip = Self.recording()
        #expect(clip.piece(at: 0)!.playsSound)
        let did = clip.setSpeed(ofPiece: 0, percent: 400)
        #expect(did)
        // The one gate the player, the exporter and the waveform all read.
        #expect(clip.piece(at: 0)!.playsSound == false)
        #expect(clip.playback[0].playsSound == false)
        let back = clip.setSpeed(ofPiece: 0, percent: 200)
        #expect(back)
        #expect(clip.piece(at: 0)!.playsSound)
    }

    @Test func aHeldFrameIsSilentForItsOwnReason() {
        let held = ClipPiece.held(atSourceMS: 4000, forMS: 2000)
        #expect(held.speedSound == .silentHeld)
        #expect(held.playsSound == false)
    }

    @Test func theSoundSentenceSaysWhatIsHappeningAndWhy() {
        // Each one is a whole sentence a person can disagree with, which is
        // the point: the decision is stated where it is being made.
        #expect(ClipSpeedSound.asRecorded.sentence.contains("as recorded"))
        #expect(ClipSpeedSound.pitchedUp.sentence.contains("higher"))
        #expect(ClipSpeedSound.pitchedDown.sentence.contains("lower"))
        #expect(ClipSpeedSound.silentTooFast.sentence.contains("Silent"))
        #expect(ClipSpeedSound.silentTooSlow.sentence.contains("Silent"))
        #expect(ClipSpeedSound.silentHeld.sentence.contains("one frame"))
        for sound in [ClipSpeedSound.asRecorded, .pitchedUp, .pitchedDown,
                      .silentTooFast, .silentTooSlow, .silentHeld] {
            #expect(sound.sentence.contains("—") == false)   // no em dashes, ever
            #expect(sound.sentence.hasSuffix("."))
        }
    }

    // MARK: - What it does about frames

    @Test func spedUpItSkipsFramesAndSaysSo() {
        let reading = ClipSpeedReading(ClipPiece(sourceInMS: 0, lengthMS: 1000, speedPercent: 400))
        #expect(reading.frames == .skipping(oneInEvery: 4))
        #expect(reading.framesSentence.contains("One frame in every 4"))
        #expect(reading.framesSentence.contains("skipped"))
    }

    @Test func slowedDownItHoldsFramesAndSaysSo() {
        let reading = ClipSpeedReading(ClipPiece(sourceInMS: 0, lengthMS: 1000, speedPercent: 25))
        #expect(reading.frames == .holding(eachFor: 4))
        #expect(reading.framesSentence.contains("held"))
        // Nothing is invented between frames, and the sentence says it, because
        // "slow motion" makes people expect smoothing that is not there.
        #expect(reading.framesSentence.contains("Nothing is made up"))
    }

    @Test func atTheSpeedItWasRecordedEveryFramePlaysOnce() {
        let reading = ClipSpeedReading(ClipPiece(sourceInMS: 0, lengthMS: 1000))
        #expect(reading.frames == .everyFrameOnce)
        #expect(reading.framesSentence.contains("Every frame"))
    }

    @Test func aHeldFrameIsOneFrame() {
        let reading = ClipSpeedReading(ClipPiece.held(atSourceMS: 2000, forMS: 3000))
        #expect(reading.frames == .oneFrame)
        #expect(reading.isHeld)
    }

    // MARK: - What the retime did to the timeline

    @Test func theReadingSaysHowMuchRecordingFitsInHowMuchTimeline() {
        var clip = Self.recording()
        let did = clip.setSpeed(ofPiece: 0, percent: 400)
        #expect(did)
        let reading = ClipSpeedReading(clip.piece(at: 0)!)
        #expect(reading.sourceLengthMS == 10_000)
        #expect(reading.lengthMS == 2500)
        #expect(reading.lengthSentence == "10s of the recording in 2.5s.")
    }

    @Test func theReadingOfAHeldFrameTalksAboutTheHoldRatherThanASpeed() {
        let reading = ClipSpeedReading(ClipPiece.held(atSourceMS: 2000, forMS: 3000))
        #expect(reading.sourceLengthMS == 0)
        #expect(reading.lengthSentence == "One frame, on screen for 3s.")
    }

    // MARK: - What plays is what exports

    /// The claim this feature stands or falls on: a retimed document is as
    /// long as the exporter thinks it is, to the millisecond, without anybody
    /// eyeballing it.
    @Test func aRetimedDocumentExportsTheLengthItPlays() {
        var clip = Self.recording()
        let fast = clip.setSpeed(ofPiece: 0, percent: 400)
        #expect(fast)
        let cut = clip.split(atMS: 1000)
        #expect(cut)
        let slow = clip.setSpeed(ofPiece: 1, percent: 50)
        #expect(slow)

        // 1s at 4x, then what is left of the recording at half speed.
        let played = clip.totalLengthMS
        #expect(played == clip.playback.reduce(0) { $0 + $1.lengthMS })

        let plan = DocumentVideoExport.plan(durationMS: played,
                                            canvasSize: CGSize(width: 640, height: 480),
                                            format: .mp4, quality: .standard)
        #expect(plan.durationMS == played)
        // ...and the last frame photographed is inside the document rather than
        // one past its end.
        #expect(plan.timeMS(at: plan.frameCount - 1) < played)
    }

    /// Everything after a retimed piece moves along with it, which is the same
    /// ripple rule cutting obeys: pieces are laid back to back and a gap cannot
    /// be written down.
    @Test func everythingAfterARetimedPieceMovesAlong() {
        var clip = Self.recording()
        let first = clip.split(atMS: 2000)
        #expect(first)
        let second = clip.split(atMS: 6000)
        #expect(second)
        #expect(clip.rangeMS(ofPiece: 2)! == (6000, 10_000))
        let fast = clip.setSpeed(ofPiece: 1, percent: 400)
        #expect(fast)
        // The middle piece was 4s and is now 1s, so the last one starts 3s
        // earlier and the whole clip is 3s shorter.
        #expect(clip.rangeMS(ofPiece: 1)! == (2000, 3000))
        #expect(clip.rangeMS(ofPiece: 2)! == (3000, 7000))
        #expect(clip.totalLengthMS == 7000)
    }
}
