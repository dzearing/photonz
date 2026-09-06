import AppKit
import PhotonzCore
import PhotonzRender

// The measure tool's half of the canvas view. Everything here is about what
// the Measure tool draws and decides while you are pointing at the picture:
// the hover previews for Size and Gap modes, the element/neighbour/subject
// lookups those previews are built from, the readout planning that keeps a
// number clear of what it describes, the three-click caliper placement flow
// and its snapping, the alignment-guide drag, and the geometry of a placed
// caliper's three handles. It is an extension on `CanvasNSView` rather than a
// type of its own: the state it reads (viewport, document, edge map, in-flight
// placement) and the CALayers it draws into are the canvas view's, and the
// point of the split is a file small enough to review, not a new boundary. A
// few of the canvas view's members are therefore internal rather than private
// so this file can reach them; they are still the canvas view's alone.

extension CanvasNSView {
    /// Moves a dragged readout and lines it up with the other readouts on the
    /// picture, writing the landing back into `drag` and returning the guide to
    /// draw.
    ///
    /// The pill moves two ways and they mean different things: ACROSS its line
    /// it carries the caliper's head with it (the fork gets deeper), ALONG the
    /// line only the number moves and the measurement is untouched. Both line up
    /// with the readouts already placed, which is the point — a stack of widths
    /// can be pulled into one tidy column of numbers.
    ///
    /// The pointer keeps its grip on the pill, so it is the CHIP that is lined
    /// up, not the pointer. The across-axis landing is then checked: a readout
    /// pushed clear of its subject keeps its own distance from the measuring
    /// line and does not ride the head, and a snap it would not honour is
    /// dropped rather than faked.
    func snapMeasureHead(_ drag: inout MeasureHandleDrag, pointer p: CGPoint,
                         zoom: CGFloat, snapping: Bool,
                         holding held: SnapHold = .none) -> (x: CGFloat?, y: CGFloat?)? {
        guard let layer = document?.layer(id: drag.layerID),
              let m = documentMeasure(layer) else {
            drag.current = p
            return nil
        }
        let slides = Experiments.shared.measureReadoutSlideEnabled
        let landing = MeasureReadoutDrag.resolve(m, pointer: p, grabCross: drag.grabCross,
                                                 grabAlong: drag.grabAlong, guides: drag.guides,
                                                 zoom: zoom, snapping: snapping,
                                                 slidesAlong: slides, holding: held)
        drag.current = p
        drag.head = landing.headOffset
        // Only a drag that actually slid the number claims it was placed by
        // hand: pinning a number nobody moved would stop it dodging forever.
        drag.readout = slides ? landing.readout : nil
        return (landing.guideX, landing.guideY)
    }


    /// Which of a caliper's three handles is being dragged: either foot of the
    /// measuring line, or the head (the chip bar's perpendicular offset).
    enum MeasureHandle { case footA, footB, head }

