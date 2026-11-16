import AppKit
import PhotonzCore
import SwiftUI

/// **Zoom**: the lane under a recording that has zooms on it, one bar per zoom
/// (`ClipZoom.swift`, `EditorState+Zoom`).
///
/// A bar is the stretch the zoom is on; the lighter ends are its way in and
/// out, and the small upright mark where each ramp meets the hold is a handle
/// that drags the ramp longer or shorter. A press on the bar picks it, its two
/// ends trim it, its middle carries it, and a right click has Follow Cursor,
/// how far in, and Delete Zoom. Shift or Command click adds a bar to the pick
/// or takes it out, and a click on the lane's "Zoom" label picks every bar on
/// it, so a change in the panel or the menus reaches all of them at once.
/// Screen Studio's zoom track, laid out the way the Words lane is.
struct ZoomLane: View {
    @Environment(EditorState.self) private var editorState
    let layerID: UUID
    let laneWidth: CGFloat
    var indent: CGFloat = 0
    var isLocked = false
    /// Whether this is the lane itself rather than the copy drawn lifted while
    /// its track is carried, which must not say where the lane is.
    var isLifted = false

    static let height: CGFloat = 22
    static let barTop: CGFloat = 2
    static let barHeight: CGFloat = 18

    /// "Zoom" in the gutter, the way the Words lane labels itself. A click on
    /// it picks every zoom on the lane, the way a track's header picks its track.
    static func header(indent: CGFloat, isLit: Bool = false) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "plus.magnifyingglass").font(.system(size: 9, weight: .semibold))
            Text("Zoom").font(.system(size: 10, weight: .semibold)).kerning(0.2)
        }
        .foregroundStyle(isLit ? VideoKit.Palette.ink : VideoKit.Palette.dim)
        .padding(.leading, indent + 12)
        .frame(width: TimelineDock.gutter, alignment: .leading)
    }

    /// Every zoom on the lane is picked.
    private var allPicked: Bool {
        let zooms = editorState.document?.layer(id: layerID)?.zooms ?? []
        return zooms.count > 1
            && zooms.allSatisfy { editorState.isZoomPicked(ClipZoomRef(layerID: layerID, zoomID: $0.id)) }
    }

    /// What it reads off the document (the clip's zooms) follows an edit a
    /// pass later, with the lanes (`readingALatePass`): read live, every zoom
    /// lane in sight was woken in the frame of every edit.
    var body: some View { readingALatePass { lateBody } }

    @ViewBuilder private var lateBody: some View {
        HStack(spacing: TimelineDock.gap) {
            Self.header(indent: indent, isLit: allPicked)
                .contentShape(Rectangle())
                .onTapGesture { editorState.pickAllZooms(onClip: layerID) }
                .help("Pick every zoom")
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Pick every zoom")
                .playtestControl("Zoom lane label", detail: "Timeline")
            ZoomBarsView(layerID: layerID, laneWidth: laneWidth, isLocked: isLocked)
        }
        .frame(height: Self.height)
        .playtestField("Zoom lane")
        // Where the lane is down the tracks, for a box drawn over them
        // (`EditorState+TrackRange`).
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(TimelineDock.tracksSpace))
        } action: { frame in
            if !isLifted { editorState.zoomLaneRows[layerID] = frame.minY...frame.maxY }
        }
        .onDisappear { if !isLifted { editorState.zoomLaneRows[layerID] = nil } }
    }

    // MARK: Where the bars go

    struct Bar {
        let zoom: ClipZoom
        let x: CGFloat
        let width: CGFloat
        let easeIn: CGFloat
        let easeOut: CGFloat
    }

    /// Where each zoom on the clip is across the lane, read where the bars
    /// are drawn and not in the lane, so the label beside them is not built
    /// again as the timeline scrolls. A lane none of whose zooms reach the
    /// rows' sight (`TimelineSight.rows`: the window and two more either
    /// side) has nothing in the window and does not read the window at all:
    /// the hour-long reference edit has 126 Zoom lanes, and each was built
    /// again on every frame of a scroll (2026-11-15).
    static func bars(_ editorState: EditorState, layerID: UUID, laneWidth: CGFloat) -> [Bar] {
        guard let layer = editorState.document?.layer(id: layerID) else { return [] }
        let spans = editorState.zoomsShown(onClip: layerID).compactMap { zoom in
            editorState.spanOnTimeline(zoom, of: layer).map { (zoom: zoom, span: $0) }
        }
        if editorState.motionStripMeasuresADocument, let sight = editorState.timelineRowsSight,
           !spans.contains(where: { sight.reaches(fromMS: Double($0.span.start), toMS: Double($0.span.end)) }) {
            return []
        }
        let ruler = editorState.motionStripRuler
        return spans.compactMap { zoom, span in
            let x0 = laneWidth * ruler.fraction(ofMS: Double(span.start))
            let x1 = laneWidth * ruler.fraction(ofMS: Double(span.end))
            guard x1 >= 0, x0 <= laneWidth, x1 > x0 else { return nil }
            let perMS = (x1 - x0) / CGFloat(max(1, zoom.lengthMS))
            let eases = zoom.eases
            return Bar(zoom: zoom, x: x0, width: x1 - x0,
                       easeIn: CGFloat(eases.inMS) * perMS, easeOut: CGFloat(eases.outMS) * perMS)
        }
    }

    /// The bar a press at `x` landed on.
    static func bar(at x: CGFloat, in bars: [Bar]) -> Bar? {
        bars.last { x >= $0.x - 2 && x <= $0.x + $0.width + 2 }
    }

    /// How close to a bar's end, or a ramp's handle, a press takes hold of it.
    static let grip: CGFloat = 5

    /// What a press at `x` on `bar` takes hold of.
    static func grab(at x: CGFloat, on bar: Bar) -> ZoomGrab {
        guard bar.width >= grip * 4 else { return .body }
        if x <= bar.x + grip { return .start }
        if x >= bar.x + bar.width - grip { return .end }
        if bar.easeIn >= grip, abs(x - (bar.x + bar.easeIn)) <= grip { return .easeIn }
        if bar.easeOut >= grip, abs(x - (bar.x + bar.width - bar.easeOut)) <= grip { return .easeOut }
        return .body
    }

    /// What the bar says: how far in, and that it follows when it does.
    static func label(_ zoom: ClipZoom) -> String {
        let percent = "\(EditorState.zoomPercent(zoom))%"
        return zoom.followsCursor ? "\(percent) Follow" : percent
    }
}

