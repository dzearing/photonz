import AppKit
// The gallery script (`Scripts/segmented-gallery.swift`) compiles this file
// with the morph's own source beside it rather than as a module.
#if canImport(PhotonzCore)
import PhotonzCore
#endif
import SwiftUI

/// **The segmented control**: a small set of exclusive choices, all of them on
/// screen at once (`docs/design/mocks/pages/comp-segmented.html`,
/// `shared/components/segmented.css`).
///
/// The only segmented control in the app. Before it there were three: the
/// system's (`Picker` with `.segmented`, about forty of them across the panel,
/// the dialogs and the colour picker), a bare `NSSegmentedControl` for View |
/// Edit in the title bar, and a drawn one the video panel kept to itself.
/// The user turned down the title bar's on 2026-09-28 because it was not the
/// design system's, and the others were not either. `SegmentedControlUsageTests`
/// fails the build on a segmented control made any other way.
///
/// What the component page asks for, and where it is done here:
///
/// * **Anatomy.** A recessed capsule rail, darker than what it sits on, with a
///   hairline and a soft inner shadow, 2pt of padding, 2pt between segments;
///   capsule segments; ONE thumb under the picked segment, a lighter pane of
///   Liquid Glass carrying fill, hairline, a lit top line and lift together.
///   The user, 2026-09-29: "the thumb should be lighter than the rail", of the
///   old plate that matched its track, "I can barely see the thumb".
/// * **Sizes.** 24, 28 (the default, and the only size the mocks' panels use)
///   and 32. The size sets the height and the type; the width always comes from
///   the words.
/// * **Forms.** `.fill` takes its container's width in equal columns, the form
///   inside a panel or a popover; `.natural` hugs its words. Pictures instead
///   of words are square segments, each named by its tooltip.
/// * **It never wraps.** When the words would have to be cut short, the
///   control becomes a dropdown holding the same choices. Pictures never do.
/// * **States.** Hovering an unpicked segment lifts its ink and lays a faint
///   glass behind it; pressing shrinks it to 97%; one option that cannot be
///   picked keeps its place, dimmed, and says why in its tooltip; the whole
///   control dims under `.disabled`. One tab stop, arrows move the pick and
///   stop at the ends, and the focus ring sits round the plate.
/// * **Changing the value.** The thumb MOVES as liquid glass: it stretches
///   over the slot it left and the slot it is going to, squashed a little,
///   then lets go, runs a few points past and settles (`SegmentThumbMorph`,
///   the page's 420ms). It never leaves the rail, and a second choice
///   mid-flight carries on from where it is. Grab the thumb and drag it and it
///   follows the pointer, landing on the nearest segment when let go. Under
///   Reduce Motion it cross-fades instead; under Increase Contrast or Reduce
///   Transparency it is an opaque lighter plate with a firmer edge.
///
/// With the Next release's `next-designed-segmented` switch off, which is
/// always the case in Current, this is the system's segmented picker exactly as
/// each caller had it, so Current does not change.
struct SegmentedControl<Value: Hashable>: View {
    /// One choice.
    struct Option {
        var value: Value
        /// The word on the segment, and the name accessibility and a walk use
        /// for it even when the segment shows a picture instead.
        var title: String
        /// A picture in front of the word, or in place of it when the control
        /// `showsTitles` is false.
        var image: Image?
        /// What resting on it says. A picture segment without one says its title.
        var help: String?
        /// The key that picks it, printed quieter in its tooltip.
        var key: String?
        /// Set when this one cannot be picked right now: the segment keeps its
        /// place, dimmed, and its tooltip says this.
        var disabledReason: String?

        init(_ value: Value, _ title: String, image: Image? = nil, help: String? = nil,
             key: String? = nil, disabledReason: String? = nil) {
            self.value = value
            self.title = title
            self.image = image
            self.help = help
            self.key = key
            self.disabledReason = disabledReason
        }
    }

    /// `.seg.sm`, `.seg`, `.seg.lg`.
    enum Size {
        case small, regular, large

        var height: CGFloat {
            switch self {
            case .small: 24
            case .regular: 28
            case .large: 32
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .small: 11
            case .regular: 11.5
            case .large: 12.5
            }
        }

