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
        var document = document
        document.syncComponentInstances()
        self.current = document
        self.limit = limit
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Applies a mutation as a single undoable step. No-op edits are not recorded.
    ///
    /// Every copy of a component is put back in step with its original inside
    /// the same step, so editing an original and every copy following it is one
    /// undo. It happens here rather than in each command so nothing can forget:
    /// the sync is a no-op for a document with no copies in it, and a no-op for
    /// an edit that did not touch a component, so an edit that changes nothing
    /// still records nothing.
    @discardableResult
    public mutating func perform(_ mutate: (inout PhotonzDocument) -> Void) -> ComponentSyncReport {
        var next = current
        mutate(&next)
        let report = next.syncComponentInstances()
        guard next != current else { return ComponentSyncReport() }
        undoStack.append(current)
        if undoStack.count > limit { undoStack.removeFirst() }
        redoStack.removeAll()
        current = next
        return report
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
