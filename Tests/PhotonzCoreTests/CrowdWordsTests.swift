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

/// The same crowd, said in front of a noun instead of standing on its own:
/// "both copies", "all 3 labels", "for both". Sentences in the panel needed a
/// word for the crowd that was not "of them", and they were each counting at
/// two because there was nothing else to reach for.
struct CrowdWordsAllTests {

    /// Two of anything are both of it, noun or no noun.
    @Test func twoIsBoth() {
        #expect(CrowdWords.all(2) == "both")
    }

    /// From three up the number carries the sentence, exactly as it does in
    /// `them`, so the two helpers cannot disagree about where counting starts.
    @Test func threeAndUpStillSayHowMany() {
        #expect(CrowdWords.all(3) == "all 3")
        #expect(CrowdWords.all(12) == "all 12")
    }

    /// One thing is not a crowd, and each sentence names a single target its
    /// own way.
    @Test func oneOrNoneIsNotACrowd() {
        #expect(CrowdWords.all(1) == nil)
        #expect(CrowdWords.all(0) == nil)
    }

    /// `them` is `all` with two words after it, so a change to where counting
    /// starts reaches both at once.
    @Test func themIsAllOfThem() {
        for count in 2...9 {
            #expect(CrowdWords.them(count) == CrowdWords.all(count).map { "\($0) of them" })
        }
    }
}
