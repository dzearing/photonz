import AppKit
import PhotonzCore
import SwiftUI

extension EnvironmentValues {
    /// Whether the window being drawn opened as the New window: File > New,
    /// with `next-front-door` on. Read before the window's state has been
    /// seeded, so its very first frame is already the New window.
    @Entry var opensAsFrontDoor = false
}

/// The window File > New opens (Next, `next-front-door`): make an Image or a
/// Video, at a size you pick, and nothing else (the user, 2026-10-22: "have
/// Image or Video in the new dialog", "new should not have load image in it").
///
/// A window that holds no document, so no canvas, no tool bar and no panel:
/// the primary button in its title bar, the prompt bar, the two choices, and
/// the picked choice's sizes (and a length for a video). Opening is File >
/// Open and File > Open Recent; capturing is the capture keys. What it makes
/// opens in an editor window of its own, and this window closes on its own
/// once that one is up, so a window that already holds a document is never
/// replaced.
struct FrontDoorView: View {
    @Environment(EditorState.self) private var editorState
    @State private var kind: FrontDoorKind = .default
    @State private var image = SizeChoice(kind: .image)
    @State private var video = SizeChoice(kind: .video)
    @State private var seconds: Double = BlankVideo.defaultLengthSeconds
    @FocusState private var customFieldFocused: Bool

    /// The window's width, the mock's `min(640px, 92%)`.
    static let width: CGFloat = 640

    /// One kind's size: a preset's id or `customID`, the width and height
    /// showing, and the last size typed by hand (`CustomChoice`).
    struct SizeChoice {
        var selection: String
        var width: Double
        var height: Double
        var custom = CustomChoice<CGSize>()

        static let customID = "custom"

        init(kind: FrontDoorKind) {
            let first = kind.sizes.first { $0.size == kind.defaultSize }
            selection = first?.id ?? Self.customID
            width = Double(kind.defaultSize.width)
            height = Double(kind.defaultSize.height)
        }

        var size: CGSize { CGSize(width: width, height: height) }
        var isCustom: Bool { selection == Self.customID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar
            VStack(alignment: .leading, spacing: 18) {
                promptBar
                kinds
                sizes
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(FrontDoorWindowSizer())
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            if !isAvailable(kind), let first = available.first { kind = first }
        }
    }

    // MARK: Title bar

    /// The mock's title bar: the app's name and "· New" beside the traffic
    /// lights, and the primary button at the trailing end, "right where
    /// document actions always sit". It names what it will make.
    private var titleBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Text(AppInfo.name).fontWeight(.semibold)
                Text("\u{00B7} \(FrontDoor.subtitle)").foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
            // Clear of the traffic lights.
            .padding(.leading, 78)
            Spacer(minLength: 12)
            Button(action: create) {
                Label(kind.createTitle, systemImage: "plus")
            }
            .buttonStyle(FrontDoorProminentButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(!canCreate)
            .playtestControl(kind.createTitle, detail: "New window")
        }
        .controlSize(.small)
        .padding(.trailing, 14)
        // Level with the traffic lights, which sit in the middle of the first
        // 32 points of a window with a hidden title bar.
        .frame(height: 32)
        .padding(.bottom, 8)
    }

    // MARK: Prompt bar

