import Foundation

/// Reads Swift source and names every icon-only control that sets a faint ink
/// of its own, so a button you can press cannot quietly come to look disabled
/// again (`IconButtonTone`; the user's report of 2026-10-24).
///
/// What it reads as an icon control: a `Button`, `Menu` or `Toggle` whose
/// label is a picture and carries no words, and a bare `Image` that a gesture
/// drives (a reorder grip). What it reads as faint: `.tertiary` or
/// `.quaternary`, or an opacity under a half, set on the label or on the
/// control itself. Strokes, text and popovers hung on the control are not its
/// ink and are not read.
///
/// A control that is quiet for a reason (a hint rather than a button, the
/// Mac's own convention) says so in a `quiet on purpose:` comment on the
/// control or on the lines just above it, and is let through.
public enum FaintIconScan {

    public static let quietMarker = "// quiet on purpose:"

    public struct Finding: Sendable, Equatable {
        /// 1-based line the faint ink is set on.
        public let line: Int
        /// That line, trimmed.
        public let text: String
    }

    public static func findings(inSwift source: String) -> [Finding] {
        let reader = Reader(source)
        var lines = Set<Int>()
        for start in reader.controlStarts() {
            for at in reader.faintInk(ofControlAt: start) { lines.insert(reader.line(at)) }
        }
        for start in reader.imageStarts() {
            for at in reader.faintInk(ofGestureImageAt: start) { lines.insert(reader.line(at)) }
        }
        return lines.sorted().map { Finding(line: $0, text: reader.text(ofLine: $0)) }
    }
}

// MARK: - Reading

private struct Reader {
    let bytes: [UInt8]
    /// True where the byte is code: not inside a comment or a string literal
    /// (an interpolation inside a string is code again).
    let isCode: [Bool]
    let lineStarts: [Int]

    init(_ source: String) {
        bytes = Array(source.utf8)
        isCode = Self.codeMask(bytes)
        var starts = [0]
        for (i, b) in bytes.enumerated() where b == UInt8(ascii: "\n") { starts.append(i + 1) }
        lineStarts = starts
    }

