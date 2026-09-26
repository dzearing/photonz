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
            VideoKit.DropdownRow(label: "Show", value: look.show.title) {
                ForEach(CaptionGrouping.allCases, id: \.self) { show in
                    Toggle(show.title, isOn: Binding(get: { look.show == show },
                                                     set: { _ in change { $0.show = show } }))
                }
            }
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
        VideoKit.DropdownRow(label: label, value: value.title) {
            ForEach(choices, id: \.self) { shade in
                Toggle(shade.title, isOn: Binding(get: { value == shade },
                                                  set: { _ in change { set(&$0, shade) } }))
            }
        }
        .playtestField("Caption \(label.lowercased())")
    }

    // MARK: - The word being said

    @ViewBuilder private func currentWord(_ word: CaptionWordLook) -> some View {
        heading("Current word").padding(.top, 6)
        CaptionColourRow(label: "Colour", value: word.colorHex, noneTitle: "Text colour",
                         choices: CaptionColourRow.bright) { hex in change { $0.word.colorHex = hex } }
        CaptionColourRow(label: "Pill", value: word.pillHex,
                         choices: CaptionColourRow.bright) { hex in change { $0.word.pillHex = hex } }
        CaptionColourRow(label: "Glow", value: word.glowHex,
                         choices: CaptionColourRow.bright) { hex in change { $0.word.glowHex = hex } }
        CaptionColourRow(label: "Stroke", value: word.strokeHex,
                         choices: CaptionColourRow.edges) { hex in change { $0.word.strokeHex = hex } }
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
        VideoKit.DropdownRow(label: "Animation", value: word.motion.title) {
            ForEach(CaptionWordMotion.allCases, id: \.self) { motion in
                Toggle(motion.title, isOn: Binding(get: { word.motion == motion },
                                                   set: { _ in change { $0.word.pick(motion) } }))
            }
        }
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
    let choices: [(String, String)]
    let pick: (String?) -> Void

    static let bright: [(String, String)] = [
        ("Yellow", CaptionLook.activeYellow), ("Cyan", CaptionLook.karaokeCyan), ("Pink", "#FF4FD8"),
        ("Green", "#3ECF8E"), ("White", "#FFFFFF"), ("Black", "#000000"),
    ]
    static let edges: [(String, String)] = [
        ("Black", "#000000"), ("White", "#FFFFFF"), ("Yellow", CaptionLook.activeYellow),
        ("Cyan", CaptionLook.karaokeCyan), ("Pink", "#FF4FD8"),
    ]

    var body: some View {
        let name = value.flatMap { hex in choices.first { $0.1.uppercased() == hex.uppercased() }?.0 }
            ?? (value ?? noneTitle)
        VideoKit.DropdownRow(label: label, value: name, swatch: value.map(CaptionsInspector.swatch)) {
            Toggle(noneTitle, isOn: Binding(get: { value == nil }, set: { _ in pick(nil) }))
            ForEach(choices, id: \.0) { choice in
                Toggle(choice.0, isOn: Binding(get: { choice.1.uppercased() == value?.uppercased() },
                                               set: { _ in pick(choice.1) }))
            }
        }
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
                CaptionStylePreview(look: style)
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
struct CaptionStylePreview: View {
    let look: CaptionLook
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [Color(white: 0.2), Color(white: 0.08)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if reduceMotion {
                    frame(atMS: 1_400, size: proxy.size)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                        let ms = Int(context.date.timeIntervalSinceReferenceDate * 1000)
                            % CaptionLook.previewCycleMS
                        frame(atMS: ms, size: proxy.size)
                    }
                }
            }
        }
    }

    @ViewBuilder private func frame(atMS ms: Int, size: CGSize) -> some View {
        let width = max(20, size.width - 8)
        let font: CGFloat = 10
        if let text = look.previewText(atMS: ms, fontSize: font, width: width),
           let image = TextRasterizer.rasterize(
               text, size: CGSize(width: width, height: max(font * 2.6, size.height - 4)),
               outlines: look.strokeHex.map { [TextRasterizer.TextOutline(width: 1, colorHex: $0)] } ?? [],
               scale: displayScale) {
            Image(decorative: image, scale: displayScale)
                .shadow(color: glow, radius: look.glowHex == nil ? 0 : 3)
                .shadow(color: .black.opacity(look.shadow == .none ? 0 : 0.6), radius: 1.5, y: 1)
                .frame(width: size.width, height: size.height)
        }
    }

    private var glow: Color {
        guard let hex = look.glowHex, let rgba = RGBA(hex: hex) else { return .clear }
        return Color(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: 0.9)
    }
}
