import Foundation

// Ask makes the change straight away, and each request is one row of history
// (the user, 2026-11-04: "I think it should just be history rather than having
// toggles and trashcans"). Undo is how a request is taken back. Each request is
// recorded as the document before and after it, which is what the row's card
// pictures and what lets the row read, after an undo or a redo, whether its
// change is still in the document: a three-way merge over the document's saved
// form takes the difference out of the document as it is NOW, and if that finds
// something to take out, the change is there.

/// One request's change: the document just before it ran and just after.
public struct AskRecordedChange: Hashable, Sendable {
    public let before: PhotonzDocument
    public let after: PhotonzDocument

    public init(before: PhotonzDocument, after: PhotonzDocument) {
        self.before = before
        self.after = after
    }

    public enum Outcome: Hashable, Sendable {
        /// The document with the change taken out.
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

/// Ask's history in one window, newest first: one row per request. Rows last
/// for the session, beside the undo history they lean on; they hold whole
/// document snapshots, which have no business in the saved file.
public struct AskChangeList: Hashable, Sendable {

    public struct Row: Identifiable, Hashable, Sendable {
        public let id: UUID
        /// What was asked, in the person's words.
        public let asked: String
        /// What changed, in a few plain words.
        public let sentence: String
        /// What the request did not make, in one short line (`AskPlanRun`).
        public let leftOut: String?
        public let change: AskRecordedChange
        /// How Ask understood the request, in a few plain lines
        /// (`AskUnderstanding`), for the row's card.
        public let understood: [String]
        /// Whether the change is in the document: false once it was undone.
        public internal(set) var isOn = true
        /// Where each drawing the request made came from, in step order.
        public internal(set) var sources: [AskDrawingSource] = []
        /// The person's thumbs on it, if any.
        public internal(set) var verdict: AskVerdict?
    }

    public private(set) var rows: [Row] = []

    public init() {}

    public func row(_ id: UUID) -> Row? { rows.first { $0.id == id } }

    /// Records a request that ran. A request that changed nothing leaves no row.
    @discardableResult
    public mutating func record(asked: String, sentence: String, before: PhotonzDocument,
                                after: PhotonzDocument, sources: [AskDrawingSource] = [],
                                leftOut: String? = nil, understood: [String] = []) -> UUID? {
        guard before != after else { return nil }
        let row = Row(id: UUID(), asked: asked, sentence: sentence, leftOut: leftOut,
                      change: AskRecordedChange(before: before, after: after), understood: understood,
                      sources: sources)
        rows.insert(row, at: 0)
        return row.id
    }

    /// Clear History: the list goes. Nothing on the canvas changes, and undo
    /// still steps through everything the requests did.
    public mutating func clear() {
        rows = []
    }

    /// Puts the person's thumbs on a row: the same thumbs again takes it
    /// back, the other one swaps. What the row holds afterwards.
    @discardableResult
    public mutating func vote(_ verdict: AskVerdict, id: UUID) -> AskVerdict? {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return nil }
        rows[index].verdict = rows[index].verdict == verdict ? nil : verdict
        return rows[index].verdict
    }

    /// Reads each row's state off `document` after an undo or a redo stepped
    /// it: a row is on while there is something of its change to take out.
    /// Something built on it since can't be read either way, and the row
    /// stays as it was.
    public mutating func follow(_ document: PhotonzDocument) {
        for index in rows.indices {
            switch rows[index].change.takenOut(of: document) {
            case .changed: rows[index].isOn = true
            case .unchanged: rows[index].isOn = false
            case .blocked: break
            }
        }
    }
}
