import PhotonzCore
import SwiftUI

/// **Time**: what the piece you have picked does with time — how fast it plays
/// (`docs/design/mocks/pages/video-speed.html`, `next-speed-a-stretch`) and
/// holding one of its frames (`pages/video-freeze-wt.html`,
/// `next-hold-on-a-frame`).
///
/// The study's own sentence decides where this lives: "retiming is a property
/// of the selected clip, so nothing new appears in the chrome". So there is no
/// retime mode, no second window and no new tool. It is a section in the
/// Properties panel beside every other property of the thing in your hand, and
/// picking a piece on the timeline is what fills it.
///
/// What the study drew and this does not: **the speed curve plotted under the
/// clip, with draggable stops and a ramp between them.** A ramp is a cinematic
/// flourish and this app's recordings are screens: what a person wants is the
/// install bar at thirty times and the click at a quarter, which is piecewise
/// and is what the pieces already are. Speed varies across a clip by the clip
/// being in pieces, which is the same model cutting, trimming and reordering
/// all use, rather than by a second way of saying the same thing. The bar in
/// the timeline is the plot: every piece is drawn at the width its speed gives
/// it and badged with that speed.
///
/// What it says that the study did not: **what the sound does, and what it does
/// about frames**, in words, for the speed you picked. Both are questions
/// people get wrong about retiming and neither has anywhere else to be said.
struct SpeedInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Words placed on a document with time, which have an in and an
            // out and nothing else about them that is about time: no speed,
            // because there are no frames to run faster, and no held frame,
            // because there is no frame (`TitleTime.swift`).
            if let placed = editorState.placedLayerInHand, let time = placed.time {
                placedInTime(time, placed)
            } else if let piece = editorState.clipPieceInHandPiece {
                which(piece)
                if piece.isHeld {
                    held(piece)
                } else {
                    // The way IN to a hold, where a person is already looking
                    // at the frame they want to keep. The menu has the same row
                    // and the clickthrough puts it here, because freezing is a
                    // thing you decide about the shot in your hand rather than
                    // a thing you go to the menu bar for.
                    holdThisFrame()
                    // What it is doing FIRST, then the list that changes it.
                    // The three sentences are the whole answer and they were
                    // last in the section when it was first built, which put
                    // them below the fold of a panel already seven sections
                    // deep: the thing you most needed to read was the thing
                    // you had to scroll for.
                    reading(ClipSpeedReading(piece))
                    stops(piece)
                }
            } else {
                Text("No piece is picked. Click a clip on the timeline, or the piece of it you "
                     + "want to retime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        // The panel decides how wide this is, never the words in it, the same
        // rule the Transition section learned the hard way.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: When words are on screen

    /// **The whole of what a title is**: when it arrives, when it goes, and
    /// how softly it does either.
    ///
    /// What the clickthrough drew here was two timecode fields, In and Out.
    /// They are not built, and deliberately: a timecode is a thing to learn and
    /// to mistype, and the app already has a cursor in time. The bar in the
    /// timeline is the direct answer — drag either end, drag the middle — and
    /// this is the other way round, for the frame you are already looking at.
    @ViewBuilder
    private func placedInTime(_ time: LayerTime, _ layer: Layer) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(TitleTime.reading(time))
                .font(.system(size: 11, design: .monospaced))
                .panelReadout(TitleTime.reading(time))
                .playtestField("Time reading")
            HStack(spacing: 6) {
                Button("Start Here") { editorState.startPlacedLayerHere() }
                    .controlSize(.small)
                    .disabled(!editorState.canStartPlacedLayerHere)
                    .playtestControl("Start Here", detail: "the Time section")
                    .panelHelp(TitleTime.startHelp(for: layer))
                Button("End Here") { editorState.endPlacedLayerHere() }
                    .controlSize(.small)
                    .disabled(!editorState.canEndPlacedLayerHere)
                    .playtestControl("End Here", detail: "the Time section")
                    .panelHelp(TitleTime.endHelp(for: layer))
            }
            fade()
            Text(TitleTime.sentence(for: layer))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    /// How long the words take to arrive and to go.
    ///
    /// It writes an ORDINARY Opacity animation on the layer, which is why there
    /// is no curve menu and no second control here: both of those are already
    /// in the Motion section, on the motion this row wrote, and saying them
    /// twice would be two places to change one thing.
    @ViewBuilder
    private func fade() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Fade")
                .font(.system(size: 11))
            VStack(alignment: .leading, spacing: 3) {
                ForEach(TitleTime.fadeStopsMS, id: \.self) { ms in
                    fadeStop(ms, isOn: editorState.placedLayerFadeMS == ms)
                }
            }
            Text("A fade is an Opacity animation on the layer, not a setting of its own: "
                 + "it is in the Motion list, with a lane on the timeline, and it takes any "
                 + "curve.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func fadeStop(_ ms: Int, isOn: Bool) -> some View {
        Button {
            editorState.setPlacedLayerFade(ms)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
                Text(TitleTime.fadeTitle(ms))
                    .font(.system(size: 11))
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isOn && !editorState.canSetPlacedLayerFade(ms))
        .playtestControl("Fade \(TitleTime.fadeTitle(ms))",
                         detail: "the Time section's \(TitleTime.fadeTitle(ms)) fade")
        .panelHelp(ms <= 0
            ? "The words cut on and cut off."
            : "The words arrive and leave over \(TitleTime.fadeTitle(ms)).")
    }

    // MARK: Which piece

    @ViewBuilder
    private func which(_ piece: ClipPiece) -> some View {
        let count = editorState.clipInHandPieces?.count ?? 1
        let index = editorState.clipPieceInHand ?? 0
        HStack {
            Text(count > 1 ? "Piece \(index + 1) of \(count)" : "The whole clip")
                .font(.system(size: 11))
            Spacer()
            Text(ClipPiecesBar.badge(piece) ?? "1x")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .panelReadout(ClipPiecesBar.badge(piece) ?? "1x")
                .playtestField("Speed reading")
        }
    }

    // MARK: Holding the frame under the playhead

    @ViewBuilder
    private func holdThisFrame() -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Button("Hold This Frame") { editorState.holdFrameAtPlayhead() }
                .controlSize(.small)
                .disabled(!editorState.canHoldFrameAtPlayhead)
                .playtestControl("Hold This Frame", detail: "the Time section")
                .panelHelp("Stop on the frame under the playhead and hold it there. It drops "
                           + "onto the timeline as an ordinary piece: trim it, move it, draw "
                           + "over it.")
            Text("A freeze is not a new kind of object. It is a piece whose in and out are the "
                 + "same frame, which is why it trims, moves and takes a transition like any "
                 + "other piece.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: A held frame has no speed, it has a length

    @ViewBuilder
    private func held(_ piece: ClipPiece) -> some View {
        let reading = ClipSpeedReading(piece)
        VStack(alignment: .leading, spacing: 3) {
            Text("A held frame, not a speed.")
                .font(.system(size: 11))
                .panelReadout("A held frame, not a speed.")
                .playtestField("Held reading")
            Text(reading.lengthSentence)
                .font(.caption)
                .foregroundStyle(.secondary)
                .panelReadout(reading.lengthSentence)
                .playtestField("Held length reading")
            holdLengths(piece)
            Text("Any other length is the hold's own end, dragged on the timeline. To retime a "
                 + "stretch instead, pick a piece that plays.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(reading.sound.sentence)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// How long to hold it for: the same shape of list as the speeds below,
    /// because it is the same shape of judgment. One click is one undo step,
    /// which a dragged number would not be.
    @ViewBuilder
    private func holdLengths(_ piece: ClipPiece) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hold for")
                .font(.system(size: 11))
            VStack(alignment: .leading, spacing: 3) {
                ForEach(ClipPieces.holdStopsMS, id: \.self) { ms in
                    holdStop(ms, isOn: piece.lengthMS == ms)
                }
            }
        }
    }

    private func holdStop(_ ms: Int, isOn: Bool) -> some View {
        Button {
            editorState.setHoldLengthInHand(ms)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
                Text(ClipPieces.holdTitle(ms))
                    .font(.system(size: 11))
                Spacer(minLength: 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isOn && !editorState.canSetHoldLength(ms))
        .playtestControl("Hold for \(ClipPieces.holdTitle(ms))",
                         detail: "the Time section's \(ClipPieces.holdTitle(ms)) hold")
        .panelHelp("Hold this frame for \(ClipPieces.holdTitle(ms)). Everything after it moves "
                   + "along, because a hold inserts time rather than covering it over.")
    }

    // MARK: The speeds

    @ViewBuilder
    private func stops(_ piece: ClipPiece) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Speed")
                .font(.system(size: 11))
            // A row of choices rather than a menu, for the same reason the
            // Transition section uses one: the list is short, every entry is
            // one click, and a menu would hide which one you are on.
            VStack(alignment: .leading, spacing: 3) {
                ForEach(ClipSpeed.stops, id: \.self) { percent in
                    stop(percent, isOn: piece.speedPercent == percent)
                }
            }
        }
    }

    private func stop(_ percent: Int, isOn: Bool) -> some View {
        Button {
            editorState.setClipSpeedInHand(percent)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
                Text(ClipSpeed.title(percent))
                    .font(.system(size: 11))
                Spacer(minLength: 4)
                // Only the silence is written down the edge. A tag on every
                // row saying "sound" would be six things to read to learn one.
                if !ClipSpeed.isAudible(percent: percent) {
                    Text("silent")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isOn && !editorState.canSetClipSpeed(percent))
        // A control rather than a field: a walk PRESSES these, which is the
        // only way to test that the panel row really retimes the piece rather
        // than that the menu behind it does.
        .playtestControl(ClipSpeed.title(percent),
                         detail: "the Time section's \(ClipSpeed.title(percent))")
        .panelHelp("\(ClipSpeed.title(percent)). \(ClipSpeed.sound(atPercent: percent).sentence)")
    }

    // MARK: What that speed did

    @ViewBuilder
    private func reading(_ reading: ClipSpeedReading) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(reading.lengthSentence)
                .font(.caption)
                .foregroundStyle(.secondary)
                .panelReadout(reading.lengthSentence)
                .playtestField("Length reading")
            Text(reading.framesSentence)
                .font(.caption)
                .foregroundStyle(.secondary)
                .panelReadout(reading.framesSentence)
                .playtestField("Frames reading")
            // The sound answer, said for the speed that is actually on, every
            // time. A stretch that has gone quiet must never go quiet quietly.
            Text(reading.sound.sentence)
                .font(.caption)
                .foregroundStyle(reading.sound.plays ? AnyShapeStyle(.secondary)
                                                     : AnyShapeStyle(Color.orange))
                .panelReadout(reading.sound.sentence)
                .playtestField("Sound reading")
        }
    }
}
