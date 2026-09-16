import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What Corner Radius means over a GROUP.
///
/// A group has no outline of its own. It rounds by masking its corners off,
/// and a mask can only ever cut a corner away, never put a curve back. So over
/// a group holding a rounded button, the old row read the group's own mask —
/// nought — with the knob at the far left, beside a button that was plainly
/// round, and the first stretch of the pull did nothing at all because the
/// mask was still cutting less than the button's own curve. The row was not
/// broken, it was offset: it started counting from the wrong place.
///
/// So the row reads what is DRAWN at the group's corners, and cannot be pulled
/// below it. Reading: the group's own mask and the curve its contents already
/// have, whichever cuts more. Bottom stop: the curve its contents already have,
/// because there is nothing under that to pull down to.
struct ContainerRoundingTests {

    // MARK: - Fixtures

    private func rectangle(_ frame: CGRect, radius: CGFloat = 0,
                           strokeWidth: CGFloat = 0) -> Layer {
        var content = AnnotationContent(shape: .rectangle, strokeWidth: strokeWidth,
                                        start: .zero,
                                        end: CGPoint(x: frame.width, y: frame.height))
        content.cornerRadius = radius
        return Layer(name: "Rectangle", content: .annotation(content), frame: frame)
    }

    private func label(_ frame: CGRect) -> Layer {
        Layer(name: "Save", content: .text(TextContent(string: "Save")), frame: frame)
    }

    private func picture(_ frame: CGRect, styleRadius: CGFloat = 0) -> Layer {
        Layer(name: "Shot", content: .image(ImageRef(pixelSize: frame.size)), frame: frame,
              style: LayerStyle(cornerRadius: CornerRadii(styleRadius)))
    }

