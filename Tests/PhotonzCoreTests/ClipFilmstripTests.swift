import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **Pictures along a clip on the timeline** (`ClipFilmstrip.swift`).
///
/// At Fit a clip is the coloured bar the mock draws. Opened out far enough
/// that one small picture stands for a short stretch of the recording, the
/// clip shows frames of what is in it, the way Premiere and Final Cut draw a
/// clip, so a moment can be found by looking rather than by playing. The user
/// chose exactly that on 2026-09-25 ("pictures only when zoomed in").
///
/// Written before the change, which is the rule for `PhotonzCore`.
@Suite("Pictures along a clip")
struct ClipFilmstripTests {

    static let fiveMinutes = 5 * 60 * 1000

    // MARK: - When pictures show

    @Test func fitIsAlwaysTheColouredBar() {
        // Even a short clip whose tiles would each be a fraction of a second.
        #expect(ClipFilmstrip.opacity(zoom: .fit, msPerTile: 200) == 0)
        #expect(ClipFilmstrip.opacity(zoom: .fit, msPerTile: 20_000) == 0)
    }

    @Test func theFirstZoomStepShowsPicturesOfAFiveMinuteRecording() {
        // Five minutes across a 900 point lane at 2x: 150s over 900 points,
        // and a tile about 45 points wide stands for about seven seconds.
        let msPerTile = 150_000.0 / 900 * 45
        let zoom = TimelineZoom(scale: 2, startMS: 0)
        #expect(ClipFilmstrip.opacity(zoom: zoom, msPerTile: msPerTile) == 1)
    }

    @Test func aTileStandingForTooLongStaysABar() {
        // An hour at 2x: a tile is well over a minute of recording, which is
        // no picture of anything in particular.
        let zoom = TimelineZoom(scale: 2, startMS: 0)
        #expect(ClipFilmstrip.opacity(zoom: zoom, msPerTile: 90_000) == 0)
    }

    @Test func picturesFadeInAsTheTimelineOpensOutRatherThanPopping() {
        // A pinch passes through every scale between Fit and the first step:
        // the pictures come up gradually across that stretch.
        let a = ClipFilmstrip.opacity(zoom: TimelineZoom(scale: 1.1, startMS: 0), msPerTile: 1000)
        let b = ClipFilmstrip.opacity(zoom: TimelineZoom(scale: 1.3, startMS: 0), msPerTile: 1000)
        let c = ClipFilmstrip.opacity(zoom: TimelineZoom(scale: 1.6, startMS: 0), msPerTile: 1000)
        #expect(a > 0 && a < b && b < c)
        #expect(c == 1)
    }

    @Test func picturesFadeAsEachTileStandsForMore() {
        let zoom = TimelineZoom(scale: 4, startMS: 0)
        let clear = ClipFilmstrip.opacity(zoom: zoom, msPerTile: ClipFilmstrip.clearTileMS)
        let between = ClipFilmstrip.opacity(
            zoom: zoom, msPerTile: (ClipFilmstrip.clearTileMS + ClipFilmstrip.goneTileMS) / 2)
        let gone = ClipFilmstrip.opacity(zoom: zoom, msPerTile: ClipFilmstrip.goneTileMS)
        #expect(clear == 1)
        #expect(between > 0 && between < 1)
        #expect(gone == 0)
    }

    // MARK: - How big a picture is

    @Test func aTileIsTheShapeOfTheRecording() {
        // A 16:10 screen recording in a 25 point strip.
        #expect(ClipFilmstrip.tileWidth(height: 25, aspect: 1.6) == 40)
    }

    @Test func anOddShapeIsHeldToSomethingThatStillReads() {
        // A tall phone recording, and a very wide strip.
        #expect(ClipFilmstrip.tileWidth(height: 20, aspect: 0.2) == 20 * ClipFilmstrip.narrowestAspect)
        #expect(ClipFilmstrip.tileWidth(height: 20, aspect: 9) == 20 * ClipFilmstrip.widestAspect)
    }

