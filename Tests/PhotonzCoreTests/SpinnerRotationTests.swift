import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A ring or arc gets a full turn, forever, when Rotation is added**
/// (`a-ring-or-arc-gets-a-full-turn-forever-when-rota`, mock
/// `icon-loop-wt.html` step 3: "Rotation on a ring arrives at 0° to 360°,
/// Forever and Linear, because that is what you would have typed").
///
/// Everything else arrives as the swing it always has. The spinner answer is
/// for a ring or an arc drawn in an icon, where a spinner is what one is.
@Suite("A ring or arc in an icon arrives spinning")
struct SpinnerRotationTests {

    // MARK: - Fixtures

    static let box = CGRect(x: 12, y: 3, width: 9, height: 9)

    static func ellipse(rotation: CGFloat = 0) -> Layer {
        var layer = Layer(name: "Ring",
                          content: .annotation(AnnotationContent(shape: .ellipse, colorHex: "#0C0E14")),
                          frame: CGRect(x: 3, y: 3, width: 18, height: 18))
        layer.transform.rotation = rotation
        return layer
    }

    static func rectangle() -> Layer {
        Layer(name: "Box", content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#0C0E14")),
              frame: box)
    }

    /// The top right quarter of a ring of radius 9 round (12, 12), drawn with
    /// the pen: two anchors and one bend.
    static func arc(closed: Bool = false, trim: StrokeTrim? = nil) -> Layer {
        var content = PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0), handleOut: CGPoint(x: 5, y: 0)),
            PathAnchor(point: CGPoint(x: 9, y: 9), handleIn: CGPoint(x: 0, y: -5))
        ], isClosed: closed, paint: Paint(hex: "#0C0E14"), strokeWidth: 2)
        content.trim = trim
        return Layer(name: "Arc", content: .path(content), frame: box)
    }

    /// A straight open line: a stroke, not an arc.
    static func line() -> Layer {
        Layer(name: "Line", content: .path(PathContent(anchors: [
            PathAnchor(point: CGPoint(x: 0, y: 0)),
            PathAnchor(point: CGPoint(x: 9, y: 9))
        ], isClosed: false, paint: Paint(hex: "#0C0E14"), strokeWidth: 2)), frame: box)
    }

    // MARK: - What counts

    @Test func anEllipseAndAnOpenCurveAreSpinnerShapes() {
        #expect(Self.ellipse().isRingOrArc)
        #expect(Self.arc().isRingOrArc)
        // A closed curve with only part of its line drawn is an arc as well:
        // a circle trimmed to three quarters is the commonest spinner there is.
        #expect(Self.arc(closed: true, trim: StrokeTrim(start: 0, end: 0.75)).isRingOrArc)
    }

    @Test func aBoxALineAndAClosedBlobAreNot() {
        #expect(!Self.rectangle().isRingOrArc)
        #expect(!Self.line().isRingOrArc)
        // The bell's clapper and the bell itself are closed curves: they swing.
        #expect(!Self.arc(closed: true).isRingOrArc)
        #expect(!Self.arc(closed: true, trim: .whole).isRingOrArc)
    }

    // MARK: - What it arrives as

    @Test func aRingInAnIconArrivesAsAFullTurnForever() {
        for layer in [Self.ellipse(), Self.arc()] {
            let motion = LayerMotion.starting(.rotation, on: layer, inIcon: true)
            #expect(motion.from == .number(0))
            #expect(motion.to == .number(360))
            #expect(motion.repeats == .forever)
            #expect(motion.curve == .linear)
            // The mock's own turn: 1.2 s, "0 → 1200 ms".
            #expect(motion.timing.durationMS == 1200)
            #expect(motion.summary == "0° → 360° over 1.2s")
            // Around its own middle, as step 3 draws it; Artboard is step 4.
            #expect(motion.pivot == .centre)
        }
    }

    /// A ring somebody already turned keeps its angle: the turn starts from
    /// where it is, so nothing jerks the moment it is told to spin.
    @Test func aTurnedRingSpinsFromWhereItIs() {
        let motion = LayerMotion.starting(.rotation, on: Self.ellipse(rotation: .pi / 2), inIcon: true)
        #expect(motion.from == .number(90))
        #expect(motion.to == .number(450))
    }

    @Test func everythingElseKeepsItsSwing() {
        let swing = "-12° → 12° over 0.9s"
        #expect(LayerMotion.starting(.rotation, on: Self.rectangle(), inIcon: true).summary == swing)
        #expect(LayerMotion.starting(.rotation, on: Self.line(), inIcon: true).summary == swing)
        #expect(LayerMotion.starting(.rotation, on: Self.arc(closed: true), inIcon: true).summary == swing)
        // Outside an icon a ring is a mark on a picture, and it swings as it
        // always has: the tutorials put a second swing on an ellipse.
        let loose = LayerMotion.starting(.rotation, on: Self.ellipse())
        #expect(loose.summary == swing)
        #expect(loose.repeats == .foreverThereAndBack)
    }

    /// Only Rotation: any other property on a ring arrives as it always has.
    @Test func otherPropertiesOnARingAreUnchanged() {
        let ring = Self.ellipse()
        #expect(LayerMotion.starting(.scale, on: ring, inIcon: true).repeats == .foreverThereAndBack)
        let opacity = LayerMotion.starting(.opacity, on: ring, inIcon: true)
        let before = LayerMotion.starting(.opacity, on: ring)
        #expect(opacity.from == before.from && opacity.to == before.to)
        #expect(opacity.repeats == before.repeats && opacity.timing == before.timing)
    }
}
