import AppKit
import PhotonzCore
import SwiftUI

/// The bottom of the window on a keyed picture: the video timeline, slimmed
/// (`docs/design/mocks/pages/picture-keys.html`, "Where the strip lives").
///
/// One bar, then a ruler, a row per animated layer and a row under it per
/// changed value, which are the video editor's own lanes (`KeyLanesView`). No
/// scrubber (the ruler is right there), no volume and no track tools: a
/// picture has nothing to cut or hear. It ends in a repeats mark rather than a
/// duration, because a picture usually loops.
struct PictureKeyStrip: View {
    @Environment(EditorState.self) private var editorState

    private static let ceiling: CGFloat = 220
    private static let rowHeight: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            PictureKeyBar()
            GeometryReader { geo in
                let laneWidth = max(1, geo.size.width - TimelineDock.lanesLeading)
                VStack(spacing: 0) {
                    HStack(spacing: TimelineDock.gap) {
                        Text("Time")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(VideoKit.Palette.dim)
                            .padding(.leading, 12)
                            .frame(width: TimelineDock.gutter, alignment: .leading)
                        PictureKeyRuler(laneWidth: laneWidth)
                    }
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(editorState.pictureKeyLayers) { layer in
                                PictureKeyLayerRow(layer: layer, laneWidth: laneWidth,
                                                   height: Self.rowHeight)
                            }
                        }
                        .padding(.vertical, 3)
                        .coordinateSpace(.named(TimelineDock.tracksSpace))
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .overlay(alignment: .topLeading) {
                    PictureKeyEndMark(laneWidth: laneWidth)
                        .padding(.leading, TimelineDock.lanesLeading)
                }
                .overlay(alignment: .topLeading) {
                    PictureKeyPlayhead(laneWidth: laneWidth)
                        .padding(.leading, TimelineDock.lanesLeading)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: bodyHeight)
        }
        .background(VideoKit.Palette.panel)
        .tutorialAnchor(.timingStrip)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// As tall as the rows it holds, and no taller.
    private var bodyHeight: CGFloat {
        let layers = editorState.pictureKeyLayers
        let lanes = layers.reduce(0) { total, layer in
            total + (editorState.isKeyTrackOpen(layer.id) ? editorState.keyLanes(layerID: layer.id).count : 0)
        }
        let rows = CGFloat(layers.count) * (Self.rowHeight + 2)
        let inner = CGFloat(lanes) * (KeyLanesView.laneHeight + KeyLanesView.spacing)
        return min(Self.ceiling, TimelineDock.rulerHeight + rows + inner + 10)
    }
}

/// Previous key, play, next key, the time, Repeat and the timeline toggle.
private struct PictureKeyBar: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        HStack(spacing: 6) {
            VideoKit.TransportButton(symbol: "backward.end.fill", label: "Previous Key") {
                editorState.stopPictureForAKey()
                editorState.goToKey(forward: false)
            }
            .disabled(!editorState.canGoToKey(forward: false))
            .panelHelp("Go to the previous key (⌥K)")
            .playtestControl("Previous Key", detail: "Transport")
            VideoKit.TransportButton(symbol: editorState.isMotionPlaying ? "pause.fill" : "play.fill",
                                     label: editorState.isMotionPlaying ? "Pause" : "Play",
                                     role: .primary) {
                editorState.toggleMotionPreview()
            }
            .panelHelp(editorState.isMotionPlaying ? "Pause (space)" : "Play (space)")
            .playtestControl(editorState.isMotionPlaying ? "Pause" : "Play", detail: "Transport")
            VideoKit.TransportButton(symbol: "forward.end.fill", label: "Next Key") {
                editorState.stopPictureForAKey()
                editorState.goToKey(forward: true)
            }
            .disabled(!editorState.canGoToKey(forward: true))
            .panelHelp("Go to the next key (⇧K)")
            .playtestControl("Next Key", detail: "Transport")
            HStack(spacing: 6) {
                let now = KeyLap.timecode(ms: editorState.documentTimeMS)
                let length = KeyLap.timecode(ms: editorState.documentLengthMS)
                Text(now)
                    .playtestField("Key Time")
                    .panelReadout(now)
                Text("/").foregroundStyle(.tertiary)
                Text(length)
                    .foregroundStyle(.secondary)
                    .playtestField("Key Length")
                    .panelReadout(length)
            }
            .font(.system(size: 11, design: .monospaced))
            .monospacedDigit()
            .padding(.leading, 8)
            Spacer(minLength: 0)
            Button { editorState.toggleKeyLapRepeats() } label: {
                Image(systemName: "repeat")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(editorState.keyLapRepeats ? AnyShapeStyle(VideoKit.Palette.accent)
                                                               : AnyShapeStyle(VideoKit.Palette.dim))
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Repeat")
            .panelHelp(editorState.keyLapRepeats ? "Repeats. Press to play once" : "Plays once. Press to repeat")
            .playtestControl("Repeat", detail: editorState.keyLapRepeats ? "repeats" : "plays once")
            .panelReadout(editorState.keyLapRepeats ? "repeats" : "plays once")
            Button { editorState.toggleMotionStrip() } label: {
                Image(systemName: "rectangle.bottomthird.inset.filled")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(VideoKit.Palette.dim)
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Put the timeline away")
            .panelHelp("Put the timeline away (⌥⌘T)")
            .playtestControl("Hide Timing", detail: "Transport")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .tutorialAnchor(.video(.transport))
    }
}

/// The ruler: a click or a drag anywhere on it moves the playhead.
private struct PictureKeyRuler: View {
    @Environment(EditorState.self) private var editorState
    let laneWidth: CGFloat

