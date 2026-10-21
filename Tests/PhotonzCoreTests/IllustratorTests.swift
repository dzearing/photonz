import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// An illustration drawn the way a graphic artist works (`docs/design/ask.md`,
/// "Drawing an illustration"): eight passes, each checked, the last one a
/// picture made of named, editable parts with real gradient fills.
@Suite("Ask draws an illustration in a graphic artist's passes")
struct IllustratorTests {

    static func brief(_ subject: String, _ style: String? = nil) throws -> IllustrationBrief {
        try #require(IllustrationBrief.make(subject: subject, style: style))
    }

    // MARK: Pass 1, the brief

    @Test("A scene is an illustration; a single thing and an icon are not")
    func whatIsAnIllustration() {
        #expect(IllustrationBrief.make(subject: "sun over mountains") != nil)
        #expect(IllustrationBrief.make(subject: "lighthouse on a cliff") != nil)
        #expect(IllustrationBrief.make(subject: "city skyline at night") != nil)
        #expect(IllustrationBrief.make(subject: "dog") == nil)
        #expect(IllustrationBrief.make(subject: "tree") == nil)
        #expect(IllustrationBrief.make(subject: "coffee cup") == nil)
        #expect(IllustrationBrief.make(subject: "sun over mountains", icon: true) == nil)
        // A lone animal is a scene only when an illustration was asked for.
        #expect(IllustrationBrief.make(subject: "fox") == nil)
        #expect(IllustrationBrief.make(subject: "fox", style: "illustration") != nil)
    }

    @Test("The style the person names is the style drawn; with none named, one is picked and said")
    func stylesByName() throws {
        #expect(try Self.brief("sun over mountains", "line art").style == .lineArt)
        #expect(try Self.brief("sun over mountains", "black silhouette badge").style == .silhouette)
        #expect(try Self.brief("sun over mountains", "black silhouette badge").badge)
        #expect(try Self.brief("sun over mountains", "in a circle").badge)
        #expect(try Self.brief("sun over mountains", "layered sunset").style == .sunset)
        #expect(try Self.brief("sun over mountains", "flat").style == .flat)
        let picked = try Self.brief("sun over mountains")
        #expect(!picked.styleNamed)
        #expect(try Self.brief("sun over mountains", "flat").styleNamed)
    }

    @Test("The time of day comes from the words, and decides sun or moon")
    func timeOfDay() throws {
        #expect(try Self.brief("forest at dusk").time == .dusk)
        #expect(try Self.brief("city skyline at night").time == .night)
        #expect(try Self.brief("city skyline at night").has(.moon))
        #expect(try Self.brief("city skyline at night").has(.stars))
        #expect(try Self.brief("mountain lake on a sunny day").time == .day)
        #expect(try Self.brief("lighthouse on a cliff").has(.sea))
    }

    @Test("The look words a person typed are found for the model that left them out")
    func lookWords() {
        #expect(IllustrationBrief.lookWords(in: "draw a sun over mountains as line art") == ["line art"])
        #expect(IllustrationBrief.lookWords(in: "a black silhouette badge with pines") == ["black", "silhouette", "badge"])
        #expect(IllustrationBrief.lookWords(in: "draw a picture of a dog.").isEmpty)
    }

    // MARK: The passes

