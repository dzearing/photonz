import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A zoom is aimed at the part of a clip a person can SEE (`ZoomStage.swift`):
/// cropped by the canvas, by the clip's own crop or by its keyed crop edges,
/// the box drawn on what is left is exactly what fills it at the zoom's full
/// point, and the box's percent is how far in that really is.
///
/// Reported by the user on 2026-10-06: on a cropped video the zoom went far
/// further in than the box and showed a different part of the picture.
@Suite("A zoom on a cropped recording")
struct ZoomStageTests {

    /// A recording twice the size of the clip that plays it, as a real Retina
    /// recording opened in a window is.
    static func movie() -> MovieRef {
        MovieRef(id: UUID(uuidString: "5A9E0001-1111-2222-3333-444444444444")!,
                 pixelSize: CGSize(width: 2000, height: 1000), durationMS: 12_000)
    }

    static func clip() -> Layer {
        let reel = movie()
        var layer = Layer(name: "screen-recording", content: .image(reel.frameRef(atSourceMS: 0)),
                          frame: CGRect(x: 0, y: 0, width: 1000, height: 500))
        layer.movie = reel
        layer.time = LayerTime(inMS: 0, outMS: 12_000, sourceInMS: 0, sourceLengthMS: 12_000)
        return layer
    }

    static func document(_ layer: Layer = clip()) -> PhotonzDocument {
        var document = PhotonzDocument(canvasSize: CGSize(width: 1000, height: 500), layers: [layer])
        document.durationMS = 12_000
        return document
    }

    /// The 4:3 piece off the middle every crop below keeps, in the clip's
    /// points: neither the recording's shape nor in its middle.
    static let kept = CGRect(x: 100, y: 50, width: 400, height: 300)

    enum Crop: CaseIterable { case none, canvas, clip, keyed }

    static func cropped(_ crop: Crop) -> PhotonzDocument {
        var document = document()
        let id = document.layers[0].id
        switch crop {
        case .none:
            break
        case .canvas:
            document.crop(to: kept)
        case .clip:
            document.updateLayer(id: id) { $0.cropContent(to: kept) }
        case .keyed:
            let frame = document.layers[0].frame
            let edges: [(MotionProperty, CGFloat)] = [
                (.cropLeft, kept.minX / frame.width), (.cropTop, kept.minY / frame.height),
                (.cropRight, 1 - kept.maxX / frame.width), (.cropBottom, 1 - kept.maxY / frame.height),
            ]
            document.updateLayer(id: id) { layer in
                layer.motions = edges.map { edge, share in
                    var motion = LayerMotion.starting(edge, on: layer)
                    motion.from = .number(Double(share) * 100)
                    motion.to = .number(Double(share) * 100)
                    return motion
                }
            }
        }
        return document
    }

    static let hold = 4000

    static func zoomed(_ crop: Crop, scale: Double = 3, center: CGPoint? = nil,
                       follows: PointerTrack? = nil) -> (PhotonzDocument, UUID) {
        var document = cropped(crop)
        let id = document.layers[0].id
        let stage = document.zoomStage(ofClip: id, atTimeMS: hold) ?? .whole
        // A spot inside what is kept unless told otherwise: a quarter of the
        // way across the kept piece and two thirds down.
        let spot = center ?? stage.fromStage(CGPoint(x: 0.25, y: 0.66))
        var zoom = ClipZoom(startMS: 2000, endMS: 6000, easeInMS: 1000, easeOutMS: 1000,
                            scale: scale, center: spot)
        if let follows {
            zoom.followsCursor = true
            zoom.bakeCursor(from: follows)
        }
        document.updateLayer(id: id) { $0.zooms = [zoom] }
        return (document, id)
    }

    /// Where a point of the unzoomed picture (document points) is drawn once
    /// the clip is zoomed: the renderer's own two numbers, the drawn frame and
    /// the part of its picture the zoom cuts out.
    static func landed(_ p: CGPoint, in document: PhotonzDocument, clip id: UUID, atMS ms: Int) -> CGPoint? {
        let drawn = document.drawn(atTimeMS: ms)
        guard let frame = drawn.canvasFrame(of: id)?.standardized,
              let window = drawn.layer(id: id)?.zoomWindow else { return nil }
        let u = CGPoint(x: (p.x - frame.minX) / frame.width, y: (p.y - frame.minY) / frame.height)
        return CGPoint(x: frame.minX + (u.x - window.minX) / window.width * frame.width,
                       y: frame.minY + (u.y - window.minY) / window.height * frame.height)
    }

    static func corners(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
         CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
    }

    // MARK: - The stage

