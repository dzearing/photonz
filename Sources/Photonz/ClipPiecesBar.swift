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
    @Environment(\.colorScheme) private var colorScheme
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
    /// The sound lane's own colour (`VideoKit.Palette.soundTrack`): the ring
    /// round its fade diamonds and the fill of its level points.
    var soundTint: Color = VideoKit.Palette.soundTrack(0)

    /// What a walk and the help call this bar's parts: the clip's name, or
    /// "<clip> sound" for its linked sound, so the two are never confused.
    private var fieldName: String { isLinkedSound ? "\(layerName) sound" : layerName }

    @State private var isHovered = false
    /// A fade handle in the hand: which end, and how long the fade would be.
    @State private var fadeDrag: FadeDrag?
    /// A picture fade handle in the hand, on a clip, a title or a shape.
    @State private var pictureFadeDrag: FadeDrag?
    /// The level while the level line or one of its dots is in a hand, before
    /// it is let go, so the waveform follows the drag.
    @State private var levelInHand: AudioLevel?

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
        #if PHOTONZ_PLAYTEST
        let _ = ViewBuildMeter.shared.built(.clipBar)
        #endif
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
            if !isLinkedSound, let session = editorState.clipTransitionDrag, session.layerID == layerID,
               case .join(_, let index) = session.place, let cut = pieces.cut(at: index) {
                TransitionLengthBubble(
                    pointerX: x0 + laneWidth * ruler.fraction(
                        spanningMS: Double(cut.atMS + session.pointerFromCutMS)),
                    laneWidth: laneWidth, height: barHeight)
            }
            // Where this bar runs under a hold that pushed the picture alone,
            // and is therefore no longer in step with it (`HoldPush.swift`).
            // Drawn UNDER the grips, and drawn nowhere else: a document nobody
            // has frozen, and one frozen with everything waiting, are both
            // left clean.
            ForEach(editorState.holdDrifts(onBarOf: layerID), id: \.atMS) { drift in
                driftMark(drift, ruler: ruler)
            }
            // The level line, UNDER the grips: its band is twelve points
            // tall and at most levels it runs straight across a grip's middle,
            // so drawn above them it took the press a grip is there for and a
            // trim became a nudge to the volume (2026-10-07). Everywhere else
            // along the segment it is still the line that answers.
            if isSound {
                levelLine(pieces, x0: x0, ruler: ruler)
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
                let marks = editorState.clipKeyMarks(onBarOf: layerID)
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
                // Always there, as the mock draws them on every lane: a handle
                // you have to hover to find is a handle nobody finds.
                if kind != nil, !isLinkedSound {
                    soundTag(pieces, x0: x0, ruler: ruler)
                }
                if kind != nil {
                    fadeHandles(pieces, x0: x0, ruler: ruler)
                }
            }
            if fadesPicture {
                pictureFadeRamps(pieces, x0: x0, ruler: ruler)
            }
            if isBeingDragged, let snap = editorState.clipBarSnap {
                snapLine(atMS: snap.ms, ruler: ruler)
            }
            if isBeingDragged, let readout = editorState.clipBarReadout {
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
        .modifier(BarWatch(on: carriesWalkNames, name: "\(fieldName) bar", readout: readoutText) { inside in
            if kind != nil, isSound || fadesPicture { isHovered = inside }
        })
    }

    /// Whether this bar wears the names a walk finds it by. A caption cue does
    /// not: a five minute talk has 170 of them, and each name is a view of its
    /// own in the probe, five per bar, that the app a person runs never has.
    /// Zooming such a timeline out built 870 of them in one pass and froze the
    /// probe for 450ms where the app took 70 (`a-long-captioned-recording-walk`).
    /// Walks reach a cue through the editor's own caption actions instead.
    private var carriesWalkNames: Bool { kind != .caption }

    // MARK: What is on the bar

    /// The pieces as the strip is showing them. `shownDocument` already
    /// carries the drag in flight, so there is nothing to merge here.
    private var shownPieces: ClipPieces {
        editorState.shownDocument(forClip: layerID)?.layer(id: layerID)?.clipPieces
            ?? ClipPieces(single: bar)
    }

    private var isPicked: Bool { editorState.selectedLayerID == layerID }
    /// Whether this bar is in a drag at all, grabbed or carried along. Asked
    /// FIRST everywhere below, so a bar nobody is dragging never reads the
    /// drag and is not rebuilt at every move of somebody else's.
    private var isInHand: Bool { editorState.clipBarInHandIDs.contains(layerID) }
    private var isBeingDragged: Bool { isInHand && editorState.clipBarDrag?.layerID == layerID }

    /// How far the whole bar is drawn along while its left end is in a hand.
    /// Nought at every other moment, so nothing about the ordinary drawing
    /// knows this exists.
    private var headShiftMS: Int {
        guard isInHand, let session = editorState.clipBarDrag, session.layerID == layerID,
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
        guard isInHand, let session = editorState.clipBarDrag, session.layerID == layerID,
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
        // One of several clips picked with Shift: the whole clip is in hand.
        if !isPicked, editorState.multiSelectedLayerIDs.contains(layerID) { return true }
        // A piece a box over the tracks picked (`EditorState+TrackRange`).
        if !isPicked, editorState.isPiecePickedByBox(layerID: layerID, index: index) { return true }
        // On a track picked on its header: ⌫ takes it with the track.
        if !isPicked, editorState.goesWithTracksInHand(layerID, asSound: isLinkedSound) { return true }
        guard isPicked else { return false }
        guard count > 1 else { return true }
        // Mid-carry the bar is already drawn in the order it would land in, so
        // the piece in the hand is at its NEW place. Reading the picked index
        // straight off the selection would light up whatever piece happens to
        // sit at the old one, which is another piece entirely.
        if isInHand, let session = editorState.clipBarDrag, session.layerID == layerID,
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
        // A bar in one piece is never narrower than something a pointer can
        // take hold of: a frame long, zoomed out, is otherwise a hairline that
        // reads as gone (`a-shape-s-bar-never-vanishes-from-its-track-and`).
        let width = max(pieces.count == 1 ? 6 : 2, raw - (index == pieces.count - 1 ? 0 : 1.5))
        // Only the part of the piece that is on screen is drawn. Opened right
        // out, a five minute clip's bar is a hundred and eighty thousand
        // points wide, and a waveform sampled across the whole of it is a
        // hundred and eighty thousand columns nobody can see
        // (`TimelineSpan`). What shows is identical; the work is bounded by
        // the width of the window instead of by the zoom.
        let shown = TimelineSpan.drawn(x: x, width: width, across: laneWidth)
        let picked = isPiecePicked(index, of: pieces.count)
        let pictures = picturesOpacity
        if shown.width > 0 {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(fill(item, picked: picked))
            .overlay(alignment: .topLeading) {
                filmstrip(item, index: index, pieceWidth: raw, shown: shown, pictures: pictures)
            }
            .overlay { kitFace(item, width: shown.width,
                               hiddenLeading: max(0, -shown.x) + bandCover(pieces, piece: index, ruler: ruler),
                               pictures: pictures) }
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
                    let span = Double(length)
                    SoundWaveform(heights: Waveform.drawnHeights(
                        ofPeaks: wave.columns(
                            count: Int(shown.width),
                            fromSourceMS: item.sourceInMS + Int(file * Double(shown.startFraction)),
                            toSourceMS: item.sourceInMS + Int(file * Double(shown.endFraction))),
                        // Drawn at the level it plays at, fades and all, read
                        // across the same stretch of the layer the columns are.
                        level: drawnSoundLevel(lengthMS: pieces.totalLengthMS),
                        fromLayerMS: start + Int(span * Double(shown.startFraction)),
                        toLayerMS: start + Int(span * Double(shown.endFraction))),
                        color: kind == nil ? .white.opacity(0.55) : soundTint.opacity(0.55),
                        isShape: kind != nil)
                        .padding(.vertical, kind == nil ? 2 : 0)
                }
            }
            .overlay(alignment: .bottomLeading) {
                // The gain Normalize wrote, where Premiere puts a clip's
                // badges: on the clip, small, out of the waveform's way.
                // Beside it, whether its noise is cleaned, and while the
                // cleaned sound is being made, how far along that is (an EQ
                // or a compressor is made the same way, so it shows too).
                let progress = editorState.soundCleaningProgress(of: layerID)
                if isSound, shown.width > 48, soundLevel?.clipGainLabel != nil
                    || soundLevel?.activeNoiseReduction != nil || progress != nil {
                    soundBadge(gain: soundLevel?.clipGainLabel, cleaned: soundLevel?.activeNoiseReduction != nil,
                               progress: progress)
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
            // The copy badge, while ⌥ is down over the clip.
            .playtestHover(Self.pieceName(layerName: fieldName, index: index, of: pieces.count)) { inside in
                editorState.clipBarHover("\(layerID)/\(isLinkedSound)/\(index)", layerID: layerID, inside: inside)
            }
            .onDisappear {
                editorState.clipBarHover("\(layerID)/\(isLinkedSound)/\(index)", layerID: layerID, inside: false)
            }
            .gesture(carry(pieces, index: index))
            .onTapGesture {
                // A click on the clip takes it rather than any keys picked on
                // its lanes, so ⌫ afterwards means the clip.
                editorState.clearKeySelection()
                // Shift or ⌘ adds the clip to what is picked, or takes it out,
                // the way Premiere's timeline and the Layers list both do.
                // Where the timeline is the layer list this is the only way
                // left to pick two things at once without a sweep.
                let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
                if kind != nil, flags.contains(.shift) || flags.contains(.command) {
                    editorState.selectedClipPieceIndex = nil
                    editorState.extendSelection(toLayer: layerID)
                    return
                }
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
                if kind != nil { TimelineClipMenu(layerID: layerID, piece: index, onTheSound: isLinkedSound) }
            }
            // Named BEFORE the offset, as the grips are, so the mark is where
            // the piece is drawn: after it, the mark sat on the piece's
            // unshifted frame, so a walk pressed a clip that starts at five
            // seconds somewhere near nought, and a slid bar's mark never moved.
            .modifier(WalkNames(on: carriesWalkNames,
                                field: Self.pieceName(layerName: fieldName, index: index, of: pieces.count),
                                help: Self.help(pieces, index: index)))
            .offset(x: shown.x)
        }
    }

    /// The badge on a sound's segment: its gain, a sparkle when its noise is
    /// cleaned, and a ring filling while the cleaned sound is being made.
    private func soundBadge(gain: String?, cleaned: Bool, progress: Double?) -> some View {
        HStack(spacing: 3) {
            if let progress {
                ProgressRing(fraction: progress)
                    .frame(width: 8, height: 8)
            } else if cleaned {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
            }
            if let gain {
                Text(gain)
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(Capsule().fill(.black.opacity(0.45)))
        .padding(3)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([gain.map { "Gain \($0)" },
                             progress != nil ? "Cleaning noise" : (cleaned ? "Noise cleaned" : nil)]
            .compactMap { $0 }.joined(separator: ", "))
    }

    /// How loud this layer's sound is set to play, gain included.
    private var soundLevel: AudioLevel? {
        editorState.document?.layer(id: layerID)?.soundLevel
    }

    /// The level the waveform is drawn at: what the document says, or what a
    /// hand on the level line or on a fade handle is making it, so the drawing
    /// moves with the drag rather than after it.
    private func drawnSoundLevel(lengthMS: Int) -> AudioLevel {
        var level = levelInHand ?? soundLevel ?? AudioLevel()
        if let fadeDrag {
            if fadeDrag.isIn { level.setFadeIn(fadeDrag.ms, lengthMS: lengthMS) }
            else { level.setFadeOut(fadeDrag.ms, lengthMS: lengthMS) }
        }
        return level
    }

    /// The shape of this layer's sound, once it has been read off the file.
    /// Asked for every time the bar draws, and asked for in the background the
    /// first time, so a bar with no waveform in it yet is a bar rather than a
    /// wait (`SoundFiles.swift`).
    private var waveform: Waveform? {
        // What plays, so a cleaned segment draws its cleaned sound.
        guard let sound = editorState.document?.layer(id: layerID)?.playedSound else { return nil }
        let already = SoundLibrary.shared.waveform(for: sound)
        #if PHOTONZ_PLAYTEST
        DrawnWaveforms.shared.bar(of: layerID, drew: already != nil)
        #endif
        if let already { return already }
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
                           lineColor: kind == nil ? .white.opacity(0.95) : soundTint.opacity(0.95),
                           lineWidth: kind == nil ? 2 : 1.5,
                           pointColor: kind == nil ? .accentColor : soundTint,
                           onLevelInHand: { levelInHand = $0 })
                .offset(x: shown.x)
        }
    }

    /// A sound's name, as the mock's `.cliptag` wears it: white in a dark tag
    /// at the top left of the clip, over the waveform and the level line,
    /// because both are drawn in the lane's own colour and a name in a tint
    /// of it sank into them. Once per clip, kept in sight on a zoomed
    /// timeline, and clear of the fade in diamond at the clip's start.
    @ViewBuilder
    private func soundTag(_ pieces: ClipPieces, x0: CGFloat, ruler: MotionStripRuler) -> some View {
        let whole = laneWidth * ruler.fraction(spanningMS: Double(pieces.totalLengthMS))
        let shown = TimelineSpan.drawn(x: x0, width: whole, across: laneWidth)
        if shown.width > 40 {
            Text(layerName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.4)))
                .padding(.leading, x0 >= 0 ? SoundFadeDiamond.reach + 4 : 4)
                .padding(.trailing, 8)
                .padding(.top, 3)
                .frame(width: shown.width, height: barHeight, alignment: .topLeading)
                .offset(x: shown.x)
                .allowsHitTesting(false)
        }
    }

    // MARK: Pictures along the clip

    /// The recording this bar is a clip of, where it is a video clip on the
    /// dock. Nil for everything that has no pictures to show: a sound, a
    /// caption, a shape, the timing strip.
    private var pictureMovie: MovieRef? {
        guard let kind, kind == .video || kind == .videoAlternate, !isLinkedSound else { return nil }
        return editorState.document?.layer(id: layerID)?.movie
    }

    /// How strongly the pictures along this clip show: none at Fit, and in
    /// full once the timeline is opened out far enough for each picture to
    /// stand for a short stretch (`ClipFilmstrip.opacity`).
    private var picturesOpacity: Double {
        guard let movie = pictureMovie, laneWidth > 0 else { return 0 }
        let ruler = editorState.motionStripRuler
        let strip = max(1, barHeight - ClipFilmstripStrip.band)
        let aspect = movie.pixelSize.height > 0 ? movie.pixelSize.width / movie.pixelSize.height : 16.0 / 9
        let msPerTile = Double(ClipFilmstrip.tileWidth(height: strip, aspect: aspect))
            * ruler.spanMS / Double(laneWidth)
        return ClipFilmstrip.opacity(zoom: editorState.timelineWindow, msPerTile: msPerTile)
    }

    /// The row of pictures inside one piece, faded in and out as the timeline
    /// opens out past Fit and comes back to it.
    @ViewBuilder
    private func filmstrip(_ item: ClipPiece?, index: Int, pieceWidth: CGFloat,
                           shown: TimelineSpan, pictures: Double) -> some View {
        ZStack(alignment: .topLeading) {
            if pictures > 0, let item, let movie = pictureMovie {
                ClipFilmstripStrip(layerID: layerID, pieceIndex: index, movie: movie, piece: item,
                                   pieceWidth: pieceWidth,
                                   visibleFrom: shown.startFraction * pieceWidth,
                                   visibleWidth: shown.width, height: barHeight,
                                   opacity: pictures)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: pictures > 0)
    }

    /// What the dock draws inside a piece: the lit top edge every clip in the
    /// mock has, a veil over a held frame, and the clip's name where there is
    /// room to read it.
    /// `hiddenLeading` is how much of the piece is off the left edge of the
    /// window, so the name stays in sight on a zoomed timeline rather than
    /// sliding out with the clip's start.
    @ViewBuilder private func kitFace(_ piece: ClipPiece?, width: CGFloat,
                                      hiddenLeading: CGFloat, pictures: Double = 0) -> some View {
        if let kind {
            ZStack(alignment: isSound ? .topLeading : .leading) {
                if soundOnThePanelGround {
                    RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(soundTint.opacity(0.35), lineWidth: 1)
                } else if let border = kind.border {
                    RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(border)
                }
                if piece?.isHeld == true {
                    Color.black.opacity(0.4)
                }
                if !soundOnThePanelGround {
                    VStack(spacing: 0) {
                        Rectangle().fill(Color.white.opacity(0.18)).frame(height: 1)
                            .padding(.horizontal, cornerRadius / 2)
                        Spacer(minLength: 0)
                    }
                }
                // A clip's own sound is named by the picture right above it,
                // and the mock's sound segment carries no words. A sound of
                // its own wears its name above its level line (`soundTag`).
                if width - hiddenLeading > 40, !isLinkedSound {
                    if !isSound {
                        Text(layerName)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(kind.ink(colorScheme))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .shadow(color: .black.opacity(0.35), radius: 1)
                            // Over pictures the name sits in a dark pill, so it
                            // reads on a white window as well as on a dark one.
                            .padding(.horizontal, pictures > 0 ? 5 : 0)
                            .padding(.vertical, pictures > 0 ? 1 : 0)
                            .background(Capsule().fill(Color.black.opacity(0.55 * pictures)))
                            .padding(.leading, pictures > 0 ? 4 : 8)
                            .padding(.trailing, 8)
                            .frame(maxWidth: width - hiddenLeading - 4, alignment: .leading)
                            .padding(.leading, hiddenLeading)
                    }
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

    /// A sound drawn as `video-audio.html` draws its clip: the panel's own
    /// ground, a breath lighter, with a thin edge in the lane's colour, so the
    /// waveform is the coloured thing in the lane
    /// (`next-sound-on-the-panel-ground`). Off, it wears `video.html`'s green.
    private var soundOnThePanelGround: Bool {
        kind == .audio && Experiments.shared.soundOnThePanelGroundEnabled
    }

    private func fill(_ piece: ClipPiece?, picked: Bool) -> AnyShapeStyle {
        if soundOnThePanelGround {
            return AnyShapeStyle(VideoKit.Palette.panel2.color(colorScheme).mix(with: .white, by: 0.03))
        }
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
        return ClipSpeed.badge(piece.speedPercent)
    }

    static func pieceName(layerName: String, index: Int, of count: Int) -> String {
        count > 1 ? "\(layerName) piece \(index + 1)" : "\(layerName) clip"
    }

    static func help(_ pieces: ClipPieces, index: Int) -> String {
        guard pieces.count > 1 else {
            return "The clip. Drag it to move it along the timeline, Option-drag to copy it."
        }
        return "Piece \(index + 1) of \(pieces.count). Drag it somewhere else in the order, "
            + "Option-drag to copy it."
    }

    // MARK: The fades

    /// A diamond at the top of a sound's segment where each fade ends: drag
    /// the left one in to fade in, the right one in to fade out. The level
    /// line draws the fade itself, because a fade IS the level falling to
    /// silence. Placed as the mock's `.fade` is, centred on the fade's end
    /// eight points down, and held inside the segment so a diamond on a fade
    /// of nothing never hangs over the clip before it.
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
        let half = SoundFadeDiamond.reach / 2
        if whole >= SoundFadeDiamond.reach * 2 + 4 {
            if let drag = fadeDrag {
                // The fade the hand is making, before it is let go.
                FadeWedge(isIn: drag.isIn)
                    .fill(Color.black.opacity(0.35))
                    .frame(width: drag.isIn ? inWidth : outWidth, height: barHeight)
                    .offset(x: drag.isIn ? x0 : x0 + whole - outWidth)
                    .allowsHitTesting(false)
                capsule(ClipBarCopy.length(drag.ms), x: drag.isIn ? x0 + inWidth + half : x0 + whole - outWidth - 90 - half)
                    .frame(height: barHeight)
            }
            fadeHandle(isIn: true, fromMS: level.fadeInMS, lengthMS: length, ruler: ruler)
                .offset(x: x0 + min(max(half, inWidth), whole - half) - half,
                        y: SoundFadeDiamond.centreY - half)
            fadeHandle(isIn: false, fromMS: level.fadeOutMS(lengthMS: length), lengthMS: length, ruler: ruler)
                .offset(x: x0 + whole - min(max(half, outWidth), whole - half) - half,
                        y: SoundFadeDiamond.centreY - half)
        }
    }

    private func fadeHandle(isIn: Bool, fromMS: Int, lengthMS: Int,
                            ruler: MotionStripRuler) -> some View {
        SoundFadeDiamond(tint: soundTint, isInHand: fadeDrag?.isIn == isIn)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: Self.handSpace)
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

    // MARK: The picture's fades

    /// Whether this bar's picture can fade: a clip, a title, a shape, a
    /// picture, on the dock, and never a sound.
    private var fadesPicture: Bool {
        kind != nil && !isSound && !isLinkedSound && editorState.pictureFadeLayer(layerID) != nil
    }

    /// The fade at each end drawn as a shade over the bar, darkest where the
    /// picture is furthest down, the way Final Cut draws a video fade; and,
    /// on the picked or hovered bar, a handle at each top corner to drag it.
    @ViewBuilder
    private func pictureFadeRamps(_ pieces: ClipPieces, x0: CGFloat,
                                  ruler: MotionStripRuler) -> some View {
        let length = pieces.totalLengthMS
        let layer = editorState.document?.layer(id: layerID)
        let fadeIn = pictureFadeDrag.flatMap { $0.isIn ? $0.ms : nil } ?? layer?.pictureFadeMS(.in) ?? 0
        let fadeOut = pictureFadeDrag.flatMap { $0.isIn ? nil : $0.ms } ?? layer?.pictureFadeMS(.out) ?? 0
        let whole = laneWidth * ruler.fraction(spanningMS: Double(length))
        let inWidth = laneWidth * ruler.fraction(spanningMS: Double(fadeIn))
        let outWidth = laneWidth * ruler.fraction(spanningMS: Double(fadeOut))
        if fadeIn > 0 {
            FadeWedge(isIn: true)
                .fill(Color.black.opacity(0.4))
                .frame(width: inWidth, height: barHeight)
                .offset(x: x0)
                .allowsHitTesting(false)
        }
        if fadeOut > 0 {
            FadeWedge(isIn: false)
                .fill(Color.black.opacity(0.4))
                .frame(width: outWidth, height: barHeight)
                .offset(x: x0 + whole - outWidth)
                .allowsHitTesting(false)
        }
        if let drag = pictureFadeDrag {
            capsule(ClipBarCopy.length(drag.ms), x: drag.isIn ? x0 + inWidth : x0 + whole - outWidth - 90)
                .frame(height: barHeight)
        }
        if whole >= Self.smallestGrabbablePiece * 2, isPicked || isHovered || pictureFadeDrag != nil {
            pictureFadeHandle(isIn: true, fromMS: layer?.pictureFadeMS(.in) ?? 0,
                              roomMS: length - fadeOut, ruler: ruler)
                .offset(x: min(x0 + whole - 9, x0 + max(1, inWidth - 4)))
            pictureFadeHandle(isIn: false, fromMS: layer?.pictureFadeMS(.out) ?? 0,
                              roomMS: length - fadeIn, ruler: ruler)
                .offset(x: max(x0, x0 + whole - max(9, outWidth + 4)))
        }
    }

    private func pictureFadeHandle(isIn: Bool, fromMS: Int, roomMS: Int,
                                   ruler: MotionStripRuler) -> some View {
        // The sound's diamond, ringed dark rather than in the sound's colour,
        // so the two fades never read as one.
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.white)
            .overlay { RoundedRectangle(cornerRadius: 1.5).strokeBorder(Color.black.opacity(0.6), lineWidth: 1.2) }
            .frame(width: 7, height: 7)
            .rotationEffect(.degrees(45))
            .frame(width: 8, height: 8)
            .padding(.top, 1)
            .contentShape(Rectangle().inset(by: -4))
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: Self.handSpace)
                .onChanged { value in
                    let moved = Self.ms(value.translation.width, laneWidth: laneWidth, ruler: ruler)
                    let ms = min(max(0, fromMS + (isIn ? moved : -moved)), max(0, roomMS))
                    pictureFadeDrag = FadeDrag(isIn: isIn, ms: ms)
                }
                .onEnded { _ in
                    if let drag = pictureFadeDrag {
                        editorState.setPictureFade(drag.isIn ? .in : .out, toMS: drag.ms, layerID: layerID)
                    }
                    pictureFadeDrag = nil
                })
            .playtestField("\(fieldName) picture fade \(isIn ? "in" : "out")")
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
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: Self.handSpace)
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

    /// How much of a piece's start a transition band covers, so its name
    /// starts past the band rather than under it, cut off at the band's edge.
    private func bandCover(_ pieces: ClipPieces, piece index: Int, ruler: MotionStripRuler) -> CGFloat {
        guard kind != nil, index > 0, let cut = shownCuts(pieces).first(where: { $0.index == index }),
              let transition = editorState.drawnClipTransition(cut, at: .join(clip: layerID, index: index))
        else { return 0 }
        let after = max(0, transition.lengthMS - transition.beforeMS)
        // The grip straddles the band's edge by two points.
        return laneWidth * ruler.fraction(spanningMS: Double(after)) + 2
    }

    /// One transition, drawn across its join: a band as long as the transition
    /// is, centred on the cut, with a grip at each end to make it longer or
    /// shorter. Both ends do the same thing, because a transition is measured
    /// ACROSS the join and never sits to one side of it.
    @ViewBuilder
    private func band(_ cut: ClipCut, x0: CGFloat, ruler: MotionStripRuler) -> some View {
        // The length a hand is dragging while it drags, so the band follows the
        // pointer rather than waiting for the release.
        if let transition = editorState.drawnClipTransition(cut, at: .join(clip: layerID, index: cut.index)) {
            let width = laneWidth * ruler.fraction(spanningMS: Double(transition.lengthMS))
            let x = x0 + laneWidth * ruler.fraction(spanningMS: Double(cut.atMS - transition.beforeMS))
            let picked = editorState.selectedClipCutIndex == cut.index && isPicked
            let grabs = (leading: ClipTransitionEdgeDrag.canGrab(leadingEdge: true, of: transition),
                         trailing: ClipTransitionEdgeDrag.canGrab(leadingEdge: false, of: transition))
            let gripsFit = width >= Self.smallestGrabbablePiece
            ZStack {
                if kind != nil {
                    VideoKit.TransitionBand(isDip: !transition.kind.needsOverlap,
                                            isSelected: picked, height: barHeight,
                                            leadingGrip: grabs.leading && gripsFit,
                                            trailingGrip: grabs.trailing && gripsFit)
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
            .overlay(alignment: .leading) {
                if grabs.leading { bandGrip(cut, leading: true, width: width) }
            }
            .overlay(alignment: .trailing) {
                if grabs.trailing { bandGrip(cut, leading: false, width: width) }
            }
            // Pressable and right-clickable by a walk, as the join's grip it
            // covers was; marked before the offset so the mark moves with it.
            .playtestControl(Self.bandName(layerName: layerName, cut: cut.index), detail: layerName)
            .offset(x: x)
            .playtestField(Self.bandName(layerName: layerName, cut: cut.index))
            .panelHelp("\(transition.kind.title) over the join after piece \(cut.index). "
                       + "Drag an end to change how long it takes.")
        }
    }

    /// One end of a band. It goes away on a band too narrow to hold two, for
    /// the same reason a piece's grips do: a grip you cannot help but hit is
    /// worse than no grip at all, and the panel's own Length row is always
    /// there.
    @ViewBuilder
    private func bandGrip(_ cut: ClipCut, leading: Bool, width: CGFloat) -> some View {
        if width >= Self.smallestGrabbablePiece {
            // On the dock the band draws its own grip (`.xband .gr`), so this
            // is only where the hand takes hold of it, straddling the edge as
            // the grip does.
            Rectangle()
                .fill(kind == nil ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(Color.clear))
                .frame(width: kind == nil ? 3 : 5, height: barHeight - 4)
                .contentShape(Rectangle().inset(by: -5))
                .offset(x: kind == nil ? 0 : (leading ? -2 : 2))
                .gesture(bandDrag(cut, leading: leading))
                .playtestControl("\(Self.bandName(layerName: layerName, cut: cut.index)) "
                                 + (leading ? "start" : "end"), detail: layerName)
        }
    }

    private func bandDrag(_ cut: ClipCut, leading: Bool) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: Self.handSpace)
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
        if isPicked, room >= Self.smallestGrabbablePiece, !gripHidesUnderABand(pieces, edge: edge) {
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
                    guard kind != nil, !isLinkedSound else { return }
                    // The tiles open a pass after the pick, so the ring and
                    // the panel answer the click in its own frame and the
                    // popover builds in the next. Together they held one
                    // pass for ~100 ms on a captioned five minute recording,
                    // ~30 of it the popover (2026-10-06, `clip-click-cost-walk`).
                    let editorState = editorState, layerID = layerID
                    Task { @MainActor in
                        await NextRunLoopPass.start()
                        // Not if the hand has moved on in the meantime.
                        guard editorState.selectedLayerID == layerID,
                              editorState.selectedClipCutIndex == edge else { return }
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
                            TimelineClipMenu(layerID: layerID, piece: edge == 0 ? 0 : pieces.count - 1,
                                             onTheSound: isLinkedSound)
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

    /// A join carrying a transition on the dock: the band is drawn over it,
    /// as the mock draws `.xband` over the seam with nothing on top but its
    /// icon, so the join's own grip would be a second mark in the middle of
    /// it. The band picks the cut and opens its menu instead. It does not
    /// move the cut: a band is clicked to pick it, and a click that slipped a
    /// point would have rolled the edit.
    private func gripHidesUnderABand(_ pieces: ClipPieces, edge: Int) -> Bool {
        guard kind != nil, edge > 0, edge < pieces.count else { return false }
        return shownCuts(pieces).contains { $0.index == edge }
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
        // Read in a space that stays put. The grip is drawn where the drag
        // has it, so in its OWN space every move it makes is taken off the
        // next reading of the hand: it landed under the pointer, jumped back
        // to where it was grabbed, landed again, and flickered all the way
        // (`bar-end-follows-the-pointer-walk`).
        DragGesture(minimumDistance: 1, coordinateSpace: Self.handSpace)
            .onChanged { value in
                if editorState.clipBarDrag == nil {
                    editorState.beginClipBarDrag(
                        layerID: layerID,
                        grab: edge == 0 ? .clipStart : .seam(after: edge - 1))
                }
                // ⌘ held frees the edge of every magnet for as long as it is
                // held, the way it frees a handle on the canvas and in Trim.
                editorState.updateClipBarDrag(byMS: Self.ms(value.translation.width,
                                                            laneWidth: laneWidth, ruler: ruler),
                                              free: Self.commandHeld)
            }
            .onEnded { _ in editorState.commitClipBarDrag() }
    }

    /// A piece taken hold of. With more than one piece that is a carry — the
    /// order is the thing there is to change — and with one it is the clip
    /// sliding along the document, because a clip of one piece has no order to
    /// rearrange. ⌘ always means the whole clip, and so does a clip that is
    /// one of several picked, which carries the others along.
    private func carry(_ pieces: ClipPieces, index: Int) -> some Gesture {
        // On the dock the pointer is read in the tracks' own space too, so a
        // clip carried up or down lands on the track under it, or on a new
        // one between two (`EditorState+Tracks`).
        DragGesture(minimumDistance: 3,
                    coordinateSpace: kind == nil ? Self.handSpace : .named(TimelineDock.tracksSpace))
            .onChanged { value in
                if editorState.clipBarDrag == nil {
                    // One of several picked clips: the lot slides together.
                    let whole = pieces.count == 1
                        || NSEvent.modifierFlags.contains(.command)
                        || editorState.multiSelectedLayerIDs.contains(layerID)
                    // ⌥ leaves the clip where it is and carries out a copy:
                    // of the whole clip, or of this piece alone where a carry
                    // would have rearranged it (`ClipDragCopy.swift`).
                    editorState.beginClipBarDrag(layerID: layerID,
                                                 grab: whole ? .body : .carry(piece: index),
                                                 copying: Self.optionHeld)
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

    /// Where every drag on a bar reads the hand: a space that does not move
    /// when the thing being dragged does. A grip's own space travels with the
    /// grip, so a drag read there chases its own tail.
    static let handSpace: CoordinateSpace = .global

    /// ⌥ down right now, read the same two ways.
    static var optionHeld: Bool {
        NSEvent.modifierFlags.contains(.option)
            || NSApp.currentEvent?.modifierFlags.contains(.option) == true
    }

    /// ⌘ down right now, on the keyboard or on the event being handled (a
    /// walk's posted drag carries its keys on the event, not the keyboard).
    static var commandHeld: Bool {
        NSEvent.modifierFlags.contains(.command)
            || NSApp.currentEvent?.modifierFlags.contains(.command) == true
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
        Self.snapLine(atMS: ms, ruler: ruler, laneWidth: laneWidth, barHeight: barHeight)
    }

    static func snapLine(atMS ms: Int, ruler: MotionStripRuler, laneWidth: CGFloat,
                         barHeight: CGFloat) -> some View {
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
        Self.capsule(text, x: x, laneWidth: laneWidth)
    }

    /// The numbers a drag is making, in a capsule beside the bar.
    static func capsule(_ text: String, x: CGFloat, laneWidth: CGFloat) -> some View {
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
            if let gain = level.clipGainLabel { words += ", gain \(gain)" }
            let fadeIn = level.fadeInMS
            let fadeOut = level.fadeOutMS(lengthMS: pieces.totalLengthMS)
            if fadeIn > 0 { words += ", fade in \(ClipBarCopy.length(fadeIn))" }
            if fadeOut > 0 { words += ", fade out \(ClipBarCopy.length(fadeOut))" }
        }
        if fadesPicture, let layer = editorState.document?.layer(id: layerID) {
            let fadeIn = layer.pictureFadeMS(.in), fadeOut = layer.pictureFadeMS(.out)
            if fadeIn > 0 { words += ", picture fades in over \(ClipBarCopy.length(fadeIn))" }
            if fadeOut > 0 { words += ", picture fades out over \(ClipBarCopy.length(fadeOut))" }
        }
        if isBeingDragged, let readout = editorState.clipBarReadout {
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

/// A sound's fade handle, as `video-audio.html` draws its `.fade`: a 12 point
/// white square turned on its corner, ringed in the lane's own colour, lighter
/// under the pointer and ringed in the picked colour while it is in the hand.
///
/// Only the diamond takes a press, not the square it sits in, so the level
/// line and the trim grip beside it keep every click that misses it.
struct SoundFadeDiamond: View {
    /// The mock's side.
    static let side: CGFloat = 12
    /// How far it reaches corner to corner, turned: what it is laid out in.
    static let reach: CGFloat = (side * 2.squareRoot()).rounded(.up)
    /// The mock's `top:8px`: where its middle sits down from the lane's top.
    static let centreY: CGFloat = reach / 2

    let tint: Color
    var isInHand = false
    @State private var isHovered = false

    var body: some View {
        let face = RoundedRectangle(cornerRadius: 2)
        face
            .fill(isInHand ? VideoKit.rgb(0xFFF6E6) : (isHovered ? VideoKit.rgb(0xEAF7FF) : .white))
            .overlay {
                face.strokeBorder(isInHand ? VideoKit.Palette.warn.dark : tint, lineWidth: 1.5)
            }
            .frame(width: Self.side, height: Self.side)
            .rotationEffect(.degrees(45))
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
            .frame(width: Self.reach, height: Self.reach)
            .contentShape(Diamond())
            .playtestHover { isHovered = $0 }
    }

    /// The turned square's own outline, for what a press lands on.
    private struct Diamond: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
            return path
        }
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
    /// Opened on the clip's linked sound, on the Audio track under it.
    var onTheSound = false

    var body: some View {
        MenuRowsView(rows: editorState.timelineClipMenuRows(layerID: layerID, piece: piece,
                                                            onTheSound: onTheSound))
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

/// A piece's walk name and its help, or for a caption cue only the help: the
/// tooltip is the app's, the name is the probe's (`carriesWalkNames`).
private struct WalkNames: ViewModifier {
    let on: Bool
    let field: String
    let help: String

    func body(content: Content) -> some View {
        if on {
            // A control as well as a field, so a walk can PRESS a clip, with
            // Shift held if it likes, the way a person picks one on the
            // timeline: where the timeline is the layer list there is no row
            // to pick it from instead.
            content.playtestField(field)
                .playtestControl(field, detail: "Timeline")
                .panelHelp(help)
        } else {
            content.help(help)
        }
    }
}

/// The bar's hover and its readout for a walk. A caption cue has neither: its
/// hover changes nothing, and its readout is only ever read by a walk.
private struct BarWatch: ViewModifier {
    let on: Bool
    let name: String
    let readout: String
    let hover: (Bool) -> Void

    func body(content: Content) -> some View {
        if on {
            content.playtestHover(name, perform: hover).panelReadout(readout)
        } else {
            content
        }
    }
}

/// A small ring that fills clockwise from the top: how far along something
/// running in the background is, where a spinner would say only that it is.
private struct ProgressRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.3), lineWidth: 1.5)
            Circle()
                .trim(from: 0, to: max(0.04, min(1, fraction)))
                .stroke(.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
