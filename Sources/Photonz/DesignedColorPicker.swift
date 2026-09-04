import AppKit
import PhotonzCore
import SwiftUI

/// The ONE color picker (Next, `next-color-picker`), drawn the way the design
/// study drew it: `docs/design/mocks/pages/color.html`.
///
/// Every place a color is chosen opens this, so choosing a color is the same
/// act whether it paints a shape's outline, a drop shadow, a backdrop, a
/// measurement or the tool in your hand. Top to bottom: what you are painting
/// and what it looked like before, a saturation and brightness square, a switch
/// between HSL, RGB and HEX with one slider per channel, one swatch row that
/// answers "near this one" four ways, and a reading of whether the color can be
/// read on white.
///
/// A color lands on a DELIBERATE action — a swatch, a slider let go of, a
/// number typed, a sample taken — never on a drag tick, so one blue is one undo
/// step and the recents list is not a transcript of the drag.
struct DesignedColorPicker: View {
    /// The editor this picker is changing something in. Held rather than read
    /// from the environment because a popover's content is built by whoever
    /// presents it, and every caller already has this.
    let editorState: EditorState
    /// What the picker opens on: a flat color, or the gradient already there.
    let initialPaint: Paint
    /// What this color paints, in the words the row beside it uses: "Fill",
    /// "Shadow", "Backdrop". It is the picker's title.
    let name: String
    /// The layer slot this paints, when it is one, so a saved color knows what
    /// it was saved for.
    var slot: ColorSlot?
    /// Whether the thing being painted can hold a transparency. Slots that
    /// cannot are not offered an opacity slider, because a number with nowhere
    /// to be kept is a lie.
    var supportsOpacity: Bool = false
    /// Whether this slot can hold a gradient. A slot that can only take a flat
    /// color — a drop shadow, a text block's ink — never sees the type row at
    /// all, because four tiles that quietly do nothing are worse than no tiles.
    var supportsGradient: Bool = false
    /// When this sits inside another popover beside sibling controls, drop the
    /// outer padding so it lines up with them.
    var embedded: Bool = false
    /// Closes the popover from the picker's own close button.
    var onClose: (() -> Void)?
    /// Called with the paint it landed on. A flat one still carries the hex it
    /// always did, in `hex`.
    let onCommit: (Paint) -> Void

    /// Which swatch row is showing. One row, four answers to the same
    /// question, rather than four grids stacked into a scroll.
    private enum Scope: String, CaseIterable, Identifiable {
        case shades, related, document, recent
        var id: String { rawValue }
        var title: String {
            switch self {
            case .shades: return "Shades"
            case .related: return "Related"
            case .document: return "Document"
            case .recent: return "Recent"
            }
        }
        var emptyNote: String {
            switch self {
            case .document: return "Nothing painted yet."
            case .recent: return "Nothing picked yet."
            default: return ""
            }
        }
    }

    @State private var color = PickerColor()
    @State private var openedOn = PickerColor()
    /// What is being painted, ramp and all. `color` is always one color OUT of
    /// this: the flat color while it is solid, the selected stop once it is a
    /// gradient, which is what makes the square below mean one thing.
    @State private var paint = Paint(hex: "#FFFFFF")
    @State private var stopIndex = 0
    /// The last paint this picker sent out. Painting the document sends the
    /// row's own reading of it straight back in, and reopening on that would
    /// hand the ramp's selection back to the first stop and forget the colour
    /// the header is comparing against — so an echo of our own change is
    /// ignored, and only a genuinely different paint reopens the picker.
    @State private var lastSent: Paint?
    @State private var format: ColorFormat = .hsl
    @AppStorage("colorPickerScope") private var scopeName = Scope.shades.rawValue
    @State private var hexField = ""
    @State private var isSampling = false
    @State private var isNaming = false
    @State private var styleName = ""
    @FocusState private var nameFocused: Bool

