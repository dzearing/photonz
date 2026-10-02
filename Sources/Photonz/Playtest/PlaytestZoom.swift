#if PHOTONZ_PLAYTEST
import AppKit
import PhotonzCore
import PhotonzRender

/// The walk steps for zoom regions (`ClipZoom.swift`, `EditorState+Zoom`).
///
/// - `zoomScriptPointerPath` gives the recording in the window a pointer path
///   and two clicks, as if the recorder had taken them down: the sample
///   recording was made before pointers were kept, and a walk never moves the
///   person's own pointer. Written where the recorder's own record would be
///   read from, so Follow Cursor and Suggest Zooms read it the same way.
/// - `expectZoomFollowsCursor` checks the one zoom on the clip follows: at three
///   moments of its hold the frame holds the pointer clear of its edges, at the
///   zoom's own size, and has moved between them.
/// - `expectZoomExportMatches` checks what an export writes at those three
///   moments is what the canvas shows, and that both are zoomed.
@MainActor
enum PlaytestZoom {
    struct Failure: Error { let description: String }

    /// Where the pointer goes, as fractions of the picture: still at the left
    /// for the first second, across and down to the right by the sixth, with
    /// a hand's small wobble on the way, then still.
    static func scriptedPoint(atMS ms: Int) -> CGPoint {
        let t = min(max(Double(ms - 1000) / 5000, 0), 1)
        let eased = t * t * (3 - 2 * t)
        let wobble = sin(Double(ms) / 90) * 0.004
        return CGPoint(x: 0.2 + 0.6 * eased + wobble, y: 0.3 + 0.4 * eased - wobble)
    }

    /// The two scripted clicks: close together, so they make one suggestion.
    static let scriptedClickMS = [2000, 2600]

    static func recording(in editor: EditorState) throws -> Layer {
        guard let clip = editor.document?.allLayers.first(where: { $0.movie != nil }) else {
            throw Failure(description: "there is no recording in the window")
        }
        return clip
    }

    static func scriptPointerPath(_ editor: EditorState) throws -> String {
        let clip = try recording(in: editor)
        guard let movie = clip.movie else { throw Failure(description: "the clip plays no recording") }
        let size = movie.pixelSize
        var samples: [PointerSample] = []
        for ms in stride(from: 0, through: movie.durationMS, by: 16) {
            let p = scriptedPoint(atMS: ms)
            samples.append(PointerSample(ms: ms, x: p.x * size.width, y: p.y * size.height))
        }
        let clicks = scriptedClickMS.map { ms in
            let p = scriptedPoint(atMS: ms)
            return PointerClick(downMS: ms, upMS: ms + 80,
                                point: CGPoint(x: p.x * size.width, y: p.y * size.height), button: .left)
        }
        MovieLibrary.shared.setPointerTrackForPlaytest(
            PointerTrack(pixelSize: size, samples: samples, clicks: clicks), for: movie)
        return "the recording now carries a pointer path of \(samples.count) samples crossing "
            + "the picture between 1 and 6 seconds, and \(clicks.count) clicks"
    }

    /// The one zoom on the recording, and three moments inside its hold.
    static func heldMoments(_ editor: EditorState) throws -> (Layer, ClipZoom, [Int]) {
        let clip = try recording(in: editor)
        guard let zooms = clip.zooms, zooms.count == 1, let zoom = zooms.first else {
            throw Failure(description: "the recording has \(clip.zooms?.count ?? 0) zooms, not 1")
        }
        guard let span = clip.timelineSpanMS(of: zoom.id) else {
            throw Failure(description: "the zoom is not on the timeline")
        }
        let eases = zoom.eases
        let from = span.start + eases.inMS + 100
        let to = span.end - eases.outMS - 100
        guard to > from + 200 else { throw Failure(description: "the zoom's hold is too short to sample") }
        return (clip, zoom, [from, (from + to) / 2, to])
    }