        /// Either side of a segment's words (`--gap-sm`, `--s3`, `--s4`).
        var padding: CGFloat {
            switch self {
            case .small: 8
            case .regular: 12
            case .large: 16
            }
        }
    }

    enum Form {
        /// Equal columns across the container (`.seg.fill`).
        case fill
        /// Each segment as wide as its words (`.seg`).
        case natural
    }

    /// What the picked segment wears. `.accent` is the history bar's filter
    /// (`history.css`), the one place the mocks light the plate in the accent.
    enum PlateStyle {
        case raised, accent
    }

    let label: String
    let options: [Option]
    /// Nil lights nothing: the picked things disagree, or nothing is picked.
    let selection: Value?
    var size: Size = .regular
    var form: Form = .fill
    var showsTitles = true
    var plateStyle: PlateStyle = .raised
    /// What the whole control's system help tag says with the designed control
    /// off, for a caller that had one (`segmentToolTips`' fallback).
    var systemHelp: String?
    /// Tooltips under the segments rather than over them, for a control at the
    /// very top of a window.
    var tipsBelow = false
    /// False for a control that was already drawn before the switch existed
    /// (the Library's scope, the video panel's rows): it stays drawn with the
    /// switch off too, because the system control is the thing it replaced.
    var fallsBackToSystem = true
    let pick: (Value) -> Void

    init(_ label: String, selection: Value?, options: [Option], size: Size = .regular,
         form: Form = .fill, showsTitles: Bool = true, plateStyle: PlateStyle = .raised,
         systemHelp: String? = nil, tipsBelow: Bool = false, fallsBackToSystem: Bool = true,
         pick: @escaping (Value) -> Void) {
        self.label = label
        self.selection = selection
        self.options = options
        self.size = size
        self.form = form
        self.showsTitles = showsTitles
        self.plateStyle = plateStyle
        self.systemHelp = systemHelp
        self.tipsBelow = tipsBelow
        self.fallsBackToSystem = fallsBackToSystem
        self.pick = pick
    }

    init(_ label: String, selection: Binding<Value>, options: [Option], size: Size = .regular,
         form: Form = .fill, showsTitles: Bool = true, plateStyle: PlateStyle = .raised,
         systemHelp: String? = nil, tipsBelow: Bool = false) {
        self.init(label, selection: selection.wrappedValue, options: options, size: size,
                  form: form, showsTitles: showsTitles, plateStyle: plateStyle,
                  systemHelp: systemHelp, tipsBelow: tipsBelow) { selection.wrappedValue = $0 }
    }

    var body: some View {
        if Experiments.shared.designedSegmentedEnabled || !fallsBackToSystem {
            DesignedSegments(label: label, options: options, selection: selection, size: size,
                             form: form, showsTitles: showsTitles, plateStyle: plateStyle,
                             tipsBelow: tipsBelow, pick: pick)
        } else {
            systemPicker
        }
    }

