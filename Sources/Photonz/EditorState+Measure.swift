import AppKit
import CoreGraphics
import Observation
import PhotonzCore
import PhotonzRender
import SwiftUI
import UniformTypeIdentifiers

// The measure tool: laying a measurement down, what mode it is in, the
// legend it draws, and the hints it raises.
//
// Split out of EditorState.swift; nothing here changed on the way over.
extension EditorState {
    /// Every readout already on the canvas, in document space. A new
    /// measurement's readout steers around these so two numbers never stack
    /// (UX-PATTERNS D14 rule 4).
    func placedReadoutRects(excluding id: UUID? = nil) -> [CGRect] {
        guard let document else { return [] }
        return document.layers.compactMap { layer in
            layer.id == id ? nil : MeasureBuilder.readoutRect(of: layer)
        }
    }

    /// Picks where a about-to-land measurement's readout sits, so it never
    /// covers the thing it is measuring (UX-PATTERNS D14). `start`/`end` and any
    /// alignment items on `content` must be in document space.
    private func planReadout(_ content: inout MeasureContent, from start: CGPoint, to end: CGPoint,
                             avoiding extra: [CGRect] = [], describing subjects: [CGRect] = []) {
        var probe = content
        probe.start = start
        probe.end = end
        let plan = MeasureLabelPlanner.plan(for: probe, canvas: document?.canvasSize,
                                            avoiding: placedReadoutRects() + extra,
                                            describing: subjects)
        content.apply(plan)
    }

    /// The elements a caliper's feet landed on, read off the capture once, at
    /// placement time, so the readout can stay off them the way a Size readout
    /// stays off the element it measured (UX-PATTERNS D14). Two probes per
    /// foot on a click or a handle release; nothing runs per mouse move.
    func caliperSubjects(from start: CGPoint, to end: CGPoint,
                                 mode: MeasureMode) -> [CGRect] {
        let scale = document?.pixelScale ?? 1
        return ElementBounds.subjects(from: start, to: end, mode: mode,
                                      in: snappingEdgeMap, luma: measureLumaField,
                                      minElement: max(10, 10 * scale),
                                      textGap: AlignmentScan.visibleGap * max(1, scale))
    }

    /// Completed 3-click caliper placement: add the dimension layer with the
    /// active style, then auto-revert to Select and select the new caliper so its
    /// handles are immediately grabbable — matches other apps (the old sticky
    /// measure tool felt inconsistent).
    ///
    /// `headOffset` nil means the caliper landed on the release of the drag and
    /// there was never a third click to set the standoff: the head then reaches
    /// exactly as far as a Gap's does, far enough that the readout sits clear of
    /// the line it belongs to.
    func addMeasure(from start: CGPoint, to end: CGPoint, mode: MeasureMode,
                    headOffset: CGFloat?) {
        var content = measureStyle
        content.mode = mode
        content.headOffset = headOffset
            ?? MeasureBuilder.clearingHeadOffset(content: content, from: start, to: end,
                                                 canvas: document?.canvasSize)
        // A hand-drawn caliper knows what its feet landed on, so its number
        // stays off those elements and not just off its own thin line.
        planReadout(&content, from: start, to: end,
                    describing: caliperSubjects(from: start, to: end, mode: mode))
        var layer = MeasureBuilder.layer(content: content, from: start, to: end)
        // Inherit the last caliper's non-destructive effects (a drop shadow added
        // in Effects carries to the next measure), like annotations do per shape.
        layer.style = measureStyles.layerStyle
        perform { $0.addLayer(layer) }
        recordRecentColor(hex: content.strokeColorHex)
        noteMeasurementLanded()
        finishCreating(layer.id)
    }

