import Testing
@testable import PhotonzCore

/// One crowd, one set of words, so the drop lines cannot drift apart again.
struct CrowdWordsTests {

    /// Two things are both. "All 2 of them" is a machine counting.
    @Test func twoIsBoth() {
        #expect(CrowdWords.them(2) == "both of them")
    }

    /// From three up the number is the useful part: there is no word for it,
    /// and how many is exactly what somebody wants to know before letting go.
    @Test func threeAndUpStillSayHowMany() {
        #expect(CrowdWords.them(3) == "all 3 of them")
        #expect(CrowdWords.them(12) == "all 12 of them")
    }

    /// One thing is not a crowd, and each sentence names a single target its
    /// own way, so there is nothing to hand back.
    @Test func oneOrNoneIsNotACrowd() {
        #expect(CrowdWords.them(1) == nil)
        #expect(CrowdWords.them(0) == nil)
        #expect(CrowdWords.them(-1) == nil)
    }
}