    private static let width: CGFloat = 268
    private static let squareHeight: CGFloat = 132

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if supportsGradient {
                PaintTypeRow(paint: paint, onPick: setKind)
                if paint.isGradient {
                    GradientGeometryRow(paint: $paint, stopIndex: $stopIndex,
                                        onCommit: commitGeometry)
                }
            }
            SaturationValueField(color: $color, onCommit: commit)
                .frame(height: Self.squareHeight)
            formatSwitch
            sliders
            if format == .hex { hexEntry }
            swatchRow
            footer
        }
        .frame(width: Self.width)
        .padding(embedded ? 0 : 14)
        .onAppear { start() }
        .onChange(of: initialPaint) { _, incoming in
            guard incoming != lastSent else { return }
            start(incoming)
        }
    }

    // MARK: - 1 · What you are painting, before and after

    private var header: some View {
        HStack(spacing: 8) {
            // The color you opened on sits beside the one you are making, so
            // you can tell whether you actually improved it.
            HStack(spacing: 0) {
                swatch(openedOn.rgba)
                Rectangle().fill(.primary.opacity(0.25)).frame(width: 1)
                swatch(color.rgba)
            }
            .frame(width: 44, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.2), lineWidth: 1))
            .help("Was \(openedOn.hex), now \(color.hex)")

            Text(headerTitle)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 0)

            Button(action: sampleFromScreen) {
                Image(systemName: "eyedropper")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 20)
            }
            .buttonStyle(.plain)
            .disabled(isSampling)
            .help("Sample a color from anywhere on screen")

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close")
            }
        }
    }

    private func swatch(_ rgba: RGBA) -> some View {
        // Over a checkerboard, so a color you made translucent looks
        // translucent rather than looking like a darker color.
        CheckerBoard()
            .overlay(Color(hex: rgba.hexStringWithAlpha))
    }

    // MARK: - 4 · Which numbers you are sliding

    private var formatSwitch: some View {
        Picker("Color format", selection: $format) {
            ForEach(ColorFormat.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .help("Which numbers you are sliding. HEX is also where a pasted color goes.")
    }

    // MARK: - 5 · One slider per channel

    private var sliders: some View {
        VStack(spacing: 6) {
            ForEach(channels, id: \.self) { channel in
                ChannelSlider(channel: channel,
                              color: $color,
                              track: trackColors(channel),
                              showsChecker: channel == .alpha,
                              onCommit: commit)
            }
        }
    }

    /// Opacity is only offered where the thing being painted can keep one.
    private var channels: [ColorChannel] {
        supportsOpacity ? format.channels : format.channels.filter { $0 != .alpha }
    }

    /// Every track shows what moving IT does, with the other channels held
    /// where they are. That is what makes a slider readable without a legend.
    private func trackColors(_ channel: ColorChannel) -> [Color] {
        let hsl = color.hsl
        switch channel {
        case .hue:
            return stride(from: 0, through: 360, by: 60).map {
                Color(hex: RGBA(hsl: HSL(hue: Double($0), saturation: 1, lightness: 0.5)).hexString)
            }
        case .saturation:
            return [0.0, 1.0].map {
                Color(hex: RGBA(hsl: HSL(hue: hsl.hue, saturation: $0, lightness: hsl.lightness)).hexString)
            }
        case .lightness:
            return [0.0, 0.5, 1.0].map {
                Color(hex: RGBA(hsl: HSL(hue: hsl.hue, saturation: hsl.saturation, lightness: $0)).hexString)
            }
        case .red, .green, .blue:
            var low = color.rgba, high = color.rgba
            switch channel {
            case .red: low.r = 0; high.r = 1
            case .green: low.g = 0; high.g = 1
            default: low.b = 0; high.b = 1
            }
            return [Color(hex: low.hexString), Color(hex: high.hexString)]
        case .alpha:
            return [Color(hex: color.hex).opacity(0), Color(hex: color.hex)]
        }
    }

    private var hexEntry: some View {
        HStack(spacing: 6) {
            Text("HEX").font(.caption2).foregroundStyle(.secondary).frame(width: 14, alignment: .leading)
            TextField("#RRGGBB", text: $hexField)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .controlSize(.small)
                .onSubmit(submitHex)
                .help("Takes #7C4DFF, rgb(124, 77, 255) or hsl(256 100% 65%)")
        }
    }

    private func submitHex() {
        guard let parsed = ColorText.parse(hexField) else {
            hexField = displayHex          // reject by snapping back
            return
        }
        color = color.adopting(supportsOpacity ? parsed : RGBA(r: parsed.r, g: parsed.g, b: parsed.b))
        commit()
    }

    // MARK: - 6 · One swatch row, four scopes

    private var swatchRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Swatches", selection: $scopeName) {
                ForEach(Scope.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            let swatches = scopeSwatches
            if swatches.isEmpty {
                Text(scope.emptyNote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(height: 22, alignment: .leading)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 22), spacing: 5)],
                          alignment: .leading, spacing: 5) {
                    ForEach(Array(swatches.enumerated()), id: \.offset) { index, hex in
                        Button { pick(hex) } label: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(hex: hex))
                                .frame(height: 22)
                                .overlay(RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(.primary.opacity(0.18), lineWidth: 1))
                                .overlay {
                                    if isCurrent(hex, at: index) {
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(Color.accentColor, lineWidth: 2)
                                            .padding(-2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(hex)
                    }
                }
                .frame(minHeight: 22, alignment: .top)
            }
        }
    }

    private var scope: Scope { Scope(rawValue: scopeName) ?? .shades }

    /// Which swatch says "you are here". On the shades row that is the step
    /// NEAREST the color, because a color is hardly ever sitting exactly on a
    /// derived shade and a row that marks nothing says nothing.
    private func isCurrent(_ hex: String, at index: Int) -> Bool {
        if scope == .shades { return ColorRamp.nearestShadeIndex(of: color.rgba) == index }
        return hex.caseInsensitiveCompare(color.hex) == .orderedSame
    }

    private var scopeSwatches: [String] {
        switch scope {
        case .shades: return ColorRamp.shades(of: color.rgba)
        case .related: return ColorRamp.related(to: color.rgba)
        case .document: return editorState.document?.colorsInUse ?? []
        // A picker opened in a brand new document has no recents to offer, so
        // the row falls back to the app's own eight rather than saying nothing.
        case .recent:
            let recents = editorState.recentColors.colors
            return recents.isEmpty ? AnnotationStyles.swatches : recents
        }
    }

    // MARK: - 7 · Can it be read, and can it be kept

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                contrastReadout
                Spacer(minLength: 4)
                if editorState.colorStylesEnabled && !isNaming {
                    Button {
                        styleName = ""
                        isNaming = true
                        nameFocused = true
                    } label: {
                        Label("Save style", systemImage: "swatchpalette")
                            .font(.caption)
                    }
                    .controlSize(.small)
                    .help("Keeps this color in the Library under a name")
                }
            }
            if isNaming { namingField }
        }
    }

    /// Whether the color can be read on a white page, which is the question
    /// being asked when a color is picked for text or a hairline. The figure
    /// for black is in the tip, so the other half is one hover away rather
    /// than a second row taking up the popover.
    private var contrastReadout: some View {
        let onWhite = ContrastReading(of: color.rgba, on: RGBA(r: 1, g: 1, b: 1))
        let onBlack = ContrastReading(of: color.rgba, on: RGBA(r: 0, g: 0, b: 0))
        return HStack(spacing: 5) {
            Text(onWhite.grade.title)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(gradeTint(onWhite.grade)))
            Text("\(onWhite.ratioText) on white")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .help("\(onWhite.ratioText) on white, \(onBlack.ratioText) on black. "
              + "4.5:1 is the bar for body text, 3:1 for large text.")
        .accessibilityLabel("Contrast \(onWhite.ratioText) on white, \(onWhite.grade.title)")
    }

    private func gradeTint(_ grade: ContrastReading.Grade) -> Color {
        switch grade {
        case .aaa, .aa: return .green.opacity(0.25)
        case .aaLarge: return .yellow.opacity(0.3)
        case .fail: return .red.opacity(0.25)
        }
    }

    private var namingField: some View {
        HStack(spacing: 6) {
            TextField("Style name", text: $styleName)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .controlSize(.small)
                .focused($nameFocused)
                .onSubmit(saveStyle)
                .nameFieldKeys(commit: saveStyle, revert: { isNaming = false })
            Button("Save", action: saveStyle)
                .controlSize(.small)
                .help("Saves this color under that name")
        }
    }

    private func saveStyle() {
        editorState.saveColorStyle(hex: displayHex, name: styleName, slot: slot)
        isNaming = false
    }

    // MARK: - State plumbing

    private var displayHex: String {
        supportsOpacity ? color.hexWithAlpha : color.hex
    }

    /// What the header says. While a gradient is being edited it names the stop
    /// the square is pointed at, because otherwise the biggest control in the
    /// picker would be quietly editing one colour out of several with nothing
    /// saying which.
    private var headerTitle: String {
        guard supportsGradient, paint.isGradient else { return name }
        return "\(name) · stop \(stopIndex + 1)"
    }

    private func start(_ incoming: Paint? = nil) {
        paint = incoming ?? initialPaint
        lastSent = nil
        stopIndex = 0
        let seed = PickerColor(hex: activeHex) ?? PickerColor(RGBA(r: 1, g: 1, b: 1))
        color = seed
        openedOn = seed
        hexField = supportsOpacity ? seed.hexWithAlpha : seed.hex
    }

    /// The one colour the square, the sliders and the swatch row are editing:
    /// the flat colour, or the stop that is selected.
    private var activeHex: String {
        guard paint.isGradient, paint.stops.indices.contains(stopIndex) else { return paint.hex }
        return paint.stops[stopIndex].hex
    }

    private func pick(_ hex: String) {
        guard let rgba = RGBA(hex: hex) else { return }
        color = color.adopting(supportsOpacity ? rgba : RGBA(r: rgba.r, g: rgba.g, b: rgba.b))
        commit()
    }

    private func commit() {
        hexField = displayHex
        if paint.isGradient, paint.stops.indices.contains(stopIndex) {
            paint.stops[stopIndex].hex = displayHex
        } else {
            paint.hex = displayHex
        }
        send()
    }

    /// A change to the ramp or the aim, already made in `paint`. The square
    /// follows whichever stop is now selected, so clicking a key hands the
    /// square over to that colour.
    private func commitGeometry() {
        if let seed = PickerColor(hex: activeHex) { color = seed }
        hexField = displayHex
        send()
    }

    /// Switching what kind of paint this is. Turning a flat colour into a
    /// gradient starts the ramp from the colour you already had, so the first
    /// thing you see is YOUR colour running somewhere; turning one back hands
    /// you that same flat colour rather than a stop out of the ramp.
    private func setKind(_ kind: Paint.Kind) {
        guard kind != paint.kind else { return }
        let wasFlat = !paint.isGradient
        if kind != .solid, wasFlat { paint.stops = Paint.seededStops(from: paint.hex) }
        paint.kind = kind
        stopIndex = min(max(stopIndex, 0), max(paint.stops.count - 1, 0))
        if let seed = PickerColor(hex: activeHex) { color = seed }
        hexField = displayHex
        send()
    }

    /// Hands the paint out, remembering it so the reading that comes straight
    /// back does not reopen the picker on top of the person using it.
    private func send() {
        lastSent = paint
        onCommit(paint)
    }

    /// The system screen sampler. Its own magnified loupe follows the pointer
    /// and is what shows the color live; the picker takes the answer when the
    /// click lands.
    private func sampleFromScreen() {
        isSampling = true
        NSColorSampler().show { picked in
            let hex = picked?.usingColorSpace(.sRGB).map {
                RGBA(r: Double($0.redComponent), g: Double($0.greenComponent),
                     b: Double($0.blueComponent)).hexString
            }
            Task { @MainActor in
                isSampling = false
                guard let hex else { return }
                pick(hex)
            }
        }
    }
}

