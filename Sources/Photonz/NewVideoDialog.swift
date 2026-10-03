import PhotonzCore
import SwiftUI

/// "How big, and how long?" — the two questions between nothing and an empty
/// timeline (`video.html`, the New video on ramp, step 1). Opens on the mock's
/// blank project, 1920 × 1080 for ten seconds, so Return alone makes one.
///
/// Like `NewCanvasDialog`, the sheet does not decide where the video lands:
/// whoever presents it hands in `onCreate`.
struct NewVideoDialog: View {
    /// Called with the chosen size and the length in milliseconds.
    let onCreate: (CGSize, Int) -> Void
    /// Whether the video will arrive in a window of its own.
    var opensNewWindow: Bool = false

    @Environment(\.dismiss) private var dismiss

    @State private var selection: String = BlankVideo.defaultPreset.id
    @State private var width: Double = Double(BlankVideo.defaultPreset.size.width)
    @State private var height: Double = Double(BlankVideo.defaultPreset.size.height)
    @State private var seconds: Double = BlankVideo.defaultLengthSeconds
    @FocusState private var customFieldFocused: Bool
    /// The last size typed by hand, kept when a preset is picked over it, so
    /// picking Custom again gives it back (`CustomChoice`).
    @State private var custom = CustomChoice<CGSize>()

    private static let customID = "custom"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Video")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(BlankVideo.presets) { preset in
                    row(id: preset.id, title: preset.title,
                        detail: Self.dimensions(preset.size)) {
                        width = Double(preset.size.width)
                        height = Double(preset.size.height)
                    }
                    Divider().opacity(0.4)
                }
                row(id: Self.customID, title: "Custom",
                    detail: selection == Self.customID ? nil : custom.kept.map(Self.dimensions)) {
                    if let size = custom.kept {
                        width = Double(size.width)
                        height = Double(size.height)
                    }
                }
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

            HStack(spacing: 8) {
                Text("Length").font(.callout)
                Spacer(minLength: 12)
                field("Length", $seconds)
                Text("sec").font(.callout).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(opensNewWindow ? "Create in New Window" : "Create") {
                    onCreate(chosenSize, BlankVideo.lengthMS(seconds: seconds))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!BlankVideo.isValid(chosenSize) || !BlankVideo.isValidLength(seconds: seconds))
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private var chosenSize: CGSize {
        CGSize(width: width, height: height)
    }

    /// One selectable size, the same row the New Canvas sheet uses.
    private func row(id: String, title: String, detail: String?,
                     onPick: @escaping () -> Void) -> some View {
        let isSelected = selection == id
        return Button {
            custom.keep(chosenSize, isOwn: selection == Self.customID)
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

    private static func dimensions(_ size: CGSize) -> String {
        "\(Int(size.width)) × \(Int(size.height))"
    }

    private func field(_ label: String, _ value: Binding<Double>) -> some View {
        TextField(label, value: value,
                  format: .number.precision(.fractionLength(0...1)).grouping(.never))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .labelsHidden()
            .frame(width: 76)
    }
}
