import PhotonzCore
import SwiftUI

/// The Image → Resize… sheet. All sizing logic lives in `ResizeModel`
/// (PhotonzCore, tested); this view just binds fields to it.
struct ResizeDialog: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var model: ResizeModel

    /// Uniform percent presets; Retina @2x→@1x is the 50% halving spelled out.
    private static let presets: [(label: String, percent: CGFloat)] = [
        ("25%", 25), ("50%", 50), ("75%", 75), ("200%", 200),
        ("Retina @2x → @1x", 50),
    ]

    init(originalSize: CGSize) {
        _model = State(initialValue: ResizeModel(originalSize: originalSize))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Resize Image")
                    .font(.headline)
                Spacer()
                Menu("Presets") {
                    ForEach(Self.presets, id: \.label) { preset in
                        Button(preset.label) { model.applyPercent(preset.percent) }
                    }
                }
                .fixedSize()
            }

            Picker("Unit", selection: Binding(
                get: { model.unit },
                set: { model.setUnit($0) })) {
                ForEach(ResizeModel.Unit.allCases, id: \.self) { unit in
                    Text(unit.label).tag(unit)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 10) {
                field("Width", value: model.width) { model.setWidth($0) }
                Button {
                    model.setLockAspect(!model.lockAspect)
                } label: {
                    Image(systemName: model.lockAspect ? "lock" : "lock.open")
                        .frame(width: 20)
                }
                .buttonStyle(.borderless)
                .help(model.lockAspect ? "Unlock aspect ratio" : "Lock aspect ratio")
                field("Height", value: model.height) { model.setHeight($0) }
            }

            Text(resultDescription)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Resize") {
                    appState.resizeDocument(to: model.targetSize)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.isValid || model.isIdentity)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private var resultDescription: String {
        let o = model.originalSize
        guard model.isValid else { return "Enter a size larger than zero." }
        let t = model.targetSize
        return "\(Int(o.width)) × \(Int(o.height)) px  →  \(Int(t.width)) × \(Int(t.height)) px"
    }

    private func field(_ label: String, value: CGFloat,
                       set: @escaping (CGFloat) -> Void) -> some View {
        TextField(label, value: Binding(get: { Double(value) }, set: { set(CGFloat($0)) }),
                  format: .number.precision(.fractionLength(0...2)).grouping(.never))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 90)
    }
}
