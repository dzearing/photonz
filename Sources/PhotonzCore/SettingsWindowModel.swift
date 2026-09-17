import Foundation

/// The words on the app's Settings window, and the rows its one page draws.
///
/// Photonz had no Settings window at all until this, so the window exists for
/// exactly one reason: "Don't ask again" must never be a door that locks behind
/// you (UX-PATTERNS §3, "The question you can silence"). Tick the box and the
/// question is gone; this is the place that hands it back.
///
/// One page, no sidebar. There is one page of content, and four invented ones
/// to make the window look like a settings window would be decoration. A
/// sidebar arrives the day a second page does.
public enum SettingsWindowModel {

    /// What the window is called, and what the menu row that opens it says.
    /// The ellipsis is the macOS promise that a window comes next.
    public static let windowTitle = "Settings"
    public static let menuItem = "Settings\u{2026}"

    /// The heading over the one page, shared with every other surface that
    /// might show this list (`SilencedQuestions.listTitle`).
    public static let questionsTitle = SilencedQuestions.listTitle

    /// One sentence saying how a question gets on the list and what turning it
    /// back on does. It quotes the box by the words the box actually wears, so
    /// somebody who does not remember what they ticked can still recognise it.
    public static let questionsBlurb =
        "A question turns up here when you tick \u{201C}\(RasterizePrompt.suppression)\u{201D} on it. "
        + "Turn one back on and Photonz asks it the next time you use that command."

    /// What the page says when nothing has been silenced, which is the normal
    /// state and reads as reassurance rather than an unfinished screen.
    public static let emptyMessage = SilencedQuestions.emptyMessage

    /// The button on every row.
    public static let askAgainButton = SilencedQuestions.askAgainButton

    /// One row of the page: the command in the words of its menu row, and the
    /// sentence saying what its question was protecting.
    public struct QuestionRow: Identifiable, Hashable, Sendable {
        public let question: SilenceableQuestion
        public var id: String { question.id }
        public var command: String { question.command }
        public var warns: String { question.warns }

        public init(question: SilenceableQuestion) {
            self.question = question
        }
    }

    /// The rows to draw right now: ONLY what was actually silenced, so the page
    /// can never read as a set of switches inviting you to turn warnings off.
    public static func rows(of store: SilencedQuestions) -> [QuestionRow] {
        store.silenced.map(QuestionRow.init)
    }
}
