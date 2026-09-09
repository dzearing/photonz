import CoreGraphics
import Foundation

/// Snapshot-based undo/redo. Documents are small value types (pixel data lives
/// in the ImageStore), so whole-document snapshots are cheap and bulletproof.
public struct History: Sendable {
    public private(set) var current: PhotonzDocument
    /// The marquee that belongs with `current`. A selection is editor state
    /// and is never saved, but it is something a person places by hand, so it
    /// rides in this stack alongside the picture: one ⌘Z always steps back
    /// over whatever you did last, paint or outline (`SelectionSnapshot`).
    public private(set) var selection = SelectionSnapshot()

    /// One point the stack can return to: the picture and the marquee that
    /// was over it, put back together.
    private struct Step: Sendable {
        var document: PhotonzDocument
        var selection: SelectionSnapshot
    }

    private var undoStack: [Step] = []
    private var redoStack: [Step] = []
    private let limit: Int
    /// The name of the run of selection changes the last step belongs to, so a
    /// burst of arrow-key nudges collapses into one step. Anything else landing
    /// in the stack ends the run.
    private var runName: String?

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
        // ...and text that was set some other way lets go of the name it
        // claimed, for exactly the same reason and at the same moment.
        next.reconcileTextStyles()
        // ...and an effect that was tuned some other way lets go of its name
        // too, for the same reason and at the same moment.
        next.reconcileEffectStyles()
        // Every stack and grid puts its contents back in order inside the same
        // step, BEFORE the copies are refilled, so a copy of a component is
        // rebuilt from an original that has already settled. It happens here
        // rather than in each command so nothing can forget: paste a layer into
        // a stack, delete one, drag one past another, and the flow runs without
        // the command knowing stacks exist. A document with none in it is
        // untouched.
        next.reflowLayouts()
        let sync = next.syncComponentInstances()
        // ...and once more afterwards, but only when a copy actually changed,
        // because refilling a copy is the moment its own answers land: a copy
        // told to say something longer has a label that just grew, and the
        // stack around it has to close up in this same step.
        if sync.updatedInstances > 0 { next.reflowLayouts() }
        guard next != current else { return EditReport() }
        let breaks = LinkBreakReport.between(current, next)
        push(Step(document: current, selection: selection))
        redoStack.removeAll()
        current = next
        return EditReport(componentSync: sync, linkBreaks: breaks)
    }

    /// The marquee moved without that being a step of its own — the canvas was
    /// resized out from under it, a tool that has no use for it put it down,
    /// or an edit consumed it. The stack simply follows along, so the NEXT
    /// step records the outline that is really on screen.
    public mutating func syncSelection(_ next: SelectionSnapshot) {
        selection = next
    }

    /// Records the marquee's move from `previous` to where it is now as one
    /// undoable step. Call it after the change has landed (`syncSelection`
    /// having carried it here), which is how the same didSet can serve both.
    ///
    /// `run` names a burst that should undo as a single act: five taps of the
    /// arrow key put the outline five points along, and one ⌘Z brings it all
    /// the way back, the way letting go of a drag records once. Consecutive
    /// changes sharing a run join the step already on the stack; a different
    /// run, no run at all, an edit to the picture, or an undo all end it.
    ///
    /// Returns whether anything was recorded.
    @discardableResult
    public mutating func recordSelectionChange(from previous: SelectionSnapshot,
                                               run: String? = nil) -> Bool {
        guard previous != selection else { return false }
        redoStack.removeAll()
        // The step already on the stack holds where the run began, which is
        // where undo has to land, so there is nothing to add.
        if let run, run == runName, !undoStack.isEmpty { return true }
        push(Step(document: current, selection: previous))
        runName = run
        return true
    }

    public mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(Step(document: current, selection: selection))
        current = previous.document
        selection = previous.selection
        runName = nil
    }

    public mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(Step(document: current, selection: selection))
        current = next.document
        selection = next.selection
        runName = nil
    }

    private mutating func push(_ step: Step) {
        undoStack.append(step)
        if undoStack.count > limit { undoStack.removeFirst() }
        runName = nil
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
