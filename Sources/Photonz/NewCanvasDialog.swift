import PhotonzCore
import SwiftUI

/// "How big?" — the one question between nothing and a canvas you can draw on.
/// Opens with a size already picked, so Return alone makes a canvas and nobody
/// has to think about pixels to get started.
///
/// The sheet does not decide where the canvas lands: whoever presents it hands
/// in `onCreate`, so the empty window's card fills that window and the File
/// menu can open a new one, from the same sheet.
struct NewCanvasDialog: View {
    /// Called with the chosen size when Create is pressed.
    let onCreate: (CGSize) -> Void
    /// Whether the canvas will arrive in a window of its own. The button says
    /// so, because the picture behind this sheet is not going anywhere and
    /// nobody should have to press Create to find that out.
    var opensNewWindow: Bool = false

    @Environment(\.dismiss) private var dismiss

    /// A preset's id, or `customID` while the size is typed by hand.
    @State private var selection: String = BlankCanvas.defaultPreset.id
    @State private var width: Double = Double(BlankCanvas.defaultPreset.size.width)
    @State private var height: Double = Double(BlankCanvas.defaultPreset.size.height)
    @FocusState private var customFieldFocused: Bool

    private static let customID = "custom"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Canvas")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(BlankCanvas.presets) { preset in
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
                // Picking Custom puts the cursor in Width, so the next thing
                // typed is the size rather than a hunt for the field.
                .onAppear { customFieldFocused = true }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(opensNewWindow ? "Create in New Window" : "Create") {
                    onCreate(chosenSize)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!BlankCanvas.isValid(chosenSize))
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private var chosenSize: CGSize {
        CGSize(width: width, height: height)
    }

    /// One selectable size. The whole row is the target, not a small circle,
    /// and the picked one carries the accent so the choice reads at a glance.
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