    private func group(_ children: [Layer], at origin: CGPoint = .zero,
                       maskRadius: CGFloat = 0, isFrame: Bool = false,
                       size: CGSize = CGSize(width: 360, height: 120)) -> Layer {
        Layer(name: "Group", content: .group(GroupContent(children: children, isFrame: isFrame)),
              frame: CGRect(origin: origin, size: size),
              style: LayerStyle(cornerRadius: CornerRadii(maskRadius)))
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024), layers: layers)
    }

    /// The walk's own Save button: a group whose box is exactly the rounded
    /// rectangle inside it, with a label sitting on top.
    private func saveButton(radius: CGFloat = 18, maskRadius: CGFloat = 0) -> Layer {
        let box = CGRect(x: 0, y: 0, width: 360, height: 120)
        return group([rectangle(box, radius: radius),
                      label(CGRect(x: 60, y: 40, width: 48, height: 33))],
                     at: CGPoint(x: 240, y: 180), maskRadius: maskRadius)
    }

    // MARK: - The curve the contents already put there

    @Test func aGroupBackedByARoundedBoxIsAlreadyRound() {
        let button = saveButton(radius: 18)
        #expect(button.containedCornerRadii == CornerRadii(18))
    }

    @Test func aGroupBackedByASquareBoxIsNotRound() {
        let button = saveButton(radius: 0)
        #expect(button.containedCornerRadii == .none)
    }

    @Test func nothingReachingTheCornersLeavesThemSquare() {
        // Two labels side by side: the group's box is their union, and neither
        // of them covers it, so nothing round is painted at its corners.
        let g = group([label(CGRect(x: 0, y: 0, width: 100, height: 40)),
                       label(CGRect(x: 200, y: 60, width: 100, height: 40))])
        #expect(g.containedCornerRadii == .none)
    }

    @Test func aHiddenBackingBoxPaintsNothing() {
        var rect = rectangle(CGRect(x: 0, y: 0, width: 360, height: 120), radius: 18)
        rect.isVisible = false
        let g = group([rect, label(CGRect(x: 60, y: 40, width: 48, height: 33))])
        #expect(g.containedCornerRadii == .none)
    }

    @Test func theTopmostBoxCoveringTheGroupDecides() {
        let box = CGRect(x: 0, y: 0, width: 360, height: 120)
        // Later children draw on top, so the last one covering the box is the
        // one whose corners you can see.
        let g = group([rectangle(box, radius: 4), rectangle(box, radius: 18)])
        #expect(g.containedCornerRadii == CornerRadii(18))
    }

    @Test func aScreenReadsTheSurfaceFillingIt() {
        let g = group([rectangle(CGRect(x: 0, y: 0, width: 360, height: 120), radius: 12),
                       label(CGRect(x: 20, y: 20, width: 48, height: 33))],
                      at: CGPoint(x: 100, y: 100), isFrame: true)
        #expect(g.containedCornerRadii == CornerRadii(12))
    }

    @Test func cornersSetApartCarryAcross() {
        let box = CGRect(x: 0, y: 0, width: 360, height: 120)
        var content = AnnotationContent(shape: .rectangle, strokeWidth: 0,
                                        start: .zero, end: CGPoint(x: 360, y: 120))
        content.cornerRadii = CornerRadii(topLeft: 20, topRight: 20, bottomRight: 0, bottomLeft: 0)
        let tab = Layer(name: "Tab", content: .annotation(content), frame: box)
        let g = group([tab])
        #expect(g.containedCornerRadii == CornerRadii(topLeft: 20, topRight: 20,
                                                      bottomRight: 0, bottomLeft: 0))
    }

    @Test func onlyAContainerIsBackedByAnything() {
        // A rectangle draws its own curve. Nothing is "inside" it.
        let rect = rectangle(CGRect(x: 0, y: 0, width: 40, height: 40), radius: 8)
        #expect(rect.containedCornerRadii == .none)
        #expect(picture(CGRect(x: 0, y: 0, width: 40, height: 40), styleRadius: 12)
            .containedCornerRadii == .none)
    }

    // MARK: - What the row reads, and where its knob stops

    @Test func theRowReadsTheRoundnessOnScreenNotTheInvisibleBox() {
        let button = saveButton(radius: 18)
        let doc = document([button])
        let row = doc.cornerRadiusSelection(layerIDs: [button.id], readingWhatShows: true)
        #expect(row.reading.value == 18)
    }

    @Test func aMaskedGroupStopsWhereItsContentsAlreadyAre() {
        // While the group is the thing being masked, the knob cannot go under
        // the curve its contents already have: a mask takes a corner away and
        // never puts one back. A group with no mask is not masked at all any
        // more — the pull reaches the button inside it (`ContainerReachTests`),
        // which can be squared as well as rounded, so its knob starts at
        // nought.
        let button = saveButton(radius: 18, maskRadius: 24)
        let doc = document([button])
        let row = doc.cornerRadiusSelection(layerIDs: [button.id], readingWhatShows: true)
        #expect(row.floor == 18)
    }

    @Test func aMaskCuttingMoreThanTheContentsIsWhatYouSee() {
        // Mask 24 over a button curved 18: the mask takes the bigger bite, so
        // 24 is the curve on screen.
        let button = saveButton(radius: 18, maskRadius: 24)
        let doc = document([button])
        let row = doc.cornerRadiusSelection(layerIDs: [button.id], readingWhatShows: true)
        #expect(row.reading.value == 24)
        #expect(row.floor == 18)
    }

    @Test func aGroupOfSquareThingsStillStartsAtNought() {
        let button = saveButton(radius: 0)
        let doc = document([button])
        let row = doc.cornerRadiusSelection(layerIDs: [button.id], readingWhatShows: true)
        #expect(row.reading.value == 0)
        #expect(row.floor == 0)
    }

    @Test func aPlainRoundedRectangleIsUntouched() {
        let rect = rectangle(CGRect(x: 0, y: 0, width: 40, height: 40), radius: 8)
        let doc = document([rect])
        let row = doc.cornerRadiusSelection(layerIDs: [rect.id], readingWhatShows: true)
        #expect(row.reading.value == 8)
        #expect(row.floor == 0)
    }

    @Test func aPictureIsUntouched() {
        let shot = picture(CGRect(x: 0, y: 0, width: 40, height: 40), styleRadius: 12)
        let doc = document([shot])
        let row = doc.cornerRadiusSelection(layerIDs: [shot.id], readingWhatShows: true)
        #expect(row.reading.value == 12)
        #expect(row.floor == 0)
    }

    @Test func theKnobNeverBlocksTheOtherThingsPicked() {
        // A round-backed group and a plain square box picked together: the box
        // can still be pulled all the way down, so the stop is the lowest one.
        let button = saveButton(radius: 18)
        let rect = rectangle(CGRect(x: 0, y: 0, width: 40, height: 40))
        let doc = document([button, rect])
        let row = doc.cornerRadiusSelection(layerIDs: [button.id, rect.id], readingWhatShows: true)
        #expect(row.floor == 0)
    }

    // MARK: - The release before it reads exactly as it always did

    @Test func theOldRowStillReadsTheGroupsOwnMask() {
        let button = saveButton(radius: 18)
        let doc = document([button])
        #expect(doc.cornerRadiusSelection(layerIDs: [button.id]).reading.value == 0)
        #expect(doc.cornerRadiusSelection(layerIDs: [button.id]).floor == 0)
    }

    // MARK: - What a pull writes

    @Test func pullingPastTheContentsMasksTheGroup() {
        var doc = document([saveButton(radius: 18)])
        let id = doc.layers[0].id
        doc.setCornerRadii(layerIDs: [id], to: CornerRadii(24), onlyWhatShows: true)
        #expect(doc.layer(id: id)?.style.cornerRadii == CornerRadii(24))
    }

    @Test func pullingBackDownToTheContentsTakesTheMaskOffAgain() {
        // A mask that cuts exactly as much as the button's own curve cuts
        // nothing anybody can see, so the group is left carrying none: square
        // the button later and it is square, rather than still clipped to a
        // curve nobody chose.
        var doc = document([saveButton(radius: 18, maskRadius: 24)])
        let id = doc.layers[0].id
        doc.setCornerRadii(layerIDs: [id], to: CornerRadii(18), onlyWhatShows: true)
        #expect(doc.layer(id: id)?.style.cornerRadii == CornerRadii.none)
    }

    @Test func aNumberUnderTheContentsNeverLands() {
        var doc = document([saveButton(radius: 18, maskRadius: 24)])
        let id = doc.layers[0].id
        doc.setCornerRadii(layerIDs: [id], to: CornerRadii(4), onlyWhatShows: true)
        #expect(doc.layer(id: id)?.style.cornerRadii == CornerRadii.none)
    }

    @Test func eachCornerIsHeldToItsOwnFloor() {
        let box = CGRect(x: 0, y: 0, width: 360, height: 120)
        var content = AnnotationContent(shape: .rectangle, strokeWidth: 0,
                                        start: .zero, end: CGPoint(x: 360, y: 120))
        content.cornerRadii = CornerRadii(topLeft: 20, topRight: 20, bottomRight: 0, bottomLeft: 0)
        let tab = Layer(name: "Tab", content: .annotation(content), frame: box)
        var doc = document([group([tab])])
        let id = doc.layers[0].id
        doc.setCornerRadii(layerIDs: [id], to: CornerRadii(10), onlyWhatShows: true)
        // The top two are already rounder than 10, so nothing is written there;
        // the bottom two are square, so 10 lands.
        #expect(doc.layer(id: id)?.style.cornerRadii
            == CornerRadii(topLeft: 0, topRight: 0, bottomRight: 10, bottomLeft: 10))
    }

    @Test func aPlainRectangleWritesExactlyWhatItAlwaysDid() {
        var doc = document([rectangle(CGRect(x: 0, y: 0, width: 40, height: 40))])
        let id = doc.layers[0].id
        doc.setCornerRadii(layerIDs: [id], to: CornerRadii(6), onlyWhatShows: true)
        #expect(doc.layer(id: id)?.roundedCornerRadii == CornerRadii(6))
    }

    @Test func theOldWriteIsUnchanged() {
        var doc = document([saveButton(radius: 18, maskRadius: 24)])
        let id = doc.layers[0].id
        doc.setCornerRadii(layerIDs: [id], to: CornerRadii(4))
        #expect(doc.layer(id: id)?.style.cornerRadii == CornerRadii(4))
    }
}

