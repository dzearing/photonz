import PhotonzCore
import SwiftUI

/// **Title**: a few knobs that restyle the picked title at once, before anybody
/// needs to touch its parts one by one (`TitleRestyle.swift`,
/// `docs/design/video-titles-polish.md`, "What the person sees", step 4).
///
/// In the design's order: Theme, Font Pair, Energy, Intensity, Background,
/// then Sounds (a switch, off until turned on). Then Part, which picks one part of the title for the Part section below.
/// No mock draws this section; its rows are the panel's own controls
/// (UX-PATTERNS §4): swatches for colours, a dropdown for a list of more than
/// three, segments for three, a slider for a strength.
struct TitleRestyleInspector: View {
    @Environment(EditorState.self) private var editorState

    static let sectionHelp = "Restyles the whole title at once. Pick a part below to change how it comes in, "
        + "holds and goes off."

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let recipe = editorState.titleRecipeInHand {
                theme(recipe)
                fonts(recipe)
                energy(recipe)
                intensity(recipe)
                if recipe.background != nil { background(recipe) }
                sounds(recipe)
                part()
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Theme

    private func theme(_ recipe: TitleRecipe) -> some View {
        let themes = [recipe.originalTheme] + TitleTheme.curated
        let recording = recipe.theme.id == TitleTheme.recordingID ? recipe.theme : nil
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                PanelRowLabel(text: "Theme")
                Spacer(minLength: 4)
                Text(recipe.theme.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .panelReadout(recipe.theme.name)
            }
            .playtestField("Title Theme")
            // Ten across in the panel's narrowest column: never wider than
            // it, or the whole panel scrolls sideways.
            HStack(spacing: 2) {
                ForEach(themes, id: \.id) { theme in
                    swatch(theme, picked: recipe.theme.id == theme.id) { editorState.setTitleTheme(theme) }
                }
                recordingSwatch(recording)
            }
        }
    }