// MARK: - 3 · The saturation and brightness square

/// Drag anywhere in it. Arrow keys nudge by one step, shift by five, which is
/// how a color already on screen gets matched without reading a number.
private struct SaturationValueField: View {
    @Binding var color: PickerColor
    let onCommit: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let x = color.saturation * size.width
            let y = (1 - color.value) * size.height
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: RGBA(hsv: HSV(hue: color.hue, saturation: 1, value: 1)).hexString))
                    .overlay(LinearGradient(colors: [.white, .white.opacity(0)],
                                            startPoint: .leading, endPoint: .trailing))
                    .overlay(LinearGradient(colors: [.black.opacity(0), .black],
                                            startPoint: .top, endPoint: .bottom))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.primary.opacity(0.18), lineWidth: 1))

                Circle()
                    .strokeBorder(.white, lineWidth: 2)
                    .background(Circle().fill(Color(hex: color.hex)))
                    .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 1).padding(-1))
                    .frame(width: 14, height: 14)
                    .offset(x: x - 7, y: y - 7)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { move($0.location, in: size) }
                    .onEnded { value in
                        move(value.location, in: size)
                        onCommit()
                    }
            )
        }
        .focusable()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow], action: nudge)
        .accessibilityLabel("Saturation and brightness")
        .accessibilityValue(color.hex)
    }

    private func move(_ point: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        color.saturation = min(max(point.x / size.width, 0), 1)
        color.value = min(max(1 - point.y / size.height, 0), 1)
    }

    private func nudge(_ press: KeyPress) -> KeyPress.Result {
        let step = press.modifiers.contains(.shift) ? 0.05 : 0.01
        switch press.key {
        case .leftArrow: color.saturation = max(color.saturation - step, 0)
        case .rightArrow: color.saturation = min(color.saturation + step, 1)
        case .upArrow: color.value = min(color.value + step, 1)
        case .downArrow: color.value = max(color.value - step, 0)
        default: return .ignored
        }
        onCommit()
        return .handled
    }
}

