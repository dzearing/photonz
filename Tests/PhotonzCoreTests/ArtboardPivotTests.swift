import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A spinner turns about the middle of the artboard**
/// (`a-spinner-can-turn-about-the-middle-of-the-artbo`, mock
/// `icon-loop-wt.html` step 4).
///
/// A spinner is an arc on a 24 unit artboard, and an arc's own middle is not
/// the middle of the circle it belongs to. Turned about its own box it orbits;
/// turned about the artboard's middle it spins in place. So the Around row
/// offers Artboard, and the point it names is a PLACE on the artboard rather
/// than a fraction of the arc's box: reshape or nudge the arc and it still
/// spins about the middle of the icon.
@Suite("A spinner turns about the middle of the artboard")
struct ArtboardPivotTests {

    // MARK: - Fixtures

    /// The arc of the mock: the top right quarter of a ring of radius 9 round
    /// (12, 12), so its own box runs 12...21 across and 3...12 down and its
    /// own middle is (16.5, 7.5), nowhere near the middle of the icon.
    static let arcBox = CGRect(x: 12, y: 3, width: 9, height: 9)

    static func arc() -> Layer {
        Layer(name: "Arc",
              content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#0C0E14")),
              frame: arcBox)
    }

    /// A 24 unit icon frame parked somewhere on the canvas, with the arc in it.
    static func icon(holding children: [Layer], at origin: CGPoint = CGPoint(x: 300, y: 200))
        -> PhotonzDocument {
        let frame = Layer.frameLayer(name: "Icon", origin: origin,
                                     size: CGSize(width: 24, height: 24), children: children)
        return PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: [frame])
    }

    // MARK: - The value

    /// Artboard is a place, so it answers the same point whatever box it is
    /// asked about: that is what keeps a spinner spinning when its arc is
    /// nudged, reshaped or redrawn.
    @Test func anArtboardPivotIsTheSamePlaceWhateverTheLayersBox() {
        let pivot = MotionPivot.artboard(at: CGPoint(x: 12, y: 12), in: Self.arcBox)
        #expect(pivot.point(in: Self.arcBox) == CGPoint(x: 12, y: 12))
        #expect(pivot.point(in: Self.arcBox.offsetBy(dx: 3, dy: -2)) == CGPoint(x: 12, y: 12))
        #expect(pivot.point(in: CGRect(x: 0, y: 0, width: 2, height: 30)) == CGPoint(x: 12, y: 12))
    }

    /// The Around row reads Artboard, never Custom and never one of the spots
    /// on the shape, even where the arc happens to sit centred on the icon.
    @Test func theAroundRowReadsArtboard() {
        let pivot = MotionPivot.artboard(at: CGPoint(x: 12, y: 12),
                                         in: CGRect(x: 6, y: 6, width: 12, height: 12))
        #expect(pivot.isOnArtboard)
        #expect(pivot.named == nil)
        #expect(pivot.title == "Artboard")
        #expect(MotionPivot.artboardTitle == "Artboard")
        #expect(!MotionPivot.centre.isOnArtboard)
    }

    /// Artboard is one of the menu's own answers, so leaving it for Its centre
    /// does not make it the point Custom brings back.
    @Test func artboardIsNotAPointOfYourOwn() {
        let pivot = MotionPivot.artboard(at: CGPoint(x: 12, y: 12), in: Self.arcBox)
        #expect(!pivot.isOwn)
        var motion = LayerMotion.starting(.rotation, on: Self.arc())
        let before = motion
        motion.pivot = pivot
        motion = motion.keepingOwnValues(of: before)
        var back = motion
        back.pivot = .centre
        back = back.keepingOwnValues(of: motion)
        #expect(back.customPivot == nil)
    }

    /// The layer turns about it, which is the question the renderer, the
    /// outline and the hit test all ask.
    @Test func theLayerTurnsAboutTheArtboard() {
        var arc = Self.arc()
        var motion = LayerMotion.starting(.rotation, on: arc)
        motion.pivot = .artboard(at: CGPoint(x: 12, y: 12), in: arc.turnPivotBox)
        arc.motions = [motion]
        #expect(arc.turnPivot == CGPoint(x: 12, y: 12))
        arc.frame = arc.frame.offsetBy(dx: 1, dy: 1)
        #expect(arc.turnPivot == CGPoint(x: 12, y: 12))
    }

    /// Saved and read back, it is still the artboard; and a pivot written
    /// before Artboard existed reads back byte for byte the same.
    @Test func itSurvivesBeingWrittenAndAnOldPivotIsUntouched() throws {
        let pivot = MotionPivot.artboard(at: CGPoint(x: 12, y: 12), in: Self.arcBox)
        let read = try JSONDecoder().decode(MotionPivot.self, from: JSONEncoder().encode(pivot))
        #expect(read == pivot)
        #expect(read.title == "Artboard")
        let old = try JSONEncoder().encode(MotionPivot.topCentre)
        #expect(!String(decoding: old, as: UTF8.self).contains("artboard"))
    }

    // MARK: - Finding the artboard

    /// For a shape in an icon frame the middle of the frame, stated where the
    /// shape's own box is stated (from the frame's corner), wherever the frame
    /// sits on the canvas.
    @Test func theMiddleOfTheIconIsFoundFromTheShapeInIt() throws {
        let arc = Self.arc()
        let document = Self.icon(holding: [arc])
        let pivot = try #require(document.artboardPivot(for: arc.id))
        #expect(pivot.isOnArtboard)
        #expect(pivot.point(in: arc.turnPivotBox) == CGPoint(x: 12, y: 12))
    }

    /// A shape inside a group inside the icon still finds the icon's middle,
    /// stated from the group's corner.
    @Test func aShapeInAGroupInTheIconStillFindsItsMiddle() throws {
        var arc = Self.arc()
        arc.frame = arc.frame.offsetBy(dx: -2, dy: -1)
        let group = Layer(name: "Spinner",
                          content: .group(GroupContent(children: [arc])),
                          frame: CGRect(x: 2, y: 1, width: 0, height: 0))
        let document = Self.icon(holding: [group])
        let pivot = try #require(document.artboardPivot(for: arc.id))
        #expect(pivot.point(in: arc.turnPivotBox) == CGPoint(x: 10, y: 11))
    }

    /// Nothing to offer outside an icon: a shape loose on the canvas, a shape
    /// on a screen sized frame, and the icon frame itself.
    @Test func thereIsNoArtboardOutsideAnIcon() {
        let loose = Self.arc()
        let canvas = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: [loose])
        #expect(canvas.artboardPivot(for: loose.id) == nil)

        let onScreen = Self.arc()
        let screen = Layer.frameLayer(name: "Screen", origin: .zero,
                                      size: CGSize(width: 390, height: 844), children: [onScreen])
        let phone = PhotonzDocument(canvasSize: CGSize(width: 800, height: 900), layers: [screen])
        #expect(phone.artboardPivot(for: onScreen.id) == nil)

        let icon = Self.icon(holding: [Self.arc()])
        #expect(icon.artboardPivot(for: icon.layers[0].id) == nil)
    }

    // MARK: - The drag snaps

    /// Dragged near the middle of the icon, the pivot lands ON it and becomes
    /// the artboard; near the shape's own middle, it lands on Its centre;
    /// anywhere else it is wherever the hand let go.
    @Test func aDragSnapsToTheIconsMiddleAndTheShapesOwn() {
        let artboard = MotionPivot.artboard(at: CGPoint(x: 12, y: 12), in: Self.arcBox)
        let reach: CGFloat = 0.75

        let nearIcon = MotionPivot.dragged(to: CGPoint(x: 12.4, y: 11.7), in: Self.arcBox,
                                           artboard: artboard, reach: reach)
        #expect(nearIcon == artboard)

        let nearShape = MotionPivot.dragged(to: CGPoint(x: 16.2, y: 7.9), in: Self.arcBox,
                                            artboard: artboard, reach: reach)
        #expect(nearShape == .centre)

        let elsewhere = MotionPivot.dragged(to: CGPoint(x: 14, y: 2), in: Self.arcBox,
                                            artboard: artboard, reach: reach)
        #expect(elsewhere == MotionPivot(at: CGPoint(x: 14, y: 2), in: Self.arcBox))
        #expect(elsewhere.title == "Custom")

        // No icon, nothing to snap to but the shape.
        let loose = MotionPivot.dragged(to: CGPoint(x: 12.1, y: 12.1), in: Self.arcBox,
                                        artboard: nil, reach: reach)
        #expect(!loose.isOnArtboard)
    }

    /// Where the two middles are within reach of each other, the nearer wins,
    /// and a dead heat goes to the shape: its own middle follows it about.
    @Test func theNearerMiddleWins() {
        let box = CGRect(x: 6, y: 6, width: 12.6, height: 12)    // middle (12.3, 12)
        let artboard = MotionPivot.artboard(at: CGPoint(x: 12, y: 12), in: box)
        #expect(MotionPivot.dragged(to: CGPoint(x: 12.05, y: 12), in: box,
                                    artboard: artboard, reach: 1) == artboard)
        #expect(MotionPivot.dragged(to: CGPoint(x: 12.25, y: 12), in: box,
                                    artboard: artboard, reach: 1) == .centre)
        let centred = CGRect(x: 6, y: 6, width: 12, height: 12)
        let same = MotionPivot.artboard(at: CGPoint(x: 12, y: 12), in: centred)
        #expect(MotionPivot.dragged(to: CGPoint(x: 12.1, y: 12), in: centred,
                                    artboard: same, reach: 1) == .centre)
    }

    // MARK: - Leaving as a file

    /// The exported icon turns about the same point the canvas does: the
    /// middle of the 24 unit artboard, (12, 12) in the file.
    @Test func theExportedIconTurnsAboutTheMiddleOfTheArtboard() throws {
        var arc = Layer(name: "Arc", content: .path(SVGMotionExportTests.square(9)),
                        frame: Self.arcBox)
        arc.motions = [LayerMotion(property: .rotation, from: .number(0), to: .number(360),
                                   timing: MotionTiming(startMS: 0, durationMS: 800),
                                   curve: .linear, repeats: .forever,
                                   pivot: .artboard(at: CGPoint(x: 12, y: 12), in: Self.arcBox))]
        var document = Self.icon(holding: [arc])
        let frameID = document.layers[0].id
        document = try #require(document.frameDocument(id: frameID))
        let svg = SVGExport.write(document, animation: .moving(cycleMS: 800)).text
        let values = SVGMotionExportTests.valueLists(svg)
        #expect(values.first?.first == "0 12 12")
        #expect(values.first?.last == "360 12 12")
    }
}
