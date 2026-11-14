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
// `layers`, `tracks`, the duration, the canvas size or the pixel scale gives
// the document a fresh, empty store
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
        /// Where each layer is in the tree, one index per level, built once
        /// the document has been asked for layers by id a few times
        /// (`layerPath(of:)`).
        var layerPaths: [UUID: [Int]]?
        /// How many times this document has been asked for a layer by id
        /// without its index.
        var layerLookups = 0
        /// Every hold that pushed the picture alone, where it starts and how
        /// long it is, and the clip it is in (`holdDrifts(forLayer:)`).
        var pictureOnlyHolds: [PictureOnlyHold]?
        /// Everything that plays (`audioMix()`). Asked by the player on every
        /// tick and by the panel and the timeline after every edit, and it
        /// walks every layer and every cut: an edit while the 6 minute
        /// reference edit played worked it out about a dozen times
        /// (2026-11-14).
        var audioMix: [AudioMixSegment]?
    }

    struct PictureOnlyHold: Sendable {
        let layerID: UUID
        let atMS: Int
        let lengthMS: Int
    }

    final class Store: Sendable {
        let answers = Mutex(Answers())
    }

    private let store = Store()

    /// The sound plan kept, for tests: nil until the document is asked.
    var keptAudioMix: [AudioMixSegment]? { store.answers.withLock { $0.audioMix } }

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

    /// How many lookups by id a document answers by walking its tree before
    /// it builds the index: a document read once after each edit (most
    /// commands) never pays for one, and one read over and over (every bar
    /// and cut of a long timeline on every frame) pays once.
    static let lookupsBeforeIndex = 16

    /// Where the layer is, when the index is built: `.some(nil)` when the
    /// index says the layer is not in the tree, nil when there is no index
    /// yet. The index is built from `layers` the moment enough lookups have
    /// been counted.
    func layerPath(of id: UUID, in layers: [Layer]) -> [Int]?? {
        let index: [UUID: [Int]]? = store.answers.withLock { answers in
            if answers.layerPaths == nil {
                answers.layerLookups += 1
                guard answers.layerLookups > Self.lookupsBeforeIndex else { return nil }
            }
            return answers.layerPaths ?? [:]
        }
        guard var index else { return nil }
        if index.isEmpty, !layers.isEmpty {
            index = Self.paths(of: layers)
            let made = index
            store.answers.withLock { $0.layerPaths = made }
        }
        return .some(index[id])
    }

    static func paths(of layers: [Layer]) -> [UUID: [Int]] {
        var found: [UUID: [Int]] = [:]
        func walk(_ list: [Layer], _ prefix: [Int]) {
            for index in list.indices {
                let path = prefix + [index]
                found[list[index].id] = path
                if case .group(let group) = list[index].content { walk(group.children, path) }
            }
        }
        walk(layers, [])
        return found
    }

    /// The edit points on one track, kept per track.
    func editPoints(onTrack id: UUID, _ make: () -> [TimelineEditPoint]) -> [TimelineEditPoint] {
        if let kept = store.answers.withLock({ $0.editPoints[id] }) { return kept }
        let made = make()
        store.answers.withLock { $0.editPoints[id] = made }
        return made
    }
}
