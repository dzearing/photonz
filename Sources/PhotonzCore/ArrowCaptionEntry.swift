import Foundation

/// The rules of the caption field that opens the moment an arrow lands
/// (Next `next-arrow-captions`): what the keys do, which tool is in hand while
/// it is open, and what a committed draft becomes. Both the on-canvas field
/// and the inspector's Caption field read from here, so they cannot drift.
///
/// The idea in one line: **an arrow is not finished until its caption is
/// decided.** While the field it opened is up, the Arrow tool stays live, so a
/// canvas drag leaves this arrow plain and draws the next one. Anything that
/// closes the field (Command and Return, Esc, a click) finishes the arrow and
/// hands back to Select, the way every drawing tool does the moment its object
/// exists.
///
/// A caption holds as many lines as you type. Plain Return drops a line, the
/// way it does in the text tool's field on the same canvas, and Command and
/// Return finishes the label (user request 2026-09-06). Before that, Return
/// committed and a label that wanted two lines had to be squeezed into one
/// long strip.
public enum ArrowCaptionEntry {

    /// What the empty field shows. Short enough to fit a one-word pill at the
    /// default caption size, and it names the one key that is not obvious.
    public static let placeholder = "Caption, Esc to skip"

    // MARK: Keys

    public enum Key: Equatable, Sendable {
        /// Return, with or without the Command key held.
        case `return`(command: Bool)
        case escape
        /// Any typed text, including the tool shortcut letters.
        case text(String)
    }

    public enum Action: Equatable, Sendable {
        case commit
        case cancel
        /// Insert the text. A caption can start with any letter, so a tool
        /// shortcut never steals a keystroke from an open caption field.
        case type
    }

    public static func action(for key: Key) -> Action {
        switch key {
        case .return(let command): command ? .commit : .type
        case .escape: .cancel
        case .text: .type
        }
    }

    // MARK: Which tool is in hand

    /// The tool after a drag-to-create lands. Only an arrow that is about to
    /// offer its caption keeps the tool; everything else returns to Select with
    /// the new object selected (user request 2026-08-21: nudge it right away).
    public static func toolAfterLanding(_ tool: Tool, offersCaption: Bool) -> Tool {
        tool == .arrow && offersCaption ? .arrow : .select
    }

    /// The tool after the field closes. The Arrow tool that stayed live hands
    /// back to Select; a tool the user picked meanwhile (a tool bar click while
    /// the field was open) is left alone.
    public static func toolAfterClosing(_ tool: Tool) -> Tool {
        tool == .arrow ? .select : tool
    }

    /// A tool bar click while the field is open. A different tool is a plain
    /// switch: the field closes on its own and that tool stays in hand. The
    /// tool ALREADY in hand (the Arrow button right after drawing an arrow)
    /// would otherwise be a no-op that leaves the field up; read it as "done
    /// with this caption, next one": the field closes and the tool stays.
    public static func repickClosesField(picked: Tool, current: Tool, fieldOpen: Bool) -> Bool {
        fieldOpen && picked == current
    }

    public enum PressOutcome: Equatable, Sendable {
        /// Commit the draft and let the press start the next arrow.
        case commitAndDraw
        /// Commit the draft and swallow the press.
        case commitOnly
    }

    /// A mouse press on the canvas outside the open field.
    public static func pressOutsideField(tool: Tool) -> PressOutcome {
        tool == .arrow ? .commitAndDraw : .commitOnly
    }

    // MARK: The draft that lands

    /// Whitespace-only text is no caption (a fresh arrow stays plain, an edited
    /// one loses its label).
    ///
    /// The lines you typed are kept. Each one is trimmed, and an empty line at
    /// either END is dropped rather than drawn as a band of nothing inside the
    /// pill — a stray Return before or after the words is a slip, while a blank
    /// line BETWEEN two of them was typed on purpose.
    public static func caption(from draft: String) -> String? {
        var lines = draft.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        while lines.first?.isEmpty == true { lines.removeFirst() }
        while lines.last?.isEmpty == true { lines.removeLast() }
        let text = lines.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    /// The lines a caption draws in. Everything that has to reserve room for a
    /// pill without laying out a glyph counts them through here.
    public static func lines(of caption: String) -> [String] {
        caption.isEmpty ? [""] : caption.components(separatedBy: "\n")
    }

    /// How many rows of type a caption draws — never fewer than one, so an
    /// empty field still reserves a line's worth of pill.
    public static func lineCount(of caption: String) -> Int {
        max(lines(of: caption).count, 1)
    }

    /// The line the pill has to be wide enough for.
    public static func longestLine(of caption: String) -> String {
        lines(of: caption).max(by: { $0.count < $1.count }) ?? ""
    }
}
