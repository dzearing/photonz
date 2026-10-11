import AppKit
import Foundation
import PhotonzCore

// A few knobs restyle a title (`TitleRestyle.swift`,
// `docs/design/video-titles-polish.md`, "What the person sees"). The panel's
// Title section turns the knobs of the picked title, or of the title a picked
// part sits in; its Part section changes one part's in, hold and out. Each
// change is one undo step, and anything that changes how the title moves plays
// its in again so the change is seen, not imagined.
extension EditorState {

    // MARK: Reading

    /// The title the panel's Title section speaks for: the picked title, or
    /// the one the picked part, or the words open for typing, sit in.
    var titleInHandID: UUID? {
        guard Experiments.shared.titleRestyleEnabled, documentHasTime, let document else { return nil }
        for id in [selectedLayerID, editingTextLayerID].compactMap({ $0 }) {
            if let title = document.titleLayerID(containing: id) { return title }
        }
        return nil
    }

    var titleRecipeInHand: TitleRecipe? {
        titleInHandID.flatMap { document?.titleRecipe(layerID: $0) }
    }

    /// The picked part of a title: which title, where in its design, and the
    /// piece itself. Nil while the title as a whole is picked.
    var titlePartInHand: (titleID: UUID, index: Int, piece: Layer)? {
        guard let titleID = titleInHandID, let document, let title = document.layer(id: titleID),
              let recipe = title.group?.titleRecipe else { return nil }
        for id in [editingTextLayerID, selectedLayerID].compactMap({ $0 }) where id != titleID {
            for (index, part) in recipe.design.parts.enumerated() {
                if let piece = TitleDesign.find(part.path, in: title), piece.id == id {
                    return (titleID, index, piece)
                }
            }
        }
        return nil
    }

    /// Every part of the title in hand, by what it is for, for the Title
    /// section's Part menu.
    var titlePartsInHand: [(index: Int, name: String)] {
        guard let recipe = titleRecipeInHand else { return [] }
        var seen: [String: Int] = [:]
        return recipe.design.parts.enumerated().map { index, part in
            let base = Self.partName(part)
            seen[base, default: 0] += 1
            let count = recipe.design.parts.filter { Self.partName($0) == base }.count
            return (index, count > 1 ? "\(base) \(seen[base] ?? 1)" : base)
        }
    }

    /// What the panel calls a part: what it is for.
    static func partName(_ part: TitlePart) -> String {
        switch part.role {
        case .background: "Background"
        case .headline: "Headline"
        case .subtitle: "Subtitle"
        case .kicker: "Kicker"
        case .accent: "Accent"
        }
    }

    /// Whether the title in hand could be glass: something is on screen under it.
    var titleCanBeGlass: Bool {
        guard let id = titleInHandID, let document else { return false }
        return document.titleRecipe(layerID: id)?.background == .glass || document.titleHasPictureUnder(id)
    }

    // MARK: The knobs

    /// One undo step that turns knobs on the title in hand. `replaying` plays
    /// its in again afterwards, for a change to how it moves.
    func restyleTitleInHand(replaying: Bool = false, _ change: @escaping (inout TitleRecipe) -> Void) {
        guard let id = titleInHandID, var probe = document, probe.restyleTitle(layerID: id, change) else { return }
        discardDragPreview()
        perform { $0.restyleTitle(layerID: id, change) }
        if replaying { replayTitle(id) } else { documentMomentChanged() }
    }

    func setTitleTheme(_ theme: TitleTheme) {
        restyleTitleInHand { $0.theme = theme }
    }

    func setTitleFonts(_ fonts: TitleFontPair) {
        restyleTitleInHand { $0.fonts = fonts }
    }

    func setTitleEnergy(_ energy: TitleEnergy) {
        restyleTitleInHand(replaying: true) { $0.energy = energy }
    }

