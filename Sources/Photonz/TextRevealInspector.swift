import PhotonzCore
import SwiftUI

/// **Reveal**: how the picked text's words come in, a line, a word or a letter
/// at a time (`TextReveal.swift`, the Reveal section of
/// `docs/design/mocks/pages/video-motion.html`).
///
/// The mock's rows, in its order: the preset, the stagger between pieces, how
/// long each piece takes and the whole reveal's length, then the curve. Two
/// rows the mock does not draw sit with them, because a polished reveal needs
/// both: what the words split into (By) and which piece goes first (Order).
/// The mock's preset is a segmented control of three; here there are six, and
/// a list of more than three is a dropdown (UX-PATTERNS §4).
struct TextRevealInspector: View {
    @Environment(EditorState.self) private var editorState

    /// The mock's closing note, in its words, behind the header's question
    /// mark: it is longer than a panel line may be (UX-PATTERNS §4).
    static let sectionHelp = "One number drives the whole cascade. Each layer inherits the same reveal, "
        + "offset by a fixed step."

    static let stagger = [0, 20, 30, 40, 50, 60, 80, 100, 150, 200, 300]
    static let each = [200, 300, 400, 500, 600, 800, 1_000, 1_500]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let layer = editorState.textRevealLayer {
                let reveal = layer.text?.reveal
                preset(reveal)
                if let reveal {
                    unit(reveal)
                    staggerRow(reveal, id: layer.id)
                    timing(reveal, id: layer.id)
                    order(reveal)
                    CurveRow(current: reveal.curve, help: "How each piece moves on its way in.") {
                        editorState.setTextRevealCurve($0)
                    }
                    .disabled(!reveal.style.hasLength)
                }
            }
        }
        .padding(.horizontal, EditorChromeLayout.panelEdgeInset)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func preset(_ reveal: TextReveal?) -> some View {
        let styles: [TextRevealStyle?] = [nil] + TextRevealStyle.allCases.map(Optional.some)
        let value = reveal?.style.title ?? "None"
        return VideoKit.DropdownRow(
            label: "Preset", value: value,
            choices: .picking(styles, current: reveal?.style, title: { $0?.title ?? "None" }) {
                editorState.setTextRevealStyle($0)
            })
        .panelReadout(value)
        .playtestField("Reveal Preset")
        .panelHelp("How the words come in.")
    }

    private func unit(_ reveal: TextReveal) -> some View {
        VideoKit.DropdownRow(
            label: "By", value: reveal.unit.title,
            choices: .picking(TextRevealUnit.allCases, current: reveal.unit, title: \.title) {
                editorState.setTextRevealUnit($0)
            })
        .panelReadout(reveal.unit.title)
        .playtestField("Reveal By")
        .panelHelp("What the words come in as: all at once, a line, a word or a letter at a time.")
    }

    /// The mock's stepper: any number of milliseconds typed, with the usual
    /// offsets on the list at its end.
    private func staggerRow(_ reveal: TextReveal, id: UUID) -> some View {
        let words = "\(reveal.staggerMS) ms"
        return PanelNumberField(
            showing: .number("\(reveal.staggerMS)"),
            label: "Stagger",
            identity: id,
            suffix: "ms",
            width: .flexible(least: 40),
            floor: 0,
            ceiling: 2_000,
            wholeNumbers: true,
            help: "How long after one piece starts the next one does.",
            look: .well,
            presets: .init(label: "Stagger", value: words,
                           choices: .picking(Self.stops(Self.stagger, now: reveal.staggerMS),
                                             current: reveal.staggerMS, title: { "\($0) ms" }) {
                               editorState.setTextRevealStagger($0)
                           }),
            land: { value in
                editorState.setTextRevealStagger(Int(value.rounded()))
                return nil
            })
        .frame(maxWidth: .infinity)
        .panelReadout(words)
        .playtestField("Reveal Stagger")
    }

    /// Each piece's length beside the whole reveal's, as the mock pairs them.
    private func timing(_ reveal: TextReveal, id: UUID) -> some View {
        let total = editorState.textRevealTotalMS.map(Self.seconds) ?? ""
        return HStack(spacing: 8) {
            PanelNumberField(
                showing: reveal.style.hasLength ? .number("\(reveal.lengthMS)") : .standIn("None"),
                label: "Each",
                identity: id,
                suffix: "ms",
                width: .flexible(least: 36),
                floor: 1,
                ceiling: 5_000,
                wholeNumbers: true,
                help: "How long each piece takes to arrive.",
                look: .well,
                presets: .init(label: "Each", value: "\(reveal.lengthMS) ms",
                               choices: .picking(Self.stops(Self.each, now: reveal.lengthMS),
                                                 current: reveal.lengthMS, title: { "\($0) ms" }) {
                                   editorState.setTextRevealLength($0)
                               }),
                land: { value in
                    editorState.setTextRevealLength(Int(value.rounded()))
                    return nil
                })
            .frame(maxWidth: .infinity)
            .disabled(!reveal.style.hasLength)
            .playtestField("Reveal Each")
            HStack(spacing: 6) {
                Text("Total").font(.caption).foregroundStyle(.secondary)
                VideoKit.ValueFace(value: total)
                    .panelReadout(total)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .playtestField("Reveal Total")
        }
    }

    private func order(_ reveal: TextReveal) -> some View {
        VideoKit.DropdownRow(
            label: "Order", value: reveal.order.title,
            choices: .picking(TextRevealOrder.allCases, current: reveal.order, title: \.title) {
                editorState.setTextRevealOrder($0)
            })
        .panelReadout(reveal.order.title)
        .playtestField("Reveal Order")
        .panelHelp("Which piece comes in first.")
    }

    /// The stops a list offers, with the value now among them.
    private static func stops(_ stops: [Int], now: Int) -> [Int] {
        Array(Set(stops + [now])).sorted()
    }

    static func seconds(_ ms: Int) -> String {
        String(format: "%.2fs", Double(ms) / 1000)
    }
}
