import PhotonzCore
import SwiftUI

/// **Speed**: how fast the piece you have picked plays
/// (`docs/design/mocks/pages/video-speed.html`, `next-speed-a-stretch`).
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
            if let piece = editorState.clipPieceInHandPiece {
                which(piece)
                if piece.isHeld {
                    held(piece)
                } else {
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

    // MARK: A held frame has no speed

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
            Text("Drag either end of it on the timeline to hold it for longer or less long. "
                 + "To retime a stretch instead, pick a piece that plays.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Text(reading.sound.sentence)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
                         detail: "the Speed section's \(ClipSpeed.title(percent))")
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
