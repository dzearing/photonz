import AppKit
import PhotonzCore
import PhotonzRender

/// What the picture tools do in the running app (`docs/design/agent-mcp.md`,
/// slice 3).
///
/// Each one builds the layer the matching tool would have built
/// (`AgentDrawing`, PhotonzCore) and lands it through the same `EditorState`
/// call that tool makes, inside `asOneUndoStep`, so one Command Z takes back
/// one thing the agent did and what is left is a layer a person can pick up.
@MainActor
enum AgentDrawingWork {

    typealias Failure = AgentWork.Failure
    typealias Answer = AgentWork.Answer

    static func answer(_ request: AgentRequest) async throws -> Answer {
        switch request {
        case .newPicture(let width, let height):
            return try await newPicture(CGSize(width: width, height: height))
        case .addShape(let id, let shape):
            let editor = try AgentDocuments.editor(id).get()
            return try add(AgentDrawing.layer(for: shape), to: editor)
        case .addPath(let id, let path):
            let editor = try AgentDocuments.editor(id).get()
            return try add(AgentDrawing.layer(for: path), to: editor)
        case .addDrawing(let id, let call):
            return try await addDrawing(call, to: AgentDocuments.editor(id).get())
        case .addPhoto(let id, let call):
            return try await addPhoto(call, to: AgentDocuments.editor(id).get())
        case .addText(let id, let text):
            let editor = try AgentDocuments.editor(id).get()
            return try addText(text, to: editor)
        case .setLayer(let id, let layer, let change):
            return try setLayer(AgentDocuments.editor(id).get(), layer: layer, change: change)
        case .findElements(let id, let region, let limit):
            return try await findElements(AgentDocuments.editor(id).get(), region: region, limit: limit)
        case .addMeasurement(let id, let measurement):
            return try await addMeasurement(AgentDocuments.editor(id).get(), measurement)
        case .findMeasurements(let id, let region):
            return try await findMeasurements(AgentDocuments.editor(id).get(), region: region)
        case .markMeasurements(let id, let region, let marks):
            return try await markMeasurements(AgentDocuments.editor(id).get(), region: region, ids: marks)
        case .findMisalignments(let id, let region):
            return try await findMisalignments(AgentDocuments.editor(id).get(), region: region)
        case .markMisalignments(let id, let region, let findings):
            return try await markMisalignments(AgentDocuments.editor(id).get(), region: region, ids: findings)
        case .listComponents(let id):
            return try listComponents(AgentDocuments.editor(id).get())
        case .placeComponent(let id, let component, let center):
            return try placeComponent(AgentDocuments.editor(id).get(), component: component, at: center)
        case .export(let id, let format, let path, let scale, let background):
            guard format != .mp4 else { throw Failure("export: an MP4 is written from a video.") }
            return try await export(AgentDocuments.editor(id).get(), format: format, path: path,
                                    scale: scale, background: background)
        default:
            throw Failure("That is not a picture tool.")
        }
    }

    // MARK: A new picture

