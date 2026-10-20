import Foundation

// Ask makes the change straight away (the user, 2026-10-20: "I don't need to
// see all the actions taken, i just need a row that explains the change and a
// way to toggle it or delete it"). Each request is recorded as the document
// before and after it. Turning the row off takes that difference out of the
// document as it is NOW, and turning it on puts it back, by a three-way merge
// over the document's saved form: what the request changed is undone or
// redone, and everything changed since, anywhere else, stays. When something
// later changed the very thing the request made, the merge refuses rather
// than guess, and the row says so.

/// One request's change: the document just before it ran and just after.
public struct AskRecordedChange: Hashable, Sendable {
    public let before: PhotonzDocument
    public let after: PhotonzDocument

    public init(before: PhotonzDocument, after: PhotonzDocument) {
        self.before = before
        self.after = after
    }

    public enum Outcome: Hashable, Sendable {
        /// The document with the change taken out (or put back).
        case changed(PhotonzDocument)
        /// Nothing to do: the document already reads that way.
        case unchanged
        /// Something done since changed what this change made.
        case blocked
    }

    /// `current` as if this change had never been made.
    public func takenOut(of current: PhotonzDocument) -> Outcome {
        DocumentMerge.apply(from: after, to: before, onto: current)
    }

    /// What a row's click picks on the canvas: the layers the change added,
    /// outermost only, or when it added none, the innermost it edited. Only
    /// those still in `current`.
    public func madeLayerIDs(in current: PhotonzDocument) -> [UUID] {
        let was = Set(before.allLayerIDs)
        let present = Set(current.allLayerIDs)
        let added = after.allLayerIDs.filter { !was.contains($0) && present.contains($0) }
        let addedSet = Set(added)
        let outermost = added.filter { id in after.parentID(of: id).map { !addedSet.contains($0) } ?? true }
        if !outermost.isEmpty { return outermost }
        let edited = after.allLayerIDs.filter { present.contains($0) && before.layer(id: $0) != after.layer(id: $0) }
        let editedSet = Set(edited)
        return edited.filter { id in !editedSet.contains { after.parentID(of: $0) == id } }
    }

    /// `current` with this change made again.
    public func putBack(into current: PhotonzDocument) -> Outcome {
        DocumentMerge.apply(from: before, to: after, onto: current)
    }
}

/// A three-way merge over the document's saved form: the difference from
/// `from` to `to`, applied onto `onto`. Lists of things with ids (layers,
/// children, styles, tracks, clips) merge thing by thing, keeping the order
/// either side gave them; anything both sides changed differently refuses.
enum DocumentMerge {

    struct Conflict: Error {}

    static func apply(from base: PhotonzDocument, to theirs: PhotonzDocument,
                      onto mine: PhotonzDocument) -> AskRecordedChange.Outcome {
        guard let b = tree(base), let t = tree(theirs), let m = tree(mine) else { return .blocked }
        let merged: Any?
        do { merged = try merge(base: b, mine: m, theirs: t) } catch { return .blocked }
        guard let merged else { return .blocked }
        if same(merged, m) { return .unchanged }
        guard JSONSerialization.isValidJSONObject(merged),
              let data = try? JSONSerialization.data(withJSONObject: merged),
              let document = try? JSONDecoder().decode(PhotonzDocument.self, from: data) else { return .blocked }
        return document == mine ? .unchanged : .changed(document)
    }

