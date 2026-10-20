import AppKit
import PhotonzCore
import PhotonzRender

/// What the video tools do in the running app (`docs/design/agent-mcp.md`,
/// slice 4).
///
/// Each one runs the edit a person makes: File > New Video, Add Media at
/// Playhead over the picked track, the blade, the trim handles, a bar dragged
/// along, the transition picker, Insert Title Page and the words typed into
/// it, Suggest Zooms, and the write the Export sheet ends in. Each lands
/// inside `asOneUndoStep`, so one Command Z takes back one thing the agent did.
@MainActor
enum AgentVideoWork {

    typealias Failure = AgentWork.Failure
    typealias Answer = AgentWork.Answer

    static func answer(_ request: AgentRequest) async throws -> Answer {
        switch request {
        case .newVideo(let spec):
            return try await newVideo(spec)
        case .addClip(let id, let source, let atMS, let track):
            let editor = try video(id)
            let url = try file(of: source)
            var landed: Placed?
            try await editor.agentStep {
                landed = try await addClip(url, to: editor, atMS: atMS, track: track)
            }
            return .json(landed)
        case .cut(let id, let atMS, let clip):
            return try cut(video(id), atMS: atMS, clip: clip)
        case .trim(let id, let clip, let from, let to, let ripple):
            return try trim(video(id), clip: clip, fromMS: from, toMS: to, ripple: ripple)
        case .moveClip(let id, let clip, let toMS, let track):
            return try moveClip(video(id), clip: clip, toMS: toMS, track: track)
        case .setTransition(let id, let atMS, let kind, let lengthMS):
            return try setTransition(video(id), atMS: atMS, kind: kind, lengthMS: lengthMS)
        case .addTitle(let id, let title):
            return try addTitle(video(id), title)
        case .listTitles(let id):
            let editor = try video(id)
            return .json(["titlePage": editor.titlePresetNames(.titlePage),
                          "nameCard": editor.titlePresetNames(.nameCard)])
        case .recommendedZooms(let id, let clip):
            return try recommendedZooms(video(id), clip: clip)
        case .applyZooms(let id, let clip):
            return try applyZooms(video(id), clip: clip)
        case .setPlayhead(let id, let atMS):
            let editor = try video(id)
            let length = editor.document?.documentDurationMS ?? 0
            guard atMS <= length else {
                throw Failure("The video is \(AgentContactSheet.label(ms: length)) long; seconds must be inside it.")
            }
            editor.moveDocumentPlayhead(toMS: atMS)
            return .json(["playheadSeconds": Double(editor.documentTimeMS) / 1000])
        case .exportVideo(let id, let path, let size, let quality):
            return try await exportVideo(AgentDocuments.editor(id).get(), path: path, size: size, quality: quality)
        default:
            throw Failure("That is not a video tool.")
        }
    }

    // MARK: Which document, which clip

    private static func video(_ id: String?) throws -> EditorState {
        let editor = try AgentDocuments.editor(id).get()
        let document = try AgentWork.document(of: editor)
        guard document.hasTime else {
            throw Failure("\(AgentWork.title(of: editor)) is a picture, not a video. new_video makes one.")
        }
        return editor
    }

    private static func clip(_ id: String, in editor: EditorState) throws -> (UUID, Layer) {
        guard let uuid = UUID(uuidString: id), let layer = editor.document?.layer(id: uuid), layer.time != nil else {
            throw Failure("There is no clip \(id). read_document lists each track's clips with their ids.")
        }
        return (uuid, layer)
    }

    private static func track(_ id: String?, in editor: EditorState) throws -> UUID? {
        guard let id else { return nil }
        guard let uuid = UUID(uuidString: id), editor.document?.track(id: uuid) != nil else {
            throw Failure("There is no track \(id). read_document lists the track ids.")
        }
        return uuid
    }