    @Test("Eight passes in the artist's order, each with a picture and its checks")
    func eightPasses() throws {
        let passes = Illustrator.passes(try Self.brief("sun over mountains"))
        #expect(passes.map(\.title) == ["Brief", "Composition", "Values", "Shape", "Light", "Colour", "Detail and finish", "Critique"])
        for pass in passes.dropFirst() { #expect(!pass.scene.shapes.isEmpty, "pass \(pass.number) drew nothing") }
        #expect(passes.flatMap(\.checks).count >= 8)
    }

    @Test("Every check passes for every illustration the eval asks for", arguments: [
        ("sun over mountains", nil), ("sun over mountains", "line art"), ("sun over mountains with pines", "black silhouette badge"),
        ("sun over mountains", "layered sunset"), ("sun over mountains", "flat"), ("forest at dusk", "illustration"),
        ("lighthouse on a cliff", "illustration"), ("fox", "illustration"), ("city skyline at night", "illustration"),
        ("mountain lake on a sunny day", "illustration"),
    ] as [(String, String?)])
    func checksPass(subject: String, style: String?) throws {
        let failed = Illustrator.passes(try Self.brief(subject, style)).flatMap(\.checks).filter { !$0.passed }
        #expect(failed.isEmpty, "\(failed.map { "\($0.name): \($0.detail)" })")
    }

    @Test("Values: three or more planes, nearest darkest, read in grey before any colour")
    func valuesNearestDarkest() throws {
        let passes = Illustrator.passes(try Self.brief("sun over mountains"))
        let values = passes[2].checks.first { $0.name == "values" }
        #expect(values?.passed == true)
        // The value pass is grey: no shape in it carries a colour.
        for shape in passes[2].scene.shapes {
            if case .flat(let hex) = shape.fill, let rgba = RGBA(hex: hex) {
                #expect(abs(rgba.r - rgba.g) < 0.01 && abs(rgba.g - rgba.b) < 0.01, "\(shape.name) is \(hex)")
            }
        }
    }

    @Test("Light: every shadow face sits on the side of its peak away from the sun, the same side on every peak")
    func shadowsAgreeWithTheSun() throws {
        for subject in ["sun over mountains", "mountain lake on a sunny day"] {
            let work = IllustrationWork(brief: try Self.brief(subject, "painted"), tuning: IllustrationTuning())
            let faces = work.forms.flatMap(\.shadows)
            #expect(faces.count >= 3)
            for face in faces {
                let middle = face.face.reduce(CGFloat(0)) { $0 + $1.x } / CGFloat(face.face.count)
                // One light: the shadow falls on the side away from the sun's side of the picture.
                let sunSide: CGFloat = work.light.x < work.size.width / 2 ? -1 : 1
                #expect((middle - face.peak.x) * sunSide < 0, "a shadow face at \(face.peak) faces the sun")
            }
        }
    }

    @Test("Shape: ridgelines are broken and no range is a straight-sided triangle")
    func naturalRidges() throws {
        let work = IllustrationWork(brief: try Self.brief("sun over mountains", "painted"), tuning: IllustrationTuning())
        let ranges = work.forms.filter { $0.plane.kind == .range }
        #expect(ranges.count >= 3)
        for range in ranges {
            let ridge = try #require(range.ridge)
            #expect(ridge.points.count > 40)
            // Between a peak and its valley the slope bends: it strays from
            // the straight line joining them, the way a triangle's side never does.
            for peak in ridge.peaks {
                guard let valley = ridge.valleys.first(where: { $0 > peak }) else { continue }
                let a = ridge.points[peak], b = ridge.points[valley]
                let length = hypot(b.x - a.x, b.y - a.y)
                var stray: CGFloat = 0
                for p in ridge.points[peak...valley] {
                    let across: CGFloat = (b.x - a.x) * (a.y - p.y)
                    let down: CGFloat = (a.x - p.x) * (b.y - a.y)
                    stray = max(stray, abs(across - down) / length)
                }
                #expect(stray >= length * 0.02, "the slope from peak \(peak) is a straight line")
            }
        }
    }

    @Test("Colour: the far range is lighter and bluer than the near one, under a sky gradient")
    func depthInColour() throws {
        let work = IllustrationWork(brief: try Self.brief("sun over mountains", "painted"), tuning: IllustrationTuning())
        let ranges = work.planes.filter { $0.kind == .range }.sorted { $0.depth < $1.depth }
        let far = try #require(ranges.first), near = try #require(ranges.last)
        let farColour = try #require(RGBA(hex: work.colour(far))), nearColour = try #require(RGBA(hex: work.colour(near)))
        #expect(IllustrationColor.value(work.colour(far)) > IllustrationColor.value(work.colour(near)) + 0.2)
        #expect(farColour.b - farColour.r > nearColour.b - nearColour.r - 0.02)
        let sky = work.scene(stage: 7).shapes.first { $0.name == "Sky" }
        guard case .linear(let stops, _) = sky?.fill else {
            Issue.record("the sky is not a gradient")
            return
        }
        #expect(stops.count >= 2)
    }

    @Test("Nothing pokes past the picture: every part sits inside its frame")
    func nothingPastTheFrame() throws {
        for (subject, style) in [("sun over mountains", "painted"), ("sun over mountains with pines", "silhouette badge"),
                                 ("lighthouse on a cliff", "illustration")] {
            let scene = Illustrator.draw(try Self.brief(subject, style))
            let edge = CGRect(origin: .zero, size: scene.size).insetBy(dx: -8, dy: -8)
            for shape in scene.shapes where !shape.name.hasSuffix("rame line") {
                #expect(edge.contains(shape.bounds.insetBy(dx: shape.strokeWidth / 2, dy: shape.strokeWidth / 2)),
                        "\(shape.name) pokes out at \(shape.bounds)")
            }
        }
    }