    /// The document as JSON objects. JSONSerialization keeps every number
    /// exactly as it was written, so a value nobody touched goes back as it came.
    static func tree(_ document: PhotonzDocument) -> Any? {
        guard let data = try? JSONEncoder().encode(document) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case (let a?, let b?): (a as AnyObject).isEqual(b as AnyObject)
        default: false
        }
    }

    static func merge(base: Any?, mine: Any?, theirs: Any?) throws -> Any? {
        if same(base, theirs) { return mine }
        if same(base, mine) { return theirs }
        if same(mine, theirs) { return mine }
        if let b = base as? [String: Any], let m = mine as? [String: Any], let t = theirs as? [String: Any] {
            var out: [String: Any] = [:]
            for key in Set(b.keys).union(m.keys).union(t.keys) {
                if let value = try merge(base: b[key], mine: m[key], theirs: t[key]) { out[key] = value }
            }
            return out
        }
        if let b = base as? [Any], let m = mine as? [Any], let t = theirs as? [Any],
           let bi = identified(b), let mi = identified(m), let ti = identified(t) {
            return try mergeLists(base: bi, mine: mi, theirs: ti)
        }
        throw Conflict()
    }

    /// A list whose entries are objects with distinct string ids, as (id, entry).
    static func identified(_ list: [Any]) -> [(String, Any)]? {
        var seen = Set<String>()
        var out: [(String, Any)] = []
        for entry in list {
            guard let id = (entry as? [String: Any])?["id"] as? String, seen.insert(id).inserted else { return nil }
            out.append((id, entry))
        }
        return out
    }

    static func mergeLists(base: [(String, Any)], mine: [(String, Any)],
                           theirs: [(String, Any)]) throws -> [Any] {
        let b = Dictionary(base, uniquingKeysWith: { a, _ in a })
        let m = Dictionary(mine, uniquingKeysWith: { a, _ in a })
        let t = Dictionary(theirs, uniquingKeysWith: { a, _ in a })
        var merged: [String: Any] = [:]
        for id in Set(b.keys).union(m.keys).union(t.keys) {
            if let entry = try merge(base: b[id], mine: m[id], theirs: t[id]) { merged[id] = entry }
        }
        // The order is the document as it is now. A reorder the change made
        // is carried over only where nothing since reordered the same things.
        let shared = Set(b.keys).intersection(m.keys).intersection(t.keys)
        func relative(_ list: [(String, Any)]) -> [String] { list.map(\.0).filter(shared.contains) }
        var order = mine.map(\.0).filter { merged[$0] != nil }
        if relative(theirs) != relative(base) {
            guard relative(mine) == relative(base) || relative(mine) == relative(theirs) else { throw Conflict() }
            var reordered = relative(theirs).makeIterator()
            order = order.map { shared.contains($0) ? (reordered.next() ?? $0) : $0 }
        }
        // What only the change holds goes in after the entry it followed there.
        for (index, (id, _)) in theirs.enumerated() where merged[id] != nil && !order.contains(id) {
            let before = theirs[..<index].reversed().first { order.contains($0.0) }?.0
            let at = before.flatMap { order.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            order.insert(id, at: at)
        }
        return order.compactMap { merged[$0] }
    }
}

/// Ask's rows in one window, newest first: one per request, each on or off.
/// Rows last for the session, beside the undo history they lean on; they hold
/// whole document snapshots, which have no business in the saved file.
public struct AskChangeList: Hashable, Sendable {

    public struct Row: Identifiable, Hashable, Sendable {
        public let id: UUID
        /// What was asked, in the person's words.
        public let asked: String
        /// What changed, in a few plain words.
        public let sentence: String
        public let change: AskRecordedChange
        public internal(set) var isOn = true
        /// Deleted. Kept out of sight so an undo of the delete brings it back.
        public internal(set) var isDeleted = false
        /// Why the last switch did nothing, when it could not.
        public internal(set) var note: String?
    }

    public static let laterChangeNote = "A later change builds on this."

    public private(set) var rows: [Row] = []

    public init() {}

    public var shown: [Row] { rows.filter { !$0.isDeleted } }

    public func row(_ id: UUID) -> Row? { rows.first { $0.id == id } }

    /// Records a request that ran. A request that changed nothing leaves no row.
    @discardableResult
    public mutating func record(asked: String, sentence: String, before: PhotonzDocument,
                                after: PhotonzDocument) -> UUID? {
        guard before != after else { return nil }
        let row = Row(id: UUID(), asked: asked, sentence: sentence,
                      change: AskRecordedChange(before: before, after: after))
        rows.insert(row, at: 0)
        return row.id
    }

    /// Turns a row's change on or off in `document`. On `.changed`, the caller
    /// lands the document it hands back as one undo step.
    public mutating func setOn(_ on: Bool, id: UUID, in document: PhotonzDocument) -> AskRecordedChange.Outcome {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return .unchanged }
        let change = rows[index].change
        let outcome = on ? change.putBack(into: document) : change.takenOut(of: document)
        if outcome == .blocked {
            rows[index].note = Self.laterChangeNote
        } else {
            rows[index].isOn = on
            rows[index].note = nil
        }
        return outcome
    }

    /// Deletes a row for good: its change comes out first if it is on.
    public mutating func delete(id: UUID, in document: PhotonzDocument) -> AskRecordedChange.Outcome {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return .unchanged }
        var outcome = AskRecordedChange.Outcome.unchanged
        if rows[index].isOn {
            outcome = rows[index].change.takenOut(of: document)
            if outcome == .blocked {
                rows[index].note = Self.laterChangeNote
                return .blocked
            }
        }
        rows[index].isOn = false
        rows[index].isDeleted = true
        rows[index].note = nil
        return outcome
    }

    /// Reads each row's state off `document` after an undo or a redo stepped
    /// it: a row is on while there is something of its change to take out. A
    /// deleted row whose change is back (its delete undone) comes back too.
    public mutating func follow(_ document: PhotonzDocument) {
        for index in rows.indices {
            switch rows[index].change.takenOut(of: document) {
            case .changed:
                rows[index].isOn = true
                rows[index].isDeleted = false
            case .unchanged:
                rows[index].isOn = false
            case .blocked:
                break
            }
            rows[index].note = nil
        }
    }
}

