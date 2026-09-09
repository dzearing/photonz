// The layers list inside the panel: the rows it builds, the reordering and file drops onto them, and the mark that says a layer is scrolled out of view.

import PhotonzCore
import SwiftUI
import UniformTypeIdentifiers

/// Measured height of a layers-panel row, so a drop can tell the top of a row
/// from its middle, and so the list can work out how tall it wants to be
/// without measuring rows it never built. Every row is the same shape, so one
/// value serves them all.
struct LayerRowHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 38
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Measured height of the Canvas row at the foot of the list. It is separate
/// from `LayerRowHeightKey` because the Canvas row is the ONE row that is
/// always built, so it is the one measurement the list can always rely on.
struct LayerCanvasRowHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 38
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Where a dragged row would land, and what the drop line under the pointer is
/// promising. Three zones per row: the top strip puts the layers in front of
/// this one, the bottom strip behind it, and the middle of a group row puts
/// them inside it. An OPEN group has no bottom strip, because the slot under
/// its row already belongs to its own topmost child.
///
/// A drop is one document mutation, so a drag is one undo step, and every
/// layer keeps its place on the canvas.
struct LayerRowDropDelegate: DropDelegate {
    /// Everything a layer row answers for: a row being carried up or down the
    /// list (which travels as its id in plain text), a picture arriving from
    /// outside, and a saved text style off the Library shelf.
    static let acceptedTypes: [UTType] =
        [.text] + FileDrop.types + [UTType(TextStyleDrag.typeIdentifier) ?? .data]

    let row: LayerPanelRow
    let rowHeight: CGFloat
    let editorState: EditorState

    /// The row the list is holding, if any. It lives on the editor rather than
    /// in the list so that a drag which ends without reporting itself — escape,
    /// let go over the picture, let go outside the window — is still put down,
    /// by the same watch that settles the panel's own mark. See
    /// `LayerRowInHand`.
    private var dragging: UUID? { editorState.layerRowInHand }

    /// What the drag is carrying: the whole selection when the row you picked
    /// up is part of it (the way Delete and Duplicate already work), else just
    /// that row.
    private var carried: Set<UUID> {
        guard let dragging else { return [] }
        return PhotonzDocument.rowsCarried(byDragging: dragging,
                                           selection: editorState.actionableLayerIDs)
    }

    private func proposal(_ info: DropInfo) -> LayerDrop? {
        editorState.dropProposal(carrying: carried, over: row,
                                 pointerY: info.location.y, rowHeight: rowHeight)
    }

    /// Whether THIS drag is a row being carried up or down the list, rather
    /// than a file arriving from outside it.
    ///
    /// It asks what is in the air and not just whether a row was picked up,
    /// because a row can be picked up and then let go somewhere that never
    /// reports it — over the canvas, outside the window, cancelled with escape
    /// — and the list is still holding it afterwards. A picture dragged in next
    /// would then be read as that row coming back: no accept mark, and a drop
    /// that reordered layers instead of adding the picture. What you are
    /// holding decides, and a file is always answered as a file.
    private func carriesARow(_ info: DropInfo) -> Bool {
        dragging != nil && !FileDrop.isAboutAFile(info)
    }

    /// The saved text style in the air right now, nil for every other drag.
    /// Read off the drag pasteboard rather than out of the carrier the drop
    /// hands over, because a row has to answer on the frame the pointer
    /// arrives: a carrier gives up its bytes asynchronously, and a ring that
    /// appears two frames late flickers as the pointer runs down a list.
    ///
    /// Asked FIRST, before anything else about the drag: a style is the app's
    /// own pasteboard type, so it can never be mistaken for a file, and a row
    /// left stale in the list's hand by a drag that ended without saying so
    /// must not turn a style into a reorder.
    private func styleInFlight() -> TextStyleDrop.SavedStyle? {
        editorState.textStyleInFlight()
    }