// MARK: - 5 · One channel, one track, one number

/// A track shaded to show what moving it does, with the number on the right
/// editable. Its own control rather than a `Slider`, because a plain slider
/// cannot carry the gradient that makes the track readable without a legend.
private struct ChannelSlider: View {
    let channel: ColorChannel
    @Binding var color: PickerColor
    let track: [Color]
    var showsChecker: Bool = false
    let onCommit: () -> Void

    @State private var field = ""
    @FocusState private var fieldFocused: Bool

    private static let knob: CGFloat = 13

    var body: some View {
        HStack(spacing: 7) {
            Text(channel.label)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 10, alignment: .leading)

            GeometryReader { proxy in
                let width = proxy.size.width
                let fraction = color.value(of: channel) / channel.maximum
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: track, startPoint: .leading, endPoint: .trailing))
                        .background(showsChecker ? AnyView(CheckerBoard().clipShape(Capsule())) : AnyView(Color.clear))
                        .frame(height: 8)
                        .overlay(Capsule().strokeBorder(.primary.opacity(0.15), lineWidth: 1))
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                        .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
                        .frame(width: Self.knob, height: Self.knob)
                        .offset(x: fraction * max(width - Self.knob, 0))
                        .allowsHitTesting(false)
                }
                .frame(height: Self.knob)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { move($0.location.x, width: width) }
                        .onEnded { value in
                            move(value.location.x, width: width)
                            onCommit()
                        }
                )
            }
            .frame(height: Self.knob)

            TextField("", text: $field)
                .textFieldStyle(.plain)
                .font(.caption.monospacedDigit())
                .multilineTextAlignment(.trailing)
                .frame(width: 34)
                .focused($fieldFocused)
                .onSubmit(submit)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(.quaternary.opacity(0.5)))
            Text(channel.unit)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 8, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(channel.title)
        .help(channel.title)
        .onAppear { field = text }
        .onChange(of: color) { _, _ in if !fieldFocused { field = text } }
        .onChange(of: fieldFocused) { _, focused in if !focused { field = text } }
    }

    private var text: String { String(Int(color.value(of: channel))) }

    private func move(_ x: CGFloat, width: CGFloat) {
        let usable = max(width - Self.knob, 1)
        let fraction = min(max((x - Self.knob / 2) / usable, 0), 1)
        color = color.setting(channel, to: fraction * channel.maximum)
    }

    private func submit() {
        guard let typed = Double(field.trimmingCharacters(in: .whitespaces)) else {
            field = text
            return
        }
        color = color.setting(channel, to: typed)
        field = text
        onCommit()
    }
}

/// The gray chequer under anything that can be see-through, so transparency
/// looks like transparency instead of like a paler color.
struct CheckerBoard: View {
    var square: CGFloat = 5

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = (row % 2 == 0) ? 0 : square
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: y, width: square, height: square)),
                                 with: .color(Color(white: 0.78)))
                    x += square * 2
                }
                y += square
                row += 1
            }
        }
        .allowsHitTesting(false)
    }
}