    // MARK: - Which moments the pictures are of

    @Test func aTileStandsForARungOnADoublingLadder() {
        // Whatever the zoom, a tile is one frame times a power of two long,
        // so a pinch within one rung asks for no new frames at all.
        let one = ClipFilmstrip.tileMS(nominalWidth: 40, msPerPoint: 10)
        let two = ClipFilmstrip.tileMS(nominalWidth: 40, msPerPoint: 11)
        #expect(one == two)
        let frames = one / MovieRef.frameStepMS
        #expect(one % MovieRef.frameStepMS == 0)
        #expect(frames > 0 && frames & (frames - 1) == 0)
    }

    @Test func theRungIsTheOneNearestTheNominalWidth() {
        // 40 points at 10ms a point is 400ms: the rungs near it are 264 and 528.
        let tile = ClipFilmstrip.tileMS(nominalWidth: 40, msPerPoint: 10)
        #expect(tile == MovieRef.frameStepMS * 16)
    }

    @Test func aTileIsNeverShorterThanAFrame() {
        #expect(ClipFilmstrip.tileMS(nominalWidth: 40, msPerPoint: 0.01) == MovieRef.frameStepMS)
    }

    @Test func onlyTheTilesOnScreenAreLaidOut() {
        // A five minute clip opened out to a hundred thousand points: only the
        // ones over the window come back, not thousands.
        let piece = ClipPiece(sourceInMS: 0, lengthMS: Self.fiveMinutes)
        let tiles = ClipFilmstrip.tiles(of: piece, pieceWidth: 100_000,
                                        visible: 50_000...51_000, nominalWidth: 40)
        #expect(!tiles.isEmpty)
        #expect(tiles.count < 60)
        #expect(tiles.first.map { $0.x <= 50_000 } == true)
        #expect(tiles.last.map { $0.x + $0.width >= 51_000 } == true)
    }

    @Test func tilesSitEndToEndAnchoredToTheClip() {
        // Anchored to the clip rather than to the window, so scrolling slides
        // the same pictures along instead of asking for new ones.
        let piece = ClipPiece(sourceInMS: 0, lengthMS: 60_000)
        let a = ClipFilmstrip.tiles(of: piece, pieceWidth: 6000, visible: 0...500, nominalWidth: 40)
        let b = ClipFilmstrip.tiles(of: piece, pieceWidth: 6000, visible: 100...600, nominalWidth: 40)
        let shared = Set(a).intersection(Set(b))
        #expect(shared.count >= a.count - 2)
        for (left, right) in zip(a, a.dropFirst()) {
            #expect(abs(left.x + left.width - right.x) < 0.001)
            #expect(right.index == left.index + 1)
        }
    }

    @Test func eachTileIsTheFrameAtItsStartInTheRecording() {
        // A piece cut from later in the file shows the part of the file it
        // kept, and a sped up piece reads further along for the same width.
        let piece = ClipPiece(sourceInMS: 10_000, lengthMS: 10_000)
        let tiles = ClipFilmstrip.tiles(of: piece, pieceWidth: 1000, visible: 0...1000, nominalWidth: 40)
        #expect(tiles.first?.sourceMS == 10_000)
        let step = ClipFilmstrip.tileMS(nominalWidth: 40, msPerPoint: 10)
        #expect(tiles.dropFirst().first?.sourceMS == 10_000 + step)

        let fast = ClipPiece(sourceInMS: 0, lengthMS: 10_000, speedPercent: 200)
        let quick = ClipFilmstrip.tiles(of: fast, pieceWidth: 1000, visible: 0...1000, nominalWidth: 40)
        #expect(quick.dropFirst().first?.sourceMS == 2 * step)
    }

    @Test func aHeldFrameIsThatOneFrameAllAlong() {
        let held = ClipPiece.held(atSourceMS: 4200, forMS: 3000)
        let tiles = ClipFilmstrip.tiles(of: held, pieceWidth: 600, visible: 0...600, nominalWidth: 40)
        #expect(tiles.count > 1)
        #expect(tiles.allSatisfy { $0.sourceMS == 4200 })
    }

