import PhotonzCore
import PhotonzRender
import SwiftUI

/// What Export is being asked for. All but one of the answers is a picture and
/// takes a scale; the last has no pixels in it at all, which is why this is one
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

    /// The choice last used, or PNG. An answer this build cannot offer — SVG or
    /// WebP with the flag off — comes back as PNG rather than as a format with
    /// no button, which would leave the picker showing nothing selected.
    static func remembered(offeringSVG: Bool, offeringWebP: Bool) -> ExportChoice {
        let stored = UserDefaults.standard.string(forKey: rememberedKey)
        if stored == "svg" { return offeringSVG ? .svg : .picture(.png) }
        guard let format = ImageCodec.Format(rawValue: stored ?? "") else { return .picture(.png) }
        if format == .webp, !offeringWebP { return .picture(.png) }
        return .picture(format)
    }

    func remember() {
        UserDefaults.standard.set(stored, forKey: Self.rememberedKey)
    }
}

/// What quality each lossy format was last exported at.
///
/// One number per format, kept the way the format itself is kept: somebody who
/// always wants eighty percent sets it once. `ExportQuality` owns the rules,
/// so a number left over from an older build, or edited by hand, comes back
/// snapped onto the range the slider can actually reach.
enum ExportQualityMemory {
    static func remembered(format id: String) -> Int {
        let stored = UserDefaults.standard.object(forKey: ExportQuality.storageKey(format: id))
        guard let percent = stored as? Int else { return ExportQuality.standard }
        return ExportQuality.snapped(percent)
    }

    static func remember(_ percent: Int, format id: String) {
        UserDefaults.standard.set(ExportQuality.snapped(percent),
                                  forKey: ExportQuality.storageKey(format: id))
    }
}

