import AppKit
import CoreText
import PhotonzCore
import PhotonzRender

/// What each agent tool does in the running app (`docs/design/agent-mcp.md`).
///
/// Every tool here goes through what the app already runs for a person: the
/// same open door as File > Open and History, the same renderer as the canvas
/// and Export, the same frames as a video export, the same undo as Edit > Undo.
/// Pictures are drawn offscreen, so none of it needs the screen.
@MainActor
enum AgentWork {

    struct Failure: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }

    struct Answer {
        var content: [AgentContent]
        var isError = false

        static func failure(_ failure: Failure) -> Answer { Answer(content: [.text(failure.message)], isError: true) }
        static func json(_ value: some Encodable) -> Answer {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let data = (try? encoder.encode(value)) ?? Data("null".utf8)
            return Answer(content: [.text(String(decoding: data, as: UTF8.self))])
        }
    }

    static weak var coordinator: AppCoordinator?

    static func run(_ request: AgentRequest) async -> Answer {
        do {
            return try await answer(request)
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(Failure("Photonz could not do that: \(error.localizedDescription)"))
        }
    }

    private static func answer(_ request: AgentRequest) async throws -> Answer {
        switch request {
        case .listDocuments:
            return .json(AgentDocuments.open.enumerated().map { index, editor in listing(editor, front: index == 0) })
        case .listHistory(let limit):
            return try listHistory(limit: limit)
        case .openDocument(let target):
            return try await open(target)
        case .readDocument(let id):
            let editor = try AgentDocuments.editor(id).get()
            let document = try document(of: editor)
            let read = AgentDocumentRead.make(document, context: context(of: editor))
            return Answer(content: [.text(String(decoding: try read.encoded(), as: UTF8.self))])
        case .renderPicture(let id, let layer, let region, let maxSize):
            let editor = try AgentDocuments.editor(id).get()
            return try await renderPicture(editor, layer: layer, region: region, maxSize: maxSize)
        case .videoFrame(let id, let atMS, let region, let maxSize):
            let editor = try AgentDocuments.editor(id).get()
            return try await videoFrame(editor, atMS: atMS, region: region, maxSize: maxSize)
        case .contactSheet(let id, let fromMS, let toMS, let count, let columns, let cellWidth):
            let editor = try AgentDocuments.editor(id).get()
            return try await contactSheet(editor, fromMS: fromMS, toMS: toMS, count: count,
                                          columns: columns, cellWidth: cellWidth)
        case .undo(let id, let steps):
            return try step(AgentDocuments.editor(id).get(), steps: steps, back: true)
        case .redo(let id, let steps):
            return try step(AgentDocuments.editor(id).get(), steps: steps, back: false)
        case .listCommands(let id, let area, let readyOnly):
            return try listCommands(AgentDocuments.editor(id).get(), area: area, readyOnly: readyOnly)
        case .runCommand(let id, let call):
            return try await runCommand(AgentDocuments.editor(id).get(), call)
        case .newPicture, .addShape, .addPath, .addText, .setLayer, .findElements,
             .addMeasurement, .listComponents, .placeComponent, .export:
            return try await AgentDrawingWork.answer(request)
        }
    }

    // MARK: Documents

    struct Listing: Encodable {
        let id: String
        let title: String
        let file: String?
        let kind: String
        let width: Double
        let height: Double
        let durationSeconds: Double?
        let front: Bool
        let canUndo: Bool
        let canRedo: Bool
    }

    static func title(of editor: EditorState) -> String {
        (editor.documentURL ?? editor.openedFileURL ?? editor.recordingURL)?.lastPathComponent ?? editor.untitledName
    }

    private static func file(of editor: EditorState) -> String? {
        (editor.documentURL ?? editor.openedFileURL ?? editor.recordingURL)?.path
    }

    static func listing(_ editor: EditorState, front: Bool) -> Listing {
        let document = editor.document
        let hasTime = document?.hasTime ?? false
        return Listing(id: editor.agentID ?? "?", title: title(of: editor), file: file(of: editor),
                       kind: hasTime ? "video" : "picture",
                       width: Double(document?.canvasSize.width ?? 0), height: Double(document?.canvasSize.height ?? 0),
                       durationSeconds: hasTime ? Double(document?.documentDurationMS ?? 0) / 1000 : nil,
                       front: front, canUndo: editor.canUndo, canRedo: editor.canRedo)
    }

    static func document(of editor: EditorState) throws -> PhotonzDocument {
        guard let document = editor.document else { throw Failure("That window has no document in it yet.") }
        return document
    }

    private static func context(of editor: EditorState) -> AgentDocumentRead.Context {
        AgentDocumentRead.Context(id: editor.agentID ?? "?", title: title(of: editor), file: file(of: editor),
                                  playheadMS: editor.documentTimeMS,
                                  canUndo: editor.canUndo, canRedo: editor.canRedo)
    }

    struct HistoryItem: Encodable {
        let index: Int
        let name: String
        let file: String
        let kind: String
        let taken: String
    }

    private static func listHistory(limit: Int) throws -> Answer {
        guard let coordinator else { throw Failure("Photonz is still starting up. Try again in a moment.") }
        let stamp = ISO8601DateFormatter()
        let items = coordinator.capture.store.entries.prefix(limit).enumerated().map { index, entry in
            HistoryItem(index: index, name: entry.fileName, file: entry.url.path,
                        kind: entry.kind == .video ? "video" : "picture", taken: stamp.string(from: entry.createdAt))
        }
        return .json(items)
    }

    /// How long an open may take before the agent is told it did not land: a
    /// long recording reads its first frames before its window has a document.
    static let openPatienceSeconds: Double = 30

    private static func open(_ target: AgentRequest.OpenTarget) async throws -> Answer {
        guard let coordinator else { throw Failure("Photonz is still starting up. Try again in a moment.") }
        let url: URL
        switch target {
        case .path(let path):
            url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path) else { throw Failure("There is no file at \(path).") }
            let before = Set(AgentDocuments.open.compactMap(\.agentID))
            coordinator.openFileWindow(url)
            return try await opened(url, before: before)
        case .history(let index):
            let entries = coordinator.capture.store.entries
            guard entries.indices.contains(index) else {
                throw Failure(entries.isEmpty ? "History is empty."
                                              : "History has \(entries.count) items; historyIndex goes from 0 to \(entries.count - 1).")
            }
            let entry = entries[index]
            url = entry.url.standardizedFileURL
            let before = Set(AgentDocuments.open.compactMap(\.agentID))
            // The same door History's own strip uses.
            if entry.kind == .video { coordinator.openRecording(entry.url) } else { coordinator.editCapture(entry.url) }
            return try await opened(url, before: before)
        }
    }

    /// Waits for the window the open asked for to hold its document.
    private static func opened(_ url: URL, before: Set<String>) async throws -> Answer {
        let deadline = Date().addingTimeInterval(openPatienceSeconds)
        while Date() < deadline {
            let open = AgentDocuments.open
            let match = open.first { AgentDocuments.files(of: $0).contains(url) }
                ?? open.first { !before.contains($0.agentID ?? "") }
            if let match {
                return .json(listing(match, front: AgentDocuments.front === match))
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw Failure("\(url.lastPathComponent) did not open within \(Int(openPatienceSeconds)) seconds.")
    }

    // MARK: Pictures

    /// The scale that brings `size` within `maxSize` on its longer side, never
    /// larger than the document's own pixels.
    private static func scale(fitting size: CGSize, maxSize: Int) -> CGFloat {
        let longest = max(size.width, size.height)
        guard longest > 0 else { return 1 }
        return min(1, CGFloat(maxSize) / longest)
    }

    private static func checkedRegion(_ region: CGRect?, in document: PhotonzDocument) throws -> CGRect? {
        guard let region else { return nil }
        let canvas = CGRect(origin: .zero, size: document.canvasSize)
        let inside = region.intersection(canvas)
        guard !inside.isNull, inside.width >= 1, inside.height >= 1 else {
            throw Failure("That region is outside the canvas, which is \(Int(canvas.width)) by \(Int(canvas.height)).")
        }
        return inside
    }

    /// `picture` cut down to `region` (document points, top left).
    private static func crop(_ picture: CGImage, to region: CGRect?, canvas: CGSize) -> CGImage? {
        guard let region, canvas.width > 0, canvas.height > 0 else { return picture }
        let sx = CGFloat(picture.width) / canvas.width
        let sy = CGFloat(picture.height) / canvas.height
        let pixels = CGRect(x: region.minX * sx, y: region.minY * sy,
                            width: region.width * sx, height: region.height * sy).integral
        return picture.cropping(to: pixels)
    }

    private static func png(_ picture: CGImage?, saying words: String) throws -> Answer {
        guard let picture, let data = ImageCodec.encode(picture, format: .png) else {
            throw Failure("Photonz could not draw that picture.")
        }
        return Answer(content: [.text("\(words) (\(picture.width)x\(picture.height) PNG)"), .png(data)])
    }

    private static func renderPicture(_ editor: EditorState, layer: String?, region: CGRect?,
                                      maxSize: Int) async throws -> Answer {
        var document = try document(of: editor)
        let region = try checkedRegion(region, in: document)
        var layerID: UUID?
        if let layer {
            guard let id = UUID(uuidString: layer), document.layer(id: id) != nil else {
                throw Failure("There is no layer \(layer) in this document. read_document lists the layer ids.")
            }
            layerID = id
        }
        let scale = scale(fitting: region?.size ?? document.canvasSize, maxSize: maxSize)
        if document.hasTime {
            let ms = editor.documentTimeMS
            if let layerID, let alone = document.detachedLayer(id: layerID) {
                var only = PhotonzDocument(canvasSize: document.canvasSize, layers: [alone],
                                           pixelScale: document.pixelScale)
                only.durationMS = document.documentDurationMS
                document = only
            }
            let picture = await frame(of: document, store: editor.store, atMS: ms, scale: scale)
            return try png(crop(picture, region: region, canvas: document.canvasSize),
                           saying: "\(title(of: editor)) at \(AgentContactSheet.label(ms: ms))")
        }
        // Drawn here, the way Copy draws a picture, with a renderer of its own
        // so the canvas's caches are left alone.
        let renderer = DocumentRenderer()
        let picture: CGImage?
        if let layerID {
            picture = renderer.render(document, store: editor.store, only: layerID, scale: scale)
        } else {
            picture = scale == 1 ? renderer.render(document, store: editor.store)
                                 : renderer.render(document, store: editor.store, scale: scale)
        }
        return try png(crop(picture, region: region, canvas: document.canvasSize),
                       saying: layer.map { "Layer \($0) of \(title(of: editor))" } ?? title(of: editor))
    }

    private static func crop(_ picture: CGImage?, region: CGRect?, canvas: CGSize) -> CGImage? {
        picture.flatMap { crop($0, to: region, canvas: canvas) }
    }

    /// The document at a moment, drawn the way a video export draws it.
    private static func frame(of document: PhotonzDocument, store: ImageStore, atMS ms: Int,
                              scale: CGFloat) async -> CGImage? {
        let size = CGSize(width: (document.canvasSize.width * scale).rounded(),
                          height: (document.canvasSize.height * scale).rounded())
        let frames = DocumentFrames(document: document, store: store,
                                    movieURLs: MovieLibrary.shared.urls(in: document), size: size)
        defer { frames.putTheStoreBack() }
        return await frames.frame(atMS: ms)
    }

    private static func videoDocument(_ editor: EditorState) throws -> PhotonzDocument {
        let document = try document(of: editor)
        guard document.hasTime else {
            throw Failure("\(title(of: editor)) is a picture, not a video. Use render_picture to see it.")
        }
        return document
    }

    private static func videoFrame(_ editor: EditorState, atMS ms: Int, region: CGRect?,
                                   maxSize: Int) async throws -> Answer {
        let document = try videoDocument(editor)
        let length = document.documentDurationMS
        guard ms < length else {
            throw Failure("The video is \(AgentContactSheet.label(ms: length)) long; ask for a moment before that.")
        }
        let region = try checkedRegion(region, in: document)
        let scale = scale(fitting: region?.size ?? document.canvasSize, maxSize: maxSize)
        let picture = await frame(of: document, store: editor.store, atMS: ms, scale: scale)
        return try png(crop(picture, region: region, canvas: document.canvasSize),
                       saying: "\(title(of: editor)) at \(AgentContactSheet.label(ms: ms))")
    }

    private static func contactSheet(_ editor: EditorState, fromMS: Int?, toMS: Int?, count: Int,
                                     columns: Int?, cellWidth: Int) async throws -> Answer {
        let document = try videoDocument(editor)
        let length = document.documentDurationMS
        let from = min(fromMS ?? 0, max(0, length - 1))
        let to = min(toMS ?? length, length)
        let times = AgentContactSheet.times(fromMS: from, toMS: max(to, from), count: count)
        let layout = AgentContactSheet.layout(count: times.count, columns: columns, cellWidth: CGFloat(cellWidth),
                                              pictureSize: document.canvasSize)
        guard let pictureSize = layout.pictures.first?.size,
              let context = CGContext(data: nil, width: Int(layout.size.width), height: Int(layout.size.height),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw Failure("Photonz could not draw that sheet.") }
        context.setFillColor(CGColor(gray: 0.12, alpha: 1))
        context.fill(CGRect(origin: .zero, size: layout.size))
        let frames = DocumentFrames(document: document, store: editor.store,
                                    movieURLs: MovieLibrary.shared.urls(in: document), size: pictureSize)
        defer { frames.putTheStoreBack() }
        let height = layout.size.height
        for (index, ms) in times.enumerated() {
            // The sheet's rectangles are top-left; the context's are bottom-left.
            let box = layout.pictures[index]
            let flipped = CGRect(x: box.minX, y: height - box.maxY, width: box.width, height: box.height)
            if let picture = await frames.frame(atMS: ms) { context.draw(picture, in: flipped) }
            let label = layout.labels[index]
            draw(AgentContactSheet.label(ms: ms), in: context,
                 at: CGPoint(x: label.minX + 2, y: height - label.maxY + 6))
        }
        let said = times.map { AgentContactSheet.label(ms: $0) }.joined(separator: ", ")
        return try png(context.makeImage(),
                       saying: "\(title(of: editor)): \(times.count) frames at \(said), left to right, top to bottom")
    }

    private static func draw(_ text: String, in context: CGContext, at point: CGPoint) {
        let font = CTFontCreateUIFontForLanguage(.system, 13, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, 13, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.92, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = point
        CTLineDraw(line, context)
    }

    // MARK: Undo

    struct Stepped: Encodable {
        let did: Int
        let canUndo: Bool
        let canRedo: Bool
    }

    private static func step(_ editor: EditorState, steps: Int, back: Bool) throws -> Answer {
        var did = 0
        while did < steps, back ? editor.canUndo : editor.canRedo {
            if back { editor.undo() } else { editor.redo() }
            did += 1
        }
        let answer = Answer.json(Stepped(did: did, canUndo: editor.canUndo, canRedo: editor.canRedo))
        guard did > 0 else {
            throw Failure(back ? "There is nothing to undo in \(title(of: editor))."
                               : "There is nothing to redo in \(title(of: editor)).")
        }
        return answer
    }

    // MARK: Commands

    /// The command table, each with whether it can run now on `editor` as it
    /// stands, and a toggle's state.
    private static func listCommands(_ editor: EditorState, area: AppCommand.Area?, readyOnly: Bool) throws -> Answer {
        _ = try document(of: editor)
        var listed: [AgentJSON] = []
        for command in AppCommandTable.all where area == nil || command.area == area {
            let ready = editor.canRun(.menu(command.id))
            if readyOnly && !ready { continue }
            var entry = AppCommandTable.listing(command, ready: ready).objectValue ?? [:]
            if let on = editor.isOn(command.id) { entry["on"] = .bool(on) }
            listed.append(.object(entry))
        }
        return Answer(content: [.text(AgentJSON.array(listed).encodedString())])
    }

    struct Ran: Encodable {
        let ran: String
        let title: String
        let changed: Bool
        let playheadSeconds: Double?
        let picked: [String]
        let canUndo: Bool
        let canRedo: Bool
    }

    /// Picks what the call names, the way a person clicks it before choosing
    /// the row, then runs the command as its row does, all as one undo step.
    private static func runCommand(_ editor: EditorState, _ call: AppCommandCall) async throws -> Answer {
        guard let command = AppCommandTable.command(call.id) else {
            throw Failure("There is no command called \(call.id.rawValue).")
        }
        let before = try document(of: editor)
        if command.area == .timeline && !editor.documentHasTime {
            throw Failure("\(command.name) works on a video, and \(title(of: editor)) is a picture.")
        }
        var refusal: String?
        editor.agentIsRunning = true
        defer { editor.agentIsRunning = false }
        await editor.asOneUndoStepAwaiting {
            do {
                try pick(call, in: editor, document: before)
            } catch let failure as Failure {
                refusal = failure.message
                return
            } catch {
                refusal = error.localizedDescription
                return
            }
            guard editor.canRun(call) else {
                refusal = "\(command.title) cannot run now: it needs \(command.needs)." + hint(for: call, in: editor)
                return
            }
            await editor.runAwaiting(call)
        }
        if let refusal { throw Failure(refusal) }
        let after = editor.document
        return .json(Ran(ran: command.name, title: command.title, changed: after != before,
                         playheadSeconds: editor.documentHasTime ? Double(editor.documentTimeMS) / 1000 : nil,
                         picked: editor.actionableLayerIDs.map(\.uuidString).sorted(),
                         canUndo: editor.canUndo, canRedo: editor.canRedo))
    }

    /// The choices a refused call could have made, where the app knows them
    /// better than the table does.
    private static func hint(for call: AppCommandCall, in editor: EditorState) -> String {
        switch call.id {
        case .setTransitionLength where !editor.clipTransitionLengthOffers.isEmpty:
            " This cut offers " + editor.clipTransitionLengthOffers.map { "\($0)" }.joined(separator: ", ") + " ms."
        case .setFade:
            if let layer = editor.pictureFadeLayerInHand,
               let end = call.word("end").flatMap(FadeEnd.init(rawValue:)) {
                " It offers " + editor.pictureFadeStops(end, layer: layer).map { "\($0)" }.joined(separator: ", ") + " ms."
            } else { "" }
        case .fillTheStack: editor.flowFillCommand.reason.map { " " + $0 } ?? ""
        case .surfaceBehind, .inFrontOfTheRest: editor.surfaceCommand.reason.map { " " + $0 } ?? ""
        case .save where editor.saveAsksWhere:
            " This document has no file to save back to yet; export writes it to a path."
        case .insertTitle:
            if let kind = call.word("kind").flatMap(TitleKind.init(rawValue:)) {
                " The \(kind.name) styles are " + editor.titlePresetNames(kind).joined(separator: ", ") + "."
            } else { "" }
        case .animateProperty:
            if let layer = editor.layerToAnimate {
                " It can animate " + editor.animateGroups(layerID: layer.id).flatMap(\.properties)
                    .map { $0.title(on: layer) }.joined(separator: ", ") + "."
            } else { "" }
        case .stopAnimating:
            if let layer = editor.keyLayer, !editor.animatingRows.isEmpty {
                " It is animating " + editor.animatingRows.map { $0.title(on: layer) }.joined(separator: ", ") + "."
            } else { "" }
        default: ""
        }
    }

    /// Puts the playhead, the track, the clips and the piece where the call
    /// says, checking each exists first.
    private static func pick(_ call: AppCommandCall, in editor: EditorState, document: PhotonzDocument) throws {
        if let ms = call.atMS {
            let length = document.documentDurationMS
            guard document.hasTime else { throw Failure("seconds only means something on a video.") }
            guard ms <= length else {
                throw Failure("The video is \(AgentContactSheet.label(ms: length)) long; seconds must be inside it.")
            }
            editor.moveDocumentPlayhead(toMS: ms)
        }
        if let track = call.track {
            guard let id = UUID(uuidString: track), document.track(id: id) != nil else {
                throw Failure("There is no track \(track). read_document lists the track ids.")
            }
            editor.pickTrack(id, extending: false)
        }
        if call.id == .section, let range = document.markedRangeMS { editor.rulerRangeInHand = range }
        guard !call.layers.isEmpty else {
            try pickWithin(call, in: editor, document: document)
            return
        }
        var ids: [UUID] = []
        for layer in call.layers {
            guard let id = UUID(uuidString: layer), document.layer(id: id) != nil else {
                throw Failure("There is no layer \(layer). read_document lists the layer ids.")
            }
            ids.append(id)
        }
        if let piece = call.piece, let id = ids.first {
            let count = document.layer(id: id)?.clipPieces?.count ?? 1
            guard piece < count else {
                throw Failure("That clip has \(count) piece\(count == 1 ? "" : "s"); piece goes from 0 to \(count - 1).")
            }
            editor.selectClipPiece(layerID: id, index: piece)
        } else if ids.count == 1, let id = ids.first {
            editor.selectLayer(id)
        } else {
            editor.selectLayers(Set(ids))
        }
        try pickWithin(call, in: editor, document: document)
    }

    /// What a command acts on inside what was picked, the way a click on it
    /// picks it: the zoom at the playhead, or the gap at the playhead on the
    /// track named.
    private static func pickWithin(_ call: AppCommandCall, in editor: EditorState, document: PhotonzDocument) throws {
        switch call.id {
        case .followCursor, .setZoomAmount, .deleteZoom:
            guard editor.pickZoomAtPlayhead() else {
                throw Failure("There is no zoom at the playhead. read_document says how many zooms a clip "
                              + "carries; seconds puts the playhead inside one.")
            }
        case .delete where call.track != nil && call.layers.isEmpty && call.atMS != nil:
            guard let track = call.track.flatMap(UUID.init(uuidString:)), editor.pickGap(onTrack: track) else {
                throw Failure("There is no gap at the playhead on that track: a gap is empty time between two clips.")
            }
        default:
            break
        }
    }
}
