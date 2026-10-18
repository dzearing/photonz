import AppKit
import PhotonzCore
import SwiftUI

/// **Speed curve**: the lane under a clip with speed stops, plotting how fast
/// it plays on its own clock (`docs/design/mocks/pages/video-speed.html`, the
/// timeline dock's `.schdr`, `.scbody`, `.scaxis` and `.scplot`).
///
/// The mock's scale in the gutter (3x, 1x, 0, each at its own height), the
/// plot under the clip's bar with a grid line per whole speed and the 1x line
/// dashed, the line in the mock's cyan, and the speed bands under it tinted as
/// the mock's legend tints them: Slow-mo, Normal, Fast, and Freeze hatched in
/// amber. A diamond on every stop drags along and up and down at once; a
/// freeze's second zero drags along to make the hold longer or shorter. The
/// line follows the one rule every animated line follows (`AnimatedLine`): a
/// click picks, a Command-click adds a stop, and a right click on a stretch
/// offers Ramp and Hold.
///
/// It opens and closes with the track's arrow, like the key lanes, and a clip
/// with no stops has no lane at all.
struct SpeedCurveLane: View {
    @Environment(EditorState.self) private var editorState
    @Environment(\.colorScheme) private var colorScheme
    let layerID: UUID
    let layerName: String
    let laneWidth: CGFloat
    var indent: CGFloat = 0
    var isLocked = false
    /// The copy drawn lifted while its track is carried.
    var isLifted = false

    /// The mock's narrow `.scplot` (104px), and room above and below it.
    static let plotHeight: CGFloat = 104
    static let height: CGFloat = plotHeight + 6
    /// The band strip along the plot's floor, in the legend's swatches.
    static let stripHeight: CGFloat = 6
    /// Room so a diamond at 3x or at nought is drawn whole.
    static let topInset: CGFloat = 9
    static let bottomInset: CGFloat = 9
    static let diamondSize: CGFloat = 12
    static let cornerRadius: CGFloat = 8

    private static let cyan = VideoKit.rgb(0x12C2E9)
    private static let amber = VideoKit.rgb(0xFEBC2E)
    private static let amberDeep = VideoKit.rgb(0xC98F18)
    private static let space = "speed curve"

    /// Where the plot is in the window, for a walk to read its ink.
    @State private var plotFrame: CGRect = .zero
    /// Where the stop in the hand was when it was taken.
    @State private var grabbedAt: CGPoint?
    /// Where the pointer rests on the line, brightened a little.
    @State private var hovered: AnimatedLineHit?
    /// Where the lane is down the tracks, so a right click's height says
    /// whether it landed on this row.
    @State private var frameInTracks: CGRect = .zero