    /// The mock's prompt bar for the agent. Drawn, and dimmed until the agent
    /// that answers it lands: a field that took typing and then did nothing
    /// would be worse than one that says it is not ready.
    private var promptBar: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 9)
                .fill(LinearGradient(colors: [Color(red: 0.43, green: 0.55, blue: 1),
                                              Color(red: 0.77, green: 0.42, blue: 1)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
            Text(FrontDoor.promptPlaceholder)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(FrontDoor.createTitle) {}
                .buttonStyle(FrontDoorProminentButtonStyle(large: true))
                .disabled(true)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
        .help(FrontDoor.promptTip)
        .accessibilityElement(children: .combine)
    }

    // MARK: Image or Video

    private var available: [FrontDoorKind] { FrontDoorKind.allCases.filter(isAvailable) }

    private var kinds: some View {
        HStack(spacing: 12) {
            ForEach(available, id: \.self) { tile($0) }
        }
    }

    private func tile(_ choice: FrontDoorKind) -> some View {
        let isPicked = kind == choice
        return Button {
            kind = choice
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Self.tint(choice).opacity(0.16))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: choice.symbol)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Self.tint(choice))
                    }
                Text(choice.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isPicked ? Color.accentColor : Color(nsColor: .separatorColor),
                                  lineWidth: isPicked ? 1.5 : 1)
            }
            .shadow(color: isPicked ? Color.accentColor.opacity(0.35) : .clear, radius: 8, y: 3)
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        // A double click is pick and go, the way a preset in Photoshop's New
        // Document is: the first click of it has already picked the choice.
        .simultaneousGesture(TapGesture(count: 2).onEnded { kind = choice; create() })
        .help(choice.createTitle)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
        .animation(.easeOut(duration: 0.15), value: isPicked)
        .playtestControl(choice.title, detail: "New window choice")
    }

    /// The choice's colour, the mock's own: the image coral and the video
    /// cyan. Drawn only as a glyph on a wash of itself, so it reads in light
    /// and dark alike.
    private static func tint(_ kind: FrontDoorKind) -> Color {
        switch kind {
        case .image: Color(red: 1, green: 0.49, blue: 0.37)
        case .video: Color(red: 0.07, green: 0.63, blue: 0.79)
        }
    }

    // MARK: Sizes

    private var choice: Binding<SizeChoice> {
        kind == .image ? $image : $video
    }

    @ViewBuilder private var sizes: some View {
        if isAvailable(kind) {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel(FrontDoor.sizeHeader)
                VStack(spacing: 0) {
                    ForEach(kind.sizes) { preset in
                        sizeRow(id: preset.id, title: preset.title,
                                detail: FrontDoor.dimensions(preset.size)) {
                            choice.wrappedValue.width = Double(preset.size.width)
                            choice.wrappedValue.height = Double(preset.size.height)
                        }
                        Divider().opacity(0.4)
                    }
                    sizeRow(id: SizeChoice.customID, title: FrontDoor.customTitle,
                            detail: choice.wrappedValue.isCustom
                                ? nil : choice.wrappedValue.custom.kept.map(FrontDoor.dimensions)) {
                        if let size = choice.wrappedValue.custom.kept {
                            choice.wrappedValue.width = Double(size.width)
                            choice.wrappedValue.height = Double(size.height)
                        }
                    }
                }
                .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 10))
                if choice.wrappedValue.isCustom {
                    HStack(spacing: 8) {
                        field("Width", choice.width).focused($customFieldFocused)
                        Text(verbatim: "\u{00D7}").foregroundStyle(.secondary)
                        field("Height", choice.height)
                        Text("px").font(.callout).foregroundStyle(.secondary)
                    }
                    // Picking Custom puts the cursor in Width, so the next
                    // thing typed is the size rather than a hunt for the field.
                    .onAppear { customFieldFocused = true }
                }
                if kind.hasLength {
                    HStack(spacing: 8) {
                        Text(FrontDoor.lengthTitle).font(.callout)
                        Spacer(minLength: 12)
                        field(FrontDoor.lengthTitle, $seconds, fraction: 0...1)
                        Text("sec").font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
    }

    /// One selectable size. The whole row is the target, not a small circle,
    /// and the picked one carries the accent so the choice reads at a glance.
    /// A double click picks it and makes it.
    private func sizeRow(id: String, title: String, detail: String?,
                         onPick: @escaping () -> Void) -> some View {
        let isSelected = choice.wrappedValue.selection == id
        let pick = {
            let current = choice.wrappedValue
            choice.wrappedValue.custom.keep(current.size, isOwn: current.isCustom)
            choice.wrappedValue.selection = id
            onPick()
        }
        return Button(action: pick) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                Text(title)
                    .font(.callout)
                Spacer(minLength: 12)
                if let detail {
                    Text(detail)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            guard id != SizeChoice.customID else { return }
            pick()
            create()
        })
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .playtestControl(title, detail: detail ?? "")
    }

    private func field(_ label: String, _ value: Binding<Double>,
                       fraction: ClosedRange<Int> = 0...0) -> some View {
        TextField(label, value: value,
                  format: .number.precision(.fractionLength(fraction)).grouping(.never))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .labelsHidden()
            .frame(width: 76)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }

    // MARK: Doing it

    /// Whether the app this release ships can make `kind`.
    private func isAvailable(_ kind: FrontDoorKind) -> Bool {
        switch kind {
        case .image: Experiments.shared.blankCanvasEnabled
        case .video: Experiments.shared.blankVideoEnabled
        }
    }

    private var canCreate: Bool {
        guard isAvailable(kind), kind.isValid(choice.wrappedValue.size) else { return false }
        return !kind.hasLength || BlankVideo.isValidLength(seconds: seconds)
    }

    /// The primary button: make the picked kind at the picked size, in an
    /// editor window of its own that starts in the kind's mode. This window
    /// closes once that one is up (`BlankCanvas.destination`).
    private func create() {
        guard canCreate else { return }
        let size = choice.wrappedValue.size
        switch kind {
        case .image: editorState.createBlankCanvas(size: size)
        case .video: editorState.createBlankVideo(size: size, lengthMS: BlankVideo.lengthMS(seconds: seconds))
        }
    }
}

