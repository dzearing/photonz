// A track carried up or down the timeline by its header: lifted, riding the pointer, with the tracks around it opening the gap it will land in.

import AppKit
import Observation
import PhotonzCore
import SwiftUI

/// The timeline's own drag for a track, the same physical drag as the layers
/// list's (`LayerRowDragSession`): press a track's header and move, and the
/// whole track, header and lane, lifts off the timeline and follows the
/// pointer up and down; the tracks around it spring out of its way, so the gap
/// they open is where it will land (`TrackRowDrag` decides where that is). Let
/// go and it settles into the gap, in one step to undo; press Escape and it
/// goes back where it came from.
///
/// What is drawn is split as the layers list splits it: `liftedTop` changes
/// every frame and is read by the lifted track alone, `layout` changes only
/// when the gap moves and is read by the rows.
///
/// It lives on the editor, so a scripted walk drives the very same drag a
/// pointer does (`PlaytestHarness.carryTrack`).
@MainActor @Observable
final class TrackRowDragSession {

    /// Everything the rows need to be drawn during a drag, compared as a
    /// whole so an unchanged gap redraws nothing.
    struct Layout: Equatable {
        var offsets: [UUID: CGFloat] = [:]
        var gapTop: CGFloat = 0
        /// The gap is inside a group, so it is drawn in at a group's indent.
        var gapInGroup = false
    }

    enum Phase: Equatable {
        case carried
        case settling
    }

    /// The track in the air, nil when the timeline is holding nothing.
    private(set) var grabbedID: UUID?
    private(set) var phase: Phase = .carried
    private(set) var layout = Layout()
    /// Where the lifted track's top edge is drawn, in the tracks' points.
    private(set) var liftedTop: CGFloat = 0
    /// How high the lifted track stands off the timeline, 0 to 1.
    private(set) var lift: CGFloat = 0
    /// The carried track's height, which is the gap's.
    private(set) var gapHeight: CGFloat = 0
    /// Whether the carried track sat in a group when it was picked up.
    private(set) var grabbedInGroup = false
    /// How far sideways the lifted track slides as it settles, into or out
    /// of a group's indent. Zero while it is carried.
    private(set) var settleShift: CGFloat = 0

    /// How far in a group draws its tracks (`TimelineTrackRow.indent`).
    static let groupIndent: CGFloat = 10

    /// Every row's frame in the tracks' own points, as laid out: what a drag
    /// is measured against when it begins. Written by the rows.
    @ObservationIgnored var rowFrames: [UUID: CGRect] = [:]
    /// A press on a track that cannot be carried (a locked one), until it is
    /// let go, so every move of it does not ask again.
    @ObservationIgnored private(set) var refused = false

    @ObservationIgnored private(set) var drag: TrackRowDrag?
    @ObservationIgnored private weak var editor: EditorState?
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    static let spring = LayerRowDragSession.spring
    /// How close to the top or bottom of the tracks' view the pointer has to
    /// be before they scroll, and how fast they go right at the edge.
    static let edgeBand: CGFloat = 20
    static let edgeSpeed: CGFloat = 420

    var isCarrying: Bool { grabbedID != nil }

    // MARK: - Picking up

    /// Lifts the track `id` with the pointer at `pointerY` in the tracks'
    /// points. False when it cannot be carried anywhere: it is locked, it is
    /// the only row, or the rows have not been measured.
    @discardableResult
    func pickUp(_ id: UUID, pointerY: CGFloat, editor: EditorState) -> Bool {
        guard grabbedID == nil else { return false }
        guard let document = editor.document, document.canMoveTrack(id),
              let drag = TrackRowDrag(grabbing: id, rows: rows(of: editor), spacing: TimelineDock.rowSpacing,
                                      pointerY: pointerY) else {
            refused = true
            return false
        }
        self.editor = editor
        self.drag = drag
        phase = .carried
        grabbedID = id
        gapHeight = drag.gapHeight
        grabbedInGroup = drag.grabbed.group != nil
        liftedTop = drag.liftedTop
        layout = Self.layout(of: drag)
        withAnimation(Self.spring) { lift = 1 }
        watchForEscape()
        startTicker()
        return true
    }

