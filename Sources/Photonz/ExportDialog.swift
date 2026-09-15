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
    @State private var destination: SVGHandoff.Destination = .webPage
    /// How big the file would be, worked out only for a drawing made of
    /// shapes. Nil while there is nothing worth saying.
    @State private var byteCount: Int?
    /// Parts of the motion the FILE itself cannot carry, whatever the
    /// destination: a turn on a layer that is also flipped, say.
    @State private var unmoved: [SVGExport.Fallback] = []

    private var frames: [Layer] {
        guard Experiments.shared.framesEnabled else { return [] }
        return editorState.documentFrames
    }

    private var offersSVG: Bool { Experiments.shared.svgExportEnabled }

    /// Whether the hand-off question is worth asking at all: something in the
    /// drawing moves, so where it is going decides whether that survives.
    private var asksWhereItIsGoing: Bool {
        Experiments.shared.animatedSVGExportEnabled && (target?.hasMotion ?? false)
    }

    /// What the chosen destination gets.
    private var handoffFormat: SVGHandoff.Format? {
        guard asksWhereItIsGoing, let target else { return nil }
        return SVGHandoff.format(for: destination, in: target)
    }

    /// Whether the motion travels with the file.
    private var carriesTheMotion: Bool { handoffFormat == .animatedSVG }

    /// The format a destination implies, as an Export answer.
    private func answer(for format: SVGHandoff.Format) -> ExportChoice {
        switch format {
        case .animatedSVG, .stillSVG: offersSVG ? .svg : .picture(.png)
        case .picture: .picture(.png)
        }
    }

    /// Keeps where you sent the last one, unless a walk asked for this one, in
    /// which case nothing about the walk outlives it.
    private func rememberDestination() {
        #if PHOTONZ_PLAYTEST
        if editorState.playtestExportDestination != nil { return }
        #endif
        destination.remember()
    }

    private func refreshSize() {
        guard asksWhereItIsGoing, choice.isVector else {
            byteCount = nil
            unmoved = []
            return
        }
        let preflight = editorState.svgPreflight(frameID: frameID, animated: carriesTheMotion)
        byteCount = preflight?.bytes
        unmoved = preflight?.unmoved ?? []
    }

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
            // What is asked FIRST, because the destination is what decides
            // whether the motion survives, and because most people know where
            // the file is going and do not know their formats.
            if asksWhereItIsGoing {
                Picker("Where it is going", selection: $destination) {
                    ForEach(SVGHandoff.Destination.allCases, id: \.self) { where_ in
                        Text(where_.title).tag(where_)
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
            if asksWhereItIsGoing {
                handoffNote
            }
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
                        editorState.exportSVG(frameID: frameID, animated: carriesTheMotion)
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
            destination = SVGHandoff.remembered
            #if PHOTONZ_PLAYTEST
            if let asked = editorState.playtestExportDestination { destination = asked }
            #endif
            if asksWhereItIsGoing, let format = handoffFormat {
                choice = answer(for: format)
            }
            #if PHOTONZ_PLAYTEST
            if editorState.playtestOpensExportOnSVG, offersSVG { choice = .svg }
            #endif
            refreshSize()
        }
        // Picking a destination moves the format to the one that survives the
        // trip, and says why below. The picker stays exactly where it was, so
        // it can be moved straight back.
        .onChange(of: destination) {
            rememberDestination()
            if let format = handoffFormat { choice = answer(for: format) }
            refreshSize()
        }
        .onChange(of: choice) { refreshSize() }
        .onChange(of: frameID) { refreshSize() }
    }

    /// What survives the trip to the chosen destination, and what does not.
    ///
    /// The crossed-out lines are the point of the whole sheet: you find out
    /// that a code host will strip the animation, or that a drawing in a page
    /// receives no clicks, while you can still do something about it.
    @ViewBuilder private var handoffNote: some View {
        if let target {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(SVGHandoff.lines(for: destination, in: target)) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: line.survives ? "checkmark" : "xmark")
                            .font(.caption)
                            .foregroundStyle(line.survives ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(line.text)
                                .font(.caption)
                                .foregroundStyle(line.survives ? .primary : .secondary)
                            if let detail = line.detail {
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let note = unmovedNote {
                    Label(note, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
                if let format = handoffFormat {
                    Text(sizeNote(format))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The parts of the motion the file could not write at all, named before
    /// you save rather than noticed afterwards by a drawing that sits still.
    private var unmovedNote: String? {
        guard carriesTheMotion, !unmoved.isEmpty else { return nil }
        if unmoved.count == 1 {
            return "\(unmoved[0].layerName): its \(unmoved[0].reason)."
        }
        let names = unmoved.prefix(3).map(\.layerName).joined(separator: ", ")
        return "\(names) each have a change the file cannot carry."
    }

    /// What the file is, and how big it turned out to be.
    private func sizeNote(_ format: SVGHandoff.Format) -> String {
        guard choice.isVector, let byteCount else { return format.title }
        if byteCount < 1024 { return "\(format.title) · \(byteCount) bytes" }
        let kilobytes = Double(byteCount) / 1024
        return String(format: "%@ · %.1f KB", format.title, kilobytes)
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
