import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Title backgrounds move: gradients, grain and the recording behind glass
/// (task `title-backgrounds-move-gradients-grain-and-the-r`,
/// `docs/design/video-titles-polish.md`, step 3 of 6).
///
/// Written before the model. A title page's background can be alive instead of
/// flat: a few soft colour points drifting on a loop (a Mesh fill with a
/// Drift), fine film grain that moves every frame (a Grain effect), or the
/// recording under the title blurred, dimmed and slowly zooming, sharpening as
/// the title leaves (a background blur with a Zoom, keyed). Lines and paths
/// take a trim, so an underline can draw itself on. Every one of them is
/// styling read at the moment drawn, never baked into pixels.
@Suite("Title backgrounds move")
struct TitleBackgroundsTests {

    static let canvas = CGSize(width: 1920, height: 1080)

    static let aurora = Paint(hex: "#1B1446", kind: .mesh,
                              stops: [GradientStop(hex: "#1B1446", position: 0),
                                      GradientStop(hex: "#7A3CFF", position: 0.5),
                                      GradientStop(hex: "#FF6B8B", position: 1)],
                              drift: 40)

    static func recording(seconds: Int = 10) -> Layer {
        let movie = MovieRef(pixelSize: canvas, durationMS: seconds * 1000)
        var layer = Layer(name: "Recording", content: .image(movie.frameRef(atSourceMS: 0)),
                          frame: CGRect(origin: .zero, size: canvas))
        layer.movie = movie
        layer.time = LayerTime(inMS: 0, outMS: movie.durationMS, sourceInMS: 0,
                               sourceLengthMS: movie.durationMS)
        return layer
    }

