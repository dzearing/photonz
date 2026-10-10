import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Titles move in parts, not as one block (task
/// `titles-move-in-parts-not-as-one-block`, `docs/design/video-titles-polish.md`).
///
/// Written before the model. A title is parts (its background, its lines of
/// words, its accents), each with its own in, hold and out, and the design
/// compiles into ORDINARY keys on the layers inside the title's group: nothing
/// here is a new runtime object, so what a preset made is still layers you own.
@Suite("Titles move in parts")
struct TitleDesignTests {

    static let canvas = CGSize(width: 1920, height: 1080)

    static func tenSeconds() -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: canvas)
        var clip = Layer(name: "Recording",
                         content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#0C0E14")),
                         frame: CGRect(origin: .zero, size: canvas))
        clip.time = LayerTime(inMS: 0, outMS: 10_000, sourceInMS: 0, sourceLengthMS: 10_000)
        doc.layers = [clip]
        doc.durationMS = 10_000
        return doc
    }

    static func insert(_ doc: inout PhotonzDocument, _ preset: BuiltInTitle, atTimeMS ms: Int) -> InsertedTitle? {
        doc.insertTitle(preset, atTimeMS: ms)
    }

    static func end(_ doc: inout PhotonzDocument, _ id: UUID, toMS ms: Int) -> Bool {
        doc.moveLayerEnd(id, toMS: ms)
    }

    static func start(_ doc: inout PhotonzDocument, _ id: UUID, toMS ms: Int) -> Bool {
        doc.moveLayerStart(id, toMS: ms)
    }

    static func apply(_ doc: inout PhotonzDocument, _ design: TitleDesign, _ id: UUID) -> Bool {
        doc.applyTitleDesign(design, layerID: id)
    }

    /// A piece of a drawn title, by its path of names below the group.
    static func piece(_ doc: PhotonzDocument, _ group: UUID, _ path: String, atMS ms: Int) -> Layer? {
        guard let drawn = doc.drawn(atTimeMS: ms).layer(id: group) else { return nil }
        return TitleDesign.find(path, in: drawn)
    }

    static func opacity(_ doc: PhotonzDocument, _ group: UUID, _ path: String, atMS ms: Int) -> Double {
        Double(piece(doc, group, path, atMS: ms)?.style.opacity ?? -1)
    }

    // MARK: - The two new curves

    @Test("Ease out expo and Ease out quint are the published curves, on the shared list")
    func expoAndQuintJoinTheList() throws {
        for t in stride(from: 0.05, through: 0.95, by: 0.1) {
            #expect(abs(EasingCurve.easeOutExpo.value(at: t) - EasingCurve.custom(x1: 0.16, y1: 1, x2: 0.3, y2: 1).value(at: t)) < 1e-9)
            #expect(abs(EasingCurve.easeOutQuint.value(at: t) - EasingCurve.custom(x1: 0.22, y1: 1, x2: 0.36, y2: 1).value(at: t)) < 1e-9)
        }
        // Fast off the mark: most of the way there in the first quarter.
        #expect(EasingCurve.easeOutExpo.value(at: 0.25) > 0.8)
        #expect(EasingCurve.easeOutExpo.value(at: 0) == 0)
        #expect(EasingCurve.easeOutExpo.value(at: 1) == 1)
        #expect(EasingCurve.easeOutExpo.title == "Ease out expo")
        #expect(EasingCurve.easeOutQuint.title == "Ease out quint")
        // Standard eases, after Ease out and before the shaped ones.
        let named = EasingCurve.named
        #expect(Array(named.prefix(EasingCurve.standardCount))
                    == [.linear, .easeInOut, .easeIn, .easeOut, .easeOutQuint, .easeOutExpo])
        #expect(named[EasingCurve.standardCount] == .easeInOutSine)
        // Kept in a document and read back as themselves.
        let data = try JSONEncoder().encode([EasingCurve.easeOutExpo, .easeOutQuint])
        #expect(try JSONDecoder().decode([EasingCurve].self, from: data) == [.easeOutExpo, .easeOutQuint])
        // A key nobody eased under one of them reads as arriving slowly.
        #expect(KeyEase(following: .easeOutExpo) == .easeIn)
    }

    // MARK: - The model

    @Test("Every built-in title is parts, each naming a piece its group really has")
    func everyPresetIsPartsOfItsOwnGroup() throws {
        for preset in BuiltInTitle.allCases {
            let design = preset.design
            let group = preset.layer(in: Self.canvas)
            #expect(design.parts.count >= 3, "\(preset.name)")
            for part in design.parts {
                #expect(TitleDesign.find(part.path, in: group) != nil, "\(preset.name): \(part.path)")
            }
            let roles = Set(design.parts.map(\.role))
            #expect(roles.contains(.headline), "\(preset.name)")
        }
    }

    @Test("A title's parts come in on separate beats: background, then headline, then subtitle 100 to 150 ms later")
    func partsEnterOnSeparateBeats() throws {
        for preset in BuiltInTitle.allCases {
            let ins = preset.design.parts.compactMap { part in part.in.map { (part.role, $0.delayMS) } }
            // Not one slab: at least three different moments.
            #expect(Set(ins.map(\.1)).count >= 3, "\(preset.name)")
            let headline = try #require(ins.first { $0.0 == .headline }?.1, "\(preset.name)")
            if let background = ins.first(where: { $0.0 == .background })?.1 {
                #expect(background < headline, "\(preset.name)")
            }
            if let subtitle = ins.first(where: { $0.0 == .subtitle })?.1 {
                #expect((100...150).contains(subtitle - headline), "\(preset.name): \(subtitle - headline)")
            }
        }
    }

    @Test("Exits are shorter than entrances, ease in, and finish inside the last half second")
    func exitsAreShorterAndEaseIn() throws {
        for preset in BuiltInTitle.allCases {
            for part in preset.design.parts {
                guard let out = part.out else { continue }
                #expect(out.curve == .easeIn, "\(preset.name): \(part.path)")
                if let entrance = part.in {
                    #expect(out.lengthMS < entrance.lengthMS, "\(preset.name): \(part.path)")
                    #expect(out.lengthMS <= entrance.lengthMS * 7 / 10, "\(preset.name): \(part.path)")
                }
            }
            // The refit that keeps an out at the bar's end finds it there.
            #expect(preset.design.outLengthMS <= TitleAnimation.lengthMS, "\(preset.name)")
            #expect(preset.design.outLengthMS > 0, "\(preset.name)")
        }
    }

    @Test("A design keeps in a file and reads back the same")
    func aDesignRoundTrips() throws {
        let design = BuiltInTitle.midnight.design
        let data = try JSONEncoder().encode(design)
        #expect(try JSONDecoder().decode(TitleDesign.self, from: data) == design)
    }

    // MARK: - What inserting one does

    @Test("Inserted, the background has started while the headline is still to come")
    func theBackgroundLeadsTheHeadline() throws {
        var doc = Self.tenSeconds()
        let inserted = try #require(Self.insert(&doc, .midnight, atTimeMS: 1000))
        let id = inserted.layerID
        let design = BuiltInTitle.midnight.design
        let headline = try #require(design.parts.first { $0.role == .headline }?.in)
        // At the in point nothing is up yet.
        #expect(Self.opacity(doc, id, "Background", atMS: 1000) < 0.01)
        #expect(Self.opacity(doc, id, "Title", atMS: 1000) < 0.01)
        // Just before the headline's beat, the background is well on its way
        // and the headline has not begun.
        let beat = 1000 + headline.delayMS
        #expect(Self.opacity(doc, id, "Background", atMS: beat - 10) > 0.3)
        #expect(Self.opacity(doc, id, "Title", atMS: beat - 10) < 0.01)
        // Each part arrived: whole, at the place it was drawn.
        let drawnAtRest = BuiltInTitle.midnight.layer(in: Self.canvas)
        for part in design.parts {
            let entrance = try #require(part.in)
            let arrived = 1000 + entrance.delayMS + entrance.lengthMS
            let piece = try #require(Self.piece(doc, id, part.path, atMS: arrived))
            let authored = try #require(TitleDesign.find(part.path, in: drawnAtRest))
            #expect(abs(piece.style.opacity - authored.style.opacity) < 0.01, "\(part.path)")
            #expect(abs(piece.frame.minX - authored.frame.minX) < 0.5, "\(part.path)")
            #expect(abs(piece.frame.minY - authored.frame.minY) < 0.5, "\(part.path)")
        }
        // No group-wide fade in: the parts carry it.
        #expect(try #require(doc.layer(id: id)).pictureFadeMS(.in) == 0)
    }

    @Test("A title page still dissolves out with the bar's own fade; a name card leaves part by part")
    func pagesDissolveCardsLeaveInParts() throws {
        var doc = Self.tenSeconds()
        let page = try #require(Self.insert(&doc, .midnight, atTimeMS: 1000))
        let card = try #require(Self.insert(&doc, .bar, atTimeMS: 1000))
        #expect(try #require(doc.layer(id: page.layerID)).pictureFadeMS(.out) == TitleAnimation.lengthMS)
        #expect(try #require(doc.layer(id: card.layerID)).pictureFadeMS(.out) == 0)
        // The card's role is gone before its name, and both before the end.
        let end = try #require(doc.layer(id: card.layerID)?.time?.outMS)
        #expect(Self.opacity(doc, card.layerID, "Role", atMS: end - 150) < 0.05)
        #expect(Self.opacity(doc, card.layerID, "Name", atMS: end - 150) > 0.05)
        #expect(Self.opacity(doc, card.layerID, "Name", atMS: end - 1) < 0.05)
    }

    @Test("Every built-in is whole in the middle of its stretch")
    func everyPresetIsWholeInTheMiddle() throws {
        for preset in BuiltInTitle.allCases {
            var doc = Self.tenSeconds()
            let inserted = try #require(Self.insert(&doc, preset, atTimeMS: 0))
            let middle = try #require(doc.layer(id: inserted.layerID)?.time).lengthMS / 2
            let authored = preset.layer(in: Self.canvas)
            for part in preset.design.parts {
                let piece = try #require(Self.piece(doc, inserted.layerID, part.path, atMS: middle))
                let drawn = try #require(TitleDesign.find(part.path, in: authored))
                #expect(abs(piece.style.opacity - drawn.style.opacity) < 0.01, "\(preset.name): \(part.path)")
            }
        }
    }

    // MARK: - Each behaviour

    static func oneBox(_ part: TitlePart, lengthMS: Int = 4000) throws -> (PhotonzDocument, UUID) {
        var doc = tenSeconds()
        var content = AnnotationContent(shape: .rectangle, strokeWidth: 0, colorHex: "#FFFFFF",
                                        start: .zero, end: CGPoint(x: 400, y: 100))
        content.fill = Paint(hex: "#FFFFFF")
        let box = Layer(name: "Box", content: .annotation(content), frame: CGRect(x: 200, y: 300, width: 400, height: 100))
        let words = Layer(name: "Words", content: .text(TextContent(string: "Hello", fontName: "SF Pro",
                                                                     fontSize: 60, colorHex: "#FFFFFF")),
                          frame: CGRect(x: 200, y: 500, width: 300, height: 80))
        var group = Layer(name: "Title", content: .group(GroupContent(children: [box, words])), frame: .zero)
        group.time = LayerTime(inMS: 0, outMS: lengthMS)
        doc.addLayer(group)
        #expect(Self.apply(&doc, TitleDesign(parts: [part]), group.id))
        return (doc, group.id)
    }

    @Test("Rise starts lower and see-through and lands where it was drawn")
    func riseLands() throws {
        let (doc, id) = try Self.oneBox(TitlePart(path: "Box", role: .accent,
                                                  in: TitleBuild(.rise, delayMS: 0, lengthMS: 600, amount: 30)))
        let start = try #require(Self.piece(doc, id, "Box", atMS: 0))
        #expect(abs(start.frame.minY - 330) < 0.5)
        #expect(start.style.opacity < 0.01)
        let landed = try #require(Self.piece(doc, id, "Box", atMS: 600))
        #expect(abs(landed.frame.minY - 300) < 0.5)
        #expect(landed.style.opacity > 0.99)
        // On expo it is most of the way there a quarter of the way in.
        let early = try #require(Self.piece(doc, id, "Box", atMS: 150))
        #expect(early.frame.minY < 306)
    }

    @Test("Blur in starts soft and sharpens")
    func blurInSharpens() throws {
        let (doc, id) = try Self.oneBox(TitlePart(path: "Words", role: .headline,
                                                  in: TitleBuild(.blurIn, delayMS: 100, lengthMS: 500, amount: 12)))
        #expect(try #require(Self.piece(doc, id, "Words", atMS: 100)).style.blurRadius > 11)
        #expect(try #require(Self.piece(doc, id, "Words", atMS: 600)).style.blurRadius < 0.01)
        #expect(try #require(Self.piece(doc, id, "Words", atMS: 50)).style.opacity < 0.01)
    }

    @Test("Scale from starts larger and settles at its own size")
    func scaleFromSettles() throws {
        let (doc, id) = try Self.oneBox(TitlePart(path: "Box", role: .accent,
                                                  in: TitleBuild(.scaleFrom, delayMS: 0, lengthMS: 600, amount: 120)))
        #expect(abs(try #require(Self.piece(doc, id, "Box", atMS: 0)).frame.width - 480) < 1)
        #expect(abs(try #require(Self.piece(doc, id, "Box", atMS: 600)).frame.width - 400) < 0.5)
    }

    @Test("Spring pop overshoots its size once and settles")
    func springPopOvershoots() throws {
        let (doc, id) = try Self.oneBox(TitlePart(path: "Box", role: .accent,
                                                  in: TitleBuild(.springPop, delayMS: 0, lengthMS: 500, amount: 80)))
        let widths = stride(from: 0, through: 500, by: 25).compactMap { Self.piece(doc, id, "Box", atMS: $0)?.frame.width }
        #expect((widths.max() ?? 0) > 404)
        #expect(abs((widths.last ?? 0) - 400) < 0.5)
    }

    @Test("A wipe on a box grows it from one edge with the far edge still")
    func wipeGrowsABoxFromItsEdge() throws {
        let (doc, id) = try Self.oneBox(TitlePart(path: "Box", role: .accent,
                                                  in: TitleBuild(.wipe, delayMS: 0, lengthMS: 400, direction: .right)))
        let start = try #require(Self.piece(doc, id, "Box", atMS: 0))
        #expect(start.frame.width < 2)
        #expect(abs(start.frame.minX - 200) < 0.5)
        // Not even the point a crop always leaves shows before it starts.
        #expect(start.style.opacity < 0.01)
        let half = try #require(Self.piece(doc, id, "Box", atMS: 60))
        #expect(abs(half.frame.minX - 200) < 0.5)
        #expect(half.frame.width > 20 && half.frame.width < 400)
        #expect(abs(try #require(Self.piece(doc, id, "Box", atMS: 400)).frame.width - 400) < 0.5)
        #expect(try #require(Self.piece(doc, id, "Box", atMS: 400)).style.opacity > 0.99)
    }

    @Test("A wipe on words fades them until words can be masked")
    func wipeOnWordsFades() throws {
        let (doc, id) = try Self.oneBox(TitlePart(path: "Words", role: .headline,
                                                  in: TitleBuild(.wipe, delayMS: 0, lengthMS: 400)))
        let start = try #require(Self.piece(doc, id, "Words", atMS: 0))
        #expect(start.style.opacity < 0.01)
        #expect(abs(start.frame.width - 300) < 0.5)
    }

    @Test("Hold drift moves a part slowly while it is up; push grows it a little")
    func holdsKeepMoving() throws {
        let drift = TitlePart(path: "Box", role: .accent,
                              in: TitleBuild(.fade, delayMS: 0, lengthMS: 400),
                              hold: TitleHold(.drift, amount: 20, direction: .left),
                              out: TitleBuild(.fade, delayMS: 0, lengthMS: 250, curve: .easeIn))
        let (doc, id) = try Self.oneBox(drift)
        let arrived = try #require(Self.piece(doc, id, "Box", atMS: 400))
        let leaving = try #require(Self.piece(doc, id, "Box", atMS: 3750))
        #expect(abs(arrived.frame.minX - 200) < 0.5)
        #expect(abs(leaving.frame.minX - 180) < 0.5)
        let push = TitlePart(path: "Box", role: .background, in: TitleBuild(.fade, delayMS: 0, lengthMS: 400),
                             hold: TitleHold(.push, amount: 3))
        let (pushed, pid) = try Self.oneBox(push)
        #expect(abs(try #require(Self.piece(pushed, pid, "Box", atMS: 400)).frame.width - 400) < 0.5)
        #expect(abs(try #require(Self.piece(pushed, pid, "Box", atMS: 4000)).frame.width - 412) < 0.5)
    }

    @Test("An out leaves from where the hold left it, eased in, and is gone at the end")
    func outLeavesFromTheHold() throws {
        let part = TitlePart(path: "Box", role: .accent,
                             in: TitleBuild(.rise, delayMS: 0, lengthMS: 500, amount: 20),
                             hold: TitleHold(.drift, amount: 10, direction: .right),
                             out: TitleBuild(.rise, delayMS: 100, lengthMS: 300, amount: 20, curve: .easeIn))
        let (doc, id) = try Self.oneBox(part)
        // Out from 3600 to 3900: the hold ends at 3600, ten points right.
        let begins = try #require(Self.piece(doc, id, "Box", atMS: 3600))
        #expect(abs(begins.frame.minX - 210) < 0.5)
        #expect(abs(begins.frame.minY - 300) < 0.5)
        // Eased in: barely moved a quarter of the way through.
        let quarter = try #require(Self.piece(doc, id, "Box", atMS: 3675))
        #expect(quarter.frame.minY > 297)
        let gone = try #require(Self.piece(doc, id, "Box", atMS: 3900))
        #expect(abs(gone.frame.minY - 280) < 0.5)
        #expect(gone.style.opacity < 0.01)
    }

    // MARK: - Locked builds

    /// When each part's in and out start and finish, as distances from the
    /// title's in and out points, read off the keys themselves.
    static func builds(_ doc: PhotonzDocument, _ id: UUID) throws -> [String: [Int]] {
        let group = try #require(doc.layer(id: id))
        let time = try #require(group.time)
        var out: [String: [Int]] = [:]
        for part in BuiltInTitle.midnight.design.parts {
            let piece = try #require(TitleDesign.find(part.path, in: group))
            let keys = (piece.motions ?? []).flatMap(\.keyframes).map { $0.atMS - time.sourceInMS }
            let front = keys.filter { $0 < time.lengthMS / 2 }
            let back = keys.filter { $0 >= time.lengthMS / 2 }.map { time.lengthMS - $0 }
            out[part.path] = [front.min() ?? -1, front.max() ?? -1, back.max() ?? -1, back.min() ?? -1]
        }
        return out
    }

    @Test("Trimming a title stretches its hold and keeps its in and out, at three lengths")
    func lockedBuildsAtThreeLengths() throws {
        var doc = Self.tenSeconds()
        let inserted = try #require(Self.insert(&doc, .midnight, atTimeMS: 1000))
        let id = inserted.layerID
        let first = try Self.builds(doc, id)
        for length in [2500, 6000, 8500] {
            #expect(Self.end(&doc, id, toMS: 1000 + length))
            #expect(try Self.builds(doc, id) == first, "at \(length) ms")
            #expect(try #require(doc.layer(id: id)).pictureFadeMS(.out) == TitleAnimation.lengthMS)
        }
        // From the left end too: the in goes where the in point goes.
        #expect(Self.start(&doc, id, toMS: 2000))
        #expect(try Self.builds(doc, id) == first)
        // And it still plays: the headline whole in the middle.
        let time = try #require(doc.layer(id: id)?.time)
        #expect(Self.opacity(doc, id, "Title", atMS: time.inMS + time.lengthMS / 2) > 0.99)
        #expect(Self.opacity(doc, id, "Title", atMS: time.outMS - 1) < 0.05)
    }

    @Test("The background's push runs the whole hold, however long the bar is made")
    func thePushFollowsTheHold() throws {
        var doc = Self.tenSeconds()
        let id = try #require(Self.insert(&doc, .midnight, atTimeMS: 0)).layerID
        #expect(Self.end(&doc, id, toMS: 8000))
        let atEnd = try #require(Self.piece(doc, id, "Background", atMS: 7999))
        let arrived = try #require(Self.piece(doc, id, "Background", atMS: 1000))
        #expect(atEnd.frame.width > arrived.frame.width * 1.02)
    }

    // MARK: - Cards lay themselves out

    @Test("A card that lays itself out again keeps every part landing where the layout puts it")
    func aReflowedCardKeepsItsPartsInPlace() throws {
        var doc = Self.tenSeconds()
        let inserted = try #require(Self.insert(&doc, .bar, atTimeMS: 0))
        // Make the name larger: the role below it moves down.
        doc.updateLayer(id: inserted.wordsID) { name in
            if case var .text(text) = name.content {
                text.fontSize *= 1.6
                name.content = .text(text)
                name.frame.size = TextMeasurement.size(of: text)
            }
        }
        doc.reflowLayouts()
        let group = try #require(doc.layer(id: inserted.layerID))
        let role = try #require(TitleDesign.find("Role", in: group))
        let drawnRole = try #require(Self.piece(doc, inserted.layerID, "Role", atMS: 2500))
        #expect(abs(drawnRole.frame.minY - role.frame.minY) < 0.5)
        #expect(abs(drawnRole.frame.minX - role.frame.minX) < 0.5)
    }

    @Test("A part picked inside a title reads its keys on the title's clock, as it plays")
    func aPartReadsOnTheTitlesClock() throws {
        var doc = Self.tenSeconds()
        let inserted = try #require(Self.insert(&doc, .bar, atTimeMS: 3000))
        let name = inserted.wordsID
        #expect(doc.keyedValue(layerID: name, .motion(.opacity), atDocumentTimeMS: 3000) == .number(0))
        #expect(doc.keyedValue(layerID: name, .motion(.opacity), atDocumentTimeMS: 3700) == .number(100))
        #expect(doc.keyDiamond(layerID: name, .motion(.opacity), atDocumentTimeMS: 3150) == .onKey)
    }

    // MARK: - Where the playhead and the tile land

    @Test("A title has arrived once its last part has")
    func arrivalIsTheLastPart() throws {
        var doc = Self.tenSeconds()
        for preset in BuiltInTitle.allCases {
            let inserted = try #require(Self.insert(&doc, preset, atTimeMS: 2000))
            #expect(doc.titleArrivalMS(layerID: inserted.layerID) == preset.design.inLengthMS, "\(preset.name)")
        }
        // Something animated with one Animate In arrives when that does.
        var plain = Self.tenSeconds()
        var box = Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#FFFFFF")),
                        frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        box.time = LayerTime(inMS: 0, outMS: 3000)
        plain.addLayer(box)
        _ = plain.animateIn(.slide, layerID: box.id)
        #expect(plain.titleArrivalMS(layerID: box.id) == TitleAnimation.lengthMS)
    }
}