    /// Says what this row would do with the style over it, and answers the
    /// pointer the same thing. A row that cannot take it shows the no-entry
    /// sign and STILL says why, because a list that quietly refuses is exactly
    /// what this was built to stop.
    private func offerStyle(_ style: TextStyleDrop.SavedStyle) -> DropOperation {
        let drop = editorState.textStyleRowDrop(style, onRow: row.id)
        editorState.sayTextStyleRowDrop(drop)
        return drop.lands ? .copy : .forbidden
    }

    func dropEntered(info: DropInfo) {
        if let style = styleInFlight() {
            _ = offerStyle(style)
            return
        }
        guard carriesARow(info) else {
            offerFile(info)
            return
        }
        editorState.sayLayerRowLanding(proposal(info))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if let style = styleInFlight() { return DropProposal(operation: offerStyle(style)) }
        return rowOrFileUpdate(info)
    }

    private func rowOrFileUpdate(_ info: DropInfo) -> DropProposal? {
        // Nothing was picked up in the list, so this is a file coming in from
        // outside. A row answers for one because nothing behind it can, and it
        // answers the way the rest of the window does: a picture is taken, and
        // anything else shows the no-entry sign.
        guard carriesARow(info) else { return DropProposal(operation: offerFile(info)) }
        let proposed = proposal(info)
        // Said on every frame even when it has not changed, because each answer
        // is also what pushes the put-it-down deadline out: a pointer resting
        // still over one row must not be read as a drag that ended.
        editorState.sayLayerRowLanding(proposed)
        return DropProposal(operation: proposed == nil ? .forbidden : .move)
    }

    func dropExited(info: DropInfo) {
        // Said either way: a style that left this row for the next one has
        // already spoken for the new row, and this goodbye is ignored, which is
        // what stops the ring blinking off at every row edge.
        editorState.endTextStyleRowDrop(from: row.id)
        guard carriesARow(info) else {
            editorState.endPanelDrop(from: row.id)
            return
        }
        // The row is still in the hand — the drag is only off THIS row — so
        // this takes the line away and nothing more.
        if editorState.layerRowLanding?.targetID == row.id { editorState.sayLayerRowLanding(nil) }
    }

    func performDrop(info: DropInfo) -> Bool {
        if let style = styleInFlight() {
            return editorState.dropTextStyle(style, onRow: row.id)
        }
        guard carriesARow(info) else {
            let landing = fileLanding(info)
            editorState.endPanelDrop(from: row.id)
            return FileDrop.accept(info, into: editorState, landingAt: landing)
        }
        defer { editorState.letGoOfLayerRow() }
        guard let drop = proposal(info) else { return false }
        editorState.dropRows(ids: carried, drop)
        return true
    }

    /// Where the picture in the air lands if it is let go on this row now: the
    /// slot the pointer is pointing at, read the same three ways a row drag is,
    /// falling back to the top of the stack for a row that cannot take it.
    private func fileLanding(_ info: DropInfo) -> LayerDrop? {
        editorState.incomingDropProposal(over: row, pointerY: info.location.y, rowHeight: rowHeight)
            ?? editorState.incomingDropOnTop
    }

    /// Tells the panel what it is about to do with the file in the air, and
    /// answers the pointer the same thing.
    ///
    /// A row takes plain text as well as files, because that is how a row being
    /// reordered travels — so this is also where every OTHER thing the app
    /// carries around lands: a colour off a swatch, a saved colour off the
    /// Library shelf, words dragged out of a field. None of them is a file, and
    /// the panel says nothing at all about them. The pointer still shows the
    /// no-entry sign, because a colour does not belong on a layer row either.
    @discardableResult
    private func offerFile(_ info: DropInfo) -> DropOperation {
        guard FileDrop.isAboutAFile(info) else { return .forbidden }
        guard FileDrop.carriesUsableFile(info) else {
            editorState.offerPanelDrop(.refuses, from: row.id)
            return .forbidden
        }
        editorState.offerPanelDrop(.accepts(fileLanding(info)), from: row.id)
        return .copy
    }
}

