import PhotonzCore
import SwiftUI

/// Custom Liquid-Glass trim scrubber (phase 13.3): a track with draggable in/out
/// handles bracketing the kept window, dimmed trimmed-away ends, and a playhead
/// that tracks playback. Time↔x is linear over an **inset** track so a handle at
/// 0% / 100% stays fully on-screen and grabbable (the bug before: end handles
/// were half-clipped at the track edges). Handles drive `setTrimIn/out`; a drag
/// on the kept window scrubs. Every gesture resolves in the named "trim" space,
/// so `location.x` maps straight to a time with no offset bookkeeping.
struct TrimTimeline: View {
    let state: VideoEditorState

    /// Visual width of a handle; its grab area is `handleHit`, much wider.
    private let handleWidth: CGFloat = 14
    private let handleHit: CGFloat = 34
    private let trackHeight: CGFloat = 44
    /// Height of a piece block inside the track, and the gap that draws the cut
    /// between two of them — the same reading as the strip the trim replaced.
    private let blockHeight: CGFloat = 26
    private let joinGap: CGFloat = 4
    /// Breathing room at each end so a handle pinned to a clip extreme isn't
    /// clipped and stays easy to grab.
    private let inset: CGFloat = 18

    private static let space = "trim"

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let trackW = max(1, width - inset * 2)
            let duration = max(state.duration, 0.0001)
            let inX = xFor(state.trim.inPoint, trackW: trackW, duration: duration)
            let outX = xFor(state.trim.outPoint, trackW: trackW, duration: duration)
            let playX = xFor(state.currentTime, trackW: trackW, duration: duration)

            ZStack(alignment: .topLeading) {
                // Track base (the inset region).
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.08))
                    .frame(width: trackW, height: trackHeight)
                    .offset(x: inset)

                // Trimmed-away ends, dimmed, within the track region.
                Rectangle()
                    .fill(.black.opacity(0.4))
                    .frame(width: max(0, inX - inset), height: trackHeight)
                    .offset(x: inset)
                Rectangle()
                    .fill(.black.opacity(0.4))
                    .frame(width: max(0, (width - inset) - outX), height: trackHeight)
                    .offset(x: outX)

                // The pieces the recording is in, so opening the handles does
                // not take away what the strip was showing. Drawn OVER the
                // dimmed ends: the dim says which stretch of time is going,
                // the blocks say which pieces that is, and a dropped piece has
                // to stay readable to be recognised as the one being dropped.
                // An uncut recording has no pieces to show and keeps its plain
                // track, exactly as before.
                if showsPieces {
                    ForEach(pieceBlocks(trackW: trackW, duration: duration),
                            id: \.index) { block in
                        pieceBlock(block)
                    }
                }

                // Kept-window highlight border.
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: max(0, outX - inX), height: trackHeight)
                    .offset(x: inX)

                // Scrub anywhere in the kept window.
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: max(0, outX - inX), height: trackHeight)
                    .offset(x: inX)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                            .onChanged { v in
                                state.scrub(to: timeFor(v.location.x, trackW: trackW, duration: duration))
                            }
                    )

                // Playhead.
                Capsule()
                    .fill(.white)
                    .frame(width: 3, height: trackHeight)
                    .shadow(radius: 2)
                    .offset(x: playX - 1.5)
                    .allowsHitTesting(false)

                // In/out handles last so they sit above the mask + scrub area.
                handle(.left, at: inX) { x in
                    state.setTrimIn(timeFor(x, trackW: trackW, duration: duration))
                }
                handle(.right, at: outX) { x in
                    state.setTrimOut(timeFor(x, trackW: trackW, duration: duration))
                }
            }
            .coordinateSpace(.named(Self.space))
        }
        .frame(height: trackHeight)
    }

    /// Whether there are pieces worth drawing: cutting has to be available in
    /// this release, and the recording has to actually be in more than one
    /// piece. One piece is the plain track it always was.
    private var showsPieces: Bool {
        Experiments.shared.cutRecordingEnabled && state.cuts.isCut
    }

    /// Where each piece is drawn and how much of it the window keeps. The
    /// geometry lives in PhotonzCore so it is tested rather than eyeballed.
    private func pieceBlocks(trackW: CGFloat, duration: TimeInterval) -> [VideoTrimTrackBlock] {
        VideoTrimTrackBlock.blocks(
            for: state.cuts.piecesUnderTrim(fromTimeline: state.trim.inPoint,
                                            toTimeline: state.trim.outPoint),
            duration: duration, inset: inset, trackWidth: trackW, joinGap: joinGap)
    }

    /// One piece: the whole of it faintly, the part the trim window still keeps
    /// brighter on top. A piece the handles have let go of has no bright part
    /// at all, which is what "this one is going" looks like.
    private func pieceBlock(_ block: VideoTrimTrackBlock) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.white.opacity(0.12))
            if block.keptWidth > 0 {
                Rectangle()
                    .fill(.white.opacity(0.5))
                    .frame(width: block.keptWidth)
                    .offset(x: block.keptX - block.x)
            }
        }
        .frame(width: block.width, height: blockHeight)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .offset(x: block.x, y: (trackHeight - blockHeight) / 2)
        .allowsHitTesting(false)
    }

    private enum HandleSide {
        case left, right
        var image: String { self == .left ? "chevron.compact.left" : "chevron.compact.right" }
    }

    /// A handle centered on `xPos` with a wide invisible grab area so it's easy to
    /// hit. Drags map `location.x` (in the "trim" space) straight to a time.
    private func handle(_ side: HandleSide, at xPos: CGFloat,
                        onDrag: @escaping (CGFloat) -> Void) -> some View {
        ZStack {
            Color.clear
                .frame(width: handleHit, height: trackHeight)
                .contentShape(Rectangle())
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.accentColor)
                .frame(width: handleWidth, height: trackHeight)
                .overlay {
                    Image(systemName: side.image)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
                .shadow(radius: 2)
        }
        .frame(width: handleHit, height: trackHeight)
        .offset(x: xPos - handleHit / 2)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                .onChanged { v in onDrag(v.location.x) }
        )
    }

    private func xFor(_ seconds: TimeInterval, trackW: CGFloat, duration: TimeInterval) -> CGFloat {
        inset + CGFloat(min(max(0, seconds), duration) / duration) * trackW
    }

    private func timeFor(_ x: CGFloat, trackW: CGFloat, duration: TimeInterval) -> TimeInterval {
        TimeInterval(min(max(0, (x - inset) / trackW), 1)) * duration
    }
}