    /// The recording a source names, checked to be one.
    private static func file(of source: AgentClipSource) throws -> URL {
        let url: URL
        switch source {
        case .path(let path):
            url = URL(fileURLWithPath: path).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else { throw Failure("There is no file at \(path).") }
        case .history(let index):
            guard let coordinator = AgentWork.coordinator else {
                throw Failure("Photonz is still starting up. Try again in a moment.")
            }
            let entries = coordinator.capture.store.entries
            guard entries.indices.contains(index) else {
                throw Failure(entries.isEmpty ? "History is empty."
                              : "History has \(entries.count) items; historyIndex goes from 0 to \(entries.count - 1).")
            }
            url = entries[index].url.standardizedFileURL
        }
        guard MediaFiles.kind(of: url) == .recording else {
            throw Failure("\(url.lastPathComponent) is not a recording. A clip comes from a video file.")
        }
        return url
    }

    // MARK: Answers

    struct Placed: Encodable {
        let clip: String
        let name: String
        let track: String
        let inSeconds: Double
        let outSeconds: Double
        let durationSeconds: Double
    }

    private static func placed(_ id: UUID, in editor: EditorState) -> Placed? {
        guard let document = editor.document, let layer = document.layer(id: id), let time = layer.time else { return nil }
        return Placed(clip: id.uuidString, name: layer.name,
                      track: document.trackID(ofClip: id).flatMap { document.track(id: $0)?.name } ?? "",
                      inSeconds: seconds(time.inMS), outSeconds: seconds(time.outMS),
                      durationSeconds: seconds(document.documentDurationMS))
    }

    /// Exact, as read_document gives times, so a time handed back finds what
    /// it was read from.
    private static func seconds(_ ms: Int) -> Double { Double(ms) / 1000 }

    // MARK: A new video

    struct Made: Encodable {
        let video: AgentWork.Listing
        let clips: [Placed]
    }

    private static func newVideo(_ spec: AgentNewVideo) async throws -> Answer {
        guard let coordinator = AgentWork.coordinator else {
            throw Failure("Photonz is still starting up. Try again in a moment.")
        }
        let urls = try spec.clips.map(file(of:))
        // New Sequence from Clip: the frame is the first clip's.
        var size = spec.size ?? BlankVideo.defaultPreset.size
        if spec.size == nil, let first = urls.first {
            guard let movie = await MovieLibrary.shared.movie(at: first) else {
                throw Failure("\(first.lastPathComponent) would not open as a recording.")
            }
            size = movie.pixelSize
        }
        // With clips the video is as long as they are: it starts as short as
        // a video can be and grows as each lands.
        let length = urls.isEmpty ? (spec.lengthMS ?? BlankVideo.lengthMS(seconds: BlankVideo.defaultLengthSeconds))
                                  : BlankVideo.shortestLengthMS
        let before = Set(AgentDocuments.open.compactMap(\.agentID))
        coordinator.newBlankVideoWindow(size: BlankVideo.normalized(size), lengthMS: length)
        let deadline = Date().addingTimeInterval(AgentWork.openPatienceSeconds)
        var made: EditorState?
        while made == nil, Date() < deadline {
            made = AgentDocuments.open.first { !before.contains($0.agentID ?? "") && $0.document != nil }
            if made == nil { try await Task.sleep(for: .milliseconds(100)) }
        }
        guard let editor = made else {
            throw Failure("The new video did not open within \(Int(AgentWork.openPatienceSeconds)) seconds.")
        }
        var clips: [Placed] = []
        if !urls.isEmpty {
            try await editor.agentStep {
                for url in urls {
                    if let landed = try await addClip(url, to: editor, atMS: nil, track: nil) { clips.append(landed) }
                }
            }
            editor.moveDocumentPlayhead(toMS: 0)
        }
        return .json(Made(video: AgentWork.listing(editor, front: AgentDocuments.front === editor), clips: clips))
    }

    // MARK: Clips