// MARK: - Layers section

/// The layer list: thumbnails, visibility, lock, rename (double-click),
/// drag-reorder, and selection. Lives inside the docked inspector's Layers
/// section.
struct LayersListView: View {
    @Environment(EditorState.self) private var editorState
    @State private var renamingLayerID: UUID?
    @State private var renameText = ""
    @State private var rowHeight: CGFloat = 38
    /// The row at the top of the visible area. Only the rows around it get a
    /// picture made for them, so opening a document with a hundred layers
    /// costs the same handful of renders as opening one with ten.
    @State private var firstVisibleRow = 0
    @FocusState private var renameFieldFocused: Bool

    /// The layer area's max height (user-resizable, persisted). Beyond this the
    /// list scrolls INTERNALLY so a tall stack doesn't shove the Effects/Shadow
    /// sections off the bottom of the inspector — you keep the other palettes in
    /// view and scroll layers on their own.
    ///
    /// The area is sized to every row a twist could reveal rather than to the
    /// rows on screen, so opening a group scrolls inside this height instead
    /// of changing it. Before that, twisting a four layer group open in a two
    /// layer document made the area 80 points taller and carried the Layout
    /// controls off the bottom of the panel.
    ///
    /// Five rows at rest. It was eight, which in a document with any real number
    /// of layers spent a third of the panel on a list you were not looking at
    /// and pushed the look of the thing off the bottom. Drag the grabber under
    /// the list to give it back as much room as you want; that sticks.
    @AppStorage(LayersListView.heightKey) private var maxHeight = 200.0
    /// Measured height of the Canvas row, the one row that is always built.
    @State private var canvasRowHeight: CGFloat = 38
    /// What the count line and the grab bar under the list come to.
    @State private var listExtrasHeight: CGFloat = 0

    /// A second ceiling, from the dock rather than from the grab bar: what the
    /// panel can spare once every form section has been paid for. The stored
    /// ceiling is what this list ASKED for; this is what the panel HAS, and the
    /// list is drawn at the smaller of the two. See `DockHeightBudget`.
    var dockCeiling: CGFloat?
    /// Told what this list would be at full length, and what the count line and
    /// the grab bar under it cost, so the dock can budget for both separately:
    /// the list scrolls and they do not.
    var onMetrics: ((_ listNatural: CGFloat, _ extras: CGFloat) -> Void)?

    /// How tall the layers area may get, remembered across launches.
    static let heightKey = "inspector.layersHeight"
    static let minHeight: CGFloat = 120
    static let maxAllowedHeight: CGFloat = 600

