import PhotonzCore
import PhotonzRender
import SwiftUI

/// What Export is being asked for. Three of the four are pictures and take a
/// scale; the fourth has no pixels in it at all, which is why this is one
/// choice rather than a format plus a flag (Next, `next-export-svg`).
enum ExportChoice: Hashable {
    case picture(ImageCodec.Format)
    case svg

    var isVector: Bool { self == .svg }

    /// What Export opens on: whatever you picked last time. Exporting a set of
    /// icons is picking SVG once, not once per icon.
    static let rememberedKey = "export.format"

    var stored: String {
        switch self {
        case .svg: "svg"
        case .picture(let format): format.rawValue
        }
    }

    /// The choice last used, or PNG. An answer this build cannot offer — SVG
    /// with the flag off — comes back as PNG rather than as a format with no
    /// button.
    static func remembered(offeringSVG: Bool) -> ExportChoice {
        let stored = UserDefaults.standard.string(forKey: rememberedKey)
        if stored == "svg" { return offeringSVG ? .svg : .picture(.png) }
        return ImageCodec.Format(rawValue: stored ?? "").map(ExportChoice.picture) ?? .picture(.png)
    }

    func remember() {
        UserDefaults.standard.set(stored, forKey: Self.rememberedKey)
    }
}

/// Format + scale picker for Export… (⌘E). The actual rendering, encoding,
/// and save panel live in EditorState.
///
/// With frames in the document (Next, `next-frames`) it also asks WHAT to
/// export: the whole canvas, or one frame on its own. It opens on the frame you
/// have selected, so exporting the screen you are working on is Return.
///
/// With SVG in the picker (Next, `next-export-svg`), choosing it puts the scale
/// row away — 1× and 2× mean nothing for a file with no pixels — and says
/// instead what the file will be and what, if anything, could not be written as
/// shapes. That last line is the whole point of saying it here: you find out
/// before you save rather than by opening the file.
struct ExportDialog: View {
    @Environment(EditorState.self) private var editorState
    @Environment(\.dismiss) private var dismiss
    @State private var choice: ExportChoice = .picture(.png)
    @State private var scale: CGFloat = 1
    @State private var frameID: UUID?

    private var frames: [Layer] {
        guard Experiments.shared.framesEnabled else { return [] }
        return editorState.documentFrames
    }

    private var offersSVG: Bool { Experiments.shared.svgExportEnabled }

    /// What the size line describes: the chosen frame's box, else the canvas.
    private var exportedSize: CGSize? {
        if let frameID, let frame = frames.first(where: { $0.id == frameID }) {
            return frame.frame.size
        }
        return editorState.document?.canvasSize
    }

    /// What the document being exported actually is, which is the frame on its
    /// own when one is picked.
    private var target: PhotonzDocument? {
        guard let document = editorState.document else { return nil }
        if let frameID, let scoped = document.frameDocument(id: frameID) { return scoped }
        return document
    }

    /// The layers with no vector answer at all, each with the reason the file
    /// could not say them in shapes.
    private var unwritable: [SVGExport.Fallback] {
        guard choice.isVector, let target else { return [] }
        return SVGExport.fallbacks(in: target)
    }

    /// The pictures that are simply pictures: a photograph was never shapes,
    /// so nothing went wrong, but somebody about to hand the file to somebody
    /// else still wants to know there is a bitmap inside it.
    private var photographs: [String] {
        guard choice.isVector, let target else { return [] }
        let problems = Set(unwritable.map(\.layerName))
        return SVGExport.embeddedPictures(in: target)
            .map(\.layerName)
            .filter { !problems.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Not "Export Image": one of the four answers is not a picture.
            Text("Export")
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
            Picker("Format", selection: $choice) {
                Text("PNG").tag(ExportChoice.picture(.png))
                Text("JPEG").tag(ExportChoice.picture(.jpeg))
                Text("HEIC").tag(ExportChoice.picture(.heic))
                if offersSVG {
                    Text("SVG").tag(ExportChoice.svg)
                }
            }
            .pickerStyle(.segmented)
            if choice.isVector {
                vectorNote
            } else {
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
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Export…") {
                    dismiss()
                    choice.remember()
                    switch choice {
                    case .picture(let format):
                        editorState.exportComposite(format: format, scale: scale, frameID: frameID)
                    case .svg:
                        editorState.exportSVG(frameID: frameID)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
        // Opens on the frame you are working in, and on the format you picked
        // last time, so the common case is Return.
        .onAppear {
            frameID = editorState.selectedFrameID
            choice = ExportChoice.remembered(offeringSVG: offersSVG)
            #if PHOTONZ_PLAYTEST
            if editorState.playtestOpensExportOnSVG, offersSVG { choice = .svg }
            #endif
        }
    }

    /// What a vector file gets instead of a scale: what it is, and what could
    /// not be said in shapes.
    @ViewBuilder private var vectorNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let size = exportedSize {
                Label("Shapes, sharp at any size. Drawn at \(Int(size.width)) × \(Int(size.height)).",
                      systemImage: "square.on.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
            if let note = photographNote {
                Label(note, systemImage: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
            if let note = unwritableNote {
                Label(note, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The bitmaps that ride along, named.
    private var photographNote: String? {
        let names = photographs
        guard !names.isEmpty else { return nil }
        if names.count == 1 { return "\(names[0]) rides along as a picture." }
        return "\(names.count) pictures ride along: \(names.prefix(3).joined(separator: ", "))."
    }

    /// One plain line naming what could not be written as shapes and why, or
    /// nothing at all when the whole drawing came across.
    private var unwritableNote: String? {
        let problems = unwritable
        guard !problems.isEmpty else { return nil }
        if problems.count == 1 {
            return "\(problems[0].layerName) goes out as a picture: \(problems[0].reason)."
        }
        let names = problems.prefix(3).map(\.layerName).joined(separator: ", ")
        let rest = problems.count > 3 ? " and \(problems.count - 3) more" : ""
        return "\(names)\(rest) go out as pictures rather than shapes."
    }
}
