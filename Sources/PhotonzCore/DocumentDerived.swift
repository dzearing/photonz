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
// `layers`, `tracks`, the component library, the duration, the canvas size or
// the pixel scale gives the document a fresh, empty store
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
        /// The transition as the cut can draw it, and the stretch of the
        /// document it runs over, or nil where the cut draws none.
        let drawn: ClipTransition?
        let spanMS: Range<Int>

        init(incoming: UUID, outgoing: UUID, cut: ClipCut) {
            self.incoming = incoming
            self.outgoing = outgoing
            self.cut = cut
            drawn = cut.drawnTransition
            spanMS = drawn.map {
                let start = cut.atMS - $0.beforeMS
                return start..<max(start, cut.atMS + $0.holdMS + $0.afterMS)
            } ?? 0..<0
        }
    }

    struct Answers: Sendable {
        var trackLayout: PhotonzDocument.TrackLayout?
        /// Every layer on a track, a clip and everything inside it, to its
        /// track's id.
        var trackOfLayer: [UUID: UUID]?
        var editPoints: [UUID: [TimelineEditPoint]] = [:]
        /// The empty stretches on each track, kept per track: every lane of
        /// the timeline asks for its own on every frame of a zoom.
        var gaps: [UUID: [TimelineGap]] = [:]
        /// Where a closed clip's parts have timing of their own, kept per
        /// clip: every lane asks it of every clip in sight on every frame.
        var childMarks: [UUID: [LayerTime]] = [:]
        var editPointTransitions: [EditPointTransition]?
        /// Where each layer is in the tree, one index per level, built once
        /// the document has been asked for layers by id a few times
        /// (`layerPath(of:)`).
        var layerPaths: [UUID: [Int]]?
        /// Where each top level layer is, for what reads every clip on the
        /// timeline after an edit (`topLevelIndex`).
        var topLevelIndex: [UUID: Int]?
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
        /// Whether anything anywhere in the tree fades, zooms or shows its
        /// clicks (`TreeFacts`).
        var treeFacts: TreeFacts?
        /// Which layers drawing a moment has to work out, as far as no moment
        /// is needed to say (`layersWorkedOut(atTimeMS:)`).
        var workPlan: [WorkedOut]?
        /// The timeline's bars (`motionStrip()`).
        var motionStrip: [MotionStripGroup]?
        /// Which layers play a recording and when (`moviePlan`).
        var moviePlan: MoviePlan?
        /// Every main in the document, the library's first
        /// (`PhotonzDocument.mainComponents`). Putting the copies in step
        /// after an edit asks for it several times a copy, and each answer
        /// was a walk of the whole tree: on a sheet of eleven components
        /// that Ask landed, about a third of a 533 ms hold (2026-11-18).
        var mainComponents: [Layer]?
    }

    /// What the whole tree holds that drawing a moment has to do something
    /// about. Asked on every tick of a playing video and in every edit's
    /// pass, each was a copy of every layer in the document and a walk of it
    /// (`allLayers`): on the 6 minute reference edit about 6 ms of the main
    /// thread a second of play (2026-11-14), growing with the edit.
    struct TreeFacts: Sendable, Equatable {
        var pictureFades = false
        var zooms = false
        var clickEffects = false
        /// A chart with a later set of numbers.
        var chartSets = false
        /// A clip carrying a transition on the cut it arrives at.
        var arrivals = false
        /// A layer put under a mask.
        var mattes = false
        /// A motion blur that smears.
        var motionBlur = false
        var captions = false
        /// A measurement, or the two that measure a size.
        var measures = false
        /// A component's original, or a copy of one, in the picture.
        var mains = false
        var instances = false
        /// A caliper or guide itself.
        var calipers = false
        var groups = false
        var frames = false
    }

    /// Whether drawing a moment works a layer out: always, or only inside a
    /// stretch of the document.
    enum WorkedOut: Sendable, Equatable {
        case always
        case from(Int, to: Int)
    }

    /// Which top level layers play a recording, and when: what a moment's
    /// frames are read off without going through every layer (`moviePlan`).
    struct MoviePlan: Sendable {
        struct Span: Sendable {
            let index: Int
            let inMS: Int
            let outMS: Int
        }
        /// The layers that play something, or hold something that does, in
        /// order, and the stretch each can need a frame in.
        var plays: [Span] = []
        /// The clips that may fill the frame, in order.
        var covers: [Span] = []
        /// The layers holding clips merged into one.
        var merged: [Int] = []
        /// The layers a switched off track takes off screen.
        var off: Set<Int> = []
        /// Every layer, and the partner of every transition, to the top level
        /// layer it is in.
        var topLayer: [UUID: Int] = [:]
    }

    struct PictureOnlyHold: Sendable {
        let layerID: UUID
        let atMS: Int
        let lengthMS: Int
        /// The captions heard off the held clip, which moved with it.
        var carries: Set<UUID> = []
    }

    final class Store: Sendable {
        let answers = Mutex(Answers())
    }

    private let store = Store()

    /// The sound plan kept, for tests: nil until the document is asked.
    var keptAudioMix: [AudioMixSegment]? { store.answers.withLock { $0.audioMix } }
    /// The tree's facts kept, for tests: nil until the document is asked.
    var keptTreeFacts: TreeFacts? { store.answers.withLock { $0.treeFacts } }
    /// Whether the index of where each layer sits has been built, for tests.
    var hasLayerIndex: Bool { store.answers.withLock { $0.layerPaths != nil } }
    /// The mains kept, for tests: nil until the document is asked.
    var keptMainComponents: [Layer]? { store.answers.withLock { $0.mainComponents } }

    /// Whether two documents carry the very same store: one is a copy of
    /// the other and neither has had what the answers are read off written
    /// since.
    func isSameStore(as other: DocumentDerived) -> Bool { store === other.store }

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

    /// The tracks whose gaps are kept, for tests.
    var keptGapTracks: Set<UUID> { store.answers.withLock { Set($0.gaps.keys) } }

    /// The gaps on one track, kept per track.
    func gaps(onTrack id: UUID, _ make: () -> [TimelineGap]) -> [TimelineGap] {
        if let kept = store.answers.withLock({ $0.gaps[id] }) { return kept }
        let made = make()
        store.answers.withLock { $0.gaps[id] = made }
        return made
    }

    /// How many clips' part marks are kept, for tests.
    var keptChildMarkCount: Int { store.answers.withLock { $0.childMarks.count } }

    /// A clip's part marks, kept per clip.
    func childMarks(of id: UUID, _ make: () -> [LayerTime]) -> [LayerTime] {
        if let kept = store.answers.withLock({ $0.childMarks[id] }) { return kept }
        let made = make()
        store.answers.withLock { $0.childMarks[id] = made }
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

extension PhotonzDocument {
    /// Whether `other` is this document, or a copy of it, with nothing any
    /// kept answer is read off written since: its layers, tracks, component
    /// library, duration, canvas size and pixel scale all as they were. A check of one pointer,
    /// so the app can keep answers of its own beside a document (the
    /// timeline's painted bars) and know on every frame whether they still
    /// hold. False for a document of equal content read afresh.
    public func sharesWorkedOutAnswers(with other: PhotonzDocument) -> Bool {
        derived.isSameStore(as: other.derived)
    }

    /// What the tree holds that drawing a moment has to act on, worked out in
    /// one walk that copies nothing and kept until a layer changes
    /// (`DocumentDerived.TreeFacts`).
    var treeFacts: DocumentDerived.TreeFacts {
        derived.answer(\.treeFacts) {
            var facts = DocumentDerived.TreeFacts()
            forEachLayer { layer in
                if layer.pictureFade != nil { facts.pictureFades = true }
                if layer.zooms?.isEmpty == false { facts.zooms = true }
                if layer.clickEffect?.isOn == true { facts.clickEffects = true }
                if layer.style.motionBlur?.smears == true { facts.motionBlur = true }
                if layer.isCaption { facts.captions = true }
                if layer.measure != nil { facts.calipers = true }
                if layer.measure != nil || layer.isSizeMeasurement { facts.measures = true }
                guard case .group(let group) = layer.content else { return }
                facts.groups = true
                if layer.isFrame { facts.frames = true }
                if group.titleRecipe?.chart?.steps != nil { facts.chartSets = true }
                if group.componentID != nil { facts.mains = true }
                if group.instanceOf != nil { facts.instances = true }
            }
            for index in layers.indices {
                if layers[index].arrivalTransition != nil { facts.arrivals = true }
                if layers[index].style.matte != nil { facts.mattes = true }
            }
            return facts
        }
    }

    /// Works out and keeps what the player and the timeline ask of a document
    /// in the passes after an edit: the sound plan and the bars. Run off the
    /// main thread while the edit's own frame is drawn; asked for before it
    /// is ready, each is simply worked out where it is asked for.
    public func workOutWhatAnEditAsksNext() {
        _ = audioMix()
        _ = motionStrip()
        _ = pictureOnlyHolds
        for track in timelineTracks { _ = editPoints(onTrack: track.id) }
    }

    /// What the panel's sections ask of the whole tree
    /// (`PanelSectionVisibility.Situation`): a caliper or guide, a component's
    /// original or copy, a group, a frame.
    public var panelFacts: (measurement: Bool, component: Bool, container: Bool, frame: Bool) {
        let facts = treeFacts
        return (facts.calipers, facts.mains || facts.instances, facts.groups, facts.frames)
    }

    /// Where each top level layer is in `layers`: a clip read in place by its
    /// index costs nothing, and read by its id costs a copy of everything it
    /// holds, which after every edit of an hour long timeline was hundreds of
    /// them (2026-11-25).
    var topLevelIndex: [UUID: Int] {
        derived.answer(\.topLevelIndex) {
            var found: [UUID: Int] = [:]
            found.reserveCapacity(layers.count)
            for index in layers.indices where found[layers[index].id] == nil { found[layers[index].id] = index }
            return found
        }
    }
}
