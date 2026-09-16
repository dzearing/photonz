import Foundation
import PhotonzCore
import Testing

/// The other end of a guide: what the app says and offers the moment somebody
/// presses Done. A value, so every rule about it is settled here rather than in
/// a window nobody can test.
@Suite("Tutorial finish")
struct TutorialFinishTests {

    // A track of three, so "the next one" and "there is no next one" are both
    // reachable without leaning on the shipping catalogue's current order.
    private func guide(_ id: String, _ track: TutorialTrack,
                       sample: TutorialSample?) -> TutorialGuide {
        TutorialGuide(id: id, track: track, title: id.capitalized,
                      summary: "A made up guide.", minutes: 1, sample: sample,
                      steps: [TutorialStep(id: "one", anchor: .toolBar,
                                           title: "Look", body: "Look at it.")])
    }

    private var track: [TutorialGuide] {
        [guide("first", .basics, sample: .starterScreen),
         guide("second", .basics, sample: .starterScreen),
         guide("third", .basics, sample: .starterScreen),
         guide("elsewhere", .icons, sample: .iconFrame)]
    }

    // MARK: What it says

    @Test func itNamesTheGuideThatJustFinished() {
        let finish = TutorialFinish.make(after: track[0], offered: track, inSampleWindow: true)
        #expect(finish.guideID == "first")
        #expect(finish.title.contains("First"))
        #expect(!finish.message.isEmpty)
    }

    @Test func aPracticeWindowSaysSoRatherThanLettingSomebodyThinkItIsTheirs() {
        let finish = TutorialFinish.make(after: track[0], offered: track, inSampleWindow: true)
        #expect(finish.message.lowercased().contains("practice"))
    }

    @Test func aGuideTaughtOverYourOwnPictureNeverCallsItPractice() {
        let own = guide("yours", .basics, sample: nil)
        let finish = TutorialFinish.make(after: own, offered: [own], inSampleWindow: false)
        #expect(!finish.message.lowercased().contains("practice"))
    }

    // MARK: What it offers

    @Test func theNextGuideOnTheSameTrackIsTheFirstThingOffered() {
        let finish = TutorialFinish.make(after: track[0], offered: track, inSampleWindow: true)
        #expect(finish.choices.first == .nextGuide(id: "second", title: "Second"))
    }

    @Test func aTrackNeverRunsOnIntoAnotherTrack() {
        let finish = TutorialFinish.make(after: track[2], offered: track, inSampleWindow: true)
        #expect(!finish.choices.contains { if case .nextGuide = $0 { true } else { false } })
    }

    @Test func theEndOfATrackOffersTheOtherGuidesInstead() {
        let finish = TutorialFinish.make(after: track[2], offered: track, inSampleWindow: true)
        #expect(finish.choices.contains(.moreGuides))
        // And going and working comes first, because the track is done.
        #expect(finish.choices.first == .startYourOwn)
    }

    @Test func aPracticeWindowAlwaysOffersAWayIntoYourOwnWork() {
        for finished in [track[0], track[2]] {
            let finish = TutorialFinish.make(after: finished, offered: track, inSampleWindow: true)
            #expect(finish.choices.contains(.startYourOwn))
        }
    }

    @Test func aGuideTaughtInYourOwnWindowNeverOffersToTakeYouOutOfIt() {
        let own = guide("yours", .basics, sample: nil)
        let finish = TutorialFinish.make(after: own, offered: [own], inSampleWindow: false)
        #expect(!finish.choices.contains(.startYourOwn))
        #expect(finish.choices == [.moreGuides])
    }

    @Test func aGuideSwitchedOffIsNeverOfferedAsTheNextOne() {
        // The middle guide is not on offer (its feature is switched off), so
        // the one after it is what comes next.
        let offered = [track[0], track[2]]
        let finish = TutorialFinish.make(after: track[0], offered: offered, inSampleWindow: true)
        #expect(finish.choices.first == .nextGuide(id: "third", title: "Third"))
    }

    @Test func thereIsAlwaysSomethingToPress() {
        for finished in TutorialCatalog.guides {
            let finish = TutorialFinish.make(after: finished, offered: TutorialCatalog.guides,
                                             inSampleWindow: true)
            #expect(!finish.choices.isEmpty)
            #expect(finish.choices.allSatisfy { !$0.label.isEmpty && !$0.symbol.isEmpty })
            // Every choice is nameable, which is how a walk presses one.
            #expect(Set(finish.choices.map(\.name)).count == finish.choices.count)
        }
    }

    // MARK: An empty window is already a place to start

    @Test func aGuideTaughtInAnEmptyWindowDoesNotOfferToOpenAnotherOne() {
        // `.emptyWindow` is a sample, but it is already the empty editor with
        // the card offering every way in, so moving somebody on from it would
        // hand them the same window again.
        #expect(TutorialSample.emptyWindow.isMadeUpPicture == false)
        #expect(TutorialSample.starterScreen.isMadeUpPicture)
        #expect(TutorialSample.sampleRecording.isMadeUpPicture)
    }

    // MARK: Copy rules

    @Test func nothingItSaysUsesAnEmDash() {
        for finished in TutorialCatalog.guides {
            for sample in [true, false] {
                let finish = TutorialFinish.make(after: finished,
                                                 offered: TutorialCatalog.guides,
                                                 inSampleWindow: sample)
                #expect(!finish.title.contains("—"))
                #expect(!finish.message.contains("—"))
                #expect(finish.choices.allSatisfy { !$0.label.contains("—") })
            }
        }
    }

    @Test func everyShippingGuideEndsSomewhere() {
        for finished in TutorialCatalog.guides {
            let finish = TutorialFinish.make(after: finished, offered: TutorialCatalog.guides,
                                             inSampleWindow: finished.sample?.isMadeUpPicture ?? false)
            #expect(finish.title.contains(finished.title))
            #expect(!finish.choices.isEmpty)
        }
    }
}