    /// Current's control: the system picker, built the way every caller built
    /// it before this type existed.
    @ViewBuilder private var systemPicker: some View {
        let picker = Picker(label, selection: Binding<Value?>(
            get: { selection },
            set: { if let value = $0 { pick(value) } })) {
            ForEach(options.indices, id: \.self) { index in
                systemLabel(options[index]).tag(Value?.some(options[index].value))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        if let systemHelp {
            picker.segmentToolTips(options.map { $0.help ?? $0.title }, fallback: systemHelp)
        } else {
            picker
        }
    }

    @ViewBuilder private func systemLabel(_ option: Option) -> some View {
        if let image = option.image, !showsTitles {
            image
        } else {
            Text(option.title)
        }
    }
}

// MARK: - The drawn control

/// The row of segments, the space a thumb, a slot and a drag are measured in.
private let segmentedRowSpace = "segmented-row"

/// Where every segment is, handed up to the one thumb that draws the picked
/// one (and, in the gallery, a morph from another).
private struct SegmentBoxesKey: PreferenceKey {
    static let defaultValue: [Int: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { first, _ in first }
    }
}

/// The drawn control. Internal rather than private so
/// `Scripts/segmented-gallery.swift` can draw each state beside the mock.
struct DesignedSegments<Value: Hashable>: View {
    typealias Option = SegmentedControl<Value>.Option

    let label: String
    let options: [Option]
    let selection: Value?
    let size: SegmentedControl<Value>.Size
    let form: SegmentedControl<Value>.Form
    let showsTitles: Bool
    let plateStyle: SegmentedControl<Value>.PlateStyle
    let tipsBelow: Bool
    let pick: (Value) -> Void
    /// For the gallery only: draw this segment hovered, and the focus ring
    /// on, without a pointer or a keyboard.
    var shownHovered: Int?
    var shownFocused = false
    /// For the gallery only: draw the thumb this far into a morph from this
    /// segment to the picked one, so a filmstrip of the move can be drawn.
    var shownMorph: (from: Int, at: TimeInterval)?

    init(label: String, options: [Option], selection: Value?, size: SegmentedControl<Value>.Size,
         form: SegmentedControl<Value>.Form, showsTitles: Bool,
         plateStyle: SegmentedControl<Value>.PlateStyle, tipsBelow: Bool,
         shownHovered: Int? = nil, shownFocused: Bool = false,
         shownMorph: (from: Int, at: TimeInterval)? = nil, pick: @escaping (Value) -> Void) {
        self.label = label
        self.options = options
        self.selection = selection
        self.size = size
        self.form = form
        self.showsTitles = showsTitles
        self.plateStyle = plateStyle
        self.tipsBelow = tipsBelow
        self.shownHovered = shownHovered
        self.shownFocused = shownFocused
        self.shownMorph = shownMorph
        self.pick = pick
    }

    @State private var pointerOver: Int?
    private var hovered: Int? { pointerOver ?? shownHovered }
    @FocusState private var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    /// Every segment's box in the row, for a morph's start and a drag.
    @State private var slots: [Int: CGRect] = [:]
    /// A morph under way: where the thumb was when it began, and when.
    @State private var morphFrom: CGRect?
    @State private var morphStart: Date?
    /// A drag of the thumb under way: where its middle is, and how far from
    /// its middle the hand took hold.
    @State private var dragCenter: CGFloat?
    @State private var grabOffset: CGFloat = 0
    /// A drag that began off the thumb belongs to the segment it began on.
    @State private var dragIgnored = false
    @State private var rowWidth: CGFloat = 0
    @Namespace private var glass

    private typealias Palette = VideoKit.Palette

    var body: some View {
        Group {
            if showsTitles {
                // Every word whole on one row, or a dropdown of the same
                // choices: a bar whose words do not fit is the wrong control
                // for the room, and a wrapped or cut-short one reads as broken.
                ViewThatFits(in: .horizontal) {
                    bar
                    collapsed
                }
            } else {
                bar
            }
        }
        .opacity(isEnabled ? 1 : 0.42)
    }

    /// Either side of a segment's words. The fill form is the one a panel, a
    /// dock or a popover uses, and there the words only claim the least room
    /// they can stand in: the columns share out whatever the row has on top,
    /// which at a dock's usual width is more than the mock's
    /// `calc(var(--s2) - 1px)`. So a tight row (Arrangement with Mixed beside
    /// its word) keeps its bar of words, and only a row too narrow for the
    /// words themselves becomes a dropdown.
    private var wordPadding: CGFloat {
        form == .fill ? 3 : size.padding
    }

    private var pickedIndex: Int? { options.firstIndex { $0.value == selection } }

    private var bar: some View {
        SegmentColumnsLayout(form: form, spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                segment(index)
            }
        }
        .coordinateSpace(.named(segmentedRowSpace))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        .backgroundPreferenceValue(SegmentBoxesKey.self) { anchors in
            GeometryReader { proxy in
                if let pickedIndex, let anchor = anchors[pickedIndex] {
                    let row = 0...proxy.size.width
                    if let shownMorph, let from = anchors[shownMorph.from] {
                        placed(thumb, in: SegmentThumbMorph(from: proxy[from], to: proxy[anchor], row: row)
                            .frame(at: shownMorph.at))
                    } else {
                        thumbLayer(target: proxy[anchor], row: row)
                    }
                }
            }
        }
        .simultaneousGesture(thumbDrag)
        .onChange(of: pickedIndex) { old, _ in startMorph(leaving: old) }
        .task(id: morphStart) {
            // The morph's clock stops once it has landed, so a resting
            // control asks for no frames at all.
            guard morphStart != nil else { return }
            try? await Task.sleep(for: .seconds(SegmentThumbMorph.duration + 0.02))
            guard !Task.isCancelled else { return }
            morphStart = nil
            morphFrom = nil
        }
        .padding(2)
        .frame(height: size.height)
        .frame(minWidth: 0, maxWidth: form == .fill ? .infinity : nil)
        // The recessed rail: darker than what it sits on, pressed in.
        .background(Capsule().fill(Palette.segRail.shadow(
            .inner(color: Palette.segRailInset.color(scheme), radius: 1, y: 1))))
        .overlay(Capsule().strokeBorder(Palette.edgeLo).allowsHitTesting(false))
        .focusable(interactions: .activate)
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { step(-1) }
        .onKeyPress(.rightArrow) { step(1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    /// The thumb, drawn where the picked segment is, or where a morph or a
    /// drag has it right now.
    @ViewBuilder private func thumbLayer(target: CGRect, row: ClosedRange<CGFloat>) -> some View {
        if reduceMotion {
            // No travel: the old thumb fades out as the new one fades in.
            ZStack(alignment: .topLeading) {
                placed(thumb, in: target)
                    .id(pickedIndex)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.14), value: pickedIndex)
        } else {
            TimelineView(.animation(paused: morphStart == nil && dragCenter == nil)) { context in
                placed(thumb, in: thumbFrame(target: target, row: row, at: context.date))
            }
        }
    }

    private func placed(_ view: some View, in rect: CGRect) -> some View {
        view
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Where the thumb is at `date`: under the hand, part way through a
    /// morph, or at rest on `target`.
    private func thumbFrame(target: CGRect, row: ClosedRange<CGFloat>, at date: Date) -> CGRect {
        if let dragCenter, let ordered = orderedSlots {
            return SegmentThumbDrag.frame(centerX: dragCenter, slots: ordered, row: row)
        }
        if let morphFrom, let morphStart {
            return SegmentThumbMorph(from: morphFrom, to: target, row: row)
                .frame(at: date.timeIntervalSince(morphStart))
        }
        return target
    }

    /// The pick changed, by a click, a key, a drag or the document: the thumb
    /// sets off from wherever it is right now toward the new segment.
    private func startMorph(leaving old: Int?) {
        guard !reduceMotion, dragCenter == nil, let old, let oldSlot = slots[old] else { return }
        let now = Date()
        morphFrom = thumbFrame(target: oldSlot, row: 0...max(rowWidth, oldSlot.maxX), at: now)
        morphStart = now
    }

    private var orderedSlots: [CGRect]? {
        let ordered = options.indices.compactMap { slots[$0] }
        return ordered.count == options.count && !ordered.isEmpty ? ordered : nil
    }

    /// Take hold of the thumb and slide it: it follows the pointer along the
    /// rail, and on letting go lands on the segment under its middle. A drag
    /// that starts anywhere else is left to the segment it started on.
    private var thumbDrag: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(segmentedRowSpace))
            .onChanged { drag in
                if dragIgnored { return }
                if dragCenter == nil {
                    guard !reduceMotion, let pickedIndex, let slot = slots[pickedIndex],
                          slot.contains(drag.startLocation) else {
                        dragIgnored = true
                        return
                    }
                    grabOffset = drag.startLocation.x - slot.midX
                    morphStart = nil
                    morphFrom = nil
                }
                let lowest = slots[0]?.midX ?? 0
                let highest = slots[options.count - 1]?.midX ?? rowWidth
                dragCenter = min(max(drag.location.x - grabOffset, lowest), highest)
            }
            .onEnded { _ in
                defer { dragIgnored = false }
                guard let center = dragCenter, let ordered = orderedSlots else {
                    dragCenter = nil
                    return
                }
                let held = SegmentThumbDrag.frame(centerX: center, slots: ordered, row: 0...rowWidth)
                let landing = SegmentThumbDrag.landing(
                    centerX: center, slots: ordered,
                    available: options.map { $0.disabledReason == nil })
                morphFrom = held
                morphStart = Date()
                dragCenter = nil
                if let landing, landing != pickedIndex { pick(options[landing].value) }
            }
    }

    /// Lighter glass or the accent, on the thumb.
    private var solidThumb: Bool { reduceTransparency || contrast == .increased }

    /// The one thumb. It is a single view placed from the picked segment's
    /// box, so a change of value moves it rather than fading one out while
    /// another fades in.
    @ViewBuilder private var thumb: some View {
        switch plateStyle {
        case .raised where solidThumb:
            Capsule()
                .fill(Palette.segThumbSolid)
                .overlay(Capsule().strokeBorder(Palette.segThumbEdgeStrong))
                .background(ThumbLift())
                .overlay(focusRing)
        case .raised:
            // A pane of Liquid Glass lighter than the rail: the system's
            // glass under the mock's brighter fill, a hairline, and one lit
            // line along its top. The fill is what reads as "lighter" (and
            // what an offscreen render still shows); the glass is what makes
            // it a pane rather than paint as it moves.
            GlassEffectContainer {
                Capsule()
                    .fill(LinearGradient(colors: [Palette.segThumbHi.color(scheme),
                                                  Palette.segThumb.color(scheme)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().strokeBorder(Palette.segThumbEdge))
                    .overlay(TopLight(inset: 1, tone: Palette.segThumbSpec))
                    .glassEffect(.regular, in: .capsule)
                    .glassEffectID("thumb", in: glass)
            }
            .background(ThumbLift())
            .overlay(focusRing)
        case .accent:
            Capsule()
                .fill(Palette.accent)
                .background(ThumbLift())
                .overlay(focusRing)
        }
    }

    @ViewBuilder private var focusRing: some View {
        if isFocused || shownFocused {
            Capsule().stroke(Palette.accent.opacity(0.38), lineWidth: 3).padding(-1.5)
        }
    }

    private func segment(_ index: Int) -> some View {
        let option = options[index]
        let isOn = index == pickedIndex
        let isAvailable = option.disabledReason == nil
        let lit = isOn || (hovered == index && isAvailable)
        return Button {
            pick(option.value)
        } label: {
            HStack(spacing: 5) {
                if let image = option.image {
                    image
                        .font(.system(size: 13, weight: .medium))
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                if showsTitles || option.image == nil {
                    Text(option.title)
                        .font(.system(size: size.fontSize, weight: isOn ? .semibold : .medium))
                        .tracking(-0.03)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .foregroundStyle(ink(isOn: isOn, lit: lit))
            .padding(.horizontal, showsTitles || option.image == nil ? wordPadding : 0)
            .frame(minWidth: showsTitles ? 0 : size.height - 4, maxWidth: .infinity,
                   maxHeight: .infinity)
            .background {
                if hovered == index, !isOn, isAvailable {
                    Capsule().fill(Palette.glassHover)
                }
            }
            .anchorPreference(key: SegmentBoxesKey.self, value: .bounds) { [index: $0] }
            .contentShape(Capsule())
        }
        .buttonStyle(SegmentPressStyle())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(segmentedRowSpace)) } action: {
            slots[index] = $0
        }
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.42)
        .kitHover(option.title) { inside in
            if inside { pointerOver = index } else if pointerOver == index { pointerOver = nil }
        }
        .modifier(SegmentTip(text: tip(for: option),
                             key: option.disabledReason == nil ? option.key : nil,
                             below: tipsBelow))
        // Read the way a walk read a system segment: which one is on, then
        // what resting on it says.
        .playtestControl(option.title, detail: Self.walkDetail(isOn: isOn, title: option.title,
                                                               tip: tip(for: option)))
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// What resting on a segment says: why it cannot be picked, its own
    /// help, or for a picture (or a segment with a key) its name.
    private func tip(for option: Option) -> String? {
        option.disabledReason ?? option.help
            ?? (showsTitles && option.key == nil ? nil : option.title)
    }

    static func walkDetail(isOn: Bool, title: String, tip: String?) -> String {
        (isOn ? "already on \(title), " : "") + "tooltip " + (tip.map { "\"\($0)\"" } ?? "none")
    }

    private func ink(isOn: Bool, lit: Bool) -> AnyShapeStyle {
        if isOn, plateStyle == .accent { return AnyShapeStyle(Color.white) }
        return lit ? AnyShapeStyle(Palette.ink) : AnyShapeStyle(Palette.dim)
    }

    /// An arrow moves the pick one segment, stepping over any that cannot be
    /// picked, and stops at the ends: both ends are in view, so they are real
    /// ends, and a plate jumping across the track reads as the value reset.
    private func step(_ direction: Int) -> KeyPress.Result {
        var index = (pickedIndex ?? (direction > 0 ? -1 : options.count)) + direction
        while options.indices.contains(index) {
            if options[index].disabledReason == nil {
                pick(options[index].value)
                return .handled
            }
            index += direction
        }
        return .handled
    }

    /// Short of room: the same choices in a dropdown, the picked one ticked.
    private var collapsed: some View {
        VideoKit.Dropdown(
            label: label,
            value: pickedIndex.map { options[$0].title } ?? "",
            size: size == .large ? .regular : .small,
            choices: options.map { option in
                .item(option.title, isOn: option.value == selection,
                      isEnabled: option.disabledReason == nil) { pick(option.value) }
            })
    }
}

/// A capsule's lit top edge: one bright line along the top, inside the
/// hairline, fading out down the sides (`--ctl-gloss`, `--seg-thumb-spec`).
private struct TopLight: View {
    var inset: CGFloat
    var tone = VideoKit.Palette.edgeHi
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Capsule()
            .inset(by: inset)
            .strokeBorder(LinearGradient(stops: [.init(color: tone.color(scheme), location: 0),
                                                 .init(color: .clear, location: 0.3)],
                                         startPoint: .top, endPoint: .bottom),
                          lineWidth: 1)
    }
}

/// A pressed segment shrinks a little (`.seg>button:active`).
private struct SegmentPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.09), value: configuration.isPressed)
    }
}

