import PhotonzCore
import PhotonzMedia
import SwiftUI

/// **Captions**: the words the app writes off the sound, as label and value
/// rows (`Captions.swift`, `CaptionLook.swift`, `pages/video-captions.html`).
///
/// Three parts, in the mock's order: how they are written (the language, and
/// Auto, which writes them by itself when a recording with speech opens), the
/// cue in focus (its in, out, length and words), and the one look every
/// caption wears (a named style, then font, size, colour, background, lit word
/// and position). Timing and the subtitle file are the last two rows. Anything
/// longer than a label is the row's tooltip.
struct CaptionsInspector: View {
    @Environment(EditorState.self) private var editorState
    @State private var languages: [Locale] = []

    var body: some View {
        // Read so a change to Auto or the language draws the rows again.
        let _ = editorState.captionSettingsTick
        VStack(alignment: .leading, spacing: 6) {
            language
            auto
            if editorState.isWritingCaptions { listening } else { generate }
            if editorState.hasCaptions && !editorState.isWritingCaptions {
                cue
                Divider().padding(.vertical, 2)
                style
                timing
                file
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { languages = await SpeechTranscription.languages() }
    }

    // MARK: - Writing them

    private var language: some View {
        let current = EditorState.captionsLanguage
        return VideoKit.DropdownRow(label: "Language", value: Self.title(of: current)) {
            ForEach(languageChoices, id: \.self) { id in
                Toggle(Self.title(of: id), isOn: Binding(
                    get: { id == current },
                    set: { _ in EditorState.captionsLanguage = id; editorState.captionsSettingsChanged() }))
            }
        }
        .playtestField("Captions language")
        .panelHelp("The language the words are heard in.")
    }

    /// The languages this Mac can hear, English first, the one in use always
    /// among them.
    private var languageChoices: [String] {
        var ids = languages.map(\.identifier).map { $0.replacingOccurrences(of: "_", with: "-") }
        if ids.isEmpty { ids = ["en-US"] }
        let current = EditorState.captionsLanguage
        if !ids.contains(current) { ids.insert(current, at: 0) }
        return Array(Set(ids)).sorted { a, b in
            let ea = a.hasPrefix("en"), eb = b.hasPrefix("en")
            return ea != eb ? ea : Self.title(of: a) < Self.title(of: b)
        }
    }

    /// `English (en-US)`.
    static func title(of id: String) -> String {
        let name = Locale.current.localizedString(forLanguageCode: id) ?? id
        return "\(name) (\(id))"
    }

    private var auto: some View {
        VideoKit.FieldRow(label: "Auto") {
            Toggle("Write captions by themselves", isOn: Binding(
                get: { EditorState.captionsWriteThemselves },
                set: { EditorState.captionsWriteThemselves = $0; editorState.captionsSettingsChanged() }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .playtestControl("Auto captions", detail: "the Captions section")
                .panelHelp("Write captions when a talking recording opens.")
        }
    }

    /// How many there are, and the button that writes them (again).
    private var generate: some View {
        VideoKit.FieldRow(label: "Generate") {
            HStack(spacing: 6) {
                Button {
                    editorState.writeCaptions()
                } label: {
                    Label(editorState.hasCaptions ? "Write Again" : "Auto captions", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!editorState.canWriteCaptions)
                .playtestField("Write Captions")
                .panelHelp("Listen on this Mac, never uploaded, and write the words.")
                Text(count)
                    .font(.system(size: 10.5))
                    .foregroundStyle(VideoKit.Palette.faint)
                    .lineLimit(1)
                    .panelReadout(count)
                    .playtestField("Captions reading")
                    .panelHelp(editorState.captionsReading)
            }
        }
    }

    /// How many there are, in two words.
    private var count: String {
        guard editorState.hasCaptions else { return "None yet" }
        let cues = editorState.captionCount
        return "\(cues) caption\(cues == 1 ? "" : "s")"
    }

    /// While it listens: how far along, and a way out that keeps the words.
    private var listening: some View {
        VideoKit.FieldRow(label: "Listening") {
            HStack(spacing: 6) {
                ProgressView(value: editorState.captionsBeingWritten?.share ?? 0)
                    .controlSize(.small)
                    .playtestField("Captions progress")
                    .panelHelp(editorState.captionsReading)
                Button("Stop") { editorState.stopWritingCaptions() }
                    .controlSize(.small)
                    .playtestField("Stop Writing Captions")
                    .panelHelp("Stop, and keep every word heard so far.")
            }
        }
    }

    // MARK: - The cue in focus

    @ViewBuilder private var cue: some View {
        if let focus = editorState.captionCueInFocus, let time = focus.layer.time {
            VideoKit.FieldRow(label: "Cue") {
                Text("\(focus.index + 1) of \(focus.of)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(VideoKit.Palette.dim)
                    .panelReadout("cue \(focus.index + 1) of \(focus.of)")
            }
            let words = focus.layer.captionWords?.count ?? 0
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    field("In", Self.seconds(time.inMS))
                    field("Out", Self.seconds(time.outMS))
                }
                GridRow {
                    field("Dur", Self.seconds(time.outMS - time.inMS))
                    field("Words", "\(words)")
                }
            }
            .playtestField("Cue")
        }
    }

    /// `2.43s`, the mock's reading.
    static func seconds(_ ms: Int) -> String {
        String(format: "%.2fs", Double(ms) / 1000)
    }

    private func field(_ key: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(key).font(.system(size: 10)).foregroundStyle(VideoKit.Palette.faint)
            Spacer(minLength: 0)
            Text(value).font(.system(size: 11, weight: .medium)).monospacedDigit()
                .foregroundStyle(VideoKit.Palette.ink)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 6).fill(VideoKit.Palette.glassThin))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(VideoKit.Palette.edgeLo))
    }

    // MARK: - One look for every caption

    @ViewBuilder private var style: some View {
        let look = editorState.captionLook
        // The mock's style bar spans the section (`#styleSeg`, width 100%).
        // Beside a row label its three names are wider than the dock, and a
        // segmented control never shrinks, so it pushed the whole panel past
        // the window's right edge whenever a document had captions.
        Picker("Style", selection: Binding(
            get: { look.preset },
            set: { editorState.pickCaptionPreset($0) })) {
            ForEach(CaptionLook.Preset.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(maxWidth: .infinity)
        .playtestControl("Caption style", detail: "the Captions section")
        .panelHelp("One look for every caption.")
        VideoKit.DropdownRow(label: "Font", value: look.fontName) {
            ForEach(Self.fonts, id: \.self) { font in
                Toggle(font, isOn: Binding(get: { look.fontName == font },
                                           set: { _ in editorState.changeCaptionLook { $0.fontName = font } }))
            }
        }
        .playtestField("Caption font")
        VideoKit.DropdownRow(label: "Size", value: Self.sizeTitle(look.fontSize)) {
            ForEach(Self.sizes, id: \.self) { size in
                let value: CGFloat? = size == 0 ? nil : CGFloat(size)
                Toggle(Self.sizeTitle(value), isOn: Binding(
                    get: { look.fontSize == value },
                    set: { _ in editorState.changeCaptionLook { $0.fontSize = value } }))
            }
        }
        .playtestField("Caption size")
        colourRow("Colour", value: look.colorHex, choices: Self.inks) { hex in
            editorState.changeCaptionLook { $0.colorHex = hex ?? "#FFFFFF" }
        }
        colourRow("Background", value: look.backgroundHex, choices: Self.plates) { hex in
            editorState.changeCaptionLook { $0.backgroundHex = hex }
        }
        colourRow("Active", value: look.activeHex, choices: Self.actives) { hex in
            editorState.changeCaptionLook { $0.activeHex = hex }
        }
        VideoKit.FieldRow(label: "Position") {
            Picker("Position", selection: Binding(
                get: { look.position },
                set: { position in editorState.changeCaptionLook { $0.position = position } })) {
                ForEach(CaptionLook.Position.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .playtestControl("Caption position", detail: "the Captions section")
        }
    }

    private func colourRow(_ label: String, value: String?, choices: [(String, String?)],
                           pick: @escaping (String?) -> Void) -> some View {
        let name = choices.first { $0.1?.uppercased() == value?.uppercased() }?.0 ?? (value ?? "None")
        return VideoKit.DropdownRow(label: label, value: name, swatch: value.map(Self.swatch)) {
            ForEach(choices, id: \.0) { choice in
                Toggle(choice.0, isOn: Binding(get: { choice.1?.uppercased() == value?.uppercased() },
                                               set: { _ in pick(choice.1) }))
            }
        }
        .playtestField("Caption \(label.lowercased())")
    }

    static func swatch(_ hex: String) -> AnyShapeStyle {
        let rgba = RGBA(hex: hex) ?? RGBA(r: 1, g: 1, b: 1)
        return AnyShapeStyle(Color(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a))
    }

    static let fonts = ["SF Pro", "SF Pro Rounded", "New York", "Avenir Next", "Helvetica Neue", "Menlo"]
    /// Zero is Auto: the size that reads the same on any picture.
    static let sizes = [0, 24, 32, 40, 48, 56, 64, 72, 96]
    static func sizeTitle(_ size: CGFloat?) -> String {
        guard let size else { return "Auto" }
        return "\(Int(size)) px"
    }
    static let inks: [(String, String?)] = [("White", "#FFFFFF"), ("Yellow", "#FFD76A"),
                                             ("Black", "#000000"), ("Cyan", "#7FE7FF")]
    static let plates: [(String, String?)] = [("None", nil), ("Dark", CaptionLook.plate),
                                               ("Black", "#000000"), ("White", "#FFFFFFE6")]
    static let actives: [(String, String?)] = [("None", nil), ("Yellow", CaptionLook.activeYellow),
                                                ("Cyan", "#7FE7FF"), ("Pink", "#FF7AB6")]

    // MARK: - Timing and the way out

    /// The whole track, earlier or later. One caption out of step is its bar's
    /// end, dragged on the timeline.
    private var timing: some View {
        VideoKit.FieldRow(label: "Timing") {
            HStack(spacing: 6) {
                Button {
                    editorState.nudgeCaptions(byMS: -EditorState.captionNudgeMS)
                } label: {
                    Label("Earlier", systemImage: "arrow.left")
                }
                .disabled(!editorState.canNudgeCaptions)
                .playtestField("Captions Earlier")
                .panelHelp("Every caption a tenth of a second earlier.")
                Button {
                    editorState.nudgeCaptions(byMS: EditorState.captionNudgeMS)
                } label: {
                    Label("Later", systemImage: "arrow.right")
                }
                .disabled(!editorState.canNudgeCaptions)
                .playtestField("Captions Later")
                .panelHelp("Every caption a tenth of a second later.")
            }
            .controlSize(.small)
        }
    }

    private var file: some View {
        VideoKit.FieldRow(label: "Subtitles") {
            HStack(spacing: 6) {
                Menu("Export") {
                    ForEach(CaptionFileFormat.allCases, id: \.self) { format in
                        Button(format.title + "…") { editorState.exportCaptions(as: format) }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(!editorState.canExportCaptions)
                .playtestField("Export Captions")
                .panelHelp("Save the words as a subtitle file.")
                Button("Clear") { editorState.clearCaptions() }
                    .disabled(!editorState.canClearCaptions)
                    .playtestField("Clear Captions")
                    .panelHelp("Take every caption off.")
            }
            .controlSize(.small)
        }
    }
}
