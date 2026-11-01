import Foundation

/// About how many tokens a piece of a request costs the model, without its
/// tokenizer: Ask budgets every request before it is sent, so a document too
/// big to describe never reaches the model as an error (the user,
/// 2026-10-31: a change to a traced Statue of Liberty of 216 parts failed
/// with "request (41070 tokens) exceeds the available context size").
///
/// Calibrated on Qwen3.8 27B's own tokenizer, 2026-10-31 (`docs/design/ask.md`,
/// "Fitting the window"): a run of letters is about a token, a digit is one,
/// other marks are about two fifths of one, and the sum is taken 15 per cent
/// high so the estimate errs over. On the traced Statue's read_document
/// (23,423 tokens) it reads 6 per cent over; on the tools (10,837) 15 per
/// cent over; on the instructions (1,484) 2 per cent over.
public enum AskTokens {

    public static func estimate(_ text: String) -> Int {
        var count = 0.0
        var inWord = false
        for scalar in text.unicodeScalars {
            let value = scalar.value
            let letter = (65...90).contains(value) || (97...122).contains(value)
            if letter {
                if !inWord { count += 1 }
                inWord = true
                continue
            }
            inWord = false
            if (48...57).contains(value) {
                count += 1
            } else if value == 32 || value == 10 || value == 9 || value == 13 {
                continue
            } else if value < 128 {
                count += 0.4
            } else {
                // Any other letter or mark: a token or more each.
                count += 1
            }
        }
        return Int((count * 1.15).rounded(.up))
    }

    /// A picture handed to a model that sees: a token for every 32 by 32
    /// pixels (Qwen3's 16 pixel patches, merged two by two: a 1024 by 728
    /// canvas picture measured 738 tokens), read from a PNG's own header,
    /// and a few for its markers. A picture whose size cannot be read counts as a
    /// 1024 point square.
    public static func estimate(picture png: Data) -> Int {
        let bytes = [UInt8](png.prefix(24))
        var width = 1024, height = 1024
        if bytes.count == 24, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47 {
            width = bytes[16..<20].reduce(0) { $0 << 8 | Int($1) }
            height = bytes[20..<24].reduce(0) { $0 << 8 | Int($1) }
        }
        return (width * height + 1023) / 1024 + 16
    }

    /// A message of the chat as sent: its words, its pictures, its calls.
    public static func estimate(message: AgentJSON) -> Int {
        var tokens = 8 + estimate(message["content"]?.stringValue ?? "")
        for image in message["images"]?.arrayValue ?? [] {
            let png = image.stringValue.flatMap { Data(base64Encoded: String($0.prefix(64))) } ?? Data()
            tokens += estimate(picture: png)
        }
        if let calls = message["tool_calls"] { tokens += estimate(calls.encodedString()) }
        return tokens
    }
}

/// The document as Ask hands it to its model, sized to fit. A document that
/// already fits goes over exactly as read_document read it. A bigger one has
/// its biggest groups (a traced drawing of hundreds of paths) said in short,
/// one entry each: name, box, how many layers it holds, its parts' names
/// with how many share each, and its colours. The model opens one with
/// read_document of that layer, or changes a part by its name or a point
/// inside it (change_part), so nothing it needs is out of reach.
public enum AskDocumentDigest {

    /// The most the document may take of the first request, in tokens: the
    /// tools and instructions take about 12,500 and a canvas picture about
    /// 1,000, so a document this size keeps the first request under half of
    /// the smallest window.
    public static let documentTokens = 2_500
    /// The most one read_document answer may take while planning.
    public static let lookTokens = 4_000
    /// The most part names said for one layer in short.
    public static let mostNames = 24
    /// The most colours said for one layer in short.
    public static let mostColors = 8