    /// Add Media at Playhead over the track, with the playhead where the clip
    /// goes and the track picked, which is what the menu row reads.
    private static func addClip(_ url: URL, to editor: EditorState, atMS: Int?, track: String?) async throws -> Placed? {
        guard let document = editor.document else { throw Failure("That window has no document in it yet.") }
        guard let trackID = try self.track(track, in: editor) ?? document.agentDefaultPictureTrack else {
            throw Failure("This video has no picture track that is not locked.")
        }
        guard document.track(id: trackID)?.kind == .video else {
            throw Failure("That is a sound track; a recording goes on a picture track.")
        }
        let at = atMS ?? document.endOfTrackMS(trackID)
        if at > document.documentDurationMS {
            throw Failure("The video is \(AgentContactSheet.label(ms: document.documentDurationMS)) long; a clip starts inside it or at its end.")
        }
        editor.selectedTrackIDs = [trackID]
        guard let landed = await editor.placeTimelineFile(url, atMS: at, onTrack: trackID) else {
            throw Failure("\(url.lastPathComponent) could not go on the timeline there.")
        }
        editor.moveDocumentPlayhead(toMS: at)
        return placed(landed, in: editor)
    }

    private static func cut(_ editor: EditorState, atMS: Int, clip: String?) throws -> Answer {
        guard let document = editor.document else { throw Failure("That window has no document in it yet.") }
        let id: UUID
        if let clip {
            id = try self.clip(clip, in: editor).0
        } else {
            guard let under = document.agentClipUnder(ms: atMS) else {
                throw Failure("There is no clip at \(AgentContactSheet.label(ms: atMS)) to cut.")
            }
            id = under
        }
        guard let time = document.layer(id: id)?.time, time.inMS < atMS, atMS < time.outMS else {
            throw Failure("seconds must be inside the clip, between its in and out; read_document gives them.")
        }
        editor.moveDocumentPlayhead(toMS: atMS)
        editor.selectLayer(id)
        guard editor.canSplitClipAtPlayhead else {
            throw Failure("The clip cannot be cut there: it is already cut there, or its track is locked.")
        }
        editor.asOneUndoStep { editor.splitClipAtPlayhead() }
        let pieces = editor.document?.layer(id: id)?.clipPieces?.count ?? 1
        return .json(Cut(clip: id.uuidString, pieces: pieces, cutAtSeconds: seconds(atMS)))
    }

    struct Cut: Encodable {
        let clip: String
        let pieces: Int
        let cutAtSeconds: Double
    }

    private static func trim(_ editor: EditorState, clip: String, fromMS: Int?, toMS: Int?, ripple: Bool) throws -> Answer {
        let (id, _) = try self.clip(clip, in: editor)
        var refusal: String?
        editor.pauseDocument()
        editor.asOneUndoStep {
            editor.perform { refusal = $0.agentTrim(id, keepFromMS: fromMS, keepToMS: toMS, ripple: ripple) }
        }
        if let refusal {
            throw Failure(refusal)
        }
        editor.selectLayer(id)
        editor.documentMomentChanged()
        return .json(placed(id, in: editor))
    }

    private static func moveClip(_ editor: EditorState, clip: String, toMS: Int?, track: String?) throws -> Answer {
        let (id, layer) = try self.clip(clip, in: editor)
        guard let document = editor.document, let time = layer.time else { throw Failure("That clip has no time.") }
        let target = try self.track(track, in: editor) ?? document.trackID(ofClip: id)
        let start = toMS ?? time.inMS
        if let target {
            guard let kind = document.track(id: target)?.kind, kind == layer.clipTrackKind else {
                throw Failure("That track takes \(layer.clipTrackKind == .video ? "sound" : "pictures"), not this clip.")
            }
            if let inTheWay = document.agentClipInTheWay(of: id, span: start..<(start + time.lengthMS), onTrack: target) {
                let name = document.layer(id: inTheWay)?.name ?? "another clip"
                throw Failure("It would land over \(name). Move or trim that first, or pick another time or track.")
            }
        }
        if editor.isClipLocked(id) { throw Failure("\(layer.name) is on a locked track.") }
        editor.pauseDocument()
        editor.asOneUndoStep {
            editor.perform { document in
                if let target, document.trackID(ofClip: id) != target { _ = document.moveClip(id, toTrack: target) }
                _ = document.moveClip(id, toInMS: start)
            }
        }
        editor.selectLayer(id)
        editor.documentMomentChanged()
        return .json(placed(id, in: editor))
    }

