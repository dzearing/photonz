import Foundation

/// What Ask remembers of the talk in one window: the latest requests that
/// still stand (their rows on), what each did in the person's words, and what
/// it made, by id, name, kind and parts, read from the document as it is now.
/// Handed to the model with every request, so "it", "the water", "bluer" and
/// "again but smaller" resolve to what was just made (the user, 2026-10-31:
/// "is there any way for it to understand its previous steps"). It lives as
/// long as the window's Ask rows: a row deleted or turned off is forgotten.
public enum AskMemory {

    /// The most requests remembered: enough for a few rounds of "now make
    /// it...", few enough to leave the model's window for the work.
    public static let mostTurns = 6
    /// The most parts listed for one thing made.
    public static let mostParts = 24

    public struct Made: Hashable, Sendable {
        public var id: String
        public var name: String
        public var kind: String
        public var parts: [String]

        public init(id: String, name: String, kind: String, parts: [String]) {
            self.id = id
            self.name = name
            self.kind = kind
            self.parts = parts
        }
    }

    public struct Turn: Hashable, Sendable {
        public var asked: String
        public var did: String
        public var made: [Made]

        public init(asked: String, did: String, made: [Made]) {
            self.asked = asked
            self.did = did
            self.made = made
        }
    }

    /// The turns `rows` remember, oldest first, the latest `mostTurns` that
    /// are still on, each with what it made as `document` has it now.
    public static func turns(from rows: AskChangeList, in document: PhotonzDocument) -> [Turn] {
        let standing = rows.shown.filter(\.isOn).prefix(mostTurns)
        return standing.reversed().map { row in
            let made = row.change.madeLayerIDs(in: document).compactMap { id -> Made? in
                guard let layer = document.layer(id: id) else { return nil }
                return Made(id: id.uuidString, name: layer.name, kind: AgentDocumentRead.kind(of: layer),
                            parts: parts(of: layer))
            }
            return Turn(asked: row.asked, did: row.sentence, made: made)
        }
    }

    /// A painting's parts by the names its strokes carry; a group's by its
    /// children's names, one level down.
    static func parts(of layer: Layer) -> [String] {
        var parts: [String] = []
        if let paint = layer.paint {
            for stroke in paint.strokes {
                if let part = stroke.part, !parts.contains(part) { parts.append(part) }
            }
        } else if let children = layer.group?.children {
            for child in children.reversed() where !parts.contains(child.name) { parts.append(child.name) }
        }
        return Array(parts.prefix(mostParts))
    }

    /// The memory as the model reads it, after the document; empty with
    /// nothing to remember.
    public static func prompt(_ turns: [Turn]) -> String {
        guard !turns.isEmpty else { return "" }
        var lines = ["Earlier in this conversation, oldest first (the person's words, then what you did):"]
        for (index, turn) in turns.enumerated() {
            var line = "\(index + 1). Asked \u{201C}\(turn.asked)\u{201D}: \(turn.did)."
            for made in turn.made {
                line += " Made layer \(made.id), \(made.name) (\(made.kind))"
                if !made.parts.isEmpty { line += ", parts: \(made.parts.joined(separator: ", "))" }
                line += "."
            }
            lines.append(line)
        }
        lines.append("""
        When the request is about something made earlier ("it", "the water", "bluer", "bigger", "less", \
        "again but smaller"), change that thing where it is: change_part with the part's name and its \
        layer for a part of a painting or a drawing, set_layer for a whole layer. Never make it again \
        or paint over it, and leave every other part as it is.
        """)
        return lines.joined(separator: "\n")
    }
}
