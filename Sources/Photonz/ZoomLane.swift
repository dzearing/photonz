import AppKit
import PhotonzCore
import QuartzCore
import SwiftUI

/// **Zoom**: the one lane under a track whose recordings have zooms on them,
/// one bar per zoom (`ClipZoom.swift`, `EditorState+Zoom`). Every zoomed clip
/// on the track shares it: a clip's zooms stay inside the clip and the clips
/// on a track sit side by side, so the bars do too, and an hour-long edit with
/// a zoom on every other clip reads as one row rather than a row per clip
/// (126 of them on the reference edit until 2026-11-18).
///
/// A bar is the stretch the zoom is on; the lighter ends are its way in and
/// out, and the small upright mark where each ramp meets the hold is a handle
/// that drags the ramp longer or shorter. A press on the bar picks it, its two
/// ends trim it, its middle carries it, and a right click has Follow Cursor,
/// how far in, and Delete Zoom. Shift or Command click adds a bar to the pick
/// or takes it out, and a click on the lane's "Zoom" label picks every bar on
/// it, whichever clip each is on, so a change in the panel or the menus reaches all of them at once.
/// Screen Studio's zoom track, laid out the way the Words lane is.
struct ZoomLane: View {
    @Environment(EditorState.self) private var editorState
    /// The clips on the track that have zooms, in the track's order.
    let clipIDs: [UUID]
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
        let refs = clipIDs.flatMap { id in
            (editorState.document?.layer(id: id)?.zooms ?? []).map { ClipZoomRef(layerID: id, zoomID: $0.id) }
        }
        return refs.count > 1 && refs.allSatisfy(editorState.isZoomPicked)
    }

    /// What it reads off the document (the clip's zooms) follows an edit a
    /// pass later, with the lanes (`readingALatePass`): read live, every zoom
    /// lane in sight was woken in the frame of every edit.
    var body: some View { readingALatePass { lateBody } }

    @ViewBuilder private var lateBody: some View {
        // Built only near the part of the tracks on screen: when the
        // hour-long reference edit had a Zoom lane per zoomed clip, 126 of
        // them, a header, bars and grips for every one held the main thread
        // for a fifth of a second as the window opened (2026-11-16). Out of
        // sight it is an empty row of the same height, so nothing below it
        // moves.
        BuiltNearSight(height: Self.height) {
            lane.playtestField("Zoom lane")
        }
        // Where the lane is down the tracks, for a box drawn over them
        // (`EditorState+TrackRange`), built or not: written for each clip on
        // it, since a box and a right click ask by clip.
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(TimelineDock.tracksSpace))
        } action: { frame in
            guard !isLifted else { return }
            for id in clipIDs { editorState.zoomLaneRows[id] = frame.minY...frame.maxY }
        }
        .onChange(of: clipIDs) { old, new in
            guard !isLifted else { return }
            let row = old.lazy.compactMap { editorState.zoomLaneRows[$0] }.first
            for id in Set(old).subtracting(new) { editorState.zoomLaneRows[id] = nil }
            if let row { for id in new { editorState.zoomLaneRows[id] = row } }
        }
        .onDisappear {
            guard !isLifted else { return }
            for id in clipIDs { editorState.zoomLaneRows[id] = nil }
        }
    }

    private var lane: some View {
        HStack(spacing: TimelineDock.gap) {
            Self.header(indent: indent, isLit: allPicked)
                .contentShape(Rectangle())
                .onTapGesture { editorState.pickAllZooms(onClips: clipIDs) }
                .help("Pick every zoom")
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Pick every zoom")
                .playtestControl("Zoom lane label", detail: "Timeline")
            ZoomBarsView(clipIDs: clipIDs, laneWidth: laneWidth, isLocked: isLocked)
        }
    }

    // MARK: Where the bars go

    struct Bar {
        /// The clip the zoom is on.
        let layerID: UUID
        let zoom: ClipZoom
        let x: CGFloat
        let width: CGFloat
        let easeIn: CGFloat
        let easeOut: CGFloat

        var ref: ClipZoomRef { ClipZoomRef(layerID: layerID, zoomID: zoom.id) }
    }

    /// Where each zoom on the lane's clips is across the lane, read where the
    /// bars are drawn and not in the lane, so the label beside them is not
    /// built again as the timeline scrolls. A lane none of whose zooms reach
    /// the rows' sight (`TimelineSight.rows`: the window and two more either
    /// side) has nothing in the window and does not read the window at all
    /// (docs/design/video.md 8f rule 9): when every zoomed clip had a lane of
    /// its own, the hour-long reference edit's 126 were each built again on
    /// every frame of a scroll (2026-11-15).
    static func bars(_ editorState: EditorState, clipIDs: [UUID], laneWidth: CGFloat,
                     spans kept: Spans? = nil) -> [Bar] {
        guard let document = editorState.document else { return [] }
        // Where each zoom is in time, kept until a layer is written or a
        // hand holds a zoom, a clip or a box (each shows the zooms where the
        // hand has them): only where that falls across the lane changes as
        // the window moves. Worked out afresh on every frame, the zooms of
        // the hour-long reference edit's one Zoom lane were about 0.3 ms of
        // each frame of a scroll (2026-11-19).
        let inHand = editorState.zoomDrag != nil || editorState.clipBarDrag != nil
            || editorState.boxExtrasDrag != nil
        let spans = kept.flatMap { inHand ? nil : $0.spans(clipIDs, in: document) }
            ?? clipIDs.flatMap { id -> [Spans.Span] in
                guard let layer = document.layer(id: id) else { return [] }
                return editorState.zoomsShown(onClip: id).compactMap { zoom in
                    editorState.spanOnTimeline(zoom, of: layer).map { (layerID: id, zoom: zoom, span: $0) }
                }
            }
        if !inHand { kept?.keep(spans, clipIDs, for: document) }
        if editorState.motionStripMeasuresADocument, let sight = editorState.timelineRowsSight,
           !spans.contains(where: { sight.reaches(fromMS: Double($0.span.start), toMS: Double($0.span.end)) }) {
            return []
        }
        let ruler = editorState.motionStripRuler
        return spans.compactMap { layerID, zoom, span in
            let x0 = laneWidth * ruler.fraction(ofMS: Double(span.start))
            let x1 = laneWidth * ruler.fraction(ofMS: Double(span.end))
            guard x1 >= 0, x0 <= laneWidth, x1 > x0 else { return nil }
            let perMS = (x1 - x0) / CGFloat(max(1, zoom.lengthMS))
            let eases = zoom.eases
            return Bar(layerID: layerID, zoom: zoom, x: x0, width: x1 - x0,
                       easeIn: CGFloat(eases.inMS) * perMS, easeOut: CGFloat(eases.outMS) * perMS)
        }
    }

    /// Where a lane's zooms are in time, kept for one document
    /// (`PhotonzDocument.sharesWorkedOutAnswers`).
    final class Spans {
        typealias Span = (layerID: UUID, zoom: ClipZoom, span: (start: Int, end: Int))
        private var document: PhotonzDocument?
        private var clipIDs: [UUID] = []
        private var kept: [Span] = []

        func spans(_ clipIDs: [UUID], in document: PhotonzDocument) -> [Span]? {
            guard let held = self.document, held.sharesWorkedOutAnswers(with: document),
                  self.clipIDs == clipIDs else { return nil }
            return kept
        }

        func keep(_ spans: [Span], _ clipIDs: [UUID], for document: PhotonzDocument) {
            self.document = document
            self.clipIDs = clipIDs
            kept = spans
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
    let clipIDs: [UUID]
    let laneWidth: CGFloat
    let isLocked: Bool

    private var bars: [ZoomLane.Bar] {
        ZoomLane.bars(editorState, clipIDs: clipIDs, laneWidth: laneWidth, spans: spans)
    }
    /// Where the zooms are in time, between frames (`ZoomLane.Spans`).
    @State private var spans = ZoomLane.Spans()

    @State private var hovered: ZoomLane.Bar?
    @State private var pressed: (bar: ZoomLane.Bar, grab: ZoomGrab)?
    @State private var dragging = false
    /// A press between the bars, which is the timeline's box
    /// (`TimelineLaneMarquee`), not a zoom's.
    @State private var boxing = false

    private func isPicked(_ bar: ZoomLane.Bar) -> Bool {
        editorState.isZoomLit(bar.ref)
    }

    /// Whether the lane is in the tracks' view, or near enough to scroll in
    /// (`TimelineSight.rowShows`). Out of it the lane draws and reads
    /// nothing, so a zoom along time leaves it alone: when the hour-long
    /// reference edit had 126 Zoom lanes, a handful on screen, every one was
    /// drawn again on each frame of a zoom, about 8 ms a frame however far in
    /// (2026-11-16).
    @State private var showsDownTheTracks = true

    /// Its right-click rows read the document: a pass late, with its lane.
    var body: some View {
        Group {
            if showsDownTheTracks {
                readingALatePass { lateBody }
            } else {
                Color.clear.frame(width: laneWidth, height: ZoomLane.height)
            }
        }
        .onGeometryChange(for: Bool.self) { proxy in
            let view = proxy.bounds(of: .scrollView).map { $0.minY...max($0.minY, $0.maxY) }
            return TimelineSight.rowShows(minY: 0, maxY: proxy.size.height, in: view)
        } action: { showsDownTheTracks = $0 }
    }

    @ViewBuilder private var lateBody: some View {
        let bars = self.bars
        let picked = Set(bars.filter(isPicked).map(\.ref))
        Canvas { context, _ in
            for bar in bars {
                let isPicked = picked.contains(bar.ref)
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
            : bars.first { picked.contains($0.ref) }.map { ZoomLane.label($0.zoom) } ?? "")
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
                let ref = pressed.bar.ref
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
                    let ref = pressed.bar.ref
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
        TimelineLaneMarquee.changed(editorState, value, top: clipIDs.first.flatMap { editorState.zoomLaneRows[$0]?.lowerBound } ?? 0,
                                    leading: 0, ruler: editorState.motionStripRuler, laneWidth: laneWidth)
    }

    /// The bar a right click is about: the one it landed on, else the one
    /// under the pointer, else the picked one, else the only one.
    private func menuBar(_ bars: [ZoomLane.Bar]) -> ZoomLane.Bar? {
        if let pressed = rightPressedBar(bars) { return pressed }
        if let hovered { return hovered }
        let picked = editorState.selectedZoom
        return bars.first { $0.ref == picked } ?? (bars.count == 1 ? bars.first : nil)
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
            let ref = bar.ref
            // Only a bar the click landed on is picked by it.
            let _ = pressed != nil ? editorState.timelineMenuBuilt(for: .zoom(ref)) : ()
            MenuRowsView(rows: editorState.zoomMenuRows(ref))
        }
    }
}

/// A row of the timeline's tracks built only while it is within a screen's
/// height of the part of the tracks on screen, and an empty row of the same
/// height the rest of the time, so a long edit's rows far down the list cost
/// nothing to open, lay out or read aloud. Outside a scroller it is always
/// built.
struct BuiltNearSight<Content: View>: View {
    let height: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var isNear = false

    var body: some View {
        Group {
            if isNear { content() } else { Color.clear }
        }
        .frame(height: height)
        .onGeometryChange(for: Bool.self) { proxy in
            guard let shown = proxy.bounds(of: .scrollView) else { return true }
            return Self.isNear(CGRect(origin: .zero, size: proxy.size), shown: shown)
        } action: { isNear = $0 }
    }

    /// Whether a row at `row` is within a screen's height of `shown`, the
    /// scroller's visible stretch, both in the row's own space.
    static func isNear(_ row: CGRect, shown: CGRect) -> Bool {
        let reach = max(shown.height, 1)
        return row.maxY >= shown.minY - reach && row.minY <= shown.maxY + reach
    }
}