    func setTitleBackground(_ kind: TitleBackgroundKind) {
        restyleTitleInHand {
            $0.background = kind
            $0.showsBackground = true
        }
    }

    func setTitleBackgroundShown(_ shown: Bool) {
        restyleTitleInHand { $0.showsBackground = shown }
    }

    /// The Intensity slider moving: drawn, not recorded, until it lets go.
    func previewTitleIntensity(_ percent: Double) {
        guard let id = titleInHandID, var doc = document else { return }
        doc.restyleTitle(layerID: id) { $0.intensity = percent }
        titleIntensityPreview = percent
        submit(doc.drawn(atTimeMS: documentTimeMS))
    }

    /// The Intensity slider let go, or a number typed: one undo step.
    func setTitleIntensity(_ percent: Double) {
        titleIntensityPreview = nil
        restyleTitleInHand { $0.intensity = percent }
        rerender()
    }

    /// Two or three colours out of the recording under the title, as a theme.
    func setTitleThemeFromRecording() {
        guard let id = titleInHandID, let document else { return }
        Task { @MainActor [weak self] in
            guard let self, let frame = await self.recordingFrame(under: id, in: document) else { return }
            let theme = TitleTheme.sampled(from: Self.samples(of: frame))
            guard self.titleInHandID == id else { return }
            self.setTitleTheme(theme)
        }
    }

    // MARK: A part

    /// Change the picked part: its in, its hold or its out.
    func editTitlePart(replaying: Bool = true, _ change: @escaping (inout TitlePart) -> Void) {
        guard let part = titlePartInHand else { return }
        let index = part.index
        restyleTitleInHand(replaying: replaying) { recipe in
            guard recipe.design.parts.indices.contains(index) else { return }
            change(&recipe.design.parts[index])
        }
    }

    /// Pick a part of the title in hand from the Title section's Part menu,
    /// the way double clicking it on the canvas does.
    func pickTitlePart(_ index: Int) {
        guard let id = titleInHandID, let title = document?.layer(id: id),
              let recipe = title.group?.titleRecipe, recipe.design.parts.indices.contains(index),
              let piece = TitleDesign.find(recipe.design.parts[index].path, in: title) else { return }
        selectLayer(piece.id, inGroup: id)
    }

    /// Back up to the whole title from one of its parts.
    func pickWholeTitle() {
        guard let id = titleInHandID else { return }
        selectLayer(id, inGroup: nil)
    }

    // MARK: Replay

    /// Play the title's in from its first frame and stop once every part has
    /// arrived, a little after.
    func replayTitle(_ id: UUID? = nil) {
        guard let id = id ?? titleInHandID, let document, let time = document.layer(id: id)?.time else { return }
        let arrived = document.titleArrivalMS(layerID: id)
        pauseDocument()
        scrubDocument(toMS: time.inMS)
        documentPlaybackStopMS = min(time.inMS + arrived + 350, max(time.inMS, time.outMS - 1))
        playDocument()
        if !isDocumentPlaying { documentPlaybackStopMS = nil }
    }