    static func expectFollows(_ editor: EditorState) throws -> String {
        let (clip, zoom, moments) = try heldMoments(editor)
        guard zoom.followsCursor else { throw Failure(description: "the zoom does not follow the cursor") }
        guard let document = editor.document else { throw Failure(description: "no document") }
        var centres: [CGPoint] = []
        var said: [String] = []
        for ms in moments {
            guard let window = document.drawn(atTimeMS: ms).layer(id: clip.id)?.zoomWindow else {
                throw Failure(description: "at \(ms) ms the clip is not zoomed")
            }
            let source = clip.motionClockMS(atDocumentTimeMS: ms)
            let pointer = scriptedPoint(atMS: source)
            let margin = window.width * ClipZoom.followMargin - 0.002
            guard pointer.x >= window.minX + margin, pointer.x <= window.maxX - margin,
                  pointer.y >= window.minY + margin, pointer.y <= window.maxY - margin else {
                throw Failure(description: "at \(ms) ms the pointer (\(fmt(pointer))) is not held clear of "
                    + "the frame's edges (\(fmt(window.origin)) to \(fmt(CGPoint(x: window.maxX, y: window.maxY))))")
            }
            guard abs(window.width - zoom.region.width) < 0.002 else {
                throw Failure(description: "at \(ms) ms the frame is \(window.width) of the picture wide, "
                    + "not the zoom's \(zoom.region.width)")
            }
            centres.append(CGPoint(x: window.midX, y: window.midY))
            said.append("\(ms) ms: frame centred at \(fmt(centres.last ?? .zero)), pointer at \(fmt(pointer))")
        }
        let travel = zip(centres, centres.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        guard travel.allSatisfy({ $0 > 0.03 }) else {
            throw Failure(description: "the frame did not move with the pointer: " + said.joined(separator: "; "))
        }
        return "the zoom follows the pointer: " + said.joined(separator: "; ")
    }

    static func expectShapedByHand(_ editor: EditorState) throws -> String {
        let clip = try recording(in: editor)
        guard let zooms = clip.zooms, zooms.count == 1, let zoom = zooms.first,
              let span = clip.timelineSpanMS(of: zoom.id) else {
            throw Failure(description: "the recording has \(clip.zooms?.count ?? 0) zooms, not 1")
        }
        let said = "the zoom runs \(span.start) to \(span.end) ms, eases in over \(zoom.easeInMS) ms and out "
            + "over \(zoom.easeOutMS) ms, at \(EditorState.zoomPercent(zoom))%"
        var wrong: [String] = []
        if zoom.easeOutMS <= ClipZoom.defaultEaseMS + 100 { wrong.append("the way out was not dragged longer") }
        if span.end >= span.start + ClipZoom.defaultLengthMS - 100 { wrong.append("the end was not dragged earlier") }
        if zoom.scale >= ClipZoom.defaultScale - 0.05 { wrong.append("the box was not pulled wider") }
        if editor.zoomDrag != nil { wrong.append("a drag is still in hand") }
        guard wrong.isEmpty else { throw Failure(description: wrong.joined(separator: "; ") + ": " + said) }
        return said
    }

    static func addAtPlayhead(_ editor: EditorState) throws -> String {
        let ms = editor.documentTimeMS
        guard let clip = editor.clipToAddZoom(atMS: ms) else {
            throw Failure(description: "Add Zoom is dimmed at \(ms) ms: no recording here takes one")
        }
        editor.addZoom(toClip: clip, atMS: ms)
        return "Add Zoom at \(ms) ms"
    }

    static func expectPicked(_ editor: EditorState) throws -> String {
        let clip = try recording(in: editor)
        guard editor.selectedZoom?.layerID == clip.id else {
            throw Failure(description: "no zoom on the recording is picked")
        }
        guard let box = editor.zoomBoxInDocument else {
            throw Failure(description: "a zoom is picked and its box is not up on the picture")
        }
        return "a zoom is picked, its box at \(box.integral)"
    }

    static func expectLetGo(_ editor: EditorState) throws -> String {
        let clip = try recording(in: editor)
        guard editor.selectedZoom == nil else { throw Failure(description: "a zoom is still picked") }
        guard editor.selectedLayerID == clip.id else {
            throw Failure(description: "the zoom was let go and so was the recording it was on")
        }
        return "no zoom is picked, and the recording still is"
    }

    static func expectSuggested(_ editor: EditorState) throws -> String {
        let clip = try recording(in: editor)
        guard let zooms = clip.zooms, zooms.count == 1, let zoom = zooms.first else {
            throw Failure(description: "Suggest Zooms left \(clip.zooms?.count ?? 0) zooms, not 1")
        }
        let first = scriptedClickMS.first ?? 0
        let last = scriptedClickMS.last ?? 0
        var wrong: [String] = []
        if zoom.startMS + zoom.eases.inMS > first { wrong.append("it has not arrived by the first click") }
        if zoom.endMS - zoom.eases.outMS < last { wrong.append("it has left before the last click") }
        for ms in scriptedClickMS where !zoom.region.contains(scriptedPoint(atMS: ms)) {
            wrong.append("the click at \(ms) ms is outside its box")
        }
        if editor.selectedZoom?.zoomID != zoom.id { wrong.append("it is not picked") }
        let said = "one zoom from \(zoom.startMS) to \(zoom.endMS) ms at \(EditorState.zoomPercent(zoom))%"
        guard wrong.isEmpty else { throw Failure(description: wrong.joined(separator: "; ") + ": " + said) }
        return said + ", round both clicks"
    }

    static func expectExportMatches(_ editor: EditorState) async throws -> String {
        let (_, _, moments) = try heldMoments(editor)
        guard let document = editor.document else { throw Failure(description: "no document") }
        editor.letGoOfZoom()
        let frames = DocumentFrames(document: document, store: editor.store,
                                    movieURLs: MovieLibrary.shared.urls(in: document))
        defer { frames.putTheStoreBack() }
        var unzoomed = document
        for layer in unzoomed.allLayers where layer.zooms != nil {
            unzoomed.updateLayer(id: layer.id) { $0.zooms = nil }
        }
        let flat = DocumentFrames(document: unzoomed, store: editor.store,
                                  movieURLs: MovieLibrary.shared.urls(in: unzoomed))
        defer { flat.putTheStoreBack() }
        var said: [String] = []
        for ms in moments {
            editor.moveDocumentPlayhead(toMS: ms)
            try? await Task.sleep(for: .milliseconds(900))
            guard let canvas = editor.renderedImage,
                  let written = await frames.frame(atMS: ms),
                  let whole = await flat.frame(atMS: ms) else {
                throw Failure(description: "at \(ms) ms a picture could not be made")
            }
            let apart = difference(canvas, written)
            let zoomedBy = difference(written, whole)
            guard apart < 0.06 else {
                throw Failure(description: "at \(ms) ms the exported frame is not what the canvas shows "
                    + "(they differ by \(pct(apart)) on average)")
            }
            guard zoomedBy > 0.02 else {
                throw Failure(description: "at \(ms) ms the exported frame is the whole picture, not zoomed "
                    + "(it differs from the unzoomed frame by only \(pct(zoomedBy)))")
            }
            said.append("\(ms) ms: export and canvas differ by \(pct(apart)), zoom changes the frame by \(pct(zoomedBy))")
        }
        return "the exported frames match the canvas: " + said.joined(separator: "; ")
    }

    /// The mean difference of two pictures, nought to one, read at 64 x 36.
    static func difference(_ a: CGImage, _ b: CGImage) -> Double {
        guard let x = small(a), let y = small(b), x.count == y.count, !x.isEmpty else { return 1 }
        var total = 0.0
        var count = 0
        for i in stride(from: 0, to: x.count, by: 4) {
            for c in 0..<3 {
                total += abs(Double(x[i + c]) - Double(y[i + c])) / 255
                count += 1
            }
        }
        return total / Double(max(1, count))
    }

    private static func small(_ image: CGImage) -> [UInt8]? {
        let width = 64, height = 36
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }

    private static func fmt(_ p: CGPoint) -> String { String(format: "%.2f, %.2f", p.x, p.y) }
    private static func pct(_ v: Double) -> String { String(format: "%.1f%%", v * 100) }
}
#endif
