import AppKit
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
    /// Whether this bar carries a sound, which is what puts a waveform inside
    /// its pieces and a level line across the whole of it
    /// (`docs/design/video-audio.md`).
    var isSound: Bool = false
    /// What the clip is, on the timeline dock (`TimelineDock.swift`): drawn in
    /// the video kit's colour for its kind, with its name inside, the way
    /// `video.html` draws a clip. Nil is the timing strip's plain grey bar.
    var kind: VideoKit.ClipKind?
    /// The lane's height, where the dock sets one.
    var height: CGFloat?
    /// This bar is a clip's own sound, drawn on the audio track under the
    /// clip and LINKED to it: every drag on it is a drag on the clip, so the
    /// two move, trim and cut as one until Detach Audio parts them.
    var isLinkedSound = false

    /// What a walk and the help call this bar's parts: the clip's name, or
    /// "<clip> sound" for its linked sound, so the two are never confused.
    private var fieldName: String { isLinkedSound ? "\(layerName) sound" : layerName }

    @State private var isHovered = false
    /// A fade handle in the hand: which end, and how long the fade would be.
    @State private var fadeDrag: FadeDrag?

    private struct FadeDrag: Equatable {
        let isIn: Bool
        var ms: Int
    }

    /// A key diamond in the hand: where it was, and where it would land.
    @State private var keyDrag: KeyDrag?

    private struct KeyDrag: Equatable {
        let fromMS: Int
        var toMS: Int
    }

    /// How tall the bar is drawn. A sound's is taller, because a waveform
    /// squeezed into eighteen points is a smear and a level line needs room to
    /// be dragged up and down in.
    private var barHeight: CGFloat {
        if let height { return height }
        return isSound ? MotionStripView.soundBarHeight : MotionStripView.barHeight
    }

    /// The kit's corner on the dock, the strip's own everywhere else.
    private var cornerRadius: CGFloat { kind == nil ? 4 : VideoKit.Metrics.clipCornerRadius }

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
        let shift = laneWidth * ruler.fraction(spanningMS: Double(headShiftMS))
        let x0 = laneWidth * ruler.fraction(ofMS: Double(bar.inMS)) + shift
        return ZStack(alignment: .topLeading) {
            // The dock's lane is bare, as the mock's is: the gridlines under
            // it say where time is, and a grey trough would be a second clip.
            if kind == nil {
                RoundedRectangle(cornerRadius: 5)
                    .fill(.quaternary.opacity(0.5))
                    .frame(height: barHeight)
            }
            if headShiftMS > 0 {
                spare(width: shift, reading: ClipBarCopy.length(headShiftMS))
                    .offset(x: laneWidth * ruler.fraction(ofMS: Double(bar.inMS)))
            }
            if let behind = spareBehindMS, behind > 0 {
                spare(width: laneWidth * ruler.fraction(spanningMS: Double(behind)),
                      reading: ClipBarCopy.length(behind))
                    .offset(x: x0 + laneWidth * ruler.fraction(spanningMS: Double(pieces.totalLengthMS)))
            }
            ForEach(0..<pieces.count, id: \.self) { index in
                piece(pieces, index: index, x0: x0, ruler: ruler)
            }
            // The bands over the joins, UNDER the grips: a transition is drawn
            // over the seam because that is what it is, an interval where both
            // pieces are on screen, rather than a third object wedged between
            // them (`docs/design/video-transitions.md`).
            ForEach(shownCuts(pieces), id: \.index) { cut in
                band(cut, x0: x0, ruler: ruler)
            }
            // Where this bar runs under a hold that pushed the picture alone,
            // and is therefore no longer in step with it (`HoldPush.swift`).
            // Drawn UNDER the grips, and drawn nowhere else: a document nobody
            // has frozen, and one frozen with everything waiting, are both
            // left clean.
            ForEach(editorState.holdDrifts(forLayer: layerID), id: \.atMS) { drift in
                driftMark(drift, ruler: ruler)
            }
            ForEach(0...pieces.count, id: \.self) { edge in
                grip(pieces, edge: edge, x0: x0, ruler: ruler)
            }
            // What the tiles at a join grow out of: a point on the cut, apart
            // from the grip, which is redrawn as the cut is picked.
            if kind != nil, !isLinkedSound, Experiments.shared.transitionsAtACutEnabled {
                ForEach(pieces.cutIndices, id: \.self) { index in
                    Color.clear
                        .frame(width: 1, height: barHeight)
                        .allowsHitTesting(false)
                        .transitionPicker(at: .join(clip: layerID, index: index), editorState: editorState)
                        .offset(x: x0 + laneWidth * ruler.fraction(spanningMS: Double(pieces.startMS(ofPiece: index))))
                }
            }
            // A diamond for every moment something on the layer is keyed
            // (`ClipKeys.swift`): drag it in time, right-click it to ease it.
            if kind != nil, !isLinkedSound {
                let marks = editorState.clipKeyMarks(layerID: layerID)
                ForEach(Array(marks.enumerated()), id: \.element.documentMS) { index, mark in
                    // Only the diamonds in the window: the rest are scrolled
                    // off, and padding cannot place one off the left edge.
                    let x = laneWidth * ruler.fraction(ofMS: Double(mark.documentMS))
                    if x >= 0, x <= laneWidth + 6 {
                        keyDiamond(mark, index: index, ruler: ruler)
                    }
                }
                if let keyDrag {
                    capsule(MotionStripRuler.timecode(Double(keyDrag.toMS)),
                            x: laneWidth * ruler.fraction(ofMS: Double(keyDrag.toMS)) + 10)
                        .frame(height: barHeight)
                }
            }
            if isSound {
                levelLine(pieces, x0: x0, ruler: ruler)
                if kind != nil, isPicked || isHovered {
                    fadeHandles(pieces, x0: x0, ruler: ruler)
                }
            }
            if let snap = editorState.clipBarSnap, isBeingDragged {
                snapLine(atMS: snap.ms, ruler: ruler)
            }
            if let readout = editorState.clipBarReadout, isBeingDragged {
                capsule(readout, x: x0)
                    .frame(height: barHeight)
            }
            if editorState.renamingClipID == layerID, !isLinkedSound {
                ClipNameField(layerID: layerID, name: layerName)
                    .frame(width: max(90, min(180, laneWidth * ruler.fraction(spanningMS: Double(pieces.totalLengthMS)) - 8)))
                    .frame(height: barHeight)
                    .offset(x: max(0, x0) + 4)
            }
        }
        .frame(width: laneWidth, alignment: .leading)
        .playtestHover("\(fieldName) bar") { inside in if kind != nil, isSound { isHovered = inside } }
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
        // A free start is not a trim: the bar itself is already drawn where the
        // hand has it, because its in point moved, and there is no spare behind
        // it to draw. Shifting it again would double the drag
        // (`TitleTime.swift`).
        guard !session.drag.startIsFree else { return 0 }
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
                .frame(width: width, height: barHeight)
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
        let x = x0 + laneWidth * ruler.fraction(spanningMS: Double(start))
        // A hairline of air at each join, so two pieces read as two rather
        // than as one long bar. It comes out of the piece, never out of the
        // clip, so the bar still ends exactly where the clip does.
        let raw = laneWidth * ruler.fraction(spanningMS: Double(length))
        let width = max(2, raw - (index == pieces.count - 1 ? 0 : 1.5))
        // Only the part of the piece that is on screen is drawn. Opened right
        // out, a five minute clip's bar is a hundred and eighty thousand
        // points wide, and a waveform sampled across the whole of it is a
        // hundred and eighty thousand columns nobody can see
        // (`TimelineSpan`). What shows is identical; the work is bounded by
        // the width of the window instead of by the zoom.
        let shown = TimelineSpan.drawn(x: x, width: width, across: laneWidth)
        let picked = isPiecePicked(index, of: pieces.count)
        if shown.width > 0 {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(fill(item, picked: picked))
            .overlay { kitFace(item, width: shown.width, hiddenLeading: max(0, -shown.x)) }
            .frame(width: shown.width, height: barHeight)
            .overlay {
                // The sound itself, drawn from the stretch of the file this
                // piece plays. So a cut piece shows the part of the file it
                // kept, wherever in the file that was, and a held frame shows
                // nothing because there is no sound under one frame. Read
                // across the part of the file the WINDOW is showing, which is
                // what makes a zoomed waveform real detail rather than the
                // same drawing stretched.
                if isSound, let item, item.playsSound, let wave = waveform,
                   shown.width >= 2 {
                    let file = Double(item.sourceOutMS - item.sourceInMS)
                    SoundWaveform(columns: wave.columns(
                        count: Int(shown.width),
                        fromSourceMS: item.sourceInMS + Int(file * Double(shown.startFraction)),
                        toSourceMS: item.sourceInMS + Int(file * Double(shown.endFraction))),
                        color: kind.map { $0.ink.opacity(0.7) } ?? .white.opacity(0.55))
                        .padding(.vertical, 2)
                }
            }
            .overlay {
                if kind == nil, let badge = Self.badge(item, isSound: isSound), shown.width > 22 {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 1)
                }
            }
            .overlay(alignment: .topTrailing) {
                if kind != nil, let badge = Self.badge(item, isSound: isSound), shown.width > 30 {
                    kitBadge(badge)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                // `outline: 2px; outline-offset: 1px`: picked is a ring round
                // the clip in the accent, never a change to the clip's colour,
                // which says what the clip IS.
                if kind != nil, picked {
                    RoundedRectangle(cornerRadius: cornerRadius + 2)
                        .strokeBorder(VideoKit.Palette.accent, lineWidth: 2)
                        .padding(-3)
                        .allowsHitTesting(false)
                }
            }
            // Every hand on a piece, the right click included, is added
            // BEFORE the offset, the order the band over a cut uses. Added
            // after it, the right click answered for the lane's left edge and
            // landed on whichever piece was drawn last (2026-09-23).
            .contentShape(Rectangle())
            .gesture(carry(pieces, index: index))
            .onTapGesture {
                // A click on the clip takes it rather than any keys picked on
                // its lanes, so ⌫ afterwards means the clip.
                editorState.clearKeySelection()
                editorState.selectClipPiece(layerID: layerID,
                                            index: pieces.count > 1 ? index : nil)
                // A double click on a caption opens its words for typing, in
                // place, the way Premiere edits a caption on its track.
                if (NSApp.currentEvent?.clickCount ?? 1) >= 2,
                   editorState.document?.layer(id: layerID)?.isCaption == true {
                    editorState.beginRenamingClip(layerID)
                }
            }
            .contextMenu {
                if kind != nil { TimelineClipMenu(layerID: layerID, piece: index) }
            }
            .offset(x: shown.x)
            .playtestField(Self.pieceName(layerName: fieldName, index: index, of: pieces.count))
            .panelHelp(Self.help(pieces, index: index))
        }
    }

    /// The shape of this layer's sound, once it has been read off the file.
    /// Asked for every time the bar draws, and asked for in the background the
    /// first time, so a bar with no waveform in it yet is a bar rather than a
    /// wait (`SoundFiles.swift`).
    private var waveform: Waveform? {
        guard let sound = editorState.document?.layer(id: layerID)?.sound else { return nil }
        if let already = SoundLibrary.shared.waveform(for: sound) { return already }
        SoundLibrary.shared.loadWaveform(for: sound)
        return nil
    }

    /// The level, across the WHOLE bar rather than per piece: it is a property
    /// of the layer measured from the layer's own start, so it runs over the
    /// joins the way it runs over everything else.
    @ViewBuilder
    private func levelLine(_ pieces: ClipPieces, x0: CGFloat,
                           ruler: MotionStripRuler) -> some View {
        let whole = laneWidth * ruler.fraction(spanningMS: Double(pieces.totalLengthMS))
        let shown = TimelineSpan.drawn(x: x0, width: whole, across: laneWidth)
        if shown.width > 4 {
            SoundLevelLine(layerID: layerID, layerName: layerName,
                           level: editorState.document?.layer(id: layerID)?.soundLevel
                               ?? AudioLevel(),
                           lengthMS: pieces.totalLengthMS,
                           // The stretch of the layer that is on screen, so a
                           // dot is drawn and dragged in the window's own
                           // scale rather than off a bar wider than the Mac.
                           fromMS: Int(Double(pieces.totalLengthMS) * Double(shown.startFraction)),
                           toMS: Int(Double(pieces.totalLengthMS) * Double(shown.endFraction)),
                           width: shown.width, height: barHeight,
                           lineColor: kind == nil ? .white.opacity(0.95)
                               : Color(red: 0xBF / 255, green: 0xF3 / 255, blue: 0xE4 / 255))
                .offset(x: shown.x)
        }
    }

    /// What the dock draws inside a piece: the lit top edge every clip in the
    /// mock has, a veil over a held frame, and the clip's name where there is
    /// room to read it.
    /// `hiddenLeading` is how much of the piece is off the left edge of the
    /// window, so the name stays in sight on a zoomed timeline rather than
    /// sliding out with the clip's start.
    @ViewBuilder private func kitFace(_ piece: ClipPiece?, width: CGFloat,
                                      hiddenLeading: CGFloat) -> some View {
        if let kind {
            ZStack(alignment: isSound ? .topLeading : .leading) {
                if let border = kind.border {
                    RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(border)
                }
                if piece?.isHeld == true {
                    Color.black.opacity(0.4)
                }
                VStack(spacing: 0) {
                    Rectangle().fill(Color.white.opacity(0.18)).frame(height: 1)
                        .padding(.horizontal, cornerRadius / 2)
                    Spacer(minLength: 0)
                }
                // A clip's own sound is named by the picture right above it,
                // and the mock's sound segment carries no words.
                if width - hiddenLeading > 40, !isLinkedSound {
                    Text(layerName)
                        .font(.system(size: isSound ? 9 : 9.5, weight: .semibold))
                        .foregroundStyle(kind.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .shadow(color: .black.opacity(0.35), radius: 1)
                        .padding(.leading, isSound ? 14 : 8)
                        .padding(.trailing, 8)
                        .padding(.top, isSound ? 3 : 0)
                        .frame(maxWidth: width - hiddenLeading - 4, alignment: .leading)
                        .padding(.leading, hiddenLeading)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// A speed or a hold, as the kit's clip wears it: a dark chip in the top
    /// corner rather than words across the middle of the picture.
    private func kitBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.5)))
            .padding(.top, 3)
            .padding(.trailing, 4)
            .allowsHitTesting(false)
    }

    private func fill(_ piece: ClipPiece?, picked: Bool) -> AnyShapeStyle {
        if let kind { return kind.fill }
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

    /// The mark on a bar that a hold elsewhere has left out of step with the
    /// picture: a hairline where the hold is, and how far out everything from
    /// there on now is.
    ///
    /// This is the freeze clickthrough's own closing question answered the
    /// narrow way. It asked whether the timeline should show the drift or
    /// whether that would clutter the common case; it is shown only where
    /// there IS drift, which is the case nobody wants to find out about at the
    /// end of the edit.
    @ViewBuilder
    private func driftMark(_ drift: HoldDrift, ruler: MotionStripRuler) -> some View {
        let x = laneWidth * ruler.fraction(ofMS: Double(drift.atMS))
        if x >= 0, x <= laneWidth {
            HStack(spacing: 3) {
                Rectangle()
                    .fill(Color.orange.opacity(0.95))
                    .frame(width: 1.5, height: barHeight)
                Text(drift.label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.orange)
                    .fixedSize()
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    // A chip under the words, because they are drawn over a
                    // waveform and orange on a waveform is a smudge.
                    .background(RoundedRectangle(cornerRadius: 3).fill(.black.opacity(0.65)))
            }
            .frame(height: barHeight, alignment: .leading)
            .offset(x: x)
            .allowsHitTesting(false)
            .panelReadout(drift.label)
            .playtestField("\(layerName) out of step")
            .help(drift.sentence)
        }
    }

    /// What is written on a piece that is not playing at the speed it was
    /// recorded at. Nothing at all on an ordinary one, because a badge on
    /// every piece is a badge that says nothing.
    static func badge(_ piece: ClipPiece?, isSound: Bool = false) -> String? {
        guard let piece else { return nil }
        // A held piece on a SOUND is not a frame standing still, it is the
        // quiet a hold on the picture pushed into it. Same piece, and the word
        // for it is different because what you get is different.
        if piece.isHeld { return isSound ? "silence" : "hold" }
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

    // MARK: The fades

    /// A handle at each top corner of a sound's segment: drag the left one in
    /// to fade in, the right one in to fade out. The level line draws the
    /// fade itself, because a fade IS the level falling to silence.
    @ViewBuilder
    private func fadeHandles(_ pieces: ClipPieces, x0: CGFloat,
                             ruler: MotionStripRuler) -> some View {
        let length = pieces.totalLengthMS
        let level = editorState.document?.layer(id: layerID)?.soundLevel ?? AudioLevel()
        let fadeIn = fadeDrag.flatMap { $0.isIn ? $0.ms : nil } ?? level.fadeInMS
        let fadeOut = fadeDrag.flatMap { $0.isIn ? nil : $0.ms } ?? level.fadeOutMS(lengthMS: length)
        let whole = laneWidth * ruler.fraction(spanningMS: Double(length))
        let inWidth = laneWidth * ruler.fraction(spanningMS: Double(fadeIn))
        let outWidth = laneWidth * ruler.fraction(spanningMS: Double(fadeOut))
        if whole >= Self.smallestGrabbablePiece * 2 {
            if let drag = fadeDrag {
                // The fade the hand is making, before it is let go.
                FadeWedge(isIn: drag.isIn)
                    .fill(Color.black.opacity(0.35))
                    .frame(width: drag.isIn ? inWidth : outWidth, height: barHeight)
                    .offset(x: drag.isIn ? x0 : x0 + whole - outWidth)
                    .allowsHitTesting(false)
                capsule(ClipBarCopy.length(drag.ms), x: drag.isIn ? x0 + inWidth : x0 + whole - outWidth - 90)
                    .frame(height: barHeight)
            }
            fadeHandle(isIn: true, fromMS: level.fadeInMS, lengthMS: length, ruler: ruler)
                .offset(x: min(x0 + whole - 9, x0 + max(1, inWidth - 4)))
            fadeHandle(isIn: false, fromMS: level.fadeOutMS(lengthMS: length), lengthMS: length, ruler: ruler)
                .offset(x: max(x0, x0 + whole - max(9, outWidth + 4)))
        }
    }

    private func fadeHandle(isIn: Bool, fromMS: Int, lengthMS: Int,
                            ruler: MotionStripRuler) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white)
            .overlay { RoundedRectangle(cornerRadius: 2).strokeBorder(Color.black.opacity(0.35), lineWidth: 0.5) }
            .frame(width: 8, height: 8)
            .padding(.top, 1)
            .contentShape(Rectangle().inset(by: -4))
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let moved = Self.ms(value.translation.width, laneWidth: laneWidth, ruler: ruler)
                    let ms = min(max(0, fromMS + (isIn ? moved : -moved)), lengthMS)
                    fadeDrag = FadeDrag(isIn: isIn, ms: ms)
                }
                .onEnded { _ in
                    if let drag = fadeDrag {
                        editorState.selectLayer(layerID)
                        editorState.setSoundFade(onLayer: layerID, fadeIn: drag.isIn, ms: drag.ms)
                    }
                    fadeDrag = nil
                })
            .playtestField("\(fieldName) fade \(isIn ? "in" : "out")")
            .panelHelp(isIn ? "Fade in: drag right" : "Fade out: drag left")
    }

    // MARK: Keys

    /// How near the playhead, in points, a dragged key has to come to land on it.
    private static let keySnap: CGFloat = 6

    /// One key diamond on the clip. Drag it along to move every key at that
    /// moment; click it to put the playhead on it; right-click it for how it
    /// eases, and to delete it.
    private func keyDiamond(_ mark: ClipKeyMark, index: Int, ruler: MotionStripRuler) -> some View {
        let dragging = keyDrag?.fromMS == mark.documentMS
        let ms = dragging ? (keyDrag?.toMS ?? mark.documentMS) : mark.documentMS
        let x = laneWidth * ruler.fraction(ofMS: Double(ms))
        let ease = editorState.document?.clipKeyEase(layerID: layerID, atMS: mark.documentMS)
        let eased = ease.map { $0 != .linear } ?? true
        let names = mark.properties.map(\.title).joined(separator: ", ")
        return VideoKit.KeyMark(isEased: eased)
            .scaleEffect(dragging ? 1.35 : 1)
            // A small square to hold, not the bar's full height: a key at the
            // very start or end of a clip sits on its trim grip, and the grip
            // stays in reach above and below it.
            .frame(width: 12, height: 12)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { value in
                    let moved = Self.ms(value.translation.width, laneWidth: laneWidth, ruler: ruler)
                    var landing = mark.documentMS + moved
                    // It lands on the playhead when it comes near, the way a
                    // clip's edge does.
                    let playhead = editorState.documentTimeMS
                    let gap = laneWidth * ruler.fraction(spanningMS: Double(abs(landing - playhead)))
                    if gap <= Self.keySnap { landing = playhead }
                    keyDrag = KeyDrag(fromMS: mark.documentMS, toMS: landing)
                }
                .onEnded { _ in
                    if let drag = keyDrag {
                        editorState.moveClipKeys(layerID: layerID, fromMS: drag.fromMS, toMS: drag.toMS)
                    }
                    keyDrag = nil
                })
            .onTapGesture { editorState.pickClipKey(layerID: layerID, atMS: mark.documentMS) }
            .contextMenu {
                MenuRowsView(rows: editorState.clipKeyMenuRows(layerID: layerID, atMS: mark.documentMS))
            }
            .playtestControl("Key \(index + 1)", detail: layerName)
            .panelHelp("\(MotionStripRuler.timecode(Double(mark.documentMS))): \(names)")
            // Placed by padding rather than an offset, so the diamond's frame
            // is where it is drawn and a walk's right click lands on it.
            .padding(.leading, max(0, x - 6))
            .padding(.top, (barHeight - 12) / 2)
    }

    // MARK: The band over a cut

    /// The cuts worth drawing something on: the ones carrying a transition.
    /// An untouched cut draws nothing and takes no width, because nothing is
    /// there.
    private func shownCuts(_ pieces: ClipPieces) -> [ClipCut] {
        // A transition is drawn once, on the picture it dissolves.
        guard Experiments.shared.transitionsAtACutEnabled, !isLinkedSound else { return [] }
        return pieces.cuts.filter { $0.drawnTransition != nil }
    }

    /// One transition, drawn across its join: a band as long as the transition
    /// is, centred on the cut, with a grip at each end to make it longer or
    /// shorter. Both ends do the same thing, because a transition is measured
    /// ACROSS the join and never sits to one side of it.
    @ViewBuilder
    private func band(_ cut: ClipCut, x0: CGFloat, ruler: MotionStripRuler) -> some View {
        if let transition = cut.drawnTransition {
            let width = laneWidth * ruler.fraction(spanningMS: Double(transition.lengthMS))
            let x = x0 + laneWidth * ruler.fraction(spanningMS: Double(cut.atMS - transition.beforeMS))
            let picked = editorState.selectedClipCutIndex == cut.index && isPicked
            ZStack {
                if kind != nil {
                    VideoKit.TransitionBand(isDip: !transition.kind.needsOverlap,
                                            isSelected: picked, height: barHeight)
                } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.accentColor.opacity(picked ? 0.55 : 0.35))
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(.white.opacity(picked ? 0.9 : 0.5), lineWidth: 1)
                    }
                }
                if kind == nil, width > 30 {
                    Text(ClipTransitionCopy.length(transition.lengthMS))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .shadow(radius: 1)
                }
            }
            .frame(width: max(3, min(width, laneWidth + TimelineSpan.slack * 2)), height: barHeight)
            .contentShape(Rectangle())
            // One click picks the cut; two open its tiles, to change what is on it.
            .onTapGesture(count: 2) {
                editorState.openTransitionPicker(at: .join(clip: layerID, index: cut.index))
            }
            .onTapGesture { editorState.selectClipCut(layerID: layerID, index: cut.index) }
            .contextMenu {
                if kind != nil { TimelineCutMenu(layerID: layerID, cut: cut.index) }
            }
            .overlay(alignment: .leading) { bandGrip(cut, leading: true, width: width) }
            .overlay(alignment: .trailing) { bandGrip(cut, leading: false, width: width) }
            .offset(x: x)
            .playtestField(Self.bandName(layerName: layerName, cut: cut.index))
            .panelHelp("\(transition.kind.title) over the join after piece \(cut.index). "
                       + "Drag either end to change how long it takes.")
        }
    }

    /// One end of a band. It goes away on a band too narrow to hold two, for
    /// the same reason a piece's grips do: a grip you cannot help but hit is
    /// worse than no grip at all, and the panel's own Length row is always
    /// there.
    @ViewBuilder
    private func bandGrip(_ cut: ClipCut, leading: Bool, width: CGFloat) -> some View {
        if width >= Self.smallestGrabbablePiece {
            Rectangle()
                .fill(.white.opacity(0.85))
                .frame(width: 3, height: barHeight - 4)
                .contentShape(Rectangle().inset(by: -5))
                .gesture(bandDrag(cut, leading: leading))
        }
    }

    private func bandDrag(_ cut: ClipCut, leading: Bool) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if editorState.clipTransitionDrag == nil {
                    editorState.beginClipTransitionDrag(layerID: layerID, cutIndex: cut.index,
                                                        leadingEdge: leading)
                }
                editorState.updateClipTransitionDrag(
                    byMS: Self.ms(value.translation.width, laneWidth: laneWidth,
                                  ruler: editorState.motionStripRuler))
            }
            .onEnded { _ in editorState.commitClipTransitionDrag() }
    }

    static func bandName(layerName: String, cut: Int) -> String {
        "\(layerName) transition at join \(cut)"
    }

    // MARK: The grips

    /// One grip per edge: nought is the clip's in point, and every other one
    /// is the join after the piece before it, which for the last is the clip's
    /// out point.
    @ViewBuilder
    private func grip(_ pieces: ClipPieces, edge: Int, x0: CGFloat,
                      ruler: MotionStripRuler) -> some View {
        let ms = edge == 0 ? 0 : (pieces.rangeMS(ofPiece: edge - 1)?.end ?? 0)
        let x = x0 + laneWidth * ruler.fraction(spanningMS: Double(ms))
        let room = min(neighbourWidth(pieces, edge: edge, ruler: ruler),
                       Self.gripWidth * 3)
        let width = max(3, min(Self.gripWidth, room / 3))
        if isPicked, room >= Self.smallestGrabbablePiece {
            gripFace(width: width)
                .frame(width: width, height: barHeight)
                .contentShape(Rectangle().inset(by: -5))
                .gesture(edgeDrag(pieces, edge: edge, ruler: ruler))
                // A join is a CUT, and a cut is a thing you can pick: one click
                // and the panel is talking about what happens there. Dragging
                // the same grip still trims, because the two gestures are told
                // apart by whether the hand moved.
                // With transitions on, the click also opens the tiles right at
                // the cut (`video-transition-wt.html`, "At this cut").
                .onTapGesture {
                    guard edge > 0, edge < pieces.count else { return }
                    editorState.selectClipCut(layerID: layerID, index: edge)
                    if kind != nil, !isLinkedSound {
                        editorState.openTransitionPicker(at: .join(clip: layerID, index: edge))
                    }
                }
                // A join is a cut, so its right click is the cut's menu; the
                // bar's two ends are the clip's own and answer with the clip's.
                .contextMenu {
                    if kind != nil {
                        if edge > 0, edge < pieces.count {
                            TimelineCutMenu(layerID: layerID, cut: edge)
                        } else {
                            TimelineClipMenu(layerID: layerID, piece: edge == 0 ? 0 : pieces.count - 1)
                        }
                    }
                }
                // Pressable by a walk by the same name, marked before the
                // offset below so the mark moves with the grip.
                .playtestControl(Self.gripName(layerName: fieldName, edge: edge, of: pieces.count),
                                 detail: "Timeline")
                // The first grip sits inside the bar and the rest hang off the
                // join to its left, so a grip never covers the piece after it.
                .offset(x: x - (edge == 0 ? 0 : width))
                .playtestField(Self.gripName(layerName: fieldName, edge: edge, of: pieces.count))

                .panelHelp(edge == 0
                           ? "Where the clip starts. Drag it: nothing is thrown away."
                           : (edge == pieces.count
                              ? "Where the clip ends. Drag it."
                              : "The join after piece \(edge). Drag it."))
        }
    }

    /// A grip as the strip draws it (an accent capsule), or as the kit's clip
    /// does (a white bar with a dark hairline, readable on any clip colour).
    @ViewBuilder private func gripFace(width: CGFloat) -> some View {
        if kind == nil {
            Capsule()
                .fill(Color.accentColor)
                .overlay { Capsule().strokeBorder(Color.white.opacity(0.75), lineWidth: 1) }
        } else {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white)
                .overlay { RoundedRectangle(cornerRadius: 2).strokeBorder(Color.black.opacity(0.3), lineWidth: 0.5) }
                .frame(width: min(4, width))
                .padding(.vertical, 5)
                .frame(width: width)
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
        return laneWidth * ruler.fraction(spanningMS: Double(smallest))
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
        // On the dock the pointer is read in the tracks' own space too, so a
        // clip carried up or down lands on the track under it, or on a new
        // one between two (`EditorState+Tracks`).
        DragGesture(minimumDistance: 3,
                    coordinateSpace: kind == nil ? .local : .named(TimelineDock.tracksSpace))
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
                // A linked sound goes where its clip goes, along time only:
                // up or down would be a picture landing on a sound track.
                if kind != nil, !isLinkedSound {
                    editorState.updateClipTrackDrop(pointerY: value.location.y,
                                                    travelledY: value.translation.height)
                }
            }
            .onEnded { _ in editorState.commitClipBarDrag() }
    }

    /// How many milliseconds a sideways travel is worth on this ruler.
    static func ms(_ points: CGFloat, laneWidth: CGFloat, ruler: MotionStripRuler) -> Int {
        // A TRAVEL rather than a moment: how far the hand moved has nothing to
        // do with where the window starts (`TimelineZoom.swift`).
        Int(ruler.msSpanning(fraction: Double(points / max(1, laneWidth))).rounded())
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
                .frame(width: 8, height: barHeight + 10)
            Rectangle()
                .fill(Color.green)
                .frame(width: 2, height: barHeight + 10)
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
        var words = "\(fieldName) \(bar.inMS) to \(bar.outMS) ms"
        if pieces.count > 1 { words += ", \(pieces.count) pieces" }
        for index in 0..<pieces.count {
            if let badge = Self.badge(pieces.piece(at: index)) {
                words += ", piece \(index + 1) \(badge)"
            }
        }
        for cut in shownCuts(pieces) {
            guard let transition = cut.drawnTransition else { continue }
            words += ", \(transition.kind.title.lowercased()) "
                + "\(ClipTransitionCopy.length(transition.lengthMS)) at join \(cut.index)"
        }
        if isSound, let level = editorState.document?.layer(id: layerID)?.soundLevel {
            if level.gain != AudioLevel.unityGain { words += ", level \(level.label)" }
            let fadeIn = level.fadeInMS
            let fadeOut = level.fadeOutMS(lengthMS: pieces.totalLengthMS)
            if fadeIn > 0 { words += ", fade in \(ClipBarCopy.length(fadeIn))" }
            if fadeOut > 0 { words += ", fade out \(ClipBarCopy.length(fadeOut))" }
        }
        if let readout = editorState.clipBarReadout, isBeingDragged {
            words += ", dragging \(readout)"
            if let snap = editorState.clipBarSnap { words += ", \(ClipBarCopy.caught(on: snap))" }
        }
        if let readout = editorState.clipTransitionReadout,
           editorState.clipTransitionDrag?.layerID == layerID {
            words += ", dragging the transition to \(readout)"
        }
        return words
    }
}

