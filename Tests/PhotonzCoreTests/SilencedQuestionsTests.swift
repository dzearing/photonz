import Foundation
import Testing
@testable import PhotonzCore

@Suite("Questions you have silenced")
struct SilencedQuestionsTests {
    private func store() -> SilencedQuestions {
        SilencedQuestions(defaults: InMemorySilenceDefaults())
    }

    @Test func everyQuestionTheAppCanAskIsNamedByItsCommand() {
        // The list is read by a person, so each entry carries the words that
        // appear on the menu row, not an internal id.
        #expect(!SilenceableQuestion.all.isEmpty)
        for question in SilenceableQuestion.all {
            #expect(!question.command.isEmpty)
            #expect(!question.warns.isEmpty)
            #expect(!question.id.isEmpty)
            // No ellipsis: the menu row promises a question, the list names a
            // command.
            #expect(!question.command.hasSuffix("\u{2026}"))
        }
        #expect(Set(SilenceableQuestion.all.map(\.id)).count == SilenceableQuestion.all.count)
    }

    @Test func theOneQuestionThatShipsIsTurnIntoPicture() {
        #expect(SilenceableQuestion.all.map(\.id) == [SilenceableQuestion.turnIntoPicture.id])
        #expect(SilenceableQuestion.turnIntoPicture.command == "Turn Into Picture")
        // The key that already holds people's answers, unchanged: somebody who
        // silenced this last week is still silenced today.
        #expect(SilenceableQuestion.turnIntoPicture.storageKey == "photonz.turnIntoPicture.dontAsk")
    }

    @Test func nothingIsSilencedUntilSomebodySilencesIt() {
        let store = store()
        #expect(store.silenced.isEmpty)
        #expect(store.isSilenced(.turnIntoPicture) == false)
    }

    @Test func silencingPutsTheQuestionOnTheList() {
        let store = store()
        store.silence(.turnIntoPicture)
        #expect(store.isSilenced(.turnIntoPicture))
        #expect(store.silenced.map(\.id) == [SilenceableQuestion.turnIntoPicture.id])
    }

    @Test func askingAgainTakesItOffTheListAndTheCommandAsksAgain() {
        let store = store()
        store.silence(.turnIntoPicture)
        store.askAgain(.turnIntoPicture)
        #expect(store.isSilenced(.turnIntoPicture) == false)
        #expect(store.silenced.isEmpty)
    }

    @Test func askingAgainWhenNothingWasSilencedChangesNothing() {
        let store = store()
        store.askAgain(.turnIntoPicture)
        #expect(store.isSilenced(.turnIntoPicture) == false)
    }

    @Test func theListOnlyEverHoldsWhatWasSilenced() {
        // The list is never a set of switches to go and flip: a question nobody
        // has silenced is simply absent from it.
        let store = store()
        #expect(store.silenced.count == 0)
        store.silence(.turnIntoPicture)
        #expect(store.silenced.count == 1)
        store.askAgain(.turnIntoPicture)
        #expect(store.silenced.count == 0)
    }

    @Test func theAnswerIsRememberedUnderTheQuestionsOwnKey() {
        // Per app bundle, one key per question: dev, probe and the shipping app
        // each keep their own answer, and no question can turn another off.
        let defaults = InMemorySilenceDefaults()
        let store = SilencedQuestions(defaults: defaults)
        store.silence(.turnIntoPicture)
        #expect(defaults.isSilenced(forKey: "photonz.turnIntoPicture.dontAsk"))
        // A second store reading the same defaults sees the same answer.
        #expect(SilencedQuestions(defaults: defaults).isSilenced(.turnIntoPicture))
    }

    @Test func silencedQuestionsComeBackInCatalogOrder() {
        let store = store()
        for question in SilenceableQuestion.all { store.silence(question) }
        #expect(store.silenced.map(\.id) == SilenceableQuestion.all.map(\.id))
    }

    @Test func theEmptyListSaysSoInPlainWords() {
        // The sentence a person reads when they have silenced nothing. It has
        // to read as reassurance, not as an unfinished screen.
        #expect(SilencedQuestions.emptyMessage
            == "Photonz is asking you every question it knows how to ask.")
        #expect(SilencedQuestions.listTitle == "Questions you have silenced")
        #expect(SilencedQuestions.askAgainButton == "Ask Me Again")
    }
}
