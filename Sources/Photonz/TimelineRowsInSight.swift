import AppKit
import PhotonzCore
import SwiftUI

/// How a tall edit's tracks are kept (`TimelineRowInSight`).
enum TimelineRowsInSight {
    /// Past this many rows a timeline is tall; a shorter one keeps them all
    /// awake, as it always has.
    static let tallEdit = 24
    /// The rows built with the timeline: the first two screens.
    static let builtAtFirst = 14
    /// How far past the part on screen a row is awake, as a share of it, and
    /// how far past it a row falls asleep.
    static let reach: CGFloat = 0.2
    static let leaves: CGFloat = 0.5
}

/// Which row of a tall edit a view is in, and whether it is far from the part
/// of the timeline on screen (`TimelineRowInSight`): what it shows then waits,
/// whatever changes, until it comes near again.
struct TimelineRowSleep: Equatable {
    let row: UUID
    let isAsleep: Bool
    let chores: TimelineRowChores

    static func == (a: Self, b: Self) -> Bool { a.row == b.row && a.isAsleep == b.isAsleep && a.chores === b.chores }
}

extension EnvironmentValues {
    /// Nothing for a row that never sleeps: a short edit's.
    @Entry var timelineRowSleep: TimelineRowSleep?
}

/// What a view last built, held by reference so keeping it wakes nothing.
/// What it holds can hold it (a view's closures hold its state), so its row
/// and its window let go of it when they go (`TimelineRowChores.letGo`).
@MainActor final class KeptBuild {
    fileprivate var view: Any?
    fileprivate var isAsleep = false
    /// Something it was made from has changed while it slept.
    fileprivate var isStale = false
    /// Asleep, and to be built again all the same (`TimelineRowChores`).
    fileprivate var catchesUp = false
    fileprivate let nudge = Nudge()

    @Observable @MainActor final class Nudge { var count = 0 }

    fileprivate func letGo() {
        view = nil
        isAsleep = false
        isStale = false
        catchesUp = false
    }
}

/// What `build` makes, kept while the row it is in is asleep: the first change
/// to anything it was made from marks it stale, and nothing after that wakes
/// it. Waking builds it again only if it is stale: the same views as before,
/// handed back, are nothing for SwiftUI to lay out or read out again, which is
/// most of what a row woken by a scroll cost (4 of its 5 ms, 2026-11-24). A
/// stale one is built again in its sleep once nothing is being done.
@MainActor
func keptAsleep<Content: View>(_ sleep: TimelineRowSleep?, _ kept: KeptBuild, _ build: () -> Content) -> Content {
    guard let sleep else { return build() }
    let asleep = sleep.isAsleep
    if asleep { _ = kept.nudge.count }
    if let view = kept.view as? Content, !kept.catchesUp {
        if asleep, kept.isAsleep {
            if !kept.isStale {
                kept.isStale = true
                sleep.chores.stale(kept, in: sleep.row)
            }
            return view
        }
        if asleep || (kept.isAsleep && !kept.isStale) {
            kept.isAsleep = asleep
            // Read again, so a change still reaches it.
            _ = build()
            return view
        }
    }
    let view = build()
    guard !sleep.chores.windowHasGone else { return view }
    if kept.view == nil { sleep.chores.keeps(kept, in: sleep.row) }
    kept.view = view
    kept.isAsleep = asleep
    kept.isStale = false
    kept.catchesUp = false
    return view
}

/// What a tall edit's far rows have waiting to be done to them, a few at a
/// time, while nothing is being done with the timeline: built, put to sleep,
/// or built again in their sleep after a change. Any of it costs a pass that
/// a scroll would be late for. One for each window.
@MainActor final class TimelineRowChores {
    private enum Kind { case sleep, wake, build }
    private struct Weak { weak var kept: KeptBuild? }
    private var waiting: [(row: UUID, kind: Kind, work: () -> Void)] = []
    private var staleOnes: [Weak] = []
    /// What each row's views keep, to let go of when the row goes.
    private var kept: [UUID: [Weak]] = [:]
    /// Rows come near in their sleep with nothing changed since, and what
    /// wakes each at once when something does.
    private var sleepingNear: [UUID: () -> Void] = [:]
    weak var editor: EditorState?
    fileprivate var windowHasGone = false
    private var task: Task<Void, Never>?
    /// When the rows last scrolled, or something in one last changed.
    private var lastMoved = Date.distantPast

