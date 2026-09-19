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
/// A drawing made on a blank canvas can go out with NOTHING behind it, as SVG
/// and as a picture alike: Include the background is the same control in the
/// same place for both, and it is never offered for a format that cannot hold
/// transparency or for a document with no canvas to leave out.
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
    /// How big the SVG would be, worked out only for a drawing made of
    /// shapes. Nil when the drawing carries a photograph, which cannot be
    /// weighed without rendering it, and nil while the answer is not SVG.
    @State private var byteCount: Int?
    /// Whether the SVG has been weighed at all since the last change. It is
    /// worked out where it is asked for rather than off in a task — writing an
    /// icon out as text is a few milliseconds, not a render and an encode — so
    /// this only ever separates "there is no number for this drawing" from
    /// "nobody has asked yet".
    @State private var vectorWeighed = false
    /// Parts of the motion the FILE itself cannot carry, whatever the
    /// destination: a turn on a layer that is also flipped, say.
    @State private var unmoved: [SVGExport.Fallback] = []
    /// The canvas behind the drawing, when there is one Export can offer to
    /// leave out.
    @State private var backdrop: SVGExport.Backdrop?
    /// Which of the target's bitmaps are one flat colour, by bitmap id.
    ///
    /// Worked out when the sheet opens and whenever the target changes, rather
    /// than while the sheet draws. Finding out walks every pixel of every
    /// picture in the document — 36 ms for a 12 megapixel canvas — and four
    /// separate lines of this sheet want the answer, so asking from `body`
    /// meant several of those on every pass SwiftUI made. The document cannot
    /// change while the sheet is up, which is the same thing the size weigher
    /// already assumes.
    @State private var flatImages: [UUID: RGBA] = [:]
    /// Whether the canvas colour goes into the file. Off, because a drawing
    /// handed to somebody else nearly always lands on their page rather than
    /// on the one it was drawn on, and a white box round an icon is the thing
    /// that makes it unusable there. Not remembered: it is answered per export
    /// and shown on the sheet each time, so it can never be a setting somebody
    /// left on months ago.
    @State private var keepsBackground = false
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

    /// What the file does with the canvas the drawing was made on.
    private var background: SVGExport.Background {
        backdrop != nil && !keepsBackground ? .drop : .keep
    }

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
        refreshWhatIsFlat()
        refreshVectorSize()
        refreshPictureSize()
    }

    /// Reads the pixels once, for every line of the sheet that needs them.
    ///
    /// A nil backdrop takes the background row away rather than dimming it: a
    /// screenshot has a photograph behind it, not a canvas, and there is
    /// nothing to ask about.
    private func refreshWhatIsFlat() {
        guard let target else {
            flatImages = [:]
            backdrop = nil
            return
        }
        flatImages = FlatBitmap.colors(in: target, store: editorState.store)
        backdrop = holdsTransparency
            ? SVGExport.backdrop(in: target, flatImages: flatImages)
            : nil
    }

    /// Whether the file being written could hold see-through pixels at all.
    ///
    /// SVG always can. A picture can only where the format can: a JPEG or a
    /// HEIC has no way to say "nothing here", so the question is never asked
    /// for them and the canvas goes in as it always did.
    private var holdsTransparency: Bool {
        switch choice {
        case .svg: true
        case .picture(let format): format.holdsTransparency
        }
    }

    /// Weighs the SVG, for every SVG and not only the moving ones.
    ///
    /// The gate used to be the hand-off question, so a still icon — the thing
    /// this app exports as SVG more than anything else — was the one answer on
    /// the sheet that never said what the file would weigh. Weighing it means
    /// writing it, which for a drawing made of shapes is a few milliseconds of
    /// text (`SVGPreflightSizeTests`), so it happens here rather than in a task
    /// and the number is on the sheet the moment it opens.
    private func refreshVectorSize() {
        guard choice.isVector else {
            byteCount = nil
            unmoved = []
            vectorWeighed = false
            return
        }
        vectorWeighed = true
        let preflight = editorState.svgPreflight(frameID: frameID, animated: carriesTheMotion,
                                                 background: background)
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

    /// The picture format being weighed, which is every picture format and not
    /// only the lossy ones.
    ///
    /// The difference from `lossyFormat` is PNG. It has no quality to choose,
    /// which is why it has no slider, but it still weighs something and that
    /// something still moves: a bigger scale, a different frame, and above all
    /// the canvas being left out, which is the whole reason an icon is
    /// exported as a PNG in the first place. Gated on the same flag as the
    /// rest of the weighing, so a build without it writes and says exactly
    /// what it always did.
    private var weighedFormat: ImageCodec.Format? {
        guard offersQuality, case .picture(let format) = choice else { return nil }
        return format
    }

    /// What the chosen answer is called, and what it costs, on one line.
    ///
    /// One line for every picture format, from one place, so PNG and JPEG can
    /// never drift into saying the size two different ways.
    private var sizeLine: String {
        if choice.isVector {
            return ExportQuality.note(forName: vectorName, bytes: byteCount,
                                      weighed: vectorWeighed)
        }
        return ExportQuality.note(forFormat: weighedFormat?.rawValue ?? "", percent: qualityPercent,
                                  bytes: pictureBytes, weighed: weighed)
    }

    /// What the vector file is called on its own line: the hand-off answer
    /// where one has been chosen, so a file carrying its motion says so, and
    /// plain SVG otherwise.
    private var vectorName: String {
        (handoffFormat?.isVector == true ? handoffFormat : nil)?.title
            ?? SVGHandoff.Format.stillSVG.title
    }

    /// Whether the SVG line has a number behind it. A drawing with a photograph
    /// in it cannot be weighed without rendering the photograph, and the sheet
    /// says nothing rather than a guess: the line naming the picture that rides
    /// along is directly underneath, so the absence is already explained.
    private var saysWhatTheVectorWeighs: Bool { byteCount != nil }

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
        guard let weighedFormat, let document = editorState.document else {
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
        // The very answer Export will be given, so the number on the sheet and
        // the file on disk can never be two different pictures. Without this
        // the weight ignored the background checkbox entirely, which nobody
        // could see while only the lossy formats were weighed -- three of the
        // four cannot hold transparency at all -- and which is the one thing
        // somebody ticking that box on a PNG is watching for.
        let background = background
        weighing = true
        weighTask = Task {
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            let bytes = await sizer.byteCount(of: document, frameID: frameID, scale: scale,
                                              format: weighedFormat, quality: quality,
                                              background: background)
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
        return SVGExport.fallbacks(in: target, flatImages: flatImages,
                                   isMoving: carriesTheMotion)
    }

    /// The pictures that are simply pictures: a photograph was never shapes,
    /// so nothing went wrong, but somebody about to hand the file to somebody
    /// else still wants to know there is a bitmap inside it.
    private var photographs: [String] {
        guard choice.isVector, let target else { return [] }
        let problems = Set(unwritable.map(\.layerName))
        return SVGExport.embeddedPictures(in: target, flatImages: flatImages,
                                          isMoving: carriesTheMotion)
            .map(\.layerName)
            .filter { !problems.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ExportSheetMetrics.spacing) {
            // Not "Export Image": one of the four answers is not a picture.
            Text("Export")
                .font(.headline)
            if !frames.isEmpty {
                labelledRow("Export") {
                    Picker("Export", selection: $frameID) {
                        Text("Whole canvas").tag(UUID?.none)
                        ForEach(frames) { frame in
                            Text(frame.name).tag(UUID?.some(frame.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
            // What is asked FIRST, because the destination is what decides
            // whether the motion survives, and because most people know where
            // the file is going and do not know their formats.
            if asksWhereItIsGoing {
                labelledRow("Where it is going") {
                    Picker("Where it is going", selection: $destination) {
                        ForEach(SVGHandoff.Destination.allCases, id: \.self) { where_ in
                            Text(where_.title).tag(where_)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }
            // The label is written out rather than left to the Picker: a
            // segmented Picker hands its own label whatever width is left over,
            // and with five formats in the row that was two characters, so
            // "Format" came out stacked Fo/r/m/at. Held at its natural width
            // the label cannot break, and a format added later makes the
            // segments narrower instead of breaking the word beside them.
            labelledRow("Format") {
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
                .labelsHidden()
            }
            if asksWhereItIsGoing {
                handoffNote
            }
            if choice.isVector {
                vectorNote
            } else {
                labelledRow("Scale") {
                    Picker("Scale", selection: $scale) {
                        Text("1×").tag(CGFloat(1))
                        Text("2×").tag(CGFloat(2))
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                if let size = exportedSize {
                    Text("\(Int(size.width * scale)) × \(Int(size.height * scale)) px")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if lossyFormat != nil {
                    qualityRow
                } else if weighedFormat != nil {
                    // The same line in the same place, minus the slider there
                    // is nothing to choose with. PNG is the format an icon is
                    // saved in, so "what will this weigh" is asked here more
                    // than anywhere else on the sheet.
                    sizeNote()
                }
                // Last in the block, exactly where it sits for SVG: an icon
                // drawn on a blank canvas can go out as a PNG with nothing
                // behind it too.
                if let backdrop {
                    backgroundRow(backdrop)
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
                                                    frameID: frameID, background: background,
                                                    using: sizer)
                    case .svg:
                        editorState.exportSVG(frameID: frameID, animated: carriesTheMotion,
                                              background: background)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(ExportSheetMetrics.padding)
        // Wide enough for the format row to hold its name and five buttons on
        // one line. At 320 the segments took every point there was and the word
        // beside them came out stacked two letters a line; the rest of the
        // sheet, the hand-off lines especially, reads better with the room too.
        .frame(width: ExportSheetMetrics.width)
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
        // A file with nothing behind it is a different file, so it is a
        // different number, whether it is shapes or pixels.
        .onChange(of: keepsBackground) {
            refreshVectorSize()
            refreshPictureSize()
        }
        // 2x is a different file, so it is a different number.
        .onChange(of: scale) { refreshPictureSize() }
        .onChange(of: qualityPercent) { refreshPictureSize() }
    }

    /// One row of the sheet. The row itself is `ExportSheetRow`, shared with
    /// the sheet a recording leaves through so the two cannot drift apart.
    @ViewBuilder
    private func labelledRow<Control: View>(_ name: String,
                                            @ViewBuilder control: () -> Control) -> some View {
        ExportSheetRow(name, control: control)
    }

    /// The quality to write at, and what the file weighs there.
    ///
    /// Two lines rather than one: the slider answers how much of the picture to
    /// keep, and the line under it answers what that is called and what it
    /// costs. The size is the whole reason the row exists, so it sits directly
    /// under the thing that changes it rather than in the corner of the sheet.
    @ViewBuilder private var qualityRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            labelledRow("Quality") {
                Slider(value: qualityBinding,
                       in: Double(ExportQuality.lowest)...Double(ExportQuality.highest),
                       step: Double(ExportQuality.step))
                    .accessibilityLabel("Quality")
                    .accessibilityValue(qualityVoice)
                Text("\(qualityPercent)%")
                    .monospacedDigit()
                    .frame(width: 38, alignment: .trailing)
            }
            sizeNote()
        }
    }

    /// What the file will weigh, said once for every answer on the sheet.
    ///
    /// Under the slider where there is one, and in exactly that place where
    /// there is not, so the eye looking for the size finds it in the same spot
    /// whichever format is picked.
    ///
    /// `icon` is what the vector block passes: everything it says wears a
    /// symbol, and a line with none in the middle of that list hangs out to the
    /// left of the lines above and below it. The words and the place are the
    /// same either way, which is the part that has to match.
    @ViewBuilder private func sizeNote(icon: String? = nil) -> some View {
        Group {
            if let icon {
                Label(sizeLine, systemImage: icon)
                    .labelStyle(.titleAndIcon)
            } else {
                Text(sizeLine)
            }
        }
            .font(.caption)
            .foregroundStyle(.secondary)
            // A number being replaced fades rather than blanking, so the
            // line never jumps about under a hand that is still moving.
            .opacity(weighing ? 0.45 : 1)
            .animation(.easeOut(duration: 0.12), value: weighing)
            .animation(.easeOut(duration: 0.12), value: pictureBytes)
            .animation(.easeOut(duration: 0.12), value: byteCount)
            .playtestControl(Self.sizeLabel, detail: sizeLine)
    }

    /// The name a walk finds the size line by. Steady, because the words on
    /// the line are the thing under test and change with every format, every
    /// scale and every tick of the background box.
    static let sizeLabel = "What it will weigh"

    /// What survives the trip to the chosen destination, and what does not.
    ///
    /// The crossed-out lines are the point of the whole sheet: you find out
    /// that a code host will strip the animation, or that a drawing in a page
    /// receives no clicks, while you can still do something about it.
    @ViewBuilder private var handoffNote: some View {
        if let target {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(SVGHandoff.lines(for: destination, in: target,
                                         flatImages: flatImages)) { line in
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
            // Directly under how big it was drawn, which is where a picture
            // format's size sits under its pixel size. The eye looking for
            // "what will this cost me" finds it in the same place whichever
            // of the five answers is picked.
            if saysWhatTheVectorWeighs {
                sizeNote(icon: "scalemass")
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
            if let backdrop {
                backgroundRow(backdrop)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Whether the canvas goes into the file, asked only when there is a
    /// canvas to leave out.
    ///
    /// An icon drawn on a blank canvas used to export with a white rectangle
    /// the size of the canvas behind it, which is invisible on a white page
    /// and a white box on every other one. It goes out see-through now, and
    /// this is where you say otherwise, before you save rather than after you
    /// open the file. The swatch is the colour that would go, so what the
    /// checkbox is talking about is a thing you can see rather than a word.
    /// One place the words live, so the walk that presses it and the sheet
    /// that shows it can never drift apart.
    static let backgroundLabel = "Include the background"

    @ViewBuilder private func backgroundRow(_ backdrop: SVGExport.Backdrop) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Toggle(Self.backgroundLabel, isOn: $keepsBackground)
                    .toggleStyle(.checkbox)
                    .playtestControl(Self.backgroundLabel,
                                     detail: keepsBackground
                                         ? "Export, the \(backdrop.color.hexString) canvas goes in"
                                         : "Export, nothing behind the drawing")
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(hex: backdrop.color.hexStringWithAlpha))
                    .frame(width: 14, height: 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 1)
                    )
                    .accessibilityHidden(true)
            }
            Text(keepsBackground
                 ? "The canvas colour is painted behind your drawing."
                 : "Nothing behind your drawing, so it sits on any colour.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
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