    /// `text` as read_document wrote it, fitted to `tokens`. With `opening`,
    /// it is the read of one layer the model asked to see: that layer's own
    /// parts are listed, as many as fit, the rest counted.
    public static func fitted(_ text: String, tokens budget: Int = documentTokens, opening: Bool = false) -> String {
        guard AskTokens.estimate(text) > budget,
              var read = try? JSONDecoder().decode(AgentDocumentRead.self, from: Data(text.utf8)) else { return text }
        func cost(_ read: AgentDocumentRead) -> Int {
            (try? read.encoded()).map { AskTokens.estimate(String(decoding: $0, as: UTF8.self)) } ?? Int.max
        }
        // The biggest groups first: a parent always holds more than any
        // group inside it, so it is said in short before its own groups are.
        let keep: [Int]? = opening && read.layers.count == 1 ? [0] : nil
        let groups = Self.groups(in: read.layers).filter { $0.path != keep }.sorted { $0.size > $1.size }
        for group in groups {
            if cost(read) <= budget { break }
            Self.update(&read.layers, at: group.path) { layer in
                guard layer.children != nil else { return }
                layer.parts = Self.parts(of: layer)
                layer.children = nil
            }
        }
        if cost(read) > budget { trim(&read, to: budget, opening: keep != nil) }
        return (try? read.encoded()).map { String(decoding: $0, as: UTF8.self) } ?? text
    }

    /// Whether a fitted read says any layer in short.
    public static func saysInShort(_ text: String) -> Bool { text.contains("\"parts\":{") }

    /// Each layer a fitted read says in short, by id, with its parts' names
    /// as they are named (without how many share them).
    public static func namesInShort(_ text: String) -> [String: [String]] {
        guard saysInShort(text), let read = try? JSONDecoder().decode(AgentDocumentRead.self, from: Data(text.utf8))
        else { return [:] }
        var found: [String: [String]] = [:]
        func walk(_ layer: AgentDocumentRead.Layer) {
            if let parts = layer.parts {
                found[layer.id] = parts.names.map { name in
                    guard name.hasSuffix(")"), let open = name.range(of: " (", options: .backwards) else { return name }
                    return String(name[..<open.lowerBound])
                }
            }
            layer.children?.forEach(walk)
        }
        read.layers.forEach(walk)
        return found
    }

