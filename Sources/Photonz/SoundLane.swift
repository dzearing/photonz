import PhotonzCore
import SwiftUI

// What a piece of sound looks like on the timeline
// (`docs/design/video-audio.md`).
//
// Two drawings and they answer two different questions. The WAVEFORM says
// where the words and the beats are, so a cut can be aimed at one instead of
// guessed at. The LEVEL LINE says how loud it is as it runs: a fade is a point
// at the start and a point a moment later, a duck is a point either side of a
// dip. The Fades section in the panel writes the same fade points, and its
// curve bends the line along a fade (`AudioLevel.moments`).

/// The shape of a sound, drawn inside one piece of a clip's bar.
///
/// Mirrored about the middle the way every waveform everywhere is, because a
/// sound read as a block growing up from the floor reads as a bar chart.
///
/// Drawn in decibels (`Waveform.drawnHeight`), as Premiere's logarithmic
/// waveforms are: a straight scale drew a screen recording's system audio,
/// forty decibels down, as a flat line. Then scaled by the level it plays at,
/// as the mock draws it, so a fade in rises out of nothing and a sound turned
/// down draws smaller (`Waveform.drawnHeights`). `heights` is one nought-to-one
/// height per column, worked out already.
///
/// On the dock it is one filled shape, the top edge along and the bottom edge
/// back, as video-audio.html's lanes draw it (`SoundLaneShape.outline`). The
/// icon strip keeps its row of thin bars.
struct SoundWaveform: View {
    let heights: [Float]
    /// The sound lane's own colour at .55 on the dock, white elsewhere.
    var color: Color = .white.opacity(0.55)
    /// One smooth shape rather than a bar per column.
    var isShape = false

    var body: some View {
        Canvas { context, size in
            guard heights.count > 0, size.width > 0 else { return }
            if isShape {
                let outline = SoundLaneShape.outline(heights: heights, width: size.width,
                                                     height: size.height)
                guard let first = outline.first else { return }
                var shape = Path()
                shape.move(to: first)
                for point in outline.dropFirst() { shape.addLine(to: point) }
                shape.closeSubpath()
                context.fill(shape, with: .color(color))
                return
            }
            let step = size.width / CGFloat(heights.count)
            let middle = size.height / 2
            var path = Path()
            for (index, height) in heights.enumerated() {
                // Never nothing at all: a hairline through the quiet parts is
                // what makes a stretch of silence read as silence rather than
                // as a gap in the drawing.
                let half = max(0.5, CGFloat(height) * (middle - 1))
                let x = CGFloat(index) * step
                path.addRect(CGRect(x: x, y: middle - half,
                                    width: max(0.75, step - 0.35), height: half * 2))
            }
            context.fill(path, with: .color(color))
        }
        .allowsHitTesting(false)
    }
}

/// The level, drawn across a sound layer's whole bar, with a dot at every
/// moment somebody has pinned it.
///
/// The line is where the level IS, not where the fader is: the fader and the
/// shape multiply, so pulling the fader down carries the whole shape down with
/// it and the line goes on saying what you would hear.
///
/// It answers a click the way every animated line on the timeline does
/// (`AnimatedLine`, UX-PATTERNS D21): a click on a dot picks it, a click on
/// the line between two dots picks that segment, ⌘-click on the line adds a
/// dot, Shift adds to the pick, and a plain click never adds anything. A
/// picked segment shows a bend handle at its middle; its right click offers
/// the shared curve list. A drag on the line anywhere else is the fader.
struct SoundLevelLine: View {
    @Environment(EditorState.self) private var editorState
    let layerID: UUID
    let layerName: String
    let level: AudioLevel
    let lengthMS: Int
    /// The stretch of the layer this drawing covers, which is the whole of it
    /// until the timeline is opened out and only part of the bar is on screen
    /// (`TimelineZoom.swift`). Everything below measures against this pair, so
    /// a dot is drawn where the window puts it and dragging one lands on the
    /// moment under the hand at any zoom.
    let fromMS: Int
    let toMS: Int
    let width: CGFloat
    let height: CGFloat
    /// The sound lane's own colour on the dock, as video-audio.html strokes
    /// it, white on the icon strip.
    var lineColor: Color = .white.opacity(0.95)
    /// The mock's 1.5 on the dock, 2 on the icon strip.
    var lineWidth: CGFloat = 2
    /// The sound lane's own colour on the dock (`.anode`), the accent on the
    /// icon strip.
    var pointColor: Color = .accentColor
    /// The clip's own right-click menu, offered under the line's rows so a
    /// right click on the line is a right click on the clip (nil on the icon
    /// strip, which has no clip menu).
    var clipMenu: ClipMenuTarget?
    /// Told the level as drawn while a drag is under way, and nil when it is
    /// let go, so the waveform under the line shrinks and grows with the hand
    /// rather than jumping when the drag lands.
    var onLevelInHand: (AudioLevel?) -> Void = { _ in }