    /// Dragging one of a placed caliper's three handles. Feet drags keep the
    /// measuring line level (the opposite foot follows onto the dragged foot's
    /// cross-axis); the head drag changes only the signed perpendicular offset.
    struct MeasureHandleDrag {
        let layerID: UUID
        let handle: MeasureHandle
        let mode: MeasureMode
        let originalStart: CGPoint   // feet, document space
        let originalEnd: CGPoint
        let originalHeadOffset: CGFloat
        /// Where on the cross axis the pointer took hold, relative to the head:
        /// a head grabbed by its readout (anywhere on the pill) or a little off
        /// its dot keeps that grip, instead of jumping under the pointer.
        var grabCross: CGFloat = 0
        /// The same grip ALONG the line, relative to the readout pill's centre,
        /// so a pill taken hold of by its edge does not jump under the pointer.
        var grabAlong: CGFloat = 0
        /// The lines the OTHER measurements offer this drag, collected once at
        /// grab time: nothing else on the canvas moves while a handle is held,
        /// and rebuilding them per mouse-moved event would be wasted work.
        var guides: EdgeSnapping.GuideLines = .none
        /// The head-drag landing, resolved against the readout's real geometry:
        /// the signed head offset, and where the number sits along the line when
        /// this drag moved it (nil when it did not).
        var head: CGFloat?
        var readout: MeasureReadoutPlacement?
        var originalReadout: MeasureReadoutPlacement
        var current: CGPoint
        /// The caliper's (start, end, headOffset) with this drag applied, plus
        /// where the drag put the number when it moved it at all.
        func params() -> (start: CGPoint, end: CGPoint, headOffset: CGFloat,
                          readout: MeasureReadoutPlacement?) {
            var s = originalStart, e = originalEnd, off = originalHeadOffset
            switch handle {
            case .head:
                off = head ?? ((mode == .horizontal ? current.y - s.y : current.x - s.x) - grabCross)
                return (s, e, off, readout)
            case .footA:
                s = current
                if mode == .horizontal { e.y = current.y } else { e.x = current.x }
            case .footB:
                e = current
                if mode == .horizontal { s.y = current.y } else { s.x = current.x }
            }
            // Dragging a fork keeps the HEAD (chip) fixed in absolute space —
            // the leg depth grows/shrinks to absorb the feet line's move, so the
            // label doesn't wander when you adjust the measured span.
            let headAbs = mode == .horizontal ? originalStart.y + originalHeadOffset
                                              : originalStart.x + originalHeadOffset
            let feet = mode == .horizontal ? s.y : s.x
            off = headAbs - feet
            return (s, e, off, nil)
        }
        /// Where the caliper was before this drag, readout included — an Esc
        /// puts the number back exactly as it was, hand-placed or not.
        func originalParams() -> (start: CGPoint, end: CGPoint, headOffset: CGFloat,
                                  readout: MeasureReadoutPlacement?) {
            (originalStart, originalEnd, originalHeadOffset, originalReadout)
        }
    }

    /// The three draggable handles of a placed caliper in document space: the two
    /// feet (the measuring line) and the head (the chip bar's offset point).
    func measureHandles(_ layer: Layer) -> [(handle: MeasureHandle, point: CGPoint)] {
        guard let m = layer.measure, m.alignment == nil,
              let s = layer.measureEndpoint(.start), let e = layer.measureEndpoint(.end) else { return [] }
        let g = MeasureContent.caliperGeometry(mode: m.mode, start: s, end: e, headOffset: m.headOffset)
        return [(.footA, g.footA), (.footB, g.footB), (.head, g.labelAnchor)]
    }

    /// The lines a dragged FOOT lands on besides the picture's own borders: the
    /// guides pinned onto this document, and the lines the measurements already
    /// on the canvas offer (their feet, heads and ends, so two calipers can
    /// share a start line). Pass nil to exclude nothing (a caliper being placed
    /// is not a layer yet).
    ///
    /// The pinned guides come first, so where a guide and another caliper's
    /// line sit on the same number the guide wins the tie: you pinned it on
    /// purpose and the caliper only happens to be there. They are also the half
    /// that does not depend on the measurement flag — a guide catches a foot
    /// for the same reason it catches a dragged box.
    func measureGuideLines(excluding id: UUID?) -> EdgeSnapping.GuideLines {
        let pinned = canvasSnapGuides
        var lines = EdgeSnapping.GuideLines(
            vertical: CanvasGuides.positions(pinned, axis: .vertical),
            horizontal: CanvasGuides.positions(pinned, axis: .horizontal))
        guard Experiments.shared.measureGuideSnapEnabled, let document else { return lines }
        let measurements = MeasureSnapping.lines(in: document, excluding: id)
        lines.vertical += measurements.vertical
        lines.horizontal += measurements.horizontal
        return lines
    }

    /// The lines a dragged READOUT CHIP lines up with: where the other chips
    /// centre. A chip is not a measured point, so the picture's own edges have
    /// no say over where it parks — the other chips do.
    func measureChipGuideLines(excluding id: UUID) -> EdgeSnapping.GuideLines {
        guard Experiments.shared.measureGuideSnapEnabled, let document else { return .none }
        return MeasureSnapping.chipLines(in: document, excluding: id)
    }

    /// A caliper's content re-based to document space (its feet are stored
    /// layer-local), so its readout geometry compares against the pointer.
    func documentMeasure(_ layer: Layer) -> MeasureContent? {
        guard var m = layer.measure, m.alignment == nil,
              let s = layer.measureEndpoint(.start), let e = layer.measureEndpoint(.end) else { return nil }
        m.start = s
        m.end = e
        return m
    }