    @Test func aClipWhollyOnTheCanvasIsItsOwnStage() throws {
        let document = Self.document()
        let stage = try #require(document.zoomStage(ofClip: document.layers[0].id, atTimeMS: Self.hold))
        #expect(stage.picture == CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(stage.visible == CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(stage.onCanvas == CGRect(x: 0, y: 0, width: 1000, height: 500))
    }

    @Test(arguments: [Crop.canvas, .clip, .keyed])
    func theStageIsThePartOfTheRecordingLeftOnTheCanvas(_ crop: Crop) throws {
        let document = Self.cropped(crop)
        let stage = try #require(document.zoomStage(ofClip: document.layers[0].id, atTimeMS: Self.hold))
        let seen = stage.seen
        #expect(abs(seen.minX - 0.1) < 0.001 && abs(seen.minY - 0.1) < 0.001, "\(crop): \(seen)")
        #expect(abs(seen.width - 0.4) < 0.001 && abs(seen.height - 0.6) < 0.001, "\(crop): \(seen)")
        // A spot of the recording and back.
        let spot = CGPoint(x: 0.3, y: 0.55)
        let there = stage.fromStage(stage.toStage(spot))
        #expect(abs(there.x - spot.x) < 1e-9 && abs(there.y - spot.y) < 1e-9)
    }

    // MARK: - The box is what fills the picture

