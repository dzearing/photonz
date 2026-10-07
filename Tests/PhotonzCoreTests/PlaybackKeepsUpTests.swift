import PhotonzCore
import Testing

/// A walk that played a full-screen recording said 17 of its 24 looks held a
/// frame 16 behind, and passed (`a-full-screen-retina-recording-keeps-up-while-it`).
/// Lateness is a failure now, inside a small allowance for a loaded machine.
@Suite("How late a playing picture may be before a walk fails")
struct PlaybackKeepsUpTests {

    @Test("Every frame in time passes")
    func inTime() {
        #expect(PlaybackKeepsUp.problem(lateLooks: [], framesBehind: 0, looks: 24) == nil)
    }

    @Test("Two late looks a frame or two behind pass")
    func allowance() {
        #expect(PlaybackKeepsUp.problem(lateLooks: [3, 17], framesBehind: 2, looks: 24) == nil)
    }

    @Test("A third late look fails, naming the looks")
    func tooManyLate() {
        let problem = PlaybackKeepsUp.problem(lateLooks: [3, 9, 17], framesBehind: 1, looks: 24)
        #expect(problem?.contains("3 of 24") == true)
        #expect(problem?.contains("3, 9, 17") == true)
    }

    @Test("One look three frames behind fails")
    func tooFarBehind() {
        let problem = PlaybackKeepsUp.problem(lateLooks: [5], framesBehind: 3, looks: 24)
        #expect(problem?.contains("3 frames behind") == true)
    }
}
