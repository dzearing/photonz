import PhotonzCore
import SwiftUI

/// **Time**: what the piece you have picked does with time, as label and value
/// rows (`docs/design/mocks/pages/video.html`, PROPERTIES).
///
/// A clip piece is its Speed, one dropdown, and what you hear at it. A held
/// frame is how long it holds. A title is how it fades. Where each one starts,
/// ends and how long it runs is the Properties pane's clip line, which leads
/// the panel.
///
/// Freezing a frame and what a freeze pushes are verbs, so they are on the
/// clip's right-click menu (Freeze Frame ▸), not here. Every longer answer
/// (why a fast stretch goes silent, what happens to frames) is the row's
/// tooltip, never a sentence in the panel.
struct SpeedInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        #if PHOTONZ_PLAYTEST
        let _ = ViewBuildMeter.shared.built(.timeSection)
        #endif
        readingForTheLookRows { lookBody }
    }

    /// The body, built by `readingForTheLookRows`: nothing in it shows a
    /// key on where a layer is.
    @ViewBuilder private var lookBody: some View {
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
                pictureFades
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: A title

    // When it is on screen is the Properties pane's clip line, one section up
    // (`PropertiesPane.swift`). Start at Playhead and End at Playhead are
    // verbs, so they are on the bar's right-click menu, not here.
    @ViewBuilder
    private var placedInTime: some View {
        pictureFades
    }

    /// Fade In and Fade Out: how the picture comes up at the start of the bar
    /// and goes down at its end, the lengths the right-click offers, and the
    /// curve both run on. The same rows for a clip, a title or anything else
    /// on the timeline.
    @ViewBuilder
    private var pictureFades: some View {
        if let layer = editorState.pictureFadeLayerInHand {
            ForEach(FadeEnd.allCases, id: \.self) { end in
                let now = layer.pictureFadeMS(end)
                let stops = editorState.pictureFadeStops(end, layer: layer)
                VideoKit.DropdownRow(
                    label: end.title, value: PictureFade.title(now),
                    choices: .picking(stops.contains(now) ? stops : stops + [now], current: now,
                                      title: PictureFade.title,
                                      isEnabled: { _ in true }) { ms in
                        editorState.setPictureFade(end, toMS: ms,
                                                   layerIDs: editorState.pictureFadeTargetsInHand)
                    })
                .playtestField(end.title)
                .panelHelp(end == .in ? "How long the picture takes to come up" : "How long the picture takes to go down")
            }
            // The one Curve row every transition is tuned with (`CurveRow`),
            // once there is a fade to shape.
            if let fade = layer.pictureFade, !fade.isNone {
                CurveRow(current: fade.shownCurve, help: "How the picture comes up and goes down.",
                         row: "Fade curve") {
                    editorState.setPictureFadeCurve($0, layerID: layer.id)
                }
            }
        }
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
        if let ramp = piece.speedRamp {
            ramped(piece, ramp)
        } else {
            playsAtOneSpeed(piece)
        }
    }

    @ViewBuilder
    private func playsAtOneSpeed(_ piece: ClipPiece) -> some View {
        let reading = ClipSpeedReading(piece)
        VideoKit.DropdownRow(
            label: "Speed", value: ClipSpeed.title(piece.speedPercent),
            choices: .picking(ClipSpeed.stops, current: piece.speedPercent, title: ClipSpeed.menuTitle,
                              isEnabled: { $0 == piece.speedPercent || editorState.canSetClipSpeed($0) }) {
                editorState.setClipSpeedInHand($0)
            },
            // ⌘R, Premiere's Speed/Duration, opens this list (`EditorState+SpeedKey`).
            opensWhenAsked: editorState.pendingClipSpeedChoices,
            opened: editorState.clipSpeedChoicesOpened)
        .playtestField("Speed")
        .panelHelp(reading.framesSentence)
        // How long it runs is the Properties pane's clip line, one section up.
        sound(reading.sound)
    }

    // MARK: A piece with speed stops

    /// The mock's Speed stop section (`video-speed.html`, PROPERTIES): which
    /// stop of how many, its speed, and how the piece gets between stops.
    /// Adding, deleting and resetting are verbs, so they are rows of the
    /// clip's Speed menu, not buttons here.
    @ViewBuilder
    private func ramped(_ piece: ClipPiece, _ ramp: SpeedRamp) -> some View {
        let count = ramp.stops.count
        let picked = min(editorState.speedStopInHand ?? 0, count - 1)
        let speed = ramp.stops[picked].speedPercent
        // Freeze first, the mock's fourth preset, then every speed a piece
        // can play at.
        let offered = SpeedStopNames.speeds
        let speeds = offered.contains(speed) ? offered : (offered + [speed]).sorted()
        VideoKit.DropdownRow(
            label: "Speed stop", value: Self.stopTitle(picked, of: count),
            choices: .picking(Array(0..<count), current: picked, title: { Self.stopTitle($0, of: count) },
                              isEnabled: { _ in true }) {
                editorState.pickSpeedStop($0)
            })
        .playtestField("Speed stop")
        .panelHelp("The stop the rows below change. The playhead goes to it.")
        VideoKit.DropdownRow(
            label: "Speed", value: SpeedStopNames.speedTitle(speed),
            choices: .picking(speeds, current: speed, title: SpeedStopNames.speedTitle,
                              isEnabled: {
                                  $0 == speed || ($0 == 0 ? editorState.canFreezeSpeedStopInHand
                                                          : editorState.canSetSpeedStopInHand($0))
                              }) {
                if $0 == 0 { editorState.freezeSpeedStopInHand() } else { editorState.setSpeedStopInHand($0) }
            },
            opensWhenAsked: editorState.pendingClipSpeedChoices,
            opened: editorState.clipSpeedChoicesOpened)
        .playtestField("Speed")
        .panelHelp("How fast the clip plays as it passes this stop.")
        VideoKit.FieldRow(label: "Between stops") {
            SegmentedControl("Between stops", selection: ramp.blend,
                             options: SpeedRampBlend.allCases.map { .init($0, $0.title) },
                             form: .natural) { editorState.setRampBlendInHand($0) }
                .controlSize(.small)
                .fixedSize()
        }
        .panelReadout(ramp.blend.title)
        .playtestField("Between stops")
        // The mock's own line, moved behind the row (UX-PATTERNS §4).
        .panelHelp(SpeedStopNames.betweenStopsHelp)
        sound(ClipSpeedReading(piece).sound)
    }

    /// `2 of 3`: the mock's `4 of 7`.
    static func stopTitle(_ index: Int, of count: Int) -> String { "\(index + 1) of \(count)" }

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
        VideoKit.DropdownRow(
            label: "Hold", value: ClipPieces.holdTitle(piece.lengthMS),
            choices: .picking(ClipPieces.holdStopsMS, current: piece.lengthMS, title: ClipPieces.holdTitle,
                              isEnabled: { $0 == piece.lengthMS || editorState.canSetHoldLength($0) }) {
                editorState.setHoldLengthInHand($0)
            },
            // A held frame has no speed, so ⌘R opens how long it holds.
            opensWhenAsked: editorState.pendingClipSpeedChoices,
            opened: editorState.clipSpeedChoicesOpened)
        .playtestField("Hold")
        .panelHelp("How long the frame stays on screen.")
        let push = piece.holdPush ?? .thisTrack
        VideoKit.FieldRow(label: "Freezes") {
            VideoKit.ValueFace(value: push.title)
                .panelReadout(push.title)
        }
        .playtestField("Freezes")
        .panelHelp(push.sentence(holdMS: piece.lengthMS))
    }
}
