import AppKit
import CoreGraphics
import Observation
import PhotonzCore
import PhotonzRender
import SwiftUI
import UniformTypeIdentifiers

// Frames: making them, sizing them, and turning a canvas drag into one.
//
// Split out of EditorState.swift; nothing here changed on the way over.
extension EditorState {
    // MARK: - Frames (Next flag `next-frames`)

    var lastFrameSize: CGSize {
        get {
            let parts = lastFrameSizeRaw.split(separator: "x").compactMap { Double($0) }
            guard parts.count == 2 else { return FramePreset.default.size }
            return FramePreset.normalized(CGSize(width: parts[0], height: parts[1]))
        }
        set {
            let size = FramePreset.normalized(newValue)
            lastFrameSizeRaw = "\(Int(size.width))x\(Int(size.height))"
        }
    }

    /// Whether the frame rows and the frame tool exist at all.
    var framesEnabled: Bool { Experiments.shared.framesEnabled }

    /// Whether Layer ▸ Frame Selection would do anything: one unlocked layer
    /// is enough, because putting a single thing on a screen of its own is a
    /// normal way to start.
    var canFrameSelection: Bool {
        guard framesEnabled, let document else { return false }
        return document.canFrameSelection(ids: actionableLayerIDs)
    }

    /// The frame Export would offer as its scope: the selected frame, or the
    /// frame whatever is selected lives in. Nil when the selection is nowhere
    /// near one.
    var selectedFrameID: UUID? {
        guard let document, let id = selectedLayerID else { return nil }
        return document.frameID(containing: id)
    }

    /// Every frame in the document, outermost first — the export scope menu
    /// and the frame label chrome both read this.
    var documentFrames: [Layer] {
        document?.frames ?? []
    }

    /// A frame drawn on the canvas, or dropped at a chosen size. One undo
    /// step, then the frame is selected with the Select tool in hand, the way
    /// every other created layer lands.
    @discardableResult
    func addFrame(at origin: CGPoint, size: CGSize, name: String? = nil) -> UUID? {
        guard document != nil else { return nil }
        let size = FramePreset.normalized(size)
        var madeID: UUID?
        perform { document in
            madeID = document.addFrame(name: name, origin: origin, size: size).id
        }
        lastFrameSize = size
        if let madeID { finishCreating(madeID) }
        return madeID
    }

    /// The frame tool's drag: a frame the size you drew, or — when the drag
    /// was really a click — one at the size you made last, dropped with its
    /// top left where you clicked.
    func addFrame(from start: CGPoint, to end: CGPoint) {
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        if rect.width < 4 || rect.height < 4 {
            addFrame(at: start, size: lastFrameSize)
        } else {
            addFrame(at: rect.origin, size: rect.size)
        }
    }

    /// Layer ▸ New Frame…: a frame at a chosen size, placed where the eye
    /// already is. The first one lands in the middle of what you are looking
    /// at; every one after that lines up to the right of the frames already on
    /// the canvas, which is how a document ends up reading as a row of screens
    /// rather than a stack of them.
    func addFrameInView(size: CGSize) {
        guard let document else { return }
        let size = FramePreset.normalized(size)
        let canvas = CGRect(origin: .zero, size: document.canvasSize)
        var visible = canvas
        if let viewport {
            visible = CGRect(x: -viewport.origin.x / viewport.zoom,
                             y: -viewport.origin.y / viewport.zoom,
                             width: viewport.viewSize.width / viewport.zoom,
                             height: viewport.viewSize.height / viewport.zoom)
                .intersection(canvas)
        }
        addFrame(at: document.placementForNewFrame(size: size, visible: visible), size: size)
    }

    /// Layer ▸ Frame Selection: puts a frame around what is selected, fitted
    /// to it exactly, in one undo step.
    func frameSelection() {
        guard canFrameSelection else { return }
        let ids = actionableLayerIDs
        discardDragPreview()
        var madeID: UUID?
        perform { document in
            madeID = document.frameSelection(ids: ids)?.id
        }
        groupContextID = madeID.flatMap { document?.parentID(of: $0) }
        selectedLayerID = madeID
        setSelection(nil, captureLayers: false)
    }

    /// The frame inspector's size menu and its typed width and height. The
    /// layers inside stay where they are: a frame's size says where it clips.
    func setFrameSize(id: UUID, size: CGSize) {
        guard document?.layer(id: id)?.isFrame == true else { return }
        discardDragPreview()
        perform { $0.setFrameSize(id: id, size: size) }
        lastFrameSize = size
    }

