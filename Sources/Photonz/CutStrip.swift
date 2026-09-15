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
    /// at, not a line to read a position off.
    private let blockHeight: CGFloat = 22
    private let hitHeight: CGFloat = 24
    /// The visible cut between two pieces.
    private let joinGap: CGFloat = 4
    private let thumbW: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            let duration = max(state.duration, 0.0001)
            let width = max(1, geo.size.width)
            let selected = state.selectedPieceIndex
            let playX = CGFloat(min(max(0, state.currentTime), duration) / duration) * width

            ZStack(alignment: .leading) {
                ForEach(Array(state.cuts.pieces.enumerated()), id: \.offset) { index, piece in
                    let range = state.cuts.timelineRange(ofPiece: index) ?? (0, 0)
                    let x = CGFloat(range.start / duration) * width
                    let w = CGFloat(piece.duration / duration) * width
                    block(isSelected: index == selected,
                          playedFraction: playedFraction(in: range, playhead: state.currentTime))
                        .frame(width: max(2, w - joinGap), height: blockHeight)
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
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .frame(height: hitHeight)
        .accessibilityLabel("Recording pieces")
        .accessibilityValue(pieceSummary)
    }

    /// One piece. The played part of it is brighter, the same way the scrubber
    /// fills behind its thumb, so progress still reads at a glance; the piece
    /// the playhead is in wears the accent so there is never a question about
    /// what Delete would take.
    private func block(isSelected: Bool, playedFraction: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(.primary.opacity(isSelected ? 0.3 : 0.18))
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.75))
                                     : AnyShapeStyle(Color.primary.opacity(0.55)))
                    .frame(width: geo.size.width * CGFloat(playedFraction))
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private func playedFraction(in range: (start: TimeInterval, end: TimeInterval),
                                playhead: TimeInterval) -> Double {
        let length = range.end - range.start
        guard length > 0 else { return 0 }
        return min(max(0, (playhead - range.start) / length), 1)
    }

    private var pieceSummary: String {
        let count = state.cuts.pieceCount
        guard let selected = state.selectedPieceIndex else { return "\(count) pieces" }
        return "Piece \(selected + 1) of \(count)"
    }
}
