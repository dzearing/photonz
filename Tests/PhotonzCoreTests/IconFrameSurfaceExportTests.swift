import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// An icon drawn in an icon frame, handed to somebody else.
///
/// A new frame paints white so that a screen you cannot see is a screen you can
/// build on. On an icon that white is the artboard, not the icon: nobody drew
/// it, and written into the file it is a white box on every page that is not
/// white. A colour somebody gave the frame is theirs and stays, and a screen
/// keeps its surface because a screen's surface is part of the screen.
@Suite("An icon frame's white stays out of what it exports")
struct IconFrameSurfaceExportTests {

    static func circle(at origin: CGPoint = CGPoint(x: 4, y: 4),
                       side: CGFloat = 16) -> Layer {
        var content = AnnotationContent(shape: .ellipse)
        content.fillColorHex = "#FF3B30"
        content.strokeWidth = 0
        return Layer(name: "Circle", content: .annotation(content),
                     frame: CGRect(origin: origin, size: CGSize(width: side, height: side)))
    }

    /// A phone screen, the shape a screen frame really is: a square up to the
    /// largest icon side is an icon by the app's own rule.
    static func screen(hex: String? = Layer.defaultFrameBackgroundHex,
                       children: [Layer]? = nil) -> Layer {
        Layer.frameLayer(name: "Screen", origin: .zero, size: CGSize(width: 390, height: 844),
                         children: children ?? [circle()], backgroundHex: hex)
    }

    static func frame(side: CGFloat = 24, hex: String? = Layer.defaultFrameBackgroundHex,
                      at origin: CGPoint = .zero, children: [Layer]? = nil) -> Layer {
        Layer.frameLayer(name: "Frame", origin: origin, size: CGSize(width: side, height: side),
                         children: children ?? [circle()], backgroundHex: hex)
    }