    // MARK: Transitions

    struct Transitioned: Encodable {
        let atSeconds: Double
        let kind: String
        let lengthSeconds: Double?
    }

    private static func setTransition(_ editor: EditorState, atMS: Int, kind: ClipTransitionKind?,
                                      lengthMS: Int?) throws -> Answer {
        guard Experiments.shared.transitionsAtACutEnabled else { throw Failure("This release has no transitions at a cut.") }
        guard let document = editor.document, let cut = document.agentCut(nearMS: atMS) else {
            let cuts = editor.document?.transitionCuts().map { seconds($0.atMS) } ?? []
            throw Failure(cuts.isEmpty ? "This video has no cuts: a cut is where two clips meet on a track, or where cut makes one."
                                       : "There is no cut at that time. The cuts are at \(cuts.map { "\($0)" }.joined(separator: ", ")) seconds.")
        }
        if let kind, cut.cut.fitted(kind) == nil {
            let fits = ClipTransitionKind.allCases.filter { cut.cut.fitted($0) != nil }.map(\.rawValue)
            throw Failure("\(kind.rawValue) needs spare frames either side of this cut, and it has none. It can take "
                          + (fits.isEmpty ? "no transition." : fits.joined(separator: ", ") + "."))
        }
        editor.asOneUndoStep {
            editor.setTransition(kind, at: cut.place)
            guard let lengthMS, let now = editor.document?.documentCut(at: cut.place),
                  let existing = now.cut.transition else { return }
            let length = min(max(ClipTransition.shortestMS, lengthMS), now.cut.longestMS(for: existing))
            if length != existing.lengthMS {
                editor.perform { $0.setTransition(existing.withLength(length), at: cut.place) }
            }
        }
        let landed = editor.document?.documentCut(at: cut.place)?.cut.transition
        return .json(Transitioned(atSeconds: seconds(cut.atMS), kind: landed?.kind.rawValue ?? "none",
                                  lengthSeconds: landed.map { seconds($0.lengthMS) }))
    }

    // MARK: Titles

    struct Titled: Encodable {
        let title: String
        let style: String
        /// Where it landed: the track asked for when it was free there, else
        /// a new one over it, since a title never covers what is on a track.
        let track: String
        let inSeconds: Double
        let outSeconds: Double
        let parts: [Part]
        /// Lines of the style's own sample words nobody worded, taken out.
        let sampleLinesTakenOut: [String]?
        let durationSeconds: Double
    }

    struct Part: Encodable {
        let layer: String
        let name: String
        let text: String
    }