    @Test("A badge is cut to a circle with a frame line")
    func badgeIsACircle() throws {
        let scene = Illustrator.draw(try Self.brief("sun over mountains with pines", "silhouette badge"))
        #expect(scene.size.width == scene.size.height)
        let centre = CGPoint(x: scene.size.width / 2, y: scene.size.height / 2)
        let frameLine = scene.shapes.first { $0.name == "Frame line" }
        #expect(frameLine != nil)
        let radius = scene.size.width * 0.47
        for shape in scene.shapes where shape.name != "Frame line" && shape.name != "Inner frame line" {
            guard case .path(let paths) = shape.geometry else { continue }
            for point in paths.flatMap({ $0.flattened(steps: 2) }) {
                #expect(hypot(point.x - centre.x, point.y - centre.y) <= radius + 1, "\(shape.name) leaves the circle")
            }
        }
    }

    @Test("A treeline is one pine repeated at different heights")
    func treeline() throws {
        let work = IllustrationWork(brief: try Self.brief("forest at dusk"), tuning: IllustrationTuning())
        let front = try #require(work.forms.first { $0.plane.name == "Middle pines" })
        let heights = front.outline.dropFirst().map(\.bounds.height)
        #expect(heights.count >= 10)
        #expect((heights.max() ?? 0) > (heights.min() ?? 0) * 1.2)
    }

    @Test("The same brief always draws the same picture")
    func deterministic() throws {
        let brief = try Self.brief("lighthouse on a cliff")
        #expect(Illustrator.draw(brief) == Illustrator.draw(brief))
    }

    // MARK: The finished picture

    @Test("The SVG names every part, groups them, and fills with real gradients")
    func cleanSVG() throws {
        let svg = Illustrator.draw(try Self.brief("sun over mountains", "painted")).svg()
        #expect(svg.contains("<linearGradient"))
        #expect(svg.contains("<radialGradient"))
        #expect(svg.contains("<g id=\"sky\">"))
        #expect(svg.contains("id=\"shadow-face"))
        #expect(!svg.contains("<image"))
        #expect(!svg.contains("mask"))
    }

    @Test("As layers: a group per part of the picture, named, with the app's own gradient fills")
    func asLayers() throws {
        let scene = Illustrator.draw(try Self.brief("sun over mountains", "painted"))
        guard case .success(let art) = SVGArtwork.parse(scene.svg(), keepingGroups: true) else {
            Issue.record("the illustration's svg did not read")
            return
        }
        let group = art.group(named: "Sun over mountains", fitting: CGRect(x: 100, y: 100, width: 1200, height: 800))
        guard case .group(let top) = group.content else {
            Issue.record("not a group")
            return
        }
        let names = top.children.map(\.name)
        #expect(names.contains("Sky"))
        #expect(names.contains("Sun"))
        #expect(names.contains("Far range"))
        #expect(names.contains("Near range"))
        func all(_ layer: Layer) -> [Layer] {
            if case .group(let g) = layer.content { return [layer] + g.children.flatMap(all) }
            return [layer]
        }
        let everything = all(group)
        #expect(everything.contains { $0.name == "Shadow face" })
        let gradients = everything.compactMap { layer -> Paint? in
            if case .path(let path) = layer.content { return path.fill }
            if case .annotation(let a) = layer.content { return a.fill }
            return nil
        }.filter(\.isGradient)
        #expect(gradients.count >= 3)
    }

    @Test("Exported from the document, the illustration is clean SVG: shapes and gradients, no pictures")
    func exportsClean() throws {
        let scene = Illustrator.draw(try Self.brief("lighthouse on a cliff"))
        guard case .success(let art) = SVGArtwork.parse(scene.svg(), keepingGroups: true) else {
            Issue.record("did not read")
            return
        }
        var document = PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024))
        document.addDrawing(art, named: "Lighthouse on a cliff", icon: false,
                            box: AgentDrawingPlacement.box(nil, fitting: scene.size, on: document.canvasSize))
        let export = SVGExport.write(document)
        #expect(export.fallbacks.isEmpty, "\(export.fallbacks)")
        #expect(export.text.contains("<linearGradient"))
        #expect(export.text.contains("<radialGradient"))
        #expect(!export.text.contains("<image"))
    }
}