    /// Whether a container hides what hangs off its edge: a screen, or a group
    /// somebody gave a size of its own.
    func setClipsContents(id: UUID, _ clips: Bool) {
        guard document?.layer(id: id)?.hasBoxOfItsOwn == true else { return }
        perform { $0.setClipsContents(id: id, clips) }
    }

    /// The same switch over every picked group, in one undo step.
    func setClipsContents(ids: [UUID], _ clips: Bool) {
        guard !ids.isEmpty else { return }
        perform { $0.setClipsContents(ids: ids, clips) }
    }

    /// The surface a frame paints behind its contents; nil is a frame you see
    /// the canvas through.
    func setFrameBackground(id: UUID, hex: String?) {
        guard document?.layer(id: id)?.isFrame == true else { return }
        perform { $0.setFrameBackground(id: id, hex: hex) }
        if let hex { recordRecentColor(hex: hex) }
    }

    // MARK: - Frames from the canvas
    //
    // The canvas drags in CANVAS coordinates; a layer stores its frame in its
    // PARENT'S. The two are the same thing for a layer sitting loose on the
    // canvas, which is every layer in a document with no groups, so these two
    // entry points convert once and everything downstream keeps working in the
    // space it always did.

    /// A canvas-space point in the space the layer is stored in. Unchanged for
    /// a layer sitting loose on the canvas.
    func parentPoint(_ point: CGPoint, of id: UUID) -> CGPoint {
        let origin = document?.parentOrigin(of: id) ?? .zero
        return CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    /// Live drag update from the canvas, in canvas coordinates.
    ///
    /// A group takes the same path as everything else: the box it is being
    /// dragged to goes into `resized(to:)`, which moves it when the size did
    /// not change and scales everything inside it when it did
    /// (`docs/design/ui-building.md`). Previews always start from the document
    /// as it was before the drag — `submit` renders without touching history —
    /// so a hundred mouse-moves compose into one clean scale rather than a
    /// hundred stacked ones.
    func previewCanvasFrame(id: UUID, frame: CGRect) {
        guard let parent = storedCanvasFrame(frame, of: id) else { return }
        previewLayerFrame(id: id, frame: parent)
    }

    /// Mouse-up from the canvas, in canvas coordinates: one undo step.
    func commitCanvasFrame(id: UUID, frame: CGRect) {
        guard let parent = storedCanvasFrame(frame, of: id) else { return }
        commitLayerFrame(id: id, frame: parent)
    }

    /// Mouse-up on a DRAG, in canvas coordinates: the same one undo step, plus
    /// the layer joining the screen it was dropped on or leaving the one it was
    /// dragged out of.
    ///
    /// Only a drag takes this path. A resize and an arrow-key nudge come
    /// through `commitCanvasFrame` and never change what holds a layer: a nudge
    /// quietly changing hands one point at a time is a surprise nobody can see
    /// coming, and there is no pointer over a screen to say it is about to
    /// happen. See `FrameAdoption.swift`.
    func commitCanvasDrop(id: UUID, frame: CGRect) {
        guard let parent = storedCanvasFrame(frame, of: id) else { return }
        commitLayerFrame(id: id, frame: parent, joiningScreens: true)
    }

    /// Live drag update for a whole multi-selection, in canvas coordinates:
    /// every layer the drag carries goes to its own new origin, and a group
    /// takes what is inside it along in one number changing.
    ///
    /// There is no floated sprite for a selection — a sprite carries one layer
    /// — so this re-renders the picture per mouse move, the path a text layer's
    /// drag has always taken.
    func previewCanvasOrigins(_ moves: [UUID: CGPoint]) {
        guard !moves.isEmpty, var doc = document else { return }
        // The rubber band that picked these layers described where they WERE.
        // The moment they move it stops being true, so it comes down rather
        // than lying, exactly as it does when a ⇧-click changes the selection.
        // A pixel region belongs to the region tools: that one stays.
        if selection != nil, !selectionTargetsPixels { setSelection(nil, captureLayers: false) }
        // A sprite left over from an earlier one-layer drag would float that
        // layer over a picture that has already moved it. Dropped once, not
        // once per mouse move: this runs on every point of the drag.
        if dragPreview != nil { discardDragPreview() }
        for (id, origin) in moves { doc.moveLayer(id: id, toCanvasOrigin: origin) }
        previewMoves = moves.reduce(into: [:]) { frames, move in
            frames[move.key] = doc.canvasBounds(of: move.key)
        }
        submit(doc)
    }

    /// Mouse-up on a multi-selection drag: the whole selection lands in ONE
    /// undo step, so one ⌘Z puts all of it back where it was.
    func commitCanvasOrigins(_ moves: [UUID: CGPoint], joiningScreens: Bool = false) {
        previewMoves = [:]
        guard !moves.isEmpty else { return }
        // The rubber band that picked these layers described where they WERE,
        // so it comes down the moment they move. A drag already dropped it on
        // its first live update; an arrow-key nudge has no live update at all,
        // and without this the band sits there outlining empty canvas.
        if selection != nil, !selectionTargetsPixels { setSelection(nil, captureLayers: false) }
        discardDragPreview()
        // Draw order, so a selection dropped on a screen keeps its stacking
        // inside it rather than landing in whatever order a dictionary iterated.
        let ordered = document?.allLayers.map(\.id).filter { moves[$0] != nil } ?? Array(moves.keys)
        var joined: [UUID] = []
        perform { document in
            for (id, origin) in moves { document.moveLayer(id: id, toCanvasOrigin: origin) }
            if joiningScreens { joined = document.adoptMovedLayers(ids: ordered) }
        }
        revealJoinedScreens(joined)
    }
}

// MARK: - Columns on a screen (Next flag `next-frames`)
//
// The column layout one screen is designed to: twelve with a gutter on a
// desktop, four on a phone. Drawn over that screen and pulling a drag to its
// edges, and nowhere else in the app.
//
// Not the canvas grid, which covers everything, is set by a spacing, belongs to
// the view rather than the document, and never pulls (`CanvasGridSettings`).
extension EditorState {

