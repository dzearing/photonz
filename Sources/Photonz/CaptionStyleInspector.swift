import PhotonzCore
import PhotonzRender
import SwiftUI

/// **How the words show**, in the Captions section: a row of style tiles
/// that play the real caption in each style, then how many words show at a
/// time, how the words either side of the one being said look, and the
/// current word's own colour, pill, glow, outline, shadow, size and motion
/// (`CaptionWordStyle.swift`). Label and control rows only.
struct CaptionWordsInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let _ = editorState.captionSettingsTick
        let look = editorState.captionLook
        VStack(alignment: .leading, spacing: 6) {
            heading("Caption style")
            CaptionStyleTiles(look: look)
            VideoKit.DropdownRow(
                label: "Show", value: look.show.title,
                choices: .picking(CaptionGrouping.allCases, current: look.show, title: \.title) { show in
                    change { $0.show = show }
                })
            .playtestField("Show")
            .panelHelp("How many words are on screen at a time.")
            if look.show.usesLines {
                VideoKit.FieldRow(label: "Lines") {
                    VideoKit.Segmented(options: [(1, "1"), (2, "2")], selection: look.lines) { lines in
                        change { $0.lines = lines }
                    }
                    .playtestControl("Caption lines", detail: "the Captions section")
                    .panelHelp("The most lines a caption fills.")
                }
            }
            shadeRow("Said", value: look.said, choices: CaptionWordShade.saidChoices) { $0.said = $1 }
            shadeRow("Coming", value: look.coming, choices: CaptionWordShade.comingChoices) { $0.coming = $1 }
            currentWord(look.word)
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(VideoKit.Palette.dim)
    }

    private func change(_ edit: (inout CaptionLook) -> Void) {
        editorState.changeCaptionLook(edit)
    }

    private func shadeRow(_ label: String, value: CaptionWordShade, choices: [CaptionWordShade],
                          set: @escaping (inout CaptionLook, CaptionWordShade) -> Void) -> some View {
        VideoKit.DropdownRow(
            label: label, value: value.title,
            choices: .picking(choices, current: value, title: \.title) { shade in
                change { set(&$0, shade) }
            })
        .playtestField("Caption \(label.lowercased())")
    }

    // MARK: - The word being said

    @ViewBuilder private func currentWord(_ word: CaptionWordLook) -> some View {
        heading("Current word").padding(.top, 6)
        CaptionColourRow(label: "Colour", value: word.colorHex, noneTitle: "Text colour",
                         choices: CaptionColourNames.bright) { hex in change { $0.word.colorHex = hex } }
        CaptionColourRow(label: "Pill", value: word.pillHex,
                         choices: CaptionColourNames.bright) { hex in change { $0.word.pillHex = hex } }
        CaptionColourRow(label: "Glow", value: word.glowHex,
                         choices: CaptionColourNames.bright) { hex in change { $0.word.glowHex = hex } }
        CaptionColourRow(label: "Stroke", value: word.strokeHex,
                         choices: CaptionColourNames.edges) { hex in change { $0.word.strokeHex = hex } }
        VideoKit.FieldRow(label: "Shadow") {
            Toggle("Shadow", isOn: Binding(get: { word.shadow },
                                           set: { on in change { $0.word.shadow = on } }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .playtestControl("Current word shadow", detail: "the Captions section")
        }
        VideoKit.FieldRow(label: "Scale") {
            HStack(spacing: 8) {
                Slider(value: Binding(get: { Double(word.scale) },
                                      set: { value in change { $0.word.scale = CGFloat(value) } }),
                       in: Double(CaptionWordLook.scaleRange.lowerBound)...Double(CaptionWordLook.scaleRange.upperBound))
                    .controlSize(.small)
                    .playtestField("Current word scale")
                readout("\(Int((word.scale * 100).rounded()))%")
            }
        }
        VideoKit.DropdownRow(
            label: "Animation", value: word.motion.title,
            choices: .picking(CaptionWordMotion.allCases, current: word.motion, title: \.title) { motion in
                change { $0.word.pick(motion) }
            })
        .playtestField("Animation")
        if word.motion != .none {
            VideoKit.FieldRow(label: "Speed") {
                HStack(spacing: 8) {
                    // Right is quicker: the slider reads as speed, the value
                    // as how long the motion takes.
                    let range = CaptionWordLook.speedRange
                    Slider(value: Binding(get: { Double(range.upperBound + range.lowerBound - word.speedMS) },
                                          set: { value in change {
                                              $0.word.speedMS = range.upperBound + range.lowerBound - Int(value.rounded())
                                          } }),
                           in: Double(range.lowerBound)...Double(range.upperBound))
                        .controlSize(.small)
                        .playtestField("Current word speed")
                    readout(String(format: "%.2fs", Double(word.speedMS) / 1000))
                }
            }
        }
    }

    private func readout(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(VideoKit.Palette.ink)
            .frame(width: 36, alignment: .trailing)
            .panelReadout(text)
    }
}

/// One colour, from a short list, or none.
struct CaptionColourRow: View {
    let label: String
    /// What a walk calls it.
    var field: String? = nil
    let value: String?
    var noneTitle = "None"
    let choices: [CaptionColourNames.Choice]
    let pick: (String?) -> Void

    var body: some View {
        let name = CaptionColourNames.name(of: value, among: choices, none: noneTitle)
        VideoKit.DropdownRow(
            label: label, value: name, swatch: value.map(CaptionsInspector.swatch),
            choices: [.item(noneTitle, isOn: value == nil) { pick(nil) }]
                + choices.map { choice in
                    .item(choice.name, isOn: choice.hex?.uppercased() == value?.uppercased()) { pick(choice.hex) }
                })
        .playtestField(field ?? "Current word \(label.lowercased())")
    }
}

// MARK: - Style tiles

/// The named styles and the user's own, each a tile playing the real caption
/// in that style, the way the transition picker's tiles play their
/// transition. A click wears the style; the last tile keeps the look you have
/// now as a style of your own.
struct CaptionStyleTiles: View {
    @Environment(EditorState.self) private var editorState
    let look: CaptionLook

    var body: some View {
        // Read so a style kept or deleted draws the tiles again.
        let _ = editorState.captionSettingsTick
        let saved = EditorState.captionStyles.styles
        VideoKit.TileGrid(minimumWidth: 72, columns: 3, spacing: 6) {
            ForEach(CaptionLook.Preset.allCases, id: \.self) { preset in
                let style = CaptionLook.preset(preset)
                tile(preset.title, style: style, isSelected: look.wears(style)) {
                    editorState.pickCaptionStyle(style, keepingType: true)
                }
            }
            ForEach(saved) { mine in
                tile(mine.name, style: mine.look, isSelected: look == mine.look) {
                    editorState.pickCaptionStyle(mine.look, keepingType: false)
                }
                .contextMenu {
                    Button("Delete Style") { editorState.removeCaptionStyle(id: mine.id) }
                }
            }
            Button {
                editorState.saveCaptionStyle()
            } label: {
                VideoKit.Tile(name: "Save style", thumbnailHeight: 34) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(VideoKit.Palette.dim)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .buttonStyle(.plain)
            .playtestControl("Save caption style", detail: "the Captions section")
            .panelHelp("Keep this look as a style of your own.")
        }
        .playtestField("Caption styles")
    }

    private func tile(_ name: String, style: CaptionLook, isSelected: Bool,
                      pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            VideoKit.Tile(name: name, isSelected: isSelected, thumbnailHeight: 34) {
                CaptionStylePreview(look: style).equatable()
            }
        }
        .buttonStyle(.plain)
        .playtestControl("Caption style \(name)", detail: isSelected ? "on" : "off")
        .accessibilityLabel(name)
    }
}

/// A caption in `look`, playing its words on a dark frame: the rasterizer the
/// film is drawn with, at tile size. Holds one moment still for anyone who
/// has asked for less motion.
///
/// Equatable on its look, and drawn `.equatable()`: the Captions section
/// follows the picked caption, so every pick re-ran all five tiles and set
/// their words again in the click's own pass: five tile bodies a pick before,
/// none after (2026-09-27, `caption-pick-answers-at-once-walk`). A style does
/// not change when the pick does, so the tile keeps its frame.
///
/// The words play as a reel Core Animation runs (`VideoKit.LoopingFrames`):
/// the lap's frames are drawn once, off the main thread, and nothing runs on
/// it while they play. The tile holds its still moment until they are ready.
struct CaptionStylePreview: View, Equatable {
    let look: CaptionLook

    nonisolated static func == (lhs: CaptionStylePreview, rhs: CaptionStylePreview) -> Bool {
        lhs.look == rhs.look
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var played: VideoKit.PlayedReel?

    /// What a reel was drawn for: the style, the tile's size and the screen's.
    private struct ReelKey: Hashable {
        let look: CaptionLook
        let size: CGSize
        let scale: CGFloat
    }

    private static let fontSize: CGFloat = 10

    var body: some View {
        // Read here, not inside the reader: a state read only inside its
        // closure does not bring the closure back when the reel lands, and
        // the tile stayed on its still moment for good.
        let played = reduceMotion ? nil : played
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [Color(white: 0.2), Color(white: 0.08)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if let played {
                    VideoKit.LoopingFrames(reel: played, scale: displayScale, shadows: shadows)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    frame(atMS: 1_400, size: proxy.size)
                }
            }
            .task(id: ReelKey(look: look, size: proxy.size, scale: displayScale)) {
                guard !reduceMotion else { return }
                await play(ReelKey(look: look, size: proxy.size, scale: displayScale))
            }
        }
    }

    private func play(_ key: ReelKey) async {
        if let ready = VideoKit.PlayedReels[key] {
            played = ready
            return
        }
        // A tile already playing is being resized: wait for the size to
        // settle rather than drawing a lap for every width it passes through.
        if played != nil {
            try? await Task.sleep(for: .milliseconds(150))
            if Task.isCancelled { return }
        }
        guard key.size.width > 0, key.size.height > 0 else { return }
        let reel = await Task.detached(priority: .userInitiated) {
            Self.draw(key.look, size: key.size, scale: key.scale)
        }.value
        guard !Task.isCancelled, let reel else { return }
        VideoKit.PlayedReels.keep(reel, for: key)
        played = reel
    }

    /// Every frame of `look`'s lap that differs, as pictures.
    nonisolated private static func draw(_ look: CaptionLook, size: CGSize, scale: CGFloat) -> VideoKit.PlayedReel? {
        let box = textBox(size)
        let reel = look.previewReel(fontSize: fontSize, width: box.width)
        let outlines = look.strokeHex.map { [TextRasterizer.TextOutline(width: 1, colorHex: $0)] } ?? []
        var frames: [CGImage] = []
        for shot in reel.shots {
            // A moment with nothing to say is an empty frame, not a skipped
            // one, or the words before it would linger.
            guard let image = shot.frame.flatMap({
                TextRasterizer.rasterize($0, size: box, outlines: outlines, scale: scale)
            }) ?? blank else { return nil }
            frames.append(image)
        }
        return VideoKit.PlayedReel(frames: frames, keyTimes: reel.keyTimes,
                                   lapSeconds: Double(reel.lapMS) / 1000)
    }

    nonisolated private static func textBox(_ size: CGSize) -> CGSize {
        CGSize(width: max(20, size.width - 8), height: max(fontSize * 2.6, size.height - 4))
    }

    nonisolated private static let blank: CGImage? = CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )?.makeImage()

    @ViewBuilder private func frame(atMS ms: Int, size: CGSize) -> some View {
        let box = Self.textBox(size)
        if let text = look.previewText(atMS: ms, fontSize: Self.fontSize, width: box.width),
           let image = TextRasterizer.rasterize(
               text, size: box,
               outlines: look.strokeHex.map { [TextRasterizer.TextOutline(width: 1, colorHex: $0)] } ?? [],
               scale: displayScale) {
            Image(decorative: image, scale: displayScale)
                .shadow(color: glow, radius: look.glowHex == nil ? 0 : 3)
                .shadow(color: .black.opacity(look.shadow == .none ? 0 : 0.6), radius: 1.5, y: 1)
                .frame(width: size.width, height: size.height)
        }
    }

    /// The same two shadows the still frame wears, for the playing one.
    private var shadows: [VideoKit.FrameShadow] {
        var shadows: [VideoKit.FrameShadow] = []
        if let glow = glowColor { shadows.append(.init(color: glow, radius: 3)) }
        if look.shadow != .none {
            shadows.append(.init(color: CGColor(gray: 0, alpha: 0.6), radius: 1.5, offset: CGSize(width: 0, height: 1)))
        }
        return shadows
    }

    private var glowColor: CGColor? {
        guard let hex = look.glowHex, let rgba = RGBA(hex: hex) else { return nil }
        return CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: 0.9)
    }

    private var glow: Color {
        glowColor.map { Color(cgColor: $0) } ?? .clear
    }
}
