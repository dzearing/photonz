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
    ///
    /// The links that broke on the way are worked out here for the same reason
    /// (`LinkBreakReport`): a break is a fact about the difference between two
    /// versions of the document, so every command gets it right without knowing
    /// it exists.
    @discardableResult
    public mutating func perform(_ mutate: (inout PhotonzDocument) -> Void) -> EditReport {
        var next = current
        mutate(&next)
        // A color that was repainted some other way lets go of the style it
        // claimed, BEFORE the copies are refilled, so a copy is never rebuilt
        // from an original whose claim has already gone stale.
        next.reconcileColorStyles()
        // Every stack and grid puts its contents back in order inside the same
        // step, BEFORE the copies are refilled, so a copy of a component is
        // rebuilt from an original that has already settled. It happens here
        // rather than in each command so nothing can forget: paste a layer into
        // a stack, delete one, drag one past another, and the flow runs without
        // the command knowing stacks exist. A document with none in it is
        // untouched.
        next.reflowLayouts()
        let sync = next.syncComponentInstances()
        guard next != current else { return EditReport() }
        let breaks = LinkBreakReport.between(current, next)
        undoStack.append(current)
        if undoStack.count > limit { undoStack.removeFirst() }
        redoStack.removeAll()
        current = next
        return EditReport(componentSync: sync, linkBreaks: breaks)
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

/// What one undoable edit did that something on screen needs to say out loud:
/// how far it reached into the copies of a component, and what stopped
/// following what it came from.
public struct EditReport: Hashable, Sendable {
    public var componentSync: ComponentSyncReport
    public var linkBreaks: LinkBreakReport

    public init(componentSync: ComponentSyncReport = ComponentSyncReport(),
                linkBreaks: LinkBreakReport = LinkBreakReport()) {
        self.componentSync = componentSync
        self.linkBreaks = linkBreaks
    }
}