/// The New window's primary button and the prompt bar's Create: white on the
/// accent, whatever the window is doing.
///
/// Not the system's prominent style: in a window that is not key it drops its
/// fill and keeps its white label, which on the light window is white on
/// white (seen in `front-door-1-design-ui-picked-sc.png`, 2026-10-09). White
/// on the accent is the system's own pairing, so nothing here alters a
/// system colour. A dimmed one is the plain grey a dimmed control is, with
/// its label in the secondary colour, since white on a faded accent is faint.
private struct FrontDoorProminentButtonStyle: ButtonStyle {
    var large = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 13 : 12, weight: .medium))
            .foregroundStyle(isEnabled ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .padding(.horizontal, large ? 14 : 9)
            .frame(height: large ? 30 : 22)
            .background(isEnabled
                            ? AnyShapeStyle(Color.accentColor.opacity(configuration.isPressed ? 0.8 : 1))
                            : AnyShapeStyle(.quaternary),
                        in: .rect(cornerRadius: large ? 9 : 6))
            .contentShape(.rect(cornerRadius: large ? 9 : 6))
    }
}

/// Fits the window round the New window: the mock's width, and as tall as
/// what it holds, centred on the screen the first time.
private struct FrontDoorWindowSizer: NSViewRepresentable {
    func makeNSView(context: Context) -> SizerView { SizerView() }
    func updateNSView(_ view: SizerView, context: Context) {
        DispatchQueue.main.async { view.fit() }
    }

    final class SizerView: NSView {
        private var centred = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            fit()
        }

        override func layout() {
            super.layout()
            DispatchQueue.main.async { [weak self] in self?.fit() }
        }

        /// The window's content to the size of the front door, which this
        /// view is the background of.
        func fit() {
            guard let window, bounds.height > 0 else { return }
            let wanted = CGSize(width: max(FrontDoorView.width, window.contentMinSize.width),
                                height: max(bounds.height.rounded(), window.contentMinSize.height))
            let content = window.contentRect(forFrameRect: window.frame).size
            if abs(content.width - wanted.width) > 0.5 || abs(content.height - wanted.height) > 0.5 {
                let top = window.frame.maxY
                window.setContentSize(wanted)
                // Grow and shrink from the top, the way a window does.
                if centred {
                    var frame = window.frame
                    frame.origin.y = top - frame.height
                    window.setFrame(frame, display: true)
                }
            }
            if !centred {
                centred = true
                window.center()
            }
        }
    }
}
