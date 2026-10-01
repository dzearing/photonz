#if PHOTONZ_PLAYTEST
import AppKit
import PhotonzCore
import PhotonzRender

/// The walk steps for an effect at each click (`ClickEffect.swift`,
/// `EditorState+ClickEffects`). The clicks are the two `PlaytestZoom` scripts
/// onto the sample recording (`zoomScriptPointerPath`), at 2 s and 2.6 s.
///
/// - `expectClickRipple` checks a ring is drawn centred on the first click at
///   three moments across it, growing and fading, and nothing either side.
/// - `expectClickEffectExportMatches` checks an exported frame at those moments
///   is what the canvas shows round the click, and differs from one without.
/// - `expectClickTicksEdited` checks the first click was hidden and the second
///   slid later, by hand on the clip's ticks.
@MainActor
enum PlaytestClickEffects {
    struct Failure: Error { let description: String }

    static func recording(in editor: EditorState) throws -> Layer {
        guard let clip = editor.document?.allLayers.first(where: { $0.movie != nil }) else {
            throw Failure(description: "there is no recording in the window")
        }
        return clip
    }

    /// The first scripted click: where it lands on the timeline and where on
    /// the canvas, and three moments across its effect.
    static func firstClick(_ editor: EditorState) throws -> (Layer, at: Int, point: CGPoint, moments: [Int]) {
        let clip = try recording(in: editor)
        guard clip.movie != nil, let first = PlaytestZoom.scriptedClickMS.first,
              let at = clip.timelineMS(ofClickAtSourceMS: first) else {
            throw Failure(description: "the first scripted click is not on the clip")
        }
        let p = PlaytestZoom.scriptedPoint(atMS: first)
        let box = clip.frame
        let point = CGPoint(x: box.minX + p.x * box.width, y: box.minY + p.y * box.height)
        return (clip, at, point, [at + 40, at + 180, at + 330])
    }

    /// What the drawn document has over the clip at a moment that the
    /// document itself does not: the click's mark.
    static func marks(_ document: PhotonzDocument, at ms: Int) -> [Layer] {
        document.drawn(atTimeMS: ms).allLayers.filter { document.layer(id: $0.id) == nil }
    }

    static func expectRipple(_ editor: EditorState) throws -> String {
        let (clip, at, point, moments) = try firstClick(editor)
        guard let document = editor.document else { throw Failure(description: "no document") }
        guard let effect = clip.clickEffect, effect.isOn else {
            throw Failure(description: "the recording's Clicks switch is off")
        }
        guard effect.style == .ripple else {
            throw Failure(description: "the clicks are drawn as \(effect.style.title), not Ripple")
        }
        var said: [String] = []
        var widths: [CGFloat] = []
        var fades: [Double] = []
        for ms in moments {
            let found = marks(document, at: ms)
            guard found.count == 1, let ring = found.first else {
                throw Failure(description: "at \(ms) ms there are \(found.count) click marks, not 1")
            }
            guard hypot(ring.frame.midX - point.x, ring.frame.midY - point.y) < 3 else {
                throw Failure(description: "at \(ms) ms the ring is centred at \(fmt(ring.frame.center)), "
                    + "not on the click at \(fmt(point))")
            }
            widths.append(ring.frame.width)
            fades.append(ring.style.opacity)
            said.append("\(ms) ms: ring \(Int(ring.frame.width)) pt across at \(Int(ring.style.opacity * 100))%")
        }
        guard zip(widths, widths.dropFirst()).allSatisfy({ $1 > $0 }),
              zip(fades, fades.dropFirst()).allSatisfy({ $1 < $0 }) else {
            throw Failure(description: "the ring does not spread and fade: " + said.joined(separator: "; "))
        }
        for ms in [at - 30, at + ClickEffect.lengthMS + 20] where !marks(document, at: ms).isEmpty {
            throw Failure(description: "at \(ms) ms, outside the click's moment, a mark is drawn")
        }
        return "a ripple at the click at \(fmt(point)): " + said.joined(separator: "; ")
    }

