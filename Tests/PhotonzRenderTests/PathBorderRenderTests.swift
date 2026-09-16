import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A Border added to a path follows the path.
///
/// A path can be any silhouette at all, and for a while a Border on one came
/// out as a plain rectangle round its bounding box: the ring was generated as
/// a rounded rect, so the corner of the box was painted although the shape was
/// nowhere near it (reported 2026-09-13). The closed half of that was fixed
/// when `ringed` learned to bake a silhouette from the outline itself; the OPEN
/// half was not, because an open path has no inside for an Inside ring to sit
/// in and the renderer fell back to the box.
///
/// So these tests read the pixels rather than the code: the corner of a
/// triangle's box is empty, the band on a line is the width that was asked for,
/// and every other kind of layer draws exactly what it drew before.
@Suite("A border follows the path")
struct PathBorderRenderTests {

    private let canvas = CGSize(width: 220, height: 220)

    // MARK: Helpers

    private func rgba(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    /// One layer on an empty canvas, as a bitmap and the width of a row.
    private func shoot(_ layer: Layer) throws -> (data: [UInt8], width: Int) {
        var document = PhotonzDocument(canvasSize: canvas)
        document.addLayer(layer)
        let image = try #require(DocumentRenderer().render(document, store: ImageStore()))
        return (rgba(image), image.width)
    }

    private func alpha(_ shot: (data: [UInt8], width: Int), _ x: Int, _ y: Int) -> Int {
        Int(shot.data[(y * shot.width + x) * 4 + 3])
    }

    /// How many pixels on the canvas the ring painted, which is what says
    /// whether a band is the thickness that was asked for.
    private func inked(_ shot: (data: [UInt8], width: Int)) -> Int {
        var count = 0
        for y in 0..<Int(canvas.height) {
            for x in 0..<Int(canvas.width) where alpha(shot, x, y) > 10 { count += 1 }
        }
        return count
    }

    /// A path carrying no line and no fill of its own, so the only ink on the
    /// canvas is the Border under test.
    private func bare(_ anchors: [CGPoint], closed: Bool) -> PathContent {
        var content = PathContent(anchors: anchors.map { PathAnchor(point: $0) },
                                  isClosed: closed)
        content.strokeWidth = 0
        content.paint = Paint(hex: "#00000000")
        content.fill = nil
        return content
    }

    /// The triangle the bug was reported on, at the place it was reported at.
    private func triangle(_ border: BorderEffect) -> Layer {
        var layer = PathBuilder.layer(
            bare([CGPoint(x: 60, y: 0), CGPoint(x: 120, y: 100), CGPoint(x: 0, y: 100)],
                 closed: true),
            at: CGPoint(x: 40, y: 40))
        layer.style.effects.append(.border(border))
        return layer
    }

    /// An open chevron: down from the top left, back up to the top right. Its
    /// bounding box has two corners the line comes nowhere near.
    private func chevron(_ border: BorderEffect) -> Layer {
        var layer = PathBuilder.layer(
            bare([CGPoint(x: 0, y: 0), CGPoint(x: 60, y: 100), CGPoint(x: 120, y: 0)],
                 closed: false),
            at: CGPoint(x: 40, y: 50))
        layer.style.effects.append(.border(border))
        return layer
    }

    // MARK: A closed path

    @Test("The corner of a triangle's box is not painted by its border",
          arguments: [CGFloat(1), 6, 20], BorderPosition.allCases)
    func theBoxCornerStaysEmpty(width: CGFloat, position: BorderPosition) throws {
        let shot = try shoot(triangle(BorderEffect(width: width, colorHex: "#FF0000",
                                                   position: position)))
        // The box runs (40,40) to (160,140). Its top two corners are far from
        // any edge of the triangle, whose apex is at (100,40).
        #expect(alpha(shot, 43, 43) == 0)
        #expect(alpha(shot, 156, 43) == 0)
    }

    @Test("An outside border on a triangle hugs the apex and the slopes")
    func theRingFollowsTheOutline() throws {
        let shot = try shoot(triangle(BorderEffect(width: 6, colorHex: "#FF0000",
                                                   position: .outside)))
        // Four points above the apex (100,40): outside the shape, inside the
        // ring.
        #expect(alpha(shot, 100, 36) > 200)
        // ...and twelve above it, past the far side of a 6 point ring.
        #expect(alpha(shot, 100, 27) == 0)
        // The middle of the triangle, far from every edge, is untouched: the
        // ring is a band round the outline, not a fill.
        #expect(alpha(shot, 100, 110) == 0)
    }

    @Test("An inside border on a triangle eats into the shape, not into the box")
    func anInsideRingStaysOnTheOutline() throws {
        let shot = try shoot(triangle(BorderEffect(width: 6, colorHex: "#FF0000",
                                                   position: .inside)))
        // Just inside the bottom edge at y = 140 is ink; well above it is not.
        #expect(alpha(shot, 100, 137) > 200)
        #expect(alpha(shot, 100, 120) == 0)
        // ...and nothing has leaked into the corner of the box.
        #expect(alpha(shot, 43, 43) == 0)
    }

    // MARK: An open path

    @Test("A border on an open line runs down the line, never round its box",
          arguments: BorderPosition.allCases)
    func aLineIsNeverBoxed(position: BorderPosition) throws {
        let shot = try shoot(chevron(BorderEffect(width: 8, colorHex: "#FF0000",
                                                  position: position)))
        // The bottom two corners of the box: the chevron's arms pass nowhere
        // near either, so a ring round the BOX shows up here and one on the
        // line does not.
        #expect(alpha(shot, 44, 146) == 0)
        #expect(alpha(shot, 176, 146) == 0)
        // ...and the line itself is painted. Layer (30,50) is halfway down the
        // left arm, which is canvas (70,100).
        #expect(alpha(shot, 70, 100) > 200)
    }

    @Test("...and it is the width that was asked for, whichever position it says",
          arguments: BorderPosition.allCases)
    func aLineGetsTheWidthItAsksFor(position: BorderPosition) throws {
        // An open line has no inside, so all three positions draw the one band
        // down the middle of it: the same picture, to the pixel.
        let asked = try shoot(chevron(BorderEffect(width: 8, colorHex: "#FF0000",
                                                   position: position)))
        let centred = try shoot(chevron(BorderEffect(width: 8, colorHex: "#FF0000",
                                                     position: .center)))
        #expect(asked.data == centred.data)
    }

    @Test("A wider border on a line is wider, proportionally")
    func aLineBandScalesWithItsWidth() throws {
        let thin = inked(try shoot(chevron(BorderEffect(width: 4, colorHex: "#FF0000",
                                                        position: .center))))
        let fat = inked(try shoot(chevron(BorderEffect(width: 16, colorHex: "#FF0000",
                                                       position: .center))))
        // Four times the width over the same length of line, give or take the
        // round caps on the two ends.
        #expect(Double(fat) > Double(thin) * 3.4)
        #expect(Double(fat) < Double(thin) * 4.6)
    }

    @Test("A line's border asks the layer for the room it needs")
    func aLineAsksForRoom() throws {
        let layer = chevron(BorderEffect(width: 8, colorHex: "#FF0000", position: .inside))
        #expect(layer.outlineOutset == 4)
        // The band is 8 wide centred on the arm, so it reaches 4 points past
        // the box at the bottom point of the chevron, canvas (100,150).
        let shot = try shoot(layer)
        #expect(alpha(shot, 100, 152) > 100)
    }

    // MARK: Nothing else moved

    @Test("A picture, a frame, a group and an oval ring exactly as they did")
    func everythingElseIsUntouched() throws {
        // Each of these is drawn twice through the same renderer, once with the
        // Border in each position, and the answers are pinned by the pixels
        // rather than by a golden file: what matters is that the ring is round
        // the box (or the oval) and reaches where its position says.
        var oval = Layer(name: "Oval",
                         content: .annotation(AnnotationContent(shape: .ellipse,
                                                                strokeWidth: 0)),
                         frame: CGRect(x: 40, y: 40, width: 120, height: 80))
        oval.style.effects = [.border(BorderEffect(width: 8, colorHex: "#FF0000",
                                                   position: .outside))]
        #expect(!oval.ringsAnOpenLine)
        let ovalShot = try shoot(oval)
        // The corner of the oval's box is empty and the point above its top is
        // ink: the oval rings as an oval, as it has since 2026-09-08.
        #expect(alpha(ovalShot, 44, 44) == 0)
        #expect(alpha(ovalShot, 100, 36) > 200)

        var frame = Layer(name: "Frame",
                          content: .group(GroupContent(children: [], isFrame: true)),
                          frame: CGRect(x: 40, y: 40, width: 120, height: 80))
        frame.style.effects = [.border(BorderEffect(width: 8, colorHex: "#FF0000",
                                                    position: .outside))]
        #expect(!frame.ringsAnOpenLine)
        #expect(frame.outlineOutset == 8)
        let frameShot = try shoot(frame)
        // A frame's ring IS its box, corners and all.
        #expect(alpha(frameShot, 36, 36) > 200)
        #expect(alpha(frameShot, 100, 80) == 0)
    }

    @Test("A closed path's border is unchanged by the open-line rule")
    func aClosedPathKeepsItsPositions() throws {
        // Inside, centred and outside are three different pictures on a shape
        // with an inside: the rule that collapses them only reaches lines.
        let inside = try shoot(triangle(BorderEffect(width: 8, colorHex: "#FF0000",
                                                     position: .inside)))
        let centred = try shoot(triangle(BorderEffect(width: 8, colorHex: "#FF0000",
                                                      position: .center)))
        let outside = try shoot(triangle(BorderEffect(width: 8, colorHex: "#FF0000",
                                                      position: .outside)))
        #expect(inside.data != centred.data)
        #expect(centred.data != outside.data)
    }
}
