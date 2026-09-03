import PhotonzCore
import PhotonzRender
import SwiftUI

/// Format + scale picker for Export… (⌘E). The actual rendering, encoding,
/// and save panel live in EditorState.
///
/// With frames in the document (Next, `next-frames`) it also asks WHAT to
/// export: the whole canvas, or one frame on its own. It opens on the frame you
/// have selected, so exporting the screen you are working on is Return.
struct ExportDialog: View {
    @Environment(EditorState.self) private var editorState
    @Environment(\.dismiss) private var dismiss
    @State private var format: ImageCodec.Format = .png
    @State private var scale: CGFloat = 1
    @State private var frameID: UUID?

    private var frames: [Layer] {
        guard Experiments.shared.framesEnabled else { return [] }
        return editorState.documentFrames
    }

    /// What the size line describes: the chosen frame's box, else the canvas.
    private var exportedSize: CGSize? {
        if let frameID, let frame = frames.first(where: { $0.id == frameID }) {
            return frame.frame.size
        }
        return editorState.document?.canvasSize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export Image")
                .font(.headline)
            if !frames.isEmpty {
                Picker("Export", selection: $frameID) {
                    Text("Whole canvas").tag(UUID?.none)
                    ForEach(frames) { frame in
                        Text(frame.name).tag(UUID?.some(frame.id))
                    }
                }
                .pickerStyle(.menu)
            }
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
            if let size = exportedSize {
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
                    editorState.exportComposite(format: format, scale: scale, frameID: frameID)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
        // Opens on the frame you are working in, so the common case is Return.
        .onAppear { frameID = editorState.selectedFrameID }
    }
}