    @Test func theLastTileIsCutToTheEndOfThePiece() {
        let piece = ClipPiece(sourceInMS: 0, lengthMS: 10_000)
        let tiles = ClipFilmstrip.tiles(of: piece, pieceWidth: 1010, visible: 0...2000, nominalWidth: 40)
        let last = tiles.last
        #expect(last.map { abs($0.x + $0.width - 1010) < 0.001 } == true)
        #expect(tiles.allSatisfy { $0.x < 1010 })
    }

    @Test func nothingOnScreenIsNoTiles() {
        let piece = ClipPiece(sourceInMS: 0, lengthMS: 10_000)
        #expect(ClipFilmstrip.tiles(of: piece, pieceWidth: 0, visible: 0...100, nominalWidth: 40).isEmpty)
        #expect(ClipFilmstrip.tiles(of: piece, pieceWidth: 1000, visible: 2000...2100, nominalWidth: 40).isEmpty)
    }

    // MARK: - Which view draws which tile

    /// A tile's slot is the view that draws it. A far jump of the playhead
    /// carries the window to tiles it has never shown, and a view per tile
    /// INDEX threw every picture view away and built new ones on each jump,
    /// a fifth of the pause after it (`first-long-jump-when-zoomed-in-walk`).
    /// Slots come round in a ring as wide as the window holds, so the jump
    /// hands the same views new pictures.
    @Test func aFarJumpDrawsItsTilesWithTheViewsAlreadyThere() {
        let piece = ClipPiece(sourceInMS: 0, lengthMS: Self.fiveMinutes)
        let here = ClipFilmstrip.tiles(of: piece, pieceWidth: 100_000, visible: 2000...2900, nominalWidth: 40)
        let there = ClipFilmstrip.tiles(of: piece, pieceWidth: 100_000, visible: 61_013...61_913,
                                        nominalWidth: 40)
        let ring = ClipFilmstrip.slotRing(visibleWidth: 900, tileWidth: here[0].width)
        let before = Set(here.map { ClipFilmstrip.slot(of: $0.index, ring: ring) })
        let after = Set(there.map { ClipFilmstrip.slot(of: $0.index, ring: ring) })
        // Every tile on screen has a view of its own...
        #expect(before.count == here.count)
        #expect(after.count == there.count)
        // ...and at most the one or two the ring holds spare are new.
        #expect(after.subtracting(before).count <= 2)
    }

    /// Scrolling keeps each picture in the view that was already drawing it,
    /// which is what kept a scrolled filmstrip from flickering.
    @Test func aScrollKeepsEachTileInItsView() {
        let piece = ClipPiece(sourceInMS: 0, lengthMS: 60_000)
        let a = ClipFilmstrip.tiles(of: piece, pieceWidth: 6000, visible: 0...500, nominalWidth: 40)
        let b = ClipFilmstrip.tiles(of: piece, pieceWidth: 6000, visible: 100...600, nominalWidth: 40)
        let ring = ClipFilmstrip.slotRing(visibleWidth: 500, tileWidth: a[0].width)
        let slotOf = { (tiles: [ClipFilmstrip.Tile]) in
            Dictionary(uniqueKeysWithValues: tiles.map { ($0.index, ClipFilmstrip.slot(of: $0.index, ring: ring)) })
        }
        let first = slotOf(a)
        let second = slotOf(b)
        for (index, slot) in second where first[index] != nil {
            #expect(first[index] == slot, "tile \(index) moved to another view")
        }
        #expect(Set(second.values).count == b.count)
    }

    @Test func aRingIsNeverEmpty() {
        #expect(ClipFilmstrip.slotRing(visibleWidth: 0, tileWidth: 40) >= 1)
        #expect(ClipFilmstrip.slotRing(visibleWidth: 900, tileWidth: 0) >= 1)
        #expect(ClipFilmstrip.slot(of: -3, ring: 4) >= 0)
    }
}