    func build(_ row: UUID, _ work: @escaping () -> Void) { add(row, .build, work) }
    func sleep(_ row: UUID, _ work: @escaping () -> Void) { add(row, .sleep, work) }

    /// A sleeping row has come near the part on screen. What it shows is as it
    /// would be awake unless something has changed since it fell asleep, so
    /// unless something has it is woken once the scroll rests, or as soon as
    /// something does change: waking a row a scroll passes over is a frame
    /// the scroll is late for.
    func comesNear(_ row: UUID, _ wake: @escaping () -> Void) {
        drop(row)
        if (kept[row] ?? []).contains(where: { $0.kept?.isStale == true }) { return wake() }
        sleepingNear[row] = wake
        add(row, .wake) { [weak self] in
            self?.sleepingNear[row] = nil
            wake()
        }
    }

    fileprivate func keeps(_ build: KeptBuild, in row: UUID) {
        kept[row] = (kept[row] ?? []).filter { $0.kept != nil && $0.kept !== build } + [Weak(kept: build)]
    }

    /// A row has gone, or with none named the window has: nothing is kept for
    /// it, and nothing is waiting to be done to it.
    func letGo(_ row: UUID? = nil) {
        guard let row else {
            for one in kept.values.joined() { one.kept?.letGo() }
            windowHasGone = true
            kept = [:]
            sleepingNear = [:]
            waiting = []
            staleOnes = []
            return
        }
        drop(row)
        for one in kept.removeValue(forKey: row) ?? [] { one.kept?.letGo() }
    }

    fileprivate func stale(_ kept: KeptBuild, in row: UUID) {
        if let wake = sleepingNear[row] {
            drop(row)
            // Said while the row is being built, so woken after.
            DispatchQueue.main.async(execute: wake)
            return
        }
        staleOnes.append(Weak(kept: kept))
        moved()
        start()
    }

    private func add(_ row: UUID, _ kind: Kind, _ work: @escaping () -> Void) {
        waiting.removeAll { $0.row == row }
        waiting.append((row, kind, work))
        start()
    }

    private func start() {
        guard task == nil else { return }
        task = Task { @MainActor [weak self] in
            while let self, !self.waiting.isEmpty || !self.staleOnes.isEmpty {
                try? await Task.sleep(for: .milliseconds(16))
                guard let editor = self.editor else { break }
                if NSEvent.pressedMouseButtons != 0 || Date().timeIntervalSince(self.lastMoved) < 0.25 { continue }
                self.next(whilePlaying: editor.isDocumentPlaying)
            }
            self?.task = nil
        }
    }

    private func next(whilePlaying: Bool) {
        let sleepers = waiting.filter { $0.kind == .sleep }.prefix(6)
        if !sleepers.isEmpty {
            waiting.removeAll { one in sleepers.contains { $0.row == one.row } }
            for one in sleepers { one.work() }
            return
        }
        if let index = waiting.firstIndex(where: { $0.kind == .wake }) {
            waiting.remove(at: index).work()
            return
        }
        // Building waits for playback to stop.
        if whilePlaying { return }
        if let index = waiting.firstIndex(where: { $0.kind == .build }) {
            waiting.remove(at: index).work()
            return
        }
        // A row's few builds together: 36 far rows after a zoom are caught up
        // in half a second, so a scroll that follows finds them ready.
        for _ in 0..<4 where !staleOnes.isEmpty {
            guard let kept = staleOnes.removeFirst().kept, kept.isAsleep, kept.isStale else { continue }
            kept.catchesUp = true
            kept.nudge.count += 1
        }
    }

