import PhotonzCore
import PhotonzMedia
import SwiftUI

/// **Captions**: the words the app writes off the sound, as label and value
/// rows (`Captions.swift`, `CaptionLook.swift`, `pages/video-captions.html`).
///
/// Before there are any captions, one thing: the Add Captions button. Captions
/// are made only when somebody asks (the user, 2026-09-28), so there is no
/// Auto switch and nothing listens as a recording opens.
///
/// Once there are some, three parts in the mock's order: how they are written
/// (the language, and Rewrite), the cue in focus (its in, out, length and
/// words), and the one look every caption wears (a named style, then font,
/// size, colour, background, lit word and position). Timing and the subtitle
/// file are the last two rows. Anything longer than a label is the row's
/// tooltip.
struct CaptionsInspector: View {
    @Environment(EditorState.self) private var editorState
    @State private var languages: [Locale] = []

    var body: some View {
        // Read so a change to the language draws the rows again.
        let _ = editorState.captionSettingsTick
        VStack(alignment: .leading, spacing: 6) {
            if editorState.isWritingCaptions {
                listening
            } else if !editorState.hasCaptions {
                addCaptionsButton
            } else {
                language
                guides
                generate
                CaptionCueInFocusRows()
                Divider().padding(.vertical, 2)
                CaptionWordsInspector()
                Divider().padding(.vertical, 2)
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
        return VideoKit.DropdownRow(
            label: "Language", value: Self.title(of: current),
            choices: .picking(languageChoices, current: current, title: { Self.title(of: $0) }) { id in
                EditorState.captionsLanguage = id
                editorState.captionsSettingsChanged()
            })
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

    /// The title-safe and action-safe guides over the picture, on or off.
    private var guides: some View {
        VideoKit.FieldRow(label: "Guides") {
            Button { editorState.toggleSafeAreas() } label: {
                Label("Safe areas", systemImage: "viewfinder")
            }
            .buttonStyle(CaptionBarButtonStyle(filled: EditorState.showsSafeAreas))
            .accessibilityValue(EditorState.showsSafeAreas ? "On" : "Off")
            .panelHelp("Show title and action safe areas")
            .playtestControl("Safe areas", detail: EditorState.showsSafeAreas ? "on" : "off")
        }
    }

    /// The section before there are any captions: this, and nothing else.
    private var addCaptionsButton: some View {
        Button {
            editorState.writeCaptions()
        } label: {
            Label("Add Captions", systemImage: "captions.bubble")
                .lineLimit(1)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .fixedSize()
        .disabled(!editorState.canWriteCaptions)
        .playtestControl("Add Captions", detail: "the Captions section")
        .panelHelp(editorState.canWriteCaptions
            ? "Listen on this Mac, never uploaded, and write the words."
            : Captions.nothingToHear)
    }

    /// The button that writes them (again), and how many there are.
    ///
    /// The button is never cut short: it keeps its whole label, and in a dock
    /// too narrow for it beside its name the row drops it under the name. The
    /// count sits beside it while there is room and steps away when there is
    /// not; the Cue row still says which of how many is on screen. Until
    /// 2026-09-27 both shared the row's 148pt and the button read "Write Ag...".
    private var generate: some View {
        VideoKit.FieldRow(label: "Generate") {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    generateButton
                    if let count { countReading(count) }
                }
                generateButton
            }
        }
    }

    private var generateButton: some View {
        Button {
            editorState.writeCaptions()
        } label: {
            Label("Rewrite", systemImage: "sparkles")
                .lineLimit(1)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .fixedSize()
        .disabled(!editorState.canWriteCaptions)
        .playtestField("Write Captions")
        .panelHelp("Listen on this Mac, never uploaded, and write the words.")
    }

    private func countReading(_ count: String) -> some View {
        Text(count)
            .font(.system(size: 10.5))
            .foregroundStyle(VideoKit.Palette.faint)
            .lineLimit(1)
            .fixedSize()
            .panelReadout(count)
            .playtestField("Captions reading")
            .panelHelp(editorState.captionsReading)
    }

    /// How many there are, in two words, or nothing before there are any.
    private var count: String? {
        guard editorState.hasCaptions else { return nil }
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
                Button("Cancel") { editorState.stopWritingCaptions() }
                    .controlSize(.small)
                    .playtestField("Stop Writing Captions")
                    .panelHelp("Stop, and keep every word heard so far.")
            }
        }
    }

    /// `2.43s`, the mock's reading.
    static func seconds(_ ms: Int) -> String {
        String(format: "%.2fs", Double(ms) / 1000)
    }


    // MARK: - One look for every caption

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

    // MARK: - Timing and the way out

    /// The whole track, earlier or later. One caption out of step is its bar's
    /// end, dragged on the timeline.
    private var timing: some View {
        VideoKit.FieldRow(label: "Timing") {
            // Never cut short: the words while they fit, the arrows alone
            // (their words in the tip) in a dock too narrow for them. Until
            // 2026-09-29 a narrow dock read "Ear..." and "La...".
            ViewThatFits(in: .horizontal) {
                timingButtons(words: true)
                timingButtons(words: false)
            }
        }
    }

    private func timingButtons(words: Bool) -> some View {
        HStack(spacing: 6) {
            nudgeButton("Earlier", systemImage: "arrow.left", byMS: -EditorState.captionNudgeMS,
                        words: words, help: "Every caption a tenth of a second earlier.")
            nudgeButton("Later", systemImage: "arrow.right", byMS: EditorState.captionNudgeMS,
                        words: words, help: "Every caption a tenth of a second later.")
        }
        .controlSize(.small)
    }

    private func nudgeButton(_ title: String, systemImage: String, byMS: Int, words: Bool,
                             help: String) -> some View {
        Button {
            editorState.nudgeCaptions(byMS: byMS)
        } label: {
            if words {
                Label(title, systemImage: systemImage).lineLimit(1)
            } else {
                Image(systemName: systemImage).accessibilityLabel(title)
            }
        }
        .fixedSize()
        .disabled(!editorState.canNudgeCaptions)
        .playtestControl("Captions \(title)", detail: "the Captions section")
        .panelHelp(help)
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

/// The cue under the playhead (or the one picked): which of how many, and its
/// in, out, length and words. A view of its own because it is the one part of
/// the section that follows the playhead: inside the section's body, every
/// step of an arrow key re-read every cue's words for the count above it
/// (`a-long-captioned-recording-walk`).
private struct CaptionCueInFocusRows: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
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
                    field("In", CaptionsInspector.seconds(time.inMS))
                    field("Out", CaptionsInspector.seconds(time.outMS))
                }
                GridRow {
                    field("Dur", CaptionsInspector.seconds(time.outMS - time.inMS))
                    field("Words", "\(words)")
                }
            }
            .playtestField("Cue")
        }
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
}

