import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Title pages that look like Apple designed them (task
/// `title-pages-that-look-like-apple-designed-them`, mock
/// `docs/design/mocks/pages/video-titles-apple.html`).
///
/// Written before the presets. The user called the set they replaced busy and
/// picked all ten of the mock's studies (card answered 2026-10-18, option b):
/// they lead the title pages, in the mock's order, and the old pages move under
/// More Styles. Every one keeps the mock's restraint: a still background, fades,
/// rises of 24 points at most, blurs that clear, ins of 360 to 950 ms on an ease
/// out, outs of 300 to 450 ms, nothing that springs, flips or turns in depth.
@Suite("Title pages that look like Apple designed them")
struct TitleCalmSetTests {

    static let canvas = CGSize(width: 1920, height: 1080)

    static let names = ["Keynote Section", "Film Super", "Session Title", "Chapter Card", "Editorial",
                        "Sessions Stage", "Launch", "Gradient Word", "Big Number", "End Card"]

    static let moreStyles = ["Keynote Clean", "Soft Gradient Glass", "Kinetic Bold", "Editorial Serif",
                             "Tech Terminal", "Behind Glass", "Light Leak", "Gradient Glow", "Stacked Stagger"]

    static func placed(_ preset: BuiltInTitle) throws -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: canvas)
        var shape = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: "#101318",
                                      start: .zero, end: CGPoint(x: canvas.width, y: canvas.height))
        shape.fill = Paint(hex: "#101318")
        var clip = Layer(name: "Recording", content: .annotation(shape), frame: CGRect(origin: .zero, size: canvas))
        clip.time = LayerTime(inMS: 0, outMS: 10_000, sourceInMS: 0, sourceLengthMS: 10_000)
        doc.layers = [clip]
        doc.durationMS = 10_000
        let inserted = doc.insertTitle(preset, atTimeMS: 1000)
        return (doc, try #require(inserted, "\(preset.name)").layerID)
    }

    // MARK: - The set and where it sits

    @Test("The ten studies lead the title pages in the mock's order, the old pages follow as More Styles")
    func theTenLead() {
        #expect(BuiltInTitle.calmSet.map(\.name) == Self.names)
        let pages = BuiltInTitle.presets(of: .titlePage)
        #expect(pages.map(\.name) == Self.names + Self.moreStyles)
        #expect(pages.filter(\.isMoreStyle).map(\.name) == Self.moreStyles)
        #expect(BuiltInTitle.calmSet.allSatisfy { $0.kind == .titlePage && !$0.isMoreStyle && $0.isCalm })
        // The name cards are not part of the study and stay as they were.
        #expect(BuiltInTitle.presets(of: .nameCard).allSatisfy { !$0.isMoreStyle && !$0.isCalm })
        // None of them needs a moving backdrop, so every release offers them.
        #expect(BuiltInTitle.presets(of: .titlePage, movingBackdrops: false) == BuiltInTitle.calmSet)
    }

    @Test("The catalog files the old pages under their own More Styles header below the ten")
    func catalogGroups() {
        let catalog = VideoCatalog.assemble(titles: TitlePreset.shelf(saved: [], charts: false), backgrounds: [],
                                            transitions: [], pictures: [], components: [])
        let groups = catalog.groups(category: .titlePages, query: "", builtForVideoOnly: true)
        #expect(groups.map(\.title) == ["Title Pages", "More Styles"])
        #expect(groups.first?.items.map(\.entry.name) == Self.names)
        #expect(groups.last?.items.map(\.entry.name) == Self.moreStyles)
        #expect(groups.allSatisfy { $0.category == .titlePages })
        // The chip still counts every title page.
        let chips = catalog.categories(builtForVideoOnly: true)
        let pageChip = chips.first(where: { $0.category == .titlePages })
        #expect(pageChip?.count == 19)
        // A search that finds pages of both kinds keeps the two headers.
        let found = catalog.groups(category: nil, query: "editorial", builtForVideoOnly: true)
        #expect(found.map(\.title) == ["Title Pages", "More Styles"])
    }

    // MARK: - Restraint, as the mock sets it

    @Test("Every in takes 360 to 950 ms on an ease out, every out 300 to 450 ms on an even ease")
    func calmTiming() {
        let easeOuts: Set<EasingCurve> = [.easeOutExpo, .easeOut, .easeInOutSine]
        for preset in BuiltInTitle.calmSet {
            for part in preset.design.parts {
                if let build = part.in {
                    #expect((360...950).contains(build.lengthMS), "\(preset.name) \(part.path) in \(build.lengthMS)")
                    #expect(easeOuts.contains(build.curve), "\(preset.name) \(part.path) in on \(build.curve)")
                }
                if let build = part.out {
                    #expect((300...450).contains(build.lengthMS), "\(preset.name) \(part.path) out \(build.lengthMS)")
                    #expect(build.curve == .easeInOutSine, "\(preset.name) \(part.path) out on \(build.curve)")
                }
            }
        }
    }

    @Test("Nothing springs, flips, turns in depth or is typed; travel stays under 24 points")
    func calmMoves() {
        let allowed: Set<TitleBuildKind> = [.fade, .rise, .blurIn, .scaleFrom, .maskReveal, .trackIn, .drawOn]
        for preset in BuiltInTitle.calmSet {
            for part in preset.design.parts {
                for build in [part.in, part.out].compactMap({ $0 }) {
                    #expect(allowed.contains(build.kind), "\(preset.name) \(part.path) \(build.kind)")
                    if build.kind == .rise { #expect(build.amount <= 24, "\(preset.name) \(part.path) rises \(build.amount)") }
                    if build.kind == .scaleFrom { #expect(abs(build.amount - 100) <= 8, "\(preset.name) scales \(build.amount)") }
                    if build.kind == .trackIn { #expect(build.amount <= 10, "\(preset.name) tracks \(build.amount)") }
                    if let scale = build.scale { #expect(abs(scale - 100) <= 8, "\(preset.name) \(part.path) \(scale)") }
                }
            }
        }
    }

    @Test("Every background holds still; only Sessions Stage's glow drifts, a few points over the whole title")
    func stillBackgrounds() {
        for preset in BuiltInTitle.calmSet {
            for part in preset.design.parts where part.role == .background {
                #expect(part.in == nil && part.out == nil && part.hold == .still, "\(preset.name) background moves")
            }
            let drifting = preset.design.parts.filter { $0.hold != .still }
            if preset == .sessionsStage {
                #expect(drifting.map(\.path) == ["Glow"])
                #expect(drifting.allSatisfy { $0.hold.kind == .drift && $0.hold.amount <= 60 })
            } else {
                #expect(drifting.isEmpty, "\(preset.name) holds with \(drifting.map(\.path))")
            }
            // No live look, grain or glow anywhere.
            for piece in preset.layer(in: Self.canvas).selfAndDescendants {
                #expect(piece.annotation?.fill?.kind != .live, "\(preset.name) \(piece.name)")
                #expect(piece.style.effects.isEmpty, "\(preset.name) \(piece.name) wears \(piece.style.effects)")
            }
        }
    }

    @Test("The words are set as the mock sets them: its faces, sizes, tracking and leading")
    func typeAsTheMock() throws {
        func words(_ preset: BuiltInTitle, _ path: String) throws -> TextContent {
            let found = TitleDesign.find(path, in: preset.layer(in: Self.canvas))?.text
            return try #require(found, "\(preset.name) \(path)")
        }
        let section = try words(.keynoteSection, "Title")
        #expect(section.string == "Timeline" && section.fontSize == 184 && section.weight == .semibold)
        #expect(section.tracking == -0.028 && section.lineHeight == 1 && section.colorHex == "#F5F5F7")
        let editorial = try words(.editorialNY, "Title")
        #expect(editorial.fontName == "New York" && editorial.fontSize == 128 && editorial.lineHeight == 1.06)
        #expect(editorial.string == "A better way\nto explain things")
        #expect(try words(.editorialNY, "Kicker").tracking == 0.16)
        let launch = try words(.launch, "Title")
        #expect(launch.fill?.isGradient == true && launch.tracking == -0.034)
        let gradient = try words(.gradientWord, "Title")
        #expect(gradient.fill?.orderedStops.count == 6 && gradient.fillLength == 2.2)
        // At most one colour beyond black, white and grey on every page but
        // Gradient Word, whose one accent is the spectrum itself.
        for preset in BuiltInTitle.calmSet where preset != .gradientWord {
            let colours = Set(preset.layer(in: Self.canvas).selfAndDescendants.compactMap { $0.text?.colorHex }
                .filter { !Self.isNeutral($0) })
            #expect(colours.count <= 1, "\(preset.name) uses \(colours.sorted())")
        }
    }

    @Test("Gradient Word's colours wash through its words once and then hold still")
    func gradientSweep() throws {
        let (doc, id) = try Self.placed(.gradientWord)
        let title = try #require(doc.layer(id: id))
        let words = try #require(TitleDesign.find("Title", in: title))
        let sweep = try #require(words.motions?.first { $0.property == .gradientShift })
        let keys = sweep.keyframes.map { ($0.atMS, $0.value) }
        #expect(keys.first?.0 == 0 && keys.first?.1 == .number(100))
        #expect(keys.last?.0 == 1600 && keys.last?.1 == .number(0))
        let later = try #require(doc.drawn(atTimeMS: 3000).layer(id: id))
        let held = try #require(TitleDesign.find("Title", in: later))
        #expect(held.text?.fillShift == 0)
    }

    @Test("Each lands, plays on its tile and is all there once arrived")
    func landsAndArrives() throws {
        for preset in BuiltInTitle.calmSet {
            let (doc, id) = try Self.placed(preset)
            let arrived = doc.titleArrivalMS(layerID: id)
            #expect((600...1700).contains(arrived), "\(preset.name) arrives at \(arrived)")
            #expect(TitlePreset.builtIn(preset).preview(frame: Self.canvas, width: 320) != nil, "\(preset.name)")
        }
    }

    @Test("Typing new words into a page leaves them as clean as it set them: no shadow, no halo")
    func typedWordsStayClean() throws {
        for preset in BuiltInTitle.calmSet {
            var (doc, id) = try Self.placed(preset)
            let landed = try #require(doc.layer(id: id))
            let words = try #require(TitleDesign.find("Title", in: landed))
            var typed = try #require(words.text)
            typed.string = "Photonz 3"
            doc.commitTextEdit(id: words.id, content: typed, canvasFrame: words.frame)
            _ = doc.relayOutTitle(layerID: id)
            let laidOut = try #require(doc.layer(id: id))
            let after = try #require(TitleDesign.find("Title", in: laidOut))
            #expect(after.text?.string == "Photonz 3", "\(preset.name)")
            #expect(after.style.shadows.isEmpty, "\(preset.name) wears \(after.style.shadows.count) shadows")
        }
    }

    // MARK: - A blur or a scale alongside a move

    @Test("A build carries a blur and a scale alongside its own move, as keys that clear with it")
    func alongside() throws {
        let rise = TitleBuild(.rise, delayMS: 100, lengthMS: 800, amount: 18, blur: 4)
        let blurred = TitleBuild(.blurIn, delayMS: 0, lengthMS: 900, amount: 18, scale: 103.5)
        let design = TitleDesign(parts: [
            TitlePart(path: "Title", role: .headline, in: rise),
            TitlePart(path: "Subtitle", role: .subtitle, in: blurred),
        ])
        var doc = PhotonzDocument(canvasSize: Self.canvas)
        doc.durationMS = 10_000
        let words = Layer(name: "Title", content: .text(TextContent(string: "Hello", fontSize: 80)),
                          frame: CGRect(x: 100, y: 100, width: 400, height: 100))
        let line = Layer(name: "Subtitle", content: .text(TextContent(string: "There", fontSize: 40)),
                         frame: CGRect(x: 100, y: 300, width: 400, height: 60))
        var group = Layer(name: "Title Page", content: .group(GroupContent(children: [words, line])),
                          frame: .zero)
        group.time = LayerTime(inMS: 0, outMS: 4000, sourceInMS: 0)
        doc.addLayer(group)
        let wrote = doc.applyTitleDesign(design, layerID: group.id)
        #expect(wrote)
        let placed = try #require(doc.layer(id: group.id))
        let title = try #require(TitleDesign.find("Title", in: placed))
        #expect(Set(title.motions?.map(\.property) ?? []) == [.opacity, .position, .blur])
        let blur = try #require(title.motions?.first { $0.property == .blur })
        #expect(blur.keyframes.first?.value == .number(4) && blur.keyframes.first?.atMS == 100)
        #expect(blur.keyframes.last?.value == .number(0) && blur.keyframes.last?.atMS == 900)
        let subtitle = try #require(TitleDesign.find("Subtitle", in: placed))
        #expect(Set(subtitle.motions?.map(\.property) ?? []) == [.opacity, .blur, .scale])
        #expect(subtitle.motions?.first { $0.property == .scale }?.keyframes.first?.value == .number(103.5))
        // Words that come in by their own reveal still blur as a whole.
        let lines = TitleBuild(.rise, delayMS: 100, lengthMS: 850, amount: 22, by: .line, staggerMS: 90, blur: 4)
        let rewrote = doc.applyTitleDesign(TitleDesign(parts: [TitlePart(path: "Title", role: .headline, in: lines)]),
                                           layerID: group.id)
        #expect(rewrote)
        let again = try #require(doc.layer(id: group.id))
        let revealed = try #require(TitleDesign.find("Title", in: again))
        #expect(revealed.text?.reveal?.style == .riseAndFade)
        #expect(revealed.motions?.contains { $0.property == .blur } == true)
        // Old designs decode with nothing alongside.
        let old = try JSONDecoder().decode(TitleBuild.self, from: Data(
            #"{"kind":"rise","delayMS":0,"lengthMS":500,"amount":12,"direction":"up","curve":{"easeOut":{}}}"#.utf8))
        #expect(old.blur == nil && old.scale == nil)
    }

    static func isNeutral(_ hex: String) -> Bool {
        let digits = hex.dropFirst()
        guard digits.count >= 6, let value = Int(digits.prefix(6), radix: 16) else { return true }
        let r = (value >> 16) & 0xFF, g = (value >> 8) & 0xFF, b = value & 0xFF
        return max(r, g, b) - min(r, g, b) <= 40
    }
}