    /// The rows the timeline is showing, top down, where they were measured.
    /// Empty when any of them has not been.
    private func rows(of editor: EditorState) -> [TrackRowDrag.Row] {
        var rows: [TrackRowDrag.Row] = []
        for row in editor.timelineRows {
            guard let frame = rowFrames[row.id] else { return [] }
            let kind: TrackRowDrag.Row.Kind
            switch row {
            case .group(_, let isCollapsed, _): kind = .heading(isOpen: !isCollapsed)
            case .track(let track, let inGroup): kind = .track(group: inGroup ? track.track.groupID : nil)
            }
            rows.append(TrackRowDrag.Row(id: row.id, top: frame.minY, height: frame.height, kind: kind))
        }
        return rows
    }

    // MARK: - Carrying

    /// The pointer moved, to `pointerY` in the tracks' points.
    func move(pointerY: CGFloat) {
        guard phase == .carried, var drag else { return }
        drag.move(pointerY: pointerY)
        self.drag = drag
        publish(drag)
    }

    private func publish(_ drag: TrackRowDrag) {
        if liftedTop != drag.liftedTop { liftedTop = drag.liftedTop }
        let next = Self.layout(of: drag)
        if next != layout { withAnimation(Self.spring) { layout = next } }
    }

    private static func layout(of drag: TrackRowDrag) -> Layout {
        var offsets: [UUID: CGFloat] = [:]
        for row in drag.rest {
            let offset = drag.offset(of: row.id)
            if offset != 0 { offsets[row.id] = offset }
        }
        return Layout(offsets: offsets, gapTop: drag.gapTop, gapInGroup: drag.gapGroup != nil)
    }

    // MARK: - Letting go

    /// Let go: the track settles into the gap, and then the document changes,
    /// in one undo step. A press that never lifted anything just ends.
    func letGo() {
        refused = false
        guard phase == .carried, let drag else { return }
        phase = .settling
        stopWatching()
        let into = (drag.gapGroup != nil ? 1 : 0) - (grabbedInGroup ? 1 : 0)
        withAnimation(Self.spring) {
            liftedTop = drag.gapTop
            lift = 0
            settleShift = CGFloat(into) * Self.groupIndent
        } completion: { [weak self] in
            self?.finish(landing: self?.drag?.landing)
        }
    }

    /// Escape: the track goes back where it came from and nothing changes.
    func cancel() {
        guard phase == .carried, var drag else { return }
        phase = .settling
        stopWatching()
        drag.returnHome()
        self.drag = drag
        withAnimation(Self.spring) {
            layout = Self.layout(of: drag)
            liftedTop = drag.gapTop
            lift = 0
        } completion: { [weak self] in
            self?.finish(landing: nil)
        }
    }