    /// Lists layers from the top until the budget, counting the rest: the
    /// document's own, or the opened layer's parts.
    private static func trim(_ read: inout AgentDocumentRead, to budget: Int, opening: Bool) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        func cost(_ layer: AgentDocumentRead.Layer) -> Int {
            (try? encoder.encode(layer)).map { AskTokens.estimate(String(decoding: $0, as: UTF8.self)) + 1 } ?? Int.max
        }
        if opening, var root = read.layers.first, let children = root.children {
            var parts = root.parts ?? Self.parts(of: root)
            root.children = []
            root.parts = parts
            read.layers = [root]
            var spent = (try? read.encoded()).map { AskTokens.estimate(String(decoding: $0, as: UTF8.self)) } ?? 0
            var listed: [AgentDocumentRead.Layer] = []
            for child in children {
                let more = cost(child)
                if spent + more + 8 > budget { break }
                spent += more
                listed.append(child)
            }
            parts.listed = listed.count
            root.parts = parts
            root.children = listed
            read.layers = [root]
            return
        }
        let layers = read.layers
        read.layers = []
        read.layersNotListed = (read.layersNotListed ?? 0) + layers.count
        var spent = (try? read.encoded()).map { AskTokens.estimate(String(decoding: $0, as: UTF8.self)) } ?? 0
        var listed: [AgentDocumentRead.Layer] = []
        for layer in layers {
            let more = cost(layer)
            if spent + more > budget { break }
            spent += more
            listed.append(layer)
        }
        read.layers = listed
        let notListed = (read.layersNotListed ?? 0) - listed.count
        read.layersNotListed = notListed > 0 ? notListed : nil
    }

    /// Every layer that holds others, with where it is and how many it holds.
    private static func groups(in layers: [AgentDocumentRead.Layer], at path: [Int] = []) -> [(path: [Int], size: Int)] {
        var found: [(path: [Int], size: Int)] = []
        for (index, layer) in layers.enumerated() {
            guard let children = layer.children, !children.isEmpty else { continue }
            found.append((path + [index], descendants(of: layer)))
            found += groups(in: children, at: path + [index])
        }
        return found
    }

    private static func descendants(of layer: AgentDocumentRead.Layer) -> Int {
        (layer.children ?? []).reduce(0) { $0 + 1 + descendants(of: $1) }
    }

    private static func update(_ layers: inout [AgentDocumentRead.Layer], at path: [Int],
                               _ change: (inout AgentDocumentRead.Layer) -> Void) {
        guard let first = path.first, layers.indices.contains(first) else { return }
        if path.count == 1 {
            change(&layers[first])
            return
        }
        guard var children = layers[first].children else { return }
        update(&children, at: Array(path.dropFirst()), change)
        layers[first].children = children
    }

    /// A layer said in short: its parts' names, alike names ("Teal 3", "Teal
    /// 4") once with how many, most shared first, and its colours.
    static func parts(of layer: AgentDocumentRead.Layer) -> AgentDocumentRead.Parts {
        let children = layer.children ?? []
        var order: [String] = []
        var counts: [String: Int] = [:]
        for child in children {
            let name = baseName(child.name)
            if counts[name] == nil { order.append(name) }
            counts[name, default: 0] += 1
        }
        let names = order.enumerated()
            .sorted { (counts[$0.element] ?? 0, -$0.offset) > (counts[$1.element] ?? 0, -$1.offset) }
            .map(\.element)
            .prefix(mostNames)
            .map { name in (counts[name] ?? 0) > 1 ? "\(name) (\(counts[name] ?? 0))" : name }
        var colorOrder: [String] = []
        var colorCounts: [String: Int] = [:]
        func walk(_ layer: AgentDocumentRead.Layer) {
            let ink = layer.path.map { $0.fill ?? $0.stroke } ?? layer.shape.map { $0.fill ?? $0.stroke } ?? layer.text?.color
            if let ink {
                let hex = ink.uppercased()
                if colorCounts[hex] == nil { colorOrder.append(hex) }
                colorCounts[hex, default: 0] += 1
            }
            layer.children?.forEach(walk)
        }
        children.forEach(walk)
        let colors = colorOrder.enumerated()
            .sorted { (colorCounts[$0.element] ?? 0, -$0.offset) > (colorCounts[$1.element] ?? 0, -$1.offset) }
            .map(\.element)
            .prefix(mostColors)
        return AgentDocumentRead.Parts(count: descendants(of: layer), names: Array(names),
                                       colors: colors.isEmpty ? nil : Array(colors))
    }

    /// A name without the number a copy or a traced piece is given: "Teal
    /// 12" is "Teal", "Cloud 2" is "Cloud".
    static func baseName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let space = trimmed.lastIndex(of: " ") else { return trimmed }
        let tail = trimmed[trimmed.index(after: space)...]
        guard !tail.isEmpty, tail.allSatisfy(\.isNumber) else { return trimmed }
        return String(trimmed[..<space]).trimmingCharacters(in: .whitespaces)
    }
}

/// What the person reads when the model or its server fails: one short plain
/// sentence saying what happened and what to try, never the server's own
/// words (no token counts, no JSON, no model names).
public enum AskTrouble {

    public static let tooMuchSentence = "That was too much for Ask to read at once. Try asking about one part."
    public static let noModelSentence = "Ask couldn't find its model. Check Settings."
    public static let failedSentence = "Ask's model couldn't answer that. Try again."

    public static func sentence(forServerError words: String) -> String {
        let said = words.lowercased()
        if said.contains("context") || said.contains("too long") || said.contains("exceeds") || said.contains("too many tokens") {
            return tooMuchSentence
        }
        if said.contains("model"), said.contains("not found") { return noModelSentence }
        return failedSentence
    }
}