    private static func newPicture(_ size: CGSize) async throws -> Answer {
        guard let coordinator = AgentWork.coordinator else {
            throw Failure("Photonz is still starting up. Try again in a moment.")
        }
        let before = Set(AgentDocuments.open.compactMap(\.agentID))
        // File > New Blank Canvas, once its size has been chosen.
        coordinator.newBlankCanvasWindow(size: BlankCanvas.normalized(size))
        let deadline = Date().addingTimeInterval(AgentWork.openPatienceSeconds)
        while Date() < deadline {
            if let made = AgentDocuments.open.first(where: { !before.contains($0.agentID ?? "") && $0.document != nil }) {
                return .json(AgentWork.listing(made, front: AgentDocuments.front === made))
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw Failure("The new picture did not open within \(Int(AgentWork.openPatienceSeconds)) seconds.")
    }

    // MARK: Drawing

    struct Box: Encodable {
        let x: Double, y: Double, width: Double, height: Double
        init(_ rect: CGRect) {
            func tidy(_ v: CGFloat) -> Double { (Double(v) * 100).rounded() / 100 }
            x = tidy(rect.minX); y = tidy(rect.minY); width = tidy(rect.width); height = tidy(rect.height)
        }
    }

    struct Drawn: Encodable {
        let layer: String
        let name: String
        let frame: Box
        let canUndo: Bool
    }

    static func drawn(_ id: UUID, in editor: EditorState) -> Answer {
        let layer = editor.document?.layer(id: id)
        // A group's stored size is unused; its box is what it holds.
        let box = layer.map(AgentDrawing.box(of:))
        return .json(Drawn(layer: id.uuidString, name: layer?.name ?? "",
                           frame: Box(box ?? .zero), canUndo: editor.canUndo))
    }

    /// Lands `layer` the way a drawing tool does, at the playhead on a video,
    /// and picks it, as one undo step.
    private static func add(_ layer: Layer, to editor: EditorState) throws -> Answer {
        _ = try AgentWork.document(of: editor)
        editor.asOneUndoStep {
            editor.addDrawnLayer(layer)
            editor.selectLayer(layer.id)
        }
        guard editor.document?.layer(id: layer.id) != nil else {
            throw Failure("Photonz could not add that layer to \(AgentWork.title(of: editor)).")
        }
        return drawn(layer.id, in: editor)
    }

    struct DrawnDrawing: Encodable {
        let layer: String
        let name: String
        let frame: Box
        /// "painted: <model>, N paths in S s", or "your svg".
        let from: String
        let parts: Int
        let canUndo: Bool
    }

    /// A thing drawn in one go: painted for the request by the picture model
    /// and traced when it is running, else the agent's own SVG, as a named
    /// group (an icon frame for an icon) of layers a person can edit, picked,
    /// as one undo step. Nothing is looked up: there is no stored drawing.
    private static func addDrawing(_ call: AgentDrawingCall, to editor: EditorState) async throws -> Answer {
        let document = try AgentWork.document(of: editor)
        let drawing: SVGArtwork
        let from: String
        var fitted: CGRect?
        if let painting = await AskPictureModel.paint(call) {
            // "Ask paints its drawings": painted for the request and traced
            // into named, filled paths, whatever the subject.
            let painted = try painting.get()
            switch SVGArtwork.parse(painted.svg, keepingGroups: true) {
            case .success(let read): drawing = read
            case .failure(let trouble): throw Failure("add_drawing: \(trouble.message)")
            }
            from = "painted: \(painted.model), \(painted.paths) paths in \(Int(painted.seconds.rounded())) s"
            fitted = AgentDrawingPlacement.box(call.frame, fitting: drawing.bounds.size, on: document.canvasSize)
        } else if let svg = call.svg {
            switch SVGArtwork.parse(svg) {
            case .success(let read): drawing = read
            case .failure(let trouble): throw Failure("add_drawing: \(trouble.message)")
            }
            from = "your svg"
        } else {
            throw Failure(AgentDrawingCall.needsSVG(call.subject))
        }
        var made: UUID?
        editor.asOneUndoStep {
            if call.icon {
                let blank = isBlank(document, in: editor)
                editor.perform { made = $0.addDrawing(drawing, named: call.layerName, icon: true, box: call.frame, blank: blank) }
            } else {
                let group = drawing.group(named: call.layerName,
                                          fitting: fitted ?? AgentDrawingPlacement.box(call.frame, on: document.canvasSize))
                editor.addDrawnLayer(group, remembering: false)
                made = group.id
            }
            if let made { editor.selectLayer(made) }
        }
        guard let made, let layer = editor.document?.layer(id: made) else {
            throw Failure("Photonz could not add that drawing to \(AgentWork.title(of: editor)).")
        }
        return .json(DrawnDrawing(layer: made.uuidString, name: layer.name, frame: Box(AgentDrawing.box(of: layer)),
                                  from: from, parts: drawing.parts.count, canUndo: editor.canUndo))
    }

    struct MadePhoto: Encodable {
        let layer: String
        let name: String
        let frame: Box
        /// "painted: <model>, W x H in S s".
        let from: String
        let canUndo: Bool
    }

    /// A photo painted for the request by the picture model and kept as
    /// pixels: one ordinary picture layer filling the box asked for, the
    /// pixel selection, or the canvas, picked, as one undo step.
    private static func addPhoto(_ call: AgentPhotoCall, to editor: EditorState) async throws -> Answer {
        let document = try AgentWork.document(of: editor)
        var asked = call.frame
        if asked == nil, editor.selectionTargetsPixels, let region = editor.selection { asked = region.bounds }
        let box = AgentPhotoPlacement.box(asked, on: document.canvasSize)
        guard let painting = await AskPictureModel.photo(call, box: box.size) else {
            throw Failure("add_photo: Photonz cannot paint a photo on this Mac until its picture model is set up in Settings, Ask.")
        }
        let photo = try painting.get()
        guard editor.document != nil else { throw Failure("The document was closed before the photo was ready.") }
        let ref = editor.store.register(photo.image)
        let name = PlacedImageNaming.layerName(named: call.layerName,
                                               taken: Set(editor.document?.allLayers.map(\.name) ?? []))
        let layer = Layer(name: name, content: .image(ref), frame: box)
        editor.asOneUndoStep {
            editor.addDrawnLayer(layer, remembering: false)
            editor.selectLayer(layer.id)
        }
        guard let landed = editor.document?.layer(id: layer.id) else {
            throw Failure("Photonz could not add that photo to \(AgentWork.title(of: editor)).")
        }
        return .json(MadePhoto(layer: layer.id.uuidString, name: landed.name, frame: Box(landed.frame),
                               from: "painted: \(photo.model), \(photo.width) x \(photo.height) in \(Int(photo.seconds.rounded())) s",
                               canUndo: editor.canUndo))
    }

    /// Whether the picture holds nothing anybody made: no layers, or only a
    /// locked background of one flat colour, which is what a new blank
    /// picture is. A screenshot's background is not flat, so it never counts.
    private static func isBlank(_ document: PhotonzDocument, in editor: EditorState) -> Bool {
        document.layers.allSatisfy { layer in
            guard layer.isLocked, let ref = layer.imageRef, let image = editor.store.image(for: ref) else { return false }
            return isFlat(image)
        }
    }

    /// Nine pixels across the picture, all the same colour.
    private static func isFlat(_ image: CGImage) -> Bool {
        let side = 3
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return false }
        let first = Array(pixels[0..<4])
        return stride(from: 0, to: pixels.count, by: 4).allSatisfy { Array(pixels[$0..<($0 + 4)]) == first }
    }

    private static func addText(_ text: AgentText, to editor: EditorState) throws -> Answer {
        if let family = text.fontName, family != "SF Pro",
           !NSFontManager.shared.availableFontFamilies.contains(family) {
            throw Failure("add_text: there is no font called \(family) on this Mac. Leave fontName out for SF Pro.")
        }
        let content = text.content
        let natural = TextRasterizer.naturalSize(content, maxWidth: text.width ?? .greatestFiniteMagnitude)
        let size = CGSize(width: text.width ?? natural.width, height: natural.height)
        var layer = TextBuilder.layer(content: content, at: text.origin, naturalSize: size)
        if let name = text.name { layer.name = name }
        if !text.shadow { layer.style.shadows = [] }
        return try add(layer, to: editor)
    }

    private static func setLayer(_ editor: EditorState, layer: String, change: AgentLayerChange) throws -> Answer {
        let document = try AgentWork.document(of: editor)
        guard let id = UUID(uuidString: layer), let was = document.layer(id: id) else {
            throw Failure("There is no layer \(layer) in this document. read_document lists the layer ids.")
        }
        guard !was.isLocked else { throw Failure("\(was.name) is locked. Unlock it with run_command lock_layer, on false.") }
        // A piece inside a component copy is rebuilt from its original after
        // every edit, so writing onto it would answer "done" and change
        // nothing. Its words land where typing over it lands; anything else
        // about it is the original's.
        if let piece = document.componentPiece(of: id) {
            let onlyWords = change.text != nil && !change.movesOrSizes && change.name == nil && change.visible == nil && change.flip.isEmpty
                && change.fontSize == nil && change.look == AgentLook()
            let original = document.mainComponent(componentID: piece.componentID)?.name ?? "its original"
            guard onlyWords, let words = change.text else {
                throw Failure("\(was.name) is part of a copy of \(original), and everything but its words follows the original. Change the original with run_command edit_original (every copy follows), or run_command make_unique on the copy to stop it following.")
            }
            var trial = document
            switch trial.agentWordCopyPiece(id, to: words) {
            case .refused(let why): throw Failure(why)
            case .notAPiece: break
            case .landed:
                editor.asOneUndoStep { editor.commitPieceWordingForAgent(of: id, to: words) }
                return drawn(id, in: editor)
            }
        }
        let changed = try AgentDrawing.applying(change, to: was, canvas: document.canvasSize).get()
        let title = document.titleLayerID(containing: id)
        editor.asOneUndoStep {
            if change.changesTheWords, change.width == nil, change.height == nil, let words = changed.text?.string {
                // The words go in the way typing them does: a box made roomier
                // than its words keeps its room (a centred title line stays
                // centred), one hugging its words re-hugs them.
                var rest = changed
                rest.content = was.content
                rest.frame = CGRect(origin: changed.frame.origin, size: was.frame.size)
                editor.perform { $0.updateLayer(id: id) { $0 = rest } }
                if var content = rest.text, let size = changed.text?.fontSize {
                    content.fontSize = size
                    editor.perform { $0.updateLayer(id: id) { $0.content = .text(content) } }
                }
                AgentVideoWork.reword(id, to: words, in: editor)
            } else {
                editor.perform { $0.updateLayer(id: id) { $0 = changed } }
            }
            // A line of a title moves the rest of it, as typing into it does.
            if let title { editor.perform { _ = $0.relayOutTitle(layerID: title) } }
        }
        return drawn(id, in: editor)
    }

    // MARK: What is in the picture

    /// The picture's edges and brightness, read once and kept with the editor
    /// so the Measure tool's own snapping sees them too.
    private static func analysis(of editor: EditorState) async -> EdgeMapAnalyzer.Analysis {
        guard let ref = editor.document?.layers.compactMap(\.imageRef).first else { return .empty }
        if let ready = editor.readyEdgeMaps[ref.id] { return ready }
        let cache = editor.edgeMapCache
        let store = editor.store
        let analysis = await Task.detached(priority: .userInitiated) {
            cache.analysis(for: ref, store: store)
        }.value
        editor.readyEdgeMaps[ref.id] = analysis
        return analysis
    }

    struct Found: Encodable {
        let count: Int
        let readsThePicture: Bool
        let elements: [Box]
    }

    private static func findElements(_ editor: EditorState, region: CGRect?, limit: Int) async throws -> Answer {
        let document = try AgentWork.document(of: editor)
        let read = await analysis(of: editor)
        let found = await Task.detached(priority: .userInitiated) {
            AgentElementScan.elements(in: document, edges: read.edges, luma: read.luma,
                                      region: region, limit: limit)
        }.value
        return .json(Found(count: found.count, readsThePicture: !read.edges.isEmpty,
                           elements: found.map(Box.init)))
    }

    // MARK: A redline

    /// The redline of the picture, chosen in code off its layout
    /// (`RedlinePlan`): the same picture and region read the same every time,
    /// so the ids a look handed out name the same marks when they are laid.
    private static func redline(_ editor: EditorState, region: CGRect?) async throws -> (marks: [RedlineMark], obstacles: [CGRect], edges: [CGRect]) {
        let document = try AgentWork.document(of: editor)
        let read = await analysis(of: editor)
        guard !read.luma.isEmpty else {
            throw Failure("There is no picture to measure. find_measurements reads a screenshot.")
        }
        let scale = document.pixelScale
        let luma = read.luma
        return await Task.detached(priority: .userInitiated) {
            let nodes = LayoutRead.read(luma, pixelScale: scale, region: region)
            let canvas = region ?? CGRect(x: 0, y: 0, width: luma.width, height: luma.height)
            return (RedlinePlan.marks(in: nodes, canvas: canvas, pixelScale: scale),
                    RedlinePlan.obstacles(in: nodes, canvas: canvas, pixelScale: scale),
                    RedlinePlan.edges(in: nodes, canvas: canvas, pixelScale: scale))
        }.value
    }

    private static func findMeasurements(_ editor: EditorState, region: CGRect?) async throws -> Answer {
        let found = try await redline(editor, region: region)
        return .json(RedlinePlan.report(found.marks, pixelScale: try AgentWork.document(of: editor).pixelScale))
    }

    private static func markMeasurements(_ editor: EditorState, region: CGRect?, ids: [String]) async throws -> Answer {
        let found = try await redline(editor, region: region)
        let unknown = ids.filter { id in !found.marks.indices.contains { RedlinePlan.id($0) == id } }
        guard unknown.isEmpty else {
            throw Failure("There is no mark \(unknown.joined(separator: ", ")). find_measurements lists them.")
        }
        let chosen = found.marks.enumerated().filter { ids.contains(RedlinePlan.id($0.offset)) }
        let before = Set(editor.document?.layers.map(\.id) ?? [])
        editor.setTool(.measure)
        editor.asOneUndoStep { editor.addRedline(chosen.map(\.element), obstacles: found.obstacles, edges: found.edges) }
        let added = (editor.document?.layers ?? []).filter { !before.contains($0.id) }
        guard !added.isEmpty else { throw Failure("Photonz could not lay those measurements.") }
        return .json(Marked(layers: added.map(\.id.uuidString), marked: chosen.map { RedlinePlan.id($0.offset) }))
    }

    // MARK: Misalignments

    /// What is inconsistent in the picture, read in code off its pixels
    /// (`MisalignmentScan`): the same picture and region read the same every
    /// time, so the ids a look handed out name the same findings when the
    /// marks are made.
    private static func misalignments(_ editor: EditorState, region: CGRect?) async throws -> [Misalignment] {
        let document = try AgentWork.document(of: editor)
        let read = await analysis(of: editor)
        guard !read.luma.isEmpty else {
            throw Failure("There is no picture to check. find_misalignments reads a screenshot.")
        }
        let scale = document.pixelScale
        return await Task.detached(priority: .userInitiated) {
            MisalignmentScan.findings(luma: read.luma, pixelScale: scale, region: region)
        }.value
    }

    private static func findMisalignments(_ editor: EditorState, region: CGRect?) async throws -> Answer {
        .json(MisalignmentScan.report(try await misalignments(editor, region: region)))
    }

    struct Marked: Encodable {
        let layers: [String]
        let marked: [String]
    }

    private static func markMisalignments(_ editor: EditorState, region: CGRect?, ids: [String]) async throws -> Answer {
        let found = try await misalignments(editor, region: region)
        let chosen = found.enumerated().filter { ids.contains(MisalignmentScan.id($0.offset)) }
        let unknown = ids.filter { id in !found.indices.contains { MisalignmentScan.id($0) == id } }
        guard unknown.isEmpty else {
            throw Failure("There is no finding \(unknown.joined(separator: ", ")). find_misalignments lists them.")
        }
        let before = Set(editor.document?.layers.map(\.id) ?? [])
        editor.asOneUndoStep { editor.addMisalignmentMarks(chosen.map(\.element)) }
        let added = (editor.document?.layers ?? []).filter { !before.contains($0.id) }
        guard !added.isEmpty else { throw Failure("Photonz could not mark those findings.") }
        return .json(Marked(layers: added.map(\.id.uuidString), marked: chosen.map { MisalignmentScan.id($0.offset) }))
    }

    // MARK: Measuring

    struct Measured: Encodable {
        let layers: [String]
        let names: [String]
        /// How many of the measured sides or feet sit on an edge the picture
        /// really has, out of how many there are. Nil on a canvas with no picture.
        let onEdges: Int?
        let outOf: Int
        let measured: Box?
    }

    private static func addMeasurement(_ editor: EditorState, _ measurement: AgentMeasurement) async throws -> Answer {
        let document = try AgentWork.document(of: editor)
        let read = await analysis(of: editor)
        let canvas = CGRect(origin: .zero, size: document.canvasSize)
        func inside(_ point: CGPoint) throws {
            guard canvas.contains(point) else {
                throw Failure("That point is outside the canvas, which is \(Int(canvas.width)) by \(Int(canvas.height)).")
            }
        }
        // The Measure tool in hand, as a person measuring has it, so the
        // readouts steer round what they measure the way a click's do.
        editor.setTool(.measure)
        let before = Set(document.layers.map(\.id))
        var onEdges: Int?
        var outOf = 0
        var measuredBox: CGRect?
        switch measurement {
        case .size, .sizeAt:
            let rect: CGRect
            switch measurement {
            case .size(let box):
                rect = box.standardized
            case .sizeAt(let point, let level):
                try inside(point)
                guard let found = AgentMeasurePlan.element(at: point, level: level, edges: read.edges,
                                                           luma: read.luma, document: document) else {
                    throw Failure("The Measure tool finds no element at that point. find_elements lists the ones it sees.")
                }
                rect = found
            default:
                rect = .zero
            }
            guard rect.width >= 1, rect.height >= 1, rect.intersects(canvas) else {
                throw Failure("That box is empty or off the canvas.")
            }
            editor.measureToolMode = .size
            let neighbors = AgentMeasurePlan.sizeNeighbors(of: rect, style: editor.measureStyles.content(for: .size),
                                                           edges: read.edges, luma: read.luma, document: document)
            editor.asOneUndoStep { editor.addElementSize(rect, neighbors: neighbors) }
            measuredBox = rect
            outOf = 4
            if !read.edges.isEmpty { onEdges = AgentMeasurePlan.sidesOnEdges(rect, in: read.edges) }
        case .gap(let a, let b):
            guard let gap = AgentMeasurePlan.gap(between: a, and: b) else {
                throw Failure("Those two boxes overlap or sit corner to corner, so no space faces across between them.")
            }
            try landGap(gap, in: editor)
            outOf = 2
            if !read.edges.isEmpty { onEdges = feet(gap, read.edges) }
        case .gapAt(let point):
            try inside(point)
            guard let gap = AgentMeasurePlan.gap(at: point, luma: read.luma, document: document) else {
                throw Failure("The Measure tool finds no gap at that point. Try two boxes from find_elements.")
            }
            try landGap(gap, in: editor)
            outOf = 2
            if !read.edges.isEmpty { onEdges = feet(gap, read.edges) }
        case .distance(let from, let to, let axis):
            editor.measureToolMode = .distance
            editor.asOneUndoStep { editor.addMeasure(from: from, to: to, mode: axis, headOffset: nil) }
            outOf = 2
            if !read.edges.isEmpty {
                onEdges = AgentMeasurePlan.feetOnEdges(from: from, to: to, axis: axis, in: read.edges)
            }
        }
        let added = (editor.document?.layers ?? []).filter { !before.contains($0.id) }
        guard !added.isEmpty else { throw Failure("Photonz could not place that measurement.") }
        return .json(Measured(layers: added.map(\.id.uuidString), names: added.map(\.name),
                              onEdges: onEdges, outOf: outOf, measured: measuredBox.map(Box.init)))
    }

    private static func landGap(_ gap: GapMeasurement, in editor: EditorState) throws {
        guard gap.length > 0 else { throw Failure("Those edges touch; there is no space between them.") }
        editor.measureToolMode = .gap
        editor.asOneUndoStep { editor.addGapMeasure(gap) }
    }

    private static func feet(_ gap: GapMeasurement, _ edges: EdgeMap) -> Int {
        AgentMeasurePlan.feetOnEdges(from: gap.start, to: gap.end, axis: gap.axis, in: edges)
    }

    // MARK: Components

    struct Component: Encodable {
        let id: String
        let name: String
        let from: String
        let detail: String
    }

    private static func listComponents(_ editor: EditorState) throws -> Answer {
        _ = try AgentWork.document(of: editor)
        guard editor.componentsEnabled else { throw Failure("This release has no Library components.") }
        return .json(editor.componentEntries.map {
            Component(id: $0.id, name: $0.name, from: from($0, in: editor), detail: $0.detail)
        })
    }

    private static func from(_ entry: LibraryEntry, in editor: EditorState) -> String {
        if editor.starterComponent(entryID: entry.id) != nil { return "starter" }
        if editor.sharedComponent(entryID: entry.id) != nil { return "shared" }
        return "document"
    }

    private static func placeComponent(_ editor: EditorState, component: String, at center: CGPoint) throws -> Answer {
        _ = try AgentWork.document(of: editor)
        guard editor.componentsEnabled else { throw Failure("This release has no Library components.") }
        let entries = editor.componentEntries
        let wanted = component.trimmingCharacters(in: .whitespaces)
        guard let entry = entries.first(where: { $0.id == wanted })
                ?? entries.first(where: { $0.name.caseInsensitiveCompare(wanted) == .orderedSame }),
              let id = UUID(uuidString: entry.id) else {
            let names = entries.map(\.name).joined(separator: ", ")
            throw Failure("There is no component called \(component). The Library has \(names).")
        }
        var placed: UUID?
        editor.asOneUndoStep { placed = editor.placeComponent(componentID: id, at: center) }
        guard let placed else { throw Failure("Photonz could not place \(entry.name) there.") }
        return drawn(placed, in: editor)
    }

    // MARK: Export

    struct Exported: Encodable {
        let path: String
        let format: String
        let bytes: Int
        let width: Int?
        let height: Int?
        /// Layers an SVG could only carry as pictures, with why.
        let asPictures: [String]?
    }

    private static func export(_ editor: EditorState, format: AgentExportFormat, path: String,
                               scale: Double, background: Bool) async throws -> Answer {
        let document = try AgentWork.document(of: editor)
        let url = URL(fileURLWithPath: path)
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path, isDirectory: &isFolder),
              isFolder.boolValue else {
            throw Failure("There is no folder at \(url.deletingLastPathComponent().path) to write into.")
        }
        let backdrop: SVGExport.Background = background ? .keep : .drop
        let answer: Exported
        switch format {
        case .png:
            let sizer = ExportSizer(renderer: DocumentRenderer(), store: editor.store)
            guard let data = await sizer.data(of: document, frameID: nil, scale: CGFloat(scale),
                                              format: .png, quality: 0.9, background: backdrop) else {
                throw Failure("Photonz could not draw the picture as a PNG.")
            }
            try data.write(to: url)
            let size = document.canvasSize
            answer = Exported(path: url.path, format: "png", bytes: data.count,
                              width: Int((size.width * scale).rounded()), height: Int((size.height * scale).rounded()),
                              asPictures: nil)
        case .svg:
            guard let written = SVGExporter.data(document, store: editor.store, renderer: DocumentRenderer(),
                                                 background: backdrop) else {
                throw Failure("Photonz could not write the picture as SVG.")
            }
            try written.data.write(to: url)
            answer = Exported(path: url.path, format: "svg", bytes: written.data.count,
                              width: Int(document.canvasSize.width), height: Int(document.canvasSize.height),
                              asPictures: written.fallbacks.isEmpty ? nil
                                  : written.fallbacks.map { "\($0.layerName): \($0.reason)" })
        case .mp4:
            throw Failure("export: an MP4 is written from a video.")
        }
        return .json(answer)
    }
}
