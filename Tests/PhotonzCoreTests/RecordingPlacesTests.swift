import Foundation
import PhotonzCore
import Testing

@Suite("Where you were in a recording")
struct RecordingPlacesTests {

    private let stamp = "1758400000.0-150948"
    private let path = "/Users/someone/Pictures/Screenshots/demo-run.mp4"

    private func places(momentMS: Int = 4_000, durationMS: Int = 8_000,
                        stamp: String? = nil) -> RecordingPlaces {
        var places = RecordingPlaces()
        places.remember(path: path, momentMS: momentMS, durationMS: durationMS,
                        stamp: stamp ?? self.stamp)
        return places
    }

    @Test func aMomentInTheMiddleComesBack() {
        #expect(places().moment(forPath: path, stamp: stamp, durationMS: 8_000) == 4_000)
    }

    @Test func aRecordingNeverOpenedHasNoMoment() {
        #expect(RecordingPlaces().moment(forPath: path, stamp: stamp, durationMS: 8_000) == nil)
    }

    /// The first moments are where a recording opens anyway, so remembering them
    /// buys nothing and forgetting them means a restart really restarts.
    @Test func theOpeningSecondsAreNotWorthRemembering() {
        let places = places(momentMS: 800)
        #expect(places.moment(forPath: path, stamp: stamp, durationMS: 8_000) == nil)
    }

    @Test func watchingItOutIsNotWorthRemembering() {
        let places = places(momentMS: 7_900)
        #expect(places.moment(forPath: path, stamp: stamp, durationMS: 8_000) == nil)
    }

    /// Scrubbing back to the top after leaving off in the middle has to FORGET
    /// the middle, or the next open would ignore what you just did.
    @Test func goingBackToTheStartForgetsTheOldMoment() {
        var places = places(momentMS: 4_000)
        places.remember(path: path, momentMS: 200, durationMS: 8_000, stamp: stamp)
        #expect(places.moment(forPath: path, stamp: stamp, durationMS: 8_000) == nil)
    }

    /// A save writes the trim into the file, so the old moment may point past
    /// the end of what is now there.
    @Test func aFileThatChangedSinceIsStartedOver() {
        let places = places()
        #expect(places.moment(forPath: path, stamp: "1758499999.0-90210", durationMS: 5_000) == nil)
    }

    @Test func aMomentPastTheEndOfAShorterFileIsDropped() {
        let places = places(momentMS: 7_000, durationMS: 8_000)
        #expect(places.moment(forPath: path, stamp: stamp, durationMS: 3_000) == nil)
    }

    /// The length is read off the file again on the way back in, so a moment
    /// that now sits in the last second of it is started over rather than
    /// dropping somebody at the end of a clip they have to scrub back through.
    @Test func aMomentInWhatIsNowTheLastSecondIsStartedOver() {
        var places = RecordingPlaces()
        places.remember(path: path, momentMS: 9_500, durationMS: 20_000, stamp: stamp)
        #expect(places.moment(forPath: path, stamp: stamp, durationMS: 10_000) == nil)
        #expect(places.moment(forPath: path, stamp: stamp, durationMS: 20_000) == 9_500)
    }

    @Test func rememberingAgainReplacesRatherThanStacks() {
        var places = places(momentMS: 4_000)
        places.remember(path: path, momentMS: 5_500, durationMS: 8_000, stamp: stamp)
        #expect(places.places.count == 1)
        #expect(places.moment(forPath: path, stamp: stamp, durationMS: 8_000) == 5_500)
    }

    @Test func onlyTheLastFortyRecordingsAreKept() {
        var places = RecordingPlaces()
        for index in 0..<(RecordingPlaces.limit + 10) {
            places.remember(path: "/tmp/clip-\(index).mp4", momentMS: 4_000,
                            durationMS: 8_000, stamp: stamp)
        }
        #expect(places.places.count == RecordingPlaces.limit)
        // Newest first: the last one written is still there, the first is not.
        #expect(places.moment(forPath: "/tmp/clip-49.mp4", stamp: stamp, durationMS: 8_000) == 4_000)
        #expect(places.moment(forPath: "/tmp/clip-0.mp4", stamp: stamp, durationMS: 8_000) == nil)
    }

    @Test func forgettingOneLeavesTheRest() {
        var places = places()
        places.remember(path: "/tmp/other.mp4", momentMS: 3_000, durationMS: 8_000, stamp: stamp)
        places.forget(path: path)
        #expect(places.moment(forPath: path, stamp: stamp, durationMS: 8_000) == nil)
        #expect(places.moment(forPath: "/tmp/other.mp4", stamp: stamp, durationMS: 8_000) == 3_000)
    }

    @Test func roundTripsThroughJSON() throws {
        let original = places()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RecordingPlaces.self, from: data)
        #expect(decoded == original)
    }
}
