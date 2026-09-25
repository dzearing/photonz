import PhotonzCore
import SwiftUI

/// **Time**: what the piece you have picked does with time, as label and value
/// rows (`docs/design/mocks/pages/video.html`, PROPERTIES).
///
/// A clip piece is its Speed, one dropdown, and what you hear at it. A held
/// frame is how long it holds. A title is where the playhead puts its ends and
/// how it fades. Where each one starts, ends and how long it runs is the
/// Properties pane's clip line, which leads the panel.
///
/// Freezing a frame and what a freeze pushes are verbs, so they are on the
/// clip's right-click menu (Freeze Frame ▸), not here. Every longer answer
/// (why a fast stretch goes silent, what happens to frames) is the row's
/// tooltip, never a sentence in the panel.
struct SpeedInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Words placed on a document with time: an in, an out and a fade,
            // and nothing about frames (`TitleTime.swift`).
            if editorState.placedLayerInHand?.time != nil {
                placedInTime
            } else if let piece = editorState.clipPieceInHandPiece {
                which
                if piece.isHeld {
                    held(piece)
                } else {
                    plays(piece)
                }
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: A title

    // When it is on screen is the Properties pane's clip line, one section up
    // (`PropertiesPane.swift`), so this says only what you can do about it.
    @ViewBuilder
    private var placedInTime: some View {
        VideoKit.FieldRow(label: "Playhead") {
            HStack(spacing: 6) {
                Button("Start Here") { editorState.startPlacedLayerHere() }
                    .disabled(!editorState.canStartPlacedLayerHere)
                    .playtestControl("Start Here", detail: "the Time section")
                    .panelHelp("Start it at the playhead.")
                Button("End Here") { editorState.endPlacedLayerHere() }
                    .disabled(!editorState.canEndPlacedLayerHere)
                    .playtestControl("End Here", detail: "the Time section")
                    .panelHelp("End it at the playhead.")
            }
            .controlSize(.small)
        }
        fade
    }

    /// How long the words take to arrive and to go. It writes an ordinary
    /// Opacity animation, so its curve is Animating's, not a second control.
    private var fade: some View {
        let now = editorState.placedLayerFadeMS
        return VideoKit.DropdownRow(label: "Fade", value: TitleTime.fadeTitle(now)) {
            ForEach(TitleTime.fadeStopsMS, id: \.self) { ms in
                Toggle(TitleTime.fadeTitle(ms), isOn: Binding(
                    get: { ms == now },
                    set: { _ in editorState.setPlacedLayerFade(ms) }))
                    .disabled(ms != now && !editorState.canSetPlacedLayerFade(ms))
            }
        }
        .playtestField("Fade")
        .panelHelp("How long it takes to fade in and out.")
    }

    // MARK: Which piece

    @ViewBuilder
    private var which: some View {
        let count = editorState.clipInHandPieces?.count ?? 1
        if count > 1 {
            let value = "\((editorState.clipPieceInHand ?? 0) + 1) of \(count)"
            VideoKit.FieldRow(label: "Piece") {
                VideoKit.ValueFace(value: value)
                    .panelReadout(value)
            }
            .playtestField("Piece")
        }
    }

    // MARK: A piece that plays

    @ViewBuilder
    private func plays(_ piece: ClipPiece) -> some View {
        let reading = ClipSpeedReading(piece)
        VideoKit.DropdownRow(label: "Speed", value: ClipSpeed.title(piece.speedPercent)) {
            ForEach(ClipSpeed.stops, id: \.self) { percent in
                Toggle(ClipSpeed.menuTitle(percent), isOn: Binding(
                    get: { piece.speedPercent == percent },
                    set: { _ in editorState.setClipSpeedInHand(percent) }))
                    .disabled(piece.speedPercent != percent && !editorState.canSetClipSpeed(percent))
            }
        }
        .playtestField("Speed")
        .panelHelp(reading.framesSentence)
        // How long it runs is the Properties pane's clip line, one section up.
        sound(reading.sound)
    }

    /// What you hear under this piece, in a word, with the reason on hover.
    /// A stretch that has gone quiet must never go quiet quietly, so Silent
    /// wears the warning colour.
    private func sound(_ sound: ClipSpeedSound) -> some View {
        VideoKit.FieldRow(label: "Sound") {
            VideoKit.ValueFace(value: sound.word,
                               tint: sound.plays ? nil : AnyShapeStyle(Color.orange))
                .panelReadout(sound.word)
        }
        .playtestField("Sound reading")
        .panelHelp(sound.sentence)
    }

    // MARK: A held frame

    @ViewBuilder
    private func held(_ piece: ClipPiece) -> some View {
        VideoKit.DropdownRow(label: "Hold", value: ClipPieces.holdTitle(piece.lengthMS)) {
            ForEach(ClipPieces.holdStopsMS, id: \.self) { ms in
                Toggle(ClipPieces.holdTitle(ms), isOn: Binding(
                    get: { piece.lengthMS == ms },
                    set: { _ in editorState.setHoldLengthInHand(ms) }))
                    .disabled(piece.lengthMS != ms && !editorState.canSetHoldLength(ms))
            }
        }
        .playtestField("Hold")
        .panelHelp("How long the frame stays on screen.")
        let push = piece.holdPush ?? .pictureOnly
        VideoKit.FieldRow(label: "While held") {
            VideoKit.ValueFace(value: push.title)
                .panelReadout(push.title)
        }
        .playtestField("While held")
        .panelHelp(push.sentence(holdMS: piece.lengthMS))
    }
}
