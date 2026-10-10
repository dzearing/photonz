import Foundation

// Curves kept under a name (task `every-transition-can-be-picked-from-presets-and`).
//
// A curve somebody drew for one zoom is a curve they want on the next dissolve
// and the next title too, so it is kept with the app rather than with one
// document, the way Premiere keeps a saved preset and the way ⌘T's default
// transition is kept (`DefaultTransitionStore`). Every Curve row in the app
// lists them under Saved, after the shared eight, whatever it is the curve of.

/// One curve kept under a name.
public struct SavedCurve: Hashable, Codable, Sendable {
    public var name: String
    public var curve: EasingCurve

    public init(name: String, curve: EasingCurve) {
        self.name = name
        self.curve = curve
    }
}

/// The curves kept under a name, in the order they were first kept.
public struct SavedCurves: Hashable, Codable, Sendable {
    public private(set) var items: [SavedCurve]

    public init(items: [SavedCurve] = []) {
        self.items = items
    }

    /// The most a list keeps: past this a menu stops being a list you read.
    public static let most = 24

    /// Keep `curve` as `name`, spaces trimmed. A name already kept (in any
    /// case) takes the newer curve and the newer spelling where it stood.
    /// Answers the name kept, or nil for a name with nothing in it.
    @discardableResult
    public mutating func save(_ curve: EasingCurve, as name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let kept = SavedCurve(name: trimmed, curve: curve)
        if let index = index(named: trimmed) {
            items[index] = kept
        } else {
            items.append(kept)
            if items.count > Self.most { items.removeFirst(items.count - Self.most) }
        }
        return trimmed
    }

    /// Forget the curve kept as `name`, in any case.
    public mutating func remove(named name: String) {
        guard let index = index(named: name) else { return }
        items.remove(at: index)
    }

    /// The name `curve` is kept under, if it is.
    public func name(of curve: EasingCurve) -> String? {
        items.first { $0.curve == curve }?.name
    }

    private func index(named name: String) -> Int? {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.firstIndex { $0.name.lowercased() == wanted }
    }
}
