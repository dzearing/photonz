#if PHOTONZ_PLAYTEST
import Foundation
import PhotonzCore

/// Walk steps for the one Curve row every transition is tuned with (task
/// `every-transition-can-be-picked-from-presets-and`).
///
/// - `curveDrawOnZoom` stands in for dragging the curve editor's two handles
///   on the one zoom and keeping what was drawn as "Slow start": the same two
///   calls "Save" in the editor makes.
/// - `expectZoomFollowsCurve` scrubs to a quarter, a half and three quarters of
///   the zoom's way in and its way out and fails unless the canvas is that far
///   in along the zoom's curve, within 2%.
/// - `expectDissolveFollowsCurve` does the same for the transition on the cut
///   in hand, reading how far up the incoming shot is, on the canvas and in
///   the frame the exporter is handed.
@MainActor
enum PlaytestCurves {

    /// What the stand-in draws: slow off the mark, then quick to arrive.
    static let drawn = EasingCurve.custom(x1: 0.7, y1: 0, x2: 0.9, y2: 0.4)
    static let savedName = "Slow start"

    static func drawOnZoom(_ editor: EditorState) throws -> String {
        let (clip, zoom, _, _) = try PlaytestZoom.theZoom(editor)
        SavedCurveStore.shared.save(drawn, as: savedName)
        editor.setZoomCurve([ClipZoomRef(layerID: clip.id, zoomID: zoom.id)], drawn, end: .both)
        guard let now = editor.document?.layer(id: clip.id)?.zooms?.first, now.inCurve == drawn,
              now.outCurveShown == drawn else {
            throw PlaytestZoom.Failure(description: "the drawn curve did not land on the zoom")
        }
        return "drew \(drawn.title) on the zoom and saved it as \(savedName)"
    }

    static func expectZoomFollowsCurve(_ editor: EditorState) async throws -> String {
        let (clip, zoom, start, end) = try PlaytestZoom.theZoom(editor)
        let eases = zoom.eases
        var said: [String] = []
        for (way, curve, from, length, isIn) in [("in", zoom.inCurve, start, eases.inMS, true),
                                                 ("out", zoom.outCurveShown, end - eases.outMS, eases.outMS, false)] {
            for q in [0.25, 0.5, 0.75] {
                let ms = from + Int((Double(length) * q).rounded())
                await PlaytestZoom.scrub(editor, toMS: ms, settle: .milliseconds(300))
                guard let drawn = editor.playtestLastDrawn?.layer(id: clip.id) else {
                    throw PlaytestZoom.Failure(description: "at \(ms) ms the canvas was given no recording")
                }
                let width = Double(drawn.zoomWindow?.width ?? 1)
                // The window is the picture shrunk by scale^amount.
                let amount = width >= 1 ? 0 : log(1 / width) / log(zoom.scale)
                let wanted = isIn ? max(0, curve.value(at: q)) : max(0, 1 - curve.value(at: q))
                guard abs(amount - wanted) <= 0.02 else {
                    throw PlaytestZoom.Failure(description: "\(Int(q * 100))% of the way \(way) (\(ms) ms) the "
                        + "zoom is \(pct(amount)) in, and its curve \(curve.title) says \(pct(wanted))")
                }
                said.append("\(way) \(Int(q * 100))%: \(pct(amount)) vs \(pct(wanted))")
            }
        }
        return "the zoom follows its curve on the canvas: " + said.joined(separator: "; ")
    }

    static func expectDissolveFollowsCurve(_ editor: EditorState) async throws -> String {
        guard let inHand = editor.cutInHand, let transition = inHand.cut.drawnTransition,
              case let .edit(outgoing, incoming) = inHand.place else {
            throw PlaytestZoom.Failure(description: "no transition between two clips is in hand")
        }
        guard transition.kind == .dissolve else {
            throw PlaytestZoom.Failure(description: "the transition in hand is \(transition.kind.title), not a dissolve")
        }
        let from = inHand.atMS - transition.beforeMS
        var said: [String] = []
        func incomingOpacity(_ shown: PhotonzDocument, atMS ms: Int) -> Double? {
            if ms < inHand.atMS {
                return shown.layers.first { $0.id != outgoing && $0.id != incoming && $0.isVisible }
                    .map { Double($0.style.opacity) }
            }
            return shown.layers.first { $0.id == incoming }.map { Double($0.style.opacity) }
        }
        for q in [0.25, 0.5, 0.75] {
            let ms = from + Int((Double(transition.lengthMS) * q).rounded())
            await PlaytestZoom.scrub(editor, toMS: ms, settle: .milliseconds(300))
            guard let canvas = editor.playtestLastDrawn.flatMap({ incomingOpacity($0, atMS: ms) }),
                  let document = editor.document,
                  let export = incomingOpacity(document.drawn(atTimeMS: ms), atMS: ms) else {
                throw PlaytestZoom.Failure(description: "at \(ms) ms the incoming shot is not on screen")
            }
            let wanted = min(max(transition.curve.value(at: q), 0), 1)
            guard abs(canvas - wanted) <= 0.02, abs(export - wanted) <= 0.02 else {
                throw PlaytestZoom.Failure(description: "\(Int(q * 100))% through (\(ms) ms) the incoming shot is "
                    + "\(pct(canvas)) up on the canvas and \(pct(export)) in the export, and its curve "
                    + "\(transition.curve.title) says \(pct(wanted))")
            }
            said.append("\(Int(q * 100))%: canvas \(pct(canvas)), export \(pct(export)), curve \(pct(wanted))")
        }
        return "the dissolve follows its curve: " + said.joined(separator: "; ")
    }

    private static func pct(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }
}
#endif
