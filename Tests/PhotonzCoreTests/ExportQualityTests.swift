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
        // A PNG keeps every pixel and an SVG has none: a quality means nothing
        // for either, so neither grows a control.
        #expect(!ExportQuality.applies(toFormat: "png"))
        #expect(!ExportQuality.applies(toFormat: "svg"))
    }

    /// A format nobody has taught this about gets no control rather than a
    /// control that does nothing. WebP will be taught here when it arrives.
    @Test func anUnknownFormatGetsNoQuality() {
        #expect(!ExportQuality.applies(toFormat: "webp"))
        #expect(!ExportQuality.applies(toFormat: ""))
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
}
