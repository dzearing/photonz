import PhotonzCore
import SwiftUI

/// "How big is this screen?" — the one question between a canvas and something
/// to build on (Next, `next-frames`).
///
/// It opens on the size you made last, so Return alone gives you another screen
/// the same size, and the frame lands in the middle of what you are looking at
/// rather than at some corner you would have to go find.
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
                ForEach(FramePreset.all) { preset in
                    row(id: preset.id, title: preset.title,
                        detail: Self.dimensions(preset.size)) {
                        width = Double(preset.size.width)
                        height = Double(preset.size.height)
                    }
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
                Button("Add Frame") {
                    editorState.addFrameInView(size: chosenSize)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!FramePreset.isValid(chosenSize))
            }
        }
        .padding(20)
        .frame(width: 320)
        // Opens on the size made last: a second phone screen is Return.
        .onAppear {
            let last = editorState.lastFrameSize
            width = Double(last.width)
            height = Double(last.height)
            selection = FramePreset.matching(last)?.id ?? Self.customID
        }
    }

    private var chosenSize: CGSize {
        CGSize(width: width, height: height)
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
    }

    private static func dimensions(_ size: CGSize) -> String {
        "\(Int(size.width)) × \(Int(size.height))"
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