    /// Puts the timeline back to plain rows and, when there is somewhere to
    /// land, makes the one edit. Without animation: the rows are already drawn
    /// where the edit puts them.
    private func finish(landing: TrackLanding?) {
        let id = grabbedID
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            if let editor, let id, let landing { editor.moveTrack(id, landing) }
            clear()
        }
    }

    private func clear() {
        stopWatching()
        drag = nil
        grabbedID = nil
        layout = Layout()
        lift = 0
        settleShift = 0
        gapHeight = 0
        grabbedInGroup = false
        phase = .carried
    }

    // MARK: - Escape and the edges

    private func watchForEscape() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { self?.cancel() }
            return nil
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { @MainActor [weak self] in
            var last = CACurrentMediaTime()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard let self, self.phase == .carried, self.drag != nil else { return }
                let now = CACurrentMediaTime()
                self.autoscroll(dt: min(now - last, 0.05))
                last = now
            }
        }
    }

    private func stopWatching() {
        ticker?.cancel()
        ticker = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Held near the top or bottom of the tracks' view, the tracks scroll on
    /// their own, faster the closer the pointer is to the edge, and the gap
    /// keeps following the pointer as the rows pass under it.
    private func autoscroll(dt: CFTimeInterval) {
        guard let editor, let drag else { return }
        let geometry = editor.timelineTracksScrollGeometry
        guard geometry.overflows, geometry.viewportHeight > Self.edgeBand * 2 else { return }
        let viewportY = drag.pointerY - geometry.offsetY
        let into: CGFloat
        if viewportY < Self.edgeBand {
            into = -(Self.edgeBand - viewportY) / Self.edgeBand
        } else if viewportY > geometry.viewportHeight - Self.edgeBand {
            into = (viewportY - (geometry.viewportHeight - Self.edgeBand)) / Self.edgeBand
        } else {
            return
        }
        let clamped = min(max(into, -1), 1)
        let furthest = max(0, geometry.contentHeight - geometry.viewportHeight)
        let next = min(max(geometry.offsetY + Self.edgeSpeed * clamped * abs(clamped) * CGFloat(dt), 0), furthest)
        guard abs(next - geometry.offsetY) > 0.1 else { return }
        editor.timelineTracksScroll.scrollTo(y: next)
        // The pointer has not moved on the screen, so it has moved through the
        // tracks by as much as they scrolled.
        move(pointerY: drag.pointerY + (next - geometry.offsetY))
    }
}

// MARK: - What it looks like

/// Where a row of the timeline is drawn while a track is carried: moved out
/// of the way once the gap has passed it, and not drawn at all when it is the
/// track in the air. A view of its own, so what it reads of the drag is ITS
/// dependency and not the whole timeline's.
struct TrackRowDragPlacement: ViewModifier {
    let id: UUID
    let session: TrackRowDragSession

    func body(content: Content) -> some View {
        Placed(id: id, session: session, content: content)
    }

    private struct Placed: View {
        let id: UUID
        let session: TrackRowDragSession
        let content: Content

        var body: some View {
            content
                .offset(y: session.layout.offsets[id] ?? 0)
                .opacity(session.grabbedID == id ? 0 : 1)
        }
    }
}

/// The place the carried track will land: a soft recess as tall as the track,
/// across the header and the lane, drawn in at a group's indent when it would
/// join one.
struct TrackDragGap: View {
    let session: TrackRowDragSession

    var body: some View {
        if session.isCarrying {
            let layout = session.layout
            RoundedRectangle(cornerRadius: 6)
                .fill(VideoKit.Palette.ink.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(VideoKit.Palette.ink.opacity(0.12), lineWidth: 1)
                }
                .frame(height: session.gapHeight)
                .padding(.leading, layout.gapInGroup ? TrackRowDragSession.groupIndent : 0)
                .offset(y: layout.gapTop)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// The carried track itself, the real track rather than a picture of it, on
/// a plate of its own with a shadow under it. It goes up and down with the
/// pointer and nowhere else, and slides into or out of a group's indent only
/// as it settles.
struct LiftedTrackRow<Row: View>: View {
    let session: TrackRowDragSession
    let row: Row

    var body: some View {
        let lift = session.lift
        row
            .background {
                // A shadow alone barely reads on the dark timeline, so the
                // plate also carries an edge.
                RoundedRectangle(cornerRadius: 6)
                    .fill(VideoKit.Palette.raised)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(VideoKit.Palette.lineStrong.opacity(lift), lineWidth: 1)
                    }
                    .padding(.leading, session.grabbedInGroup ? TrackRowDragSession.groupIndent : 0)
                    .shadow(color: .black.opacity(0.35 * lift), radius: 10 * lift, y: 4 * lift)
            }
            .scaleEffect(1 + 0.012 * lift, anchor: .leading)
            .offset(x: session.settleShift, y: session.liftedTop)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
