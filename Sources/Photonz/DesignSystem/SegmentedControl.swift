import AppKit
import PhotonzCore
import SwiftUI

/// **The segmented control**: a small set of exclusive choices, all of them on
/// screen at once (`docs/design/mocks/pages/comp-segmented.html`).
///
/// It is the system's own control, `NSSegmentedControl`, so macOS draws all of
/// it: its track, its picked segment, its contrast and its motion. The user, 2026-09-29:
/// "what happened to using the native liquid glass segmented control." Before
/// that this file drew a rail and slid a pane of glass along it, and the
/// drawing is what produced an unreadable white-on-white history filter and a
/// thumb that overshot its rail. Nothing here draws the control any more.
///
/// Why AppKit's control rather than SwiftUI's `Picker(.segmented)`, which is
/// the same control underneath: measured on 2026-09-29, the picker never
/// stretches (a picker framed 280pt wide stays 87pt), so a panel row cannot
/// have its equal columns; and it resets AppKit's style to `.automatic` on
/// every update, leaving the look to macOS. The first View | Edit switch was
/// a bare control on `.automatic` and was seen as two loose buttons in the
/// title bar. Here the style is pinned to `.rounded`: one control, the same
/// everywhere, title bar included (filmed there on 2026-09-29).
///
/// What macOS 26 draws, filmed the same day: one continuous track; in an
/// active window the picked segment is filled with the accent colour, in an
/// inactive one it is a grey plate; a new pick switches at once rather than
/// sliding.
///
/// * **Sizes** are the system's control sizes. With no size given it takes
///   the size around it (`.controlSize(.small)` in a dense panel row).
/// * **Forms.** `.fill` takes its container's width, in equal columns when
///   the widest word fits an equal share and each word's own width otherwise;
///   `.natural` is equal segments as wide as the widest word.
/// * **It never wraps.** When the words would have to be cut short the
///   control becomes a dropdown holding the same choices. Pictures never do.
/// * **Disabled** is the system's: one option that cannot be picked is
///   dimmed by AppKit and says why in its tooltip; the whole control dims
///   under `.disabled`.
/// * **Motion** is the system's. A pick made inside another animation (View |
///   Edit under `.viewEditMode`) cannot disturb it: SwiftUI's transactions do
///   not reach an AppKit control.
///
/// With the Next release's `next-designed-segmented` switch off, which is
/// always the case in Current, this is the SwiftUI segmented picker exactly as
/// each caller had it, so Current does not change.
struct SegmentedControl<Value: Hashable>: View {
    /// One choice.
    struct Option {
        var value: Value
        /// The word on the segment, and the name accessibility and a walk use
        /// for it even when the segment shows a picture instead.
        var title: String
        /// A picture in front of the word, or in place of it when the control
        /// `showsTitles` is false. Its `accessibilityDescription` is the name
        /// the segment answers to, so build it named (`SegmentedControl.symbol`).
        var image: NSImage?
        /// What resting on it says. A picture segment without one says its title.
        var help: String?
        /// The key that picks it, printed quieter in its tooltip.
        var key: String?
        /// Set when this one cannot be picked right now: the segment keeps its
        /// place, dimmed, and its tooltip says this.
        var disabledReason: String?

        init(_ value: Value, _ title: String, image: NSImage? = nil, help: String? = nil,
             key: String? = nil, disabledReason: String? = nil) {
            self.value = value
            self.title = title
            self.image = image
            self.help = help
            self.key = key
            self.disabledReason = disabledReason
        }
    }

    /// The system's control sizes.
    enum Size {
        case small, regular, large

        var controlSize: NSControl.ControlSize {
            switch self {
            case .small: .small
            case .regular: .regular
            case .large: .large
            }
        }
    }

    enum Form {
        /// The container's width, in equal segments.
        case fill
        /// As wide as the system draws it.
        case natural
    }

    let label: String
    let options: [Option]
    /// Nil lights nothing: the picked things disagree, or nothing is picked.
    let selection: Value?
    /// Nil takes the control size around it.
    var size: Size?
    var form: Form = .fill
    var showsTitles = true
    /// What the whole control's system help tag says in Current, for a caller
    /// that had one (`segmentToolTips`' fallback).
    var systemHelp: String?
    /// Tooltips under the segments rather than over them, for a control at the
    /// very top of a window.
    var tipsBelow = false
    /// False for a control that was already drawn before the switch existed
    /// (the Library's scope, the video panel's rows): it is this control with
    /// the switch off too, because the SwiftUI picker is not what it replaced.
    var fallsBackToSystem = true
    let pick: (Value) -> Void

    init(_ label: String, selection: Value?, options: [Option], size: Size? = nil,
         form: Form = .fill, showsTitles: Bool = true,
         systemHelp: String? = nil, tipsBelow: Bool = false, fallsBackToSystem: Bool = true,
         pick: @escaping (Value) -> Void) {
        self.label = label
        self.selection = selection
        self.options = options
        self.size = size
        self.form = form
        self.showsTitles = showsTitles
        self.systemHelp = systemHelp
        self.tipsBelow = tipsBelow
        self.fallsBackToSystem = fallsBackToSystem
        self.pick = pick
    }