/// A segment's tooltip, when it has something to say.
private struct SegmentTip: ViewModifier {
    let text: String?
    let key: String?
    let below: Bool

    func body(content: Content) -> some View {
        if let text {
            content.toolTip(text, key: key, below: below)
        } else {
            content
        }
    }
}

/// The thumb's lift (`--seg-thumb-lift`): a tight shadow and a soft one,
/// drawn only OUTSIDE the thumb. A shadow under a see-through pane would show
/// through it and darken the very thing that has to read lighter, which is
/// what a CSS box-shadow never does either.
private struct ThumbLift: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let ink = dark ? Color.black : VideoKit.rgb(0x121828)
        ZStack {
            Capsule().fill(ink.opacity(dark ? 0.30 : 0.10)).blur(radius: dark ? 5 : 4).offset(y: 3)
            Capsule().fill(ink.opacity(dark ? 0.45 : 0.14)).blur(radius: 1).offset(y: 1)
        }
        .mask {
            Rectangle()
                .padding(-14)
                .overlay(Capsule().blendMode(.destinationOut))
                .compositingGroup()
        }
        .allowsHitTesting(false)
    }
}

extension VideoKit.Palette {
    /// Behind a hovered segment: `color-mix(var(--glass) 55%, transparent)`.
    static let glassHover = VideoKit.Tone(light: VideoKit.rgb(0xFFFFFF, 0.74 * 0.55),
                                          dark: VideoKit.rgb(0x1A1D27, 0.72 * 0.55))
    /// The recessed rail (`--seg-rail`, `--seg-rail-inset`). Light is as dark
    /// as it is so the white thumb clears the user's 1.5:1 on the lightest
    /// thing it sits on, the white title bar (it measured 1.19:1 at the page's
    /// first .075, and 1.48:1 on the title bar at .19).
    static let segRail = VideoKit.Tone(light: VideoKit.rgb(0x121828, 0.22),
                                       dark: VideoKit.rgb(0x000000, 0.30))
    static let segRailInset = VideoKit.Tone(light: VideoKit.rgb(0x121828, 0.10),
                                            dark: VideoKit.rgb(0x000000, 0.35))
    /// The thumb, top to bottom (`--seg-thumb-hi`, `--seg-thumb`), its
    /// hairline and its lit top line.
    static let segThumbHi = VideoKit.Tone(light: VideoKit.rgb(0xFFFFFF, 1),
                                          dark: VideoKit.rgb(0xFFFFFF, 0.26))
    static let segThumb = VideoKit.Tone(light: VideoKit.rgb(0xFFFFFF, 0.96),
                                        dark: VideoKit.rgb(0xFFFFFF, 0.17))
    static let segThumbEdge = VideoKit.Tone(light: VideoKit.rgb(0x121828, 0.10),
                                            dark: VideoKit.rgb(0xFFFFFF, 0.14))
    static let segThumbSpec = VideoKit.Tone(light: VideoKit.rgb(0xFFFFFF, 1),
                                            dark: VideoKit.rgb(0xFFFFFF, 0.34))
    /// Under Increase Contrast or Reduce Transparency: an opaque plate, still
    /// lighter than the rail, with a firmer edge.
    static let segThumbSolid = VideoKit.Tone(light: VideoKit.rgb(0xFFFFFF),
                                             dark: VideoKit.rgb(0x4E5360))
    static let segThumbEdgeStrong = VideoKit.Tone(light: VideoKit.rgb(0x121828, 0.32),
                                                  dark: VideoKit.rgb(0xFFFFFF, 0.36))
}