    /// The readout pill's footprint in document space. Dragging the number
    /// drags the head: it is the obvious thing to take hold of, and while the
    /// pill sits on the head midpoint it is the ONLY grab there (see
    /// `drawnMeasureHandles`).
    func measureReadoutRect(_ layer: Layer) -> CGRect? {
        guard let m = documentMeasure(layer), m.showLabel else { return nil }
        return m.labelRect(chipSize: m.estimatedLabelSize)
    }


    /// The handles that get a dot. The head dot is left out while the readout
    /// covers it: a white dot on the digits made "121 px" read as "12 px",
    /// and the pill is the grab there anyway.
    func drawnMeasureHandles(_ layer: Layer) -> [CGPoint] {
        let covered = documentMeasure(layer).map { $0.labelCoversHeadHandle(chipSize: $0.estimatedLabelSize) } ?? false
        return measureHandles(layer).compactMap { covered && $0.handle == .head ? nil : $0.point }
    }

    /// Tracks the pointer for the measure tool's hover dot + placement preview.
    func handleMeasureHover(_ event: NSEvent) {
        hoverPoint = convert(event.locationInWindow, from: nil)
        // Feed the axis-gating accumulator while seeking foot B so a decisive
        // drag direction suppresses perpendicular snap jitter.
        if case .firstPlaced = measurePlacement, let viewport, let hoverPoint {
            trackDragMotion(viewport.documentPoint(fromView: hoverPoint))
        }
        refreshMeasureCreation(modifierFlags: event.modifierFlags)
    }

    // MARK: Caliper 3-click placement

    /// Snaps the FIRST foot to a nearby edge (small window; ⌘ = free).
    func snapMeasureAnchor(_ doc: CGPoint, modifiers: NSEvent.ModifierFlags) -> CGPoint {
        guard let viewport, !modifiers.contains(.command) else { return doc }
        return EdgeSnapping.snap(doc, edges: edgeMap, zoom: viewport.zoom,
                                 includeCenters: measureSnapsToCenters,
                                 guides: measureGuideLines(excluding: nil)).point
    }

    /// Snaps the SECOND foot along the measuring line from foot1 (edge magnetize +
    /// axis gating; ⌘ = free), then levels it to the dominant axis. Returns the
    /// leveled foot and the chosen axis.
    private func snapMeasureSecondFoot(from foot1: CGPoint, to doc: CGPoint,
                                       modifiers: NSEvent.ModifierFlags) -> (foot2: CGPoint, mode: MeasureMode) {
        var p = doc
        if modifiers.contains(.command) {
            // Freed by hand: nothing is being stood on any more, so nothing is
            // waiting to grab the line back when the key comes up.
            snapHold = .none
        } else if let viewport {
            // The line the preview is showing is the line the click lands on:
            // the same hold the handle drags use, so drawing a caliper and
            // adjusting one afterwards behave identically.
            let snap = axisGated(EdgeSnapping.snap(doc, edges: edgeMap, zoom: viewport.zoom,
                                                   xSpan: min(foot1.x, doc.x)...max(foot1.x, doc.x),
                                                   ySpan: min(foot1.y, doc.y)...max(foot1.y, doc.y),
                                                   includeCenters: measureSnapsToCenters,
                                                   guides: measureGuideLines(excluding: nil),
                                                   holding: snapHold),
                                  raw: doc)
            snapHold.caught(x: snap.guideX, y: snap.guideY)
            p = snap.point
        }
        let mode = MeasureContent.dominantAxis(from: foot1, to: p)
        let foot2 = mode == .horizontal ? CGPoint(x: p.x, y: foot1.y) : CGPoint(x: foot1.x, y: p.y)
        return (foot2, mode)
    }

    /// Signed perpendicular distance from the measuring line to `doc` — the head
    /// (depth + direction). Kept a hair off zero so a click on the line still
    /// yields a visible caliper.
    private func measureHeadOffset(mode: MeasureMode, foot1: CGPoint, point doc: CGPoint) -> CGFloat {
        let raw = mode == .horizontal ? doc.y - foot1.y : doc.x - foot1.x
        if abs(raw) < 4 { return raw >= 0 ? 4 : -4 }
        return raw
    }

