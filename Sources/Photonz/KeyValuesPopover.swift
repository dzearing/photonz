import AppKit
import PhotonzCore
import SwiftUI

/// The picked keys' values: a popover above the key a click picked, one row
/// per value, name left and number right, with Reset at the foot (Next,
/// `next-key-values`; the placement contract's key overlay;
/// `docs/design/mocks/pages/video-animate.html`, THE KEY OVERLAY).
///
/// The transform values popover's kind (`TransformValuesPopover`): the tool
/// bar's own glass and corner, no stroke, the same row look. It hangs from the
/// key and never covers it, nor the curve and handles around it on an open
/// graph (`KeyValuesPlacement`), following it as the timeline scrolls. Drawn
/// over the whole window, so a key near the top of the timeline can put it
/// over the canvas's foot.
struct KeyValuesPopover: View {
    @Environment(EditorState.self) private var editorState

    /// What a walk and a screen reader know the popover by.
    static let name = "Key values"
    static let width: CGFloat = 196

    var body: some View {
        GeometryReader { proxy in
            let window = proxy.frame(in: .global)
            if editorState.showsKeyValues, let anchor = editorState.keyValuesAnchorFrame {
                let local = anchor.offsetBy(dx: -window.minX, dy: -window.minY)
                let bounds = CGRect(origin: .zero, size: proxy.size)
                // On an open graph it keeps off the curve and its handles.
                let clear = editorState.keyValuesClearLines.map {
                    $0.map { CGPoint(x: $0.x - window.minX, y: $0.y - window.minY) }
                }
                let place = { (popover: ViewDimensions) in
                    KeyValuesPlacement.frame(anchor: local,
                                             size: CGSize(width: popover.width, height: popover.height),
                                             in: bounds, clearOf: clear)
                }
                popover
                    .fixedSize()
                    .alignmentGuide(.leading) { -place($0).minX }
                    .alignmentGuide(.top) { -place($0).minY }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                        editorState.keyValuesPopoverFrame = $0
                    }
                    .onDisappear { editorState.keyValuesPopoverFrame = nil }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 4)),
                                            removal: .identity))
                    .modifier(KeyValuesClickAway())
            }
        }
        .transaction(value: editorState.showsKeyValues) { transaction in
            transaction.animation = editorState.showsKeyValues ? .easeOut(duration: 0.14) : nil
        }
        // A menu opening anywhere is another operation, as for the
        // transform values.
        .onReceive(NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)) { _ in
            editorState.dropKeyValues()
        }
    }

    private var popover: some View {
        let rows = editorState.keyValueRows
        let corner = Experiments.shared.toolBar.cornerRadius
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(rows, id: \.motionID) { row in
                KeyValueRowView(row: row, anchor: editorState.keyValuesAnchor?.ref)
            }
            Rectangle()
                .fill(.separator)
                .frame(height: 1)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
            Button("Reset") { editorState.resetKeyValues() }
                .buttonStyle(KeyValuesButtonStyle())
                .disabled(!editorState.canResetKeyValues)
                .help("Reset to the default")
                .playtestControl("Reset", detail: Self.name)
        }
        .padding(10)
        .frame(width: Self.width)
        // The tool bar's own glass and corner, and like the bar no stroke.
        .glassEffect(.regular, in: .rect(cornerRadius: corner))
        .contentShape(.rect(cornerRadius: corner))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.name)
        .playtestField(Self.name)
    }

    /// What each row of the popover says: its name and what its box shows.
    /// A point is two rows, X and Y. The walk reads these.
    static func lines(_ rows: [KeyValueRow]) -> [(name: String, showing: NumberBox.Showing)] {
        rows.flatMap { row -> [(name: String, showing: NumberBox.Showing)] in
            switch row.value {
            case let .number(number):
                return [(row.title, .number(SpaceRowText.text(number)))]
            case let .point(x, y):
                return [("\(row.title) X", x.map { .number(SpaceRowText.text($0)) } ?? .standIn(MixedValue.text)),
                        ("\(row.title) Y", y.map { .number(SpaceRowText.text($0)) } ?? .standIn(MixedValue.text))]
            case let .color(hex):
                return [(row.title, .number(String(hex.dropFirst())))]
            case .mixed:
                return [(row.title, .standIn(MixedValue.text))]
            }
        }
    }
}

/// One value of the picked keys: a number box in the transform values' row
/// look, two for a point, a swatch and its hex for a colour.
private struct KeyValueRowView: View {
    @Environment(EditorState.self) private var editorState
    let row: KeyValueRow
    let anchor: KeyRef?