/// **Text**, for a picked Captions layer: the same font, size, weight, colour
/// and alignment controls a text layer has, set once for every caption in the
/// layer (`CaptionLook`). A Captions layer is picked, moved and sized like any
/// other layer; this is where its type is.
struct CaptionsTextInspector: View {
    @Environment(EditorState.self) private var editorState

    var body: some View {
        let look = editorState.captionLook
        let size = editorState.document?.canvasSize ?? .zero
        VStack(alignment: .leading, spacing: 8) {
            SelectionMenu(label: "Font",
                          reading: StyleReading(value: look.fontName, isMixed: false),
                          options: TextStyles.fontOptions(picked: [look.fontName]),
                          title: { $0 },
                          help: "The font of every caption") { font in
                editorState.setCaption(.font, to: .font(font))
            }
            PanelPair {
                let shown = look.resolvedFontSize(in: size)
                SelectionMenu(label: "Size",
                              reading: StyleReading(value: shown, isMixed: false),
                              options: Self.sizes(with: shown),
                              title: { TextStyles.sizeWords($0) },
                              help: "The size of every caption") { picked in
                    editorState.setCaption(.size, to: .size(picked))
                }
                SelectionMenu(label: "Weight",
                              reading: StyleReading(value: look.weight, isMixed: false),
                              options: TextWeight.allCases,
                              title: { $0.rawValue.capitalized },
                              help: "The weight of every caption") { weight in
                    editorState.setCaption(.weight, to: .weight(weight))
                }
            }
            CaptionColourWellRow(control: .textColour, name: "Caption colour", look: look)
            CaptionColourWellRow(control: .background, name: "Caption background", look: look)
            // The whole text's own glow, outline and shadow; the word being
            // said has its own in the Captions section.
            CaptionColourWellRow(control: .glow, name: "Caption glow", look: look)
            CaptionColourWellRow(control: .stroke, name: "Caption stroke", look: look)
            VideoKit.DropdownRow(
                label: "Shadow", value: look.shadow.title,
                choices: .picking(CaptionShadow.allCases, current: look.shadow, title: \.title) { shadow in
                    editorState.setCaption(.shadow, to: .shadow(shadow))
                })
            .playtestField("Caption shadow")
            VStack(alignment: .leading, spacing: 2) {
                Text("Align").font(.caption).foregroundStyle(.secondary)
                SegmentedControl("Align", selection: look.alignment,
                                 options: TextAlign.allCases.map {
                                     .init($0, $0.title, image: SegmentedControl<TextAlign>.symbol($0.symbolName, named: $0.title))
                                 },
                                 form: .natural, showsTitles: false,
                                 systemHelp: "Where the words sit across the box") { align in
                    editorState.setCaption(.align, to: .align(align))
                }
                .controlSize(.small)
            }
            .playtestField("Caption align")
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 8)
    }

    /// The text sizes, plus the size the captions are at now.
    static func sizes(with shown: CGFloat) -> [CGFloat] {
        let base = TextStyles.fontSizes
        return base.contains(shown) ? base : (base + [shown]).sorted()
    }
}