    private static func addTitle(_ editor: EditorState, _ spec: AgentTitle) throws -> Answer {
        guard editor.canInsertTitle else { throw Failure("This release has no title pages.") }
        let names = editor.titlePresetNames(spec.kind)
        let wanted = spec.style ?? names.first ?? ""
        guard let preset = titlePreset(spec.kind, named: wanted) else {
            throw Failure("There is no \(spec.kind.name) style called \(wanted). The styles are \(names.joined(separator: ", ")).")
        }
        var beforeClip: UUID?
        if let clip = spec.beforeClip {
            let (id, _) = try self.clip(clip, in: editor)
            guard editor.document?.canInsertTitle(inFrontOf: id) == true else {
                throw Failure("A title page goes in front of a clip or another page on an unlocked picture track, and that is not one.")
            }
            beforeClip = id
        }
        let trackID = try track(spec.track, in: editor)
        let before = Set(editor.document?.layers.map(\.id) ?? [])
        var refusal: String?
        var removed: [String] = []
        editor.agentIsRunning = true
        defer { editor.agentIsRunning = false }
        editor.asOneUndoStep {
            if let beforeClip {
                editor.moveDocumentPlayhead(toMS: editor.document?.layer(id: beforeClip)?.time?.inMS ?? 0)
                if editor.document?.canInsertTitle(beforeClip: beforeClip) == true {
                    // A recording: the person's own Insert Title Page with it picked.
                    editor.selectLayer(beforeClip)
                    guard editor.insertTitleBeforeClip(preset) else {
                        refusal = "That style is not a page that goes in front of a clip."
                        return
                    }
                } else {
                    // Another page: the same insert, in front of it.
                    let join = DefaultTransitionStore.shared.kind
                    let blurs = Experiments.shared.motionBlurEnabled
                    var inserted: InsertedTitle?
                    editor.pauseDocument()
                    editor.perform { inserted = $0.insertTitle(preset, inFrontOf: beforeClip, join: join, motionBlur: blurs) }
                    guard let inserted else {
                        refusal = "That style is not a page that goes in front of a clip."
                        return
                    }
                    editor.selectLayer(inserted.layerID)
                }
            } else {
                if let at = spec.atMS { editor.moveDocumentPlayhead(toMS: at) }
                // Over the picture at the playhead, not in front of a clip
                // starting there: the agent named no clip.
                editor.selectLayer(nil)
                editor.insertTitle(preset, onTrack: trackID)
            }
            guard let title = editor.document?.layers.first(where: { !before.contains($0.id) && $0.isPlacedInTime }) else {
                refusal = "Photonz could not insert that title there."
                return
            }
            editor.typeInOnceShown = nil
            removed = reword(title: title.id, kind: spec.kind, text: spec.text, subtitle: spec.subtitle, in: editor)
        }
        if let refusal { throw Failure(refusal) }
        guard let document = editor.document,
              let title = document.layers.first(where: { !before.contains($0.id) && $0.isPlacedInTime }),
              let time = title.time else {
            throw Failure("Photonz could not insert that title there.")
        }
        let parts = title.selfAndDescendants.compactMap { layer -> Part? in
            layer.text.map { Part(layer: layer.id.uuidString, name: layer.name, text: $0.string) }
        }
        return .json(Titled(title: title.id.uuidString, style: wanted,
                            track: document.trackID(ofClip: title.id).flatMap { document.track(id: $0)?.name } ?? "",
                            inSeconds: seconds(time.inMS),
                            outSeconds: seconds(time.outMS), parts: parts,
                            sampleLinesTakenOut: removed.isEmpty ? nil : removed,
                            durationSeconds: seconds(document.documentDurationMS)))
    }

