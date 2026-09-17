import Foundation
import Testing
@testable import PhotonzCore

/// The rules behind the Export sheet's quality slider: what it can reach, what
/// it lands on, what it is called, and where each format's answer is kept.
@Suite("The quality of a lossy export")
struct ExportQualityTests {

    @Test func onlyTheFormatsThatThrowPixelsAwayHaveAQuality() {
        #expect(ExportQuality.applies(toFormat: "jpeg"))
        #expect(ExportQuality.applies(toFormat: "heic"))
        #expect(ExportQuality.applies(toFormat: "webp"))
        // A PNG keeps every pixel and an SVG has none: a quality means nothing
        // for either, so neither grows a control.
        #expect(!ExportQuality.applies(toFormat: "png"))
        #expect(!ExportQuality.applies(toFormat: "svg"))
    }

    /// A format nobody has taught this about gets no control rather than a
    /// control that does nothing.
    @Test func anUnknownFormatGetsNoQuality() {
        #expect(!ExportQuality.applies(toFormat: "tiff"))
        #expect(!ExportQuality.applies(toFormat: ""))
    }

    /// WebP is the one format whose top of the slider throws nothing away, so
    /// lossless is reached by dragging to 100 rather than by a second control.
    @Test func theTopOfTheSliderIsLosslessOnlyForWebP() {
        #expect(ExportQuality.isLossless(atPercent: 100, format: "webp"))
        #expect(!ExportQuality.isLossless(atPercent: 95, format: "webp"))
        #expect(!ExportQuality.isLossless(atPercent: 100, format: "jpeg"))
        #expect(!ExportQuality.isLossless(atPercent: 100, format: "heic"))
        #expect(ExportQuality.word(for: 100, format: "webp") == "Lossless")
        #expect(ExportQuality.word(for: 95, format: "webp") == "Best")
        #expect(ExportQuality.word(for: 100, format: "jpeg") == "Best")
    }

    @Test func theSliderCannotReachAQualityThatBreaksThePicture() {
        #expect(ExportQuality.lowest == 30)
        #expect(ExportQuality.highest == 100)
        #expect(ExportQuality.snapped(0) == 30)
        #expect(ExportQuality.snapped(-40) == 30)
        #expect(ExportQuality.snapped(1000) == 100)
    }

    @Test func everyAnswerLandsOnAStop() {
        #expect(ExportQuality.snapped(82) == 80)
        #expect(ExportQuality.snapped(83) == 85)
        #expect(ExportQuality.snapped(90) == 90)
        #expect(ExportQuality.stops.first == 30)
        #expect(ExportQuality.stops.last == 100)
        #expect(ExportQuality.stops.count == 15)
        for stop in ExportQuality.stops {
            #expect(ExportQuality.snapped(stop) == stop)
        }
    }

    /// The number every export went out at before there was anything to turn,
    /// so turning the feature on changes nobody's files.
    @Test func theStartingQualityIsWhatTheAppAlreadyUsed() {
        #expect(ExportQuality.standard == 90)
        #expect(ExportQuality.stops.contains(ExportQuality.standard))
        #expect(ExportQuality.fraction(90) == 0.9)
        #expect(ExportQuality.fraction(100) == 1)
        #expect(ExportQuality.fraction(30) == 0.3)
    }

    /// A percentage says how much is kept; it does not say what that looks
    /// like. The word does, in one glance, without a preview.
    @Test func everyQualityHasAPlainWordForIt() {
        #expect(ExportQuality.word(for: 100) == "Best")
        #expect(ExportQuality.word(for: 95) == "Best")
        #expect(ExportQuality.word(for: 90) == "High")
        #expect(ExportQuality.word(for: 80) == "High")
        #expect(ExportQuality.word(for: 75) == "Good")
        #expect(ExportQuality.word(for: 60) == "Good")
        #expect(ExportQuality.word(for: 55) == "Low")
        #expect(ExportQuality.word(for: 45) == "Low")
        #expect(ExportQuality.word(for: 40) == "Rough")
        #expect(ExportQuality.word(for: 30) == "Rough")
    }

    /// One remembered number per format, because eighty for a JPEG and eighty
    /// for a HEIC are not the same picture.
    @Test func eachFormatKeepsItsOwnAnswer() {
        #expect(ExportQuality.storageKey(format: "jpeg") == "export.quality.jpeg")
        #expect(ExportQuality.storageKey(format: "heic") == "export.quality.heic")
        #expect(ExportQuality.storageKey(format: "jpeg") != ExportQuality.storageKey(format: "heic"))
    }

    @Test func aFileSizeIsSaidTheWayAPersonWouldSayIt() {
        #expect(ExportQuality.fileSize(bytes: 0) == "0 bytes")
        #expect(ExportQuality.fileSize(bytes: 940) == "940 bytes")
        #expect(ExportQuality.fileSize(bytes: 1024) == "1.0 KB")
        #expect(ExportQuality.fileSize(bytes: 4300) == "4.2 KB")
        #expect(ExportQuality.fileSize(bytes: 421_888) == "412 KB")
        #expect(ExportQuality.fileSize(bytes: 1_572_864) == "1.5 MB")
        #expect(ExportQuality.fileSize(bytes: 26_214_400) == "25 MB")
    }

    /// Negative bytes are not a thing, but a number arriving from a subtraction
    /// somewhere should read as nothing rather than as nonsense.
    @Test func aSizeBelowNothingReadsAsNothing() {
        #expect(ExportQuality.fileSize(bytes: -12) == "0 bytes")
    }

    // MARK: - The line under the format

    /// The whole point of the line: what the answer is called, and what the
    /// file weighs there, in one sentence for every picture format.
    @Test func theLineSaysWhatItIsCalledAndWhatItWeighs() {
        #expect(ExportQuality.note(forFormat: "jpeg", percent: 90, bytes: 421_888, weighed: true)
                == "High · 412 KB")
        #expect(ExportQuality.note(forFormat: "webp", percent: 100, bytes: 4300, weighed: true)
                == "Lossless · 4.2 KB")
    }

    /// PNG throws nothing away, so there is no quality to name and the line
    /// says the thing that is true of it instead. Same words, same place, same
    /// size on the end: the absence of a slider reads as an answer rather than
    /// as a control that failed to arrive.
    @Test func aFormatWithNoQualityStillSaysWhatItWeighs() {
        #expect(ExportQuality.note(forFormat: "png", percent: 90, bytes: 86_016, weighed: true)
                == "Lossless · 84 KB")
        // Whatever percentage is lying around from the last lossy format, PNG
        // is not that quality and must never say so.
        #expect(ExportQuality.note(forFormat: "png", percent: 30, bytes: 86_016, weighed: true)
                == "Lossless · 84 KB")
    }

    /// The first number costs a render and an encode, so the line has to say
    /// something before it lands, and something else if it never does.
    @Test func theLineSaysSoWhileTheNumberIsBeingWorkedOut() {
        #expect(ExportQuality.note(forFormat: "png", percent: 90, bytes: nil, weighed: false)
                == "Lossless · working out the size")
        #expect(ExportQuality.note(forFormat: "jpeg", percent: 60, bytes: nil, weighed: false)
                == "Good · working out the size")
        // Weighed and still nothing: this picture cannot be encoded at all, so
        // the line stops promising a number that is never coming.
        #expect(ExportQuality.note(forFormat: "png", percent: 90, bytes: nil, weighed: true)
                == "Lossless")
    }
}
