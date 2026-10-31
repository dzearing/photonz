import Foundation
import PhotonzCore

/// What the brush tools do in the running app (`docs/design/brushes.md`,
/// decision 8).
///
/// set_brush arms the brush exactly as the tool options do, and paint_stroke
/// lands through `addBrushStroke`, the call the canvas makes when a person
/// lets go of a stroke: the same value, the same render, the same layer, one
/// undo step. Only the tool in the person's hand is left alone.
@MainActor
enum AgentPaintWork {

    typealias Failure = AgentWork.Failure
    typealias Answer = AgentWork.Answer

    static func answer(_ request: AgentRequest) throws -> Answer {
        switch request {
        case .listBrushes(let id):
            // The brushes and their settings need no document: with none
            // open, the brush in hand is the one the app saved.
            if id == nil, AgentDocuments.open.isEmpty {
                guard Experiments.shared.brushEnabled else { throw Failure("This release has no Brush.") }
                let styles = EditorState.loadAnnotationStyles()
                return .json(AgentBrushListing.make(
                    armed: styles.armedBrush,
                    colorHex: styles.colorHex(for: .brush) ?? AnnotationStyles.defaultBrushColorHex,
                    remembered: styles.brush(for:)))
            }
            let editor = try AgentDocuments.editor(id).get()
            _ = try usable(editor)
            return .json(listing(editor))
        case .setBrush(let id, let change):
            return try setBrush(AgentDocuments.editor(id).get(), change)
        case .paintStroke(let id, let stroke):
            return try paint(AgentDocuments.editor(id).get(), stroke)
        default:
            throw Failure("That is not a brush tool.")
        }
    }

    private static func usable(_ editor: EditorState) throws -> PhotonzDocument {
        let document = try AgentWork.document(of: editor)
        guard Experiments.shared.brushEnabled else { throw Failure("This release has no Brush.") }
        guard !document.hasTime else { throw Failure("The Brush paints on a picture; a video has none.") }
        return document
    }

    private static func listing(_ editor: EditorState) -> AgentBrushListing {
        AgentBrushListing.make(armed: editor.armedBrush, colorHex: editor.armedBrushColorHex,
                               remembered: editor.brushTileSettings)
    }

    private static func setBrush(_ editor: EditorState, _ change: AgentBrushChange) throws -> Answer {
        _ = try usable(editor)
        let brush: BrushSettings
        switch AgentPaint.brush(change, armed: editor.armedBrush, remembered: editor.brushTileSettings) {
        case .success(let made): brush = made
        case .failure(let refused): throw Failure("set_brush: \(refused.message)")
        }
        editor.annotationStyles.setArmedBrush(brush)
        if let hex = change.colorHex { editor.annotationStyles.setColorHex(hex, for: .brush) }
        editor.saveAnnotationStyles()
        return .json(listing(editor).armed)
    }

    struct Painted: Encodable {
        let layer: String
        let name: String
        /// How many strokes the layer holds now.
        let strokes: Int
        let medium: String
        let canUndo: Bool
    }

    private static func paint(_ editor: EditorState, _ call: AgentStroke) throws -> Answer {
        let document = try usable(editor)
        // Where it goes, picked first, as a person picks a layer before painting on it.
        var pick = editor.selectedLayerID
        if let named = call.layer {
            guard let id = UUID(uuidString: named), let layer = document.layer(id: id) else {
                throw Failure("paint_stroke: there is no layer \(named). read_document lists the layers.")
            }
            guard layer.paint != nil else {
                throw Failure("paint_stroke: \(layer.name) is not a paint layer. Leave layer out to start a Paint layer above it.")
            }
            guard !layer.isLocked else { throw Failure("paint_stroke: \(layer.name) is locked.") }
            pick = id
        } else if call.newLayer {
            pick = nil
        }
        let previous = pick.flatMap { document.layer(id: $0)?.paint?.strokes.last }
        let stroke: BrushStroke
        switch AgentPaint.brushStroke(call, armed: editor.armedBrush, armedColorHex: editor.armedBrushColorHex,
                                      remembered: editor.brushTileSettings,
                                      startedAt: AgentPaint.startedAt(now: Date().timeIntervalSinceReferenceDate,
                                                                      after: previous),
                                      seed: UInt32.random(in: 1...UInt32.max)) {
        case .success(let made): stroke = made
        case .failure(let refused): throw Failure("paint_stroke: \(refused.message)")
        }
        // A smudge drags the paint it starts on and never makes a layer.
        let smudged = stroke.settings.mode == .smudge
            ? document.smudgeTarget(at: stroke.samples[0].point, picked: pick) : nil
        if stroke.settings.mode == .smudge, smudged == nil {
            throw Failure("paint_stroke: a smudge drags paint already on a paint layer, and there is none where it starts.")
        }
        let before = editor.document
        editor.asOneUndoStep {
            if pick != editor.selectedLayerID { editor.selectLayer(pick) }
            editor.addBrushStroke(stroke, picksUpBrush: false)
        }
        guard let after = editor.document, after != before, let landed = smudged ?? editor.selectedLayerID,
              let layer = after.layer(id: landed), let paint = layer.paint else {
            throw Failure("Photonz could not paint that stroke on \(AgentWork.title(of: editor)).")
        }
        return .json(Painted(layer: landed.uuidString, name: layer.name, strokes: paint.strokes.count,
                             medium: stroke.settings.medium.rawValue, canUndo: editor.canUndo))
    }
}