    /// Whether the caliper lands the moment the measuring line is done, with its
    /// number placed for you (Next, `next-measure-modes` / distance-on-release),
    /// instead of waiting for a third click to set the head.
    var measureLandsOnRelease: Bool {
        measureToolMode == .distance && Experiments.shared.measureDistanceLandsOnRelease
    }

    /// Advances placement on mouse-up. `dragged` = the press moved far enough to
    /// count as a drag. The measuring line is set by click/click OR by a single
    /// press-drag-release; the head is a final click (or drag). The last step
    /// commits the caliper (which auto-reverts to the Select tool).
    ///
    /// With `measureLandsOnRelease` on there is no last step: finishing the line
    /// commits, and the head and the number are placed the way Gap places its
    /// own. Moving the number afterwards is a drag on the pill, which is the
    /// same grab that has always moved it.
    func advanceMeasurePlacement(at raw: CGPoint, dragged: Bool,
                                 modifiers: NSEvent.ModifierFlags) {
        switch measurePlacement {
        case nil:
            // mouse-down normally creates .firstPlaced; guard defensively.
            resetDragMotion(raw)
            measurePlacement = .firstPlaced(foot1: snapMeasureAnchor(raw, modifiers: modifiers))
        case .firstPlaced(let foot1):
            if measureFirstFootPress && !dragged {
                // A plain click placed foot A — stay and wait for a foot-B click.
                measureFirstFootPress = false
            } else {
                // Either a press-drag-release drew the line, or a later click/drag
                // set foot B. Complete the measuring line → head-placement mode.
                measureFirstFootPress = false
                let (foot2, mode) = snapMeasureSecondFoot(from: foot1, to: raw, modifiers: modifiers)
                guard hypot(foot2.x - foot1.x, foot2.y - foot1.y) >= 1 else { break }
                guard !measureLandsOnRelease else {
                    finishMeasurePlacement(foot1: foot1, foot2: foot2, mode: mode, headOffset: nil)
                    break
                }
                measurePlacement = .secondPlaced(foot1: foot1, foot2: foot2, mode: mode)
            }
        case .secondPlaced(let foot1, let foot2, let mode):
            finishMeasurePlacement(foot1: foot1, foot2: foot2, mode: mode,
                                   headOffset: measureHeadOffset(mode: mode, foot1: foot1,
                                                                 point: raw))
        }
        refreshOverlays()
    }

    /// Lands the caliper and clears the in-flight chrome. `headOffset` nil means
    /// the app picks the standoff itself, the way it does for a Gap.
    private func finishMeasurePlacement(foot1: CGPoint, foot2: CGPoint,
                                        mode: MeasureMode, headOffset: CGFloat?) {
        measurePlacement = nil
        measureFirstFootPress = false
        snapGuide = nil
        snapDotLayer.isHidden = true
        clearAnnotationPreview()
        onMeasureCommit(foot1, foot2, mode, headOffset) // adds, selects, reverts to Select
    }

    /// Cancels an in-progress placement (⎋, tool switch, or a Measure mode
    /// switch) — both the caliper draft and any alignment-guide drag.
    func cancelMeasurePlacement() {
        measurePlacement = nil
        measureFirstFootPress = false
        measurePressDownView = nil
        alignmentDrag = nil
        alignmentPreviewLayer.isHidden = true
        snapGuide = nil
        snapDotLayer.isHidden = true
        hideMeasureHoverReadout()
        clearAnnotationPreview()
    }

    // MARK: Alignment-guide drag (Next, `next-measure-align`)