    private static func titlePreset(_ kind: TitleKind, named name: String) -> TitlePreset? {
        if let own = TitlePresetStore.shared.presets(of: kind).first(where: { $0.name == name }) { return .saved(own) }
        return TitlePreset.builtIn(of: kind, movingBackdrops: Experiments.shared.titleBackgroundsEnabled)
            .first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// The words typed into a title's lines, measured and laid out the way
    /// typing them does (`commitTextEdit`, then the title laid out again so
    /// its backing follows). The main line takes `text`; the second line (a
    /// subtitle or role, else a kicker over the title) takes `subtitle`. Any
    /// line still holding the style's sample words ("A short line about it",
    /// "Chapter 2") goes, so nothing on screen says what the agent did not.
    private static func reword(title: UUID, kind: TitleKind, text: String, subtitle: String?,
                               in editor: EditorState) -> [String] {
        guard let document = editor.document, let layer = document.layer(id: title) else { return [] }
        let texts = layer.selfAndDescendants.filter { $0.text != nil }
        let roles = Dictionary(
            (document.titleRecipe(layerID: title)?.design.parts ?? []).map {
                (String($0.path.split(separator: "/").last ?? Substring($0.path)), $0.role)
            }, uniquingKeysWith: { first, _ in first })
        func role(_ part: Layer) -> TitlePartRole? {
            roles[part.name] ?? ["Title": .headline, "Name": .headline, "Subtitle": .subtitle, "Role": .subtitle,
                                 "Kicker": .kicker][part.name]
        }
        let main = texts.first { role($0) == .headline } ?? texts.first
        let rest = texts.filter { $0.id != main?.id }
        let second = rest.first { role($0) == .subtitle } ?? rest.first { role($0) == .kicker }
        let words = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let main { reword(main.id, to: text, in: editor) }
        var removed: [String] = []
        for part in rest {
            if part.id == second?.id, !words.isEmpty {
                reword(part.id, to: words, in: editor)
            } else {
                editor.perform { $0.removeLayer(id: part.id) }
                removed.append(part.name)
            }
        }
        editor.perform { _ = $0.relayOutTitle(layerID: title) }
        return removed
    }

    /// One text layer's words changed, its box re-measured the way the inline
    /// editor measures: a box someone made roomier than its words keeps its
    /// room (a centred title line stays centred), one hugging its words
    /// re-hugs them.
    static func reword(_ id: UUID, to string: String, in editor: EditorState) {
        guard let document = editor.document, let layer = document.layer(id: id), var content = layer.text,
              let canvasFrame = document.canvasFrame(of: id) else { return }
        content.string = string
        let room = TextBlockMetrics.roomyBox(for: layer.text ?? content, frame: layer.frame)
        let size = TextBlockMetrics.frameSize(for: content, maxWidth: room.width ?? .greatestFiniteMagnitude,
                                              roomyWidth: room.width, roomyHeight: room.height,
                                              hugsShortWords: Experiments.shared.placementEnabled)
        editor.perform { $0.commitTextEdit(id: id, content: content, canvasFrame: CGRect(origin: canvasFrame.origin, size: size)) }
    }

    // MARK: Zooms

    struct Zoom: Encodable {
        let fromSeconds: Double
        let toSeconds: Double
        let percent: Int
    }

    struct ClipZooms: Encodable {
        let clip: String
        let name: String
        let clicks: Int
        let has: Int
        let recommended: [Zoom]
        let note: String?
    }

    /// The recordings a zoom call is about: the one named, or every one on
    /// the timeline in time order.
    private static func recordings(_ editor: EditorState, clip: String?) throws -> [Layer] {
        guard let document = editor.document else { return [] }
        if let clip {
            let (_, layer) = try self.clip(clip, in: editor)
            guard layer.movie != nil else { throw Failure("\(layer.name) is not a recording; zooms go on recordings.") }
            return [layer]
        }
        return document.timelineClipLayers.filter { $0.movie != nil }
            .sorted { ($0.time?.inMS ?? 0) < ($1.time?.inMS ?? 0) }
    }

    private static func recommendedZooms(_ editor: EditorState, clip: String?) throws -> Answer {
        guard editor.canWorkWithZooms else { throw Failure("This release has no zooms.") }
        guard let document = editor.document else { return .json([ClipZooms]()) }
        let listed = try recordings(editor, clip: clip).map { layer -> ClipZooms in
            let clicks = editor.clicks(ofClip: layer.id)
            var trial = document
            let zooms = trial.addSuggestedZooms(toClip: layer.id, clicks: clicks)
            let placed = trial.layer(id: layer.id) ?? layer
            let note: String? = clicks.isEmpty ? "No clicks were kept while this was recorded, so nothing is recommended."
                : zooms.isEmpty ? "Every click already has a zoom, or none has room for one." : nil
            return ClipZooms(clip: layer.id.uuidString, name: layer.name, clicks: clicks.count,
                             has: layer.zooms?.count ?? 0,
                             recommended: zooms.map { zoom in
                                 Zoom(fromSeconds: seconds(onTheVideo(zoom.startMS, of: placed)),
                                      toSeconds: seconds(onTheVideo(zoom.endMS, of: placed)),
                                      percent: Int((zoom.scale * 100).rounded()))
                             }, note: note)
        }
        return .json(listed)
    }

    struct Zoomed: Encodable {
        /// Zooms put on, by clip id.
        let added: [String: Int]
        let total: Int
    }

    /// A moment of a clip's recording on the video's clock. A zoom may ease
    /// out past the last frame the clip plays (its recording runs on), which
    /// the clip never shows, so that end is the clip's own end.
    private static func onTheVideo(_ sourceMS: Int, of clip: Layer) -> Int {
        if let played = clip.timelineMS(ofClickAtSourceMS: sourceMS) { return played }
        guard let time = clip.time else { return sourceMS }
        return min(max(time.inMS + sourceMS - time.sourceInMS, time.inMS), time.outMS)
    }

    private static func applyZooms(_ editor: EditorState, clip: String?) throws -> Answer {
        guard editor.canWorkWithZooms else { throw Failure("This release has no zooms.") }
        let targets = try recordings(editor, clip: clip)
        var added: [String: Int] = [:]
        editor.asOneUndoStep {
            for layer in targets where editor.canSuggestZooms(onClip: layer.id) {
                let had = editor.document?.layer(id: layer.id)?.zooms?.count ?? 0
                editor.suggestZooms(onClip: layer.id)
                let now = editor.document?.layer(id: layer.id)?.zooms?.count ?? 0
                if now > had { added[layer.id.uuidString] = now - had }
            }
        }
        guard !added.isEmpty else {
            throw Failure(clip == nil ? "No recording on the timeline has a zoom to recommend: they kept no clicks, or every click has one."
                                      : "That clip has no zoom to recommend: it kept no clicks, or every click has one.")
        }
        return .json(Zoomed(added: added, total: added.values.reduce(0, +)))
    }

    // MARK: Export

    struct Exported: Encodable {
        let path: String
        let format: String
        let bytes: Int
        let width: Int
        let height: Int
        let seconds: Double
    }

    private static func exportVideo(_ editor: EditorState, path: String, size: VideoExportSize,
                                    quality: VideoExportQuality) async throws -> Answer {
        let document = try AgentWork.document(of: editor)
        guard document.hasTime else {
            throw Failure("\(AgentWork.title(of: editor)) is a picture; export it as png or svg.")
        }
        let url = URL(fileURLWithPath: path)
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path, isDirectory: &isFolder),
              isFolder.boolValue else {
            throw Failure("There is no folder at \(url.deletingLastPathComponent().path) to write into.")
        }
        guard editor.videoExport == nil else { throw Failure("This video is already being exported. Try again when it is done.") }
        editor.pauseDocument()
        try await editor.writeVideo(format: .mp4, quality: quality, size: size, to: url)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        let plan = DocumentVideoExport.plan(range: document.exportRangeMS(.whole), canvasSize: document.canvasSize,
                                            format: .mp4, quality: quality, size: size)
        return .json(Exported(path: url.path, format: "mp4", bytes: bytes,
                              width: Int(plan.size.width), height: Int(plan.size.height),
                              seconds: seconds(document.documentDurationMS)))
    }
}

extension EditorState {
    /// An agent's call that awaits work in the middle, folded into one undo
    /// step, its refusal carried out of the fold.
    func agentStep(_ body: () async throws -> Void) async throws {
        var thrown: Error?
        await asOneUndoStepAwaiting {
            do { try await body() } catch { thrown = error }
        }
        if let thrown { throw thrown }
    }
}
