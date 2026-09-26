import Foundation

/// How much the app may say in the places a person reads at a glance: a line
/// in the right hand panel, and the description under an Experiments switch.
///
/// UX-PATTERNS §4 "How much a section may say" settled it on 2026-09-14: one
/// short line, and only when it earns it. Nothing held anyone to that, so by
/// 2026-09-23 video sections carried paragraphs and switch descriptions ran to
/// 557 words. The tests read the app's own source with `phrases(inSwift:)` and
/// fail the day a new sentence lands (`PanelCopyBudgetTests`,
/// `FlagDescriptionBudgetTests`).
public enum CopyBudget {

    /// The longest line a panel may show, in characters. UX-PATTERNS asks for
    /// about forty at the panel's default width; sixty is the hard wall.
    public static let panelLine = 60

    /// The longest thing the chrome outside the panel may say, in characters:
    /// the timeline, the transport, the tool bar, canvas overlays, popovers,
    /// toasts and empty states. A label or a value, never a sentence
    /// (`no-sentences-or-debug-readouts-anywhere-in-the-c`, 2026-09-25).
    public static let chromeLine = 30

    /// The longest description an Experiments switch may carry, in words.
    public static let flagDescriptionWords = 40

    /// What an interpolated value counts as: a number or a short name.
    public static let interpolation = "····"

    /// One piece of text as it would be read: a literal, or several glued
    /// together with `+`.
    public struct Phrase: Equatable, Sendable {
        public let text: String
        /// 1-based line the phrase starts on.
        public let line: Int
        /// A hover tip. The budget sends cut sentences there, so it is not
        /// held to the panel line.
        public let isTooltip: Bool

        public init(text: String, line: Int, isTooltip: Bool) {
            self.text = text
            self.line = line
            self.isTooltip = isTooltip
        }
    }

    public static func overPanelBudget(_ text: String) -> Bool {
        text.count > panelLine
    }

    /// What is wrong with a piece of chrome copy.
    public enum ChromeFault: String, Sendable, CaseIterable {
        /// Over `chromeLine` characters.
        case long
        /// Says something in a sentence: ends on a full stop, or has two.
        case sentence
        /// Reads like a debug value: `@`, or raw milliseconds.
        case debug
        /// "no X": a placeholder where nothing should be shown at all.
        case placeholder
        /// An explanation in brackets.
        case parenthetical
    }