/// What a pull on a GROUP reaches.
///
/// A group paints nothing of its own, so its own mask can only ever cut a
/// corner off empty space. Pick a group with room around its contents — a
/// button with a caption under it, a stack with padding — and the old row read
/// 0 beside a button that was plainly round, and pulling it changed nothing on
/// the canvas but the dashed selection marquee. The user settled it on
/// 2026-09-13: the row rounds what is INSIDE the group.
///
/// So the row reaches past the group to the things inside it that have corners
/// and paint them, exactly as if those things had been picked. A group somebody
/// already masked by hand keeps its mask; a screen rounds its own surface; a
/// copy of a component is left to its knob.
struct ContainerReachTests {

    private func rectangle(_ frame: CGRect, radius: CGFloat = 0) -> Layer {
        var content = AnnotationContent(shape: .rectangle, strokeWidth: 0, start: .zero,
                                        end: CGPoint(x: frame.width, y: frame.height))
        content.cornerRadius = radius
        return Layer(name: "Rectangle", content: .annotation(content), frame: frame)
    }

    private func label(_ frame: CGRect) -> Layer {
        Layer(name: "Save", content: .text(TextContent(string: "Save")), frame: frame)
    }

    private func group(_ children: [Layer], at origin: CGPoint = .zero,
                       maskRadius: CGFloat = 0, isFrame: Bool = false,
                       size: CGSize = CGSize(width: 360, height: 200)) -> Layer {
        Layer(name: "Group", content: .group(GroupContent(children: children, isFrame: isFrame)),
              frame: CGRect(origin: origin, size: size),
              style: LayerStyle(cornerRadius: CornerRadii(maskRadius)))
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 1440, height: 1024), layers: layers)
    }

    /// The case this was filed from: a button with a caption sitting UNDER it,
    /// so the group's box is taller than the button and its own corners are
    /// empty air.
    private func buttonWithRoomAroundIt(radius: CGFloat = 18,
                                        maskRadius: CGFloat = 0) -> Layer {
        group([rectangle(CGRect(x: 0, y: 0, width: 360, height: 120), radius: radius),
               label(CGRect(x: 0, y: 160, width: 200, height: 33))],
              at: CGPoint(x: 240, y: 180), maskRadius: maskRadius)
    }

    // MARK: - What the pull reaches

    @Test func aPullOnAGroupRoundsTheBoxInsideIt() {
        var doc = document([buttonWithRoomAroundIt()])
        let id = doc.layers[0].id
        let row = doc.cornerRadiusSelection(layerIDs: [id], readingWhatShows: true)
        doc.setCornerRadii(layerIDs: row.layerIDs, to: CornerRadii(24), onlyWhatShows: true)
        let inside = doc.layer(id: id)?.children.first
        #expect(inside?.roundedCornerRadii == CornerRadii(24))
        // ...and the group itself is left carrying no mask, because the mask
        // was never the thing anybody could see.
        #expect(doc.layer(id: id)?.style.cornerRadii == CornerRadii.none)
    }

    @Test func theRowReadsTheBoxInsideAGroupWithRoomAroundIt() {
        let button = buttonWithRoomAroundIt(radius: 18)
        let row = document([button]).cornerRadiusSelection(layerIDs: [button.id],
                                                           readingWhatShows: true)
        #expect(row.reading.value == 18)
        #expect(row.reachesContents)
    }

    @Test func theRowSaysHowManyThingsItReachedInto() {
        let button = buttonWithRoomAroundIt()
        let row = document([button]).cornerRadiusSelection(layerIDs: [button.id],
                                                           readingWhatShows: true)
        #expect(row.reachedIntoContainers == 1)
        #expect(row.count == 1)
    }

    @Test func aGroupWhoseContentsFillItIsReachedTheSameWay() {
        // The half that shipped on 2026-09-12: the row still reads 18, which is
        // the curve on screen. What changed is that it reaches the button
        // rather than masking the group, so the pull can go DOWN as well as up.
        let button = group([rectangle(CGRect(x: 0, y: 0, width: 360, height: 120), radius: 18),
                            label(CGRect(x: 60, y: 40, width: 48, height: 33))],
                           size: CGSize(width: 360, height: 120))
        let row = document([button]).cornerRadiusSelection(layerIDs: [button.id],
                                                           readingWhatShows: true)
        #expect(row.reading.value == 18)
        #expect(row.floor == 0)
    }

    @Test func pullingAGroupAllTheWayDownSquaresWhatIsInsideIt() {
        var doc = document([buttonWithRoomAroundIt(radius: 18)])
        let id = doc.layers[0].id
        let row = doc.cornerRadiusSelection(layerIDs: [id], readingWhatShows: true)
        #expect(row.floor == 0)
        doc.setCornerRadii(layerIDs: row.layerIDs, to: .none, onlyWhatShows: true)
        #expect(doc.layer(id: id)?.children.first?.roundedCornerRadii == CornerRadii.none)
    }

    @Test func theWordsInAGroupAreLeftAlone() {
        var doc = document([buttonWithRoomAroundIt()])
        let id = doc.layers[0].id
        let row = doc.cornerRadiusSelection(layerIDs: [id], readingWhatShows: true)
        doc.setCornerRadii(layerIDs: row.layerIDs, to: CornerRadii(24), onlyWhatShows: true)
        // A label paints nothing at its own corners, so rounding it would write
        // a number that changes no pixel.
        #expect(doc.layer(id: id)?.children.last?.style.cornerRadii == CornerRadii.none)
    }

    @Test func theKnobStopsWhereTheThingItRoundsIsFullyRound() {
        // The group's box is 360 by 200, the button inside it 360 by 120. The
        // knob runs to the BUTTON's fully round, not the group's, so there is
        // no stretch of track past the point where anything can change.
        let button = buttonWithRoomAroundIt()
        let row = document([button]).cornerRadiusSelection(layerIDs: [button.id],
                                                           readingWhatShows: true)
        #expect(row.limit == 60)
    }

    @Test func aGroupInsideAGroupIsReachedAllTheWayDown() {
        let inner = group([rectangle(CGRect(x: 0, y: 0, width: 100, height: 40), radius: 6)],
                          size: CGSize(width: 100, height: 40))
        var doc = document([group([inner], size: CGSize(width: 200, height: 80))])
        let outer = doc.layers[0].id
        let row = doc.cornerRadiusSelection(layerIDs: [outer], readingWhatShows: true)
        #expect(row.reading.value == 6)
        doc.setCornerRadii(layerIDs: row.layerIDs, to: CornerRadii(12), onlyWhatShows: true)
        #expect(doc.layer(id: outer)?.children.first?.children.first?.roundedCornerRadii
            == CornerRadii(12))
    }

    @Test func twoBoxesInOneGroupRoundTogether() {
        let a = rectangle(CGRect(x: 0, y: 0, width: 100, height: 40), radius: 4)
        let b = rectangle(CGRect(x: 120, y: 0, width: 100, height: 40), radius: 4)
        var doc = document([group([a, b], size: CGSize(width: 220, height: 40))])
        let id = doc.layers[0].id
        let row = doc.cornerRadiusSelection(layerIDs: [id], readingWhatShows: true)
        #expect(row.count == 2)
        doc.setCornerRadii(layerIDs: row.layerIDs, to: CornerRadii(10), onlyWhatShows: true)
        #expect(doc.layer(id: id)?.children.map(\.roundedCornerRadii)
            == [CornerRadii(10), CornerRadii(10)])
    }

    @Test func twoBoxesRoundedApartReadAsMixed() {
        let a = rectangle(CGRect(x: 0, y: 0, width: 100, height: 40), radius: 4)
        let b = rectangle(CGRect(x: 120, y: 0, width: 100, height: 40), radius: 12)
        let g = group([a, b], size: CGSize(width: 220, height: 40))
        let row = document([g]).cornerRadiusSelection(layerIDs: [g.id], readingWhatShows: true)
        #expect(row.reading.isMixed)
    }

    @Test func aHiddenBoxInsideIsNotReached() {
        var hidden = rectangle(CGRect(x: 0, y: 0, width: 360, height: 120), radius: 18)
        hidden.isVisible = false
        let g = group([hidden, label(CGRect(x: 0, y: 160, width: 200, height: 33))])
        let row = document([g]).cornerRadiusSelection(layerIDs: [g.id], readingWhatShows: true)
        // Nothing inside it can show a curve, so the row goes back to the
        // group's own mask rather than rounding something nobody can see.
        #expect(!row.reachesContents)
    }

    @Test func aLockedBoxInsideIsNotReached() {
        var locked = rectangle(CGRect(x: 0, y: 0, width: 360, height: 120), radius: 18)
        locked.isLocked = true
        let g = group([locked, label(CGRect(x: 0, y: 160, width: 200, height: 33))])
        let row = document([g]).cornerRadiusSelection(layerIDs: [g.id], readingWhatShows: true)
        #expect(!row.reachesContents)
    }

    @Test func nothingPaintedInsideLeavesTheGroupRoundingItself() {
        let g = group([label(CGRect(x: 0, y: 0, width: 100, height: 40)),
                       label(CGRect(x: 0, y: 60, width: 100, height: 40))])
        let row = document([g]).cornerRadiusSelection(layerIDs: [g.id], readingWhatShows: true)
        #expect(!row.reachesContents)
        #expect(row.layerIDs == [g.id])
    }

    // MARK: - What the pull does NOT reach

    @Test func aGroupSomebodyAlreadyMaskedKeepsItsMask() {
        // A mask can only have got there by being asked for, so it is not taken
        // away underneath somebody. The row goes on meaning the mask until it
        // is pulled back off.
        let button = buttonWithRoomAroundIt(radius: 18, maskRadius: 24)
        let row = document([button]).cornerRadiusSelection(layerIDs: [button.id],
                                                           readingWhatShows: true)
        #expect(!row.reachesContents)
        #expect(row.layerIDs == [button.id])
        #expect(row.reading.value == 24)
    }

    @Test func aScreenRoundsItsOwnSurface() {
        // A frame has a box and a background of its own, so its corners are
        // painted and rounding them is visible. Nothing to reach through.
        let screen = group([rectangle(CGRect(x: 20, y: 20, width: 100, height: 40), radius: 6)],
                           isFrame: true)
        let row = document([screen]).cornerRadiusSelection(layerIDs: [screen.id],
                                                           readingWhatShows: true)
        #expect(!row.reachesContents)
        #expect(row.layerIDs == [screen.id])
    }

    @Test func aPlainRoundedRectangleIsUntouched() {
        let rect = rectangle(CGRect(x: 0, y: 0, width: 40, height: 40), radius: 8)
        let row = document([rect]).cornerRadiusSelection(layerIDs: [rect.id],
                                                         readingWhatShows: true)
        #expect(!row.reachesContents)
        #expect(row.reading.value == 8)
        #expect(row.floor == 0)
    }

    @Test func theReleaseBeforeItReachesNothing() {
        let button = buttonWithRoomAroundIt(radius: 18)
        let row = document([button]).cornerRadiusSelection(layerIDs: [button.id])
        #expect(!row.reachesContents)
        #expect(row.reading.value == 0)
    }
}
