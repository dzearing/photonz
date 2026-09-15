import PhotonzCore
import SwiftUI

/// "How big is this screen?" — the one question between a canvas and something
/// to build on (Next, `next-frames`).
///
/// It opens on the size you made last, so Return alone gives you another screen
/// the same size, and the frame lands in the middle of what you are looking at
/// rather than at some corner you would have to go find.
///
/// With `next-icon-frames` on there is a second group under the screens: the
/// sizes icons are drawn at. They are a row of small buttons rather than six
/// more rows of numbers, because six rows that each say the same word and a
/// different number is exactly the wall of numbers a short list exists to
/// avoid.
struct NewFrameDialog: View {
    @Environment(EditorState.self) private var editorState
    @Environment(\.dismiss) private var dismiss

    /// A preset's id, or `customID` while the size is typed by hand.
    @State private var selection = ""
    @State private var width: Double = 0
    @State private var height: Double = 0
    @FocusState private var customFieldFocused: Bool

    private static let customID = "custom"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Frame")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(FramePreset.screens) { preset in
                    row(id: preset.id, title: preset.title,
                        detail: FramePreset.sizeText(preset.size)) {
                        take(preset.size)
                    }
                    Divider().opacity(0.4)
                }
                if editorState.iconFramesEnabled {
                    iconSizes
                    Divider().opacity(0.4)
                }
                row(id: Self.customID, title: "Custom", detail: nil) {}
            }
            .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 10))

            if selection == Self.customID {
                HStack(spacing: 8) {
                    field("Width", $width).focused($customFieldFocused)
                    Text(verbatim: "×").foregroundStyle(.secondary)
                    field("Height", $height)
                    Text("px").font(.callout).foregroundStyle(.secondary)
                }
                .onAppear { customFieldFocused = true }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .playtestControl("Cancel", detail: "New Frame")
                Button("Add Frame") {
                    editorState.addFrameInView(size: chosenSize)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!FramePreset.isValid(chosenSize))
                .playtestControl("Add Frame", detail: "New Frame")
            }
        }
        .padding(20)
        .frame(width: 320)
        // A guide about starting an icon points at this sheet, so the card
        // lands beside it rather than on top of it.
        .tutorialAnchor(.dialog(.newFrame))
        // Opens on the size made last: a second phone screen is Return.
        .onAppear {
            let last = editorState.lastFrameSize
            width = Double(last.width)
            height = Double(last.height)
            selection = FramePreset.matching(last)?.id ?? Self.customID
        }
    }

    /// The icon group: a heading and the six sizes side by side, each one a
    /// square the width of its neighbours so the strip reads as one control
    /// rather than six loose buttons.
    private var iconSizes: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Icons")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(FramePreset.icons) { preset in
                    chip(preset)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .playtestField("Icons")
    }

    private func chip(_ preset: FramePreset) -> some View {
        let isSelected = selection == preset.id
        return Button {
            selection = preset.id
            take(preset.size)
        } label: {
            Text(verbatim: "\(Int(preset.size.width))")
                .font(.callout.monospacedDigit())
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary.opacity(0.5)),
                            in: .rect(cornerRadius: 6))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help("A \(FramePreset.sizeText(preset.size)) canvas to draw an icon on")
        .playtestControl("\(Int(preset.size.width))", detail: FramePreset.sizeText(preset.size))
    }

    private var chosenSize: CGSize {
        CGSize(width: width, height: height)
    }

    private func take(_ size: CGSize) {
        width = Double(size.width)
        height = Double(size.height)
    }

    private func row(id: String, title: String, detail: String?,
                     onPick: @escaping () -> Void) -> some View {
        let isSelected = selection == id
        return Button {
            selection = id
            onPick()
        } label: {
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
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .playtestControl(title, detail: detail ?? "")
    }

    private func field(_ label: String, _ value: Binding<Double>) -> some View {
        TextField(label, value: value,
                  format: .number.precision(.fractionLength(0)).grouping(.never))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .labelsHidden()
            .frame(width: 76)
    }
}