    /// Draws the dashed guide being dragged, leveled onto the drag's dominant
    /// axis through the (snapped) anchor.
    func refreshAlignmentPreview() {
        guard let viewport, let drag = alignmentDrag else {
            alignmentPreviewLayer.isHidden = true
            return
        }
        hideMeasureHoverReadout()
        let axis = MeasureContent.dominantAxis(from: drag.anchor, to: drag.current)
        let end = axis == .vertical
            ? CGPoint(x: drag.anchor.x, y: drag.current.y)
            : CGPoint(x: drag.current.x, y: drag.anchor.y)
        let path = CGMutablePath()
        path.move(to: viewport.viewPoint(fromDocument: drag.anchor))
        path.addLine(to: viewport.viewPoint(fromDocument: end))
        let style = measureContent ?? MeasureContent()
        let rgba = RGBA(hex: style.strokeColorHex) ?? RGBA(r: 1, g: 0.23, b: 0.19)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        alignmentPreviewLayer.path = path
        alignmentPreviewLayer.strokeColor = CGColor(srgbRed: rgba.r, green: rgba.g,
                                                    blue: rgba.b, alpha: rgba.a)
        alignmentPreviewLayer.lineWidth = max(1, style.strokeWidth * viewport.zoom)
        alignmentPreviewLayer.isHidden = false
        snapDotLayer.isHidden = true
        CATransaction.commit()
    }

    /// Mouse-up on an alignment drag: level onto the dominant axis and hand the
    /// guide (axis, cross-axis position, along-axis span) to the app, which
    /// scans the edges it crosses and commits the check. A press that never
    /// really dragged is a quiet no-op — a guide needs a span.
    func finishAlignmentDrag(from anchor: CGPoint, to raw: CGPoint) {
        guard let viewport else { return }
        let axis = MeasureContent.dominantAxis(from: anchor, to: raw)
        let alongLength = axis == .vertical ? abs(raw.y - anchor.y) : abs(raw.x - anchor.x)
        guard alongLength * viewport.zoom > 8 else {
            refreshMeasureCreation(modifierFlags: [])
            return
        }
        let position = axis == .vertical ? anchor.x : anchor.y
        let span = axis == .vertical
            ? min(anchor.y, raw.y)...max(anchor.y, raw.y)
            : min(anchor.x, raw.x)...max(anchor.x, raw.x)
        onAlignmentCommit(axis, position, span) // adds, selects, reverts to Select
    }

    // MARK: Size / Gap mode preview (Next)

    /// Hides every mode-preview layer (a miss, a placement, a tool switch).
    func hideMeasureHoverReadout() {
        hoverBoundsLayer.isHidden = true
        hoverWidthCaliperLayer.isHidden = true
        hoverHeightCaliperLayer.isHidden = true
        measureElementPreview = nil
        measureElementNeighbors = []
        measureGapPreview = nil
    }

    /// Draws (or hides) what a click would commit in the current mode.
    ///
    /// Only Size and Gap draw here at all: Distance leaves the canvas untouched
    /// until you click, which is the whole reason it is the default. A miss is
    /// quiet (no chrome), and until the edge map has finished computing,
    /// detection sees `EdgeMap.empty` and this stays a no-op — the same gate
    /// snapping uses. Whatever is drawn is stashed, so mouse-up commits exactly
    /// the thing you were looking at.
    private func refreshMeasureHoverReadout(modifierFlags: NSEvent.ModifierFlags) {
        measureElementPreview = nil
        measureElementNeighbors = []
        measureGapPreview = nil
        guard tool == .measure, measurePlacement == nil,
              measureToolMode.previewsUnderPointer,
              let viewport, let document, let hoverPoint else {
            hideMeasureHoverReadout()
            return
        }
        let probe = viewport.documentPoint(fromView: hoverPoint)
        guard CGRect(origin: .zero, size: document.canvasSize).contains(probe) else {
            hideMeasureHoverReadout()
            return
        }
        let style = measureContent ?? MeasureContent()
        switch measureToolMode {
        case .size:
            let ladder = ElementBounds.candidates(
                at: probe, in: edgeMap, luma: lumaField,
                // Ten logical points is the smallest thing worth calling an
                // element, whatever the capture's scale; a line of text ends
                // at the same visible gap the alignment scan splits items on.
                minElement: max(10, 10 * document.pixelScale),
                textGap: AlignmentScan.visibleGap * max(1, document.pixelScale))
            guard let rect = ladder.isEmpty
                    ? nil : ladder[min(max(measureCandidateLevel, 0), ladder.count - 1)] else {
                hideMeasureHoverReadout()
                return
            }
            measureElementPreview = rect
            drawElementPreview(rect, style: style, viewport: viewport,
                               pixelScale: document.pixelScale, canvas: document.canvasSize)
        case .gap:
            guard let gap = ElementBounds.gap(at: probe, in: edgeMap) else {
                hideMeasureHoverReadout()
                return
            }
            measureGapPreview = gap
            drawGapPreview(gap, style: style, viewport: viewport,
                           pixelScale: document.pixelScale, canvas: document.canvasSize)
        case .distance, .alignment:
            hideMeasureHoverReadout()
        }
    }

