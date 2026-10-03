import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Title pages and name cards (`docs/design/video-titles.md`).
///
/// Written before the model. A preset is a group of ordinary layers placed in
/// time and animated in and out with the keys Animate In and Animate Out write,
/// so everything checked here is that sentence: what lands, where, for how
/// long, with which keys, and that a person's own version comes back out the
/// same way.
@Suite("Title pages and name cards")
struct TitlePresetsTests {

    static let canvas = CGSize(width: 1920, height: 1080)

    /// An eight second recording-shaped document.
    static func eightSeconds(canvas: CGSize = canvas) -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: canvas)
        var clip = Layer(name: "Recording",
                         content: .annotation(AnnotationContent(shape: .rectangle,
                                                                colorHex: "#0C0E14")),
                         frame: CGRect(origin: .zero, size: canvas))
        clip.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: 8000)
        doc.layers = [clip]
        doc.durationMS = 8000
        return doc
    }

    static func insert(_ doc: inout PhotonzDocument, _ preset: BuiltInTitle,
                       atTimeMS ms: Int) -> InsertedTitle? {
        doc.insertTitle(preset, atTimeMS: ms)
    }

    static func insert(_ doc: inout PhotonzDocument, _ preset: SavedTitlePreset,
                       atTimeMS ms: Int) -> InsertedTitle? {
        doc.insertTitle(preset, atTimeMS: ms)
    }

    // MARK: - The type list

    @Test func everyKindHasAtLeastFourPresets() {
        #expect(TitleKind.allCases.count >= 2)
        for kind in TitleKind.allCases {
            #expect(BuiltInTitle.presets(of: kind).count >= 4, "\(kind.name)")
        }
    }

    @Test func kindsHaveTheirOwnLengths() {
        #expect(TitleKind.titlePage.lengthMS == 4000)
        #expect(TitleKind.nameCard.lengthMS == 5000)
    }

    @Test func presetNamesAreShortAndUniqueWithinAKind() {
        for kind in TitleKind.allCases {
            let names = BuiltInTitle.presets(of: kind).map(\.name)
            #expect(Set(names).count == names.count)
            for name in names { #expect(name.count <= 20 && !name.contains("—")) }
        }
    }

    // MARK: - What lands

    @Test func aTitlePageCoversTheWholeFrame() throws {
        for preset in BuiltInTitle.presets(of: .titlePage) {
            let layer = preset.layer(in: Self.canvas)
            let box = layer.localBounds
            #expect(box.minX <= 0 && box.minY <= 0, "\(preset.name)")
            #expect(box.maxX >= Self.canvas.width && box.maxY >= Self.canvas.height, "\(preset.name)")
        }
    }

    @Test func aNameCardSitsInTheBottomLeftOfTheFrame() {
        for preset in BuiltInTitle.presets(of: .nameCard) {
            let box = preset.layer(in: Self.canvas).localBounds
            #expect(box.minX > 0 && box.minX < Self.canvas.width * 0.2, "\(preset.name)")
            #expect(box.maxY < Self.canvas.height && box.minY > Self.canvas.height * 0.6, "\(preset.name)")
            #expect(box.maxX < Self.canvas.width * 0.7, "\(preset.name)")
        }
    }

    @Test func everyPresetIsOneGroupOfOrdinaryLayersWithWordsInIt() {
        for preset in BuiltInTitle.allCases {
            let layer = preset.layer(in: Self.canvas)
            #expect(layer.isGroup)
            #expect(layer.name == preset.kind.name)
            #expect(layer.children.count >= 2)
            #expect(layer.selfAndDescendants.contains { $0.text != nil }, "\(preset.name)")
            // Nothing component-shaped: a preset is a copy you own.
            #expect(layer.group?.componentID == nil)
        }
    }

    @Test func aPresetScalesWithTheFrame() {
        let small = BuiltInTitle.presets(of: .nameCard)[0].layer(in: CGSize(width: 960, height: 540))
        let big = BuiltInTitle.presets(of: .nameCard)[0].layer(in: Self.canvas)
        let ratio = big.localBounds.height / small.localBounds.height
        #expect(abs(ratio - 2) < 0.15)
    }

    // MARK: - Inserting

    @Test func insertingPutsItAtThePlayheadForItsKindsLength() throws {
        var doc = Self.eightSeconds()
        let preset = BuiltInTitle.presets(of: .nameCard)[0]
        let inserted = try #require(Self.insert(&doc, preset, atTimeMS: 2000))
        let layer = try #require(doc.layer(id: inserted.layerID))
        #expect(layer.time?.inMS == 2000)
        #expect(layer.time?.outMS == 7000)
        #expect(layer.isPlacedInTime)
        // Its own track: a new top-level layer, on top of the recording.
        #expect(doc.layers.last?.id == inserted.layerID)
    }

    @Test func aTitlePageAtTheStartRunsItsWholeLengthEvenPastTheEnd() throws {
        var doc = Self.eightSeconds()
        let preset = BuiltInTitle.presets(of: .titlePage)[0]
        let inserted = try #require(Self.insert(&doc, preset, atTimeMS: 6000))
        let layer = try #require(doc.layer(id: inserted.layerID))
        #expect(layer.time?.outMS == 10_000)
        #expect(doc.documentDurationMS == 10_000)
    }

    @Test func insertingAnimatesItInAndOut() throws {
        var doc = Self.eightSeconds()
        for preset in BuiltInTitle.allCases {
            let inserted = try #require(Self.insert(&doc, preset, atTimeMS: 1000))
            let layer = try #require(doc.layer(id: inserted.layerID))
            let marks = doc.clipKeyMarks(layerID: layer.id).map(\.documentMS)
            let time = try #require(layer.time)
            // Each end either fades, with the one fade the bar shows, or is
            // keys: one at the end and one where it has finished arriving.
            if preset.animateIn == .fade {
                #expect(layer.pictureFadeMS(.in) == TitleAnimation.lengthMS, "\(preset.name)")
            } else {
                #expect(marks.contains(time.inMS), "\(preset.name)")
                #expect(marks.contains(time.inMS + TitleAnimation.lengthMS), "\(preset.name)")
            }
            if preset.animateOut == .fade {
                #expect(layer.pictureFadeMS(.out) == TitleAnimation.lengthMS, "\(preset.name)")
            } else {
                #expect(marks.contains(time.outMS), "\(preset.name)")
            }
        }
    }

    @Test func aFadeInStartsInvisibleAndArrivesWhole() throws {
        var doc = Self.eightSeconds()
        let preset = try #require(BuiltInTitle.allCases.first { $0.animateIn == .fade })
        let inserted = try #require(Self.insert(&doc, preset, atTimeMS: 1000))
        let layer = try #require(doc.layer(id: inserted.layerID))
        #expect(layer.pictureFadeLevel(atDocumentTimeMS: 1000) < 0.01)
        #expect(layer.pictureFadeLevel(atDocumentTimeMS: 2000) > 0.99)
    }

    @Test func aSlideInStartsWhollyOffTheLeftOfTheFrame() throws {
        var doc = Self.eightSeconds()
        let preset = try #require(BuiltInTitle.presets(of: .nameCard).first { $0.animateIn == .slide })
        let inserted = try #require(Self.insert(&doc, preset, atTimeMS: 1000))
        let layer = try #require(doc.layer(id: inserted.layerID))
        let start = try #require(doc.keyedValue(layerID: layer.id, .motion(.position),
                                                atDocumentTimeMS: 1000))
        guard case let .point(origin) = start else {
            Issue.record("position is not a point")
            return
        }
        // The group's box, moved to where the slide starts, ends left of x 0.
        let box = layer.localBounds
        let right = box.maxX + (origin.x - layer.frame.origin.x)
        #expect(right <= 0)
    }

    @Test func theWordsToTypeAreTheMainLine() throws {
        var doc = Self.eightSeconds()
        let page = try #require(Self.insert(&doc, BuiltInTitle.presets(of: .titlePage)[0], atTimeMS: 0))
        #expect(doc.layer(id: page.wordsID)?.name == "Title")
        let card = try #require(Self.insert(&doc, BuiltInTitle.presets(of: .nameCard)[0], atTimeMS: 0))
        #expect(doc.layer(id: card.wordsID)?.name == "Name")
    }

    @Test func aDocumentWithNoTimeTakesNoTitle() {
        var doc = PhotonzDocument(canvasSize: Self.canvas)
        #expect(doc.insertTitle(BuiltInTitle.allCases[0], atTimeMS: 0) == nil)
        #expect(doc.layers.isEmpty)
    }

    @Test func twoInsertsAreTwoIndependentLayers() throws {
        var doc = Self.eightSeconds()
        let preset = BuiltInTitle.presets(of: .nameCard)[1]
        let one = try #require(Self.insert(&doc, preset, atTimeMS: 0))
        let two = try #require(Self.insert(&doc, preset, atTimeMS: 3000))
        #expect(one.layerID != two.layerID)
        #expect(one.wordsID != two.wordsID)
        let ids = doc.allLayers.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyPanelBehindACardsWordsCoversThem() throws {
        for preset in BuiltInTitle.presets(of: .nameCard) where preset != .minimal {
            var doc = Self.eightSeconds()
            let card = try #require(Self.insert(&doc, preset, atTimeMS: 0))
            let words = try #require(doc.canvasLayer(id: card.wordsID)).frame
            let panels = try #require(doc.layer(id: card.layerID)).selfAndDescendants
                .filter { $0.name == "Background" }
            #expect(!panels.isEmpty, "\(preset.name)")
            // The panel's drawn rectangle, not only its frame, is the size of
            // the card: a shape stretched from nothing draws nothing.
            let covering = panels.compactMap { panel -> CGRect? in
                guard let drawn = doc.canvasLayer(id: panel.id), let shape = drawn.annotation else { return nil }
                let corner = CGPoint(x: drawn.frame.minX + shape.end.x, y: drawn.frame.minY + shape.end.y)
                return CGRect(origin: drawn.frame.origin,
                              size: CGSize(width: corner.x - drawn.frame.minX, height: corner.y - drawn.frame.minY))
            }
            #expect(covering.contains { $0.contains(CGPoint(x: words.midX, y: words.midY)) }, "\(preset.name)")
        }
    }

    @Test func aLongerNameMakesAWiderCard() throws {
        for preset in BuiltInTitle.presets(of: .nameCard) {
            var doc = Self.eightSeconds()
            let card = try #require(Self.insert(&doc, preset, atTimeMS: 0))
            let before = try #require(doc.layer(id: card.layerID)).localBounds
            let words = try #require(doc.canvasLayer(id: card.wordsID))
            var content = try #require(words.text)
            content.string = "Alexandra Montgomery-Smith"
            // The box the app commits: the words, measured.
            let wider = CGRect(origin: words.frame.origin, size: TextMeasurement.size(of: content))
            doc.commitTextEdit(id: card.wordsID, content: content, canvasFrame: wider)
            let after = try #require(doc.layer(id: card.layerID)).localBounds
            #expect(after.width > before.width * 1.5, "\(preset.name)")
            // Every panel behind the words still covers them (Minimal has none).
            guard preset != .minimal else { continue }
            let name = try #require(doc.canvasLayer(id: card.wordsID)).frame
            #expect(after.maxX >= name.maxX, "\(preset.name)")
        }
    }

    // MARK: - Your own

    @Test func savingKeepsTheEditedVersionAndInsertsItBackTheSame() throws {
        var doc = Self.eightSeconds()
        let preset = BuiltInTitle.presets(of: .nameCard)[0]
        let inserted = try #require(Self.insert(&doc, preset, atTimeMS: 1000))
        doc.updateLayer(id: inserted.wordsID) { layer in
            if case .text(var words) = layer.content {
                words.string = "Dana Zearing"
                words.colorHex = "#FFCC00"
                layer.content = .text(words)
            }
        }
        let saved = try #require(doc.savedTitlePreset(layerID: inserted.layerID, name: "My card"))
        #expect(saved.kind == .nameCard)
        #expect(saved.name == "My card")
        #expect(saved.lengthMS == 5000)

        // Round trip through settings.
        let data = try JSONEncoder().encode([saved])
        let back = try JSONDecoder().decode([SavedTitlePreset].self, from: data)
        #expect(back == [saved])

        var other = Self.eightSeconds()
        let again = try #require(Self.insert(&other, back[0], atTimeMS: 3000))
        let layer = try #require(other.layer(id: again.layerID))
        #expect(layer.time?.inMS == 3000)
        #expect(layer.time?.outMS == 8000)
        #expect(other.layer(id: again.wordsID)?.text?.string == "Dana Zearing")
        #expect(other.layer(id: again.wordsID)?.text?.colorHex == "#FFCC00")
        // Its animation came with it, moved to where it now starts.
        let marks = other.clipKeyMarks(layerID: layer.id).map(\.documentMS)
        #expect(marks.contains(3000) && marks.contains(3000 + TitleAnimation.lengthMS))
        #expect(layer.pictureFadeMS(.out) == TitleAnimation.lengthMS)
        #expect(again.layerID != inserted.layerID)
    }

    @Test func aSavedPresetInsertedInTheSameDocumentLandsOnATrackOfItsOwn() throws {
        var doc = Self.eightSeconds()
        let card = try #require(Self.insert(&doc, BuiltInTitle.presets(of: .nameCard)[0], atTimeMS: 0))
        doc.updateLayer(id: card.layerID) { $0.trackID = UUID() }
        let saved = try #require(doc.savedTitlePreset(layerID: card.layerID, name: "Mine"))
        let again = try #require(Self.insert(&doc, saved, atTimeMS: 2000))
        #expect(doc.layer(id: again.layerID)?.trackID == nil)
        #expect(doc.layer(id: again.layerID)?.name == "Name Card")
    }

    @Test func aSavedPresetKnowsItsKindFromHowMuchOfTheFrameItCovers() throws {
        var doc = Self.eightSeconds()
        let page = try #require(Self.insert(&doc, BuiltInTitle.presets(of: .titlePage)[2], atTimeMS: 0))
        #expect(doc.savedTitlePreset(layerID: page.layerID, name: "Mine")?.kind == .titlePage)
    }

    @Test func aSavedPresetLandsScaledOnAFrameOfAnotherSize() throws {
        var doc = Self.eightSeconds()
        let card = try #require(Self.insert(&doc, BuiltInTitle.presets(of: .nameCard)[0], atTimeMS: 0))
        let saved = try #require(doc.savedTitlePreset(layerID: card.layerID, name: "Half"))
        var small = Self.eightSeconds(canvas: CGSize(width: 960, height: 540))
        let placed = try #require(Self.insert(&small, saved, atTimeMS: 0))
        let before = try #require(doc.layer(id: card.layerID)).localBounds
        let after = try #require(small.layer(id: placed.layerID)).localBounds
        #expect(abs(after.width - before.width / 2) < before.width * 0.02)
        #expect(abs(after.minY - before.minY / 2) < before.height * 0.05)
    }

    @Test func onlySomethingPlacedInTimeCanBeSaved() throws {
        var doc = Self.eightSeconds()
        let recording = try #require(doc.layers.first)
        #expect(doc.savedTitlePreset(layerID: recording.id, name: "Nope") == nil)
        #expect(!doc.canSaveTitlePreset(layerID: recording.id))
    }

    @Test func aBlankNameIsRefused() throws {
        var doc = Self.eightSeconds()
        let card = try #require(Self.insert(&doc, BuiltInTitle.presets(of: .nameCard)[0], atTimeMS: 0))
        #expect(doc.savedTitlePreset(layerID: card.layerID, name: "   ") == nil)
    }
}
