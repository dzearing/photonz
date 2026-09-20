import PhotonzCore
import SwiftUI

/// **A clip's bar in the timeline**, drawn as the pieces it is cut into and
/// built to be taken hold of (`ClipBarDrag.swift`,
/// `docs/design/video-surface.md` §10.4).
///
/// A split adds a PIECE to this row, never a second row (UX-PATTERNS D18), so
/// what a cut recording looks like is this one bar with joins in it. Each
/// piece can be picked, carried somewhere else in the order, and thrown away;
/// every join and both ends can be dragged.
///
/// One rule holds the gestures together and it is worth stating on the view
/// that implements it: **every edge you can take hold of follows your hand.**
/// The bar's left end moves the clip's in point and takes the clip with it;
/// every join, and the right end, is the END of the piece to its left. There
/// is deliberately no gesture for the START of a piece that is not the first
/// one, because a clip's pieces lie end to end with no holes, so the join is
/// pinned by the piece before it and the edge could only run away from the
/// hand. That job belongs to the playhead: B where the good part starts, then
/// ⌫.
struct ClipPiecesBar: View {
    @Environment(EditorState.self) private var editorState
    let layerID: UUID
    let layerName: String
    /// The stretch as the strip is SHOWING it, which is the landing while a
    /// drag is in flight.
    let bar: LayerTime
    let laneWidth: CGFloat

    /// The widest a grip gets. It gives way to the piece it is on rather than
    /// eating it: two fixed grips on a quarter second piece would leave no
    /// body to pick the piece up by.
    private static let gripWidth: CGFloat = 7
    /// A piece narrower than this keeps its seams but loses its grips, because
    /// a grip you cannot help but hit is worse than no grip at all.
    private static let smallestGrabbablePiece: CGFloat = 14

