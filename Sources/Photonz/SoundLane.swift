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
            context.fill(path, with: .color(.white.opacity(0.55)))
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
    let width: CGFloat
    let height: CGFloat

    /// How big the dot you drag is.
    private static let dotSize: CGFloat = 9
    /// Room left at the top and the bottom so a dot at either extreme is drawn
    /// whole rather than sliced in half by the edge of the bar.
    private static var inset: CGFloat { dotSize / 2 + 1 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            line
            ForEach(level.points, id: \.atMS) { point in
                dot(point)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        // A click anywhere on the bar that is not on a dot pins the level
        // there, which is the whole of "add a point": there is no add button
        // and no mode, because the line is the control.
        .contentShape(Rectangle())
        .onTapGesture { location in
            guard editorState.selectedLayerID == layerID else {
                editorState.selectLayer(layerID)
                return
            }
            editorState.setSoundLevelPoint(atLayerMS: ms(atX: location.x),
                                           gain: gain(atY: location.y))
        }
    }

    private var line: some View {
        Path { path in
            let points = shape
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
        .stroke(.white.opacity(0.95), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        .shadow(color: .black.opacity(0.6), radius: 1.5)
        .allowsHitTesting(false)
    }

    /// The line's corners: one at each end of the bar and one at every point,
    /// which is exactly what `AudioLevel.gain(atLayerMS:)` describes.
    private var shape: [CGPoint] {
        guard lengthMS > 0, width > 0 else { return [] }
        var moments = [0] + level.points.map(\.atMS) + [lengthMS]
        moments = Array(Set(moments)).sorted().filter { $0 >= 0 && $0 <= lengthMS }
        return moments.map { CGPoint(x: x(atMS: $0), y: y(forGain: level.gain(atLayerMS: $0))) }
    }

    private func dot(_ point: AudioLevelPoint) -> some View {
        Circle()
            .fill(Color.accentColor)
            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
            .frame(width: Self.dotSize, height: Self.dotSize)
            .position(x: x(atMS: point.atMS),
                      y: y(forGain: level.gain(atLayerMS: point.atMS)))
            .gesture(drag(point))
            // A dot you cannot get rid of is a dot you regret putting down.
            .onTapGesture(count: 2) {
                editorState.removeSoundLevelPoint(atLayerMS: point.atMS)
            }
            .playtestField("\(layerName) level at \(EditorState.timecode(ms: point.atMS))")
            .panelHelp("The level here. Drag it up or down, or along. Double click to take it out.")
    }

    /// Dragging a dot moves it in both directions at once: up and down is how
    /// loud, along is when. One gesture, because a point IS those two numbers.
    private func drag(_ point: AudioLevelPoint) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                move(point, to: value.location)
            }
            .onEnded { value in
                move(point, to: value.location)
            }
    }

    private func move(_ point: AudioLevelPoint, to location: CGPoint) {
        let landing = ms(atX: location.x)
        if landing != point.atMS { editorState.removeSoundLevelPoint(atLayerMS: point.atMS) }
        editorState.setSoundLevelPoint(atLayerMS: landing, gain: gain(atY: location.y))
    }

    // MARK: Where a number is on the bar

    private func x(atMS ms: Int) -> CGFloat {
        guard lengthMS > 0 else { return 0 }
        return width * CGFloat(min(max(0, ms), lengthMS)) / CGFloat(lengthMS)
    }

    private func ms(atX x: CGFloat) -> Int {
        guard width > 0 else { return 0 }
        return Int((Double(min(max(0, x), width)) / Double(width) * Double(lengthMS)).rounded())
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
