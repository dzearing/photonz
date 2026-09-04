import CoreGraphics
import Foundation
import PhotonzCore
import Testing

private let boxFrame = CGRect(x: 100, y: 100, width: 200, height: 120)

private func box(transform: LayerTransform = .identity, locked: Bool = false) -> Layer {
    Layer(name: "Shot", content: .image(ImageRef(pixelSize: CGSize(width: 200, height: 120))),
          frame: boxFrame, transform: transform, isLocked: locked)
}

private func arrow(from start: CGPoint = CGPoint(x: 300, y: 300),
                   to end: CGPoint = CGPoint(x: 460, y: 300),
                   caption: String? = nil) -> Layer {
    var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
    content.caption = caption
    return AnnotationBuilder.layer(content: content, from: start, to: end)
}

private func caliper() -> Layer {
    MeasureBuilder.layer(content: MeasureContent(mode: .horizontal),
                         from: CGPoint(x: 200, y: 400), to: CGPoint(x: 380, y: 400))
}

private func cue(_ p: CGPoint, _ layer: Layer, zoom: CGFloat = 1,
                 captionsEnabled: Bool = true, offersRotation: Bool = true) -> CanvasPointerCue? {
    CanvasPointer.cue(at: p, layer: layer, frame: layer.frame, zoom: zoom,
                      captionsEnabled: captionsEnabled, offersRotation: offersRotation)
}

@Suite("Pointer cue for every handle on the canvas")
struct CanvasPointerCueTests {

    // MARK: The eight frame handles

    @Test func everyFrameHandleReadsAsItsOwnResize() {
        let layer = box()
        for handle in ResizeHandle.allCases {
            let p = Handles.point(for: handle, in: boxFrame)
            #expect(cue(p, layer) == .resize(handle), "\(handle)")
        }
    }

    @Test func insideTheFrameIsNoCueAtAll() {
        #expect(cue(CGPoint(x: boxFrame.midX, y: boxFrame.midY), box()) == nil)
    }

    @Test func wellOutsideTheFrameIsNoCue() {
        #expect(cue(CGPoint(x: 600, y: 600), box()) == nil)
    }

    @Test func aHandleIsOnlyReachableWithinItsSlop() {
        let layer = box()
        let justOff = CGPoint(x: boxFrame.minX - 5, y: boxFrame.minY)
        #expect(cue(justOff, layer) == .resize(.topLeft))
        // The same spot zoomed in is five SCREEN points further away, so it
        // falls outside the 6pt slop and stops promising a resize.
        #expect(cue(justOff, layer, zoom: 4) == nil)
    }