    static func overARecording() -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: canvas)
        doc.layers = [recording()]
        doc.durationMS = 10_000
        return doc
    }

    static func box(_ fill: Paint, size: CGSize = canvas) -> Layer {
        var content = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: fill.hex,
                                        start: .zero, end: CGPoint(x: size.width, y: size.height))
        content.fill = fill
        return Layer(name: "Background", content: .annotation(content), frame: CGRect(origin: .zero, size: size))
    }

    static func line(from: CGPoint, to: CGPoint) -> Layer {
        let content = AnnotationContent(shape: .line, strokeWidth: 4, colorHex: "#FFFFFF",
                                        start: from, end: to)
        return Layer(name: "Rule", content: .annotation(content),
                     frame: CGRect(x: 0, y: 0, width: max(to.x, 1), height: max(to.y, 1)))
    }

    static func piece(_ doc: PhotonzDocument, _ group: UUID, _ path: String, atMS ms: Int) -> Layer? {
        guard let drawn = doc.drawn(atTimeMS: ms).layer(id: group) else { return nil }
        return TitleDesign.find(path, in: drawn)
    }

    static func distance(_ a: RGBA, _ b: RGBA) -> Double {
        abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b)
    }

    // MARK: - A mesh that drifts

    @Test("A Mesh fill is soft colour points: near a point it is that point's colour, between them a blend")
    func aMeshIsSoftColourPoints() throws {
        let paint = Self.aurora
        #expect(paint.isGradient)
        #expect(Paint.Kind.mesh.title == "Mesh")
        let points = paint.meshPoints(atMS: 0)
        #expect(points.count == 3)
        for point in points {
            let colour = try #require(paint.meshColor(at: point.center, in: Self.canvas, atMS: 0))
            // Nearest its own colour of the three.
            let mine = Self.distance(colour, point.color)
            for other in points where other.color != point.color {
                #expect(mine < Self.distance(colour, other.color))
            }
        }
        // Every point of the box is some colour, never nothing.
        for x in stride(from: 0.0, through: 1.0, by: 0.25) {
            for y in stride(from: 0.0, through: 1.0, by: 0.25) {
                #expect(paint.meshColor(at: CGPoint(x: x, y: y), in: Self.canvas, atMS: 0) != nil)
            }
        }
    }

    @Test("Drift moves the points slowly and comes back round on a loop; no drift holds them still")
    func driftLoops() {
        let paint = Self.aurora
        let loop = paint.driftLoopMS
        #expect(loop != nil)
        let period = loop ?? 0
        // A gentle sweep: the loop is many seconds, not a jitter.
        #expect(period >= 8000)
        let start = paint.meshPoints(atMS: 0).map(\.center)
        let quarter = paint.meshPoints(atMS: period / 4).map(\.center)
        let round = paint.meshPoints(atMS: period).map(\.center)
        #expect(zip(start, quarter).contains { hypot($0.x - $1.x, $0.y - $1.y) > 0.05 })
        for (a, b) in zip(start, round) { #expect(hypot(a.x - b.x, a.y - b.y) < 1e-6) }
        // One frame apart they barely move, so it reads as drift, not a jump.
        let next = paint.meshPoints(atMS: 17).map(\.center)
        for (a, b) in zip(start, next) { #expect(hypot(a.x - b.x, a.y - b.y) < 0.002) }
        // Twice the drift, twice as fast.
        var faster = paint
        faster.drift = 80
        #expect(faster.driftLoopMS == period / 2)
        // No drift: still, whatever the moment.
        var still = paint
        still.drift = 0
        #expect(still.driftLoopMS == nil)
        #expect(still.meshPoints(atMS: 0).map(\.center) == still.meshPoints(atMS: 5000).map(\.center))
    }

    @Test("A mesh and its drift are kept in the document; a flat paint still writes its bare hex")
    func meshIsKept() throws {
        let data = try JSONEncoder().encode(Self.aurora)
        let back = try JSONDecoder().decode(Paint.self, from: data)
        #expect(back == Self.aurora)
        #expect(back.drift == 40)
        #expect(back.draws(sameAs: Self.aurora))
        var calmer = Self.aurora
        calmer.drift = 10
        #expect(!calmer.draws(sameAs: Self.aurora))
        let flat = try JSONEncoder().encode(Paint(hex: "#FF3B30"))
        #expect(String(decoding: flat, as: UTF8.self) == "\"#FF3B30\"")
        // A gradient that never drifted writes no drift at all.
        let linear = Paint(hex: "#000000", kind: .linear,
                           stops: [GradientStop(hex: "#000000", position: 0),
                                   GradientStop(hex: "#FFFFFF", position: 1)])
        #expect(!String(decoding: try JSONEncoder().encode(linear), as: UTF8.self).contains("drift"))
    }

    @Test("Turning a fill into a Mesh starts it drifting gently, with your colour in it")
    func becomingAMesh() {
        var paint = Paint(hex: "#2A2160")
        paint.becoming(.mesh)
        #expect(paint.kind == .mesh)
        #expect(paint.stops.count >= 3)
        #expect(paint.stops.contains { $0.hex == "#2A2160" })
        #expect(paint.drift == Paint.startingDrift)
        #expect(Paint.startingDrift > 0)
    }

    // MARK: - Grain

    @Test("Grain is an effect you add once, with an amount, kept in the document")
    func grainIsAnEffect() throws {
        #expect(EffectKind.grain.title == "Grain")
        #expect(!EffectKind.grain.isCountable)
        #expect(EffectKind.grain.colorSlot == nil)
        #expect(AddableEffect.allCases.contains(.grain))
        guard case let .grain(grain) = AddableEffect.grain.newEffect else {
            Issue.record("Grain adds a grain")
            return
        }
        #expect(grain.isOn)
        #expect(grain.amount == GrainEffect.startingAmount)
        #expect(grain.amount > 0 && grain.amount <= 30)
        var layer = Self.box(Paint(hex: "#101020"))
        layer.style.effects = [.grain(GrainEffect(amount: 12))]
        #expect(layer.style.grain?.amount == 12)
        let data = try JSONEncoder().encode(layer.style.effects)
        #expect(String(decoding: data, as: UTF8.self).contains("\"kind\":\"grain\""))
        #expect(try JSONDecoder().decode([LayerEffect].self, from: data) == layer.style.effects)
        // Off keeps the amount and paints nothing.
        layer.style.effects[0].isOn = false
        #expect(layer.style.grain == nil)
    }

    // MARK: - The clock a moving look runs on

    @Test("A drifting fill or grain is told the moment it is drawn at; anything else is not")
    func movingLooksAreToldTheMoment() throws {
        var doc = PhotonzDocument(canvasSize: Self.canvas)
        var drifting = Self.box(Self.aurora)
        drifting.time = LayerTime(inMS: 1000, outMS: 5000, sourceInMS: 0)
        var grainy = Self.box(Paint(hex: "#101020"))
        grainy.style.effects = [.grain(GrainEffect(amount: 10))]
        grainy.time = LayerTime(inMS: 0, outMS: 5000, sourceInMS: 0)
        var plain = Self.box(Paint(hex: "#101020"))
        plain.time = LayerTime(inMS: 0, outMS: 5000, sourceInMS: 0)
        doc.layers = [drifting, grainy, plain]
        doc.durationMS = 5000
        let drawn = doc.drawn(atTimeMS: 3000)
        // On its own clock: a second into its bar is two seconds in.
        #expect(drawn.layer(id: drifting.id)?.drawnAtMS == 2000)
        #expect(drawn.layer(id: grainy.id)?.drawnAtMS == 3000)
        #expect(drawn.layer(id: plain.id)?.drawnAtMS == nil)
        // Never stored: the document keeps the layer you drew.
        #expect(doc.layer(id: drifting.id)?.drawnAtMS == nil)
        // A still mesh needs no clock either.
        var still = Self.aurora
        still.drift = 0
        var held = Self.box(still)
        held.time = LayerTime(inMS: 0, outMS: 5000, sourceInMS: 0)
        doc.layers = [held]
        #expect(doc.drawn(atTimeMS: 1000).layer(id: held.id)?.drawnAtMS == nil)
    }

    @Test("Inside a title, a piece's drift runs on the title's clock")
    func piecesRunOnTheTitleClock() throws {
        var doc = Self.overARecording()
        let landed = doc.insertTitle(.aurora, atTimeMS: 2000)
        let inserted = try #require(landed)
        let background = try #require(Self.piece(doc, inserted.layerID, "Background", atMS: 3500))
        #expect(background.drawnAtMS == 1500)
    }

    // MARK: - Glass that zooms

    @Test("A background blur has a Zoom, and both it and the blur key like any value")
    func glassZoomAndBlurKey() throws {
        var glass = Self.box(Paint(hex: "#000000"))
        glass.style.opacity = 0.4
        glass.style.effects = [.blur(BlurEffect(radius: 36, kind: .background, zoom: 105))]
        #expect(glass.style.backgroundBlurZoom == 105)
        #expect(MotionProperty.backgroundBlur.current(of: glass) == .number(36))
        #expect(MotionProperty.backgroundZoom.current(of: glass) == .number(105))
        #expect(MotionProperty.backgroundBlur.title == "Background blur")
        #expect(MotionProperty.backgroundZoom.title == "Background zoom")
        #expect(MotionProperty.backgroundBlur.isLength)
        #expect(!MotionProperty.backgroundZoom.isLength)
        // A layer blur is not the glass, and the glass is not a layer blur.
        #expect(MotionProperty.blur.current(of: glass) == nil)
        let keyable = glass.keyableProperties
        #expect(keyable.contains(.motion(.backgroundBlur)))
        #expect(keyable.contains(.motion(.backgroundZoom)))
        let plain = Self.box(Paint(hex: "#000000"))
        #expect(MotionProperty.backgroundBlur.current(of: plain) == nil)
        #expect(!plain.keyableProperties.contains(.motion(.backgroundZoom)))

        var doc = PhotonzDocument(canvasSize: Self.canvas)
        glass.time = LayerTime(inMS: 0, outMS: 4000, sourceInMS: 0)
        doc.layers = [glass]
        doc.durationMS = 4000
        doc.startKeying(layerID: glass.id, .motion(.backgroundBlur), atDocumentTimeMS: 1000, ease: .linear)
        doc.setKeyedValue(.number(0), layerID: glass.id, .motion(.backgroundBlur),
                          atDocumentTimeMS: 3000, ease: .linear)
        doc.startKeying(layerID: glass.id, .motion(.backgroundZoom), atDocumentTimeMS: 0, ease: .linear)
        doc.setKeyedValue(.number(100), layerID: glass.id, .motion(.backgroundZoom),
                          atDocumentTimeMS: 2000, ease: .linear)
        let half = try #require(doc.drawn(atTimeMS: 2000).layer(id: glass.id))
        #expect(abs(half.style.backgroundBlurRadius - 18) < 0.01)
        #expect(abs(half.style.backgroundBlurZoom - 100) < 0.01)
        let start = try #require(doc.drawn(atTimeMS: 1000).layer(id: glass.id))
        #expect(abs(start.style.backgroundBlurZoom - 102.5) < 0.01)
        let end = try #require(doc.drawn(atTimeMS: 3500).layer(id: glass.id))
        #expect(end.style.backgroundBlurRadius == 0)
    }

    @Test("A blur written before it had a zoom reads back at 100%, and writes no zoom")
    func zoomIsOptionalOnDisk() throws {
        let old = try JSONDecoder().decode(BlurEffect.self,
                                           from: Data(#"{"radius":12,"isOn":true,"kind":"background"}"#.utf8))
        #expect(old.zoom == 100)
        let plain = String(decoding: try JSONEncoder().encode(BlurEffect(radius: 12, kind: .background)),
                           as: UTF8.self)
        #expect(!plain.contains("zoom"))
        let zoomed = BlurEffect(radius: 30, kind: .background, zoom: 105)
        #expect(try JSONDecoder().decode(BlurEffect.self, from: JSONEncoder().encode(zoomed)) == zoomed)
    }

    // MARK: - Strokes that draw on

    @Test("A path's length, and the part of it a trim keeps")
    func trimmingAPath() {
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: 100, y: 0))
        path.addLine(to: CGPoint(x: 100, y: 100))
        #expect(abs(StrokeTrim.length(of: path) - 200) < 0.01)
        let half = StrokeTrim(start: 0, end: 0.5).applied(to: path)
        #expect(abs(StrokeTrim.length(of: half) - 100) < 0.01)
        #expect(abs(half.currentPoint.x - 100) < 0.01 && abs(half.currentPoint.y) < 0.01)
        let middle = StrokeTrim(start: 0.25, end: 0.75).applied(to: path)
        #expect(abs(StrokeTrim.length(of: middle) - 100) < 0.01)
        #expect(abs(middle.boundingBoxOfPath.minX - 50) < 0.01)
        #expect(abs(middle.boundingBoxOfPath.maxY - 50) < 0.01)
        #expect(StrokeTrim(start: 0.6, end: 0.6).applied(to: path).isEmpty)
        #expect(StrokeTrim.whole.isWhole)
        // Curves too: a circle's quarter is a quarter of its round.
        let circle = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: 100, height: 100), transform: nil)
        let round = StrokeTrim.length(of: circle)
        #expect(abs(round - .pi * 100) < 0.5)
        #expect(abs(StrokeTrim.length(of: StrokeTrim(start: 0, end: 0.25).applied(to: circle)) - round / 4) < 0.5)
    }

    @Test("Lines and paths key Trim start and Trim end; words and pictures do not")
    func linesKeyATrim() throws {
        var rule = Self.line(from: CGPoint(x: 0, y: 2), to: CGPoint(x: 200, y: 2))
        #expect(MotionProperty.trimEnd.current(of: rule) == .number(100))
        #expect(MotionProperty.trimStart.current(of: rule) == .number(0))
        #expect(MotionProperty.trimStart.title == "Trim start")
        #expect(MotionProperty.trimEnd.title == "Trim end")
        #expect(rule.keyableProperties.contains(.motion(.trimEnd)))
        #expect(rule.keyableProperties.contains(.motion(.trimStart)))
        let words = Layer(name: "Title", content: .text(TextContent(string: "Hi")),
                          frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        #expect(MotionProperty.trimEnd.current(of: words) == nil)
        #expect(!words.keyableProperties.contains(.motion(.trimEnd)))
        // A filled box with no line has nothing to trim.
        #expect(MotionProperty.trimEnd.current(of: Self.box(Paint(hex: "#000000"))) == nil)
        let path = Layer(name: "Swoosh",
                         content: .path(PathContent(anchors: [PathAnchor(point: CGPoint(x: 0, y: 0)),
                                                              PathAnchor(point: CGPoint(x: 50, y: 20))],
                                                    fill: nil)),
                         frame: CGRect(x: 0, y: 0, width: 50, height: 20))
        #expect(MotionProperty.trimEnd.current(of: path) == .number(100))

        var doc = PhotonzDocument(canvasSize: Self.canvas)
        rule.time = LayerTime(inMS: 0, outMS: 4000, sourceInMS: 0)
        doc.layers = [rule]
        doc.durationMS = 4000
        doc.startKeying(layerID: rule.id, .motion(.trimEnd), atDocumentTimeMS: 0, ease: .linear)
        doc.setKeyedValue(.number(0), layerID: rule.id, .motion(.trimEnd), atDocumentTimeMS: 0, ease: .linear)
        doc.setKeyedValue(.number(100), layerID: rule.id, .motion(.trimEnd),
                          atDocumentTimeMS: 1000, ease: .linear)
        let drawing = try #require(doc.drawn(atTimeMS: 500).layer(id: rule.id))
        #expect(abs((drawing.annotation?.trim?.end ?? -1) - 0.5) < 0.01)
        #expect(drawing.annotation?.trim?.start == 0)
        // Once drawn on it is the whole line again, with no trim left on it.
        let drawn = try #require(doc.drawn(atTimeMS: 2000).layer(id: rule.id))
        #expect(drawn.annotation?.trim == nil || drawn.annotation?.trim?.isWhole == true)
        // The document keeps the line you drew.
        #expect(doc.layer(id: rule.id)?.annotation?.trim == nil)
    }

    @Test("A trim is kept on the line in the document, and a line with none writes none")
    func trimIsKept() throws {
        var content = AnnotationContent(shape: .line, colorHex: "#FFFFFF", start: .zero,
                                        end: CGPoint(x: 100, y: 0))
        #expect(!String(decoding: try JSONEncoder().encode(content), as: UTF8.self).contains("trim"))
        content.trim = StrokeTrim(start: 0.1, end: 0.6)
        let back = try JSONDecoder().decode(AnnotationContent.self, from: JSONEncoder().encode(content))
        #expect(back.trim == StrokeTrim(start: 0.1, end: 0.6))
        var path = PathContent(anchors: [PathAnchor(point: .zero), PathAnchor(point: CGPoint(x: 10, y: 10))])
        path.trim = StrokeTrim(start: 0, end: 0.3)
        #expect(try JSONDecoder().decode(PathContent.self, from: JSONEncoder().encode(path)).trim == path.trim)
    }

    // MARK: - The two new title pages

    @Test("Aurora: a live aurora with grain, and an underline that draws itself on")
    func auroraPage() throws {
        // Retired from the shelf by the designed set, and still drawn the same.
        #expect(BuiltInTitle.aurora.isRetired)
        #expect(!BuiltInTitle.presets(of: .titlePage).contains(.aurora))
        #expect(BuiltInTitle.aurora.name == "Aurora")
        var doc = Self.overARecording()
        let landed = doc.insertTitle(.aurora, atTimeMS: 3000)
        let inserted = try #require(landed)
        let group = try #require(doc.layer(id: inserted.layerID))
        let background = try #require(TitleDesign.find("Background", in: group))
        let fill = try #require(background.annotation?.fill)
        #expect(fill.kind == .live)
        #expect(fill.live?.look == .aurora)
        #expect(fill.moves)
        #expect((background.style.grain?.amount ?? 0) > 0)
        // The underline is a line, drawn on from nothing after the title.
        let rule = try #require(TitleDesign.find("Accent", in: group))
        #expect(rule.annotation?.shape == .line)
        let early = try #require(Self.piece(doc, inserted.layerID, "Accent", atMS: 3000 + 300))
        let late = try #require(Self.piece(doc, inserted.layerID, "Accent", atMS: 3000 + 1500))
        #expect((early.annotation?.trim?.end ?? 1) < 0.2)
        #expect(late.annotation?.trim == nil || late.annotation?.trim?.isWhole == true)
        // The aurora keeps moving while the title holds: two moments of the
        // hold are drawn with different clocks.
        let a = try #require(Self.piece(doc, inserted.layerID, "Background", atMS: 4500))
        let b = try #require(Self.piece(doc, inserted.layerID, "Background", atMS: 5500))
        #expect(a.drawnAtMS != b.drawnAtMS)
    }

    @Test("Behind Glass over a recording: blurred, dimmed and zooming, and it lands in the real footage")
    func behindGlassPage() throws {
        #expect(BuiltInTitle.presets(of: .titlePage).contains(.glass))
        #expect(BuiltInTitle.glass.name == "Behind Glass")
        var doc = Self.overARecording()
        let recording = try #require(doc.layers.first?.id)
        let landed = doc.insertTitle(.glass, atTimeMS: 0)
        let inserted = try #require(landed)
        // Laid OVER the recording's first seconds, never pushing it later:
        // the recording is its background.
        #expect(doc.layer(id: recording)?.time?.inMS == 0)
        let group = try #require(doc.layer(id: inserted.layerID))
        let length = try #require(group.time?.lengthMS)
        // It leaves through its own parts, not the bar's fade.
        #expect(group.pictureFadeMS(.out) == 0)
        let glass = try #require(TitleDesign.find("Background", in: group))
        #expect(glass.style.backgroundBlurRadius >= 30 && glass.style.backgroundBlurRadius <= 40)
        #expect(abs(glass.style.opacity - TitleLook.glassDim) < 0.001)

        // Held: blurred 30 to 40, dimmed enough for white words to read over
        // a white screenshot, the zoom easing from 102 to 100 (toned down
        // from 105 on 2026-10-18, task `the-existing-title-pages-are-toned-down-to-calm`).
        let held = try #require(Self.piece(doc, inserted.layerID, "Background", atMS: 1200))
        #expect(held.style.backgroundBlurRadius >= 30)
        #expect(abs(held.style.opacity - TitleLook.glassDim) < 0.01)
        let zoomEarly = held.style.backgroundBlurZoom
        let later = try #require(Self.piece(doc, inserted.layerID, "Background", atMS: length - 900))
        #expect(zoomEarly > later.style.backgroundBlurZoom)
        #expect(zoomEarly <= 102.001 && later.style.backgroundBlurZoom >= 99.999)
        let first = try #require(Self.piece(doc, inserted.layerID, "Background", atMS: 0))
        #expect(first.style.backgroundBlurZoom > 101.5)

        // Out: blur and dim go to nothing by the end, so the last frame of the
        // title IS the footage.
        let last = try #require(Self.piece(doc, inserted.layerID, "Background", atMS: length - 1))
        #expect(last.style.backgroundBlurRadius < 1.5)
        #expect(last.style.opacity < 0.03)
        #expect(abs(last.style.backgroundBlurZoom - 100) < 0.01)
        let words = try #require(Self.piece(doc, inserted.layerID, "Title", atMS: length - 1))
        #expect(words.style.opacity < 0.03)
    }

    @Test("Draw On writes a trim on a line, and wipes anything with no line")
    func drawOnBuild() throws {
        var doc = Self.overARecording()
        var line = Self.line(from: CGPoint(x: 0, y: 2), to: CGPoint(x: 300, y: 2))
        line.name = "Rule"
        var slab = Self.box(Paint(hex: "#FFFFFF"), size: CGSize(width: 300, height: 8))
        slab.name = "Bar"
        var group = Layer(name: "Card", content: .group(GroupContent(children: [line, slab])), frame: .zero)
        group.time = LayerTime(inMS: 0, outMS: 4000, sourceInMS: 0)
        doc.layers.append(group)
        let design = TitleDesign(parts: [
            TitlePart(path: "Rule", role: .accent, in: TitleBuild(.drawOn, delayMS: 0, lengthMS: 400),
                      out: TitleBuild(.drawOn, delayMS: 0, lengthMS: 200, curve: .easeIn)),
            TitlePart(path: "Bar", role: .accent, in: TitleBuild(.drawOn, delayMS: 0, lengthMS: 400,
                                                                 direction: .right)),
        ])
        #expect(TitleBuildKind.drawOn.title == "Draw On")
        let applied = doc.applyTitleDesign(design, layerID: group.id)
        #expect(applied)
        let ruled = try #require(doc.layer(id: group.id).flatMap { TitleDesign.find("Rule", in: $0) })
        #expect(ruled.motions?.contains { $0.property == .trimEnd } == true)
        #expect(ruled.motions?.contains { $0.property == .trimStart } == true)
        let half = try #require(Self.piece(doc, group.id, "Rule", atMS: 200))
        #expect((half.annotation?.trim?.end ?? 0) > 0.3)
        #expect((half.annotation?.trim?.end ?? 1) < 1)
        // Leaving, it undraws from where it started.
        let leaving = try #require(Self.piece(doc, group.id, "Rule", atMS: 3900))
        #expect((leaving.annotation?.trim?.start ?? 0) > 0.3)
        let barred = try #require(doc.layer(id: group.id).flatMap { TitleDesign.find("Bar", in: $0) })
        #expect(barred.motions?.contains { $0.property == .cropRight } == true)
        #expect(barred.motions?.contains { $0.property == .trimEnd } != true)
    }
}