    private func swatch(_ theme: TitleTheme, picked: Bool, pick: @escaping () -> Void) -> some View {
        Button(action: pick) {
            TitleThemeSwatch(theme: theme, picked: picked)
        }
        .buttonStyle(.plain)
        .panelHelp(theme.name)
        .playtestControl("Theme \(theme.name)", detail: "Title")
        .accessibilityLabel("Theme \(theme.name)")
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    /// From Recording: the clip's own colours, sampled when pressed.
    private func recordingSwatch(_ sampled: TitleTheme?) -> some View {
        Button { editorState.setTitleThemeFromRecording() } label: {
            if let sampled {
                TitleThemeSwatch(theme: sampled, picked: true)
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator))
                    .overlay(Image(systemName: "film").font(.system(size: 9)).foregroundStyle(.secondary))
                    .frame(width: TitleThemeSwatch.side, height: TitleThemeSwatch.side)
            }
        }
        .buttonStyle(.plain)
        .panelHelp("From Recording")
        .playtestControl("Theme From Recording", detail: "Title")
        .accessibilityLabel("Theme From Recording")
    }

    // MARK: Font pair

    private func fonts(_ recipe: TitleRecipe) -> some View {
        let pairs = [recipe.originalFonts] + TitleFontPair.curated
        return VideoKit.DropdownRow(
            label: "Font Pair", value: recipe.fonts.name,
            choices: .picking(pairs, current: recipe.fonts, title: \.name) { editorState.setTitleFonts($0) })
        .panelReadout(recipe.fonts.name)
        .playtestField("Title Font Pair")
        .panelHelp("A face for the headline and one for the words under it.")
    }

    // MARK: Energy

    private func energy(_ recipe: TitleRecipe) -> some View {
        PanelFieldRow("Energy") {
            SegmentedControl("Energy", selection: recipe.energy,
                             options: TitleEnergy.allCases.map { .init($0, $0.title) },
                             size: .small) { editorState.setTitleEnergy($0) }
        }
        .panelReadout(recipe.energy.title)
        .playtestField("Title Energy")
        .panelHelp("How fast and how hard the whole title moves.")
    }

    // MARK: Intensity

    private func intensity(_ recipe: TitleRecipe) -> some View {
        let range = TitleRecipe.intensityRange
        let shown = editorState.titleIntensityPreview ?? recipe.intensity
        let state = editorState
        return PanelFieldRow("Intensity") {
            HStack(spacing: 6) {
                Slider(value: Binding(get: { shown / 100 },
                                      set: { state.previewTitleIntensity(($0 * 100).rounded()) }),
                       in: (range.lowerBound / 100)...(range.upperBound / 100)) { editing in
                    if !editing, let percent = state.titleIntensityPreview { state.setTitleIntensity(percent) }
                }
                .controlSize(.small)
                .frame(minWidth: PanelSliderRow.trackMinimum)
                .playtestControl("Slider", detail: "Intensity")
                SliderReadout(typing: .percent, label: "Intensity", value: CGFloat(shown / 100),
                              isMixed: false,
                              range: CGFloat(range.lowerBound / 100)...CGFloat(range.upperBound / 100),
                              identity: state.titleInHandID) { value in
                    state.setTitleIntensity(Double(value * 100).rounded())
                }
            }
        }
        .playtestField("Intensity")
        .panelHelp("Blur, distance, grain and glow together.")
    }

    // MARK: Background

    private func background(_ recipe: TitleRecipe) -> some View {
        let kinds = TitleBackgroundKind.allCases.filter { $0 != .glass || editorState.titleCanBeGlass }
        let value = recipe.showsBackground ? (recipe.background?.title ?? "None") : "None"
        var choices: [VideoKit.Choice] = [
            .item("None", isOn: !recipe.showsBackground) { editorState.setTitleBackgroundShown(false) },
        ]
        choices += kinds.map { kind in
            .item(kind.title, isOn: recipe.showsBackground && recipe.background == kind) {
                editorState.setTitleBackground(kind)
            }
        }
        return VideoKit.DropdownRow(label: "Background", value: value, choices: choices)
            .panelReadout(value)
            .playtestField("Title Background")
            .panelHelp("What is behind the words, or nothing.")
    }

    // MARK: Sounds

    /// A soft whoosh as the words come in and a tick as each small accent
    /// lands, as a bar of sound under the title. Off until turned on.
    private func sounds(_ recipe: TitleRecipe) -> some View {
        let on = recipe.playsSounds
        return PanelFieldRow("Sounds") {
            Toggle("Sounds", isOn: Binding(get: { on }, set: { editorState.setTitleSounds($0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .playtestControl("Title Sounds", detail: on ? "on" : "off")
                .accessibilityLabel("Title Sounds")
        }
        .panelReadout(on ? "On" : "Off")
        .playtestField("Title Sounds")
        .panelHelp("A soft whoosh as the words come in, and a tick as each accent lands.")
    }

    // MARK: Part

    private func part() -> some View {
        let parts = editorState.titlePartsInHand
        let inHand = editorState.titlePartInHand?.index
        let value = parts.first { $0.index == inHand }?.name ?? "Whole Title"
        var choices: [VideoKit.Choice] = [
            .item("Whole Title", isOn: inHand == nil) { editorState.pickWholeTitle() },
            .divider,
        ]
        choices += parts.map { part in
            .item(part.name, isOn: part.index == inHand) { editorState.pickTitlePart(part.index) }
        }
        return VideoKit.DropdownRow(label: "Part", value: value, choices: choices)
            .panelReadout(value)
            .playtestField("Title Part")
            .panelHelp("Pick one part to change how it comes in, holds and goes off.")
    }
}

/// A theme as a small square: its background, its accent in the corner, and
/// "Aa" in its headline colour.
struct TitleThemeSwatch: View {
    let theme: TitleTheme
    let picked: Bool

    static let side: CGFloat = 17

    var body: some View {
        let ground = theme.backgrounds.map { Color(hex: $0) }
        RoundedRectangle(cornerRadius: 5)
            .fill(LinearGradient(colors: ground.count > 1 ? ground : ground + ground,
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(alignment: .bottomTrailing) {
                Circle().fill(Color(hex: theme.accent)).frame(width: 5, height: 5).padding(2)
            }
            .overlay {
                Text("Aa").font(.system(size: 7, weight: .bold)).foregroundStyle(Color(hex: theme.primary))
            }
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.separator, lineWidth: 0.5))
            .padding(2)
            .overlay(RoundedRectangle(cornerRadius: 7)
                .strokeBorder(picked ? Color.accentColor : .clear, lineWidth: 2))
            .frame(width: Self.side + 4, height: Self.side + 4)
            .contentShape(Rectangle())
    }
}

/// **Part**: one part of the picked title, its in, its hold and its out, each
/// a named behaviour with a few knobs, and Replay
/// (`docs/design/video-titles-polish.md`, "What the person sees", step 5).
/// Its keys stay on the timeline and in Properties for anyone who wants to
/// hand-edit them; changing a behaviour here writes them again.
struct TitlePartInspector: View {
    @Environment(EditorState.self) private var editorState

    static let sectionHelp = "How this part comes in, what it does while the title holds, and how it goes off. "
        + "Its keys stay editable on the timeline."

    static let lengths = [150, 200, 250, 300, 400, 500, 600, 700, 800, 1_000, 1_200, 1_500]
    static let delays = [0, 50, 100, 150, 200, 250, 300, 400, 500, 600, 800]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let inHand = editorState.titlePartInHand,
               let recipe = editorState.titleRecipeInHand,
               recipe.design.parts.indices.contains(inHand.index) {
                let part = recipe.design.parts[inHand.index]
                build("In", part.in, id: inHand.piece.id) { change in
                    editorState.editTitlePart { change(&$0.in) }
                }
                hold(part.hold, id: inHand.piece.id)
                build("Out", part.out, id: inHand.piece.id) { change in
                    editorState.editTitlePart { change(&$0.out) }
                }
                Button("Replay") { editorState.replayTitle() }
                    .controlSize(.small)
                    .panelHelp("Plays the title's in again")
                    .playtestControl("Replay", detail: "Part")
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: In and out

    private func build(_ name: String, _ build: TitleBuild?, id: UUID,
                       edit: @escaping (@escaping (inout TitleBuild?) -> Void) -> Void) -> some View {
        let kinds: [TitleBuildKind?] = [nil] + TitleBuildKind.allCases.map(Optional.some)
        let value = build?.kind.title ?? "None"
        let arriving = name == "In"
        return VStack(alignment: .leading, spacing: 6) {
            VideoKit.DropdownRow(
                label: name, value: value,
                choices: .picking(kinds, current: build?.kind, title: { $0?.title ?? "None" }) { kind in
                    edit { Self.replace(&$0, with: kind, arriving: arriving) }
                })
            .panelReadout(value)
            .playtestField("Part \(name)")
            .panelHelp(arriving ? "How this part comes in." : "How this part goes off.")
            if let build {
                msField("Length", build.lengthMS, stops: Self.lengths, id: id, row: name) { ms in
                    edit { $0?.lengthMS = max(1, ms) }
                }
                msField(arriving ? "Delay" : "Early", build.delayMS, stops: Self.delays, id: id, row: name) { ms in
                    edit { $0?.delayMS = max(0, ms) }
                }
                if let amount = Self.amount(of: build.kind) {
                    amountField(amount, build.amount, id: id, row: name) { value in
                        edit { $0?.amount = value }
                    }
                }
                if Self.hasDirection(build.kind) {
                    direction(build.direction, row: name) { direction in edit { $0?.direction = direction } }
                }
                // Words can come in a piece at a time.
                if arriving, inHandIsText, Self.goesByPiece(build.kind) {
                    pieces(build, id: id, edit: edit)
                }
                if arriving {
                    CurveRow(current: build.curve, help: "How this part moves on its way in.", row: "Part In Curve") {
                        curve in edit { $0?.curve = curve }
                    }
                }
            }
        }
    }

    /// Whether the picked part is words, which can come in a piece at a time.
    private var inHandIsText: Bool { editorState.titlePartInHand?.piece.text != nil }

    /// Whether a kind of in can bring words in by line, word or letter.
    static func goesByPiece(_ kind: TitleBuildKind) -> Bool {
        switch kind {
        case .fade, .rise, .blurIn, .maskReveal, .trackIn, .typewriter: true
        case .swingIn, .flipUp, .flyInFromDepth, .tiltSettle: true
        case .scaleFrom, .wipe, .springPop, .drawOn, .frost: false
        }
    }

    static let staggers = [20, 30, 40, 50, 60, 80, 100, 120, 150, 200]

    /// By (Whole, Line, Word, Letter) and, once it goes by a piece, how far
    /// apart the pieces start.
    private func pieces(_ build: TitleBuild, id: UUID,
                        edit: @escaping (@escaping (inout TitleBuild?) -> Void) -> Void) -> some View {
        let unit = build.unit ?? build.kind.defaultUnit
        return VStack(alignment: .leading, spacing: 6) {
            VideoKit.DropdownRow(
                label: "By", value: unit.title,
                choices: .picking(TextRevealUnit.allCases, current: unit, title: \.title) { picked in
                    edit { $0?.unit = picked }
                })
            .panelReadout(unit.title)
            .playtestField("Part In By")
            .panelHelp("Whether the words come in whole, or a line, word or letter at a time.")
            if unit != .whole {
                let stagger = build.staggerMS ?? (build.kind == .typewriter ? 50 : unit.defaultStaggerMS)
                msField("Stagger", stagger, stops: Self.staggers, id: id, row: "In") { ms in
                    edit { $0?.staggerMS = max(0, ms) }
                }
            }
        }
    }

    /// A part's in or out turned into another kind, keeping its timing and
    /// direction; nil takes it off.
    static func replace(_ current: inout TitleBuild?, with kind: TitleBuildKind?, arriving: Bool) {
        guard let kind else {
            current = nil
            return
        }
        let was = current
        var fresh = arriving
            ? TitleBuild(kind, delayMS: was?.delayMS ?? 0, lengthMS: was?.lengthMS ?? 600)
            : TitleBuild.off(kind, delayMS: was?.delayMS ?? 0, lengthMS: was?.lengthMS ?? 250)
        fresh.direction = was?.direction ?? (kind == .wipe || kind == .drawOn ? .right : .up)
        // Words that came in a piece at a time keep coming in by that piece.
        if arriving, goesByPiece(kind), let was, goesByPiece(was.kind) {
            fresh.unit = was.unit
            fresh.staggerMS = was.staggerMS
        }
        current = fresh
    }

    // MARK: Hold

    private func hold(_ hold: TitleHold, id: UUID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VideoKit.DropdownRow(
                label: "Hold", value: Self.title(hold.kind),
                choices: .picking(TitleHoldKind.allCases, current: hold.kind, title: Self.title) { kind in
                    editorState.editTitlePart(replaying: false) { part in
                        part.hold.kind = kind
                        if part.hold.amount == 0, kind != .blink { part.hold.amount = kind == .drift ? 16 : 3 }
                    }
                })
            .panelReadout(Self.title(hold.kind))
            .playtestField("Part Hold")
            .panelHelp("What this part does while the title is up.")
            if hold.kind != .none, hold.kind != .blink {
                let amount = hold.kind == .drift ? Amount.distance : Amount.grow
                amountField(amount, hold.amount, id: id, row: "Hold") { value in
                    editorState.editTitlePart(replaying: false) { $0.hold.amount = value }
                }
                if hold.kind == .drift {
                    direction(hold.direction, row: "Hold") { direction in
                        editorState.editTitlePart(replaying: false) { $0.hold.direction = direction }
                    }
                }
            }
        }
    }

    private static func title(_ kind: TitleHoldKind) -> String {
        switch kind {
        case .none: "None"
        case .drift: "Drift"
        case .push: "Push"
        case .blink: "Blink"
        }
    }

    // MARK: Knobs

    enum Amount {
        case distance, blur, scale, grow, spread, angle, depth

        var label: String {
            switch self {
            case .distance: "Distance"
            case .blur: "Blur"
            case .scale: "Scale"
            case .grow: "Grow"
            case .spread: "Spread"
            case .angle: "Angle"
            case .depth: "Depth"
            }
        }

        var suffix: String {
            switch self {
            case .distance, .blur, .depth: DocumentUnit.word
            case .scale, .grow, .spread: "%"
            case .angle: "°"
            }
        }
    }

    static func amount(of kind: TitleBuildKind) -> Amount? {
        switch kind {
        case .rise: .distance
        case .blurIn: .blur
        case .scaleFrom, .springPop: .scale
        case .trackIn: .spread
        case .swingIn, .flipUp, .tiltSettle: .angle
        case .flyInFromDepth: .depth
        case .fade, .wipe, .drawOn, .frost, .maskReveal, .typewriter: nil
        }
    }

    static func hasDirection(_ kind: TitleBuildKind) -> Bool {
        kind == .rise || kind == .wipe || kind == .drawOn || kind == .maskReveal
            || kind == .swingIn || kind == .flipUp || kind == .flyInFromDepth
    }

    static func help(forTime label: String) -> String {
        switch label {
        case "Length": "How long it takes."
        case "Stagger": "How long after one piece starts the next one does."
        default: "How long after the title starts, or before it ends."
        }
    }

    private func msField(_ label: String, _ ms: Int, stops: [Int], id: UUID, row: String,
                         set: @escaping (Int) -> Void) -> some View {
        PanelNumberField(
            showing: .number("\(ms)"),
            label: label,
            identity: "\(id)-\(row)-\(label)",
            suffix: "ms",
            width: .flexible(least: 40),
            floor: 0,
            ceiling: 5_000,
            wholeNumbers: true,
            help: Self.help(forTime: label),
            look: .well,
            presets: .init(label: label, value: "\(ms) ms",
                           choices: .picking(Array(Set(stops + [ms])).sorted(), current: ms,
                                             title: { "\($0) ms" }) { set($0) }),
            land: { value in
                set(Int(value.rounded()))
                return nil
            })
        .frame(maxWidth: .infinity)
        .panelReadout("\(ms) ms")
        .playtestField("Part \(row) \(label)")
    }

    private func amountField(_ amount: Amount, _ value: Double, id: UUID, row: String,
                             set: @escaping (Double) -> Void) -> some View {
        let shown = Int(value.rounded())
        return PanelNumberField(
            showing: .number("\(shown)"),
            label: amount.label,
            identity: "\(id)-\(row)-amount",
            suffix: amount.suffix,
            width: .flexible(least: 40),
            floor: amount == .grow ? -50 : 0,
            ceiling: amount == .scale ? 300 : amount == .angle ? 180 : amount == .depth ? 3_000 : 400,
            wholeNumbers: true,
            help: "How far, how soft or how big.",
            look: .well,
            land: { typed in
                set(Double(typed))
                return nil
            })
        .frame(maxWidth: .infinity)
        .panelReadout("\(shown) \(amount.suffix)")
        .playtestField("Part \(row) \(amount.label)")
    }

    private func direction(_ direction: TitleDirection, row: String,
                           set: @escaping (TitleDirection) -> Void) -> some View {
        let title: (TitleDirection) -> String = { $0.rawValue.capitalized }
        return VideoKit.DropdownRow(
            label: "Direction", value: title(direction),
            choices: .picking(TitleDirection.allCases, current: direction, title: title) { set($0) })
        .panelReadout(title(direction))
        .playtestField("Part \(row) Direction")
    }
}
