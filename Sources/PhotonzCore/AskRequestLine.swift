import Foundation

// A request sent while Ask is still working waits its turn (the user,
// 2026-10-20: "It should queue and let me cancel in the agent ux if it hasn't
// started"). Each window keeps its own line; it runs first in, first out, and
// a request taken out before it starts never runs at all.

/// The requests waiting for Ask in one window, oldest first.
public struct AskRequestLine: Hashable, Sendable {

    public struct Request: Identifiable, Hashable, Sendable {
        public let id: UUID
        /// What was asked, in the person's words.
        public let words: String
    }

    /// Waiting, in the order they will run.
    public private(set) var waiting: [Request] = []

    public init() {}

    public var isEmpty: Bool { waiting.isEmpty }

    /// Newest first, the way the Agent group lists its rows.
    public var shown: [Request] { waiting.reversed() }

    /// Puts a request at the back of the line. Nil for blank words.
    @discardableResult
    public mutating func add(_ words: String) -> Request? {
        let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let request = Request(id: UUID(), words: trimmed)
        waiting.append(request)
        return request
    }

    /// Takes a waiting request out, so it never runs. False when it was not
    /// waiting (already started, or already taken out).
    @discardableResult
    public mutating func cancel(_ id: UUID) -> Bool {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return false }
        waiting.remove(at: index)
        return true
    }

    /// The request whose turn it is, out of the line.
    public mutating func next() -> Request? {
        waiting.isEmpty ? nil : waiting.removeFirst()
    }

    public mutating func clear() {
        waiting.removeAll()
    }
}