    var body: some View {
        let lines = KeyValuesPopover.lines([row])
        switch row.property {
        case .color, .shadowColor, .glowColor, .borderColor:
            KeyColorRow(row: row, showing: lines.first?.showing ?? .nothing, anchor: anchor)
        default:
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                let axis = lines.count == 2 ? index : nil
                PanelNumberField(
                    showing: line.showing,
                    label: "Key value \(line.name)",
                    identity: [AnyHashable(row.motionID), AnyHashable(anchor)],
                    leading: line.name,
                    suffix: row.unit,
                    width: .flexible(least: 56),
                    playtest: ("Key value \(line.name)", KeyValuesPopover.name),
                    spell: { SpaceRowText.text(Double($0)) },
                    look: .row,
                    sums: true,
                    escape: { editorState.dropKeyValues() },
                    land: { value in
                        let edit: KeyValueEdit = switch axis {
                        case 0: .x(Double(value))
                        case 1: .y(Double(value))
                        default: .number(Double(value))
                        }
                        let now = editorState.setKeyValue(motionID: row.motionID, edit)
                        return now.map { KeyValuesPopover.lines([KeyValueRow(row, value: $0)]) }?
                            .dropFirst(axis ?? 0).first?.showing
                    })
                    .playtestField("Key value \(line.name)")
            }
        }
    }
}

/// A colour key: its name, a swatch of it and its hex, typed.
private struct KeyColorRow: View {
    @Environment(EditorState.self) private var editorState
    let row: KeyValueRow
    let showing: NumberBox.Showing
    let anchor: KeyRef?
    @State private var draft = ""
    @State private var picking = false
    @FocusState private var focused: Bool

    private var hex: String? {
        if case let .color(hex) = row.value { return hex }
        return nil
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(row.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            // A click on the swatch opens the app's one colour picker.
            Button { picking = true } label: {
                RoundedRectangle(cornerRadius: 4)
                    .fill(swatch)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.primary.opacity(0.2), lineWidth: 1))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Pick a colour")
            .playtestControl("Swatch", detail: KeyValuesPopover.name)
            .popover(isPresented: $picking, arrowEdge: .bottom) {
                ColorPickerPopover(initialHex: hex ?? "#FFFFFF",
                                   recents: editorState.recentColors.colors) { picked in
                    editorState.setKeyValue(motionID: row.motionID, .color(picked))
                }
            }
            TextField("", text: $draft, prompt: Text(showing == .standIn(MixedValue.text) ? MixedValue.text : ""))
                .textFieldStyle(.plain)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .frame(width: 64)
                .focused($focused)
                .onSubmit(land)
                .onExitCommand {
                    draft = showing.text
                    editorState.dropKeyValues()
                }
                .accessibilityLabel("Key value \(row.title)")
        }
        .padding(.horizontal, 6)
        .frame(height: VideoKit.Metrics.controlSmall)
        .onChange(of: showing, initial: true) { _, now in
            if case .number(let text) = now { draft = text } else { draft = "" }
        }
        .onChange(of: focused) { _, isFocused in if !isFocused { land() } }
        .panelReadout(showing.text)
        .playtestField("Key value \(row.title)")
    }

    private var swatch: Color {
        guard case let .color(hex) = row.value, let rgba = RGBA(hex: hex) else { return .clear }
        return Color(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
    }

    private func land() {
        guard case .number(let shown) = showing, draft != shown, !draft.isEmpty else { return }
        editorState.setKeyValue(motionID: row.motionID, .color(draft))
    }
}

extension KeyValueRow {
    /// The same row reading something else: what a box hands back once a
    /// value has landed.
    init(_ row: KeyValueRow, value: KeyValueReading) {
        self.init(motionID: row.motionID, property: row.property, title: row.title, value: value)
    }
}

/// Reset: a text button on a soft plate the popover's width, the transform
/// values' own.
private struct KeyValuesButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity)
            .frame(height: VideoKit.Metrics.controlSmall)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(.primary.opacity(configuration.isPressed ? 0.16 : 0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

/// A press anywhere outside the popover closes it, before the press does
/// whatever it does there: a press on another key then opens it again over
/// that key.
private struct KeyValuesClickAway: ViewModifier {
    @Environment(EditorState.self) private var editorState
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown,
                                                                      .otherMouseDown]) { event in
                    MainActor.assumeIsolated { pressed(event) }
                    return event
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }

    @MainActor
    private func pressed(_ event: NSEvent) {
        // Only a press in the editor's own window: the colour picker the
        // swatch opens is a window of its own, and a press in it is not
        // elsewhere.
        guard let frame = editorState.keyValuesPopoverFrame, let window = event.window, window.isMainWindow,
              let view = window.contentView else { return }
        let inView = view.convert(event.locationInWindow, from: nil)
        let point = view.isFlipped ? inView : CGPoint(x: inView.x, y: view.bounds.height - inView.y)
        if !frame.insetBy(dx: -2, dy: -2).contains(point) { editorState.dropKeyValues() }
    }
}