    @Test(arguments: Crop.allCases)
    func theBoxsCornersLandOnThePicturesCorners(_ crop: Crop) throws {
        let (document, id) = Self.zoomed(crop)
        let stage = try #require(document.zoomStage(ofClip: id, atTimeMS: Self.hold))
        let zoom = try #require(document.layer(id: id)?.zooms?.first)
        let box = stage.onCanvas(zoom.target(atMS: Self.hold, on: stage))
        for (corner, goal) in zip(Self.corners(box), Self.corners(stage.onCanvas)) {
            let at = try #require(Self.landed(corner, in: document, clip: id, atMS: Self.hold))
            #expect(hypot(at.x - goal.x, at.y - goal.y) < 0.01,
                    "\(crop): the box's corner \(corner) lands at \(at), not on the picture's \(goal)")
        }
    }

    @Test(arguments: Crop.allCases)
    func theBoxsPercentIsHowFarInItReallyIs(_ crop: Crop) throws {
        let (document, id) = Self.zoomed(crop, scale: 3)
        let stage = try #require(document.zoomStage(ofClip: id, atTimeMS: Self.hold))
        let zoom = try #require(document.layer(id: id)?.zooms?.first)
        let box = stage.onCanvas(zoom.target(atMS: Self.hold, on: stage))
        #expect(abs(stage.onCanvas.width / box.width - 3) < 0.001, "\(crop): \(box) on \(stage.onCanvas)")
        #expect(abs(stage.onCanvas.height / box.height - 3) < 0.001, "\(crop): \(box) on \(stage.onCanvas)")
    }

    @Test(arguments: Crop.allCases)
    func theBoxHasThePicturesShape(_ crop: Crop) throws {
        let (document, id) = Self.zoomed(crop)
        let stage = try #require(document.zoomStage(ofClip: id, atTimeMS: Self.hold))
        let zoom = try #require(document.layer(id: id)?.zooms?.first)
        let box = stage.onCanvas(zoom.target(atMS: Self.hold, on: stage))
        let picture = stage.onCanvas.width / stage.onCanvas.height
        #expect(abs(box.width / box.height - picture) < 0.001)
    }

    @Test(arguments: [Crop.canvas, .clip, .keyed])
    func theSpotIsAPointOfTheRecording(_ crop: Crop) throws {
        // The middle of the box is the spot of the recording the zoom is on,
        // wherever the crop has put that spot on the canvas.
        let spot = CGPoint(x: 0.22, y: 0.5)
        let (document, id) = Self.zoomed(crop, center: spot)
        let stage = try #require(document.zoomStage(ofClip: id, atTimeMS: Self.hold))
        let zoom = try #require(document.layer(id: id)?.zooms?.first)
        let box = stage.onCanvas(zoom.target(atMS: Self.hold, on: stage))
        // The recording is drawn at half size from the canvas's own origin
        // before any crop, so its point is half its pixels, less what the
        // canvas crop took off the top-left.
        let shift: CGPoint = crop == .canvas ? Self.kept.origin : .zero
        let goal = CGPoint(x: spot.x * 1000 - shift.x, y: spot.y * 500 - shift.y)
        #expect(abs(box.midX - goal.x) < 0.01 && abs(box.midY - goal.y) < 0.01, "\(crop): \(box)")
    }

    @Test func anUncroppedZoomIsUnchanged() throws {
        let (document, id) = Self.zoomed(.none, scale: 2, center: CGPoint(x: 0.75, y: 0.25))
        let window = try #require(document.drawn(atTimeMS: Self.hold).layer(id: id)?.zoomWindow)
        let zoom = try #require(document.layer(id: id)?.zooms?.first)
        #expect(window == zoom.window(atMS: Self.hold))
        #expect(window == CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
    }

    @Test(arguments: [Crop.canvas, .clip, .keyed])
    func theWayInStartsFromTheWholePicture(_ crop: Crop) throws {
        // Just after the zoom starts, what is drawn is (nearly) the picture
        // as it was: no jump at the first frame of the way in.
        let (document, id) = Self.zoomed(crop)
        let window = try #require(document.drawn(atTimeMS: 2010).layer(id: id)?.zoomWindow)
        #expect(window.width > 0.99 && window.minX > -0.01 && window.maxX < 1.01, "\(window)")
    }

    // MARK: - Following and suggesting

    @Test(arguments: [Crop.canvas, .clip, .keyed])
    func aFollowingZoomKeepsThePointerInThePictureYouSee(_ crop: Crop) throws {
        // The pointer wanders across the part of the recording that is kept.
        var samples: [PointerSample] = []
        for ms in stride(from: 0, through: 12_000, by: 33) {
            let t = Double(ms) / 12_000
            samples.append(PointerSample(ms: ms, x: 2000 * (0.15 + 0.3 * t), y: 1000 * (0.3 + 0.3 * t)))
        }
        let track = PointerTrack(pixelSize: CGSize(width: 2000, height: 1000), samples: samples, clicks: [])
        let (document, id) = Self.zoomed(crop, scale: 2, follows: track)
        let stage = try #require(document.zoomStage(ofClip: id, atTimeMS: Self.hold))
        for ms in [3200, 4000, 4800] {
            let p = try #require(track.position(atMS: ms))
            let unzoomed = stage.onCanvas(CGPoint(x: p.x / 2000, y: p.y / 1000))
            let at = try #require(Self.landed(unzoomed, in: document, clip: id, atMS: ms))
            #expect(stage.onCanvas.insetBy(dx: 5, dy: 5).contains(at),
                    "\(crop) at \(ms) ms: the pointer is drawn at \(at), outside \(stage.onCanvas)")
        }
    }

    @Test(arguments: [Crop.canvas, .clip, .keyed])
    func aSuggestedZoomFramesTheClicksYouSee(_ crop: Crop) throws {
        var document = Self.cropped(crop)
        let id = document.layers[0].id
        let clicks = [PointerClick(downMS: 4000, upMS: 4080, point: CGPoint(x: 500, y: 500), button: .left),
                      PointerClick(downMS: 4600, upMS: 4680, point: CGPoint(x: 700, y: 600), button: .left)]
        let made = document.addSuggestedZooms(toClip: id, clicks: clicks)
        let zoom = try #require(made.first)
        let stage = try #require(document.zoomStage(ofClip: id, atTimeMS: Self.hold))
        let box = stage.onCanvas(zoom.target(atMS: Self.hold, on: stage))
        for click in clicks {
            let p = stage.onCanvas(CGPoint(x: click.point.x / 2000, y: click.point.y / 1000))
            #expect(box.contains(p), "\(crop): the click at \(click.point) is at \(p), outside the box \(box)")
        }
        #expect(stage.onCanvas.contains(box), "\(crop): the box \(box) leaves the picture \(stage.onCanvas)")
    }

    // MARK: - Editing keeps it on the picture

    @Test(arguments: [Crop.canvas, .clip])
    func aSpotPushedPastTheEdgeStopsAtThePicturesEdge(_ crop: Crop) throws {
        var (document, id) = Self.zoomed(crop, scale: 2)
        let zoomID = try #require(document.layer(id: id)?.zooms?.first?.id)
        document.updateZoom(onClip: id, id: zoomID) { $0.center = CGPoint(x: 0.99, y: 0.01) }
        let stage = try #require(document.zoomStage(ofClip: id, atTimeMS: Self.hold))
        let zoom = try #require(document.layer(id: id)?.zooms?.first)
        let region = zoom.region(on: stage)
        #expect(abs(region.maxX - 1) < 1e-6 && abs(region.minY) < 1e-6, "\(crop): \(region)")
        // ...and the spot written down is the middle of that box.
        let middle = stage.toStage(zoom.center)
        #expect(abs(middle.x - region.midX) < 1e-6 && abs(middle.y - region.midY) < 1e-6)
    }

    @Test func aZoomAddedWithNoPointerSitsInTheMiddleOfThePictureYouSee() throws {
        var document = Self.cropped(.canvas)
        let id = document.layers[0].id
        let added = document.addZoom(toClip: id, atTimeMS: 2000, around: nil)
        let zoom = try #require(added)
        let stage = try #require(document.zoomStage(ofClip: id, atTimeMS: 2000))
        let middle = stage.toStage(zoom.center)
        #expect(abs(middle.x - 0.5) < 1e-6 && abs(middle.y - 0.5) < 1e-6)
    }

    // MARK: - Zooms written before

    /// A zoom as a document written before this stored it: no mark, and its
    /// numbers fractions of the clip's whole frame and its picture.
    static func reopened(_ document: PhotonzDocument) throws -> PhotonzDocument {
        var legacy = document
        for layer in legacy.allLayers where layer.zooms != nil {
            legacy.updateLayer(id: layer.id) { $0.zooms = $0.zooms?.map { var z = $0; z.aimedAtWhatIsSeen = nil; return z } }
        }
        let data = try JSONEncoder().encode(legacy)
        #expect(!(String(data: data, encoding: .utf8) ?? "").contains("aimedAtWhatIsSeen"))
        return try JSONDecoder().decode(PhotonzDocument.self, from: data)
    }

    @Test func aZoomWrittenBeforeOnAnUncroppedClipOpensUnchanged() throws {
        let (document, id) = Self.zoomed(.none, scale: 2.5, center: CGPoint(x: 0.7, y: 0.3))
        let opened = try Self.reopened(document)
        let zoom = try #require(opened.layer(id: id)?.zooms?.first)
        #expect(zoom.scale == 2.5 && zoom.center == CGPoint(x: 0.7, y: 0.3))
        #expect(zoom.aimedAtWhatIsSeen == true)
    }

    @Test func aZoomWrittenBeforeOnACroppedClipOpensShowingWhatItsBoxShowed() throws {
        // Before, the box was fractions of the cropped clip's own frame.
        var document = Self.cropped(.clip)
        let id = document.layers[0].id
        let old = ClipZoom(startMS: 2000, endMS: 6000, scale: 2, center: CGPoint(x: 0.25, y: 0.75))
        document.updateLayer(id: id) { $0.zooms = [old] }
        let opened = try Self.reopened(document)
        let zoom = try #require(opened.layer(id: id)?.zooms?.first)
        let stage = try #require(opened.zoomStage(ofClip: id, atTimeMS: Self.hold))
        // What its box covered, in the clip's frame: the old region.
        let frame = Self.kept
        let oldBox = CGRect(x: frame.minX + 0 * frame.width, y: frame.minY + 0.5 * frame.height,
                            width: 0.5 * frame.width, height: 0.5 * frame.height)
        let box = stage.onCanvas(zoom.target(atMS: Self.hold, on: stage))
        #expect(abs(box.minX - oldBox.minX) < 0.01 && abs(box.minY - oldBox.minY) < 0.01
                && abs(box.width - oldBox.width) < 0.01 && abs(box.height - oldBox.height) < 0.01,
                "opened at \(box), was \(oldBox)")
    }

    @Test func aZoomWrittenBeforeOnACroppedCanvasOpensAtTheSizeItsBoxWas() throws {
        // Before, the box was fractions of the clip's whole frame, which runs
        // past the cropped canvas: 1000 wide, of which 400 are seen. A box a
        // fifth of the frame across was 200 points: half the picture seen.
        var document = Self.cropped(.canvas)
        let id = document.layers[0].id
        let old = ClipZoom(startMS: 2000, endMS: 6000, scale: 5, center: CGPoint(x: 0.3, y: 0.3))
        document.updateLayer(id: id) { $0.zooms = [old] }
        let opened = try Self.reopened(document)
        let zoom = try #require(opened.layer(id: id)?.zooms?.first)
        #expect(abs(zoom.scale - 2) < 1e-9, "opened at \(zoom.scale)")
        #expect(zoom.center == CGPoint(x: 0.3, y: 0.3))
    }

    // MARK: - Clicks drawn on a cropped clip

    @Test func aClickIsDrawnWhereItIsOnACroppedClip() throws {
        var document = Self.cropped(.clip)
        let id = document.layers[0].id
        let click = PointerClick(downMS: 4000, upMS: 4080, point: CGPoint(x: 500, y: 400), button: .left)
        document.updateLayer(id: id) {
            $0.clickEffect = ClickEffect(isOn: true)
            $0.addedClicks = [click]
        }
        let drawn = document.drawn(atTimeMS: 4100)
        let mark = try #require(drawn.allLayers.first { $0.id != id && $0.name != "screen-recording" })
        // The recording point (500, 400) is the clip's point (250, 200).
        #expect(abs(mark.frame.midX - 250) < 1 && abs(mark.frame.midY - 200) < 1, "\(mark.frame)")
    }
}