    func moved() { lastMoved = Date() }
    func drop(_ row: UUID) {
        waiting.removeAll { $0.row == row }
        sleepingNear[row] = nil
    }
}

/// One track's row in a tall edit: awake only while it is within reach of the
/// part of the tracks on screen, and asleep the rest of the time.
///
/// Fifty rows of which seven are seen were each built again by every edit and
/// laid out again on every frame of a zoom: 25 ms of an edit's longest pass,
/// and most of a zoom frame's 27 ms (2026-11-24). Taken down out of sight
/// instead, each row cost a scroll its whole building as it came in: a pass of
/// 14 to 17 ms for a few rows, whatever was done to spread it. Asleep it
/// keeps its views and reads nothing, and wakes with one build of a lane.
struct TimelineRowInSight<Content: View>: View {
    @Environment(EditorState.self) private var editorState
    let row: TimelineTrackRowModel
    let height: CGFloat
    let laneHeight: CGFloat
    /// False for a row that is always awake: a short edit's, or one with rows
    /// open under its lane.
    let gates: Bool
    @ViewBuilder let content: () -> Content

    private enum Place { case away, leaving, near }
    @State private var built: Bool
    @State private var awake: Bool
    /// Asleep and out of sight: left out of what the window asks every view
    /// in it about.
    @State private var isFar = false

    init(row: TimelineTrackRowModel, height: CGFloat, laneHeight: CGFloat, gates: Bool, startsNear: Bool,
         @ViewBuilder content: @escaping () -> Content) {
        self.row = row
        self.height = height
        self.laneHeight = laneHeight
        self.gates = gates
        self.content = content
        _built = State(initialValue: startsNear)
        _awake = State(initialValue: startsNear)
    }

    var body: some View {
        if gates {
            Group {
                if built { content() } else { away }
            }
            .accessibilityElement(children: isFar ? .ignore : .contain)
            .accessibilityHidden(isFar)
            .allowsHitTesting(!isFar)
            .environment(\.timelineRowSleep, TimelineRowSleep(row: row.id, isAsleep: !awake,
                                                              chores: editorState.timelineRowChores))
            .onDisappear { editorState.timelineRowChores.letGo(row.id) }
            .onGeometryChange(for: Place.self) { proxy in
                guard let shown = proxy.bounds(of: .scrollView) else { return .near }
                let past = max(shown.minY - proxy.size.height, -shown.maxY) / max(shown.height, 1)
                return past < TimelineRowsInSight.reach ? .near
                    : past < TimelineRowsInSight.leaves ? .leaving : .away
            } action: { place in
                moved(to: place)
            }
        } else {
            content()
        }
    }

    private func moved(to place: Place) {
        let chores = editorState.timelineRowChores
        chores.moved()
        switch place {
        case .near:
            if isFar { isFar = false }
            if !built {
                chores.drop(row.id)
                built = true
                awake = true
            } else if !awake {
                chores.comesNear(row.id) { awake = true }
            } else {
                chores.drop(row.id)
            }
        case .leaving:
            break
        case .away:
            if !built {
                chores.build(row.id) { built = true }
                return
            }
            guard awake else { return chores.drop(row.id) }
            chores.sleep(row.id) {
                // A row in a hand stays awake: its gesture reads what it shows.
                if editorState.rulerReadsTheHand || editorState.clipTransitionDrag != nil
                    || editorState.zoomDrag != nil || editorState.trackRowDrag.isCarrying { return }
                awake = false
                isFar = true
            }
        }
    }

    private var away: some View {
        Color.clear
            .frame(height: height)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(TimelineDock.tracksSpace)) } action: { frame in
                editorState.trackDropRows[row.id] = TrackDropRow(trackID: row.id, minY: frame.minY,
                                                                 maxY: frame.minY + laneHeight)
            }
    }
}