    /// The elements around the picked one, so the two readouts can steer around
    /// them: what is touching it, and what sits as far out as the number itself
    /// will travel, since a button half a chip away is just as much in the way.
    /// Detection costs milliseconds per probe and the pick holds still while
    /// the pointer wanders inside one element, so the last answer is reused
    /// until the pick actually changes.
    private func neighbors(of rect: CGRect, reach: CGFloat) -> [CGRect] {
        if let cached = measureNeighborCache, cached.rect == rect, cached.reach == reach {
            return cached.neighbors
        }
        let scale = max(1, document?.pixelScale ?? 1)
        let found = ElementBounds.neighbors(of: rect, in: edgeMap, luma: lumaField,
                                            minElement: max(10, 10 * scale),
                                            textGap: AlignmentScan.visibleGap * scale,
                                            reaches: [ElementBounds.neighborProbeReach,
                                                      Double(reach)])
        measureNeighborCache = (rect, reach, found)
        return found
    }

    /// Size mode's preview: the picked element outlined in the measure ink, with
    /// the width and height calipers a click would leave behind.
    private func drawElementPreview(_ rect: CGRect, style: MeasureContent,
                                    viewport: Viewport, pixelScale: CGFloat, canvas: CGSize) {
        let rgba = RGBA(hex: style.strokeColorHex) ?? RGBA(r: 1, g: 0.23, b: 0.19)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // Element outline: the measure ink at reduced opacity + a whisper of
        // fill, so there is never any doubt about WHAT is being measured — the
        // complaint that sank the old always-on version.
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
            .map { viewport.viewPoint(fromDocument: $0) }
        let outline = CGMutablePath()
        outline.addLines(between: corners)
        outline.closeSubpath()
        hoverBoundsLayer.path = outline
        hoverBoundsLayer.strokeColor = CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: 0.7)
        hoverBoundsLayer.fillColor = CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: 0.05)
        hoverBoundsLayer.isHidden = false

        // Width caliper along the bottom edge, height caliper along the right,
        // both heads reaching outward far enough to clear the element — the same
        // placement the click commits, so the preview never lies.
        let widthFeet = (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY))
        let heightFeet = (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY))
        var widthStyle = style
        widthStyle.mode = .horizontal
        var heightStyle = style
        heightStyle.mode = .vertical
        let widthHead = MeasureBuilder.clearingHeadOffset(content: widthStyle, from: widthFeet.0,
                                                          to: widthFeet.1, canvas: canvas)
        let heightHead = MeasureBuilder.clearingHeadOffset(content: heightStyle, from: heightFeet.0,
                                                           to: heightFeet.1, canvas: canvas)
        // Both readouts are told the element itself is off limits, and steer
        // around whatever sits within reach of where a number would land; the
        // height number also dodges the width number, exactly the order the
        // commit uses, so nothing shifts between the preview and the click.
        let widthChip = widthStyle.estimatedLabelSize
        let heightChip = heightStyle.estimatedLabelSize
        let reach = max(abs(widthHead) + widthChip.height / 2,
                        abs(heightHead) + heightChip.width / 2)
        let neighbors = neighbors(of: rect, reach: reach)
        measureElementNeighbors = neighbors
        let widthReadout = layoutHoverCaliper(
            hoverWidthCaliperLayer, sprite: &hoverWidthSprite,
            style: style, mode: .horizontal,
            from: widthFeet.0, to: widthFeet.1, headOffset: widthHead,
            viewport: viewport, pixelScale: pixelScale,
            avoiding: neighbors, describing: [rect])
        layoutHoverCaliper(
            hoverHeightCaliperLayer, sprite: &hoverHeightSprite,
            style: style, mode: .vertical,
            from: heightFeet.0, to: heightFeet.1, headOffset: heightHead,
            viewport: viewport, pixelScale: pixelScale,
            avoiding: neighbors + [widthReadout].compactMap { $0 }, describing: [rect])
    }

    /// Gap mode's preview: one caliper across the whitespace, no outline — there
    /// is no element to outline, and the caliper's own feet already show which
    /// two edges are being measured to.
    private func drawGapPreview(_ gap: GapMeasurement, style: MeasureContent,
                                viewport: Viewport, pixelScale: CGFloat, canvas: CGSize) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        hoverBoundsLayer.isHidden = true
        hoverHeightCaliperLayer.isHidden = true
        var ink = style
        ink.mode = gap.axis
        // The readout is told which two elements bound the gap, exactly as the
        // click will tell it, so the preview never lies about where it lands.
        layoutHoverCaliper(hoverWidthCaliperLayer, sprite: &hoverWidthSprite,
                           style: style, mode: gap.axis,
                           from: gap.start, to: gap.end,
                           headOffset: MeasureBuilder.clearingHeadOffset(
                               content: ink, from: gap.start, to: gap.end, canvas: canvas),
                           viewport: viewport, pixelScale: pixelScale,
                           describing: subjects(of: gap, pixelScale: pixelScale))
    }

    /// The elements on either side of `gap`, read once per gap rather than per
    /// mouse move: the pointer wanders inside one gap for many events and the
    /// answer cannot change until the gap does.
    private func subjects(of gap: GapMeasurement, pixelScale: CGFloat) -> [CGRect] {
        if let cached = measureGapSubjectCache, cached.gap == gap { return cached.subjects }
        let found = ElementBounds.subjects(from: gap.start, to: gap.end, mode: gap.axis,
                                           in: edgeMap, luma: lumaField,
                                           minElement: max(10, 10 * pixelScale),
                                           textGap: AlignmentScan.visibleGap * max(1, pixelScale))
        measureGapSubjectCache = (gap, found)
        return found
    }

    /// Positions one transient caliper layer, rasterizing through the same
    /// `MeasureBuilder`/`MeasureRasterizer` pipeline a committed caliper uses so
    /// the readout (chip, unit, decimals, ink) matches a real measure exactly.
    /// The raster is cached until the measured span or style actually changes.
    @discardableResult
    private func layoutHoverCaliper(_ caliperLayer: CALayer, sprite: inout HoverCaliperSprite?,
                                    style: MeasureContent, mode: MeasureMode,
                                    from start: CGPoint, to end: CGPoint, headOffset: CGFloat,
                                    viewport: Viewport, pixelScale: CGFloat,
                                    avoiding extra: [CGRect] = [],
                                    describing subjects: [CGRect] = []) -> CGRect? {
        var content = style
        content.mode = mode
        content.headOffset = headOffset
        content.showLabel = true
        // The preview picks the readout's spot exactly the way the commit will,
        // so nothing jumps when you click (UX-PATTERNS D14).
        var probe = content
        probe.start = start
        probe.end = end
        let plan = MeasureLabelPlanner.plan(for: probe, canvas: viewport.documentSize,
                                            avoiding: placedReadoutRects() + extra,
                                            describing: subjects)
        content.apply(plan)
        probe.apply(plan)
        let readout = probe.labelRect(chipSize: probe.estimatedLabelSize)
        let built = MeasureBuilder.layer(content: content, from: start, to: end)
        let key = "\(mode.rawValue)|\(start)|\(end)|\(style.unit.rawValue)|\(style.decimals)|"
            + "\(style.strokeColorHex)|\(style.chipColorHex)|\(style.textColorHex)|"
            + "\(style.labelScale)|\(style.strokeWidth)|\(pixelScale)|"
            + "\(plan.placement.rawValue)|\(plan.nudge)|\(plan.crossReach)"
        if sprite?.key != key {
            guard let measure = built.measure,
                  let image = MeasureRasterizer.rasterize(measure, size: built.frame.size,
                                                          pixelScale: pixelScale) else {
                sprite = nil
                caliperLayer.isHidden = true
                return nil
            }
            sprite = HoverCaliperSprite(key: key, image: image, frame: built.frame)
        }
        guard let sprite else { return nil }
        caliperLayer.contents = sprite.image
        let origin = viewport.viewPoint(fromDocument: sprite.frame.origin)
        caliperLayer.frame = CGRect(x: origin.x, y: origin.y,
                                    width: sprite.frame.width * viewport.zoom,
                                    height: sprite.frame.height * viewport.zoom)
        caliperLayer.isHidden = false
        return readout
    }

    /// Every readout already on the canvas, in document space — what a hovered
    /// preview steers around, same as a committed measurement does.
    private func placedReadoutRects() -> [CGRect] {
        (document?.layers ?? []).compactMap { MeasureBuilder.readoutRect(of: $0) }
    }

    /// Draws the measure tool's creation chrome — the snapping dot(s) and the
    /// in-progress preview line/squared-U — for the 3-click placement flow. ⌘
    /// bypasses edge snapping throughout.
    func refreshMeasureCreation(modifierFlags: NSEvent.ModifierFlags) {
        refreshMeasureHoverReadout(modifierFlags: modifierFlags)
        guard tool == .measure, let viewport else {
            snapDotLayer.isHidden = true
            return
        }
        let cursor = hoverPoint.map { viewport.documentPoint(fromView: $0) }
        let dots = CGMutablePath()
        let r: CGFloat = 4
        func addDot(_ doc: CGPoint) {
            let v = viewport.viewPoint(fromDocument: doc)
            dots.addEllipse(in: CGRect(x: v.x - r, y: v.y - r, width: 2 * r, height: 2 * r))
        }
        var previewPoints: [CGPoint] = []

        // Alignment mode: only the snap dot (it shows which edge a press would
        // anchor the guide on); the caliper placement chrome never applies.
        if measureChecksAlignment {
            if alignmentDrag == nil, let cursor {
                addDot(snapMeasureAnchor(cursor, modifiers: modifierFlags))
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            snapDotLayer.path = dots
            snapDotLayer.isHidden = dots.isEmpty
            annotationPreviewLayer.isHidden = true
            annotationPreviewHeadLayer.path = nil
            CATransaction.commit()
            return
        }

        switch measurePlacement {
        case nil:
            if let cursor { addDot(snapMeasureAnchor(cursor, modifiers: modifierFlags)) }
        case .firstPlaced(let foot1):
            addDot(foot1)
            if let cursor {
                let (foot2, _) = snapMeasureSecondFoot(from: foot1, to: cursor, modifiers: modifierFlags)
                addDot(foot2)
                previewPoints = [foot1, foot2]
            }
        case .secondPlaced(let foot1, let foot2, let mode):
            addDot(foot1)
            addDot(foot2)
            if let cursor {
                let off = measureHeadOffset(mode: mode, foot1: foot1, point: cursor)
                let g = MeasureContent.caliperGeometry(mode: mode, start: foot1, end: foot2, headOffset: off)
                addDot(g.labelAnchor)
                previewPoints = g.path
            }
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        snapDotLayer.path = dots
        snapDotLayer.isHidden = dots.isEmpty
        if previewPoints.count >= 2 {
            let style = measureContent ?? MeasureContent()
            let path = CGMutablePath()
            let pts = previewPoints.map { viewport.viewPoint(fromDocument: $0) }
            path.move(to: pts[0])
            for p in pts.dropFirst() { path.addLine(to: p) }
            let rgba = RGBA(hex: style.strokeColorHex) ?? RGBA(r: 1, g: 0.23, b: 0.19)
            annotationPreviewLayer.path = path
            annotationPreviewLayer.strokeColor = CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
            annotationPreviewLayer.fillColor = nil
            annotationPreviewLayer.lineWidth = max(1, style.strokeWidth * viewport.zoom)
            annotationPreviewLayer.lineJoin = .round
            annotationPreviewLayer.lineCap = .round
            annotationPreviewLayer.compositingFilter = nil
            annotationPreviewHeadLayer.path = nil
            annotationPreviewLayer.isHidden = false
        } else {
            annotationPreviewLayer.isHidden = true
            annotationPreviewHeadLayer.path = nil
        }
        CATransaction.commit()
    }
}
