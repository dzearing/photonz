import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Title pages and name cards on the Library shelf (`docs/design/video-titles.md`,
/// "On the Library shelf").
///
/// Written before the model. The shelf lists every preset, the person's own
/// first within each kind; a tile let go over the timeline lands on the track
/// under the pointer when that track is free for the whole of it and on a new
/// track of its own above it when not, so a drop never covers a clip; and each
/// tile is a picture of the preset at rest.
@Suite("Title presets on the Library shelf")
struct TitlePresetShelfTests {

    static let canvas = TitlePresetsTests.canvas

    static func saved(_ name: String, _ kind: TitleKind) throws -> SavedTitlePreset {
        var doc = TitlePresetsTests.eightSeconds()
        let preset: BuiltInTitle = kind == .titlePage ? .paper : .clean
        let insertedLanded = doc.insertTitle(preset, atTimeMS: 0)
        let inserted = try #require(insertedLanded)
        var kept = try #require(doc.savedTitlePreset(layerID: inserted.layerID, name: name))
        kept.kind = kind
        return kept
    }

    // MARK: - The list

    @Test func theShelfHoldsEveryBuiltInPresetPagesFirst() {
        let shelf = TitlePreset.shelf(saved: [])
        #expect(shelf.count == BuiltInTitle.allCases.count)
        #expect(shelf.map(\.name) == ["Midnight", "Sunrise", "Paper", "Spotlight",
                                      "Bar", "Clean", "Accent", "Minimal"])
    }

    @Test func aPersonsOwnPresetsComeFirstWithinTheirKind() throws {
        let card = try Self.saved("Team Card", .nameCard)
        let page = try Self.saved("Intro", .titlePage)
        let shelf = TitlePreset.shelf(saved: [card, page])
        #expect(shelf.map(\.name) == ["Intro", "Midnight", "Sunrise", "Paper", "Spotlight",
                                      "Team Card", "Bar", "Clean", "Accent", "Minimal"])
    }

    @Test func everyTileHasAShelfEntryInComponentsThatFindsItAgain() throws {
        let card = try Self.saved("Team Card", .nameCard)
        let shelf = TitlePreset.shelf(saved: [card])
        let ids = shelf.map(\.entry.id)
        #expect(Set(ids).count == ids.count)
        for preset in shelf {
            #expect(preset.entry.scope == .components)
            #expect(preset.entry.name == preset.name)
            #expect(TitlePreset(entryID: preset.entry.id, saved: [card]) == preset)
        }
        #expect(TitlePreset(entryID: "not-a-title", saved: [card]) == nil)
        // A saved one that has since been forgotten is no longer on the shelf.
        #expect(TitlePreset(entryID: TitlePreset.saved(card).id, saved: []) == nil)
    }

    @Test func theLineUnderATileSaysItsKindAndWhoseItIs() throws {
        #expect(TitlePreset.builtIn(.midnight).entry.detail == "Title Page")
        #expect(TitlePreset.builtIn(.bar).entry.detail == "Name Card")
        #expect(TitlePreset.saved(try Self.saved("Team Card", .nameCard)).entry.detail == "Your Name Card")
    }

    @Test func searchFindsAPresetByItsName() {
        let entries = TitlePreset.shelf(saved: []).map(\.entry)
        #expect(LibrarySearch.filter(entries, query: "spotlight").map(\.name) == ["Spotlight"])
    }

    // MARK: - Where a drop lands

    /// The recording on V1 and an empty track above it, the way a person has
    /// it after Add Track Above.
    static func recordingWithATrackAbove() -> (PhotonzDocument, v1: UUID, v2: UUID) {
        var doc = TitlePresetsTests.eightSeconds()
        let clip = doc.layers[0].id
        let v1 = doc.addTrack(.video, at: 0)
        doc.updateLayer(id: clip) { $0.trackID = v1 }
        let v2 = doc.addTrack(.video, at: 0)
        return (doc, v1, v2)
    }

    @Test func aDropOnAFreeTrackLandsOnThatTrack() throws {
        let (doc, _, v2) = Self.recordingWithATrackAbove()
        let landing = doc.titleLanding(lengthMS: 5000, atMS: 2000, over: .onto(v2))
        #expect(landing.target == .onto(v2))
        #expect(landing.allowed)
        #expect(landing.startMS == 2000)
        #expect(landing.lengthMS == 5000)
    }

    @Test func aDropOnABusyTrackGetsANewTrackJustAboveIt() throws {
        let (doc, v1, _) = Self.recordingWithATrackAbove()
        let index = try #require(doc.timelineTracks.firstIndex { $0.id == v1 })
        let landing = doc.titleLanding(lengthMS: 5000, atMS: 2000, over: .onto(v1))
        #expect(landing.target == .newTrack(at: index))
        #expect(landing.allowed)
        #expect(!doc.timelineTracks.map(\.name).contains(landing.trackName))
    }

    @Test func aDropBetweenTracksMakesOneThereAndNowhereGoesOnTop() {
        let (doc, _, _) = Self.recordingWithATrackAbove()
        #expect(doc.titleLanding(lengthMS: 4000, atMS: 0, over: .newTrack(at: 1)).target == .newTrack(at: 1))
        #expect(doc.titleLanding(lengthMS: 4000, atMS: 0, over: nil).target == .newTrack(at: 0))
    }

    @Test func aLockedTrackIsNeverLandedOn() throws {
        var (doc, _, v2) = Self.recordingWithATrackAbove()
        doc.updateTrack(v2) { $0.isLocked = true }
        let landing = doc.titleLanding(lengthMS: 4000, atMS: 0, over: .onto(v2))
        #expect(landing.target != .onto(v2))
        #expect(landing.allowed)
    }

    @Test func insertingAtALandingPutsItOnThatTrackAtThatMoment() throws {
        var (doc, v1, v2) = Self.recordingWithATrackAbove()
        let landing = doc.titleLanding(lengthMS: TitleKind.nameCard.lengthMS, atMS: 3000, over: .onto(v2))
        let insertedLanded = doc.insertTitle(.builtIn(.bar), atTimeMS: 3000, landing: landing)
        let inserted = try #require(insertedLanded)
        #expect(doc.trackID(ofClip: inserted.layerID) == v2)
        let time = try #require(doc.layer(id: inserted.layerID)?.time)
        #expect(time.inMS == 3000)
        #expect(time.outMS == 3000 + TitleKind.nameCard.lengthMS)
        // The recording is untouched.
        #expect(doc.clipIDs(onTrack: v1).count == 1)
        #expect(doc.layers.first { $0.name == "Recording" }?.time?.inMS == 0)
        #expect(doc.layers.first { $0.name == "Recording" }?.time?.outMS == 8000)
    }

    @Test func insertingOnABusyTracksLandingMakesTheNewTrackAndCoversNothing() throws {
        var (doc, v1, _) = Self.recordingWithATrackAbove()
        let before = doc.timelineTracks.count
        let landing = doc.titleLanding(lengthMS: TitleKind.titlePage.lengthMS, atMS: 1000, over: .onto(v1))
        let insertedLanded = doc.insertTitle(.builtIn(.midnight), atTimeMS: 1000, landing: landing)
        let inserted = try #require(insertedLanded)
        #expect(doc.timelineTracks.count == before + 1)
        let track = try #require(doc.trackID(ofClip: inserted.layerID))
        #expect(track != v1)
        #expect(doc.layers.first { $0.name == "Recording" }?.time?.outMS == 8000)
        #expect(doc.clipIDs(onTrack: v1).count == 1)
    }

    @Test func aLandedPresetStillAnimatesInAndOutAndOpensItsWords() throws {
        var (doc, _, v2) = Self.recordingWithATrackAbove()
        let landing = doc.titleLanding(lengthMS: TitleKind.nameCard.lengthMS, atMS: 1000, over: .onto(v2))
        let insertedLanded = doc.insertTitle(.builtIn(.bar), atTimeMS: 1000, landing: landing)
        let inserted = try #require(insertedLanded)
        let layer = try #require(doc.layer(id: inserted.layerID))
        // Bar slides in (keys) and fades out (the bar's own fade).
        #expect(!(layer.motions ?? []).isEmpty)
        #expect(doc.layer(id: inserted.wordsID)?.name == "Name")
    }

    @Test func aSavedPresetLandsAtALandingToo() throws {
        let card = try Self.saved("Team Card", .nameCard)
        var (doc, _, v2) = Self.recordingWithATrackAbove()
        let landing = doc.titleLanding(lengthMS: card.lengthMS, atMS: 2500, over: .onto(v2))
        let insertedLanded = doc.insertTitle(.saved(card), atTimeMS: 2500, landing: landing)
        let inserted = try #require(insertedLanded)
        #expect(doc.trackID(ofClip: inserted.layerID) == v2)
        #expect(doc.layer(id: inserted.layerID)?.time?.inMS == 2500)
    }

    // MARK: - The picture on the tile

    static let frame = CGSize(width: 1920, height: 1080)

    @Test func aTilesPictureIsAStillOfThePresetAtRest() throws {
        for preset in TitlePreset.shelf(saved: []) {
            let picture = try #require(preset.preview(frame: Self.frame, width: 320), "\(preset.name)")
            // About as wide as asked: a card's sizes are whole points on the
            // frame it is drawn for, so its corner lands within a few pixels.
            #expect(abs(picture.canvasSize.width - 320) <= 320 * 0.1, "\(preset.name)")
            #expect(!picture.hasTime, "a tile is a still picture: \(preset.name)")
            // Nothing in it is invisible: a fade in drawn at its first frame
            // would be an empty tile.
            for layer in picture.allLayers {
                #expect(layer.isVisible, "\(preset.name): \(layer.name)")
            }
            let words = picture.allLayers.filter { $0.text != nil }
            #expect(!words.isEmpty, "\(preset.name)")
        }
    }

    @Test func aTitlePagesPictureIsTheWholeFrame() throws {
        let picture = try #require(TitlePreset.builtIn(.midnight).preview(frame: Self.frame, width: 320))
        #expect(picture.canvasSize == CGSize(width: 320, height: 180))
    }

    @Test func aNameCardsPictureIsTheCornerOfTheFrameItSitsIn() throws {
        for preset in TitlePreset.shelf(saved: []) where preset.kind == .nameCard {
            let picture = try #require(preset.preview(frame: Self.frame, width: 320), "\(preset.name)")
            let size = picture.canvasSize
            // The tile's own shape, so it fills the card's picture well.
            #expect(abs(size.width / size.height - 1.6) < 0.05, "\(preset.name) \(size)")
            // The backdrop fills it, so white words have something to read against.
            let backdrop = try #require(picture.layers.first)
            #expect(backdrop.frame.standardized == CGRect(origin: .zero, size: size))
            // The card is whole, and big enough to read: well over a quarter
            // of the picture across, where on the whole frame it is a speck.
            let box = try #require(picture.layers.last).localBounds
            #expect(box.minX >= 0 && box.maxX <= size.width + 0.5, "\(preset.name) \(box)")
            #expect(box.minY >= 0 && box.maxY <= size.height + 0.5, "\(preset.name) \(box)")
            #expect(box.width >= size.width * 0.3, "\(preset.name) \(box) in \(size)")
            // ...and it is still seen sitting low in the frame, as it lands.
            #expect(box.minY > size.height * 0.4, "\(preset.name) \(box) in \(size)")
        }
    }

    @Test func aSlideInPresetIsPicturedWhereItRestsNotWhereItStarts() throws {
        // Bar slides in from off the left of the frame; its tile must show it
        // where it settles, inside the picture.
        let picture = try #require(TitlePreset.builtIn(.bar).preview(frame: Self.frame, width: 320))
        let card = try #require(picture.layers.last)
        #expect(card.frame.minX > 0)
    }

    @Test func aSavedPresetIsPicturedToo() throws {
        let card = try Self.saved("Team Card", .nameCard)
        let picture = try #require(TitlePreset.saved(card).preview(frame: Self.frame, width: 320))
        #expect(abs(picture.canvasSize.width - 320) <= 320 * 0.1)
        let shown = try #require(picture.layers.last).localBounds
        #expect(shown.maxX <= picture.canvasSize.width + 0.5)
    }

    // MARK: - The shelf drawn in groups

    @Test func aGroupedShelfIsEachGroupsTilesUnderItsHeader() {
        let width: CGFloat = 236
        let sizing = LibraryShelfLayout.Sizing.card
        let header = LibraryShelfLayout.groupHeaderHeight
        let titles = LibraryShelfLayout.contentHeight(tileCount: 8, width: width, sizing: sizing)
        let components = LibraryShelfLayout.contentHeight(tileCount: 5, width: width, sizing: sizing)
        #expect(LibraryShelfLayout.contentHeight(groups: [8, 5], width: width, sizing: sizing)
                == header + titles + header + components)
        // An empty group takes no room at all, header included.
        #expect(LibraryShelfLayout.contentHeight(groups: [8, 0], width: width, sizing: sizing)
                == header + titles)
        #expect(LibraryShelfLayout.contentHeight(groups: [0, 0], width: width, sizing: sizing) == 0)
    }

    @Test func aTileInALaterGroupStartsBelowTheGroupsAboveIt() {
        let width: CGFloat = 236
        let sizing = LibraryShelfLayout.Sizing.card
        let header = LibraryShelfLayout.groupHeaderHeight
        let titles = LibraryShelfLayout.contentHeight(tileCount: 8, width: width, sizing: sizing)
        #expect(LibraryShelfLayout.tileTop(group: 0, index: 2, groups: [8, 5], width: width, sizing: sizing)
                == header + LibraryShelfLayout.tileTop(index: 2, width: width, sizing: sizing))
        #expect(LibraryShelfLayout.tileTop(group: 1, index: 3, groups: [8, 5], width: width, sizing: sizing)
                == header + titles + header + LibraryShelfLayout.tileTop(index: 3, width: width, sizing: sizing))
    }
}
