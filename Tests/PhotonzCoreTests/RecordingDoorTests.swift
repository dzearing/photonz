import Foundation
import PhotonzCore
import Testing

@Suite("The way in to a recording")
struct RecordingDoorTests {

    // MARK: - What the facts mean

    @Test func aPlayableFileIsReady() {
        let facts = RecordingFileFacts(exists: true, byteCount: 150_948, durationMS: 8_000)
        #expect(RecordingDoor.state(of: facts) == .ready)
    }

    @Test func nothingThereIsGone() {
        #expect(RecordingDoor.state(of: RecordingFileFacts(exists: false)) == .gone)
    }

    @Test func aGrowingFileIsStillBeingWritten() {
        let facts = RecordingFileFacts(exists: true, byteCount: 4_096, isGrowing: true)
        #expect(RecordingDoor.state(of: facts) == .stillWriting)
    }

    /// A file being copied in can already answer with the length it has SO FAR.
    /// Opening that would put half a recording in the window, so growing wins
    /// over a readable length.
    @Test func growingBeatsAReadableLength() {
        let facts = RecordingFileFacts(exists: true, byteCount: 4_096, isGrowing: true, durationMS: 2_000)
        #expect(RecordingDoor.state(of: facts) == .stillWriting)
    }

    @Test func aFileWithNoLengthInItIsUnplayable() {
        #expect(RecordingDoor.state(of: RecordingFileFacts(exists: true, byteCount: 12)) == .unplayable)
        #expect(RecordingDoor.state(of: RecordingFileFacts(exists: true, byteCount: 12, durationMS: 0)) == .unplayable)
    }

    @Test func anEmptyFileThatIsNotGrowingIsUnplayable() {
        #expect(RecordingDoor.state(of: RecordingFileFacts(exists: true, byteCount: 0)) == .unplayable)
    }

    // MARK: - What it says

    @Test func readySaysNothing() {
        #expect(RecordingDoor.message(for: .ready, name: "demo-run.mp4") == nil)
    }

    @Test func everyRefusalNamesTheFileAndSaysWhy() {
        for state in [RecordingOpenState.gone, .stillWriting, .unplayable] {
            let said = RecordingDoor.message(for: state, name: "demo-run.mp4")
            #expect(said != nil)
            #expect(said?.title.contains("demo-run.mp4") == true)
            #expect(said?.detail.isEmpty == false)
        }
    }

    /// User-facing copy rule: no em dashes anywhere a person reads.
    @Test func nothingItSaysCarriesAnEmDash() {
        var lines = [RecordingDoor.gaveUpMessage(name: "demo-run.mp4")]
        for state in [RecordingOpenState.gone, .stillWriting, .unplayable] {
            if let said = RecordingDoor.message(for: state, name: "demo-run.mp4") { lines.append(said) }
        }
        for line in lines {
            #expect(!line.title.contains("—"))
            #expect(!line.detail.contains("—"))
        }
    }

    @Test func givingUpSaysHowLongItWaited() {
        let said = RecordingDoor.gaveUpMessage(name: "demo-run.mp4")
        #expect(said.detail.contains("\(Int(RecordingDoor.patienceSeconds))"))
    }
}
