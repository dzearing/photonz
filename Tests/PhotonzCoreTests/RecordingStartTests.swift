import CoreGraphics
import Foundation
import PhotonzCore
import Testing

@Suite("A recording begins the moment Start is pressed")
struct RecordingStartBudgetTests {
    @Test func theBudgetIsAHundredMilliseconds() {
        #expect(RecordingStartBudget.returnToFirstFrameMS == 100)
    }

    @Test func theMedianDecides() {
        #expect(RecordingStartBudget.median([30, 10, 20]) == 20)
        #expect(RecordingStartBudget.median([40, 10, 30, 20]) == 25)
        #expect(RecordingStartBudget.median([]) == nil)
    }

    @Test func aMedianInsideTheBudgetPasses() {
        #expect(RecordingStartBudget.isWithin(readingsMS: [18, 22, 25, 140]))
        #expect(RecordingStartBudget.isWithin(readingsMS: [100]))
    }

    @Test func aMedianOverTheBudgetFails() {
        #expect(!RecordingStartBudget.isWithin(readingsMS: [263, 278, 303]))
        #expect(!RecordingStartBudget.isWithin(readingsMS: [101]))
    }

    @Test func noReadingsOrABrokenReadingFails() {
        #expect(!RecordingStartBudget.isWithin(readingsMS: []))
        #expect(!RecordingStartBudget.isWithin(readingsMS: [20, .nan, 30]))
        #expect(!RecordingStartBudget.isWithin(readingsMS: [20, -1, 30]))
    }
}

@Suite("A stream warmed while the card is up is used when it fits")
struct RecordingWarmStartTests {
    private let mic = RecordingConfig(audio: [.microphone], microphoneDeviceID: "mic-a")
    private let region = CGRect(x: 10, y: 20, width: 300, height: 200)

    @Test func nothingWarmMeansAColdStart() {
        #expect(RecordingWarmStart.plan(warm: nil, chosen: RecordingConfig(), sameDisplay: true) == .cold)
    }

    @Test func theSameChoicesBeginOnTheWarmStream() {
        #expect(RecordingWarmStart.plan(warm: RecordingConfig(), chosen: RecordingConfig(), sameDisplay: true) == .begin)
        #expect(RecordingWarmStart.plan(warm: mic, chosen: mic, sameDisplay: true) == .begin)
    }

    @Test func theFormatDoesNotMatterToTheStream() {
        let gif = RecordingConfig(format: .gif)
        #expect(RecordingWarmStart.plan(warm: RecordingConfig(), chosen: gif, sameDisplay: true) == .begin)
    }

    @Test func aRegionChosenAfterwardsReframesTheWarmStream() {
        let chosen = RecordingConfig(source: .region(region))
        #expect(RecordingWarmStart.plan(warm: RecordingConfig(), chosen: chosen, sameDisplay: true) == .reframe)
        let warmRegion = RecordingConfig(source: .region(.zero))
        #expect(RecordingWarmStart.plan(warm: warmRegion, chosen: chosen, sameDisplay: true) == .reframe)
        #expect(RecordingWarmStart.plan(warm: chosen, chosen: chosen, sameDisplay: true) == .begin)
    }

    @Test func differentSoundStartsCold() {
        let system = RecordingConfig(audio: [.systemAudio])
        #expect(RecordingWarmStart.plan(warm: RecordingConfig(), chosen: system, sameDisplay: true) == .cold)
        #expect(RecordingWarmStart.plan(warm: system, chosen: RecordingConfig(), sameDisplay: true) == .cold)
        #expect(RecordingWarmStart.plan(warm: RecordingConfig(), chosen: mic, sameDisplay: true) == .cold)
    }

    @Test func anotherMicrophoneStartsCold() {
        var other = mic
        other.microphoneDeviceID = "mic-b"
        #expect(RecordingWarmStart.plan(warm: mic, chosen: other, sameDisplay: true) == .cold)
    }

    @Test func aMicrophoneIdWithoutTheMicrophoneIsIgnored() {
        let stale = RecordingConfig(microphoneDeviceID: "mic-a")
        #expect(RecordingWarmStart.plan(warm: RecordingConfig(), chosen: stale, sameDisplay: true) == .begin)
    }

    @Test func anotherDisplayStartsCold() {
        #expect(RecordingWarmStart.plan(warm: RecordingConfig(), chosen: RecordingConfig(), sameDisplay: false) == .cold)
    }
}
