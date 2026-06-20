import PhotonzRender
import SwiftUI

/// Format + scale picker for Export… (⌘E). The actual rendering, encoding,
/// and save panel live in EditorState.
struct ExportDialog: View {
    @Environment(EditorState.self) private var editorState
    @Environment(\.dismiss) private var dismiss
    @State private var format: ImageCodec.Format = .png
    @State private var scale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Image")
                .font(.headline)
            Picker("Format", selection: $format) {
                Text("PNG").tag(ImageCodec.Format.png)
                Text("JPEG").tag(ImageCodec.Format.jpeg)
                Text("HEIC").tag(ImageCodec.Format.heic)
            }
            .pickerStyle(.segmented)
            Picker("Scale", selection: $scale) {
                Text("1×").tag(CGFloat(1))
                Text("2×").tag(CGFloat(2))
            }
            .pickerStyle(.segmented)
            if let size = editorState.document?.canvasSize {
                Text("\(Int(size.width * scale)) × \(Int(size.height * scale)) px")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Export…") {
                    dismiss()
                    editorState.exportComposite(format: format, scale: scale)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