/// The bars themselves, painted, with the picked one lit.
private struct ZoomBarsView: View {
    @Environment(EditorState.self) private var editorState
    let layerID: UUID
    let laneWidth: CGFloat
    let isLocked: Bool

    private var bars: [ZoomLane.Bar] { ZoomLane.bars(editorState, layerID: layerID, laneWidth: laneWidth) }

    @State private var hovered: ZoomLane.Bar?
    @State private var pressed: (bar: ZoomLane.Bar, grab: ZoomGrab)?
    @State private var dragging = false
    /// A press between the bars, which is the timeline's box
    /// (`TimelineLaneMarquee`), not a zoom's.
    @State private var boxing = false

    private func isPicked(_ bar: ZoomLane.Bar) -> Bool {
        editorState.isZoomLit(ClipZoomRef(layerID: layerID, zoomID: bar.zoom.id))
    }

    /// Its right-click rows read the document: a pass late, with its lane.
    var body: some View { readingALatePass { lateBody } }

    @ViewBuilder private var lateBody: some View {
        let bars = self.bars
        let picked = Set(bars.filter(isPicked).map(\.zoom.id))
        Canvas { context, _ in
            for bar in bars {
                let isPicked = picked.contains(bar.zoom.id)
                let rect = CGRect(x: bar.x, y: ZoomLane.barTop, width: max(3, bar.width),
                                  height: ZoomLane.barHeight)
                let shape = Path(roundedRect: rect, cornerRadius: 5)
                context.fill(shape, with: .style(isPicked ? AnyShapeStyle(VideoKit.Palette.accent)
                                                          : AnyShapeStyle(VideoKit.Palette.glassThin)))
                // The ramps: the way in and out, lighter, so the hold reads as
                // the solid middle.
                context.drawLayer { inner in
                    inner.clip(to: shape)
                    let ramp = Color.white.opacity(isPicked ? 0.22 : 0.08)
                    inner.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: bar.easeIn, height: rect.height)),
                               with: .color(ramp))
                    inner.fill(Path(CGRect(x: rect.maxX - bar.easeOut, y: rect.minY,
                                           width: bar.easeOut, height: rect.height)),
                               with: .color(ramp))
                }
                // Picked bars keep a dark edge, so two picked side by side
                // still read as two bars rather than one long one.
                context.stroke(Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 4.5),
                               with: isPicked ? .color(.black.opacity(0.4)) : .style(VideoKit.Palette.edgeLo),
                               lineWidth: 1)
                // The two ramp handles.
                let handleInk = isPicked ? AnyShapeStyle(Color.white) : AnyShapeStyle(VideoKit.Palette.dim)
                for x in [rect.minX + bar.easeIn, rect.maxX - bar.easeOut]
                where bar.easeIn > 0 || bar.easeOut > 0 {
                    guard x > rect.minX + 2, x < rect.maxX - 2 else { continue }
                    context.fill(Path(roundedRect: CGRect(x: x - 1, y: rect.minY + 4, width: 2,
                                                          height: rect.height - 8), cornerRadius: 1),
                                 with: .style(handleInk))
                }
                let words = ZoomLane.label(bar.zoom)
                if bar.width - bar.easeIn - bar.easeOut >= CGFloat(words.count) * 6 + 8 {
                    let text = Text(words)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(isPicked ? AnyShapeStyle(Color.white) : AnyShapeStyle(VideoKit.Palette.ink))
                    context.draw(text, at: CGPoint(x: rect.minX + bar.easeIn + 6, y: rect.midY), anchor: .leading)
                }
            }
        }
        .frame(width: laneWidth, height: ZoomLane.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(press)
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point):
                hovered = ZoomLane.bar(at: point.x, in: bars)
                let grab = hovered.map { ZoomLane.grab(at: point.x, on: $0) }
                switch grab {
                case .start?, .end?, .easeIn?, .easeOut?: NSCursor.resizeLeftRight.set()
                default: NSCursor.arrow.set()
                }
            case .ended:
                hovered = nil
                NSCursor.arrow.set()
            }
        }
        // Handed the bars this build already worked out: the menu's builder
        // runs with every build, and working them out again for it was a
        // third of a Zoom lane's cost on a zoom of the hour-long edit.
        .contextMenu { menu(bars) }
        .help(hovered.map { ZoomLane.label($0.zoom) } ?? "")
        .clipped()
        .accessibilityElement()
        .accessibilityLabel("Zoom")
        .accessibilityValue(picked.count > 1 ? "\(picked.count) picked"
            : bars.first { picked.contains($0.zoom.id) }.map { ZoomLane.label($0.zoom) } ?? "")
        .playtestControl("Zoom lane", detail: "Timeline")
    }

    private var press: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if pressed == nil, !boxing {
                    guard let bar = ZoomLane.bar(at: value.startLocation.x, in: bars) else {
                        boxing = true
                        return box(value)
                    }
                    pressed = (bar, ZoomLane.grab(at: value.startLocation.x, on: bar))
                }
                if boxing { return box(value) }
                guard let pressed, !isLocked else { return }
                let ref = ClipZoomRef(layerID: layerID, zoomID: pressed.bar.zoom.id)
                if !dragging {
                    guard abs(value.translation.width) >= 3 else { return }
                    dragging = true
                    editorState.beginZoomDrag(ref, grab: pressed.grab)
                }
                let ms = Int(editorState.motionStripRuler.msSpanning(
                    fraction: Double(value.translation.width / max(1, laneWidth))).rounded())
                // Plus however far the timeline has scrolled under the hand
                // at an edge (`TimelineEdgeScroll`).
                editorState.updateZoomDrag(byMS: ms + editorState.timelineEdgePannedMS)
                editorState.zoomDragHand(laneX: value.location.x, handMS: ms)
            }
            .onEnded { value in
                defer {
                    pressed = nil
                    dragging = false
                    boxing = false
                }
                guard let pressed else {
                    // A press on the empty lane is a press on empty timeline
                    // space: a click puts the playhead there and lets go of
                    // what is picked, a drag draws a box.
                    if boxing || ZoomLane.bar(at: value.startLocation.x, in: bars) == nil {
                        if !boxing { box(value) }
                        TimelineLaneMarquee.ended(editorState, value, leading: 0,
                                                  ruler: editorState.motionStripRuler, laneWidth: laneWidth)
                    }
                    return
                }
                if dragging {
                    editorState.commitZoomDrag()
                } else {
                    // The playhead to the moment clicked
                    // (`EditorState+TimelinePointing`), BEFORE the pick: a
                    // playhead moving puts a framed zoom's box away, and the
                    // pick is what puts it up.
                    editorState.playheadToTimelineClick(laneX: value.startLocation.x, laneWidth: laneWidth)
                    let ref = ClipZoomRef(layerID: layerID, zoomID: pressed.bar.zoom.id)
                    let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
                    if flags.contains(.shift) || flags.contains(.command) {
                        editorState.togglePickedZoom(ref)
                    } else {
                        editorState.pickZoom(ref)
                    }
                }
            }
    }

    /// Hand a press between the bars to the timeline's box.
    private func box(_ value: DragGesture.Value) {
        TimelineLaneMarquee.changed(editorState, value, top: editorState.zoomLaneRows[layerID]?.lowerBound ?? 0,
                                    leading: 0, ruler: editorState.motionStripRuler, laneWidth: laneWidth)
    }

    /// The bar a right click is about: the one it landed on, else the one
    /// under the pointer, else the picked one, else the only one.
    private func menuBar(_ bars: [ZoomLane.Bar]) -> ZoomLane.Bar? {
        if let pressed = rightPressedBar(bars) { return pressed }
        if let hovered { return hovered }
        let picked = editorState.selectedZoom?.layerID == layerID ? editorState.selectedZoom?.zoomID : nil
        return bars.first { $0.zoom.id == picked } ?? (bars.count == 1 ? bars.first : nil)
    }

    /// The bar under the moment a right click on the tracks just landed on
    /// (`EditorState+TimelinePointing`).
    private func rightPressedBar(_ bars: [ZoomLane.Bar]) -> ZoomLane.Bar? {
        guard let ms = editorState.timelineRightPressMS else { return nil }
        let x = laneWidth * editorState.motionStripRuler.fraction(ofMS: Double(ms))
        return ZoomLane.bar(at: x, in: bars)
    }

    @ViewBuilder private func menu(_ bars: [ZoomLane.Bar]) -> some View {
        // Built afresh for every right click.
        let _ = editorState.timelineRightPresses
        let pressed = rightPressedBar(bars)
        if let bar = pressed ?? menuBar(bars) {
            let ref = ClipZoomRef(layerID: layerID, zoomID: bar.zoom.id)
            // Only a bar the click landed on is picked by it.
            let _ = pressed != nil ? editorState.timelineMenuBuilt(for: .zoom(ref)) : ()
            MenuRowsView(rows: editorState.zoomMenuRows(ref))
        }
    }
}