    var body: some View {
        let ruler = editorState.motionStripRuler
        ZStack(alignment: .bottomLeading) {
            Color.clear
            ForEach(KeyLap.ticks(lapMS: editorState.keyLapMarkMS), id: \.ms) { tick in
                Text(tick.label)
                    .font(.system(size: MotionStripRulerView.fontSize, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                    .padding(.leading, MotionStripRuler.labelLead)
                    .overlay(alignment: .leading) { Rectangle().fill(.separator).frame(width: 1) }
                    .offset(x: laneWidth * ruler.fraction(ofMS: Double(tick.ms)))
            }
        }
            .frame(height: TimelineDock.rulerHeight, alignment: .bottom)
            .clipped()
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !editorState.playheadInHand { editorState.beginPlayheadDrag() }
                    let fraction = min(max(0, value.location.x / max(1, laneWidth)), 1)
                    let ms = editorState.motionStripRuler.ms(atFraction: Double(fraction))
                    editorState.dragPlayhead(toMS: Int(ms.rounded()),
                                             snappingWithinMS: editorState.keySnapReachMS(laneWidth: laneWidth))
                }
                .onEnded { _ in editorState.endPlayheadDrag() })
            .playtestControl("Key Ruler", detail: "Timeline")
    }
}

/// The red line down the rows, read in a view of its own so that playing does
/// not rebuild the rows under it.
private struct PictureKeyPlayhead: View {
    @Environment(EditorState.self) private var editorState
    let laneWidth: CGFloat

    var body: some View {
        VideoKit.Playhead(fraction: editorState.motionStripRuler.fraction(ofMS: Double(editorState.documentTimeMS)))
            .frame(width: laneWidth)
            .frame(maxHeight: .infinity)
            .panelReadout("playhead \(KeyLap.timecode(ms: editorState.documentTimeMS))")
    }
}

/// The end of the lap: the dashed line and the word, which you drag to change
/// the length. It says ends where the picture plays once.
private struct PictureKeyEndMark: View {
    @Environment(EditorState.self) private var editorState
    let laneWidth: CGFloat

    private var word: String { editorState.keyLapRepeats ? "repeats" : "ends" }

    var body: some View {
        let ruler = editorState.motionStripRuler
        let x = laneWidth * ruler.fraction(ofMS: Double(editorState.keyLapMarkMS))
        ZStack(alignment: .topLeading) {
            MotionStripRestartLine()
                .stroke(Color.accentColor.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
                .offset(x: x)
                .allowsHitTesting(false)
            Text(word)
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundStyle(Color.accentColor)
                .fixedSize()
                .padding(.horizontal, 4)
                .frame(height: TimelineDock.rulerHeight)
                .contentShape(Rectangle())
                .offset(x: x)
                .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("picture-key-end"))
                    .onChanged { value in
                        if editorState.keyLapDrag == nil { editorState.beginKeyLapDrag() }
                        let fraction = max(0, value.location.x / max(1, laneWidth))
                        editorState.dragKeyLap(toMS: Int(editorState.motionStripRuler
                            .ms(atFraction: Double(fraction)).rounded()))
                    }
                    .onEnded { _ in editorState.endKeyLapDrag() })
                .panelHelp("Drag to change the length")
                .playtestControl("Key Lap End", detail: "\(word) at \(KeyLap.timecode(ms: editorState.keyLapMarkMS))")
                .panelReadout("\(word) at \(KeyLap.timecode(ms: editorState.keyLapMarkMS))")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .coordinateSpace(.named("picture-key-end"))
    }
}

/// One layer: its name, its diamond and its key line, and the value rows under
/// it where it has any.
private struct PictureKeyLayerRow: View {
    @Environment(EditorState.self) private var editorState
    let layer: Layer
    let laneWidth: CGFloat
    let height: CGFloat

