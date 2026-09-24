import PhotonzCore
import SwiftUI

// What a piece of sound looks like on the timeline
// (`docs/design/video-audio.md`).
//
// Two drawings and they answer two different questions. The WAVEFORM says
// where the words and the beats are, so a cut can be aimed at one instead of
// guessed at. The LEVEL LINE says how loud it is as it runs, and it is the only
// control for that: a fade is a point at the start and a point a moment later,
// a duck is a point either side of a dip, and there is deliberately no fade
// control and no curve menu because both would be the same thing said again.

/// The shape of a sound, drawn inside one piece of a clip's bar.
///
/// Mirrored about the middle the way every waveform everywhere is, because a
/// sound read as a block growing up from the floor reads as a bar chart.
struct SoundWaveform: View {
    let columns: [Float]
    /// The mock's `.wave i` on the dock (the audio ink at .7), white elsewhere.
    var color: Color = .white.opacity(0.55)

    var body: some View {
        Canvas { context, size in
            guard columns.count > 0, size.width > 0 else { return }
            let step = size.width / CGFloat(columns.count)
            let middle = size.height / 2
            var path = Path()
            for (index, column) in columns.enumerated() {
                // Never nothing at all: a hairline through the quiet parts is
                // what makes a stretch of silence read as silence rather than
                // as a gap in the drawing.
                let half = max(0.5, CGFloat(column) * (middle - 1))
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
    /// The mock's duck line colour on the dock, white on the icon strip.
    var lineColor: Color = .white.opacity(0.95)

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

    /// How big the dot you drag is.
    private static let dotSize: CGFloat = 9
    /// How far either side of the line still counts as on it.
    private static let bandWidth: CGFloat = 12
    /// Room left at the top and the bottom so a dot at either extreme is drawn
    /// whole rather than sliced in half by the edge of the bar.
    private static var inset: CGFloat { dotSize / 2 + 1 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            line
            ForEach(shownPoints, id: \.atMS) { point in
                dot(point)
            }
            if let movingPoint { readout(movingPoint.to) }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        // Only the line itself is the control, the way Premiere's volume
        // line is: the rest of the segment picks the clip up and moves it.
        // A click on the line pins the level there, and a drag up or down
        // moves the whole line, which is the fader.
        .contentShape(LevelBand(points: shape, width: Self.bandWidth))
        .onTapGesture { location in
            guard editorState.selectedLayerID == layerID else {
                editorState.selectLayer(layerID)
                return
            }
            editorState.setSoundLevelPoint(onLayer: layerID, fromMS: nil,
                                           to: AudioLevelPoint(atMS: ms(atX: location.x),
                                                               gain: shapeGain(atY: location.y)))
        }
        .gesture(fader)
        .playtestField("\(layerName) level line")
        .panelHelp("The volume. Drag the line up or down; click it to pin the level there.")
    }

    /// The level as drawn: the fader in the hand, while there is one.
    private var shownLevel: AudioLevel {
        var shown = level
        if let draggedGain { shown.gain = draggedGain }
        if let movingPoint {
            shown.removePoint(atMS: movingPoint.fromMS)
            shown.setPoint(atMS: movingPoint.to.atMS, gain: movingPoint.to.gain)
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

    /// Where a stored point is drawn: under the hand while it is dragged.
    private func drawn(_ point: AudioLevelPoint) -> AudioLevelPoint {
        guard let movingPoint, movingPoint.fromMS == point.atMS else { return point }
        return movingPoint.to
    }

    private var fader: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let held = heldAtMS ?? ms(atX: value.startLocation.x)
                heldAtMS = held
                let shape = level.shape(atLayerMS: held)
                guard shape > 0 else { return }
                draggedGain = AudioLevel.bounded(gain(atY: value.location.y) / shape)
            }
            .onEnded { _ in
                if let draggedGain {
                    editorState.selectLayer(layerID)
                    editorState.setSoundGain(draggedGain, onLayer: layerID)
                }
                draggedGain = nil
                heldAtMS = nil
            }
    }

    /// The points inside the stretch on screen. One off the side of the
    /// window would otherwise be drawn pinned to the edge, where it reads as a
    /// point somebody put there.
    private var shownPoints: [AudioLevelPoint] {
        level.points.filter { $0.atMS >= fromMS && $0.atMS <= toMS }
    }

    private var line: some View {
        Path { path in
            let points = shape
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
        .stroke(lineColor, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        .shadow(color: .black.opacity(0.6), radius: 1.5)
        .allowsHitTesting(false)
    }

    /// The line's corners: one at each end of the bar and one at every point,
    /// which is exactly what `AudioLevel.gain(atLayerMS:)` describes.
    private var shape: [CGPoint] {
        guard lengthMS > 0, width > 0 else { return [] }
        var moments = [fromMS] + shownLevel.points.map(\.atMS) + [toMS]
        moments = Array(Set(moments)).sorted().filter { $0 >= fromMS && $0 <= toMS }
        return moments.map { CGPoint(x: x(atMS: $0), y: y(forGain: shownLevel.gain(atLayerMS: $0))) }
    }

    private func dot(_ stored: AudioLevelPoint) -> some View {
        let point = drawn(stored)
        return Circle()
            .fill(Color.accentColor)
            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
            .frame(width: Self.dotSize, height: Self.dotSize)
            .position(x: x(atMS: point.atMS),
                      y: y(forGain: shownLevel.gain(atLayerMS: point.atMS)))
            .gesture(drag(stored))
            // A dot you cannot get rid of is a dot you regret putting down.
            .onTapGesture(count: 2) {
                editorState.removeSoundLevelPoint(onLayer: layerID, atLayerMS: stored.atMS)
            }
            .playtestField("\(layerName) level at \(EditorState.timecode(ms: point.atMS))")
            .panelHelp("The level here. Drag it up or down, or along. Double click to take it out.")
    }

    /// Dragging a dot moves it in both directions at once: up and down is how
    /// loud, along is when. One gesture, because a point IS those two numbers.
    private func drag(_ point: AudioLevelPoint) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                movingPoint = (point.atMS, landing(at: value.location))
            }
            .onEnded { value in
                movingPoint = nil
                editorState.setSoundLevelPoint(onLayer: layerID, fromMS: point.atMS,
                                               to: landing(at: value.location))
            }
    }

    /// The point a dot let go at `location` makes: its moment, and the
    /// shape that puts the line under the hand with the fader where it is.
    private func landing(at location: CGPoint) -> AudioLevelPoint {
        AudioLevelPoint(atMS: ms(atX: location.x), gain: shapeGain(atY: location.y))
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

/// The strip either side of the level line that a click or a drag takes hold
/// of: the line, fattened, so the rest of the segment is left to the clip.
private struct LevelBand: Shape {
    let points: [CGPoint]
    let width: CGFloat

    func path(in rect: CGRect) -> Path {
        var line = Path()
        guard let first = points.first else { return line }
        line.move(to: first)
        for point in points.dropFirst() { line.addLine(to: point) }
        return line.strokedPath(StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
}