/// The shape a fade in flight is drawn with: the part of the segment the fade
/// takes the sound out of.
private struct FadeWedge: Shape {
    let isIn: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if isIn {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

/// What a right-click on a clip on the timeline offers
/// (`EditorState+TimelineMenus`).
struct TimelineClipMenu: View {
    @Environment(EditorState.self) private var editorState
    let layerID: UUID
    var piece: Int = 0

    var body: some View {
        MenuRowsView(rows: editorState.timelineClipMenuRows(layerID: layerID, piece: piece))
    }
}

/// What a right-click on a join, or the transition over one, offers.
struct TimelineCutMenu: View {
    @Environment(EditorState.self) private var editorState
    let layerID: UUID
    let cut: Int

    var body: some View {
        MenuRowsView(rows: editorState.timelineCutMenuRows(layerID: layerID, cut: cut))
    }
}

/// A clip's name, typed over its bar after Rename. Return keeps it, Escape or
/// clicking away leaves the name as it was.
private struct ClipNameField: View {
    @Environment(EditorState.self) private var editorState
    let layerID: UUID
    let name: String
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $draft)
            .textFieldStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 4)
            .frame(height: 18)
            .background(RoundedRectangle(cornerRadius: 4).fill(VideoKit.Palette.panel))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(VideoKit.Palette.accent))
            .focused($isFocused)
            .onSubmit { commit() }
            .onExitCommand { editorState.renamingClipID = nil }
            .onChange(of: isFocused) { _, focused in
                if !focused { editorState.renamingClipID = nil }
            }
            .onAppear {
                draft = editorState.captionWords(of: layerID) ?? name
                isFocused = true
            }
            .playtestControl("Clip name", detail: "Timeline")
    }

    /// A caption's field edits its words; any other clip's, its name.
    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if editorState.captionWords(of: layerID) != nil {
            editorState.setCaptionText(id: layerID, to: trimmed)
        } else if !trimmed.isEmpty, trimmed != name {
            editorState.renameLayer(id: layerID, to: trimmed)
        }
        editorState.renamingClipID = nil
    }
}