// MARK: - Columns

/// The segments laid out on one row, never two.
///
/// `.natural`: each segment as wide as its words. `.fill`: equal columns when
/// the widest word fits an equal share, which is the component's fill form;
/// when it does not, each segment keeps its own width and the room left over
/// is shared out, so no label is cut while there is room for all of them
/// (the dock rule in `segmented.css`). Short of room altogether, every
/// segment gives up the same share of its width; the control's own
/// `ViewThatFits` turns into a dropdown before that shows.
struct SegmentColumnsLayout: Layout {
    enum Form { case fill, natural }

    var form: Form
    var spacing: CGFloat

    init<Value>(form: SegmentedControl<Value>.Form, spacing: CGFloat) {
        self.form = form == .fill ? .fill : .natural
        self.spacing = spacing
    }

    init(fills: Bool, spacing: CGFloat) {
        self.form = fills ? .fill : .natural
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let natural = naturalWidths(subviews)
        let gaps = spacing * CGFloat(max(0, subviews.count - 1))
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        let wanted = natural.reduce(0, +) + gaps
        let width: CGFloat
        switch form {
        case .fill: width = proposal.width ?? wanted
        case .natural: width = min(wanted, proposal.width ?? wanted)
        }
        return CGSize(width: width, height: proposal.height ?? height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sized = Self.widths(natural: naturalWidths(subviews), room: bounds.width,
                                spacing: spacing, fills: form == .fill)
        var x = bounds.minX
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: sized[index], height: bounds.height))
            x += sized[index] + spacing
        }
    }

    /// The width each segment gets, given their natural widths and the room.
    static func widths(natural: [CGFloat], room total: CGFloat, spacing: CGFloat,
                       fills: Bool) -> [CGFloat] {
        guard !natural.isEmpty else { return [] }
        let count = CGFloat(natural.count)
        let room = max(0, total - spacing * (count - 1))
        let sum = natural.reduce(0, +)
        if sum > room {
            return natural.map { sum > 0 ? $0 * room / sum : room / count }
        }
        guard fills else { return natural }
        let share = room / count
        if let widest = natural.max(), widest <= share {
            return Array(repeating: share, count: natural.count)
        }
        return natural.map { $0 + (room - sum) / count }
    }

    private func naturalWidths(_ subviews: Subviews) -> [CGFloat] {
        subviews.map { $0.sizeThatFits(.unspecified).width }
    }
}