    /// The frame on its own, exactly as Export scopes a picked frame.
    static func scoped(_ frame: Layer) throws -> PhotonzDocument {
        let whole = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: [frame])
        return try #require(whole.frameDocument(id: frame.id))
    }

    static func rects(_ svg: String) -> Int { svg.components(separatedBy: "<rect").count - 1 }

    // MARK: The white nobody drew

    @Test func aNewIconFramesWhiteIsNotInTheFile() throws {
        let svg = SVGExport.write(try Self.scoped(Self.frame()), background: .drop).text
        #expect(!svg.contains("#FFFFFF"))
        #expect(Self.rects(svg) == 0)
        #expect(svg.contains("#FF3B30"))
    }

    @Test func nothingIsLeftToCutOnceEverythingSitsInsideTheFrame() throws {
        let svg = SVGExport.write(try Self.scoped(Self.frame()), background: .drop).text
        #expect(!svg.contains("clipPath"))
        #expect(!svg.contains("clip-path"))
    }

    @Test func aShapeHangingOffTheFrameIsStillCutAtItsEdge() throws {
        let hanging = Self.frame(children: [Self.circle(at: CGPoint(x: 16, y: 4))])
        let svg = SVGExport.write(try Self.scoped(hanging), background: .drop).text
        #expect(svg.contains("clip-path"))
        #expect(!svg.contains("#FFFFFF"))
    }

    @Test func aStrokeReachingPastTheEdgeIsStillCutAtIt() throws {
        // A path's line sits on its outline, so half of it lies past a box
        // the outline fills.
        let square = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            PathAnchor(point: CGPoint(x: 24, y: 0)),
            PathAnchor(point: CGPoint(x: 24, y: 24)),
            PathAnchor(point: CGPoint(x: 0, y: 24))
        ], isClosed: true, paint: Paint(hex: "#112233"), strokeWidth: 6)
        let ring = Layer(name: "Ring", content: .path(square),
                         frame: CGRect(x: 0, y: 0, width: 24, height: 24))
        let svg = SVGExport.write(try Self.scoped(Self.frame(children: [ring])),
                                  background: .drop).text
        #expect(svg.contains("clip-path"))
    }

    @Test func askingToKeepItWritesTheWhite() throws {
        let svg = SVGExport.write(try Self.scoped(Self.frame()), background: .keep).text
        #expect(svg.contains("#FFFFFF"))
    }

    @Test func theSheetIsToldThereIsSomethingToLeaveOut() throws {
        let frame = Self.frame()
        let found = try #require(SVGExport.backdrop(in: try Self.scoped(frame), flatImages: [:]))
        #expect(found.layerID == frame.id)
        #expect(found.isFrameSurface)
        #expect(!found.isChosen)
        #expect(found.color == RGBA(r: 1, g: 1, b: 1, a: 1))
    }

    @Test func aMovingIconLosesTheWhiteToo() throws {
        var dot = Self.circle()
        dot.motions = [Self.drift(by: 2)]
        let scoped = try Self.scoped(Self.frame(children: [dot]))
        let svg = SVGExport.write(scoped, animation: .moving(cycleMS: 1000), background: .drop).text
        #expect(svg.contains("<animate"))
        #expect(Self.rects(svg) == 0)
        #expect(!svg.contains("clip-path"))
    }

    @Test func aShapeThatMovesOffTheFrameIsStillCutAtItsEdge() throws {
        var dot = Self.circle()
        dot.motions = [Self.drift(by: 40)]
        let scoped = try Self.scoped(Self.frame(children: [dot]))
        let svg = SVGExport.write(scoped, animation: .moving(cycleMS: 1000), background: .drop).text
        #expect(svg.contains("clip-path"))
        #expect(!svg.contains("#FFFFFF"))
    }

    /// `dot` swinging ±`degrees` for ever, about `point` in its parent's space.
    static func swing(_ dot: Layer, about point: CGPoint, degrees: Double) -> LayerMotion {
        LayerMotion(property: .rotation, from: .number(-degrees), to: .number(degrees),
                    timing: MotionTiming(startMS: 0, durationMS: 1000),
                    curve: .linear, repeats: .foreverThereAndBack,
                    pivot: MotionPivot(at: point, in: dot.frame))
    }

    @Test func aShapeSwungOutOfTheFrameByAFarPivotIsStillCut() throws {
        // Turned about its own middle this dot stays put. About a point down
        // in the far corner it swings clean out of the frame.
        var dot = Self.circle(at: CGPoint(x: 10, y: 2), side: 4)
        dot.motions = [Self.swing(dot, about: CGPoint(x: 12, y: 40), degrees: 40)]
        let scoped = try Self.scoped(Self.frame(children: [dot]))
        let svg = SVGExport.write(scoped, animation: .moving(cycleMS: 2000), background: .drop).text
        #expect(svg.contains("clip-path"))
    }

    @Test func aShapeSwingingInsideTheFrameAboutItsMountIsNotCut() throws {
        // Hung from the middle of the frame's top, a bell's own swing. It would
        // read as leaving the frame if it were turned about its own middle.
        var bell = Self.circle(at: CGPoint(x: 6, y: 4), side: 12)
        bell.motions = [Self.swing(bell, about: CGPoint(x: 12, y: 4), degrees: 12)]
        let scoped = try Self.scoped(Self.frame(children: [bell]))
        let svg = SVGExport.write(scoped, animation: .moving(cycleMS: 2000), background: .drop).text
        #expect(!svg.contains("clip-path"))
    }

    /// Slides `distance` to the right of where `circle()` sits, for ever.
    static func drift(by distance: CGFloat) -> LayerMotion {
        LayerMotion(property: .position, from: .point(CGPoint(x: 4, y: 4)),
                    to: .point(CGPoint(x: 4 + distance, y: 4)),
                    timing: MotionTiming(startMS: 0, durationMS: 1000),
                    curve: .linear, repeats: .forever)
    }

    // MARK: A colour somebody gave it

    @Test func aColourSomebodyChoseStaysInTheFile() throws {
        let scoped = try Self.scoped(Self.frame(hex: "#3B82F6"))
        let svg = SVGExport.write(scoped, background: .drop).text
        #expect(svg.contains("#3B82F6"))
        #expect(svg.contains("clip-path"))
        let found = try #require(SVGExport.backdrop(in: scoped, flatImages: [:]))
        #expect(found.isChosen)
    }

    @Test func unTickingTheBoxLeavesEvenAChosenColourOut() throws {
        let scoped = try Self.scoped(Self.frame(hex: "#3B82F6"))
        let svg = SVGExport.write(scoped, background: .dropChosen).text
        #expect(!svg.contains("#3B82F6"))
        #expect(svg.contains("#FF3B30"))
    }

    @Test func aFrameSomebodyStyledIsTheirsEvenInWhite() throws {
        var rounded = Self.frame()
        rounded.style.cornerRadii = CornerRadii(6)
        let scoped = try Self.scoped(rounded)
        #expect(SVGExport.write(scoped, background: .drop).text.contains("#FFFFFF"))
        #expect(SVGExport.backdrop(in: scoped, flatImages: [:])?.isChosen == true)
    }

    @Test func aFrameYouSeeStraightThroughHasNothingToAskAbout() throws {
        let scoped = try Self.scoped(Self.frame(hex: nil))
        #expect(SVGExport.backdrop(in: scoped, flatImages: [:]) == nil)
    }

    // MARK: A screen

    @Test func aScreenWritesExactlyWhatItAlwaysDid() throws {
        let scoped = try Self.scoped(Self.screen())
        let kept = SVGExport.write(scoped, background: .keep).text
        #expect(kept.contains("#FFFFFF"))
        #expect(SVGExport.write(scoped, background: .drop).text == kept)
        #expect(SVGExport.write(scoped, background: .dropChosen).text == kept)
        #expect(SVGExport.backdrop(in: scoped, flatImages: [:]) == nil)
    }

    @Test func aRectangularFrameIsAScreenHoweverSmall() throws {
        let wide = Layer.frameLayer(name: "Wide", origin: .zero,
                                    size: CGSize(width: 48, height: 24),
                                    children: [Self.circle()])
        let scoped = try Self.scoped(wide)
        #expect(SVGExport.write(scoped, background: .drop).text.contains("#FFFFFF"))
    }

    // MARK: The whole drawing

    /// A white canvas with `layers` on it, as New Canvas leaves one.
    static func onACanvas(_ layers: [Layer]) -> (document: PhotonzDocument, flat: [UUID: RGBA]) {
        let ref = ImageRef(pixelSize: CGSize(width: 400, height: 300))
        var document = PhotonzDocument.withBaseImage(ref)
        document.canvasSize = CGSize(width: 400, height: 300)
        document.layers.append(contentsOf: layers)
        return (document, [ref.id: RGBA(r: 1, g: 1, b: 1, a: 1)])
    }

    @Test func theWholeDrawingLeavesTheCanvasAndTheFramesWhiteOut() {
        let (document, flat) = Self.onACanvas([Self.frame(at: CGPoint(x: 40, y: 40))])
        let svg = SVGExport.write(document, flatImages: flat, background: .drop).text
        #expect(Self.rects(svg) == 0)
        #expect(svg.contains("#FF3B30"))
    }

    @Test func anIconInsideAScreenKeepsItsPlaceOnTheScreen() {
        let icon = Self.frame(hex: Layer.defaultFrameBackgroundHex, at: CGPoint(x: 20, y: 20))
        let screen = Self.screen(hex: "#112233", children: [icon])
        let (document, flat) = Self.onACanvas([screen])
        let svg = SVGExport.write(document, flatImages: flat, background: .drop).text
        #expect(svg.contains("#FFFFFF"))
    }

    // MARK: The same answer for a picture

    @Test func aPictureLosesTheSameWhite() throws {
        let frame = Self.frame()
        let dropped = try Self.scoped(frame).drawn(with: .drop, flatImages: [:])
        let drawn = try #require(dropped.layer(id: frame.id))
        #expect(drawn.isVisible)
        #expect(drawn.group?.background == nil)
        #expect(drawn.children.count == 1)
    }

    @Test func aPictureKeepsAChosenColourUntilTheBoxIsUnticked() throws {
        let frame = Self.frame(hex: "#3B82F6")
        let scoped = try Self.scoped(frame)
        #expect(scoped.drawn(with: .drop, flatImages: [:]) == scoped)
        let dropped = scoped.drawn(with: .dropChosen, flatImages: [:])
        #expect(dropped.layer(id: frame.id)?.group?.background == nil)
    }

    @Test func aScreenPictureIsUntouched() throws {
        let scoped = try Self.scoped(Self.screen())
        #expect(scoped.drawn(with: .dropChosen, flatImages: [:]) == scoped)
    }
}
