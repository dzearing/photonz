import PhotonzCore
import SwiftUI

/// **The expanded cut** (`docs/design/mocks/pages/video-transition-wt.html`,
/// `#rowA` and `#rowB`; `shared/components/video.css`, `.track.xrow`,
/// `.xused`, `.xfade`, `.xboth`): the open cut's two clips on rows of their
/// own under the track, A over B, where an overlap is literally two clips at
/// the same time.
///
/// A ends on the cut and B starts on it, exactly as they were cut. A dissolve
/// is A's hatched frames running on past the cut and B's coming up before it,
/// the spare each side spends, with the mock's dashed box and its label over
/// the stretch where both are on screen. A dip spends nothing: each side
/// fades inside its own time, and a hold on black parts them by the black.
///
/// Only drawn; it answers no pointer, so nothing here can move a clip.
struct ExpandedCutRows: View {
    @Environment(EditorState.self) private var editorState
    let rows: ExpandedCut
    let laneWidth: CGFloat
    var indent: CGFloat = 0

    /// `.track.xrow .lane{height:22px}`, and `.track.xrow{margin:3px 0}`.
    static let rowHeight: CGFloat = 22
    static let rowGap: CGFloat = 3
    static let height: CGFloat = rowHeight * 2 + rowGap
    /// `.track.xrow .clip{border-radius:5px}`.
    static let cornerRadius: CGFloat = 5
    /// `.xboth .lb{top:-15px}`: the label rides over the top of B's row.
    static let labelRise: CGFloat = 15

    #if PHOTONZ_PLAYTEST
    @State private var laneFrame: CGRect = .zero
    #endif

    var body: some View {
        HStack(alignment: .top, spacing: TimelineDock.gap) {
            gutter
            lane
                .frame(width: laneWidth, height: Self.height, alignment: .topLeading)
                .clipShape(TimelineEdgeClip())
        }
        .frame(height: Self.height)
        .allowsHitTesting(false)
        .playtestField("Expanded cut")
    }

    // MARK: The gutter: A and B

    /// `.track.xrow .tl{font-size:9.5px;color:var(--faint)}`.
    private var gutter: some View {
        VStack(alignment: .leading, spacing: Self.rowGap) {
            ForEach(["A", "B"], id: \.self) { side in
                Text(side)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(VideoKit.Palette.faint)
                    .padding(.leading, indent + 12)
                    .frame(width: TimelineDock.gutter, height: Self.rowHeight, alignment: .leading)
                    .accessibilityLabel("Expanded cut row \(side)")
            }
        }
    }

    // MARK: The lane: two rows on the ruler

    private var lane: some View {
        let a = rows.a, b = rows.b
        let bTop = Self.rowHeight + Self.rowGap
        return ZStack(alignment: .topLeading) {
            // In an overlap each clip's bar runs on over the frames it
            // spends, at its own colour, hatched (step 5's `#xClipA` and
            // `#xClipB` widths, with `.xused` over them).
            bar(a.name, kind: .video, fromMS: a.startMS, toMS: a.spent?.upperBound ?? a.endMS, top: 0)
            if let spent = a.spent { hatch(spent, top: 0) }
            if let fade = a.fade { fadeMark(fade, out: true, top: 0) }

            bar(b.name, kind: .videoAlternate, fromMS: b.spent?.lowerBound ?? b.startMS, toMS: b.endMS, top: bTop)
            if let spent = b.spent { hatch(spent, top: bTop) }
            if let fade = b.fade { fadeMark(fade, out: false, top: bTop) }
            if let both = rows.both, let label = rows.bothLabel { bothMark(both, label: label, top: bTop) }
            // Each name over everything drawn on its bar, so a dip's fade up
            // from black never darkens the words with it.
            name(a.name, kind: .video, fromMS: a.startMS, toMS: a.endMS, top: 0)
            name(b.name, kind: .videoAlternate, fromMS: b.spent?.lowerBound ?? b.startMS, toMS: b.endMS, top: bTop)
        }
        #if PHOTONZ_PLAYTEST
        .background {
            let _ = DrawnExpandedCut.shared.showing(DrawnExpandedCut.Rows(
                laneFrame: laneFrame, laneWidth: laneWidth, rowHeight: Self.rowHeight, bTop: bTop,
                rows: rows, label: rows.bothLabel))
            Color.clear
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            laneFrame = frame
            DrawnExpandedCut.shared.moved(to: frame)
        }
        .onDisappear { DrawnExpandedCut.shared.gone() }
        #endif
    }