    init(_ label: String, selection: Binding<Value>, options: [Option], size: Size? = nil,
         form: Form = .fill, showsTitles: Bool = true,
         systemHelp: String? = nil, tipsBelow: Bool = false) {
        self.init(label, selection: selection.wrappedValue, options: options, size: size,
                  form: form, showsTitles: showsTitles,
                  systemHelp: systemHelp, tipsBelow: tipsBelow) { selection.wrappedValue = $0 }
    }

    /// A symbol as a segment's picture, carrying the option's name: a segment
    /// answers to its picture's description (a SwiftUI `.accessibilityLabel`
    /// does not reach it), which is what a screen reader says and what a walk
    /// presses it by.
    static func symbol(_ name: String, named title: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: title)
        image?.accessibilityDescription = title
        return image
    }

    var body: some View {
        if Experiments.shared.designedSegmentedEnabled || !fallsBackToSystem {
            if showsTitles {
                // Every word whole on one row, or a dropdown of the same
                // choices: a bar whose words do not fit is the wrong control
                // for the room, and a cut-short one reads as broken.
                ViewThatFits(in: .horizontal) {
                    segments
                    collapsed
                }
            } else {
                segments
            }
        } else {
            swiftUIPicker
        }
    }

    private var segments: some View {
        SystemSegments(label: label, options: options, selection: selection,
                       size: size?.controlSize, form: form, showsTitles: showsTitles, pick: pick)
            .overlay { tips }
    }

    /// One tooltip per segment, laid over it: an `NSSegmentedControl` takes
    /// its tooltips from the system, and the app's own tooltip is what every
    /// other control shows. An even row of anchors is a row of equal
    /// segments, which is every control that has tips today (pictures, and
    /// the title bar's two words); a `.fill` row squeezed into each word's own
    /// width would place them a little off. The anchors take no clicks.
    @ViewBuilder private var tips: some View {
        let texts = options.map(tip(for:))
        if texts.contains(where: { $0 != nil }) {
            HStack(spacing: 0) {
                ForEach(options.indices, id: \.self) { index in
                    if let text = texts[index] {
                        Color.clear
                            .toolTip(text, key: options[index].disabledReason == nil ? options[index].key : nil,
                                     below: tipsBelow)
                    } else {
                        Color.clear
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// What resting on a segment says: why it cannot be picked, its own
    /// help, or for a picture (or a segment with a key) its name.
    private func tip(for option: Option) -> String? {
        option.disabledReason ?? option.help
            ?? (showsTitles && option.key == nil ? nil : option.title)
    }

    /// Short of room: the same choices in a dropdown, the picked one ticked.
    private var collapsed: some View {
        VideoKit.Dropdown(
            label: label,
            value: options.first { $0.value == selection }?.title ?? "",
            size: size == .large ? .regular : .small,
            choices: options.map { option in
                .item(option.title, isOn: option.value == selection,
                      isEnabled: option.disabledReason == nil) { pick(option.value) }
            })
    }

    /// Current's control: the SwiftUI picker, built the way every caller built
    /// it before this type existed.
    @ViewBuilder private var swiftUIPicker: some View {
        let picker = Picker(label, selection: Binding<Value?>(
            get: { selection },
            set: { if let value = $0 { pick(value) } })) {
            ForEach(options.indices, id: \.self) { index in
                swiftUILabel(options[index]).tag(Value?.some(options[index].value))
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

    @ViewBuilder private func swiftUILabel(_ option: Option) -> some View {
        if let image = option.image, !showsTitles {
            Image(nsImage: image)
        } else {
            Text(option.title)
        }
    }
}

// MARK: - The system control

/// `NSSegmentedControl`, one capsule (`.rounded`), one pick (`.selectOne`).
private struct SystemSegments<Value: Hashable>: NSViewRepresentable {
    let label: String
    let options: [SegmentedControl<Value>.Option]
    let selection: Value?
    /// Nil takes the environment's.
    let size: NSControl.ControlSize?
    let form: SegmentedControl<Value>.Form
    let showsTitles: Bool
    let pick: (Value) -> Void

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        // Pinned, never `.automatic`, so macOS never picks another look for
        // it (the first View | Edit switch, on automatic, was seen separated).
        control.segmentStyle = .rounded
        control.trackingMode = .selectOne
        control.segmentDistribution = .fillEqually
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.values = options.map(\.value)
        context.coordinator.pick = pick

        let controlSize = size ?? Self.appKitSize(context.environment.controlSize)
        if control.controlSize != controlSize { control.controlSize = controlSize }
        // The words follow the size on their own check: SwiftUI hands an
        // environment's control size to the control before this runs, so a
        // font set only when the size changed was never set at all, and every
        // small row drew its words at the regular 13pt (found 2026-09-30).
        let fontSize = NSFont.systemFontSize(for: controlSize)
        if control.font?.pointSize != fontSize { control.font = .systemFont(ofSize: fontSize) }
        control.isEnabled = context.environment.isEnabled
        control.setAccessibilityLabel(label)

        if control.segmentCount != options.count { control.segmentCount = options.count }
        for (index, option) in options.enumerated() {
            let word = showsTitles || option.image == nil ? option.title : ""
            if control.label(forSegment: index) != word { control.setLabel(word, forSegment: index) }
            if control.image(forSegment: index) !== option.image {
                control.setImage(option.image, forSegment: index)
            }
            control.setEnabled(option.disabledReason == nil, forSegment: index)
        }
        let picked = options.firstIndex { $0.value == selection } ?? -1
        if control.selectedSegment != picked { control.selectedSegment = picked }
    }

    /// `.natural` is equal segments as wide as the widest word. `.fill` asks
    /// for the least room that shows every word whole, and takes whatever
    /// room it is given: equal columns when the widest word fits an equal
    /// share, else each segment keeps its own width and the rest is shared
    /// out (a panel row of Before the cut | Across it | After it), so no word
    /// is cut while there is room for all of them.
    ///
    /// Short of the system's own widths, the words keep their width with a
    /// tighter margin before the control gives up and becomes a dropdown
    /// (`SegmentRoom`), and that tight width is what it asks for when asked
    /// what it would like, so the dropdown only arrives when a word really
    /// would be cut.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView control: NSSegmentedControl,
                      context: Context) -> CGSize? {
        // Every measure below is of the system's own widths, so any tight
        // widths from the last pass come off first.
        Self.setWidths(nil, of: control)
        let equal = Self.width(of: control, laidOut: .fillEqually)
        guard form == .fill else {
            if control.segmentDistribution != .fillEqually { control.segmentDistribution = .fillEqually }
            return equal
        }
        let fit = Self.width(of: control, laidOut: .fit)
        let words = wordWidths(of: control)
        let tight = words.map { Self.tightWidth(of: control, words: $0) } ?? fit.width
        guard let width = proposal.width, width.isFinite else {
            return CGSize(width: tight, height: equal.height)
        }
        switch SegmentRoom.layout(available: width, equal: equal.width, systemFit: fit.width, tight: tight) {
        case .equal:
            if control.segmentDistribution != .fillEqually { control.segmentDistribution = .fillEqually }
        case .proportional:
            if control.segmentDistribution != .fillProportionally { control.segmentDistribution = .fillProportionally }
        case .tight, .tooNarrow:
            if let words {
                let chrome = tight - SegmentRoom.tightWidth(words: words, chrome: 0)
                if control.segmentDistribution != .fit { control.segmentDistribution = .fit }
                Self.setWidths(SegmentRoom.tightWidths(words: words, available: width, chrome: chrome),
                               of: control)
            } else if control.segmentDistribution != .fillProportionally {
                control.segmentDistribution = .fillProportionally
            }
        }
        return CGSize(width: width, height: equal.height)
    }

    /// How wide each segment's word is in the control's own font, or nil for
    /// a control with pictures on it, which keeps the system's widths.
    private func wordWidths(of control: NSSegmentedControl) -> [CGFloat]? {
        guard showsTitles, options.allSatisfy({ $0.image == nil }), !options.isEmpty else { return nil }
        let font = control.font ?? .systemFont(ofSize: NSFont.systemFontSize(for: control.controlSize))
        return options.map { ceil(($0.title as NSString).size(withAttributes: [.font: font]).width) }
    }

    /// The width the control asks for with each word given a tight margin,
    /// its edge included, as AppKit measures it.
    private static func tightWidth(of control: NSSegmentedControl, words: [CGFloat]) -> CGFloat {
        let was = control.segmentDistribution
        control.segmentDistribution = .fit
        setWidths(words.map { $0 + SegmentRoom.tightMargin }, of: control)
        let width = control.intrinsicContentSize.width
        setWidths(nil, of: control)
        control.segmentDistribution = was
        return width
    }

    /// Gives each segment its own width, or hands them all back to the system.
    private static func setWidths(_ widths: [CGFloat]?, of control: NSSegmentedControl) {
        for index in 0..<control.segmentCount {
            let width = widths.map { $0.indices.contains(index) ? $0[index] : 0 } ?? 0
            if control.width(forSegment: index) != width { control.setWidth(width, forSegment: index) }
        }
    }

    /// How big the control asks to be when its segments are laid out one way.
    private static func width(of control: NSSegmentedControl,
                              laidOut distribution: NSSegmentedControl.Distribution) -> CGSize {
        let was = control.segmentDistribution
        guard was != distribution else { return control.intrinsicContentSize }
        control.segmentDistribution = distribution
        defer { control.segmentDistribution = was }
        return control.intrinsicContentSize
    }

    func makeCoordinator() -> Coordinator { Coordinator(pick: pick) }

    private static func appKitSize(_ size: ControlSize) -> NSControl.ControlSize {
        switch size {
        case .mini: .mini
        case .small: .small
        case .large: .large
        case .extraLarge: .extraLarge
        default: .regular
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var values: [Value] = []
        var pick: (Value) -> Void

        init(pick: @escaping (Value) -> Void) { self.pick = pick }

        @objc func changed(_ control: NSSegmentedControl) {
            guard values.indices.contains(control.selectedSegment) else { return }
            pick(values[control.selectedSegment])
        }
    }
}