    @Test func anObjectThatDoesNotResizeOffersNoResizeCue() {
        // A line edits by its ends; it never grows the eight frame handles, so
        // the pointer must not offer one at its frame corner.
        let line = arrow(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 220))
        #expect(line.allowsFrameResize == false)
        #expect(cue(CGPoint(x: line.frame.midX, y: line.frame.minY), line,
                    offersRotation: false) == nil)
    }

    // MARK: Endpoint handles

    @Test func eitherEndOfAnArrowReadsAsAGrab() {
        let layer = arrow()
        #expect(cue(CGPoint(x: 300, y: 300), layer, offersRotation: false) == .grab)
        #expect(cue(CGPoint(x: 460, y: 300), layer, offersRotation: false) == .grab)
    }

    @Test func theMiddleOfAnArrowIsNoCue() {
        #expect(cue(CGPoint(x: 380, y: 300), arrow(), offersRotation: false) == nil)
    }

    @Test func anEndpointBeatsTheCaptionPillWhereTheyOverlap() {
        // Short arrow: the pill sits over the tail handle, and the press gives
        // the handle priority. Both read as a grab, so the point of the test is
        // that the tail still answers at all.
        let layer = arrow(from: CGPoint(x: 300, y: 300), to: CGPoint(x: 340, y: 300),
                          caption: "Save button")
        #expect(cue(CGPoint(x: 300, y: 300), layer, offersRotation: false) == .grab)
    }

    // MARK: The grabs that already worked keep working

    @Test func aCaliperFootStillReadsAsAGrab() {
        #expect(cue(CGPoint(x: 200, y: 400), caliper(), offersRotation: false) == .grab)
    }

    @Test func aCaptionPillStillReadsAsAGrab() {
        let layer = arrow(caption: "Save button")
        let pill = try! #require(CanvasGrab.captionPillRect(of: layer))
        #expect(cue(CGPoint(x: pill.midX, y: pill.midY), layer, offersRotation: false) == .grab)
        #expect(cue(CGPoint(x: pill.midX, y: pill.midY), layer,
                    captionsEnabled: false, offersRotation: false) == nil)
    }

    // MARK: The rotate knob

    @Test func theRotateKnobReadsAsRotate() {
        let layer = box()
        let knob = try! #require(layer.rotateKnobPoint(zoom: 1))
        #expect(cue(knob, layer) == .rotate)
    }

    @Test func theKnobFloatsAboveTheTopEdgeNotOnIt() {
        let layer = box()
        let knob = try! #require(layer.rotateKnobPoint(zoom: 1))
        #expect(knob.x == boxFrame.midX)
        #expect(knob.y == boxFrame.minY - 18)
    }

    @Test func noKnobCueOnSomethingThatDoesNotTurn() {
        let layer = box()
        let knob = try! #require(layer.rotateKnobPoint(zoom: 1))
        #expect(cue(knob, layer, offersRotation: false) == nil)
    }

    @Test func theKnobIsOnlyReachableWithinItsSlop() {
        let layer = box()
        let knob = try! #require(layer.rotateKnobPoint(zoom: 1))
        #expect(cue(CGPoint(x: knob.x + 7, y: knob.y), layer) == .rotate)
        #expect(cue(CGPoint(x: knob.x + 10, y: knob.y), layer) == nil)
    }

    @Test func theKnobStaysTheSameSizeOnScreenAtEveryZoom() {
        let layer = box()
        // 18 SCREEN points off the edge, so zoomed out it floats further away
        // in document units and stays exactly as far from the edge on screen.
        let knob = try! #require(layer.rotateKnobPoint(zoom: 0.5))
        #expect(knob.y == boxFrame.minY - 36)
        #expect(cue(knob, layer, zoom: 0.5) == .rotate)
    }

    // MARK: A turned layer points where its handles actually sit

    @Test func aQuarterTurnMovesEachHandlesArrowsRoundWithIt() {
        let turned = LayerTransform(rotation: .pi / 2)
        #expect(Handles.screenHandle(for: .top, transform: turned) == .right)
        #expect(Handles.screenHandle(for: .right, transform: turned) == .bottom)
        #expect(Handles.screenHandle(for: .topLeft, transform: turned) == .topRight)
        #expect(Handles.screenHandle(for: .bottomRight, transform: turned) == .bottomLeft)
    }

    @Test func anUnturnedLayerKeepsEveryHandleAsItIs() {
        for handle in ResizeHandle.allCases {
            #expect(Handles.screenHandle(for: handle, transform: .identity) == handle)
        }
    }

    @Test func aSmallTiltRoundsToTheHandleItStillLooksLike() {
        // 10° is not enough to make the top handle look like anything else.
        let tilted = LayerTransform(rotation: .pi / 18)
        #expect(Handles.screenHandle(for: .top, transform: tilted) == .top)
        // 30° is past halfway to the diagonal, so it now reads as a corner.
        let more = LayerTransform(rotation: .pi / 6)
        #expect(Handles.screenHandle(for: .top, transform: more) == .topRight)
    }

    @Test func oppositeHandlesShareOnePointer() {
        // The platform draws four resize pointers, not eight: the top and the
        // bottom handle wear the same up-and-down arrows. Naming them by the
        // handle would claim a difference nobody can see.
        for handle in ResizeHandle.allCases {
            #expect(handle.axis == handle.opposite.axis, "\(handle)")
        }
        #expect(Set(ResizeHandle.allCases.map(\.axis)).count == 4)
        #expect(ResizeHandle.topLeft.axis.rawValue == "up-left-down-right")
    }

    @Test func aMirroredLayerSwapsItsSides() {
        let flipped = LayerTransform(flipHorizontal: true)
        #expect(Handles.screenHandle(for: .left, transform: flipped) == .right)
        #expect(Handles.screenHandle(for: .topLeft, transform: flipped) == .topRight)
        #expect(Handles.screenHandle(for: .top, transform: flipped) == .top)
    }

    @Test func aTurnedLayersHandleIsFoundWhereItIsDrawn() {
        // The handle is hit-tested in the layer's own untransformed space, so
        // the cue has to look for the pointer there too — otherwise a turned
        // layer's handles answer in the wrong places.
        let layer = box(transform: LayerTransform(rotation: .pi / 2))
        let center = CGPoint(x: boxFrame.midX, y: boxFrame.midY)
        let drawn = Handles.point(for: .topLeft, in: boxFrame)
            .applying(layer.transform.affineTransform(around: center))
        #expect(cue(drawn, layer) == .resize(.topLeft))
    }

    // MARK: The crop box's own eight handles

    @Test func everyCropHandleReadsAsItsOwnResize() {
        let rect = CGRect(x: 40, y: 60, width: 300, height: 200)
        for handle in ResizeHandle.allCases {
            let p = Handles.point(for: handle, in: rect)
            #expect(CanvasPointer.cropCue(at: p, cropRect: rect, zoom: 1) == .resize(handle),
                    "\(handle)")
        }
    }

    @Test func insideTheCropBoxKeepsTheCropCrosshair() {
        // A press inside the box moves it, but the crosshair already says the
        // Crop tool is drawing and dragging. Nil hands the pointer back to it.
        let rect = CGRect(x: 40, y: 60, width: 300, height: 200)
        #expect(CanvasPointer.cropCue(at: CGPoint(x: rect.midX, y: rect.midY),
                                      cropRect: rect, zoom: 1) == nil)
    }

    @Test func outsideTheCropBoxKeepsTheCropCrosshair() {
        let rect = CGRect(x: 40, y: 60, width: 300, height: 200)
        #expect(CanvasPointer.cropCue(at: CGPoint(x: 800, y: 800),
                                      cropRect: rect, zoom: 1) == nil)
    }

    @Test func aCropHandleIsReachableWithinTheSameSlopThePressUses() {
        // The crop press finds a handle up to eight SCREEN points away, wider
        // than a layer's six, so the cue has to be just as generous or it
        // would go quiet on presses that do resize.
        let rect = CGRect(x: 40, y: 60, width: 300, height: 200)
        let justOff = CGPoint(x: rect.minX - 7, y: rect.minY)
        #expect(CanvasPointer.cropCue(at: justOff, cropRect: rect, zoom: 1) == .resize(.topLeft))
        // Zoomed in, the same document point is 28 screen points out: past the
        // slop, so it stops promising a resize.
        #expect(CanvasPointer.cropCue(at: justOff, cropRect: rect, zoom: 4) == nil)
    }

    @Test func noCropRectMeansNoCropCue() {
        #expect(CanvasPointer.cropCue(at: CGPoint(x: 40, y: 60), cropRect: nil, zoom: 1) == nil)
    }

    // MARK: Locked layers behave as the press does

    @Test func aLockedLayerCuesNothingBecauseItReshapesFromNothing() {
        // A locked layer draws no handles and no knob, and a press where one
        // used to be does nothing. The pointer says so: a plain arrow every-
        // where over it, the same answer the chrome and the press give.
        let layer = box(locked: true)
        for handle in ResizeHandle.allCases {
            #expect(cue(Handles.point(for: handle, in: boxFrame), layer) == nil, "\(handle)")
        }
        if let knob = layer.rotateKnobPoint(zoom: 1) {
            #expect(cue(knob, layer) == nil)
        }
        #expect(cue(CGPoint(x: boxFrame.midX, y: boxFrame.midY), layer) == nil)
    }

    @Test func aLockedArrowCuesNeitherItsEndsNorItsCaption() {
        var locked = arrow(caption: "Save")
        locked.isLocked = true
        #expect(cue(CGPoint(x: 300, y: 300), locked) == nil)
        #expect(cue(CGPoint(x: 460, y: 300), locked) == nil)
        if let pill = CanvasGrab.captionPillRect(of: locked) {
            #expect(cue(CGPoint(x: pill.midX, y: pill.midY), locked) == nil)
        }
    }

    @Test func aLockedCaliperCuesNoneOfItsThreeHandles() {
        var locked = caliper()
        locked.isLocked = true
        guard let m = MeasureBuilder.documentSpaceContent(of: locked) else { return }
        let g = m.caliperGeometry()
        for dot in [g.footA, g.footB, m.headHandle] {
            #expect(cue(dot, locked) == nil)
        }
    }

    @Test func lockingIsWhatSilencesIt() {
        // The unlocked twin still answers, so the tests above are measuring the
        // lock and not a point that was never a handle.
        #expect(cue(Handles.point(for: .topLeft, in: boxFrame), box()) == .resize(.topLeft))
    }
}
