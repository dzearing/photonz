// A row of the layers list carried by the pointer: lifted, riding it up and down, with the rows around it opening the gap it will land in.

import AppKit
import Observation
import PhotonzCore
import SwiftUI

/// The layers list's own drag, with no drag image and no drop line: the row
/// you grab lifts off the list and follows the pointer up and down, and the
/// rows around it spring out of its way, so the gap they open is where it will
/// land (`LayerRowDrag` decides where that is). Let go and it settles into the
/// gap; press Escape and it goes back where it came from.
///
/// What is drawn is split into what changes every frame and what changes only
/// when the gap moves, so a frame of a drag redraws the lifted row and nothing
/// else: `liftedTop` is read by the lifted row alone, `layout` by the rows,
/// and the rows only move when the pointer crosses the middle of one.
///
/// It lives on the editor, not in the list, so a scripted walk drives the very
/// same drag a pointer does (`PlaytestHarness.dragRow`).
@MainActor @Observable
final class LayerRowDragSession {

    /// Everything the rows need to be drawn during a drag, compared as a
    /// whole so an unchanged gap redraws nothing.
    struct Layout: Equatable {
        var offsets: [UUID: CGFloat] = [:]
        var travelling: Set<UUID> = []
        var trailingOffset: CGFloat = 0
        var gapTop: CGFloat = 0
        var gapDepth: Int = 0
    }

    enum Phase: Equatable {
        /// In the hand, following the pointer.
        case carried
        /// Let go: settling into the gap, or going back home after Escape.
        case settling
    }

    /// The row in the air, nil when the list is holding nothing. Changes at
    /// the start and end of a drag only.
    private(set) var grabbedID: UUID?
    private(set) var phase: Phase = .carried
    /// Where the rows are drawn. Changes when the gap moves.
    private(set) var layout = Layout()
    /// Where the lifted row's top edge is drawn, in the list's points. Changes
    /// every frame.
    private(set) var liftedTop: CGFloat = 0
    /// How high the lifted row stands off the list, 0 to 1: its shadow and
    /// scale. Goes to 0 as it settles.
    private(set) var lift: CGFloat = 0
    /// One row's height in the list, so the gap can be drawn that tall.
    private(set) var rowHeight: CGFloat = 0
    /// How far sideways the lifted row slides as it settles, so it lands at
    /// the indent of the list it is joining. Zero while it is carried: in the
    /// hand it only goes up and down.
    private(set) var settleShift: CGFloat = 0
    /// How many layers the lifted row stands for: more than one when the row
    /// grabbed was part of a selection, and the rest ride along under it.
    private(set) var carriedCount = 0

    /// How far in each level of a group draws its rows (`LayersRow.indent`).
    static let indentPerLevel: CGFloat = 14

    /// The model under all of it.
    @ObservationIgnored private(set) var drag: LayerRowDrag?
    @ObservationIgnored private weak var editor: EditorState?
    /// The group that was open when it was picked up, shut for the drag and
    /// opened again after it.
    @ObservationIgnored private var reopenAfter: UUID?
    /// The Escape key, while a row is in the air.
    @ObservationIgnored private var keyMonitor: Any?
    /// The beat that scrolls the list near its edges and springs a shut group
    /// open under a resting pointer.
    @ObservationIgnored private var ticker: Task<Void, Never>?
    /// The pointer, in the scrolling area's own points (top of what is showing
    /// is zero), which is what the edges are measured from.
    @ObservationIgnored private var viewportY: CGFloat = 0
    /// The shut group the pointer is resting on, and since when.
    @ObservationIgnored private var springing: (id: UUID, since: CFTimeInterval, at: CGFloat)?

    /// The list's scrolling, handed over by the list so the drag can scroll it
    /// near its edges.
    struct Scroller {
        var offset: () -> CGFloat
        var viewport: () -> CGFloat
        var contentHeight: () -> CGFloat
        /// One row's height as the list measured it, for a walk that carries
        /// a row the way a hand does.
        var rowHeight: () -> CGFloat
        var scrollTo: (CGFloat) -> Void
    }
    @ObservationIgnored var scroller: Scroller?

