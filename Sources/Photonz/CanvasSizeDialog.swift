import PhotonzCore
import SwiftUI

/// The Image → Canvas Size… sheet: new pixel dimensions plus a 3×3 anchor
/// picker for where the existing content pins. Content never scales — that's
/// the resize dialog's job.
struct CanvasSizeDialog: View {
    @Environment(EditorState.self) private var editorState
    @Environment(\.dismiss) private var dismiss
    @State private var width: Double
    @State private var height: Double
    @State private var anchor: CanvasAnchor = .center
    private let originalSize: CGSize

    private static let anchorGrid: [[CanvasAnchor]] = [
        [.topLeft, .top, .topRight],
        [.left, .center, .right],
        [.bottomLeft, .bottom, .bottomRight],
    ]

    init(originalSize: CGSize) {
        self.originalSize = originalSize
        _width = State(initialValue: Double(originalSize.width))
        _height = State(initialValue: Double(originalSize.height))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Canvas Size")
                .font(.headline)

            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    field("Width", $width)
                    field("Height", $height)
                    Text(verbatim: "\(Int(originalSize.width)) × \(Int(originalSize.height)) px now")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                anchorPicker
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Apply") {
                    editorState.setCanvasSize(to: CGSize(width: width.rounded(), height: height.rounded()),
                                           anchor: anchor)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(width < 1 || height < 1 || isIdentity)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private var isIdentity: Bool {
        width.rounded() == Double(originalSize.width) && height.rounded() == Double(originalSize.height)
    }

    /// 3×3 anchor grid; the selected cell pins the existing content.
    private var anchorPicker: some View {
        VStack(spacing: 3) {
            ForEach(Self.anchorGrid, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(row, id: \.self) { cell in
                        Button {
                            anchor = cell
                        } label: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(anchor == cell ? Color.accentColor : Color.secondary.opacity(0.25))
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help("Anchor content at \(cell.rawValue)")
                    }
                }
            }
        }
    }

    private func field(_ label: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            TextField(label, value: value,
                      format: .number.precision(.fractionLength(0)).grouping(.never))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text("px")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
