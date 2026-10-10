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
/// - `expectZoomScrubMatchesExport` scrubs across the zoom, picked or not, and
///   checks the canvas is the exported frame at every moment, pixel for pixel.
/// - `expectZoomEasesFrameByFrame` steps through the ways in and out and
///   checks the picture moves at every frame.
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

    static func expectThreePicked(_ editor: EditorState) throws -> String {
        let clip = try recording(in: editor)
        let picked = editor.pickedZooms.filter { $0.layerID == clip.id }
        guard picked.count == 3, editor.pickedZooms.count == 3 else {
            throw Failure(description: "\(editor.pickedZooms.count) zooms are picked, not 3")
        }
        let lit = (clip.zooms ?? []).filter { editor.isZoomPicked(ClipZoomRef(layerID: clip.id, zoomID: $0.id)) }
        guard lit.count == 3 else { throw Failure(description: "\(lit.count) bars are lit, not 3") }
        guard editor.zoomBoxInDocument == nil, !editor.showsZoomBox else {
            throw Failure(description: "three zooms are picked and a zoom box is still up on the picture")
        }
        return "three of \(clip.zooms?.count ?? 0) zooms are picked, their bars lit, no box on the picture"
    }

    static func expectEveryPicked(_ editor: EditorState) throws -> String {
        let clip = try recording(in: editor)
        let zooms = clip.zooms ?? []
        let lit = zooms.filter { editor.isZoomPicked(ClipZoomRef(layerID: clip.id, zoomID: $0.id)) }
        guard zooms.count > 1, lit.count == zooms.count, editor.pickedZooms.count == zooms.count else {
            throw Failure(description: "\(lit.count) of \(zooms.count) zooms are picked")
        }
        guard editor.zoomBoxInDocument == nil else {
            throw Failure(description: "every zoom is picked and a zoom box is still up on the picture")
        }
        return "all \(zooms.count) zooms are picked, no box on the picture"
    }

    static func expectPickedEaseInAlike(_ editor: EditorState) throws -> String {
        let clip = try recording(in: editor)
        let zooms = clip.zooms ?? []
        let picked = zooms.filter { editor.isZoomPicked(ClipZoomRef(layerID: clip.id, zoomID: $0.id)) }
        let rest = zooms.filter { !editor.isZoomPicked(ClipZoomRef(layerID: clip.id, zoomID: $0.id)) }
        let eases = Set(picked.map(\.easeInMS))
        guard picked.count > 1, eases.count == 1, let ease = eases.first else {
            throw Failure(description: "the \(picked.count) zooms picked ease in over \(picked.map(\.easeInMS)) ms")
        }
        guard rest.contains(where: { $0.easeInMS != ease }) else {
            throw Failure(description: "every zoom eases in over \(ease) ms, picked or not: "
                + "the change reached zooms that were not picked")
        }
        return "the \(picked.count) zooms picked all ease in over \(ease) ms; the others over "
            + "\(rest.map(\.easeInMS)) ms"
    }

    static func expectCount(_ editor: EditorState, _ count: Int, nonePicked: Bool = false) throws -> String {
        let clip = try recording(in: editor)
        let zooms = clip.zooms ?? []
        let said = zooms.map { "\($0.startMS)-\($0.endMS) ms in \($0.easeInMS)" }.joined(separator: ", ")
        guard zooms.count == count else {
            throw Failure(description: "the recording has \(zooms.count) zooms, not \(count): \(said)")
        }
        if nonePicked, !editor.pickedZooms.isEmpty {
            throw Failure(description: "\(editor.pickedZooms.count) zooms are still picked after they went")
        }
        return "\(count) zooms: \(said)"
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

    static func expectBoxDown(_ editor: EditorState) throws -> String {
        let clip = try recording(in: editor)
        guard editor.selectedZoom?.layerID == clip.id else {
            throw Failure(description: "no zoom on the recording is picked")
        }
        if let box = editor.zoomBoxInDocument {
            throw Failure(description: "the zoom's box is still up at \(box.integral): the picture shows the "
                + "whole recording, not what the zoom does at \(editor.documentTimeMS) ms")
        }
        return "a zoom is picked with its box down: the picture is the zoom at \(editor.documentTimeMS) ms"
    }

    /// The one zoom on the recording and where it runs on the timeline.
    static func theZoom(_ editor: EditorState) throws -> (Layer, ClipZoom, start: Int, end: Int) {
        let clip = try recording(in: editor)
        guard let zooms = clip.zooms, zooms.count == 1, let zoom = zooms.first,
              let span = clip.timelineSpanMS(of: zoom.id) else {
            throw Failure(description: "the recording has \(clip.zooms?.count ?? 0) zooms, not 1")
        }
        return (clip, zoom, span.start, span.end)
    }

    /// Scrub the playhead to `ms` the way a click on the ruler does, and wait
    /// for the picture of that moment to land.
    static func scrub(_ editor: EditorState, toMS ms: Int, settle: Duration = .milliseconds(700)) async {
        editor.beginRulerPress(atMS: ms, reachMS: 0)
        editor.dragRulerPress(toMS: ms, moved: false, snapMS: 0)
        editor.endRulerPress(atMS: ms, moved: false)
        try? await Task.sleep(for: settle)
    }

    static func expectScrubMatchesExport(_ editor: EditorState) async throws -> String {
        let (clip, zoom, start, end) = try theZoom(editor)
        guard let document = editor.document else { throw Failure(description: "no document") }
        let picked = editor.selectedZoom != nil
        let eases = zoom.eases
        let moments = [
            ("way in, a quarter", start + eases.inMS / 4),
            ("way in, half", start + eases.inMS / 2),
            ("way in, three quarters", start + eases.inMS * 3 / 4),
            ("hold", (start + eases.inMS + end - eases.outMS) / 2),
            ("way out, half", end - eases.outMS / 2),
        ]
        let frames = DocumentFrames(document: document, store: editor.store,
                                    movieURLs: MovieLibrary.shared.urls(in: document))
        defer { frames.putTheStoreBack() }
        var unzoomed = document
        unzoomed.updateLayer(id: clip.id) { $0.zooms = nil }
        let flat = DocumentFrames(document: unzoomed, store: editor.store,
                                  movieURLs: MovieLibrary.shared.urls(in: unzoomed))
        defer { flat.putTheStoreBack() }
        var said: [String] = []
        var worst = 0.0
        for (name, ms) in moments {
            await scrub(editor, toMS: ms)
            if picked, let box = editor.zoomBoxInDocument {
                throw Failure(description: "scrubbed to \(ms) ms (\(name)) with the zoom picked, and the "
                    + "picture shows the whole recording with the box at \(box.integral), not the zoom")
            }
            guard let canvas = editor.renderedImage,
                  let written = await frames.frame(atMS: ms),
                  let whole = await flat.frame(atMS: ms) else {
                throw Failure(description: "at \(ms) ms a picture could not be made")
            }
            let apart = pixelsApart(canvas, written)
            worst = max(worst, apart)
            let zoomedBy = pixelsApart(written, whole)
            guard apart <= 0.01 else {
                throw Failure(description: "scrubbed to \(ms) ms (\(name)): \(pct(apart)) of the canvas's "
                    + "pixels differ from the exported frame, more than 1% (the zoom changes "
                    + "\(pct(zoomedBy)) of them)")
            }
            if name == "hold", zoomedBy < 0.1 {
                throw Failure(description: "at \(ms) ms, inside the hold, the exported frame is barely zoomed "
                    + "(\(pct(zoomedBy)) of pixels changed)")
            }
            said.append("\(name) \(ms) ms: \(pct(apart)) apart, zoom changes \(pct(zoomedBy))")
        }
        if picked, editor.selectedZoom == nil {
            throw Failure(description: "scrubbing let the picked zoom go")
        }
        return "scrubbed with the zoom \(picked ? "picked" : "not picked"), the canvas is the export at "
            + "every moment (worst \(pct(worst)) of pixels apart): " + said.joined(separator: "; ")
    }

    static func expectEasesFrameByFrame(_ editor: EditorState) async throws -> String {
        let (clip, zoom, start, end) = try theZoom(editor)
        let eases = zoom.eases
        let step = MovieRef.frameStepMS
        func widthDrawn(at ms: Int) async throws -> Double {
            await scrub(editor, toMS: ms, settle: .milliseconds(60))
            guard let drawn = editor.playtestLastDrawn?.layer(id: clip.id) else {
                throw Failure(description: "at \(ms) ms the canvas was given no recording")
            }
            return Double(drawn.zoomWindow?.width ?? 1)
        }
        var into: [Double] = []
        for ms in stride(from: start + step, to: start + eases.inMS, by: step) {
            into.append(try await widthDrawn(at: ms))
        }
        var outOf: [Double] = []
        for ms in stride(from: end - eases.outMS + step, to: end, by: step) {
            outOf.append(try await widthDrawn(at: ms))
        }
        guard into.count >= 5, outOf.count >= 5 else {
            throw Failure(description: "the zoom's ways in and out are too short to step through")
        }
        let inSteps = zip(into, into.dropFirst()).filter { $1 >= $0 }.count
        let outSteps = zip(outOf, outOf.dropFirst()).filter { $1 <= $0 }.count
        func widths(_ w: [Double]) -> String { w.map { String(format: "%.3f", $0) }.joined(separator: " ") }
        guard inSteps == 0, outSteps == 0 else {
            throw Failure(description: "the picture does not move at every frame: in \(widths(into)); out "
                + "\(widths(outOf))")
        }
        return "frame by frame the picture goes in over \(into.count) frames (\(widths(into))) and back out "
            + "over \(outOf.count) (\(widths(outOf)))"
    }

    // MARK: A zoom on a cropped recording

    /// The three ways a recording gets cropped, each the way the app does it:
    /// the Crop tool with nothing picked crops the canvas, the Crop tool with
    /// the clip picked crops the clip itself, and Crop Left and Crop Top keyed
    /// on the clip's Motion list cut its edges in. The region kept is the same
    /// share of the recording each time: a 4:3 piece off-centre, so the
    /// picture left is neither the recording's shape nor in its middle, and it
    /// keeps the sample's tile, the one part of it with something to read.
    static let croppedShare = CGRect(x: 0.03, y: 0.1, width: 0.625, height: 0.75)

    static func cropCanvas(_ editor: EditorState) throws -> String {
        let clip = try recording(in: editor)
        guard let canvas = editor.document?.canvasSize else { throw Failure(description: "no document") }
        editor.selectLayer(nil)
        editor.setTool(.crop)
        let rect = CGRect(x: canvas.width * croppedShare.minX, y: canvas.height * croppedShare.minY,
                          width: canvas.width * croppedShare.width, height: canvas.height * croppedShare.height)
        editor.setCropRect(rect)
        editor.commitCrop()
        editor.selectLayer(clip.id)
        guard let after = editor.document?.canvasSize, abs(after.width - rect.width) < 1 else {
            throw Failure(description: "the Crop tool did not crop the canvas to \(rect.integral)")
        }
        return "the canvas is cropped to \(rect.integral) of the recording"
    }

    static func cropClip(_ editor: EditorState) throws -> String {
        let clip = try recording(in: editor)
        editor.selectLayer(clip.id)
        editor.setTool(.crop)
        let frame = clip.frame.standardized
        let rect = CGRect(x: frame.minX + frame.width * croppedShare.minX,
                          y: frame.minY + frame.height * croppedShare.minY,
                          width: frame.width * croppedShare.width, height: frame.height * croppedShare.height)
        editor.setCropRect(rect)
        editor.commitCrop()
        guard let cropped = editor.document?.layer(id: clip.id), cropped.crop != nil else {
            throw Failure(description: "the Crop tool did not crop the clip")
        }
        return "the clip is cropped to \(cropped.frame.integral), its picture to \(cropped.crop?.integral ?? .zero)"
    }

    static func cropByKeys(_ editor: EditorState) throws -> String {
        let clip = try recording(in: editor)
        editor.selectLayer(clip.id)
        let edges: [(MotionProperty, Double)] = [
            (.cropLeft, Double(croppedShare.minX) * 100), (.cropTop, Double(croppedShare.minY) * 100),
            (.cropRight, Double(1 - croppedShare.maxX) * 100), (.cropBottom, Double(1 - croppedShare.maxY) * 100),
        ]
        for (edge, percent) in edges {
            editor.addMotion(edge)
            guard let motion = editor.document?.layer(id: clip.id)?.motions?.first(where: { $0.property == edge })
            else { throw Failure(description: "\(edge.title) did not go on the clip's Motion list") }
            editor.updateMotion(id: motion.id) {
                $0.from = .number(percent)
                $0.to = .number(percent)
            }
        }
        editor.pauseMotionPreview()
        editor.pauseDocument()
        guard let shown = editor.document?.drawn(atTimeMS: editor.documentTimeMS).layer(id: clip.id),
              shown.crop != nil else {
            throw Failure(description: "the keyed crop edges did not crop the clip as drawn")
        }
        return "the clip's four edges are keyed in, drawing it at \(shown.frame.integral)"
    }

    /// The part of the clip a person can see at a moment, in document points:
    /// the clip as drawn, inside the canvas. Read off the document, not the
    /// zoom's own idea of it.
    static func visiblePicture(_ document: PhotonzDocument, clip: UUID, atMS ms: Int) -> CGRect? {
        var unzoomed = document
        unzoomed.updateLayer(id: clip) { $0.zooms = nil }
        let drawn = unzoomed.drawn(atTimeMS: ms)
        guard let frame = drawn.canvasFrame(of: clip)?.standardized else { return nil }
        let seen = frame.intersection(CGRect(origin: .zero, size: document.canvasSize))
        return seen.isNull || seen.width < 1 || seen.height < 1 ? nil : seen
    }

    /// Draw the picked zoom's box round a spot of the picture a person can see,
    /// the way a hand does: a press beside the box, a drag, a let go.
    static func drawBoxOnVisiblePicture(_ editor: EditorState) throws -> String {
        let clip = try recording(in: editor)
        guard let document = editor.document,
              let seen = visiblePicture(document, clip: clip.id, atMS: editor.documentTimeMS) else {
            throw Failure(description: "none of the recording is on the canvas")
        }
        guard editor.zoomBoxInDocument != nil else { throw Failure(description: "the zoom's box is not up") }
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: seen.minX + seen.width * x, y: seen.minY + seen.height * y)
        }
        // Round the tile's count, the part of the sample with detail in it.
        let from = at(0.05, 0.2), to = at(0.32, 0.45)
        guard editor.zoomBoxDown(at: from) else { throw Failure(description: "the box did not take the press") }
        for step in 1...8 {
            let t = CGFloat(step) / 8
            editor.zoomBoxDragged(to: CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
        }
        editor.zoomBoxReleased(at: to)
        guard let box = editor.zoomBoxInDocument else {
            throw Failure(description: "the box went down when the drag let go")
        }
        let label = editor.zoomInHand.map { ZoomLane.label($0.zoom) } ?? "nothing"
        return "the box drawn from (\(Int(from.x)), \(Int(from.y))) to (\(Int(to.x)), \(Int(to.y))) on the "
            + "visible picture \(seen.integral) lands at \(box.integral), labelled \(label)"
    }

    /// The test the user asked for: with the box up, read where it is and what
    /// it says; then at the zoom's full point the exported frame must be what
    /// was inside the box, filling the visible picture. Measured three ways:
    /// where the box's corners land (within 2 px of the picture's own), how far
    /// in it really is against the box's percent, and the pixels themselves.
    static func expectShowsItsBox(_ editor: EditorState) async throws -> String {
        let (clip, zoom, start, end) = try theZoom(editor)
        guard let document = editor.document else { throw Failure(description: "no document") }
        guard let box = editor.zoomBoxInDocument else {
            throw Failure(description: "the zoom's box is not up to read")
        }
        let percent = EditorState.zoomPercent(zoom)
        let hold = (start + zoom.eases.inMS + end - zoom.eases.outMS) / 2
        guard let seen = visiblePicture(document, clip: clip.id, atMS: hold) else {
            throw Failure(description: "none of the recording is on the canvas")
        }
        editor.letGoOfZoom()

        // Where the box's corners go: the drawn clip's frame and the part of
        // its picture the zoom cuts out, the renderer's own two numbers.
        let drawn = document.drawn(atTimeMS: hold)
        guard let frame = drawn.canvasFrame(of: clip.id)?.standardized,
              let window = drawn.layer(id: clip.id)?.zoomWindow, window.width > 0, window.height > 0 else {
            throw Failure(description: "at \(hold) ms, the zoom's full point, the clip is not zoomed")
        }
        func landed(_ p: CGPoint) -> CGPoint {
            let u = CGPoint(x: (p.x - frame.minX) / frame.width, y: (p.y - frame.minY) / frame.height)
            return CGPoint(x: frame.minX + (u.x - window.minX) / window.width * frame.width,
                           y: frame.minY + (u.y - window.minY) / window.height * frame.height)
        }
        let pairs = [(CGPoint(x: box.minX, y: box.minY), CGPoint(x: seen.minX, y: seen.minY)),
                     (CGPoint(x: box.maxX, y: box.minY), CGPoint(x: seen.maxX, y: seen.minY)),
                     (CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: seen.maxX, y: seen.maxY)),
                     (CGPoint(x: box.minX, y: box.maxY), CGPoint(x: seen.minX, y: seen.maxY))]
        let miss = pairs.map { hypot(landed($0.0).x - $0.1.x, landed($0.0).y - $0.1.y) }.max() ?? .infinity
        let really = Double(seen.width / box.width)
        let reallyTall = Double(seen.height / box.height)

        // The pixels: the zoomed frame's visible picture against the
        // unzoomed frame's box, blown up to the same size.
        let frames = DocumentFrames(document: document, store: editor.store,
                                    movieURLs: MovieLibrary.shared.urls(in: document))
        defer { frames.putTheStoreBack() }
        var unzoomed = document
        unzoomed.updateLayer(id: clip.id) { $0.zooms = nil }
        let flat = DocumentFrames(document: unzoomed, store: editor.store,
                                  movieURLs: MovieLibrary.shared.urls(in: unzoomed))
        defer { flat.putTheStoreBack() }
        guard let zoomed = await frames.frame(atMS: hold), let whole = await flat.frame(atMS: hold) else {
            throw Failure(description: "at \(hold) ms a picture could not be made")
        }
        let k = CGFloat(zoomed.width) / document.canvasSize.width
        func pixels(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX * k, y: r.minY * k, width: r.width * k, height: r.height * k).integral
        }
        guard let shown = zoomed.cropping(to: pixels(seen)), let inBox = whole.cropping(to: pixels(box)) else {
            throw Failure(description: "the frames could not be cut to the picture and the box")
        }
        let apart = pixelsApart(shown, inBox)
        let detail = spread(inBox)
        let said = "box \(box.integral) on the visible picture \(seen.integral), labelled \(percent)%; at its full "
            + "point (\(hold) ms) its corners land within \(String(format: "%.1f", miss)) px of the picture's, it is "
            + "really \(String(format: "%.0f", really * 100))% across and \(String(format: "%.0f", reallyTall * 100))% "
            + "down, and \(pct(apart)) of the frame's pixels differ from the box's contents"
        var wrong: [String] = []
        if miss > 2 { wrong.append("the box's corners miss the picture's by up to \(String(format: "%.1f", miss)) px") }
        if abs(really * 100 - Double(percent)) > max(2, Double(percent) * 0.01) {
            wrong.append("the box says \(percent)% and the zoom is really \(String(format: "%.0f", really * 100))%")
        }
        if apart > 0.05 { wrong.append("the zoomed frame is not what was inside the box") }
        if detail < 0.05 { wrong.append("the box is on a part of the picture with nothing in it to compare") }
        guard wrong.isEmpty else { throw Failure(description: wrong.joined(separator: "; ") + ": " + said) }
        return said
    }

    /// The share of two pictures' pixels, nought to one, that differ by more
    /// than a tenth in any channel, read at 320 x 200.
    static func pixelsApart(_ a: CGImage, _ b: CGImage) -> Double {
        guard let x = small(a, width: 320, height: 200), let y = small(b, width: 320, height: 200),
              x.count == y.count, !x.isEmpty else { return 1 }
        var apart = 0
        for i in stride(from: 0, to: x.count, by: 4) {
            let most = (0..<3).map { abs(Int(x[i + $0]) - Int(y[i + $0])) }.max() ?? 0
            if most > 25 { apart += 1 }
        }
        return Double(apart) / Double(x.count / 4)
    }

    /// The share of a picture's pixels, nought to one, more than a tenth away
    /// from its average colour: how much there is in it to compare.
    static func spread(_ image: CGImage) -> Double {
        guard let x = small(image, width: 160, height: 100), !x.isEmpty else { return 0 }
        let count = x.count / 4
        let mean = (0..<3).map { c in stride(from: c, to: x.count, by: 4).reduce(0) { $0 + Int(x[$1]) } / count }
        var off = 0
        for i in stride(from: 0, to: x.count, by: 4) where (0..<3).contains(where: { abs(Int(x[i + $0]) - mean[$0]) > 25 }) {
            off += 1
        }
        return Double(off) / Double(count)
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

    private static func small(_ image: CGImage, width: Int = 64, height: Int = 36) -> [UInt8]? {
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