    /// A LazyVStack of rows (NOT a `List`: a List has no natural height and its
    /// fixed-height hack clipped the top rows), inside a bounded ScrollView so it
    /// scrolls independently, plus a drag handle to resize it. Reordering uses the
    /// same drag/drop the inspector sections use.
    ///
    /// Lazy, so a hundred-layer document builds the five rows the panel shows
    /// and makes the rest as you scroll to them. That is why the area's height
    /// is WORKED OUT (`LayerListMetrics`) rather than measured: a lazy stack
    /// reports no height for a row it never built, and feeding that back into
    /// this frame is a loop that shrinks itself — a smaller frame builds fewer
    /// rows, which reports a smaller height, which shrinks the frame again.
    var body: some View {
        let displays = editorState.layerRows
        // The area is sized to every row a twist COULD reveal, not to the rows
        // showing right now, so opening a group scrolls inside the list rather
        // than growing it and pushing the controls under it off the panel.
        let reserved = LayerListMetrics.naturalHeight(
            rowCount: editorState.layerListReservedRowCount(visibleRowCount: displays.count),
            rowHeight: rowHeight,
            canvasRowHeight: canvasRowHeight)
        // The height the list is actually given, which is also the height of
        // the window of rows worth drawing pictures for. Two ceilings, and the
        // lower one wins: what the reader dragged the grab bar to, and what the
        // dock has room for after the form sections are paid.
        let ceiling = min(maxHeight, dockCeiling ?? .greatestFiniteMagnitude)
        let viewport = PanelAreaResize.height(contentHeight: reserved, ceiling: ceiling)
        // What the grab bar may reach. Never past what the dock can spare, so
        // the bar is never a control that cannot act: every point of it still
        // moves the list, and when the dock has nothing at all to give, the bar
        // is not drawn rather than sitting there refusing to move. The room is
        // still there to be had — collapsing a section you are not using is
        // what frees it.
        let grabRange = min(reserved, dockCeiling ?? .greatestFiniteMagnitude)
        // ...and what the list would be if the dock were NOT pressing on it:
        // its rows, capped by the ceiling the reader set with that bar. This is
        // what the dock budgets from, so it reserves room for the list the
        // reader asked for rather than for rows the grab bar already ruled out.
        let unpressed = PanelAreaResize.height(contentHeight: reserved, ceiling: maxHeight)
        return VStack(spacing: 0) {
            ScrollView(.vertical) {
                rows(displays, viewport: viewport)
            }
            .frame(height: viewport)
            .scrollBounceBehavior(.basedOnSize)
            // Which row is at the top, watched as a ROW rather than as an
            // offset: the action then fires once per row you scroll past
            // instead of once per frame, which is what keeps this cheap.
            .onScrollGeometryChange(for: Int.self) { geometry in
                LayerListMetrics.firstVisibleRow(
                    scrollOffset: geometry.contentOffset.y + geometry.contentInsets.top,
                    rowHeight: rowHeight)
            } action: { _, row in
                firstVisibleRow = row
            }
            // The one line the list says while a saved style is over a row:
            // what letting go there would do, and why it would do nothing when
            // it would do nothing. Over the list rather than at the foot of the
            // whole panel, so it is a glance from the row it is about.
            .overlay(alignment: styleNoteEdge(displays, viewport: viewport)) {
                StyleRowDropNote(drop: editorState.layerRowStyleDrop)
                    .allowsHitTesting(false)
            }
            .animation(.easeOut(duration: 0.12), value: editorState.layerRowStyleDrop)

            // What the list costs BESIDES the rows. These do not scroll with
            // the list — a grab bar that scrolled away would be a grab bar you
            // could not reach — so the dock has to budget for them separately.
            VStack(spacing: 0) {
                multiSelectionCount
                resizeHandle(reserved: grabRange)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { extras in
                listExtrasHeight = extras
                onMetrics?(unpressed, extras)
            }
        }
        .onAppear { onMetrics?(unpressed, listExtrasHeight) }
        .onChange(of: unpressed) { _, latest in onMetrics?(latest, listExtrasHeight) }
        // The Rename command asks for a row's field. Only rows this list shows
        // answer, so the Measurements list next door does not open a second
        // field on the same layer.
        .onChange(of: editorState.layerAwaitingRename) { _, id in
            guard let id, editorState.panelRows.contains(where: { $0.id == id }),
                  let layer = editorState.document?.layer(id: id) else { return }
            editorState.layerAwaitingRename = nil
            beginRename(id: layer.id, name: layer.name)
        }
    }

    /// Which end of the list the one line about a style sits at: the end the
    /// aimed row is NOT near, so the sentence is close enough to read in the
    /// same glance and never draws over the very row it is about.
    private func styleNoteEdge(_ displays: [LayerRowDisplay], viewport: CGFloat) -> Alignment {
        guard let id = editorState.layerRowStyleDrop?.rowID,
              let index = displays.firstIndex(where: { $0.id == id }) else { return .bottom }
        let fromTop = CGFloat(index - firstVisibleRow) * (rowHeight + LayerListMetrics.spacing)
        return fromTop > viewport / 2 ? .top : .bottom
    }

    /// The inspector shows no per-layer sections for a multi-selection, so
    /// this one line is what says the panel and the canvas agree: "3 layers
    /// selected". Absent for zero or one.
    private var multiSelectionCount: some View {
        let count = editorState.multiSelectedLayerIDs.count
        return Group {
            if count >= 2 {
                Text("\(count) layers selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.leading, EditorChromeLayout.panelEdgeInset)
                    .panelEdgePadding()
                    .padding(.top, 4)
            }
        }
    }

    /// The list, built from ONE read of the document: `editorState.layerRows`
    /// walks the tree once and hands back what each row draws, and the
    /// thumbnails come in one pass beside it. Each row is then an `.equatable()`
    /// view over plain values, so a click that moves the selection redraws the
    /// two rows whose highlight changed and leaves the rest alone. Before this,
    /// every row re-ran its body on every click and looked its own layer up by
    /// searching the whole tree, which cost the list the square of its length
    /// (measured 2026-09-04: about 0.14ms of main thread per row per click).
    ///
    /// Lazy: `LazyVStack` builds a row the first time it comes into view and
    /// keeps it after that, so opening a hundred-layer document costs the five
    /// rows the panel is showing, not a hundred context menus, drop delegates
    /// and gesture recognisers nobody is looking at.
    private func rows(_ displays: [LayerRowDisplay], viewport: CGFloat) -> some View {
        // The twist column appears only once there is something to twist open,
        // so a document with no groups is the list it always was.
        let showsTwist = Experiments.shared.layersListShowsGroups && displays.contains { $0.row.isGroup }
        let componentsEnabled = Experiments.shared.componentsEnabled
        // Both component menu items also need the row to be the selected one,
        // so folding that in here keeps every OTHER row's value unchanged when
        // these flip.
        let canMakeComponent = componentsEnabled && editorState.canMakeComponent
        let canDetachInstance = componentsEnabled && editorState.canDetachInstance
        // Pictures for the rows you can see and a few off each edge, NOT for
        // the ninety behind them: every one is a real render, so asking for
        // all of them is most of the cost of opening a big document and none
        // of the benefit. Rows outside the window draw their placeholder until
        // they come near, and the cache keeps every picture once it lands, so
        // scrolling back over ground you have covered asks for nothing.
        let window = LayerListMetrics.thumbnailWindow(rowCount: displays.count,
                                                      rowHeight: rowHeight,
                                                      firstVisibleRow: firstVisibleRow,
                                                      viewportHeight: viewport)
        let thumbnails = editorState.thumbnails(for: Array(displays[window]))
        // One drop line for two kinds of drag: a row being reordered inside
        // the list, and a picture arriving from outside it. They never happen
        // at once, and drawing them the same way is the point — the promise a
        // file gets is the promise the list already made to its own rows.
        // The row being carried and where it would land are the editor's, not
        // this view's: a drag that ends without reporting itself must still be
        // put down, and only something outside the list can notice that.
        let target = editorState.layerRowLanding ?? editorState.panelDropLanding
        // A saved style is aimed at ONE row, so only that row wears a mark. It
        // never happens at the same time as a reorder or a file: a style is the
        // app's own pasteboard type and nothing else in the air can look like
        // one.
        let styleDrop = editorState.layerRowStyleDrop
        return LazyVStack(spacing: LayerListMetrics.spacing) {
            ForEach(displays) { display in
                LayersRow(display: display,
                          thumbnail: thumbnails[display.id],
                          showsTwist: showsTwist,
                          componentsEnabled: componentsEnabled,
                          offersMakeComponent: canMakeComponent && display.isSelected,
                          offersDetachInstance: canDetachInstance && display.isSelected,
                          drop: target?.targetID == display.id ? target : nil,
                          styleDrop: styleDrop?.rowID == display.id ? styleDrop : nil,
                          draftName: renamingLayerID == display.id ? renameText : nil,
                          rowHeight: rowHeight,
                          editorState: editorState,
                          renameText: $renameText,
                          renameFieldFocused: $renameFieldFocused,
                          beginRename: beginRename(id:name:),
                          commitRename: commitRename(id:),
                          cancelRename: cancelRename)
                    .equatable()
            }
            // The Canvas pseudo-layer: pinned at the very bottom (beneath the
            // Background it frames). Not a real layer — no eye/lock/delete/
            // reorder; selecting it puts resize handles on the canvas boundary.
            canvasRow
        }
        .padding(.horizontal, EditorChromeLayout.panelListGutter)
        .padding(.bottom, LayerListMetrics.bottomPadding)
        .onPreferenceChange(LayerRowHeightKey.self) { rowHeight = max(1, $0) }
        .onPreferenceChange(LayerCanvasRowHeightKey.self) { canvasRowHeight = max(1, $0) }
        // Rows slide/fade on add, delete, duplicate, reorder, and on a group
        // opening or closing. Keyed on the SHAPE of the list only: a selection
        // change is not a layout change and never was animated here.
        .animation(.spring(duration: 0.25), value: displays.map(\.row))
    }

    /// A grabber under the list: drag it to resize the layer area. It is there
    /// only while the list is taller than the area's floor, since below that
    /// the list is already showing everything it has and no drag could change
    /// the picture.
    ///
    /// `reserved` is the room the area keeps, which counts the rows a shut
    /// group is hiding: the same number the area is drawn at, so the bar and
    /// the frame under it can never disagree about how far a drag may go.
    private func resizeHandle(reserved: CGFloat) -> some View {
        PanelAreaResizeHandle(maxHeight: $maxHeight,
                              area: "Layers",
                              contentHeight: reserved,
                              minHeight: Self.minHeight,
                              maxAllowedHeight: Self.maxAllowedHeight,
                              help: "Drag to resize the layers area")
    }

    private var canvasRow: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .foregroundStyle(.tertiary)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 40, height: 30)
            Text("Canvas")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if let size = editorState.document?.canvasSize {
                Text(verbatim: "\(Int(size.width)) × \(Int(size.height))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.leading, 6)
        .panelEdgeRowPadding()
        .padding(.vertical, 4)
        .background {
            if editorState.isCanvasSelected {
                RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.25))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { editorState.selectCanvas() }
        .panelHelp("Select to resize the canvas by its edges")
        // Measured on its own because it is not shaped like a layer row and
        // the list's height arithmetic counts it separately. In a short list
        // it is on screen, so the measurement is live exactly when hugging
        // depends on it; in a long one the list is capped anyway and the
        // default carries.
        .background(GeometryReader { proxy in
            Color.clear.preference(key: LayerCanvasRowHeightKey.self, value: proxy.size.height)
        })
    }

    private func beginRename(id: UUID, name: String) {
        renameText = name
        renamingLayerID = id
        renameFieldFocused = true
    }

    private func commitRename(id: UUID) {
        guard renamingLayerID == id else { return }
        renamingLayerID = nil
        editorState.renameLayer(id: id, to: renameText)
    }

    /// Escape: the row keeps the name it had and nothing reaches history, the
    /// same thing Escape does to a frame's name on the canvas.
    private func cancelRename() {
        renamingLayerID = nil
    }
}

/// One row of the layers list, as a view that can tell when nothing about it
/// changed.
///
/// Everything the row draws arrives as a plain value and NOTHING in `body`
/// reads the editor state. The actions do, but they run on a click, long after
/// the row was drawn, so they never make the row an observer. That is what lets
/// `.equatable()` mean something: a click that moves the selection changes the
/// value of the two rows whose highlight changed, and every other row in the
/// list is skipped whole.
///
/// Keep it that way. Reaching for `editorState.something` inside `body` here
/// quietly puts every row back on the list of things a click has to redraw.
/// The mark on a row whose layer the container around it has cut off, and on a
/// shut group that is hiding one.
///
/// A container set to cut off what does not fit makes anything past its edge
/// disappear completely: the canvas stops drawing it, clicks go through where
/// it used to be, and until now the layers list showed a row that looked like
/// every other row. Somebody who dragged a label a little too far had lost it,
/// with undo as the only way back.
///
/// Scissors because that is the same word the switch uses ("Clip contents"),
/// and warm because a state to notice should not shout like an error.
///
/// It is also the way back. The mark used to name the box and then leave you
/// with three moves to choose between — drag the layer, turn off Clip contents,
/// or type a new number into the inspector — which is a lot of work to undo one
/// drag that went too far. Now the mark does whatever its own sentence tells
/// you to do: on a layer that has been cut off, one press slides it back over
/// the edge it left by; on a shut group speaking for what it is hiding, one
/// press opens the group so the marked rows are on screen.
///
/// At rest it stays a bare glyph, because most of the time it is telling you
/// something rather than asking to be pressed. The capsule under it arrives on
/// hover, which is the moment, and the only moment, somebody needs telling
/// that this one can be pressed.
struct OutOfViewMark: View {
    let outOfView: RowOutOfView
    /// This row's layer, for the sentence about what it is hiding.
    let name: String
    /// Where a walk finds this control: the list, the row, and what it says.
    let place: (String) -> String
    /// What one press does, which is whatever the tip has just promised.
    let press: () -> Void

    @State private var hovering = false

    var body: some View {
        Group {
            if isPressable {
                Button(action: press) { glyph }
                    .buttonStyle(.plain)
                    .onHover { hovering = $0 }
                    .playtestControl("Out of view", detail: place(state))
            } else {
                // Nothing one press could put right, so nothing that looks
                // pressable. The tip still says what happened and what would
                // fix it; a button that did the wrong thing quietly would be
                // worse than no button at all.
                glyph.playtestTarget("Out of view", kind: .row, detail: place(state))
            }
        }
        .panelHelp(explanation)
    }

    /// Whether pressing this would do anything: a layer that can come back, a
    /// container that can be made big enough for it, or a shut group with rows
    /// to show.
    private var isPressable: Bool {
        outOfView.container == nil ? outOfView.hiddenInside > 0
                                   : outOfView.canReturn || outOfView.growsContainer != nil
    }

    private var glyph: some View {
        Image(systemName: "scissors")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background {
                if hovering { Capsule().fill(Color.orange.opacity(0.18)) }
            }
            .contentShape(Capsule())
    }

    /// The word a walk matches on, so a step can say which of the two things
    /// this mark can mean it is pressing.
    private var state: String {
        outOfView.container.map { "cut off by \($0)" } ?? "hiding \(outOfView.hiddenInside)"
    }

    private var explanation: String {
        var lines: [String] = []
        if let container = outOfView.container {
            if outOfView.canReturn {
                lines.append(
                    "Out of view: this sits outside \(container), which is set to cut off what "
                    + "does not fit. Click to bring it back in, or turn off Clip contents on "
                    + "\(container) to show everything.")
            } else if let change = outOfView.growsContainer {
                // A layer whose container decides where it sits cannot be moved
                // back, so the press changes the container instead. It says
                // which number and what it becomes BEFORE it is pressed,
                // because that number is one somebody typed on purpose.
                lines.append(
                    "Out of view: \(container) is not big enough for everything in it and is set "
                    + "to cut off what does not fit. Click to make \(container) \(change) so "
                    + "everything fits, or turn off Clip contents on it.")
            } else {
                lines.append(
                    "Out of view: \(container) is not big enough for everything in it and is set "
                    + "to cut off what does not fit. Make \(container) bigger in the Layout "
                    + "section, or turn off Clip contents on it.")
            }
        }
        if outOfView.hiddenInside > 0 {
            lines.append(outOfView.hiddenInside == 1
                         ? "1 layer inside \(name) is out of view. Click to open \(name) and find it."
                         : "\(outOfView.hiddenInside) layers inside \(name) are out of view. "
                           + "Click to open \(name) and find them.")
        }
        return lines.joined(separator: " ")
    }
}