    /// Which clip menu a right click on the line carries.
    struct ClipMenuTarget {
        var piece: (Int) -> Int
        var onTheSound: Bool
    }

    /// The fader while the line is being dragged up or down, before it is
    /// let go, so the whole drag is one step to undo.
    @State private var draggedGain: Double?
    /// Where along the line the hand took hold, which is where the line stays
    /// under the pointer while it moves.
    @State private var heldAtMS: Int?
    /// A dot being dragged: where it started, and where the hand has it now.
    /// Drawn there until it is let go, which writes it once, so the whole
    /// drag is one step to undo.
    @State private var movingPoint: (fromMS: Int, to: AudioLevelPoint)?
    /// A picked segment's bend handle in the hand: the segment it bends and
    /// where its middle is, nought to one between its two levels.
    @State private var bending: (startMS: Int, middle: Double)?
    /// What the pointer rests on along the line, brightened a little so the
    /// hand sees what a click will take.
    @State private var hovered: AnimatedLineHit?

    /// Where the line is down the tracks, so a right click's height (said in
    /// the tracks' own space) can say whether it landed on this row.
    @State private var frameInTracks: CGRect = .zero

    /// How big the dot you drag is: the mock's `.anode`.
    private static let dotSize: CGFloat = 11
    /// The bend handle on a picked segment.
    private static let bendSize: CGFloat = 9
    /// Room left at the top and the bottom so a dot at either extreme is drawn
    /// whole rather than sliced in half by the edge of the bar. Held where it
    /// was when the dot was nine points, so the line sits at the height it
    /// always has for every level.
    private static let inset: CGFloat = 5.5
    /// The line's own space, which a dot's and a bend handle's drag read the
    /// hand in: each is laid out in its own few points before it is placed,
    /// so a drag read in `.local` lands near the bar's start.
    private static let lineSpace = "sound level line"

