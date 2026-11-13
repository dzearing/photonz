import Foundation
import Synchronization

// **Answers worked out once per document, not once per question**
// (`a-long-edit-with-transitions-plays-scrubs-and-ed`).
//
// Where each clip sits on the timeline's tracks, which clips meet at an edit
// point, and which of those edit points carry a transition are all read off the
// layers and the tracks, and they were read off again on every question. A
// playing clock asks them hundreds of times a tick: on the 6 minute reference
// edit, looking ahead for the frames to come laid every track out again for
// each of 35 transitions at each moment it looked at, and the main thread spent
// all of its time doing it (5 pictures shown out of 1857 in a minute of play,
// measured 2026-11-12 by `Scripts/perf/speed-walk.sh`).
//
// So the answers are kept beside the document they were read off, and thrown
// away the moment anything they were read off changes: every write to
// `layers`, `tracks` or the duration gives the document a fresh, empty store
// (the `didSet`s in `Document.swift`). A copy shares the store it was copied
// with until one of them is written to, which is exactly when their answers
// could start to differ. The store never takes part in equality, hashing or
// saving: two documents alike are alike whatever either has worked out.

/// The store a document keeps its worked-out answers in. Always equal to every
/// other, so a document's equality and hash are its content's alone.
struct DocumentDerived: Hashable, Sendable {

    /// One edit point carrying a transition: the clip arriving with it, the
    /// clip it meets, and the cut between them.
    struct EditPointTransition: Sendable {
        let incoming: UUID
        let outgoing: UUID
        let cut: ClipCut
    }

    struct Answers: Sendable {
        var trackLayout: PhotonzDocument.TrackLayout?
        /// Every layer on a track, a clip and everything inside it, to its
        /// track's id.
        var trackOfLayer: [UUID: UUID]?
        var editPoints: [UUID: [TimelineEditPoint]] = [:]
        var editPointTransitions: [EditPointTransition]?
    }

    final class Store: Sendable {
        let answers = Mutex(Answers())
    }

    private let store = Store()

    static func == (lhs: DocumentDerived, rhs: DocumentDerived) -> Bool { true }
    func hash(into hasher: inout Hasher) {}

    /// The answer kept at `path`, or `make()`'s, kept for next time. Worked
    /// out outside the lock: two threads asking at once each work it out and
    /// keep the same answer, which is cheaper than one waiting on the other.
    func answer<T: Sendable>(_ path: WritableKeyPath<Answers, T?>, _ make: () -> T) -> T {
        if let kept = store.answers.withLock({ $0[keyPath: path] }) { return kept }
        let made = make()
        store.answers.withLock { $0[keyPath: path] = made }
        return made
    }

    /// The edit points on one track, kept per track.
    func editPoints(onTrack id: UUID, _ make: () -> [TimelineEditPoint]) -> [TimelineEditPoint] {
        if let kept = store.answers.withLock({ $0.editPoints[id] }) { return kept }
        let made = make()
        store.answers.withLock { $0.editPoints[id] = made }
        return made
    }
}