    func line(_ index: Int) -> Int {
        var lo = 0, hi = lineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStarts[mid] <= index { lo = mid } else { hi = mid - 1 }
        }
        return lo + 1
    }

    func text(ofLine line: Int) -> String {
        let start = lineStarts[line - 1]
        let end = line < lineStarts.count ? lineStarts[line] - 1 : bytes.count
        return String(decoding: bytes[start..<max(start, end)], as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)
    }

    func string(_ range: Range<Int>) -> String {
        String(decoding: bytes[range], as: UTF8.self)
    }

    // MARK: Finding controls

    func controlStarts() -> [Int] {
        ["Button", "Menu", "Toggle"].flatMap { word in
            occurrences(of: word).filter { at in
                let next = skipSpaces(at + word.utf8.count, newlines: false)
                return next < bytes.count && (bytes[next] == UInt8(ascii: "(") || bytes[next] == UInt8(ascii: "{"))
            }
        }
    }

    func imageStarts() -> [Int] {
        occurrences(of: "Image").filter { at in
            let next = at + 5
            return next < bytes.count && bytes[next] == UInt8(ascii: "(")
        }
    }

    /// Where `word` appears in code as a whole identifier.
    private func occurrences(of word: String, member: Bool = false) -> [Int] {
        let w = Array(word.utf8)
        guard bytes.count >= w.count else { return [] }
        var found: [Int] = []
        var i = 0
        while i <= bytes.count - w.count {
            if bytes[i] == w[0], isCode[i], bytes[i..<(i + w.count)].elementsEqual(w),
               (i == 0 || !Self.isIdentifier(bytes[i - 1]) && (member || bytes[i - 1] != UInt8(ascii: "."))),
               i + w.count == bytes.count || !Self.isIdentifier(bytes[i + w.count]) {
                found.append(i)
                i += w.count
            } else {
                i += 1
            }
        }
        return found
    }

    // MARK: A control

    /// The faint inks a control sets on its label or on itself, as offsets.
    func faintInk(ofControlAt start: Int) -> [Int] {
        var at = skipSpaces(start, newlines: false)
        while at < bytes.count, Self.isIdentifier(bytes[at]) { at += 1 }
        at = skipSpaces(at, newlines: false)
        var label: Range<Int>?
        var firstClosure: Range<Int>?
        var hadArguments = false
        if at < bytes.count, bytes[at] == UInt8(ascii: "(") {
            guard let close = matching(at) else { return [] }
            // A title in words: `Button("Remove") { ... }`.
            let first = skipSpaces(at + 1, newlines: true)
            if first < bytes.count, bytes[first] == UInt8(ascii: "\"") { return [] }
            hadArguments = true
            at = close + 1
        }
        var end = at
        var next = skipSpaces(at, newlines: false)
        if next < bytes.count, bytes[next] == UInt8(ascii: "{"), let close = matching(next) {
            firstClosure = next..<(close + 1)
            end = close + 1
            next = skipSpaces(end, newlines: true)
            if hasWord("label:", at: next) {
                let open = skipSpaces(next + 6, newlines: true)
                if open < bytes.count, bytes[open] == UInt8(ascii: "{"), let close = matching(open) {
                    label = open..<(close + 1)
                    end = close + 1
                }
            } else if hadArguments {
                label = firstClosure
            }
        }
        guard let label else { return [] }
        let labelText = string(label)
        guard labelText.contains("Image("), !labelText.contains("Text("), !labelText.contains("Label(") else { return [] }
        let chain = modifierChain(from: end)
        let whole = start..<(chain.last?.range.upperBound ?? end)
        if saysWhyItIsQuiet(whole) { return [] }
        return faintCalls(in: label) + faintModifiers(chain)
    }

    /// The faint inks a gesture-driven picture sets on itself.
    func faintInk(ofGestureImageAt start: Int) -> [Int] {
        guard let close = matching(start + 5) else { return [] }
        let chain = modifierChain(from: close + 1)
        let gestures: Set<String> = ["gesture", "highPriorityGesture", "simultaneousGesture", "onTapGesture"]
        guard chain.contains(where: { gestures.contains($0.name) }) else { return [] }
        let whole = start..<(chain.last?.range.upperBound ?? close + 1)
        if saysWhyItIsQuiet(whole) { return [] }
        return faintModifiers(chain)
    }

    // MARK: Modifiers

    struct Modifier {
        let name: String
        let range: Range<Int>
        /// Inside the modifier's parentheses.
        let arguments: Range<Int>?
    }

    /// `.font(...)`, `.foregroundStyle(...)`, `.popover(...) { ... }` and so
    /// on, one after another across lines and comments.
    func modifierChain(from start: Int) -> [Modifier] {
        var chain: [Modifier] = []
        var at = start
        while true {
            let dot = skipSpacesAndComments(at)
            guard dot + 1 < bytes.count, bytes[dot] == UInt8(ascii: "."), Self.isIdentifier(bytes[dot + 1]) else { break }
            var i = dot + 1
            while i < bytes.count, Self.isIdentifier(bytes[i]) { i += 1 }
            let name = string((dot + 1)..<i)
            var arguments: Range<Int>?
            if i < bytes.count, bytes[i] == UInt8(ascii: "("), let close = matching(i) {
                arguments = (i + 1)..<close
                i = close + 1
            }
            while true {
                let open = skipSpaces(i, newlines: false)
                guard open < bytes.count, bytes[open] == UInt8(ascii: "{"), let close = matching(open) else { break }
                i = close + 1
            }
            chain.append(Modifier(name: name, range: dot..<i, arguments: arguments))
            at = i
        }
        return chain
    }

    private func faintModifiers(_ chain: [Modifier]) -> [Int] {
        chain.compactMap { modifier in
            guard let arguments = modifier.arguments else { return nil }
            switch modifier.name {
            case "foregroundStyle", "foregroundColor":
                return Self.isFaintStyle(string(arguments)) ? modifier.range.lowerBound : nil
            case "opacity":
                return Self.isFaintOpacity(string(arguments)) ? modifier.range.lowerBound : nil
            default:
                return nil
            }
        }
    }

    /// `.foregroundStyle(...)` and literal `.opacity(...)` calls anywhere in a
    /// label.
    private func faintCalls(in range: Range<Int>) -> [Int] {
        var found: [Int] = []
        for name in ["foregroundStyle", "foregroundColor", "opacity"] {
            for at in occurrences(of: name, member: true) where range.contains(at) {
                guard at > 0, bytes[at - 1] == UInt8(ascii: ".") else { continue }
                // `.primary.opacity(0.25)` is a colour handed to something
                // (a stroke round a swatch), not the label's own opacity.
                if name == "opacity", at > 1, Self.isIdentifier(bytes[at - 2]) { continue }
                let open = at + name.utf8.count
                guard open < bytes.count, bytes[open] == UInt8(ascii: "("), let close = matching(open) else { continue }
                let arguments = string((open + 1)..<close)
                let faint = name == "opacity" ? Self.isFaintOpacity(arguments) : Self.isFaintStyle(arguments)
                if faint { found.append(at - 1) }
            }
        }
        return found
    }

    static func isFaintStyle(_ arguments: String) -> Bool {
        if arguments.range(of: #"\.(tertiary|quaternary)\b"#, options: .regularExpression) != nil { return true }
        guard let match = arguments.range(of: #"opacity\(\s*[0-9.]+\s*\)"#, options: .regularExpression) else { return false }
        let number = arguments[match].dropFirst("opacity(".count).dropLast().trimmingCharacters(in: .whitespaces)
        return Double(number).map { $0 < 0.5 } ?? false
    }

    static func isFaintOpacity(_ arguments: String) -> Bool {
        Double(arguments.trimmingCharacters(in: .whitespacesAndNewlines)).map { $0 < 0.5 } ?? false
    }

    // MARK: Saying why

    /// The marker with a reason after it, on the control or in the comment
    /// lines just above it.
    private func saysWhyItIsQuiet(_ range: Range<Int>) -> Bool {
        var text = string(range)
        var line = self.line(range.lowerBound) - 1
        while line >= 1, self.text(ofLine: line).hasPrefix("//") {
            text = self.text(ofLine: line) + "\n" + text
            line -= 1
        }
        let marker = "quiet on purpose:"
        var search = text.startIndex..<text.endIndex
        while let found = text.range(of: marker, range: search) {
            let rest = text[found.upperBound...].prefix { $0 != "\n" }
            if !rest.trimmingCharacters(in: .whitespaces).isEmpty { return true }
            search = found.upperBound..<text.endIndex
        }
        return false
    }

    // MARK: Low level

    private func hasWord(_ word: String, at index: Int) -> Bool {
        let w = Array(word.utf8)
        return index + w.count <= bytes.count && bytes[index..<(index + w.count)].elementsEqual(w)
    }

    private func skipSpaces(_ index: Int, newlines: Bool) -> Int {
        var i = index
        while i < bytes.count {
            let b = bytes[i]
            if b == UInt8(ascii: " ") || b == UInt8(ascii: "\t") || (newlines && (b == 10 || b == 13)) {
                i += 1
            } else {
                break
            }
        }
        return i
    }

    /// Past whitespace, newlines and comments.
    private func skipSpacesAndComments(_ index: Int) -> Int {
        var i = index
        while i < bytes.count {
            let b = bytes[i]
            if b == UInt8(ascii: " ") || b == UInt8(ascii: "\t") || b == 10 || b == 13 || !isCode[i] {
                i += 1
            } else {
                break
            }
        }
        return i
    }

    /// The bracket that closes the one at `open`, counting only code.
    private func matching(_ open: Int) -> Int? {
        let opener = bytes[open]
        let closer: UInt8 = opener == UInt8(ascii: "(") ? UInt8(ascii: ")")
            : opener == UInt8(ascii: "{") ? UInt8(ascii: "}") : UInt8(ascii: "]")
        var depth = 0
        var i = open
        while i < bytes.count {
            if isCode[i] {
                if bytes[i] == opener { depth += 1 }
                else if bytes[i] == closer {
                    depth -= 1
                    if depth == 0 { return i }
                }
            }
            i += 1
        }
        return nil
    }

    static func isIdentifier(_ b: UInt8) -> Bool {
        (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 95
    }

    /// Marks comments and string literals, with interpolations inside strings
    /// read as code.
    static func codeMask(_ bytes: [UInt8]) -> [Bool] {
        enum Mode { case code, line, block(Int), string(multiline: Bool) }
        var mask = [Bool](repeating: true, count: bytes.count)
        var mode = Mode.code
        // For each open interpolation: the string it returns to, and the
        // paren depth inside it.
        var interpolations: [(multiline: Bool, depth: Int)] = []
        var i = 0
        func at(_ k: Int) -> UInt8 { k < bytes.count ? bytes[k] : 0 }
        let quote = UInt8(ascii: "\""), slash = UInt8(ascii: "/"), star = UInt8(ascii: "*")
        while i < bytes.count {
            let b = bytes[i]
            switch mode {
            case .code:
                if b == slash, at(i + 1) == slash {
                    mode = .line; mask[i] = false
                } else if b == slash, at(i + 1) == star {
                    mode = .block(1); mask[i] = false; mask[i + 1] = false; i += 1
                } else if b == quote {
                    let multi = at(i + 1) == quote && at(i + 2) == quote
                    mode = .string(multiline: multi); mask[i] = false
                    if multi { mask[i + 1] = false; mask[i + 2] = false; i += 2 }
                } else if !interpolations.isEmpty {
                    if b == UInt8(ascii: "(") {
                        interpolations[interpolations.count - 1].depth += 1
                    } else if b == UInt8(ascii: ")") {
                        interpolations[interpolations.count - 1].depth -= 1
                        if interpolations[interpolations.count - 1].depth == 0 {
                            let back = interpolations.removeLast()
                            mode = .string(multiline: back.multiline)
                            mask[i] = false
                        }
                    }
                }
            case .line:
                if b == 10 { mode = .code } else { mask[i] = false }
            case .block(let depth):
                mask[i] = false
                if b == star, at(i + 1) == slash {
                    mask[i + 1] = false; i += 1
                    mode = depth == 1 ? .code : .block(depth - 1)
                } else if b == slash, at(i + 1) == star {
                    mask[i + 1] = false; i += 1
                    mode = .block(depth + 1)
                }
            case .string(let multiline):
                mask[i] = false
                if b == UInt8(ascii: "\\") {
                    if at(i + 1) == UInt8(ascii: "(") {
                        mask[i + 1] = false
                        interpolations.append((multiline, 1))
                        mode = .code
                    } else if i + 1 < bytes.count {
                        mask[i + 1] = false
                    }
                    i += 1
                } else if b == quote {
                    if multiline {
                        if at(i + 1) == quote && at(i + 2) == quote {
                            mask[i + 1] = false; mask[i + 2] = false; i += 2
                            mode = .code
                        }
                    } else {
                        mode = .code
                    }
                } else if b == 10, !multiline {
                    mode = .code
                }
            }
            i += 1
        }
        return mask
    }
}