    /// Words typed into a title: lay it out again with the words in the same
    /// step, then, after a short pause, play its in again.
    func replayTitleAfterTyping(_ id: UUID) {
        titleReplayAfterTyping?.cancel()
        titleReplayAfterTyping = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self, self.editingTextLayerID == nil,
                  self.document?.layer(id: id) != nil else { return }
            self.replayTitle(id)
        }
    }

    // MARK: The recording's own frame

    /// A frame of the recording under a title (or the first recording in the
    /// document, for a title that opens it), small.
    func recordingFrame(under id: UUID?, in document: PhotonzDocument, width: CGFloat = 320) async -> CGImage? {
        let title = id.flatMap { document.layer(id: $0)?.time }
        let clips = document.allLayers.filter { $0.movie != nil && $0.time != nil }
            .sorted { ($0.time?.inMS ?? 0) < ($1.time?.inMS ?? 0) }
        let under = clips.first { clip in
            guard let theirs = clip.time, let title else { return false }
            return theirs.inMS <= title.inMS && theirs.outMS > title.inMS
        } ?? clips.first
        guard let clip = under, let movie = clip.movie, let time = clip.time,
              let url = MovieLibrary.shared.urls(in: document)[movie.id] else { return nil }
        let offset = max(0, (title?.inMS ?? time.inMS) - time.inMS)
        let height = (width * movie.pixelSize.height / max(1, movie.pixelSize.width)).rounded()
        return await MovieDecoder.shared.frame(of: movie, at: url, sourceMS: time.sourceInMS + offset,
                                               size: CGSize(width: width, height: max(1, height)))
    }

    /// A frame's colours, a few hundred of them, for a theme to be made of.
    static func samples(of image: CGImage) -> [RGBA] {
        let width = 24, height = 14
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return [] }
        return stride(from: 0, to: bytes.count, by: 4).map { at in
            RGBA(r: Double(bytes[at]) / 255, g: Double(bytes[at + 1]) / 255, b: Double(bytes[at + 2]) / 255)
        }
    }

    // MARK: Library tiles that play

    /// The recording's first frame, filed for the Library's title tiles to be
    /// pictured over where their style uses the recording. Nil until it has
    /// been read, and in a document with no recording.
    var titleTileRecording: ImageRef? {
        guard Experiments.shared.titleRestyleEnabled, let document else { return nil }
        guard let movie = document.allLayers.first(where: { $0.movie != nil })?.movie else { return nil }
        if let filed = titleTileRecordingFrame, filed.movieID == movie.id { return filed.ref }
        guard titleTileRecordingReading != movie.id else { return nil }
        titleTileRecordingReading = movie.id
        let doc = document
        Task { @MainActor [weak self] in
            guard let self, let frame = await self.recordingFrame(under: nil, in: doc, width: 640) else { return }
            let ref = self.store.register(frame)
            self.titleTileRecordingFrame = (movie.id, ref)
        }
        return nil
    }

    /// A preset's tile playing, `pixelsWide` across: its in, a hold, its way
    /// off (`TitlePreset.reel`), drawn once off the main thread and kept. Nil
    /// until it has been.
    func titlePresetReel(_ preset: TitlePreset, pixelsWide: CGFloat) -> VideoKit.PlayedReel? {
        guard let frame = document?.canvasSize, frame.width > 0, frame.height > 0 else { return nil }
        let width = max(1, pixelsWide.rounded())
        let recording = titleTileRecording
        let own = if case .saved(let saved) = preset { saved.hashValue } else { 0 }
        let key = "\(preset.id)|\(Int(frame.width))x\(Int(frame.height))|\(Int(width))|\(own)|"
            + (recording?.id.uuidString ?? "")
        if let reel = titlePresetReels[key] { return reel }
        guard !titlePresetReelsInFlight.contains(key) else { return nil }
        titlePresetReelsInFlight.insert(key)
        let renderer = previewRenderer
        let store = store
        Task { @MainActor [weak self] in
            let reel = await Task.detached(priority: .utility) { () -> VideoKit.PlayedReel? in
                guard let drawn = preset.reel(frame: frame, width: width, recording: recording) else { return nil }
                let frames = drawn.pictures.compactMap { renderer.render($0, store: store) }
                guard frames.count == drawn.pictures.count else { return nil }
                return VideoKit.PlayedReel(frames: frames, keyTimes: drawn.keyTimes,
                                           lapSeconds: Double(drawn.lapMS) / 1000)
            }.value
            guard let self else { return }
            self.titlePresetReelsInFlight.remove(key)
            guard let reel else { return }
            // A few tiles' worth: one played reel is some forty pictures.
            if self.titlePresetReels.count >= 8 { self.titlePresetReels.removeAll() }
            self.titlePresetReels[key] = reel
        }
        return nil
    }
}