    /// The screen the Columns section and the Layer menu row both act on: the
    /// selected screen, or the screen whatever is selected lives in. Selecting
    /// a button inside a screen and asking for columns is asking for that
    /// screen's columns, which is the only screen it could mean.
    ///
    /// The panel reads this too, so the numbers are wherever the menu row
    /// works and never the other way round (the menu row used to work with a
    /// button picked while the section had gone).
    var columnsTargetFrameID: UUID? {
        guard framesEnabled else { return nil }
        return selectedFrameID
    }

    /// That same screen as a layer, so the panel can say its name in the
    /// section header when the screen is not the thing you have picked.
    var columnsTargetFrame: Layer? {
        columnsTargetFrameID.flatMap { document?.layer(id: $0) }
    }

    /// Whether the screen those columns belong to IS what is selected. False
    /// with a button on the screen picked, which is when the section has to
    /// name the screen rather than just say "Columns".
    var isColumnsTargetSelected: Bool {
        guard let id = columnsTargetFrameID else { return false }
        return id == selectedLayerID
    }

    /// What that screen's columns are right now, or nil for a screen nobody
    /// has given any.
    var columnsTargetSettings: FrameColumns? {
        columnsTargetFrameID.flatMap { document?.layer(id: $0)?.columns }
    }

    /// Whether the columns are showing on the screen the menu row would act on.
    var isShowingFrameColumns: Bool {
        columnsTargetSettings?.isVisible ?? false
    }

    /// Layer ▸ Show Columns, and the checkbox at the top of the Columns
    /// section. Switching them off leaves every number where it was, so
    /// switching them back on is the same layout again; a screen that has never
    /// had any gets numbers picked for its width.
    func setFrameColumnsVisible(_ visible: Bool) {
        guard let id = columnsTargetFrameID else { return }
        perform { $0.setFrameColumnsVisible(id: id, visible) }
    }

    func toggleFrameColumns() {
        setFrameColumnsVisible(!isShowingFrameColumns)
    }

    /// One of the three typed numbers. Each one goes through history, so ⌘Z
    /// puts a mistyped column count back.
    func setFrameColumns(_ columns: FrameColumns) {
        guard let id = columnsTargetFrameID else { return }
        perform { $0.setFrameColumns(id: id, columns) }
    }

    func setFrameColumnCount(_ count: Int) {
        guard var columns = columnsTargetSettings else { return }
        columns.count = FrameColumns.clamped(count: count)
        setFrameColumns(columns)
    }

    func setFrameColumnGutter(_ gutter: CGFloat) {
        guard var columns = columnsTargetSettings else { return }
        columns.gutter = FrameColumns.clamped(gutter: gutter)
        setFrameColumns(columns)
    }

    func setFrameColumnMargin(_ margin: CGFloat) {
        guard var columns = columnsTargetSettings else { return }
        columns.margin = FrameColumns.clamped(margin: margin)
        setFrameColumns(columns)
    }

    /// How wide one column comes out on the screen the section is showing, or
    /// nil when the numbers leave no room for one. The panel prints it, because
    /// "what is a column actually going to be" is the question a person is
    /// really asking when they type a gutter.
    var columnsTargetColumnWidth: CGFloat? {
        guard let id = columnsTargetFrameID, let columns = columnsTargetSettings,
              let width = document?.canvasBounds(of: id)?.width else { return nil }
        return columns.bands(inWidth: width).first?.width
    }
}
