import Foundation
import PhotonzCore
import PhotonzRender

/// What the design-system tools do in the running app
/// (`docs/design/agent-mcp.md`, "Design systems").
///
/// Saving a style is the Styles shelf's own save, putting one on is what
/// choosing it from a colour row or dropping it on words does, and a layout is
/// the inspector's Layout section, each inside `asOneUndoStep` so one Command Z
/// takes back one thing the agent did.
@MainActor
enum AgentDesignWork {

    typealias Failure = AgentWork.Failure
    typealias Answer = AgentWork.Answer

    static func answer(_ request: AgentRequest) async throws -> Answer {
        switch request {
        case .listStyles(let id):
            let editor = try AgentDocuments.editor(id).get()
            return .json(AgentStyleListing.make(try usable(editor)))
        case .addStyle(let id, let style):
            return try addStyle(AgentDocuments.editor(id).get(), style)
        case .applyStyle(let id, let style, let layers, let part):
            return try applyStyle(AgentDocuments.editor(id).get(), style: style, layers: layers, part: part)
        case .setLayout(let id, let layer, let change):
            return try setLayout(AgentDocuments.editor(id).get(), layer: layer, change: change)
        case .addComponent(let id, let component):
            return try addComponent(AgentDocuments.editor(id).get(), component)
        default:
            throw Failure("That is not a design tool.")
        }
    }

    private static func usable(_ editor: EditorState) throws -> PhotonzDocument {
        let document = try AgentWork.document(of: editor)
        guard editor.colorStylesEnabled else { throw Failure("This release has no saved styles.") }
        guard !document.hasTime else { throw Failure("Styles are for a picture; a video has none.") }
        return document
    }

    struct Saved: Encodable {
        let style: String
        let name: String
        let kind: String
        let canUndo: Bool
    }

    private static func addStyle(_ editor: EditorState, _ style: AgentNewStyle) throws -> Answer {
        let document = try usable(editor)
        if document.agentStyle(named: style.name) != nil {
            throw Failure("There is already a style called \(style.name). list_styles lists them; pick another name.")
        }
        var saved: UUID?
        editor.asOneUndoStep {
            switch style {
            case .color(let name, let hex):
                // The colour picker's Save style: onto the shelf, nothing painted yet.
                saved = editor.saveColorStyle(hex: hex, name: name)
            case .text(let name, let treatment):
                editor.perform { saved = $0.addTextStyle(name: name, treatment: treatment) }
                editor.showStylesShelf()
            }
        }
        guard let saved, let name = editor.document.flatMap({ named(saved, in: $0) }) else {
            throw Failure("Photonz could not save \(style.name).")
        }
        let kind = if case .color = style { "color" } else { "text" }
        return .json(Saved(style: saved.uuidString, name: name, kind: kind, canUndo: editor.canUndo))
    }

    private static func named(_ id: UUID, in document: PhotonzDocument) -> String? {
        document.colorStyle(id: id)?.name ?? document.textStyle(id: id)?.name
    }

    struct Applied: Encodable {
        let style: String
        let layers: [String]
        let part: String?
        let canUndo: Bool
    }

    private static func applyStyle(_ editor: EditorState, style words: String, layers: [String],
                                   part: AgentStylePart?) throws -> Answer {
        let document = try usable(editor)
        guard let match = document.agentStyle(named: words) else {
            let names = (document.colorStyles.map(\.name) + document.textStyles.map(\.name)).joined(separator: ", ")
            throw Failure("There is no style called \(words). " + (names.isEmpty ? "Save one with add_style." : "The shelf has \(names)."))
        }
        var ids: [UUID] = []
        for word in layers {
            guard let id = UUID(uuidString: word), document.layer(id: id) != nil else {
                throw Failure("There is no layer \(word) in this document. read_document lists the layer ids.")
            }
            ids.append(id)
        }
        switch match {
        case .text(let styleID):
            if part != nil { throw Failure("part is for a colour; a text style sets the whole of the words.") }
            let notText = ids.compactMap { document.layer(id: $0) }.filter { $0.text == nil }.map(\.name)
            guard notText.isEmpty else {
                throw Failure("A text style goes on words, and \(notText.joined(separator: ", ")) \(notText.count == 1 ? "is" : "are") not text.")
            }
            // Dropping the style's tile on the words: re-set, boxes re-measured.
            editor.asOneUndoStep { editor.dropTextStyle(styleID: styleID, onLayers: ids) }
            return .json(Applied(style: styleID.uuidString, layers: layers, part: nil, canUndo: editor.canUndo))
        case .color(let styleID):
            var bySlot: [ColorSlot: [UUID]] = [:]
            for id in ids {
                guard let layer = document.layer(id: id) else { continue }
                let slots = layer.colorSlots
                let slot = part?.slot ?? AgentStylePart.defaultSlot(for: slots)
                guard let slot, slots.contains(slot) else {
                    throw Failure("\(layer.name) has no \(part?.rawValue ?? "colour") to paint.")
                }
                bySlot[slot, default: []].append(id)
            }
            editor.asOneUndoStep {
                for (slot, targets) in bySlot {
                    editor.perform { _ = $0.bindColorStyle(layerIDs: targets, slot: slot, styleID: styleID) }
                }
            }
            let parts = Set(bySlot.keys.map(\.rawValue)).sorted().joined(separator: ", ")
            return .json(Applied(style: styleID.uuidString, layers: layers, part: parts, canUndo: editor.canUndo))
        }
    }