    private func x(_ ms: Int) -> CGFloat {
        laneWidth * editorState.motionStripRuler.fraction(ofMS: Double(ms))
    }

    /// The clip where it was cut: its kind's colour and its name, as its bar on
    /// the track wears them, at the row's height.
    private func bar(_ name: String, kind: VideoKit.ClipKind, fromMS: Int, toMS: Int, top: CGFloat) -> some View {
        let x0 = x(fromMS), width = max(2, x(toMS) - x0)
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius)
        return shape.fill(kind.fill)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.18)).frame(height: 1)
                    .padding(.horizontal, Self.cornerRadius / 2)
            }
            .clipShape(shape)
            .frame(width: width, height: Self.rowHeight)
            .offset(x: x0, y: top)
    }

    /// A bar's name, kept in sight when the bar starts off the left of the
    /// lane, and shadowed so it reads over a fade to black as well as over
    /// the clip's own colour.
    private func name(_ name: String, kind: VideoKit.ClipKind, fromMS: Int, toMS: Int, top: CGFloat) -> some View {
        let x0 = x(fromMS), width = max(2, x(toMS) - x0)
        return Text(name)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(kind.ink)
            .shadow(color: .black.opacity(0.6), radius: 1, y: 0.5)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.leading, 8 + max(0, -x0))
            .padding(.trailing, 6)
            .frame(width: width, height: Self.rowHeight, alignment: .leading)
            .clipped()
            .offset(x: x0, y: top)
            .accessibilityLabel("Expanded cut \(name)")
    }

    /// `.xused`: the spare frames being spent, hatched white at .36 in 3pt
    /// stripes every 7pt over the clip's bar running on.
    private func hatch(_ span: Range<Int>, top: CGFloat) -> some View {
        let x0 = x(span.lowerBound), width = max(2, x(span.upperBound) - x0)
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius)
        return Color.clear
            .overlay {
                Canvas { context, size in
                    // A 45 degree stripe 3pt across, one every 7pt measured
                    // square to the stripes: √2 times that along the row.
                    let step = 7 * 2.squareRoot(), across = 3 * 2.squareRoot()
                    var x = -size.height
                    while x < size.width {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: size.height))
                        path.addLine(to: CGPoint(x: x + across, y: size.height))
                        path.addLine(to: CGPoint(x: x + across + size.height, y: 0))
                        path.addLine(to: CGPoint(x: x + size.height, y: 0))
                        path.closeSubpath()
                        context.fill(path, with: .color(.white.opacity(0.36)))
                        x += step
                    }
                }
            }
            .clipShape(shape)
            .frame(width: width, height: Self.rowHeight)
            .offset(x: x0, y: top)
    }

    /// `.xfade`: a dip's fade inside the clip's own time, to black at the cut
    /// on A and up from it on B.
    private func fadeMark(_ span: Range<Int>, out: Bool, top: CGFloat) -> some View {
        let x0 = x(span.lowerBound), width = max(2, x(span.upperBound) - x0)
        let black = VideoKit.rgb(0x05060A)
        return RoundedRectangle(cornerRadius: Self.cornerRadius)
            .fill(LinearGradient(colors: out ? [.clear, black] : [black, .clear],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: width, height: Self.rowHeight)
            .offset(x: x0, y: top)
    }

    /// `.xboth`: a dashed white box over the stretch where both are on screen,
    /// on B's row, with its length riding over the top of the row.
    private func bothMark(_ span: Range<Int>, label: String, top: CGFloat) -> some View {
        let x0 = x(span.lowerBound), width = max(2, x(span.upperBound) - x0)
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius)
        return ZStack(alignment: .top) {
            shape.fill(Color.white.opacity(0.08))
                .overlay(shape.strokeBorder(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                .frame(width: width, height: Self.rowHeight)
            Text(label)
                .font(.system(size: 8.5, weight: .bold))
                .kerning(0.25)
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(VideoKit.rgb(0x0A0C16, 0.82)))
                .offset(y: -Self.labelRise)
                .frame(width: width)
                .accessibilityLabel(label)
        }
        .frame(width: width, height: Self.rowHeight, alignment: .top)
        .offset(x: x0, y: top)
    }
}
