import CoreGraphics
import Foundation

/// Snapshot-based undo/redo. Documents are small value types (pixel data lives
/// in the ImageStore), so whole-document snapshots are cheap and bulletproof.
public struct History: Sendable {
    public private(set) var current: PhotonzDocument
    private var undoStack: [PhotonzDocument] = []
    private var redoStack: [PhotonzDocument] = []
    private let limit: Int

    public init(document: PhotonzDocument, limit: Int = 200) {
        self.current = document
        self.limit = limit
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Applies a mutation as a single undoable step. No-op edits are not recorded.
    public mutating func perform(_ mutate: (inout PhotonzDocument) -> Void) {
        var next = current
        mutate(&next)
        guard next != current else { return }
        undoStack.append(current)
        if undoStack.count > limit { undoStack.removeFirst() }
        redoStack.removeAll()
        current = next
    }

    public mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(current)
        current = previous
    }

    public mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(current)
        current = next
    }
}