    var body: some View {
        if let curve = editorState.speedCurve(layerID: layerID), let span = clipSpan {
            HStack(alignment: .top, spacing: TimelineDock.gap) {
                gutter
                plot(curve, span: span)
                    .frame(width: laneWidth, height: Self.plotHeight)
                    .clipped()
            }
            .padding(.vertical, 3)
            .frame(height: Self.height)
            .playtestField("Speed curve \(layerName)")
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(TimelineDock.tracksSpace))
            } action: { frameInTracks = $0 }
        }
    }

    // MARK: The gutter: its name and the mock's scale

    private var gutter: some View {
        ZStack(alignment: .topLeading) {
            HStack(spacing: 5) {
                Image(systemName: "gauge.with.dots.needle.67percent").font(.system(size: 9, weight: .semibold))
                Text("Speed curve").font(.system(size: 10, weight: .semibold)).kerning(0.2)
                    .lineLimit(1).truncationMode(.tail)
            }
            .foregroundStyle(VideoKit.Palette.dim)
            .padding(.leading, indent + 12)
            .padding(.trailing, 26)
            .frame(width: TimelineDock.gutter, alignment: .leading)
            .offset(y: Self.y(forSpeed: 2) - 6)
            ForEach(Array(zip(SpeedCurve.scale, [3.0, 1.0, 0.0])), id: \.0) { label, speed in
                Text(label)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(VideoKit.Palette.faint)
                    .frame(width: TimelineDock.gutter - 4, alignment: .trailing)
                    .position(x: (TimelineDock.gutter - 4) / 2, y: Self.y(forSpeed: speed))
            }
        }
        .frame(width: TimelineDock.gutter, height: Self.plotHeight, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    // MARK: The plot

    private func plot(_ curve: SpeedCurve, span: (inMS: Int, outMS: Int)) -> some View {
        let geometry = PlotGeometry(ruler: editorState.motionStripRuler, laneWidth: laneWidth,
                                    inMS: span.inMS, outMS: span.outMS)
        let animated = animatedLine(curve, geometry)
        return ZStack(alignment: .topLeading) {
            background(geometry)
            drawing(curve, geometry)
            surface(curve, animated, geometry)
            playheadDot(curve, geometry)
            ForEach(Array(curve.handles.enumerated()), id: \.offset) { index, handle in
                let x = geometry.x(atClipMS: handle.timelineMS)
                if x >= -Self.diamondSize, x <= laneWidth + Self.diamondSize {
                    diamond(handle, number: index + 1, curve: curve, geometry: geometry)
                }
            }
            if let session = editorState.speedStopDrag, session.layerID == layerID {
                readout(session, curve: curve, geometry: geometry)
            }
        }
        .coordinateSpace(.named(Self.space))
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let at): hovered = animated.hit(at)
            case .ended: hovered = nil
            }
        }
        #if PHOTONZ_PLAYTEST
        // What was drawn, written down every time it is drawn (a register
        // the views never read, so writing it here wakes nothing), and where.
        .background {
            let _ = DrawnSpeedCurves.shared.showing(layerID, DrawnSpeedCurves.Curve(
                laneFrame: plotFrame,
                bands: curve.bands.map { ($0.band, geometry.x(atClipMS: $0.startMS), geometry.x(atClipMS: $0.endMS)) },
                strip: (Self.plotHeight - Self.stripHeight)...Self.plotHeight,
                oneX: Self.y(forSpeed: 1),
                plot: geometry.visible))
            Color.clear
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            plotFrame = frame
            DrawnSpeedCurves.shared.moved(layerID, to: frame)
        }
        .onDisappear { DrawnSpeedCurves.shared.gone(layerID) }
        #endif
    }

    /// The mock's `.scplot`: the panel's raised tone with a hairline edge,
    /// under the clip's bar only. A click on it is a click on the clip.
    private func background(_ geometry: PlotGeometry) -> some View {
        let rect = geometry.plotRect(height: Self.plotHeight)
        return RoundedRectangle(cornerRadius: Self.cornerRadius)
            .fill(VideoKit.Palette.panel2)
            .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius).strokeBorder(VideoKit.Palette.edgeLo, lineWidth: 1))
            .frame(width: max(1, rect.width), height: rect.height)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { at in
                plotClick(atClipMS: geometry.clipMS(atX: rect.minX + at.x))
            }
            .contextMenu {
                let _ = editorState.timelineRightPresses
                BuiltAsItOpens { TimelineClipMenu(layerID: layerID, piece: pieceAtRightPress) }
            }
            .playtestControl("Speed curve plot \(layerName)", detail: layerName)
            .offset(x: rect.minX)
            .panelHelp("How fast the clip plays. Drag a stop; Command-click the line to add one.")
    }

    /// Bands, grid, and the line, in one pass.
    private func drawing(_ curve: SpeedCurve, _ geometry: PlotGeometry) -> some View {
        let scheme = colorScheme
        let hoveredSegment: Int? = if case let .segment(index) = hovered { index } else { nil }
        return Canvas { context, size in
            let rect = geometry.plotRect(height: size.height)
            guard rect.width > 0 else { return }
            context.clip(to: Path(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: Self.cornerRadius - 1))
            let line = curve.points.map { CGPoint(x: geometry.x(atClipMS: $0.timelineMS), y: Self.y(forSpeed: $0.speed)) }
            let floor = Self.y(forSpeed: 0)
            let stripTop = size.height - Self.stripHeight
            // The bands: a wash under the line, and the legend's swatch along
            // the floor.
            for run in curve.bands {
                let x0 = max(rect.minX, geometry.x(atClipMS: run.startMS))
                let x1 = min(rect.maxX, geometry.x(atClipMS: run.endMS))
                guard x1 > x0 else { continue }
                let column = CGRect(x: x0, y: 0, width: x1 - x0, height: size.height)
                var under = Path()
                if let first = line.first {
                    under.move(to: CGPoint(x: first.x, y: floor))
                    for point in line { under.addLine(to: point) }
                    if let last = line.last { under.addLine(to: CGPoint(x: last.x, y: floor)) }
                    under.closeSubpath()
                }
                var wash = context
                wash.clip(to: Path(column))
                wash.fill(under, with: .color(Self.color(run.band).opacity(0.22)))
                let strip = CGRect(x: x0, y: stripTop, width: x1 - x0, height: Self.stripHeight)
                if run.band == .freeze {
                    Self.hatch(strip, in: &context)
                } else {
                    context.fill(Path(strip), with: .color(Self.color(run.band)))
                }
            }
            // A grid line at every whole speed, the 1x line dashed in cyan.
            for speed in [0.0, 1, 2, 3] {
                let y = Self.y(forSpeed: speed).rounded() + 0.5
                var path = Path()
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
                if speed == 1 {
                    context.stroke(path, with: .color(Self.cyan.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                } else {
                    context.stroke(path, with: .color(Color.gray.opacity(scheme == .dark ? 0.16 : 0.22)), lineWidth: 1)
                }
            }
            // The line.
            var path = Path()
            if let first = line.first {
                path.move(to: first)
                for point in line.dropFirst() { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(Self.cyan), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            if let hoveredSegment {
                let handles = curve.handles
                if handles.indices.contains(hoveredSegment + 1) {
                    let a = handles[hoveredSegment].timelineMS, b = handles[hoveredSegment + 1].timelineMS
                    var lit = Path()
                    let stretch = line.enumerated().filter {
                        curve.points[$0.offset].timelineMS >= a && curve.points[$0.offset].timelineMS <= b
                    }.map(\.element)
                    if let first = stretch.first {
                        lit.move(to: first)
                        for point in stretch.dropFirst() { lit.addLine(to: point) }
                    }
                    context.stroke(lit, with: .color(Self.cyan.mix(with: .white, by: 0.45)),
                                   style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// The mock's freeze swatch: amber stripes at 45 degrees, three points
    /// each.
    private static func hatch(_ rect: CGRect, in context: inout GraphicsContext) {
        context.fill(Path(rect), with: .color(amberDeep))
        var stripes = context
        stripes.clip(to: Path(rect))
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            path.addLine(to: CGPoint(x: x + rect.height + 3 * 1.4142, y: rect.minY))
            path.addLine(to: CGPoint(x: x + 3 * 1.4142, y: rect.maxY))
            path.closeSubpath()
            x += 6 * 1.4142
        }
        stripes.fill(path, with: .color(amber))
    }

    // MARK: The line as something to click

    private func surface(_ curve: SpeedCurve, _ animated: AnimatedLine, _ geometry: PlotGeometry) -> some View {
        AnimatedLineSurface(
            line: animated, width: laneWidth, height: Self.plotHeight,
            rightPress: { nil },
            click: { lineClick($0, animated, curve, geometry) },
            drag: DragGesture(minimumDistance: 4).onChanged { _ in },
            beyondMenu: { TimelineClipMenu(layerID: layerID, piece: pieceAtRightPress) },
            segmentMenu: { index, _ in
                if let piece = Self.piece(ofSegment: index, in: curve) {
                    blendMenu(piece: piece)
                }
            })
    }

    @ViewBuilder
    private func blendMenu(piece: Int) -> some View {
        let blend = editorState.document?.layer(id: layerID)?.clipPieces?.piece(at: piece)?.speedRamp?.blend
        ForEach(SpeedRampBlend.allCases, id: \.self) { option in
            Toggle(option.title, isOn: Binding(get: { blend == option },
                                               set: { _ in editorState.setRampBlend(layerID: layerID, piece: piece, option) }))
        }
        Divider()
        Button(SpeedStopNames.reset) {
            editorState.selectClipPiece(layerID: layerID, index: piece)
            editorState.resetRampInHand()
        }
    }

    private func lineClick(_ at: CGPoint, _ animated: AnimatedLine, _ curve: SpeedCurve, _ geometry: PlotGeometry) {
        let flags = KeyClick.flags
        guard !flags.contains(.control), !isLocked else { return }
        switch AnimatedLine.action(for: animated.hit(at), command: flags.contains(.command),
                                   shift: flags.contains(.shift)) {
        case let .pickDot(index, _):
            guard curve.handles.indices.contains(index) else { return }
            let handle = curve.handles[index]
            editorState.pickSpeedStopOnCurve(layerID: layerID, piece: handle.piece, stop: handle.stop)
        case .pickSegment:
            plotClick(atClipMS: geometry.clipMS(atX: at.x))
        case .addDot:
            editorState.addSpeedStopOnCurve(layerID: layerID,
                                            atClipMS: Int(geometry.clipMS(atX: animated.nearestPoint(to: at).x).rounded()))
        case .clear:
            plotClick(atClipMS: geometry.clipMS(atX: at.x))
        }
    }

    /// A click off the stops: the clip picked and the playhead there, as a
    /// click anywhere on a clip's lanes does.
    private func plotClick(atClipMS ms: Double) {
        if KeyClick.flags.contains(.command), !isLocked {
            editorState.addSpeedStopOnCurve(layerID: layerID, atClipMS: Int(ms.rounded()))
            return
        }
        editorState.pickedSpeedStop = nil
        editorState.clearKeySelection()
        editorState.selectLayer(layerID)
        if let inMS = editorState.document?.layer(id: layerID)?.time?.inMS {
            editorState.playheadToTimelineClick(atMS: inMS + Int(ms.rounded()))
        }
    }

    /// The line as the shared rule sees it: a dot on every handle, the drawn
    /// line between each two, and the line either side.
    private func animatedLine(_ curve: SpeedCurve, _ geometry: PlotGeometry) -> AnimatedLine {
        func at(_ point: SpeedCurve.Point) -> CGPoint {
            CGPoint(x: geometry.x(atClipMS: point.timelineMS), y: Self.y(forSpeed: point.speed))
        }
        let handles = curve.handles
        let dots = handles.map { CGPoint(x: geometry.x(atClipMS: $0.timelineMS), y: Self.y(forSpeed: $0.speed)) }
        let segments: [[CGPoint]] = zip(handles, handles.dropFirst()).map { a, b in
            curve.points.filter { $0.timelineMS >= a.timelineMS && $0.timelineMS <= b.timelineMS }.map(at)
        }
        guard let first = handles.first, let last = handles.last else {
            return AnimatedLine(dots: [], segments: [], before: curve.points.map(at))
        }
        let before = curve.points.filter { $0.timelineMS <= first.timelineMS }.map(at)
        let after = curve.points.filter { $0.timelineMS >= last.timelineMS }.map(at)
        return AnimatedLine(dots: dots, segments: segments, before: before, after: after)
    }

    /// The piece both ends of a stretch are on, nil for a stretch across a cut.
    private static func piece(ofSegment index: Int, in curve: SpeedCurve) -> Int? {
        let handles = curve.handles
        guard handles.indices.contains(index + 1), handles[index].piece == handles[index + 1].piece else { return nil }
        return handles[index].piece
    }

    // MARK: A stop

    private func diamond(_ handle: SpeedCurve.Handle, number: Int, curve: SpeedCurve,
                         geometry: PlotGeometry) -> some View {
        let isPicked = editorState.isSpeedStopPicked(layerID: layerID, piece: handle.piece, stop: handle.stop)
            && handle.kind == .stop
        let isFreeze = handle.speed == 0
        let size = isPicked ? Self.diamondSize + 2 : Self.diamondSize
        let fill: AnyShapeStyle = isPicked ? AnyShapeStyle(VideoKit.Palette.warn)
            : AnyShapeStyle(isFreeze ? Self.amber : Self.cyan)
        let hoveredDot: Bool = if case let .dot(index) = hovered { index == number - 1 } else { false }
        // Named by the stop, counting from one along its piece, so a stop
        // keeps its name when a freeze beside it grows a second zero.
        let piece = handle.piece > 0 ? " piece \(handle.piece + 1)" : ""
        let name = (handle.kind == .holdEnd ? "Speed hold end \(handle.stop + 1)" : "Speed stop \(handle.stop + 1)")
            + piece + " \(layerName)"
        let words = handle.kind == .holdEnd
            ? "freeze holds to \(EditorState.timecode(ms: Int(handle.timelineMS)))"
            : SpeedStopNames.speedTitle(Int((handle.speed * 100).rounded()))
                + " at \(EditorState.timecode(ms: Int(handle.timelineMS)))"
        return RoundedRectangle(cornerRadius: 2)
            .fill(fill)
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(VideoKit.Palette.panel, lineWidth: 1.5))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(45))
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
            .background {
                if isPicked {
                    Circle().fill(VideoKit.Palette.warn.color(colorScheme).opacity(0.26)).frame(width: size + 8, height: size + 8)
                }
            }
            .brightness(hoveredDot && !isPicked ? 0.12 : 0)
            .frame(width: Self.diamondSize + 6, height: Self.diamondSize + 6)
            .contentShape(Rectangle())
            .gesture(drag(handle, geometry: geometry))
            .onTapGesture {
                guard !KeyClick.flags.contains(.control) else { return }
                editorState.pickSpeedStopOnCurve(layerID: layerID, piece: handle.piece, stop: handle.stop)
            }
            .contextMenu {
                let _ = editorState.timelineRightPresses
                BuiltAsItOpens { stopMenu(handle) }
            }
            .playtestControl(name, detail: layerName)
            .panelReadout("\(name.lowercased()): \(words)\(isPicked ? ", picked" : "")")
            .help(handle.kind == .holdEnd ? "How long the freeze holds. Drag along." : "A speed stop. Drag along or up and down.")
            .position(x: geometry.x(atClipMS: handle.timelineMS), y: Self.y(forSpeed: handle.speed))
    }

    /// A stop's own right click: Freeze, and Delete Speed Stop.
    @ViewBuilder
    private func stopMenu(_ handle: SpeedCurve.Handle) -> some View {
        let pieces = editorState.document?.layer(id: layerID)?.clipPieces
        let ramp = pieces?.piece(at: handle.piece)?.speedRamp
        let isFreeze = ramp?.stops.indices.contains(handle.stop) == true && ramp?.stops[handle.stop].isFreeze == true
        Button(SpeedStopNames.speedTitle(0)) {
            editorState.freezeSpeedStop(layerID: layerID, piece: handle.piece, stop: handle.stop)
        }
        .disabled(isLocked || isFreeze || pieces?.canFreezeSpeedStop(ofPiece: handle.piece, stop: handle.stop) != true)
        Button(SpeedStopNames.delete) {
            editorState.deleteSpeedStop(layerID: layerID, piece: handle.piece, stop: handle.stop)
        }
        .disabled(isLocked)
    }

    /// One gesture for both directions, because a stop IS a moment and a
    /// speed; the first and last stops only go up and down. Shift keeps it to
    /// whichever way it set off. A freeze's second zero only goes along.
    private func drag(_ handle: SpeedCurve.Handle, geometry: PlotGeometry) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.space))
            .onChanged { value in
                guard !isLocked else { return }
                // Where the stop was when the hand took it, and how far from
                // its middle the hand landed: the stop is redrawn under the
                // hand at every move, so it is never the place to measure from.
                if editorState.speedStopDrag == nil {
                    editorState.beginSpeedStopDrag(layerID: layerID, piece: handle.piece, stop: handle.stop,
                                                   kind: handle.kind)
                    grabbedAt = CGPoint(x: geometry.x(atClipMS: handle.timelineMS), y: Self.y(forSpeed: handle.speed))
                }
                let start = grabbedAt ?? value.startLocation
                var along = value.translation.width
                var upDown = value.translation.height
                if KeyClick.flags.contains(.shift) {
                    if abs(along) >= abs(upDown) { upDown = 0 } else { along = 0 }
                }
                // Along only once the hand has really gone along, so a drag
                // straight up never nudges the stop off its frame.
                let ms: Int? = abs(along) >= 3 ? Int(geometry.clipMS(atX: start.x + along).rounded()) : nil
                // A stop not moved up or down keeps its own speed, even one
                // faster than the top of the scale.
                let speed: Double? = handle.kind == .stop && abs(upDown) >= 1 ? Self.speed(atY: start.y + upDown) : nil
                editorState.updateSpeedStopDrag(toClipMS: ms, speed: speed)
            }
            .onEnded { _ in
                grabbedAt = nil
                editorState.commitSpeedStopDrag()
            }
    }

    /// The speed in the hand beside the stop, the mock's stop title.
    private func readout(_ session: SpeedStopDragSession, curve: SpeedCurve, geometry: PlotGeometry) -> some View {
        let handle = curve.handles.first { $0.piece == session.piece && $0.stop == session.stop && $0.kind == session.kind }
        let words: String = session.kind == .holdEnd
            ? String(format: "%.2fs", Double(session.holdMS ?? 0) / 1000)
            : SpeedStopNames.speedTitle(session.percent)
        let x = handle.map { geometry.x(atClipMS: $0.timelineMS) } ?? 0
        let y = handle.map { Self.y(forSpeed: $0.speed) } ?? 0
        return Text(words)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 4))
            .fixedSize()
            .position(x: min(max(x + 30, 24), max(24, laneWidth - 24)), y: max(9, y - 14))
            .allowsHitTesting(false)
            .playtestField("Speed curve readout")
    }

    /// The playhead where it crosses the curve, the mock's `.schead`.
    @ViewBuilder
    private func playheadDot(_ curve: SpeedCurve, _ geometry: PlotGeometry) -> some View {
        let ms = Double(editorState.documentTimeMS - geometry.inMS)
        if ms >= 0, ms <= Double(curve.lengthMS) {
            Circle()
                .fill(VideoKit.Palette.crit)
                .overlay(Circle().strokeBorder(VideoKit.Palette.panel, lineWidth: 1.5))
                .frame(width: 9, height: 9)
                .position(x: geometry.x(atClipMS: ms), y: Self.y(forSpeed: curve.speed(atMS: ms)))
                .allowsHitTesting(false)
        }
    }

    // MARK: Where things go

    /// The clip's span on the timeline, as shown.
    private var clipSpan: (inMS: Int, outMS: Int)? {
        guard let time = (editorState.shownDocument(forClip: layerID) ?? editorState.document)?
            .layer(id: layerID)?.time else { return nil }
        return (time.inMS, time.outMS)
    }

    /// The piece under the latest right click, for the clip's own menu.
    private var pieceAtRightPress: Int {
        guard let ms = editorState.timelineLastRightPressMS ?? Optional(editorState.documentTimeMS),
              let layer = editorState.document?.layer(id: layerID), let time = layer.time,
              let pieces = layer.clipPieces else { return 0 }
        return pieces.pieceIndex(atMS: ms - time.inMS) ?? 0
    }

    /// How far down the plot a speed sits: the mock's scale, nought on the
    /// floor over the band strip and 3x at the top.
    static func y(forSpeed speed: Double) -> CGFloat {
        let top = topInset
        let bottom = plotHeight - stripHeight - bottomInset
        return bottom - CGFloat(SpeedCurve.height(ofSpeed: speed)) * (bottom - top)
    }

    static func speed(atY y: CGFloat) -> Double {
        let top = topInset
        let bottom = plotHeight - stripHeight - bottomInset
        return Double((bottom - y) / (bottom - top)) * SpeedCurve.topSpeed
    }

    static func color(_ band: SpeedBand) -> Color {
        switch band {
        case .slow: VideoKit.rgb(0x12C2E9)
        case .normal: VideoKit.rgb(0x9A5CFF)
        case .fast: VideoKit.rgb(0xFF5D8F)
        case .freeze: VideoKit.rgb(0xFEBC2E)
        }
    }
}

/// The clip's own clock laid along the lane: where a moment of the clip is
/// drawn, at the timeline's zoom.
private struct PlotGeometry {
    let ruler: MotionStripRuler
    let laneWidth: CGFloat
    let inMS: Int
    let outMS: Int

    func x(atClipMS ms: Double) -> CGFloat {
        laneWidth * CGFloat(ruler.fraction(ofMS: Double(inMS) + ms))
    }

    func clipMS(atX x: CGFloat) -> Double {
        ruler.ms(atFraction: Double(x / max(laneWidth, 1))) - Double(inMS)
    }

    /// The plot under the clip's bar, cut to the lane.
    func plotRect(height: CGFloat) -> CGRect {
        let x0 = max(0, x(atClipMS: 0)), x1 = min(laneWidth, x(atClipMS: Double(outMS - inMS)))
        return CGRect(x: x0, y: 0, width: max(0, x1 - x0), height: height)
    }

    var visible: ClosedRange<CGFloat> {
        let rect = plotRect(height: 1)
        return rect.minX...max(rect.minX, rect.maxX)
    }
}