/// Format + scale picker for Export… (⌘E). The actual rendering, encoding,
/// and save panel live in EditorState.
///
/// With frames in the document (Next, `next-frames`) it also asks WHAT to
/// export: the whole canvas, or one frame on its own. It opens on the frame you
/// have selected, so exporting the screen you are working on is Return.
///
/// With WebP in the picker (Next, `next-export-webp`), it behaves like the other
/// lossy formats: same slider, same live size. The one thing it does that they
/// cannot is at the very top of that slider, where it writes a lossless file and
/// the line under the slider says "Lossless" instead of "Best".
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
    /// What each lossy format is set to while the sheet is up, seeded from what
    /// was remembered. Held here rather than written straight back so that
    /// moving the slider and then pressing Cancel changes nothing, and so that
    /// going JPEG → HEIC → JPEG comes back to the number you left.
    @State private var qualities: [String: Int] = [:]
    /// What the picture would weigh at the answers showing now, in bytes. Nil
    /// until the first one lands.
    @State private var pictureBytes: Int?
    /// A newer number is being worked out, so the one on screen is the last
    /// one. It stays up rather than blanking: a number that flickers to nothing
    /// every time the slider twitches is worse than one that is a moment stale.
    @State private var weighing = false
    /// Whether a weigh has finished at all. Without it a picture that cannot be
    /// encoded reads as one still being worked out, forever.
    @State private var weighed = false
    /// Encodes the picture to find out what it weighs, off the main actor, and
    /// keeps the render between qualities. Made when the sheet opens and gone
    /// when it closes, which is exactly as long as the document it assumes is
    /// standing still can be trusted to stand still.
    @State private var sizer: ExportSizer?
    @State private var weighTask: Task<Void, Never>?

    private var frames: [Layer] {
        guard Experiments.shared.framesEnabled else { return [] }
        return editorState.documentFrames
    }

    private var offersSVG: Bool { Experiments.shared.svgExportEnabled }

    private var offersWebP: Bool { Experiments.shared.webPExportEnabled }

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
        refreshVectorSize()
        refreshPictureSize()
    }

    private func refreshVectorSize() {
        guard asksWhereItIsGoing, choice.isVector else {
            byteCount = nil
            unmoved = []
            return
        }
        let preflight = editorState.svgPreflight(frameID: frameID, animated: carriesTheMotion)
        byteCount = preflight?.bytes
        unmoved = preflight?.unmoved ?? []
    }

    // MARK: - Quality

    /// Whether Export offers a quality at all (Next, `next-export-quality`).
    private var offersQuality: Bool { Experiments.shared.exportQualityEnabled }

    /// The format being exported, when it is one that throws pixels away and so
    /// has a quality worth choosing. Nil for PNG, for SVG, and with the flag
    /// off — and nil is what takes the whole row away rather than dimming it.
    private var lossyFormat: ImageCodec.Format? {
        guard offersQuality, case .picture(let format) = choice,
              ExportQuality.applies(toFormat: format.rawValue) else { return nil }
        return format
    }

    /// What the quality is set to for the format showing now.
    private var qualityPercent: Int {
        guard let lossyFormat else { return ExportQuality.standard }
        return qualities[lossyFormat.rawValue] ?? ExportQuality.standard
    }

    /// What the slider reads out loud. At the top of a format whose top is
    /// lossless, the number alone would hide the only thing worth knowing.
    private var qualityVoice: String {
        ExportQuality.isLossless(atPercent: qualityPercent, format: lossyFormat?.rawValue ?? "")
            ? "100 percent, lossless"
            : "\(qualityPercent) percent"
    }

    private var qualityBinding: Binding<Double> {
        Binding(get: { Double(qualityPercent) },
                set: { value in
                    guard let lossyFormat else { return }
                    qualities[lossyFormat.rawValue] = ExportQuality.snapped(Int(value.rounded()))
                })
    }

    /// What the chosen quality is called, and what it costs, on one line.
    private var qualityNote: String {
        let word = ExportQuality.word(for: qualityPercent,
                                      format: lossyFormat?.rawValue ?? "")
        if let pictureBytes { return "\(word) · \(ExportQuality.fileSize(bytes: pictureBytes))" }
        return weighed ? word : "\(word) · working out the size"
    }

    /// Encodes the picture to find out what it really weighs.
    ///
    /// Everything expensive is deliberate here. There is no formula for the
    /// size of a lossy file worth trusting, so the only honest number comes
    /// from encoding it; that costs a render and an encode, and it is asked for
    /// again on every stop of a slider somebody is dragging. So the work waits
    /// for the hand to settle, it happens off the main actor, the sizer keeps
    /// the render between qualities, and the number already on screen stays up
    /// until a newer one is ready.
    private func refreshPictureSize() {
        weighTask?.cancel()
        guard let lossyFormat, let document = editorState.document else {
            weighTask = nil
            pictureBytes = nil
            weighing = false
            weighed = false
            return
        }
        let sizer = sizer ?? ExportSizer(renderer: editorState.previewRenderer,
                                         store: editorState.store)
        self.sizer = sizer
        let quality = ExportQuality.fraction(qualityPercent)
        let scale = scale
        let frameID = frameID
        weighing = true
        weighTask = Task {
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            let bytes = await sizer.byteCount(of: document, frameID: frameID, scale: scale,
                                              format: lossyFormat, quality: quality)
            guard !Task.isCancelled else { return }
            pictureBytes = bytes
            weighed = true
            weighing = false
        }
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
        return SVGExporter.fallbacks(in: target, store: editorState.store)
    }

    /// The pictures that are simply pictures: a photograph was never shapes,
    /// so nothing went wrong, but somebody about to hand the file to somebody
    /// else still wants to know there is a bitmap inside it.
    private var photographs: [String] {
        guard choice.isVector, let target else { return [] }
        let problems = Set(unwritable.map(\.layerName))
        return SVGExporter.embeddedPictures(in: target, store: editorState.store)
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
                if offersWebP {
                    Text("WebP").tag(ExportChoice.picture(.webp))
                }
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
                if lossyFormat != nil {
                    qualityRow
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
                        let percent = qualities[format.rawValue] ?? ExportQuality.standard
                        if offersQuality, ExportQuality.applies(toFormat: format.rawValue) {
                            ExportQualityMemory.remember(percent, format: format.rawValue)
                        }
                        // Handing over the sizer hands over the work it has
                        // already done: the number you just read came from
                        // encoding this very file, so saving it is instant.
                        editorState.exportComposite(format: format, scale: scale,
                                                    quality: ExportQuality.fraction(percent),
                                                    frameID: frameID, using: sizer)
                    case .svg:
                        editorState.exportSVG(frameID: frameID, animated: carriesTheMotion)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
        // The last card of the SVG guide points at this sheet, so it sits
        // beside the sheet rather than over the row it is talking about.
        .tutorialAnchor(.dialog(.export))
        // Opens on the frame you are working in, and on the format you picked
        // last time, so the common case is Return.
        .onAppear {
            frameID = editorState.selectedFrameID
            choice = ExportChoice.remembered(offeringSVG: offersSVG, offeringWebP: offersWebP)
            destination = SVGHandoff.remembered
            #if PHOTONZ_PLAYTEST
            if let asked = editorState.playtestExportDestination { destination = asked }
            #endif
            if asksWhereItIsGoing, let format = handoffFormat {
                choice = answer(for: format)
            }
            #if PHOTONZ_PLAYTEST
            if editorState.playtestOpensExportOnSVG, offersSVG { choice = .svg }
            if let asked = editorState.playtestOpensExportOnPicture {
                choice = .picture(asked)
                // Taken once. A walk that photographs the quality slider and
                // then photographs PNG gets PNG, whatever order it asks in.
                editorState.playtestOpensExportOnPicture = nil
            }
            #endif
            // Only with the flag on. Off has to write what it always wrote,
            // and a number left behind by a build with the slider in it must
            // not quietly follow somebody back to the build without it.
            if offersQuality {
                qualities = Dictionary(uniqueKeysWithValues: ExportQuality.lossyFormats.map {
                    ($0, ExportQualityMemory.remembered(format: $0))
                })
            }
            refreshSize()
        }
        .onDisappear { weighTask?.cancel() }
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
        // 2x is a different file, so it is a different number.
        .onChange(of: scale) { refreshPictureSize() }
        .onChange(of: qualityPercent) { refreshPictureSize() }
    }

    /// The quality to write at, and what the file weighs there.
    ///
    /// Two lines rather than one: the slider answers how much of the picture to
    /// keep, and the line under it answers what that is called and what it
    /// costs. The size is the whole reason the row exists, so it sits directly
    /// under the thing that changes it rather than in the corner of the sheet.
    @ViewBuilder private var qualityRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text("Quality")
                Slider(value: qualityBinding,
                       in: Double(ExportQuality.lowest)...Double(ExportQuality.highest),
                       step: Double(ExportQuality.step))
                    .accessibilityLabel("Quality")
                    .accessibilityValue(qualityVoice)
                Text("\(qualityPercent)%")
                    .monospacedDigit()
                    .frame(width: 38, alignment: .trailing)
            }
            Text(qualityNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                // A number being replaced fades rather than blanking, so the
                // line never jumps about under a hand that is still moving.
                .opacity(weighing ? 0.45 : 1)
                .animation(.easeOut(duration: 0.12), value: weighing)
                .animation(.easeOut(duration: 0.12), value: pictureBytes)
        }
    }

    /// What survives the trip to the chosen destination, and what does not.
    ///
    /// The crossed-out lines are the point of the whole sheet: you find out
    /// that a code host will strip the animation, or that a drawing in a page
    /// receives no clicks, while you can still do something about it.
    @ViewBuilder private var handoffNote: some View {
        if let target {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(SVGHandoff.lines(for: destination, in: target,
                                         flatImages: FlatBitmap.colors(in: target,
                                                                       store: editorState.store))) { line in
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