    var body: some View {
        let lanes = editorState.keyLanes(layerID: layer.id)
        let open = editorState.isKeyTrackOpen(layer.id)
        VStack(alignment: .leading, spacing: KeyLanesView.spacing) {
            HStack(spacing: TimelineDock.gap) {
                HStack(spacing: 4) {
                    Button { editorState.toggleKeyTrack(layer.id) } label: {
                        Image(systemName: open ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(VideoKit.Palette.dim)
                            .frame(width: 12, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity(lanes.isEmpty ? 0 : 1)
                    .disabled(lanes.isEmpty)
                    .accessibilityLabel(open ? "Hide the values of \(layer.name)" : "Show the values of \(layer.name)")
                    .playtestControl("Values \(layer.name)", detail: "Timeline")
                    Text(layer.name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(VideoKit.Palette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    TrackKeyDiamond(layerID: layer.id, trackName: layer.name)
                }
                .padding(.leading, 6)
                .padding(.trailing, 4)
                .frame(width: TimelineDock.gutter, height: height)
                .contentShape(Rectangle())
                .onTapGesture { editorState.selectLayer(layer.id) }
                PictureKeyLine(layerID: layer.id, layerName: layer.name, laneWidth: laneWidth, height: height)
            }
            .playtestField("Key row \(layer.name)")
            if open, !lanes.isEmpty {
                KeyLanesView(layerID: layer.id, layerName: layer.name, laneWidth: laneWidth)
            }
        }
    }
}

/// A layer's bar: the length of the lap, a diamond for every moment it has,
/// and the hollow diamond at the playhead saying where the next change lands.
private struct PictureKeyLine: View {
    @Environment(EditorState.self) private var editorState
    let layerID: UUID
    let layerName: String
    let laneWidth: CGFloat
    let height: CGFloat

    private struct Drag { var fromMS: Int; var toMS: Int }
    @State private var drag: Drag?
    @State private var hoveredMS: Int?

    private static let handSpace = "picture-key-line"
    private static let keySize: CGFloat = 12

    var body: some View {
        let ruler = editorState.motionStripRuler
        let marks = editorState.clipKeyMarks(layerID: layerID)
        let lapWidth = laneWidth * ruler.fraction(ofMS: Double(editorState.keyLapMarkMS))
        let isPicked = editorState.selectedLayerID == layerID
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                // Dark enough in either appearance for the white keys on it.
                .fill(VideoKit.Palette.accent.opacity(isPicked ? 0.5 : 0.32))
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(VideoKit.Palette.accent.opacity(isPicked ? 0.9 : 0.25),
                                  lineWidth: isPicked ? 1.5 : 1))
                .frame(width: lapWidth, height: height - 4)
                .padding(.top, 2)
                .contentShape(Rectangle())
                .onTapGesture { editorState.selectLayer(layerID) }
                .contextMenu { MenuRowsView(rows: editorState.pictureKeyLineMenuRows(layerID: layerID)) }
            if let first = marks.first, let last = marks.last, last.documentMS > first.documentMS {
                Rectangle()
                    .fill(VideoKit.Palette.accent.opacity(0.8))
                    .frame(width: laneWidth * ruler.fraction(spanningMS: Double(last.documentMS - first.documentMS)),
                           height: 2)
                    .offset(x: laneWidth * ruler.fraction(ofMS: Double(first.documentMS)), y: height / 2 - 1)
                    .allowsHitTesting(false)
            }
            ForEach(Array(marks.enumerated()), id: \.element.documentMS) { index, mark in
                diamond(mark, index: index, ruler: ruler)
                    // The change landing: the small pop the mock gives it.
                    .scaleEffect(mark.isHollow ? 1 : 1.0001)
                    .transition(.scale(scale: 1.7).combined(with: .opacity))
            }
            PictureKeyGhost(layerID: layerID, laneWidth: laneWidth, height: height)
                .allowsHitTesting(false)
        }
        .animation(.spring(duration: 0.25, bounce: 0.5), value: marks.map(\.isHollow))
        .frame(width: laneWidth, height: height, alignment: .topLeading)
        .coordinateSpace(.named(Self.handSpace))
    }

    private func diamond(_ mark: ClipKeyMark, index: Int, ruler: MotionStripRuler) -> some View {
        let dragging = drag?.fromMS == mark.documentMS
        let ms = dragging ? (drag?.toMS ?? mark.documentMS) : mark.documentMS
        let x = laneWidth * ruler.fraction(ofMS: Double(ms))
        let eased = editorState.document?.clipKeyEase(layerID: layerID, atMS: mark.documentMS).map { $0 != .linear } ?? true
        let isPicked = !mark.refs.isEmpty && mark.refs.isSubset(of: editorState.pickedKeys(layerID: layerID))
        return VideoKit.KeyMark(isEased: eased, isPicked: isPicked, isHovered: hoveredMS == mark.documentMS,
                                isHollow: mark.isHollow)
            .scaleEffect(dragging ? 1.35 : 1)
            .frame(width: Self.keySize, height: Self.keySize)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.handSpace))
                .onChanged { value in
                    let lapMS = max(1, editorState.lastDocumentTimeMS)
                    let fraction = max(0, value.location.x / max(1, laneWidth))
                    let landing = Int(editorState.motionStripRuler.ms(atFraction: Double(fraction)).rounded())
                    drag = Drag(fromMS: mark.documentMS, toMS: min(max(0, landing), lapMS))
                }
                .onEnded { _ in
                    if let drag { editorState.moveClipKeys(layerID: layerID, fromMS: drag.fromMS, toMS: drag.toMS) }
                    drag = nil
                })
            .onTapGesture {
                let flags = KeyClick.flags
                guard !flags.contains(.control) else { return }
                guard !mark.isHollow else {
                    editorState.clearKeySelection()
                    editorState.pickClipKey(layerID: layerID, atMS: mark.documentMS)
                    return
                }
                editorState.pickClipKeys(layerID: layerID, mark.refs, atMS: mark.documentMS,
                                         extending: flags.contains(.shift) || flags.contains(.command))
            }
            .playtestHover("Key \(index + 1) \(layerName)") { inside in
                if inside { hoveredMS = mark.documentMS } else if hoveredMS == mark.documentMS { hoveredMS = nil }
            }
            .contextMenu {
                TimelineKeyMenu(layerID: layerID, refs: mark.refs, atMS: mark.documentMS, lane: nil) {
                    editorState.clipKeyMenuRows(layerID: layerID, atMS: mark.documentMS)
                }
            }
            .playtestControl("Key \(index + 1)", detail: layerName)
            .panelReadout("key \(index + 1) at \(KeyLap.timecode(ms: mark.documentMS))"
                          + (mark.isHollow ? ", hollow" : "") + (isPicked ? ", picked" : ""))
            .panelHelp(KeyLap.timecode(ms: mark.documentMS))
            .padding(.leading, max(0, x - Self.keySize / 2))
            .padding(.top, (height - Self.keySize) / 2)
    }
}

/// The hollow diamond standing at the playhead on a layer with keys: the next
/// change to this layer lands here. Read in a view of its own, so moving the
/// playhead does not rebuild the keys.
private struct PictureKeyGhost: View {
    @Environment(EditorState.self) private var editorState
    let layerID: UUID
    let laneWidth: CGFloat
    let height: CGFloat

    var body: some View {
        if editorState.headerKeyDiamond(layerID) == .betweenKeys, !editorState.isMotionPlaying {
            let x = laneWidth * editorState.motionStripRuler.fraction(ofMS: Double(editorState.documentTimeMS))
            VideoKit.KeyMark(isHollow: true)
                .frame(width: 12, height: 12)
                .padding(.leading, max(0, x - 6))
                .padding(.top, (height - 12) / 2)
                .panelReadout("next key at \(KeyLap.timecode(ms: editorState.documentTimeMS))")
        }
    }
}
