import PhotonzCore
import SwiftUI

/// The playback line once a recording has a cut in it: the same strip of time
/// the scrubber always was, drawn as the pieces it is actually made of.
///
/// It replaces `PlaybackScrubber` only when there is more than one piece, so an
/// untouched recording looks exactly as it always did and nobody is shown a
/// concept before they have used it. There is no separate clip selection
/// either: the piece under the playhead is the piece you are holding, so
/// clicking a piece selects it because clicking a time moves the playhead
/// there, and Delete drops the one you are looking at.
///
/// Each piece is as wide as it is long, laid out in play order with a gap
/// between them: the gap is the cut, and it is the only thing on screen that
/// was not there before.
struct CutStrip: View {
    let state: VideoEditorState

    @State private var hovering = false
    @State private var dragging = false
    @State private var wasPlayingBeforeDrag = false

    /// Blocks are taller than the scrubber's track: they are things to point
    /// at, not a line to read a position off. The row is as tall as the
    /// tallest block, which is the picked one, so picking a different piece
    /// never changes the height of the strip.
    private let blockHeight: CGFloat = CutStripBlockStyle.rowHeight
    private let hitHeight: CGFloat = 24
    /// The visible cut between two pieces.
    private let joinGap: CGFloat = 4
    private let thumbW: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let duration = max(state.duration, 0.0001)
            let width = max(1, geo.size.width)
            let selected = state.selectedPieceIndex
            // The recording's pieces said in the document's own units, measured
            // by the SAME ruler the timing strip measures a document with
            // (`DocumentTime.swift`). One arithmetic, two strips: when a
            // recording opens as an ordinary document made of clip layers,
            // nothing about where a piece lands has to be worked out twice.
            let times = state.cuts.layerTimes()
            let ruler = MotionStripRuler(documentMS: state.cuts.documentDurationMS)
            let playX = width * ruler.fraction(ofMS: playheadMS(duration: duration))

            ZStack(alignment: .leading) {
                ForEach(Array(times.enumerated()), id: \.offset) { index, time in
                    let x = width * ruler.fraction(ofMS: Double(time.inMS))
                    let w = width * ruler.fraction(ofMS: Double(time.lengthMS))
                    let style = CutStripBlockStyle.block(
                        isPicked: index == selected,
                        playedFraction: playedFraction(in: time, playheadMS: playheadMS(duration: duration)))
                    block(style)
                        .frame(width: max(2, w - joinGap), height: style.height)
                        .offset(x: x + joinGap / 2)
                }

                // The playhead, drawn over the joins so it is readable across a
                // cut as well as inside a piece.
                Capsule()
                    .fill(.white)
                    .frame(width: thumbW, height: blockHeight + 6)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    .offset(x: min(max(0, playX - thumbW / 2), width - thumbW))
                    .allowsHitTesting(false)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !dragging {
                            dragging = true
                            wasPlayingBeforeDrag = state.isPlaying
                        }
                        let fraction = min(max(0, value.location.x / width), 1)
                        state.scrub(to: TimeInterval(fraction) * duration)
                    }
                    .onEnded { _ in
                        dragging = false
                        if wasPlayingBeforeDrag { state.play() }
                    }
            )
            .playtestHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            // Crossing a join hands the pick to the next piece. Easing that
            // hand-over keeps the strip from snapping under the playhead.
            .animation(.easeOut(duration: 0.14), value: selected)
        }
        .frame(height: hitHeight)
        .accessibilityLabel("Recording pieces")
        .accessibilityValue(pieceSummary)
    }

    /// One piece.
    ///
    /// Two things are being said here and they used to be said the same way,
    /// which is how the picked piece ended up the faintest block on the strip.
    /// Brightness now says one thing only: how far into this piece you have
    /// watched. Being the picked piece — the one Delete would take — is said
    /// three other ways instead, none of which progress ever uses: the block
    /// is drawn in the accent colour, it is taller than its neighbours, and it
    /// wears a white hairline. The numbers behind all of that, and the rule
    /// that the picked block can never be quieter than one that is not, live
    /// in `CutStripBlockStyle` where they are unit tested.
    private func block(_ style: CutStripBlockStyle) -> some View {
        let shape = RoundedRectangle(cornerRadius: CutStripBlockStyle.cornerRadius)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                shape.fill(paint(style.tint).opacity(style.baseOpacity))
                shape.fill(paint(style.playedTint).opacity(style.playedOpacity))
                    .frame(width: geo.size.width * CGFloat(style.playedFraction))
                if style.strokeWidth > 0 {
                    shape.strokeBorder(paint(.lift).opacity(style.strokeOpacity),
                                       lineWidth: style.strokeWidth)
                }
            }
        }
        .clipShape(shape)
    }

    private func paint(_ tint: CutStripTint) -> Color {
        switch tint {
        case .neutral: .primary
        case .accent: .accentColor
        case .lift: .white
        }
    }

    /// Where the playhead is, in the document's own milliseconds and never
    /// past the last frame.
    private func playheadMS(duration: TimeInterval) -> Double {
        Double(min(max(0, state.currentTime), duration) * 1000)
    }

    private func playedFraction(in time: LayerTime, playheadMS: Double) -> Double {
        guard time.lengthMS > 0 else { return 0 }
        return min(max(0, (playheadMS - Double(time.inMS)) / Double(time.lengthMS)), 1)
    }

    private var pieceSummary: String {
        let count = state.cuts.pieceCount
        guard let selected = state.selectedPieceIndex else { return "\(count) pieces" }
        return "Piece \(selected + 1) of \(count)"
    }
}