    var body: some View {
        let ruler = editorState.motionStripRuler
        let pieces = shownPieces
        // While the bar's left end is being dragged the whole bar is drawn
        // where the HAND has it, and the frames being dropped are drawn faint
        // in the room that leaves. That is what makes the grip follow the hand
        // through a gesture whose result is the bar closing up from its far
        // end: you see what you are taking off, in place, and it shuts when
        // you let go (`docs/design/video-surface.md` §11.2).
        let shift = laneWidth * ruler.fraction(ofMS: Double(headShiftMS))
        let x0 = laneWidth * ruler.fraction(ofMS: Double(bar.inMS)) + shift
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(.quaternary.opacity(0.5))
                .frame(height: MotionStripView.barHeight)
            if headShiftMS > 0 {
                spare(width: shift, reading: ClipBarCopy.length(headShiftMS))
                    .offset(x: laneWidth * ruler.fraction(ofMS: Double(bar.inMS)))
            }
            if let behind = spareBehindMS, behind > 0 {
                spare(width: laneWidth * ruler.fraction(ofMS: Double(behind)),
                      reading: ClipBarCopy.length(behind))
                    .offset(x: x0 + laneWidth * ruler.fraction(ofMS: Double(pieces.totalLengthMS)))
            }
            ForEach(0..<pieces.count, id: \.self) { index in
                piece(pieces, index: index, x0: x0, ruler: ruler)
            }
            ForEach(0...pieces.count, id: \.self) { edge in
                grip(pieces, edge: edge, x0: x0, ruler: ruler)
            }
            if let snap = editorState.clipBarSnap, isBeingDragged {
                snapLine(atMS: snap.ms, ruler: ruler)
            }
            if let readout = editorState.clipBarReadout, isBeingDragged {
                capsule(readout, x: x0)
                    .frame(height: MotionStripView.barHeight)
            }
        }
        .frame(width: laneWidth, alignment: .leading)
        .panelReadout(readoutText)
    }

    // MARK: What is on the bar

    /// The pieces as the strip is showing them. `shownDocument` already
    /// carries the drag in flight, so there is nothing to merge here.
    private var shownPieces: ClipPieces {
        editorState.shownDocument?.layer(id: layerID)?.clipPieces
            ?? ClipPieces(single: bar)
    }

    private var isPicked: Bool { editorState.selectedLayerID == layerID }
    private var isBeingDragged: Bool { editorState.clipBarDrag?.layerID == layerID }

    /// How far the whole bar is drawn along while its left end is in a hand.
    /// Nought at every other moment, so nothing about the ordinary drawing
    /// knows this exists.
    private var headShiftMS: Int {
        guard let session = editorState.clipBarDrag, session.layerID == layerID,
              case .clipStart = session.grab else { return 0 }
        return session.landing.movedMS
    }

    /// How much recording there is still behind the clip's last frame, while
    /// its right end is in a hand: what there is left to pull back out into,
    /// drawn faint so nobody has to drag to find out whether there is any.
    private var spareBehindMS: Int? {
        guard let session = editorState.clipBarDrag, session.layerID == layerID,
              case .seam(let after) = session.grab,
              after == session.landing.pieces.count - 1 else { return nil }
        guard let range = session.landing.pieces.trimEndRange(ofPiece: after) else { return nil }
        return range.out
    }

    /// Frames that are still in the document and are not being played. The
    /// same faint block the Trim tool draws, for the same reason: it is the
    /// drawing that says a trim threw nothing away.
    @ViewBuilder private func spare(width: CGFloat, reading: String) -> some View {
        if width > 1 {
            RoundedRectangle(cornerRadius: 4)
                .fill(.secondary.opacity(0.18))
                .frame(width: width, height: MotionStripView.barHeight)
                .overlay {
                    if width > 34 {
                        Text(reading)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                .allowsHitTesting(false)
        }
    }

    private func isPiecePicked(_ index: Int, of count: Int) -> Bool {
        guard isPicked else { return false }
        guard count > 1 else { return true }
        // Mid-carry the bar is already drawn in the order it would land in, so
        // the piece in the hand is at its NEW place. Reading the picked index
        // straight off the selection would light up whatever piece happens to
        // sit at the old one, which is another piece entirely.
        if let session = editorState.clipBarDrag, session.layerID == layerID,
           case .carry(let grabbed) = session.grab {
            return index == (session.landing.dropIndex ?? grabbed)
        }
        return editorState.selectedClipPieceIndex == index
    }

    // MARK: One piece

    @ViewBuilder
    private func piece(_ pieces: ClipPieces, index: Int, x0: CGFloat,
                       ruler: MotionStripRuler) -> some View {
        let start = pieces.startMS(ofPiece: index)
        let item = pieces.piece(at: index)
        let length = item?.lengthMS ?? 0
        let x = x0 + laneWidth * ruler.fraction(ofMS: Double(start))
        // A hairline of air at each join, so two pieces read as two rather
        // than as one long bar. It comes out of the piece, never out of the
        // clip, so the bar still ends exactly where the clip does.
        let raw = laneWidth * ruler.fraction(ofMS: Double(length))
        let width = max(2, raw - (index == pieces.count - 1 ? 0 : 1.5))
        RoundedRectangle(cornerRadius: 4)
            .fill(fill(item, picked: isPiecePicked(index, of: pieces.count)))
            .frame(width: width, height: MotionStripView.barHeight)
            .overlay {
                if let badge = Self.badge(item), width > 22 {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 1)
                }
            }
            .offset(x: x)
            .contentShape(Rectangle())
            .gesture(carry(pieces, index: index))
            .onTapGesture {
                editorState.selectClipPiece(layerID: layerID,
                                            index: pieces.count > 1 ? index : nil)
            }
            .playtestField(Self.pieceName(layerName: layerName, index: index, of: pieces.count))
            .panelHelp(Self.help(pieces, index: index))
    }

    private func fill(_ piece: ClipPiece?, picked: Bool) -> AnyShapeStyle {
        // A HELD frame is drawn as itself rather than as a short clip: it is
        // the one piece that plays no time of the recording at all, and a
        // person scanning the bar for where they froze it should not have to
        // read a badge to find it.
        if piece?.isHeld == true {
            return AnyShapeStyle(picked ? Color.accentColor.opacity(0.9)
                                        : Color.secondary.opacity(0.7))
        }
        return AnyShapeStyle(picked ? AnyShapeStyle(Color.accentColor.opacity(0.85))
                                    : AnyShapeStyle(.secondary.opacity(0.45)))
    }

    /// What is written on a piece that is not playing at the speed it was
    /// recorded at. Nothing at all on an ordinary one, because a badge on
    /// every piece is a badge that says nothing.
    static func badge(_ piece: ClipPiece?) -> String? {
        guard let piece else { return nil }
        if piece.isHeld { return "hold" }
        switch piece.speedPercent {
        case ClipPiece.asRecordedPercent: return nil
        case let percent where percent % 100 == 0: return "\(percent / 100)x"
        default: return "\(piece.speedPercent)%"
        }
    }

    static func pieceName(layerName: String, index: Int, of count: Int) -> String {
        count > 1 ? "\(layerName) piece \(index + 1)" : "\(layerName) clip"
    }

    static func help(_ pieces: ClipPieces, index: Int) -> String {
        guard pieces.count > 1 else {
            return "The clip. Drag it to move it along the timeline."
        }
        return "Piece \(index + 1) of \(pieces.count). Drag it somewhere else in the order."
    }

    // MARK: The grips

    /// One grip per edge: nought is the clip's in point, and every other one
    /// is the join after the piece before it, which for the last is the clip's
    /// out point.
    @ViewBuilder
    private func grip(_ pieces: ClipPieces, edge: Int, x0: CGFloat,
                      ruler: MotionStripRuler) -> some View {
        let ms = edge == 0 ? 0 : (pieces.rangeMS(ofPiece: edge - 1)?.end ?? 0)
        let x = x0 + laneWidth * ruler.fraction(ofMS: Double(ms))
        let room = min(neighbourWidth(pieces, edge: edge, ruler: ruler),
                       Self.gripWidth * 3)
        let width = max(3, min(Self.gripWidth, room / 3))
        if isPicked, room >= Self.smallestGrabbablePiece {
            Capsule()
                .fill(Color.accentColor)
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.75), lineWidth: 1) }
                .frame(width: width, height: MotionStripView.barHeight)
                // The first grip sits inside the bar and the rest hang off the
                // join to its left, so a grip never covers the piece after it.
                .offset(x: x - (edge == 0 ? 0 : width))
                .contentShape(Rectangle().inset(by: -5))
                .gesture(edgeDrag(pieces, edge: edge, ruler: ruler))
                .playtestField(Self.gripName(layerName: layerName, edge: edge, of: pieces.count))
                .panelHelp(edge == 0
                           ? "Where the clip starts. Drag it: nothing is thrown away."
                           : (edge == pieces.count
                              ? "Where the clip ends. Drag it."
                              : "The join after piece \(edge). Drag it."))
        }
    }

    /// How much room there is either side of an edge, which is what decides
    /// whether a grip fits there at all.
    private func neighbourWidth(_ pieces: ClipPieces, edge: Int,
                                ruler: MotionStripRuler) -> CGFloat {
        let before = edge > 0 ? (pieces.piece(at: edge - 1)?.lengthMS ?? 0) : Int.max
        let after = edge < pieces.count ? (pieces.piece(at: edge)?.lengthMS ?? 0) : Int.max
        let smallest = min(before, after)
        guard smallest != Int.max else { return laneWidth }
        return laneWidth * ruler.fraction(ofMS: Double(smallest))
    }

    static func gripName(layerName: String, edge: Int, of count: Int) -> String {
        if edge == 0 { return "\(layerName) clip start" }
        if edge == count { return "\(layerName) clip end" }
        return "\(layerName) join \(edge)"
    }

    // MARK: The gestures

    private func edgeDrag(_ pieces: ClipPieces, edge: Int,
                          ruler: MotionStripRuler) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if editorState.clipBarDrag == nil {
                    editorState.beginClipBarDrag(
                        layerID: layerID,
                        grab: edge == 0 ? .clipStart : .seam(after: edge - 1))
                }
                editorState.updateClipBarDrag(byMS: Self.ms(value.translation.width,
                                                            laneWidth: laneWidth, ruler: ruler))
            }
            .onEnded { _ in editorState.commitClipBarDrag() }
    }

    /// A piece taken hold of. With more than one piece that is a carry — the
    /// order is the thing there is to change — and with one it is the clip
    /// sliding along the document, because a clip of one piece has no order to
    /// rearrange. ⌘ always means the whole clip.
    private func carry(_ pieces: ClipPieces, index: Int) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                if editorState.clipBarDrag == nil {
                    let whole = pieces.count == 1
                        || NSEvent.modifierFlags.contains(.command)
                    editorState.beginClipBarDrag(layerID: layerID,
                                                 grab: whole ? .body : .carry(piece: index))
                }
                editorState.updateClipBarDrag(
                    byMS: Self.ms(value.translation.width, laneWidth: laneWidth,
                                  ruler: editorState.motionStripRuler))
            }
            .onEnded { _ in editorState.commitClipBarDrag() }
    }

    /// How many milliseconds a sideways travel is worth on this ruler.
    static func ms(_ points: CGFloat, laneWidth: CGFloat, ruler: MotionStripRuler) -> Int {
        Int(ruler.ms(atFraction: Double(points / max(1, laneWidth))).rounded())
    }

    // MARK: What a drag draws

    /// The line a caught edge lands on. A wide soft band behind a hard line,
    /// because the commonest thing to catch on is the PLAYHEAD, whose own line
    /// is drawn over the top of this one: without the band there, a catch on
    /// the playhead would be invisible at exactly the moment it mattered most.
    private func snapLine(atMS ms: Int, ruler: MotionStripRuler) -> some View {
        ZStack {
            Capsule()
                .fill(Color.green.opacity(0.35))
                .frame(width: 8, height: MotionStripView.barHeight + 10)
            Rectangle()
                .fill(Color.green)
                .frame(width: 2, height: MotionStripView.barHeight + 10)
        }
        .offset(x: laneWidth * ruler.fraction(ofMS: Double(ms)) - 4, y: -5)
        .allowsHitTesting(false)
    }

    /// The numbers, said ON the row rather than over it.
    ///
    /// Over it is where it wants to be and where it cannot go: the lanes
    /// scroll, so anything drawn above the top one is cut off by the ruler.
    /// On the row it is always whole, and it is only there while the hand is
    /// down.
    private func capsule(_ text: String, x: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(.thickMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(.separator, lineWidth: 0.5) }
            .fixedSize()
            .offset(x: max(0, min(x + 10, laneWidth - 150)))
            .allowsHitTesting(false)
    }

    /// What a walk reads off the bar: the pieces, what each is doing, and the
    /// numbers a drag in flight is making.
    private var readoutText: String {
        let pieces = shownPieces
        var words = "\(layerName) \(bar.inMS) to \(bar.outMS) ms"
        if pieces.count > 1 { words += ", \(pieces.count) pieces" }
        for index in 0..<pieces.count {
            if let badge = Self.badge(pieces.piece(at: index)) {
                words += ", piece \(index + 1) \(badge)"
            }
        }
        if let readout = editorState.clipBarReadout, isBeingDragged {
            words += ", dragging \(readout)"
            if let snap = editorState.clipBarSnap { words += ", \(ClipBarCopy.caught(on: snap))" }
        }
        return words
    }
}