    /// Every rule a piece of chrome copy breaks, in `ChromeFault` order.
    public static func chromeFaults(_ text: String) -> [ChromeFault] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var faults: [ChromeFault] = []
        if trimmed.count > chromeLine { faults.append(.long) }
        let endsOnAStop = trimmed.hasSuffix(".") && !trimmed.hasSuffix("...")
        if endsOnAStop || trimmed.contains(". ") { faults.append(.sentence) }
        if trimmed.contains("@") || trimmed.contains(interpolation + "ms") { faults.append(.debug) }
        if trimmed.lowercased().hasPrefix("no ") { faults.append(.placeholder) }
        if bracketsExplain(trimmed) { faults.append(.parenthetical) }
        return faults
    }

    /// Brackets holding words, as against a shortcut: "(slowed)", not "(B)".
    static func bracketsExplain(_ text: String) -> Bool {
        var inside: String?
        for c in text {
            if c == "(" { inside = ""; continue }
            if c == ")", let words = inside {
                if words.filter(\.isLetter).count > 1 { return true }
                inside = nil
                continue
            }
            inside?.append(c)
        }
        return false
    }

    /// A string the code uses as a name rather than words: a key, a
    /// coordinate space, a symbol. One unbroken lower-case-led run.
    public static func isIdentifier(_ text: String) -> Bool {
        guard let first = text.first, first.isLowercase else { return false }
        return text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" }
    }

    public static func words(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// How an allowed offender is named in a list: its opening forty characters.
    public static func key(_ text: String) -> String {
        String(text.prefix(40))
    }

    // MARK: - Reading Swift source

    /// Calls whose string arguments are hover tips.
    static let tooltipCalls: Set<String> = ["panelHelp", "help", "segmentToolTips", "toolTip"]

    /// Calls and labels whose strings are never shown as words.
    static let hiddenCalls: Set<String> = [
        "accessibilityIdentifier", "print", "fatalError", "precondition", "preconditionFailure",
        "assert", "assertionFailure", "NSLog",
        // Probes a scripted walk reads, compiled out of a release, and what a
        // screen reader says: none of it is drawn.
        "panelReadout", "playtestControl", "playtestField", "playtestHover", "panelStartProbe",
        "tutorialAnchor", "accessibilityLabel", "accessibilityValue", "accessibilityHint",
    ]
    static let hiddenLabels: Set<String> = [
        "systemName", "named", "forKey", "identifier", "id", "key", "defaultsKey",
    ]

    static func isTooltipLabel(_ label: String) -> Bool {
        let lower = label.lowercased()
        return lower.hasSuffix("help") || lower.hasSuffix("tip") || lower.hasSuffix("tooltip")
            || lower == "hint"
    }

    /// A declaration whose name says it holds a hover tip: `help`,
    /// `placeHelp(_:)`, `helpText`, `showTip`.
    static func isTooltipName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return isTooltipLabel(name) || lower.hasSuffix("helptext") || lower.hasSuffix("tiptext")
    }

    /// A declaration whose name says it holds words for a scripted walk or a
    /// screen reader: `readout`, `readoutText`, `trackSummary`.
    static func isProbeWordsName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("playtest") || lower.hasSuffix("readout") || lower.hasSuffix("readouttext")
            || lower.hasSuffix("summary") || lower.hasSuffix("description")
    }

    private enum Register { case copy, tooltip, hidden }

    private struct Frame {
        let register: Register
        let closer: Character
        var argument: Register = .copy
        /// A brace frame's label reaches the end of its line; a paren frame's
        /// reaches the next comma.
        var endsAtNewline: Bool { closer == "}" }
    }

    /// Every piece of text a Swift file would put in front of a person, with
    /// hover tips marked and identifiers, symbol names and log lines left out.
    /// A heuristic reader, not a parser: it handles comments, escapes,
    /// interpolations, raw and multi-line literals, and literals glued with `+`.
    public static func phrases(inSwift source: String) -> [Phrase] {
        var reader = Reader(Array(source))
        return reader.run()
    }

    private struct Reader {
        let chars: [Character]
        var i = 0
        var line = 1
        var frames: [Frame] = []
        var pendingIdent = ""
        var phrases: [Phrase] = []
        /// The last word was `func`, `var` or `let`, so the next is a name.
        var naming = false
        /// Depth of a declaration named for a tip (`placeHelp`, `helpText`)
        /// whose body or value is still to come.
        var tipDeclaration: Int?
        /// The same for a declaration named for a probe's words (`readout`).
        var probeDeclaration: Int?

        init(_ chars: [Character]) { self.chars = chars }

        func peek(_ offset: Int = 0) -> Character? {
            i + offset < chars.count ? chars[i + offset] : nil
        }

        var register: Register {
            var result = Register.copy
            for frame in frames {
                for r in [frame.register, frame.argument] {
                    if r == .hidden { return .hidden }
                    if r == .tooltip { result = .tooltip }
                }
            }
            return result
        }

        mutating func advance() {
            if chars[i] == "\n" { line += 1 }
            i += 1
        }

        mutating func run() -> [Phrase] {
            while i < chars.count {
                let c = chars[i]
                if c == "/" && peek(1) == "/" {
                    while i < chars.count && chars[i] != "\n" { advance() }
                    continue
                }
                if c == "/" && peek(1) == "*" {
                    advance(); advance()
                    while i < chars.count && !(chars[i] == "*" && peek(1) == "/") { advance() }
                    if i < chars.count { advance(); advance() }
                    continue
                }
                if c == "\"" || (c == "#" && peek(1) == "\"") {
                    let startLine = line
                    var reg = register
                    if tipDeclaration == frames.count, reg == .copy {
                        reg = .tooltip
                        tipDeclaration = nil
                    }
                    if probeDeclaration == frames.count {
                        reg = .hidden
                        probeDeclaration = nil
                    }
                    var text = readLiteral()
                    while let next = gluedLiteralStart() {
                        i = next.index
                        line = next.line
                        text += readLiteral()
                    }
                    pendingIdent = ""
                    if reg != .hidden {
                        phrases.append(Phrase(text: text, line: startLine, isTooltip: reg == .tooltip))
                    }
                    continue
                }
                if c.isLetter || c == "_" {
                    var ident = ""
                    while let ch = peek(), ch.isLetter || ch.isNumber || ch == "_" {
                        ident.append(ch); advance()
                    }
                    pendingIdent = ident
                    if naming {
                        naming = false
                        if CopyBudget.isTooltipName(ident) { tipDeclaration = frames.count }
                        if CopyBudget.isProbeWordsName(ident) { probeDeclaration = frames.count }
                        continue
                    }
                    if ["func", "var", "let"].contains(ident) {
                        naming = true
                        continue
                    }
                    if peek() == ":" && peek(1) != ":", !frames.isEmpty {
                        let reg: Register = CopyBudget.hiddenLabels.contains(ident) ? .hidden
                            : CopyBudget.isTooltipLabel(ident) ? .tooltip : .copy
                        frames[frames.count - 1].argument = reg
                        advance()
                        pendingIdent = ""
                    }
                    continue
                }
                switch c {
                case "(":
                    let reg: Register = CopyBudget.tooltipCalls.contains(pendingIdent) ? .tooltip
                        : CopyBudget.hiddenCalls.contains(pendingIdent) ? .hidden : .copy
                    frames.append(Frame(register: reg, closer: ")"))
                case "[":
                    frames.append(Frame(register: .copy, closer: "]"))
                case "{":
                    let named = tipDeclaration == frames.count
                    if named { tipDeclaration = nil }
                    let probe = probeDeclaration == frames.count
                    if probe { probeDeclaration = nil }
                    frames.append(Frame(register: probe ? .hidden : named ? .tooltip : .copy, closer: "}"))
                case ")", "]", "}":
                    if let last = frames.last, last.closer == c { frames.removeLast() }
                case ",":
                    if !frames.isEmpty { frames[frames.count - 1].argument = .copy }
                case "\n", ";":
                    if tipDeclaration == frames.count { tipDeclaration = nil }
                    if probeDeclaration == frames.count { probeDeclaration = nil }
                    if let last = frames.last, last.endsAtNewline || c == ";" {
                        frames[frames.count - 1].argument = .copy
                    }
                default:
                    break
                }
                if !c.isWhitespace {
                    pendingIdent = ""
                    naming = false
                }
                advance()
            }
            return phrases
        }

        /// After a literal: the start of the next one when a `+` glues them.
        func gluedLiteralStart() -> (index: Int, line: Int)? {
            var j = i
            var l = line
            func skipSpace() {
                while j < chars.count, chars[j].isWhitespace {
                    if chars[j] == "\n" { l += 1 }
                    j += 1
                }
            }
            skipSpace()
            guard j < chars.count, chars[j] == "+" else { return nil }
            j += 1
            skipSpace()
            guard j < chars.count else { return nil }
            if chars[j] == "\"" || (chars[j] == "#" && j + 1 < chars.count && chars[j + 1] == "\"") {
                return (j, l)
            }
            return nil
        }

        /// Reads one literal starting at `i` and returns what it says.
        mutating func readLiteral() -> String {
            var hashes = 0
            while peek() == "#" { hashes += 1; advance() }
            let multiline = peek() == "\"" && peek(1) == "\"" && peek(2) == "\""
            if multiline { advance(); advance(); advance() } else { advance() }
            let closing = String(repeating: "#", count: hashes)
            var text = ""
            while i < chars.count {
                let c = chars[i]
                if multiline {
                    if c == "\"" && peek(1) == "\"" && peek(2) == "\"" && matches(closing, at: i + 3) {
                        for _ in 0..<(3 + hashes) { advance() }
                        return text.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                } else if c == "\"" && matches(closing, at: i + 1) {
                    for _ in 0..<(1 + hashes) { advance() }
                    return text
                } else if c == "\n" {
                    return text
                }
                if c == "\\" && matches(closing, at: i + 1) {
                    let escapeAt = i + 1 + hashes
                    if escapeAt < chars.count && chars[escapeAt] == "(" {
                        for _ in 0..<(1 + hashes) { advance() }
                        skipInterpolation()
                        text += CopyBudget.interpolation
                        continue
                    }
                    if hashes == 0 {
                        text.append(c); advance()
                        if i < chars.count { text.append(chars[i]); advance() }
                        continue
                    }
                }
                text.append(c)
                advance()
            }
            return text
        }

        func matches(_ hashes: String, at index: Int) -> Bool {
            var j = index
            for h in hashes {
                guard j < chars.count, chars[j] == h else { return false }
                j += 1
            }
            return true
        }

        /// Skips `( … )` of an interpolation, strings inside it included.
        mutating func skipInterpolation() {
            var depth = 0
            while i < chars.count {
                let c = chars[i]
                if c == "\"" {
                    _ = readLiteral()
                    continue
                }
                if c == "(" { depth += 1 }
                if c == ")" {
                    depth -= 1
                    if depth == 0 { advance(); return }
                }
                advance()
            }
        }
    }
}