    /// How close to the top or bottom edge of the list the pointer has to be
    /// before the list scrolls, and how fast it goes right at the edge.
    static let edgeBand: CGFloat = 28
    static let edgeSpeed: CGFloat = 520
    /// How long a pointer rests on a shut group before it springs open.
    static let springDelay: CFTimeInterval = 0.7
    /// The one motion the rows, the gap and the settling row share.
    static let spring = Animation.spring(response: 0.28, dampingFraction: 0.82)

    var isCarrying: Bool { grabbedID != nil }

    // MARK: - Picking up

    /// Lifts `id` with the pointer at `pointerY` in the list's points.
    /// `viewportY` is the same pointer in the scrolling area's points. Returns
    /// false when this row cannot be carried anywhere.
    @discardableResult
    func pickUp(_ id: UUID, pointerY: CGFloat, viewportY: CGFloat,
                rowHeight: CGFloat, spacing: CGFloat, editor: EditorState) -> Bool {
        guard grabbedID == nil, let document = editor.document,
              let layer = document.layer(id: id), !layer.isLocked else { return false }
        let carried = PhotonzDocument.rowsCarried(byDragging: id, selection: editor.actionableLayerIDs)
        // A group travels shut: its contents tuck into its row for the drag,
        // and it opens again where it lands.
        var rows = editor.panelRows
        if editor.expandedGroupIDs.contains(id) {
            reopenAfter = id
            withAnimation(Self.spring) { _ = editor.expandedGroupIDs.remove(id) }
            rows = editor.panelRows
        } else {
            reopenAfter = nil
        }
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return false }
        let pitch = rowHeight + spacing
        // A group shutting under the pointer pulls its row nowhere (its
        // contents are under it), so where the pointer took hold of the row
        // is still where it is.
        let grabbedAt = min(max(pointerY - CGFloat(index) * pitch, 0), rowHeight)
        guard let drag = LayerRowDrag(grabbing: id, carrying: carried, rows: rows, pitch: pitch,
                                      pointerY: CGFloat(index) * pitch + grabbedAt) else {
            reopen()
            return false
        }
        self.editor = editor
        self.drag = drag
        self.rowHeight = rowHeight
        self.viewportY = viewportY
        springing = nil
        phase = .carried
        grabbedID = id
        carriedCount = drag.carried.count
        liftedTop = drag.liftedTop
        layout = Self.layout(of: drag)
        withAnimation(Self.spring) { lift = 1 }
        watchForEscape()
        startTicker()
        return true
    }

    // MARK: - Carrying

    /// The pointer moved, to `pointerY` in the list's points and `viewportY`
    /// in the scrolling area's.
    func move(pointerY: CGFloat, viewportY: CGFloat) {
        guard phase == .carried, var drag, let editor, let document = editor.document else { return }
        self.viewportY = viewportY
        let carried = drag.carried
        drag.move(pointerY: pointerY) { document.canDrop(ids: carried, $0) }
        self.drag = drag
        publish(drag)
    }

    private func publish(_ drag: LayerRowDrag) {
        if liftedTop != drag.liftedTop { liftedTop = drag.liftedTop }
        let next = Self.layout(of: drag)
        if next != layout { withAnimation(Self.spring) { layout = next } }
    }

    private static func layout(of drag: LayerRowDrag) -> Layout {
        var offsets: [UUID: CGFloat] = [:]
        for row in drag.rest {
            let offset = drag.offset(of: row.id)
            if offset != 0 { offsets[row.id] = offset }
        }
        return Layout(offsets: offsets,
                      travelling: drag.hidden.union([drag.grabbedID]),
                      trailingOffset: drag.trailingOffset,
                      gapTop: drag.gapTop,
                      gapDepth: drag.gapDepth)
    }

    // MARK: - Letting go

    /// Let go: the row settles into the gap, and then the document changes,
    /// in one undo step.
    func letGo() {
        guard phase == .carried, let drag else { return }
        phase = .settling
        stopWatching()
        let depth = drag.rows.first { $0.id == drag.grabbedID }?.depth ?? 0
        withAnimation(Self.spring) {
            liftedTop = drag.gapTop
            lift = 0
            settleShift = CGFloat(drag.gapDepth - depth) * Self.indentPerLevel
        } completion: { [weak self] in
            self?.land()
        }
    }

    /// Escape, or anything else that calls the drag off: the row goes back
    /// where it came from and nothing changes.
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

    private func land() {
        finish(landing: drag?.landing)
    }

    /// Puts the list back to plain rows and, when there is somewhere to land,
    /// makes the one edit. Without animation: the rows are already drawn
    /// exactly where the edit puts them, so moving them again would be a
    /// second motion for nothing.
    private func finish(landing: LayerDrop?) {
        guard let editor else { clear(); return }
        let carried = drag?.carried ?? []
        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            if let landing { editor.dropRows(ids: carried, landing) }
            clear()
        }
        reopen()
    }

    private func reopen() {
        guard let group = reopenAfter, let editor else { reopenAfter = nil; return }
        reopenAfter = nil
        withAnimation(Self.spring) { _ = editor.expandedGroupIDs.insert(group) }
    }

    private func clear() {
        stopWatching()
        drag = nil
        grabbedID = nil
        layout = Layout()
        lift = 0
        settleShift = 0
        carriedCount = 0
        phase = .carried
        springing = nil
    }

    // MARK: - Escape, the edges, and a group springing open

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
                self.tick(dt: min(now - last, 0.05), now: now)
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

    private func tick(dt: CFTimeInterval, now: CFTimeInterval) {
        autoscroll(dt: dt)
        springOpen(now: now)
    }

    /// Near the top or bottom edge the list scrolls on its own, faster the
    /// closer the pointer is to the edge, and the gap keeps following the
    /// pointer as the rows pass under it.
    private func autoscroll(dt: CFTimeInterval) {
        guard let scroller, drag != nil else { return }
        let viewport = scroller.viewport()
        guard viewport > Self.edgeBand * 2 else { return }
        let into: CGFloat
        if viewportY < Self.edgeBand {
            into = -(Self.edgeBand - viewportY) / Self.edgeBand
        } else if viewportY > viewport - Self.edgeBand {
            into = (viewportY - (viewport - Self.edgeBand)) / Self.edgeBand
        } else {
            return
        }
        let speed = Self.edgeSpeed * min(max(into, -1), 1) * abs(min(max(into, -1), 1))
        let offset = scroller.offset()
        let furthest = max(0, scroller.contentHeight() - viewport)
        let next = min(max(offset + speed * CGFloat(dt), 0), furthest)
        guard abs(next - offset) > 0.1 else { return }
        scroller.scrollTo(next)
        move(pointerY: viewportY + next, viewportY: viewportY)
    }

    /// A pointer resting on a shut group for a beat opens it, so what is
    /// carried can go inside it.
    private func springOpen(now: CFTimeInterval) {
        guard let drag, let editor, let document = editor.document else { return }
        guard let target = drag.springTarget else { springing = nil; return }
        guard let resting = springing, resting.id == target,
              abs(resting.at - drag.pointerY) < drag.pitch / 2 else {
            springing = (target, now, drag.pointerY)
            return
        }
        guard now - resting.since >= Self.springDelay else { return }
        springing = nil
        withAnimation(Self.spring) { _ = editor.expandedGroupIDs.insert(target) }
        var reflowed = drag
        let carried = drag.carried
        reflowed.reflow(rows: editor.panelRows) { document.canDrop(ids: carried, $0) }
        self.drag = reflowed
        publish(reflowed)
    }
}
