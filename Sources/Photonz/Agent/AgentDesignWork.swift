import Foundation
import PhotonzCore

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
