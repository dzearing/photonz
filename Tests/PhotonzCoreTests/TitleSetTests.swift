import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A set of titles that look designed (task `a-set-of-titles-that-look-designed`,
/// `docs/design/video-titles-polish.md`, "Twelve style directions").
///
/// Written before the presets. The shelf and the Insert menus carry the
/// twelve styles of the brief instead of the eight plain ones, and every one
/// of them keeps the brief's designed-not-template rules: its parts arrive on
/// separate beats, it uses two type sizes at most, it comes in on an expo or
/// quint (or a spring), it leaves quicker than it came on an ease in,
/// something is still moving while it holds, its words read over dark and
/// light footage, and a lower third keeps inside title safe.
@Suite("A set of titles that look designed")
struct TitleSetTests {

    static let canvas = CGSize(width: 1920, height: 1080)

    static let names = ["Keynote Clean", "Soft Gradient Glass", "Kinetic Bold", "Editorial Serif",
                        "Tech Terminal", "Behind Glass", "Light Leak", "Gradient Glow", "Stacked Stagger",
                        "Split Wipe", "Minimal Underline", "Pill Card"]

    /// The preset placed at one second over a ten second recording of `hex`.
    static func placed(_ preset: BuiltInTitle, over hex: String = "#101318") throws -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: canvas)
        var shape = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: hex,
                                      start: .zero, end: CGPoint(x: canvas.width, y: canvas.height))
        shape.fill = Paint(hex: hex)
        var clip = Layer(name: "Recording", content: .annotation(shape), frame: CGRect(origin: .zero, size: canvas))
        clip.time = LayerTime(inMS: 0, outMS: 10_000, sourceInMS: 0, sourceLengthMS: 10_000)
        doc.layers = [clip]
        doc.durationMS = 10_000
        let inserted = doc.insertTitle(preset, atTimeMS: 1000, motionBlur: true)
        let id = try #require(inserted, "\(preset.name)").layerID
        return (doc, id)
    }

    // MARK: - The set

    @Test("The shelf and the menus carry the twelve styles of the brief, pages then cards")
    func theTwelve() {
        #expect(BuiltInTitle.shelved.map(\.name) == Self.names)
        let pages = BuiltInTitle.presets(of: .titlePage).map(\.name)
        let cards = BuiltInTitle.presets(of: .nameCard).map(\.name)
        #expect(pages == Array(Self.names.prefix(9)))
        #expect(cards == Array(Self.names.suffix(3)))
        // Nothing of the old plain set is offered any more.
        let shelf = TitlePreset.shelf(saved: []).map(\.name)
        #expect(shelf == Self.names)
        for retired in ["Midnight", "Sunrise", "Paper", "Spotlight", "Aurora", "Bar", "Clean", "Accent", "Minimal"] {
            #expect(!shelf.contains(retired))
        }
        // Without moving backdrops a release offers only what does not move:
        // every page now stands on a moving look (task
        // `title-text-visibly-comes-in-and-every-built-in-t`), so that is the
        // one bare name card.
        let still = BuiltInTitle.shelved.filter { !$0.hasMovingBackdrop }
        #expect(still.allSatisfy { !$0.hasMovingBackdrop })
        #expect(BuiltInTitle.presets(of: .nameCard, movingBackdrops: false) == [.underline])
    }

    // MARK: - Designed, not a template

    @Test("Every part arrives on its own beat: at least three different moments in each")
    func separateBeats() {
        for preset in BuiltInTitle.shelved {
            let starts = Set(preset.design.parts.compactMap { $0.in?.delayMS })
            #expect(starts.count >= 3, "\(preset.name) brings its parts in at \(starts.sorted())")
        }
    }

    // MARK: - Words that visibly come in (`TitleEntranceInkTests` measures them)

    /// What a preset's headline comes in by: the build of every part that
    /// draws it, and what its words come in a piece at a time by.
    static func entrance(_ preset: BuiltInTitle) -> String {
        preset.design.parts.filter { $0.role == .headline || $0.path == "Headline" }
            .compactMap { part in
                part.in.map { "\($0.kind.rawValue)/\(($0.unit ?? $0.kind.defaultUnit).rawValue)" }
            }
            .sorted().joined(separator: "+")
    }

    @Test("Every headline comes in its own way: no two of the set share an entrance")
    func ownEntrances() {
        var seen: [String: String] = [:]
        for preset in BuiltInTitle.shelved {
            let entrance = Self.entrance(preset)
            #expect(!entrance.isEmpty, "\(preset.name) has no headline entrance")
            if let other = seen[entrance] {
                Issue.record("\(preset.name) comes in as \(other) does: \(entrance)")
            }
            seen[entrance] = preset.name
        }
    }

    @Test("A headline takes most of a second to come in, and the line under it comes on its own later beat")
    func headlineThenSubtitle() {
        for preset in BuiltInTitle.shelved {
            guard let headline = preset.design.parts.first(where: { $0.role == .headline })?.in else {
                Issue.record("\(preset.name) has no headline in")
                continue
            }
            #expect(headline.lengthMS >= 500, "\(preset.name)'s headline pieces take \(headline.lengthMS) ms")
            for part in preset.design.parts where part.role == .subtitle {
                let later = (part.in?.delayMS ?? 0) - headline.delayMS
                #expect(later >= 300, "\(preset.name) \(part.path) comes \(later) ms after the headline")
            }
        }
    }

    @Test("Every title stands on a moving look, except one deliberately bare name card")
    func movingLooks() {
        var still: [BuiltInTitle] = []
        for preset in BuiltInTitle.shelved {
            let title = preset.layer(in: Self.canvas)
            let background = TitleDesign.find("Background", in: title)
            let live = background?.annotation?.fill?.kind == .live
            // Behind Glass is made of the recording itself, frosted.
            let frosted = background?.style.effects.contains { $0.blur?.kind == .background } == true
            if !live && !frosted { still.append(preset) }
            #expect(preset.hasMovingBackdrop == (live || frosted), "\(preset.name) says it moves: \(preset.hasMovingBackdrop)")
        }
        #expect(still == [.underline], "standing on something still: \(still.map(\.name))")
        // Ten looks, and the set uses most of them, not the same one twice
        // over.
        let looks = BuiltInTitle.shelved.compactMap {
            TitleDesign.find("Background", in: $0.layer(in: Self.canvas))?.annotation?.fill?.live?.look
        }
        #expect(Set(looks).count == looks.count, "a look is used twice: \(looks)")
        #expect(looks.count >= 9)
    }

    @Test("Two type sizes at most")
    func twoSizes() {
        for preset in BuiltInTitle.shelved {
            let layer = preset.layer(in: Self.canvas)
            let sizes = Set(layer.selfAndDescendants.compactMap { $0.text.map { Int($0.fontSize.rounded()) } })
            #expect(!sizes.isEmpty, "\(preset.name) has no words")
            #expect(sizes.count <= 2, "\(preset.name) uses \(sizes.sorted())")
        }
    }

    @Test("Everything comes in on an ease out, a spring or an even turn, and leaves quicker on an ease in")
    func easesAndExits() {
        // Ease out rather than expo for words, so half way through an in it is
        // still plainly happening; the even ease for the ones that turn in
        // depth (`TitleBuildKind.defaultCurve`), and in and out for a wipe
        // that uncovers words, so its edge is seen crossing them.
        let arriving: Set<EasingCurve> = [.easeOut, .easeOutExpo, .easeOutQuint, .easeOutBack, .easeInOutSine,
                                          .easeInOut]
        for preset in BuiltInTitle.shelved {
            for part in preset.design.parts {
                if let entrance = part.in, entrance.kind != .typewriter {
                    #expect(arriving.contains(entrance.curve), "\(preset.name) \(part.path) comes in on \(entrance.curve)")
                }
                if let exit = part.out {
                    #expect(exit.curve == .easeIn, "\(preset.name) \(part.path) leaves on \(exit.curve)")
                    if let entrance = part.in {
                        #expect(exit.lengthMS < entrance.lengthMS,
                                "\(preset.name) \(part.path) leaves in \(exit.lengthMS) ms, came in \(entrance.lengthMS)")
                    }
                }
            }
        }
    }

    @Test("Something is still moving while every title holds")
    func movesWhileHolding() throws {
        for preset in BuiltInTitle.shelved {
            let (doc, id) = try Self.placed(preset)
            let layer = try #require(doc.layer(id: id))
            let time = try #require(layer.time)
            let arrived = time.inMS + doc.titleArrivalMS(layerID: id)
            let early = try Self.drawn(doc, atMS: arrived + 200)
            let later = try Self.drawn(doc, atMS: min(arrived + 1500, time.outMS - 700))
            #expect(early != later, "\(preset.name) stands still while it holds")
        }
    }

    /// Everything drawn at a moment. Grain reseeds itself every moment,
    /// which is not the kind of moving this asks about, so a piece's clock
    /// is kept only where a fill moves on its own (a mesh or a live look).
    static func drawn(_ doc: PhotonzDocument, atMS ms: Int) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(doc.drawn(atTimeMS: ms).layers.map(Self.clockless))
    }

    static func clockless(_ layer: Layer) -> Layer {
        var still = layer
        var drifts = false
        if case .annotation(let shape) = layer.content, shape.fill?.moves == true { drifts = true }
        if !drifts { still.drawnAtMS = nil }
        if !still.children.isEmpty { still.children = still.children.map(clockless) }
        return still
    }

    @Test("Lower thirds keep inside title safe: a tenth of the frame from every edge")
    func titleSafe() throws {
        for preset in BuiltInTitle.presets(of: .nameCard) {
            let (doc, id) = try Self.placed(preset)
            let time = try #require(doc.layer(id: id)?.time)
            let rest = doc.drawn(atTimeMS: time.inMS + doc.titleArrivalMS(layerID: id) + 100)
            let box = try #require(rest.layer(id: id)?.localBounds)
            #expect(box.minX >= Self.canvas.width * 0.1 - 1, "\(preset.name) \(box)")
            #expect(box.maxX <= Self.canvas.width * 0.9 + 1, "\(preset.name) \(box)")
            #expect(box.maxY <= Self.canvas.height * 0.9 + 1, "\(preset.name) \(box)")
            #expect(box.minY >= Self.canvas.height * 0.5, "\(preset.name) sits too high: \(box)")
        }
    }

    // MARK: - Legible over dark and light footage

    /// The worst contrast a line of words can have against what is behind it,
    /// over a black frame and a white one: the title's own backdrop where it
    /// paints one (a glass dims the footage by its opacity), a card's own
    /// backing where the words sit on one, and otherwise the footage itself.
    /// Every piece below a title with its frame in the title's own space:
    /// a piece inside a group of the title is framed in that group.
    static func flattened(_ layer: Layer, offset: CGPoint = .zero) -> [(piece: Layer, frame: CGRect)] {
        layer.children.flatMap { child -> [(piece: Layer, frame: CGRect)] in
            let frame = child.frame.offsetBy(dx: offset.x, dy: offset.y)
            let below = child.isGroup ? flattened(child, offset: frame.origin) : []
            return [(child, frame)] + below
        }
    }

    static func worstContrast(_ words: Layer, ink hex: String, in title: Layer, footage: RGBA) -> Double {
        guard let ink = RGBA(hex: hex) else { return 0 }
        let pieces = flattened(title)
        guard let mine = pieces.first(where: { $0.piece.id == words.id })?.frame else { return 0 }
        let middle = CGPoint(x: mine.midX, y: mine.midY)
        var behind: [RGBA] = [footage]
        for (piece, frame) in pieces where piece.id != words.id && piece.isVisible {
            guard case .annotation(let shape) = piece.content, piece.style.matte == nil,
                  piece.style.blendMode == .normal else { continue }
            let paint = shape.fill ?? Paint(hex: shape.colorHex)
            let full = frame.width >= canvas.width * 0.9
            guard full || frame.insetBy(dx: -1, dy: -1).contains(middle) else { continue }
            // A line drawn beside the words is not behind them.
            guard shape.fill != nil else { continue }
            // A moving look is read as drawn: its ground and the brightest
            // (or darkest) it is held to (`LivePalette`).
            let stops = paint.kind == .live
                ? [LivePalette(paint).ground, LivePalette(paint).extreme]
                : (paint.isGradient ? paint.orderedStops.map(\.hex) : [paint.hex]).compactMap(RGBA.init(hex:))
            let alpha = Double(piece.style.opacity)
            behind = stops.flatMap { stop in
                behind.map { under in
                    RGBA(r: stop.r * alpha + under.r * (1 - alpha), g: stop.g * alpha + under.g * (1 - alpha),
                         b: stop.b * alpha + under.b * (1 - alpha))
                }
            }
        }
        return behind.map { SegmentInk.contrast(ink, $0) }.min() ?? 0
    }

    @Test("Every line of words reads over black footage and white footage alike")
    func legible() throws {
        for preset in BuiltInTitle.shelved {
            let title = preset.layer(in: Self.canvas)
            let pieces = Self.flattened(title)
            for (words, frame) in pieces where words.text != nil {
                // Words that throw their own shadow stand over anything, and
                // so do words drawn inside a group that throws one.
                if !words.style.shadows.isEmpty { continue }
                if title.selfAndDescendants.contains(where: { group in
                    !group.style.shadows.isEmpty && group.children.contains { $0.id == words.id }
                }) { continue }
                let size = words.text?.fontSize ?? 0
                let needed = size >= 60 ? 3.0 : 4.5
                // Words a gradient fills are judged in each of its colours.
                let filled = pieces.first { $0.piece.style.matte == .shape
                    && $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }
                var inks = [words.text?.colorHex ?? ""]
                if let filled, case .annotation(let shape) = filled.piece.content, let paint = shape.fill {
                    inks = paint.orderedStops.map(\.hex)
                }
                for footage in [RGBA(r: 0, g: 0, b: 0), RGBA(r: 1, g: 1, b: 1)] {
                    for ink in inks {
                        let contrast = Self.worstContrast(words, ink: ink, in: title, footage: footage)
                        #expect(contrast >= needed,
                                "\(preset.name) \(words.name) in \(ink) reads at \(String(format: "%.2f", contrast)):1 over \(footage)")
                    }
                }
            }
        }
    }

    // MARK: - Every one lands, types, plays and restyles

    @Test("Every preset lands with its words open, plays on its tile, and takes every theme legibly")
    func landsPlaysRestyles() throws {
        for preset in BuiltInTitle.shelved {
            let (doc, id) = try Self.placed(preset)
            #expect(doc.titleRecipe(layerID: id) != nil, "\(preset.name) keeps no recipe")
            let reel = TitlePreset.builtIn(preset).reel(frame: Self.canvas, width: 320)
            #expect((reel?.pictures.count ?? 0) > 10, "\(preset.name) has no reel")
            for theme in TitleTheme.curated {
                var styled = doc
                let changed = styled.restyleTitle(layerID: id) { $0.theme = theme }
                #expect(changed, "\(preset.name) did not take \(theme.name)")
                let title = try #require(styled.layer(id: id))
                // The restyle's own legibility pass keeps words off a backing
                // they cannot be read on.
                let pieces = Self.flattened(title)
                for (words, frame) in pieces where words.text != nil && words.style.shadows.isEmpty {
                    guard let ink = RGBA(hex: words.text?.colorHex ?? "") else { continue }
                    let middle = CGPoint(x: frame.midX, y: frame.midY)
                    let backing = pieces.last { other in
                        other.piece.id != words.id && other.piece.isVisible && other.piece.style.opacity >= 0.85
                            && other.piece.style.matte == nil && other.piece.annotation?.fill != nil
                            && !other.piece.style.effects.contains { $0.blur?.kind == .background }
                            && other.frame.contains(middle) && other.frame.width < Self.canvas.width * 0.9
                    }
                    guard let backing, case .annotation(let shape) = backing.piece.content,
                          let paint = shape.fill, let ground = RGBA(hex: paint.hex) else { continue }
                    #expect(SegmentInk.contrast(ink, ground) >= 3,
                            "\(preset.name) \(words.name) on \(theme.name)")
                }
            }
        }
    }

    @Test("The terminal's cursor waits after whatever words are typed, and blinks while the title holds")
    func cursorFollowsTheWords() throws {
        var (doc, id) = try Self.placed(.terminal)
        let before = try #require(doc.layer(id: id).flatMap { TitleDesign.find("Title", in: $0) })
        doc.updateLayer(id: before.id) { layer in
            guard case .text(var words) = layer.content else { return }
            words.string = "Shipping the whole thing faster"
            layer.content = .text(words)
        }
        let relaid = doc.relayOutTitle(layerID: id)
        #expect(relaid)
        let title = try #require(doc.layer(id: id))
        let words = try #require(TitleDesign.find("Title", in: title))
        let cursor = try #require(TitleDesign.find("Cursor", in: title))
        #expect(words.frame.width > before.frame.width)
        #expect(cursor.frame.minX >= words.frame.maxX, "the cursor sits at \(cursor.frame.minX), the words end at \(words.frame.maxX)")
        // On and off while it holds.
        let time = try #require(title.time)
        let seen = Set(stride(from: 1000, to: time.lengthMS - 600, by: 90).compactMap { at -> Bool? in
            guard let drawn = doc.drawn(atTimeMS: time.inMS + at).layer(id: id),
                  let lit = TitleDesign.find("Cursor", in: drawn) else { return nil }
            return lit.style.opacity > 0.5
        })
        #expect(seen == [true, false])
    }
}