    var body: some View {
        let animated = animatedLine
        let pick = editorState.soundLinePick(layerID: layerID)
        ZStack(alignment: .topLeading) {
            line
            stretches(animated, pick: pick)
            surface(animated)
            ForEach(Array(shownLevel.points.enumerated()), id: \.element.atMS) { index, point in
                if point.atMS >= fromMS, point.atMS <= toMS { dot(point, index: index, pick: pick) }
            }
            bendHandles(pick)
            if let movingPoint { readout(movingPoint.to) }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .coordinateSpace(.named(Self.lineSpace))
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let at): hovered = animated.hit(at)
            case .ended: hovered = nil
            }
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            proxy.frame(in: .named(TimelineDock.tracksSpace))
        } action: { frameInTracks = $0 }
        .popover(isPresented: drawingHere, attachmentAnchor: .rect(.rect(drawingAnchor(animated))),
                 arrowEdge: .top) {
            CurveEditor(curve: editorState.pickedSoundSegmentsCurve(layerID: layerID) ?? .easeInOut, saves: true) {
                editorState.finishDrawingSoundCurve($0)
            }
        }
        .playtestField("\(layerName) level line")
    }

    // MARK: The line as something to click

    /// Only the strip along the line takes a press, the way Premiere's volume
    /// line does: the rest of the segment picks the clip up and moves it. A
    /// right click opens the menu of the segment it landed on, over the
    /// clip's; either side of the dots, only the clip's
    /// (`AnimatedLineSurface`).
    private func surface(_ animated: AnimatedLine) -> some View {
        let points = shownLevel.points
        return AnimatedLineSurface(
            line: animated, width: width, height: height,
            rightPress: { rightPressPoint },
            click: { lineClick($0, animated) },
            drag: fader,
            beyondMenu: {
                if let clipMenu {
                    TimelineClipMenu(layerID: layerID, piece: clipMenu.piece(rightPressLayerMS ?? 0),
                                     onTheSound: clipMenu.onTheSound)
                }
            },
            segmentMenu: { index, landed in
                if points.indices.contains(index + 1) {
                    let start = points[index].atMS
                    let at = landed ? rightPressLayerMS ?? start : (start + points[index + 1].atMS) / 2
                    BuiltAsItOpens(rows: {
                        var rows = editorState.soundSegmentMenuRows(layerID: layerID, startMS: start,
                                                                    atLayerMS: at, landed: landed)
                        if clipMenu != nil, !rows.isEmpty { rows.append(.separator) }
                        return rows
                    })
                    if let clipMenu {
                        TimelineClipMenu(layerID: layerID, piece: clipMenu.piece(at), onTheSound: clipMenu.onTheSound)
                    }
                }
            })
            .panelHelp("The volume. Drag the line up or down. Click a dot or a segment to pick it; "
                       + "Command-click the line to add a dot.")
    }

    private func lineClick(_ at: CGPoint, _ animated: AnimatedLine) {
        let flags = KeyClick.flags
        guard !flags.contains(.control) else { return }
        let points = shownLevel.points
        switch AnimatedLine.action(for: animated.hit(at), command: flags.contains(.command),
                                   shift: flags.contains(.shift)) {
        case let .pickDot(index, extending):
            guard points.indices.contains(index) else { return }
            editorState.pickSoundPoint(layerID: layerID, atLayerMS: points[index].atMS, extending: extending)
        case let .pickSegment(index, extending):
            guard points.indices.contains(index) else { return }
            editorState.pickSoundSegment(layerID: layerID, startMS: points[index].atMS,
                                         atLayerMS: ms(atX: at.x), extending: extending)
        case .addDot:
            editorState.addSoundPointOnLine(layerID: layerID, atLayerMS: ms(atX: animated.nearestPoint(to: at).x))
        case .clear:
            // Off the dots and segments, the line is the clip: picked, and
            // the playhead where it landed (`EditorState+TimelinePointing`).
            editorState.clearKeySelection()
            editorState.selectLayer(layerID)
            if let inMS = editorState.document?.layer(id: layerID)?.time?.inMS {
                editorState.playheadToTimelineClick(atMS: inMS + ms(atX: at.x))
            }
        }
    }

    /// Where the right click that is opening a menu landed, along the layer.
    private var rightPressLayerMS: Int? {
        guard let ms = editorState.timelineLastRightPressMS,
              let inMS = editorState.document?.layer(id: layerID)?.time?.inMS else { return nil }
        return ms - inMS
    }

    /// Where the latest right click landed, in the line's own points, or nil
    /// when it was not on this line. SwiftUI builds every menu near the press
    /// in the same pass, so a line only answers a press that landed on its
    /// own row and inside its own time (`EditorState+TimelinePointing`). A
    /// press that reached the line landed inside its strip, so it is read at
    /// the line's own height there: only WHEN it landed decides which point or
    /// segment it was.
    private var rightPressPoint: CGPoint? {
        guard let ms = rightPressLayerMS, (0...lengthMS).contains(ms),
              frameInTracks.insetBy(dx: 0, dy: -2).contains(CGPoint(x: frameInTracks.midX,
                                                                    y: editorState.timelineRightPressY))
        else { return nil }
        return CGPoint(x: x(atMS: ms), y: y(forGain: shownLevel.gain(atLayerMS: ms)))
    }

    /// The line as the rule sees it, in this view's own points: a dot at
    /// every point, the drawn line between each two, and the line held either
    /// side. Points off the side of the window still count, so a segment
    /// running in from off screen can be picked.
    private var animatedLine: AnimatedLine {
        let level = shownLevel
        let points = level.points
        guard lengthMS > 0, width > 0 else { return AnimatedLine(dots: [], segments: []) }
        func at(_ ms: Int) -> CGPoint { CGPoint(x: freeX(atMS: ms), y: y(forGain: level.gain(atLayerMS: ms))) }
        let dots = points.map { at($0.atMS) }
        let segments: [[CGPoint]] = zip(points, points.dropFirst()).map { a, b in
            // Off screen it is two points; on screen, the corners the mix
            // plays, so the strip follows a bent segment.
            guard b.atMS > fromMS, a.atMS < toMS else { return [at(a.atMS), at(b.atMS)] }
            return level.moments(fromMS: a.atMS, toMS: b.atMS).map(at)
        }
        guard let first = points.first, let last = points.last else {
            return AnimatedLine(dots: [], segments: [], before: [at(fromMS), at(toMS)])
        }
        let before = first.atMS > fromMS ? [at(fromMS), at(min(first.atMS, toMS))] : []
        let after = last.atMS < toMS ? [at(max(last.atMS, fromMS)), at(toMS)] : []
        return AnimatedLine(dots: dots, segments: segments, before: before, after: after)
    }

    // MARK: Drawing

    /// The level as drawn: the fader, a dot or a bend in the hand, while
    /// there is one.
    private var shownLevel: AudioLevel {
        var shown = level
        if let draggedGain { shown.gain = draggedGain }
        if let movingPoint {
            shown.movePoint(fromMS: movingPoint.fromMS, toMS: movingPoint.to.atMS, gain: movingPoint.to.gain)
        }
        if let bending {
            shown.setSegmentsCurve(AudioLevel.bentCurve(middle: bending.middle), startingAt: [bending.startMS])
        }
        return shown
    }

    /// How loud the dot in the hand makes it, beside the dot, the way
    /// Premiere says the level while a keyframe is dragged. Styled as the
    /// mock's `.ducktag`.
    private func readout(_ point: AudioLevelPoint) -> some View {
        let heard = shownLevel.gain(atLayerMS: point.atMS)
        let words = AudioLevel(gain: heard).label
        let x = x(atMS: point.atMS)
        return Text(words)
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(Color(red: 0xBF / 255, green: 0xF3 / 255, blue: 0xE4 / 255))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 3))
            .fixedSize()
            .position(x: min(max(x + 26, 24), max(24, width - 24)), y: 8)
            .allowsHitTesting(false)
            .playtestField("\(layerName) level readout")
    }

    private var line: some View {
        Path { path in
            let points = shape
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
        .stroke(lineColor, style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
        .shadow(color: .black.opacity(0.6), radius: 1.5)
        .allowsHitTesting(false)
    }

    /// Picked segments white on an accent edge, so they read on every lane
    /// colour, light or dark; the one under the pointer a little brighter.
    /// Each carries a name at its middle for a walk to aim at.
    private func stretches(_ animated: AnimatedLine, pick: AnimatedLinePick<Int>) -> some View {
        let points = shownLevel.points
        let hoveredSegment: Int? = if case let .segment(index) = hovered { index } else { nil }
        let accent = Color.accentColor
        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for (index, segment) in animated.segments.enumerated() where points.indices.contains(index) {
                    var stretch = Path()
                    guard let first = segment.first else { continue }
                    stretch.move(to: first)
                    for point in segment.dropFirst() { stretch.addLine(to: point) }
                    if pick.segments.contains(points[index].atMS) {
                        context.stroke(stretch, with: .color(accent),
                                       style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                        context.stroke(stretch, with: .color(.white),
                                       style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    } else if index == hoveredSegment {
                        context.stroke(stretch, with: .color(lineColor.mix(with: .white, by: 0.45)),
                                       style: StrokeStyle(lineWidth: lineWidth + 1.5, lineCap: .round,
                                                          lineJoin: .round))
                    }
                }
            }
            .allowsHitTesting(false)
            ForEach(Array(animated.segments.enumerated()), id: \.offset) { index, segment in
                if points.indices.contains(index), let middle = Self.middle(of: segment),
                   middle.x >= 0, middle.x <= width {
                    let start = points[index].atMS
                    let curve = shownLevel.segmentCurve(startingAtMS: start)
                    Color.clear
                        .frame(width: 6, height: 6)
                        .playtestControl("Segment \(layerName) level \(index + 1)", detail: layerName)
                        .panelReadout("segment \(layerName) level \(index + 1): "
                                      + (curve.map { StretchCurve.title($0) } ?? "Linear")
                                      + (pick.segments.contains(start) ? ", picked" : ""))
                        .offset(x: middle.x - 3, y: middle.y - 3)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// The line's corners: one at each end of the bar, one at every point,
    /// and the steps along a curve, which are exactly the corners the mix
    /// plays ramps between (`AudioLevel.moments`).
    private var shape: [CGPoint] {
        guard lengthMS > 0, width > 0 else { return [] }
        let level = shownLevel
        let moments = level.moments(fromMS: fromMS, toMS: toMS)
        return moments.map { CGPoint(x: x(atMS: $0), y: y(forGain: level.gain(atLayerMS: $0))) }
    }

    // MARK: A dot

    private func dot(_ stored: AudioLevelPoint, index: Int, pick: AnimatedLinePick<Int>) -> some View {
        let isPicked = pick.dots.contains(stored.atMS)
        let point = movingPoint.flatMap { $0.fromMS == stored.atMS ? $0.to : nil } ?? stored
        return LevelPointDot(color: pointColor, isPicked: isPicked, isHovered: hovered == .dot(index))
            .frame(width: Self.dotSize, height: Self.dotSize)
            .contentShape(Rectangle().inset(by: -2))
            .gesture(drag(stored))
            .onTapGesture { dotClick(stored) }
            .contextMenu {
                let _ = editorState.timelineRightPresses
                BuiltAsItOpens(rows: {
                    // Every dot's menu is built again after a right click
                    // anywhere; only the one it landed on picks its dot.
                    let landed = animatedLine.landed(rightPressPoint, on: .dot(index))
                    var rows = editorState.soundPointMenuRows(layerID: layerID, atLayerMS: stored.atMS,
                                                              landed: landed)
                    if clipMenu != nil, !rows.isEmpty { rows.append(.separator) }
                    return rows
                })
                if let clipMenu {
                    TimelineClipMenu(layerID: layerID, piece: clipMenu.piece(stored.atMS),
                                     onTheSound: clipMenu.onTheSound)
                }
            }
            // Named before it is placed, so a walk's mark is the dot and not
            // the whole line.
            .playtestField("\(layerName) level at \(EditorState.timecode(ms: point.atMS))")
            .playtestControl("\(layerName) level point \(index + 1)", detail: layerName)
            .panelReadout("level point \(layerName) \(index + 1): "
                          + AudioLevel(gain: shownLevel.gain(atLayerMS: point.atMS)).label
                          + " at \(EditorState.timecode(ms: point.atMS))" + (isPicked ? ", picked" : ""))
            .panelHelp("The level here. Click to pick it, drag it up or down or along, Backspace takes it out.")
            .position(x: x(atMS: point.atMS), y: y(forGain: shownLevel.gain(atLayerMS: point.atMS)))
    }

    /// A click on a dot picks it, Shift or Command adding it to the pick or
    /// taking it out (`AnimatedLine`).
    private func dotClick(_ point: AudioLevelPoint) {
        let flags = KeyClick.flags
        guard !flags.contains(.control),
              let index = shownLevel.points.firstIndex(of: point),
              case let .pickDot(_, extending) = AnimatedLine.action(for: .dot(index),
                                                                    command: flags.contains(.command),
                                                                    shift: flags.contains(.shift))
        else { return }
        editorState.pickSoundPoint(layerID: layerID, atLayerMS: point.atMS, extending: extending)
    }

    /// Dragging a dot moves it in both directions at once: up and down is how
    /// loud, along is when. One gesture, because a point IS those two numbers.
    /// Shift keeps it to whichever way it set off.
    private func drag(_ point: AudioLevelPoint) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.lineSpace))
            .onChanged { value in
                movingPoint = (point.atMS, landing(value, from: point))
                onLevelInHand(shownLevel)
            }
            .onEnded { value in
                movingPoint = nil
                onLevelInHand(nil)
                editorState.moveSoundPoint(layerID: layerID, fromMS: point.atMS, to: landing(value, from: point))
            }
    }

    /// The point a dot let go of makes: its moment, and the shape that puts
    /// the line under the hand with the fader where it is.
    private func landing(_ value: DragGesture.Value, from point: AudioLevelPoint) -> AudioLevelPoint {
        var location = value.location
        if KeyClick.flags.contains(.shift) {
            let start = CGPoint(x: x(atMS: point.atMS), y: y(forGain: level.gain(atLayerMS: point.atMS)))
            if abs(value.translation.width) >= abs(value.translation.height) { location.y = start.y }
            else { location.x = start.x }
        }
        let time = KeyClick.flags.contains(.shift) && location.x == x(atMS: point.atMS)
            ? point.atMS : ms(atX: location.x)
        return AudioLevelPoint(atMS: time, gain: shapeGain(atY: location.y))
    }

    // MARK: Bending a picked segment

    /// A handle at the middle of every picked segment that changes level:
    /// dragged up or down, it bends the segment through the hand.
    @ViewBuilder
    private func bendHandles(_ pick: AnimatedLinePick<Int>) -> some View {
        let level = shownLevel
        let points = level.points
        ForEach(Array(zip(points, points.dropFirst()).enumerated()), id: \.offset) { index, pair in
            let (a, b) = pair
            if pick.segments.contains(a.atMS), a.gain != b.gain, level.segmentCurve(startingAtMS: a.atMS) != .steps(1) {
                let middleMS = (a.atMS + b.atMS) / 2
                let at = CGPoint(x: x(atMS: middleMS), y: y(forGain: level.gain(atLayerMS: middleMS)))
                if middleMS >= fromMS, middleMS <= toMS {
                    Circle()
                        .fill(Color.white)
                        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
                        .frame(width: Self.bendSize, height: Self.bendSize)
                        .contentShape(Circle().inset(by: -3))
                        .gesture(bend(from: a, to: b))
                        .playtestControl("Bend \(layerName) level \(index + 1)", detail: layerName)
                        .panelHelp("Drag to bend this segment.")
                        .position(at)
                }
            }
        }
    }

    private func bend(from a: AudioLevelPoint, to b: AudioLevelPoint) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.lineSpace))
            .onChanged { value in
                let heard = gain(atY: value.location.y)
                let fader = max(level.gain, 0.0001)
                let shapeGain = heard / fader
                bending = (a.atMS, (shapeGain - a.gain) / (b.gain - a.gain))
                onLevelInHand(shownLevel)
            }
            .onEnded { _ in
                if let bending { editorState.bendSoundSegment(layerID: layerID, startMS: bending.startMS,
                                                              middle: bending.middle) }
                bending = nil
                onLevelInHand(nil)
            }
    }

    // MARK: The fader

    private var fader: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let held = heldAtMS ?? ms(atX: value.startLocation.x)
                heldAtMS = held
                let shape = level.shape(atLayerMS: held)
                guard shape > 0 else { return }
                draggedGain = AudioLevel.bounded(gain(atY: value.location.y) / shape)
                onLevelInHand(shownLevel)
            }
            .onEnded { _ in
                if let draggedGain {
                    editorState.selectLayer(layerID)
                    editorState.setSoundGain(draggedGain, onLayer: layerID)
                }
                draggedGain = nil
                heldAtMS = nil
                onLevelInHand(nil)
            }
    }

    // MARK: Draw a Curve, from a segment's right click

    private var drawingHere: Binding<Bool> {
        Binding(get: { editorState.drawingSoundCurve?.layerID == layerID },
                set: { open in if !open { editorState.finishDrawingSoundCurve(nil) } })
    }

    private func drawingAnchor(_ animated: AnimatedLine) -> CGRect {
        let points = shownLevel.points
        guard let drawing = editorState.drawingSoundCurve,
              let index = points.dropLast().firstIndex(where: { drawing.pick.segments.contains($0.atMS) }),
              animated.segments.indices.contains(index),
              let middle = Self.middle(of: animated.segments[index]) else {
            return CGRect(x: width / 2, y: height / 2, width: 1, height: 1)
        }
        return CGRect(x: min(max(middle.x, 0), width) - 4, y: middle.y - 4, width: 8, height: 8)
    }

    /// Half way along a drawn stretch, by its length.
    static func middle(of points: [CGPoint]) -> CGPoint? {
        guard let first = points.first else { return nil }
        let pieces = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        var left = pieces.reduce(0, +) / 2
        for (index, length) in pieces.enumerated() {
            if left <= length, length > 0 {
                let a = points[index], b = points[index + 1], u = left / length
                return CGPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)
            }
            left -= length
        }
        return first
    }

    /// The point's own number for a height on the bar. The points are the
    /// shape under the fader, so the line only lands under the hand when the
    /// fader is divided back out.
    private func shapeGain(atY y: CGFloat) -> Double {
        let heard = gain(atY: y)
        guard level.gain > 0 else { return heard }
        return AudioLevel.bounded(heard / level.gain)
    }

    // MARK: Where a number is on the bar

    private func x(atMS ms: Int) -> CGFloat {
        let span = max(1, toMS - fromMS)
        return width * CGFloat(min(max(fromMS, ms), toMS) - fromMS) / CGFloat(span)
    }

    /// Where a moment is, carried on past either side of the window rather
    /// than held to its edge, for a point off screen.
    private func freeX(atMS ms: Int) -> CGFloat {
        width * CGFloat(ms - fromMS) / CGFloat(max(1, toMS - fromMS))
    }

    private func ms(atX x: CGFloat) -> Int {
        guard width > 0 else { return fromMS }
        let span = Double(max(1, toMS - fromMS))
        return fromMS + Int((Double(min(max(0, x), width)) / Double(width) * span).rounded())
    }

    /// The top of the bar is as loud as a level goes and the bottom is silence,
    /// so the line sitting high means loud without anything having to say so.
    ///
    /// **Not a straight mapping.** Level goes to twice as loud, so spread
    /// evenly the ordinary level would sit exactly halfway up the bar, drawn
    /// straight through the middle of the waveform where it reads as an axis
    /// rather than as a control. Squared instead: the level it was recorded at
    /// sits about seven tenths of the way up, the six decibels of headroom take
    /// the top third, and the quiet end — where a duck lives and where a
    /// hand needs the most room — gets the rest. It is also how a fader feels
    /// under a hand, which is why every mixer ever made is marked this way.
    private func y(forGain gain: Double) -> CGFloat {
        let through = min(max(0, gain), AudioLevel.loudestGain) / AudioLevel.loudestGain
        return Self.inset + (height - Self.inset * 2) * (1 - CGFloat(through.squareRoot()))
    }

    private func gain(atY y: CGFloat) -> Double {
        let usable = height - Self.inset * 2
        guard usable > 0 else { return AudioLevel.unityGain }
        let through = 1 - Double(min(max(0, y - Self.inset), usable)) / Double(usable)
        return AudioLevel.bounded(through * through * AudioLevel.loudestGain)
    }
}

/// A level point as the mock's `.anode` draws one: filled in the lane's own
/// colour, ringed in the panel's so it stands off the waveform under it, a
/// little lighter under the pointer, and white on an accent ring when picked.
private struct LevelPointDot: View {
    let color: Color
    var isPicked = false
    var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var isUnderPointer = false

    var body: some View {
        Circle()
            .fill(isPicked ? Color.white : color)
            .overlay { if !isPicked, isHovered || isUnderPointer { Circle().fill(.white.opacity(0.22)) } }
            .overlay(Circle().strokeBorder(isPicked ? Color.accentColor : VideoKit.Palette.panel.color(colorScheme),
                                           lineWidth: isPicked ? 2 : 1.5))
            .shadow(color: isPicked ? Color.accentColor.opacity(0.6) : .black.opacity(0.4), radius: 2, y: 1)
            .scaleEffect(isPicked ? 1.15 : 1)
            .playtestHover { isUnderPointer = $0 }
    }
}
