import Foundation
import Testing
@testable import PhotonzCore

@Suite("The Settings window's words")
struct SettingsWindowModelTests {
    @Test func theWindowIsCalledWhatEveryMacAppCallsIt() {
        // Somebody looking for this looks under Settings, so the window says
        // Settings and the row that opens it promises a window with an
        // ellipsis.
        #expect(SettingsWindowModel.windowTitle == "Settings")
        #expect(SettingsWindowModel.menuItem == "Settings\u{2026}")
    }

    @Test func thePageIsTheOneTheSilenceStoreAlreadyNames() {
        // One set of words for this list wherever it is shown: the page's
        // heading, its empty sentence and its button all come off the store, so
        // a surface cannot drift from it.
        #expect(SettingsWindowModel.questionsTitle == SilencedQuestions.listTitle)
        #expect(SettingsWindowModel.emptyMessage == SilencedQuestions.emptyMessage)
        #expect(SettingsWindowModel.askAgainButton == SilencedQuestions.askAgainButton)
    }

    @Test func theSentenceSaysHowAQuestionGetsOnTheListAndWhatComesBack() {
        // The page has to be readable by somebody who does not remember what
        // they ticked, so it names the box in the exact words the box wears.
        let said = SettingsWindowModel.questionsBlurb
        #expect(said.contains(RasterizePrompt.suppression))
        #expect(said.contains("next time"))
        #expect(!said.contains("\u{2014}"))
    }

    @Test func nothingInTheWindowIsWrittenForAnAgent() {
        // Every word on this surface is read by a person. A file name, a class
        // name or a defaults key on screen means the wrong words got shipped.
        let all = [SettingsWindowModel.windowTitle, SettingsWindowModel.menuItem,
                   SettingsWindowModel.questionsTitle, SettingsWindowModel.questionsBlurb,
                   SettingsWindowModel.emptyMessage, SettingsWindowModel.askAgainButton]
        for said in all {
            #expect(!said.contains("photonz."))
            #expect(!said.contains(".swift"))
            #expect(!said.isEmpty)
        }
    }

    @Test func aRowSaysTheCommandAndWhatTheQuestionWasProtecting() {
        // One row per silenced question, in the words of the menu row that
        // raises it, so the list is legible without opening a menu to check.
        let store = SilencedQuestions(defaults: InMemorySilenceDefaults())
        store.silence(.turnIntoPath)
        let rows = SettingsWindowModel.rows(of: store)
        #expect(rows.map(\.command) == ["Turn Into Path"])
        #expect(rows[0].warns == SilenceableQuestion.turnIntoPath.warns)
        #expect(rows[0].question == SilenceableQuestion.turnIntoPath)
    }

    @Test func anEmptyListIsTheNormalStateAndSaysSoRatherThanShowingSwitches() {
        // A question nobody silenced is simply absent: the page can never read
        // as a set of switches to go and turn warnings off.
        let store = SilencedQuestions(defaults: InMemorySilenceDefaults())
        #expect(SettingsWindowModel.rows(of: store).isEmpty)
        store.silence(.turnIntoPicture)
        #expect(SettingsWindowModel.rows(of: store).count == 1)
        store.askAgain(.turnIntoPicture)
        #expect(SettingsWindowModel.rows(of: store).isEmpty)
    }
}