    static func expectExportMatches(_ editor: EditorState) async throws -> String {
        let (clip, _, _, moments) = try firstClick(editor)
        guard let document = editor.document else { throw Failure(description: "no document") }
        let frames = DocumentFrames(document: document, store: editor.store,
                                    movieURLs: MovieLibrary.shared.urls(in: document))
        defer { frames.putTheStoreBack() }
        var plain = document
        plain.updateLayer(id: clip.id) { $0.clickEffect?.isOn = false }
        let flat = DocumentFrames(document: plain, store: editor.store,
                                  movieURLs: MovieLibrary.shared.urls(in: plain))
        defer { flat.putTheStoreBack() }
        let canvas = document.canvasSize
        var said: [String] = []
        for ms in moments {
            // Round the click: the ring's own box at this moment, and a little room.
            guard let ring = marks(document, at: ms).first else {
                throw Failure(description: "at \(ms) ms no effect is drawn at the click")
            }
            let box = ring.frame.insetBy(dx: -8, dy: -8)
            let round = CGRect(x: box.minX / canvas.width, y: box.minY / canvas.height,
                               width: box.width / canvas.width, height: box.height / canvas.height)
            editor.moveDocumentPlayhead(toMS: ms)
            try? await Task.sleep(for: .milliseconds(900))
            guard let shown = editor.renderedImage,
                  let written = await frames.frame(atMS: ms),
                  let without = await flat.frame(atMS: ms),
                  let a = crop(shown, round), let b = crop(written, round), let c = crop(without, round) else {
                throw Failure(description: "at \(ms) ms a picture could not be made")
            }
            let apart = PlaytestZoom.difference(a, b)
            let effectBy = PlaytestZoom.difference(b, c)
            guard apart < 0.05 else {
                throw Failure(description: "at \(ms) ms the exported frame round the click is not what the "
                    + "canvas shows (they differ by \(pct(apart)) on average)")
            }
            guard effectBy > 0.003 else {
                throw Failure(description: "at \(ms) ms the exported frame shows no effect round the click "
                    + "(it differs from the frame without by only \(pct(effectBy)))")
            }
            said.append("\(ms) ms: export and canvas differ by \(pct(apart)), the effect changes it by \(pct(effectBy))")
        }
        return "the exported frames match the canvas round the click: " + said.joined(separator: "; ")
    }

    static func expectTicksEdited(_ editor: EditorState) throws -> String {
        let clip = try recording(in: editor)
        let marks = editor.clickMarks(ofClip: clip.id)
        guard marks.count == 2 else { throw Failure(description: "the clip has \(marks.count) clicks, not 2") }
        let byTime = marks.sorted { $0.click.downMS < $1.click.downMS }
        let said = byTime.map { "\($0.click.downMS) ms\($0.isHidden ? " hidden" : "")" }.joined(separator: ", ")
        var wrong: [String] = []
        let first = PlaytestZoom.scriptedClickMS.first ?? 0
        let second = PlaytestZoom.scriptedClickMS.last ?? 0
        if !(marks.first { $0.click.downMS == first }?.isHidden ?? false) {
            wrong.append("the click at \(first) ms is not hidden")
        }
        if marks.contains(where: { $0.click.downMS == second }) || !marks.contains(where: { $0.click.downMS > second + 100 }) {
            wrong.append("the click at \(second) ms was not slid later")
        }
        guard wrong.isEmpty else { throw Failure(description: wrong.joined(separator: "; ") + ": " + said) }
        return "clicks now at " + said
    }

    /// A part of a picture given in fractions of it from the top-left.
    static func crop(_ image: CGImage, _ part: CGRect) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let rect = CGRect(x: part.minX * w, y: part.minY * h, width: part.width * w, height: part.height * h)
            .integral.intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard !rect.isEmpty else { return nil }
        return image.cropping(to: rect)
    }

    private static func fmt(_ p: CGPoint) -> String { String(format: "%.0f, %.0f", p.x, p.y) }
    private static func pct(_ v: Double) -> String { String(format: "%.1f%%", v * 100) }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
#endif