    /// Size mode's click: the element under the pointer becomes a width caliper
    /// and a height caliper in ONE undo step, both the same caliper every other
    /// mode produces. Two layers rather than a combined badge on purpose — a
    /// mode that invented its own callout would be the only one with a look of
    /// its own, and each caliper stays individually movable and deletable.
    /// The heads point outward, away from the element, so neither sits on it —
    /// and both readouts are told what the element IS, so the one case the head
    /// cannot solve (an element flush with the edge of the picture, where the
    /// head has to double back over it) still lands its number somewhere clear.
    /// `neighbors` are the elements touching this one, read off the capture by
    /// the canvas: a number parked in the next row down reads as that row's
    /// number, so the readouts steer around them when there is room to.
    func addElementSize(_ rect: CGRect, neighbors: [CGRect] = []) {
        guard rect.width > 0, rect.height > 0, let canvas = document?.canvasSize else { return }
        let widthFeet = (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY))
        let heightFeet = (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY))
        // A width is a Size callout whatever you measured last: starting from
        // the popover's last-used role left both calipers tagged Spacing (and
        // listed as "Gap") right after a Gap click. With roles on they take
        // Size's own ink, like Gap mode takes Spacing's; with roles off the
        // one shared ink stays, only the role is pinned so the names derive.
        var template = Experiments.shared.measureRolesEnabled
            ? measureStyles.content(for: .size) : measureStyle
        template.role = .size
        var width = template
        width.mode = .horizontal
        width.headOffset = MeasureBuilder.clearingHeadOffset(content: width, from: widthFeet.0,
                                                             to: widthFeet.1, canvas: canvas)
        var height = template
        height.mode = .vertical
        height.headOffset = MeasureBuilder.clearingHeadOffset(content: height, from: heightFeet.0,
                                                              to: heightFeet.1, canvas: canvas)
        planReadout(&width, from: widthFeet.0, to: widthFeet.1,
                    avoiding: neighbors, describing: [rect])
        var widthLayer = MeasureBuilder.layer(content: width, from: widthFeet.0, to: widthFeet.1)
        // The height readout also dodges the width readout that just landed —
        // they meet at the element's corner, so they are the likeliest pair in
        // the whole app to stack.
        planReadout(&height, from: heightFeet.0, to: heightFeet.1,
                    avoiding: neighbors + [MeasureBuilder.readoutRect(of: widthLayer)]
                        .compactMap { $0 },
                    describing: [rect])
        var heightLayer = MeasureBuilder.layer(content: height, from: heightFeet.0, to: heightFeet.1)
        widthLayer.style = measureStyles.layerStyle
        heightLayer.style = measureStyles.layerStyle
        perform {
            $0.addLayer(widthLayer)
            $0.addLayer(heightLayer)
        }
        recordRecentColor(hex: width.strokeColorHex)
        noteMeasurementLanded()
        finishCreating(widthLayer.id)
    }

    /// The style the canvas should preview the active Measure mode in. Gap mode
    /// previews in the Spacing ink it will actually commit, and Size mode in
    /// Size's, so what you see under the pointer is what lands.
    var measureStyleForActiveMode: MeasureContent {
        guard Experiments.shared.measureRolesEnabled else { return measureStyle }
        switch measureToolMode {
        case .gap: return measureStyles.content(for: .spacing)
        case .size: return measureStyles.content(for: .size)
        case .distance, .alignment: return measureStyle
        }
    }

    /// Gap mode's click: one caliper across the whitespace, tagged Spacing when
    /// roles are on, because a gap between two elements is by definition a
    /// spacing callout and making the user set that by hand is busywork.
    func addGapMeasure(_ gap: GapMeasurement) {
        guard gap.length > 0, let canvas = document?.canvasSize else { return }
        var content = measureStyleForActiveMode
        content.mode = gap.axis
        // The head reaches far enough that the readout sits clear of the gap
        // itself — a pill parked on a 12 px space hides the very thing measured.
        content.headOffset = MeasureBuilder.clearingHeadOffset(content: content, from: gap.start,
                                                               to: gap.end, canvas: canvas)
        // The two elements bounding the gap are what the number must stay off.
        planReadout(&content, from: gap.start, to: gap.end,
                    describing: caliperSubjects(from: gap.start, to: gap.end, mode: gap.axis))
        var layer = MeasureBuilder.layer(content: content, from: gap.start, to: gap.end)
        layer.style = measureStyles.layerStyle
        perform { $0.addLayer(layer) }
        recordRecentColor(hex: content.strokeColorHex)
        noteMeasurementLanded()
        finishCreating(layer.id)
    }

    /// What the Measure tool does when you click (Next): the two-point caliper,
    /// the size of the element under the pointer, the gap under the pointer, or
    /// an alignment guide. Always visible in the tool options, session chrome,
    /// never persisted. Distance is the default and the only mode that draws
    /// nothing on the canvas until you act.
    /// The mode STICKS, across tool switches and across launches. A tool that
    /// forgets which mode you put it in makes you re-pick it every session, and
    /// the button's glyph is the only place the bar says what the tool will do,
    /// so a mode that resets is also a glyph that lies about your last choice.
    var measureToolMode: MeasureToolMode {
        get { Experiments.shared.measureModesEnabled ? storedMeasureToolMode : .distance }
        set {
            guard newValue != storedMeasureToolMode else { return }
            storedMeasureToolMode = newValue
            measureCandidateLevel = 0
            // Every way of switching (I, the button's flyout, the inspector)
            // lands here, so this is the one place the chip needs to be raised.
            showMeasureModeHint()
        }
    }
    static let measureModeKey = "tool.measure.mode"

    /// Whether the Measure tool is in its Alignment mode (Next flag
    /// `next-measure-align`): drags draw a checking guide instead of a caliper.
    var measureChecksAlignment: Bool { measureToolMode == .alignment }

    /// The Measure tool's Snap option (Next flag `next-measure-center-snap`):
    /// true = "Edges and centers" (the mock's default), false = "Edges".
    /// Persisted with the tool's styles, so it stays how you left it.
    var measureSnapsToCenters: Bool {
        get { measureStyles.snapsToCenters }
        set { updateMeasureStyles { $0.snapsToCenters = newValue } }
    }

    /// Completed alignment-guide drag (`next-measure-align`, decision D1): scan
    /// the element edges the guide crosses, settle the guide onto the reference
    /// edge (the median — the drawn drag was the question, the reference is the
    /// answer), and commit the check as one undoable layer in the caliper's ink.
    func addAlignmentCheck(axis: MeasureMode, position: CGFloat, span: ClosedRange<CGFloat>) {
        guard document != nil, Experiments.shared.measureAlignEnabled else { return }
        let pixelScale = document?.pixelScale ?? 1
        // The picture itself, so the scan counts elements rather than edge
        // runs; empty only in the moment before the analysis lands, and then
        // the check says its items are not counted.
        let luma = measureLumaField
        let items = AlignmentScan.items(axis: axis, position: position, span: span,
                                        in: snappingEdgeMap, luma: luma, pixelScale: pixelScale)
        var content = measureStyle
        content.mode = axis
        content.headOffset = 0
        // The Experiments number is in logical px, like every readout; the
        // items are device px, so a Retina capture gets twice the room.
        content.alignment = AlignmentCheck(
            items: items,
            tolerance: AlignmentCheck.deviceTolerance(logical: Experiments.shared.measureAlignTolerance,
                                                      pixelScale: pixelScale),
            itemsAreElements: !luma.isEmpty)
        let reference = content.alignment?.verdict?.reference ?? items.first?.edge ?? position
        let start: CGPoint, end: CGPoint
        switch axis {
        case .vertical:
            start = CGPoint(x: reference, y: span.lowerBound)
            end = CGPoint(x: reference, y: span.upperBound)
        case .horizontal:
            start = CGPoint(x: span.lowerBound, y: reference)
            end = CGPoint(x: span.upperBound, y: reference)
        }
        planReadout(&content, from: start, to: end)
        var layer = MeasureBuilder.layer(content: content, from: start, to: end)
        layer.style = measureStyles.layerStyle
        perform { $0.addLayer(layer) }
        recordRecentColor(hex: content.strokeColorHex)
        noteMeasurementLanded()
        finishCreating(layer.id)
    }

    /// Raise (or re-raise) the "Copied" notice after text landed on the
    /// clipboard. Never called when a copy did nothing: the copy paths guard
    /// before they get here. Re-raising restarts the clock, so two quick
    /// copies keep one pill up that fades from the last one.
    func showCopyConfirmation(_ subject: CopyConfirmation.Subject) {
        guard Experiments.shared.measurePanelEnabled else { return }
        raiseCanvasNotice(subject)
    }

    /// Puts a notice in the canvas-bottom slot. The flag each caller lives
    /// under is checked by the caller, so one pill can answer more than one
    /// feature without either knowing about the other's switch.
    func raiseCanvasNotice(_ subject: CopyConfirmation.Subject) {
        measureModeHintTimer?.cancel()
        measureModeHint = nil
        let now = Date()
        let notice = copyConfirmation?.reshown(as: subject, at: now)
            ?? CopyConfirmation(subject: subject, shownAt: now)
        copyConfirmation = notice
        copyConfirmationTimer?.cancel()
        copyConfirmationTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(notice.lifetime))
            guard !Task.isCancelled, let self, self.copyConfirmation == notice else { return }
            self.copyConfirmation = nil
        }
    }

    /// Raise (or re-raise) the mode hint. Re-raising restarts the clock, so
    /// three quick presses of I keep one chip up that fades from the last
    /// press; the chip's text follows the mode so it never names a stale one.
    func showMeasureModeHint() {
        guard Experiments.shared.measureModesEnabled else { return }
        // The slot is shared with the "Copied" notice: the latest raise wins.
        copyConfirmationTimer?.cancel()
        copyConfirmation = nil
        let now = Date()
        let hint = measureModeHint?.reshown(as: measureToolMode, at: now)
            ?? MeasureModeHint(mode: measureToolMode, shownAt: now)
        measureModeHint = hint
        measureModeHintTimer?.cancel()
        measureModeHintTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(MeasureModeHint.lifetime))
            guard !Task.isCancelled, let self, self.measureModeHint == hint else { return }
            self.measureModeHint = nil
        }
    }

    /// A measurement just landed: the Current chip retires for the document,
    /// and the Next chip leaves early, since the click it was describing has
    /// happened and its words would only be sitting on the result.
    private func noteMeasurementLanded() {
        measureHintDismissed = true
        measureModeHintTimer?.cancel()
        measureModeHint = nil
    }

    /// Whether the Measure hint chip shows. It tells you what a click does in
    /// the mode you are in, which is the one thing a mode switcher costs you.
    /// Next (`next-measure-modes`): while a mode hint is live, on every pickup
    /// and every mode change. Current: the Measure tool is active and no
    /// measurement has ever landed in this document.
    var showsMeasureHint: Bool {
        guard activeTool == .measure, let document else { return false }
        if Experiments.shared.measureModesEnabled { return measureModeHint != nil }
        guard !measureHintDismissed else { return false }
        return !document.layers.contains { $0.measure != nil }
    }

    /// The chip's lead, set in its own weight: the mode's name. Nil in Current,
    /// where the chip is one plain line and only ever names Distance's click.
    var measureHintTitle: String? { measureModeHint?.title }

    /// That chip's line, for the current mode.
    var measureHintText: String {
        let landsOnRelease = Experiments.shared.measureDistanceLandsOnRelease
        guard let hint = measureModeHint else {
            return measureToolMode.hint(landsOnRelease: landsOnRelease)
        }
        return hint.detail(landsOnRelease: landsOnRelease)
    }

    // MARK: - Measure styling

    /// The selected layer, if it's a measure.
    var selectedMeasureLayer: Layer? {
        guard let id = selectedLayerID, let layer = document?.layer(id: id),
              layer.measure != nil else { return nil }
        return layer
    }

    /// The Measure tool's Show display filter (§5, `next-measure-roles`):
    /// which measurement roles the interactive canvas draws.
    enum MeasureShowFilter: String, CaseIterable {
        case all, size, spacing

        /// Whether the interactive canvas draws this measurement. Alignment
        /// guides are neither Size nor Spacing, so they always show.
        func shows(_ measure: MeasureContent) -> Bool {
            switch self {
            case .all: true
            case .size: measure.alignment != nil || measure.role == .size
            case .spacing: measure.alignment != nil || measure.role == .spacing
            }
        }

        var title: String {
            switch self {
            case .all: "All"
            case .size: "Size"
            case .spacing: "Spacing"
            }
        }
    }

    func setMeasureShowFilter(_ filter: MeasureShowFilter) {
        guard measureShowFilter != filter else { return }
        measureShowFilter = filter
        discardDragPreview()
        if let document { submit(document) }
    }

    /// The document as the INTERACTIVE canvas should draw it: measure layers
    /// the Show filter excludes become invisible, exactly like an eye-off.
    /// Export and pasteboard paths render the document directly, so the filter
    /// can never leak into what leaves the app.
    func displayFiltered(_ document: PhotonzDocument) -> PhotonzDocument {
        guard measureShowFilter != .all,
              Experiments.shared.measureRolesEnabled else { return document }
        var document = document
        for layer in document.layers {
            if let m = layer.measure, !measureShowFilter.shows(m) {
                document.updateLayer(id: layer.id) { $0.isVisible = false }
            }
        }
        return document
    }

    /// Which slot the legend takes. It is a key TO the measurements, so
    /// parking it on top of one makes the same mistake a callout covering its
    /// subject makes (UX-PATTERNS D14): it walks to the first free corner,
    /// and when every corner is taken it steps down the left edge (then the
    /// right) rather than sit on a measurement.
    var measureLegendAnchor: PanelAnchor {
        guard let viewport, let document else { return .topLeading }
        let rows = measureLegendEntries.count
        guard rows > 0 else { return .topLeading }
        let occupied = document.layers.compactMap { layer -> CGRect? in
            guard layer.measure != nil, layer.isVisible else { return nil }
            let origin = viewport.viewPoint(fromDocument: layer.frame.origin)
            return CGRect(x: origin.x, y: origin.y,
                          width: layer.frame.width * viewport.zoom,
                          height: layer.frame.height * viewport.zoom)
        }
        // Chrome along the bottom is a hard no: a legend parked behind the
        // tool bar is invisible, and one under the mode hint's slot gets
        // covered for two seconds every time the mode changes. The slot is
        // reserved even while no pill is up, so the legend never jumps.
        let chrome = EditorChromeLayout.bottomChrome(canvasSize: viewport.viewSize,
                                                     toolBarWidth: toolBarWidth,
                                                     noticeSize: MeasureModeHint.reservedSize)
        // The inspector toggle already lives in the top-right corner. It is
        // neither content to dodge nor chrome that takes the corner away: the
        // top-right slot tucks in underneath it, one stack gap clear.
        return PanelPlacement.firstClear(size: Self.measureLegendSize(rows: rows),
                                          in: viewport.viewSize,
                                          inset: Self.measureLegendInset,
                                          avoiding: occupied,
                                          blocked: chrome,
                                          clearing: Self.measureLegendCornerChrome(in: viewport.viewSize),
                                          gap: EditorChromeLayout.toolBarStackGap)
    }

    /// How far the legend sits below the canvas's top edge in its slot: the
    /// plain inset, except in the top-right corner, where it hangs one stack
    /// gap under the inspector toggle so the two never touch. The view pads
    /// the legend by this on top and by `measureLegendInset` on every other
    /// side.
    var measureLegendTopInset: CGFloat {
        guard let viewport else { return Self.measureLegendInset }
        let anchor = measureLegendAnchor
        guard anchor == .topLeading || anchor == .topTrailing else { return Self.measureLegendInset }
        return PanelPlacement.frame(for: anchor,
                                    size: Self.measureLegendSize(rows: measureLegendEntries.count),
                                    in: viewport.viewSize,
                                    inset: Self.measureLegendInset,
                                    clearing: Self.measureLegendCornerChrome(in: viewport.viewSize),
                                    gap: EditorChromeLayout.toolBarStackGap).minY
    }

    /// The chrome parked in a canvas corner that a corner slot tucks in
    /// beside: today only the inspector toggle, which is up whenever a
    /// document is open.
    private static func measureLegendCornerChrome(in canvasSize: CGSize) -> [CGRect] {
        [EditorChromeLayout.inspectorToggleFrame(canvasSize: canvasSize)]
    }

    /// A generous reservation for the legend's glass panel. It is chrome laid
    /// out by SwiftUI, so its exact size is not knowable here; over-reserving
    /// only makes it step aside a little sooner than strictly needed.
    static func measureLegendSize(rows: Int) -> CGSize {
        CGSize(width: 140, height: CGFloat(max(rows, 1)) * 21 + 16)
    }
    /// The legend's own padding inside the canvas: the one corner inset every
    /// piece of corner chrome shares, so the legend and the inspector toggle
    /// line up when they stack.
    static let measureLegendInset: CGFloat = EditorChromeLayout.cornerInset

    /// One row of the canvas legend (§5): a measurement kind present in the
    /// document, with the ink to swatch it in.
    struct MeasureLegendEntry: Equatable, Identifiable {
        let label: String
        let colorHex: String
        let isDashed: Bool
        var id: String { label }
    }

    /// The canvas legend (§5, `next-measure-roles`): shown while the Measure
    /// tool is active, listing only the kinds the document actually contains.
    /// Swatches take the top-most measurement of each kind's ink, so the legend
    /// matches the canvas even after per-measure recolors. Pure chrome, drawn
    /// as a SwiftUI overlay — never part of an export.
    var measureLegendEntries: [MeasureLegendEntry] {
        guard activeTool == .measure, Experiments.shared.measureRolesEnabled,
              let document else { return [] }
        let measures = document.layers.compactMap(\.measure)
        var entries: [MeasureLegendEntry] = []
        if let m = measures.last(where: { $0.alignment == nil && $0.role == .size }) {
            entries.append(MeasureLegendEntry(label: "Size", colorHex: m.strokeColorHex,
                                              isDashed: false))
        }
        if let m = measures.last(where: { $0.alignment == nil && $0.role == .spacing }) {
            entries.append(MeasureLegendEntry(label: "Spacing", colorHex: m.strokeColorHex,
                                              isDashed: false))
        }
        if let m = measures.last(where: { $0.alignment != nil }) {
            entries.append(MeasureLegendEntry(label: "Alignment", colorHex: m.strokeColorHex,
                                              isDashed: true))
        }
        return entries
    }
}
