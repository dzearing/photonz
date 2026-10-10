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

    var body: some View {
        HStack(spacing: TimelineDock.gap) {
            Self.header(indent: indent, isLit: allPicked)
                .contentShape(Rectangle())
                .onTapGesture { editorState.pickAllZooms(onClip: layerID) }
                .help("Pick every zoom")
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Pick every zoom")
                .playtestControl("Zoom lane label", detail: "Timeline")
            ZoomBarsView(layerID: layerID, bars: bars, laneWidth: laneWidth, isLocked: isLocked)
        }
        .frame(height: Self.height)
        .playtestField("Zoom lane")
    }

    // MARK: Where the bars go

    struct Bar {
        let zoom: ClipZoom
        let x: CGFloat
        let width: CGFloat
        let easeIn: CGFloat
        let easeOut: CGFloat
    }

    private var bars: [Bar] {
        guard let layer = editorState.document?.layer(id: layerID) else { return [] }
        let ruler = editorState.motionStripRuler
        return editorState.zoomsShown(onClip: layerID).compactMap { zoom in
            guard let span = editorState.spanOnTimeline(zoom, of: layer) else { return nil }
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
    let bars: [ZoomLane.Bar]
    let laneWidth: CGFloat
    let isLocked: Bool

    @State private var hovered: ZoomLane.Bar?
    @State private var pressed: (bar: ZoomLane.Bar, grab: ZoomGrab)?
    @State private var dragging = false

    private func isPicked(_ bar: ZoomLane.Bar) -> Bool {
        editorState.isZoomPicked(ClipZoomRef(layerID: layerID, zoomID: bar.zoom.id))
    }

    var body: some View {
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
        .contextMenu { menu }
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
                if pressed == nil {
                    guard let bar = ZoomLane.bar(at: value.startLocation.x, in: bars) else { return }
                    pressed = (bar, ZoomLane.grab(at: value.startLocation.x, on: bar))
                }
                guard let pressed, !isLocked else { return }
                let ref = ClipZoomRef(layerID: layerID, zoomID: pressed.bar.zoom.id)
                if !dragging {
                    guard abs(value.translation.width) >= 3 else { return }
                    dragging = true
                    editorState.beginZoomDrag(ref, grab: pressed.grab)
                }
                let ms = editorState.motionStripRuler.msSpanning(
                    fraction: Double(value.translation.width / max(1, laneWidth)))
                editorState.updateZoomDrag(byMS: Int(ms.rounded()))
            }
            .onEnded { value in
                defer {
                    pressed = nil
                    dragging = false
                }
                guard let pressed else {
                    // A press on the empty lane lets the picked zoom go.
                    if ZoomLane.bar(at: value.startLocation.x, in: bars) == nil { editorState.letGoOfZoom() }
                    return
                }
                if dragging {
                    editorState.commitZoomDrag()
                } else {
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

    /// The bar a right click is about: the one under the pointer, else the
    /// picked one, else the only one.
    private var menuBar: ZoomLane.Bar? {
        if let hovered { return hovered }
        let picked = editorState.selectedZoom?.layerID == layerID ? editorState.selectedZoom?.zoomID : nil
        return bars.first { $0.zoom.id == picked } ?? (bars.count == 1 ? bars.first : nil)
    }

    @ViewBuilder private var menu: some View {
        if let bar = menuBar {
            MenuRowsView(rows: editorState.zoomMenuRows(ClipZoomRef(layerID: layerID, zoomID: bar.zoom.id)))
        }
    }
}
