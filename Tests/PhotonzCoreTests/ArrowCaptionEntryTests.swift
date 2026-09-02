import PhotonzCore
import Testing

/// The rules of the caption field that opens the moment an arrow lands
/// (Next `next-arrow-captions`). The bug these guard against: pressing A to
/// draw the next arrow typed an "a" into the label, because the field owns
/// the keyboard and the tool had already gone back to Select.
@Suite("Arrow caption entry")
struct ArrowCaptionEntryTests {

    // MARK: Keys

    @Test func returnCommitsAndEscapeCancels() {
        #expect(ArrowCaptionEntry.action(for: .return) == .commit)
        #expect(ArrowCaptionEntry.action(for: .escape) == .cancel)
    }

    /// A caption can start with any letter, including the tool shortcuts, so a
    /// letter is always text. Starting the next arrow is a mouse gesture, not a
    /// key, while the field is open.
    @Test func toolShortcutLettersTypeIntoTheCaption() {
        for tool in Tool.allCases {
            guard let key = tool.shortcutKey else { continue }
            #expect(ArrowCaptionEntry.action(for: .text(String(key))) == .type,
                    "\(key) must type, not pick \(tool)")
            #expect(ArrowCaptionEntry.action(for: .text(String(key).uppercased())) == .type)
        }
        #expect(ArrowCaptionEntry.action(for: .text(" ")) == .type)
    }

    // MARK: Which tool is in hand

    /// The arrow is not finished until its caption is decided: while the field
    /// it opened is up, the Arrow tool stays live so a drag draws the next one.
    /// Every other shape, and an arrow with captions off, hands back to Select
    /// the moment it lands (user request 2026-08-21).
    @Test func arrowStaysInHandOnlyWhileItsFieldIsOpen() {
        #expect(ArrowCaptionEntry.toolAfterLanding(.arrow, offersCaption: true) == .arrow)
        #expect(ArrowCaptionEntry.toolAfterLanding(.arrow, offersCaption: false) == .select)
        #expect(ArrowCaptionEntry.toolAfterLanding(.rectangle, offersCaption: false) == .select)
        #expect(ArrowCaptionEntry.toolAfterLanding(.line, offersCaption: true) == .select)
    }

    /// Closing the field (Return, Esc, click-away) finishes the arrow: Select
    /// comes back. A tool the user picked meanwhile is left alone.
    @Test func closingTheFieldHandsBackFromArrowOnly() {
        #expect(ArrowCaptionEntry.toolAfterClosing(.arrow) == .select)
        #expect(ArrowCaptionEntry.toolAfterClosing(.select) == .select)
        #expect(ArrowCaptionEntry.toolAfterClosing(.rectangle) == .rectangle)
    }

    /// Clicking the tool bar button of the tool ALREADY in hand while the field
    /// is open says "done with this caption, next one": the field closes and
    /// the tool stays. Any other tool button is a plain tool switch (the field
    /// closes on its own, and `toolAfterClosing` leaves the new tool alone);
    /// with no field open a re-pick is nothing at all.
    @Test func repickingTheToolInHandClosesTheFieldAndKeepsIt() {
        #expect(ArrowCaptionEntry.repickClosesField(picked: .arrow, current: .arrow, fieldOpen: true))
        #expect(ArrowCaptionEntry.repickClosesField(picked: .select, current: .select, fieldOpen: true))
        #expect(!ArrowCaptionEntry.repickClosesField(picked: .rectangle, current: .arrow, fieldOpen: true))
        #expect(!ArrowCaptionEntry.repickClosesField(picked: .select, current: .arrow, fieldOpen: true))
        #expect(!ArrowCaptionEntry.repickClosesField(picked: .arrow, current: .arrow, fieldOpen: false))
    }

    /// A press on the canvas while the field is open: with the Arrow tool still
    /// in hand it commits the draft AND starts drawing; otherwise (a re-edit
    /// opened by double-click under Select) it only commits and is swallowed.
    @Test func canvasPressWhileFieldOpen() {
        #expect(ArrowCaptionEntry.pressOutsideField(tool: .arrow) == .commitAndDraw)
        #expect(ArrowCaptionEntry.pressOutsideField(tool: .select) == .commitOnly)
        #expect(ArrowCaptionEntry.pressOutsideField(tool: .text) == .commitOnly)
    }

    // MARK: The draft that lands

    @Test func committedDraftIsSingleLineTrimmedOrNil() {
        #expect(ArrowCaptionEntry.caption(from: "Primary action") == "Primary action")
        #expect(ArrowCaptionEntry.caption(from: "  Save \n") == "Save")
        #expect(ArrowCaptionEntry.caption(from: "two\nlines") == "two lines")
        #expect(ArrowCaptionEntry.caption(from: "") == nil)
        #expect(ArrowCaptionEntry.caption(from: "   \n ") == nil)
    }

    /// The empty field says how to skip it; no em dashes, plain words.
    @Test func placeholderTellsYouHowToSkip() {
        #expect(ArrowCaptionEntry.placeholder.contains("Esc"))
        #expect(!ArrowCaptionEntry.placeholder.contains("\u{2014}"))
        #expect(ArrowCaptionEntry.placeholder.count <= 24)
    }
}