/// The row's words: what a request changed, from the steps that landed.
public enum AskChangeWords {

    public static let budget = 40
    public static let fallback = "Made a change"

    private struct Kind {
        let verb: String
        let one: String
        let many: String
    }

    private static func kind(_ tool: String) -> Kind? {
        switch tool {
        case "add_measurement": Kind(verb: "Added", one: "a measurement", many: "measurements")
        case "add_shape", "add_path": Kind(verb: "Drew", one: "a shape", many: "shapes")
        case "add_text": Kind(verb: "Added", one: "text", many: "texts")
        case "add_title": Kind(verb: "Added", one: "a title", many: "titles")
        case "place_component": Kind(verb: "Placed", one: "a component", many: "components")
        case "set_layer": Kind(verb: "Changed", one: "a layer", many: "layers")
        case "add_style": Kind(verb: "Saved", one: "a style", many: "styles")
        case "apply_style": Kind(verb: "Restyled", one: "a layer", many: "layers")
        case "set_layout": Kind(verb: "Laid out", one: "a group", many: "groups")
        case "run_command": Kind(verb: "Ran", one: "a command", many: "commands")
        case "cut": Kind(verb: "Made", one: "a cut", many: "cuts")
        case "trim": Kind(verb: "Trimmed", one: "a clip", many: "clips")
        case "move_clip": Kind(verb: "Moved", one: "a clip", many: "clips")
        case "set_transition": Kind(verb: "Added", one: "a transition", many: "transitions")
        case "apply_zooms": Kind(verb: "Added", one: "zooms", many: "zooms")
        default: nil
        }
    }

    /// "Added 8 measurements", "Drew 3 shapes", "Added the title “Case 1”".
    public static func sentence(_ steps: [AskStep]) -> String {
        // Grouped by what each step's words say, most first, ties in the order asked.
        var groups: [(key: String, kind: Kind, steps: [AskStep])] = []
        for step in steps {
            guard let kind = kind(step.tool) else { continue }
            let key = "\(kind.verb) \(kind.many)"
            if let index = groups.firstIndex(where: { $0.key == key }) {
                groups[index].steps.append(step)
            } else {
                groups.append((key, kind, [step]))
            }
        }
        guard !groups.isEmpty else { return fallback }
        let ordered = groups.enumerated().sorted { a, b in
            (a.element.steps.count, -a.offset) > (b.element.steps.count, -b.offset)
        }.map(\.element)

        func phrase(_ group: (key: String, kind: Kind, steps: [AskStep]), room: Int) -> String {
            let count = group.steps.count
            if count > 1 { return "\(count) \(group.kind.many)" }
            if group.kind.one == "a title" || group.kind.one == "text",
               let words = group.steps[0].arguments["text"]?.stringValue?
                   .replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces),
               !words.isEmpty {
                let lead = group.kind.one == "a title" ? "the title " : "the text "
                let space = room - lead.count - 2
                guard space >= 4 else { return group.kind.one }
                let cut = words.count > space ? String(words.prefix(space - 1)) + "\u{2026}" : words
                return "\(lead)\u{201C}\(cut)\u{201D}"
            }
            return group.kind.one
        }
        func clause(_ index: Int, room: Int) -> String {
            let group = ordered[index]
            // A second clause with the same verb leaves the verb out.
            let sameVerb = index > 0 && ordered[index - 1].kind.verb == group.kind.verb
            let verb = index == 0 ? group.kind.verb : group.kind.verb.lowercased()
            let lead = sameVerb ? "" : verb + " "
            return lead + phrase(group, room: room - lead.count)
        }

        let first = clause(0, room: budget)
        var sentence = first
        switch ordered.count {
        case 1:
            break
        case 2:
            let two = first + " and " + clause(1, room: budget - first.count - 5)
            sentence = two.count <= budget ? two : first + " and 1 more"
        default:
            let more = " and \(ordered.count - 2) more"
            let two = first + ", " + clause(1, room: budget - first.count - 2 - more.count) + more
            sentence = two.count <= budget ? two : first + " and \(ordered.count - 1) more"
        }
        return sentence.count <= budget ? sentence : String(sentence.prefix(budget - 1)) + "\u{2026}"
    }
}
