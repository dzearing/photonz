import Testing
@testable import PhotonzCore

/// The description under an Experiments switch is short
/// (`panel-copy-and-flag-descriptions-have-a-length-b`, 2026-09-24).
///
/// On the day this arrived, 91 of the 104 switches were over
/// `CopyBudget.flagDescriptionWords`, the median at 179 words and the longest
/// at 557. The user picked two short sentences and forty words on the card, and
/// every one was rewritten to fit on 2026-09-28
/// (`experiments-switches-say-what-they-do-in-a-sente`), so nothing is allowed
/// over any more. Detail cut from a description belongs in docs/design or a
/// tutorial, not the window.
@Suite("Experiments switch descriptions fit the word budget")
struct FlagDescriptionBudgetTests {

    static var flags: [FeatureFlag] {
        var seen: [String: FeatureFlag] = [:]
        for release in Release.allCases {
            for flag in FeatureCatalog.flags(for: release) where seen[flag.name] == nil {
                seen[flag.name] = flag
            }
        }
        return seen.values.sorted { $0.name < $1.name }
    }

    @Test func noDescriptionOutgrowsItsBudget() {
        for flag in Self.flags {
            let words = CopyBudget.words(in: flag.description)
            #expect(words <= CopyBudget.flagDescriptionWords, """
                \(flag.name) says \(words) words; the budget is \(CopyBudget.flagDescriptionWords). \
                Say what the switch changes in a sentence or two.
                """)
        }
    }

    @Test func noDescriptionRunsPastTwoSentences() {
        for flag in Self.flags {
            let sentences = CopyBudget.sentences(in: flag.description)
            #expect(sentences <= CopyBudget.flagDescriptionSentences, """
                \(flag.name) says \(sentences) sentences; the budget is \
                \(CopyBudget.flagDescriptionSentences): what it changes, and what Off means.
                """)
        }
    }
}