    struct MadeComponent: Encodable {
        struct Look: Encodable {
            let name: String
            let layer: String
            let frame: AgentDrawingWork.Box
        }
        /// The first look, so a plan's "$N" names something on the canvas.
        let layer: String
        let component: String
        let name: String
        let looks: [Look]
        let parts: [String]
        let canUndo: Bool
    }

    /// add_component: the component and every look of it, built in the
    /// document (`PhotonzDocument.agentAddComponent`) with the app measuring
    /// the words, landed as one undo step and picked.
    /// Room left under the last row of a sheet that grew the canvas.
    static let sheetMargin: CGFloat = 48

    private static func addComponent(_ editor: EditorState, _ spec: AgentNewComponent) throws -> Answer {
        let document = try AgentWork.document(of: editor)
        guard editor.componentsEnabled else { throw Failure("This release has no components.") }
        guard !document.hasTime else { throw Failure("add_component: components are for a picture; a video has none.") }
        let measure: (TextContent, CGFloat?) -> CGSize = { content, width in
            TextRasterizer.naturalSize(content, maxWidth: width ?? .greatestFiniteMagnitude)
        }
        // Tried on a copy first, so a call that cannot be built answers its
        // sentence and leaves no empty step in the history.
        var trial = document
        _ = try trial.agentAddComponent(spec, measure: measure).get()
        var built: AgentMadeComponent?
        editor.asOneUndoStep {
            editor.perform { built = try? $0.agentAddComponent(spec, measure: measure).get() }
            // A table that runs past the canvas grows it from the top left,
            // so nothing already there moves, keeping the table's own left
            // margin on the right and a margin under its last row.
            if let sheet = built?.sheet, let canvas = editor.document?.canvasSize {
                let needed = CGSize(width: max(canvas.width, (sheet.frame.maxX + sheet.frame.minX).rounded(.up)),
                                    height: max(canvas.height, (sheet.frame.maxY + Self.sheetMargin).rounded(.up)))
                if needed != canvas { editor.setCanvasSize(to: needed, anchor: .topLeft) }
            }
            if let first = built?.looks.first { editor.selectLayer(first.layer) }
        }
        guard let made = built else { throw Failure("Photonz could not add \(spec.name) to \(AgentWork.title(of: editor)).") }
        guard let landed = editor.document, let first = made.looks.first,
              landed.layer(id: first.layer) != nil else {
            throw Failure("Photonz could not add \(spec.name) to \(AgentWork.title(of: editor)).")
        }
        let looks = made.looks.map { look in
            MadeComponent.Look(name: look.name, layer: look.layer.uuidString,
                               frame: AgentDrawingWork.Box(landed.canvasBounds(of: look.layer) ?? .zero))
        }
        return .json(MadeComponent(layer: first.layer.uuidString, component: made.componentID.uuidString,
                                   name: landed.mainComponent(componentID: made.componentID)?.name ?? spec.name,
                                   looks: looks, parts: spec.parts.map(\.name), canUndo: editor.canUndo))
    }

    private static func setLayout(_ editor: EditorState, layer: String, change: AgentLayoutChange) throws -> Answer {
        let document = try AgentWork.document(of: editor)
        guard Experiments.shared.autoLayoutEnabled else { throw Failure("This release has no layout for groups.") }
        guard let id = UUID(uuidString: layer), let found = document.layer(id: id) else {
            throw Failure("There is no layer \(layer) in this document. read_document lists the layer ids.")
        }
        guard found.isGroup else {
            throw Failure("\(found.name) is not a group. Make one first: run_command group with its pieces in layers.")
        }
        guard document.ownsContentRules(id: id) else {
            throw Failure("\(found.name) is a copy of a component; its layout is its original's. Use run_command edit_original.")
        }
        editor.asOneUndoStep { editor.perform { $0.agentSetLayout(id: id, change) } }
        return AgentDrawingWork.drawn(id, in: editor)
    }
}
