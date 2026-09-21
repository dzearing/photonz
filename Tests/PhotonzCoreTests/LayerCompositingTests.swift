import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **Compositing is layers with a rule for how they combine.** Three rules, and
/// two of them are new here: keying a colour out of a layer, and taking a
/// layer's shape from the one under it. The third, Blending, already shipped.
///
/// Written before the code, which is the rule for `PhotonzCore`. The maths is
/// here rather than in the renderer on purpose: what makes a key clean is
/// arithmetic, and arithmetic that lives behind Core Image cannot be tested at
/// all.
@Suite("Layers combine over what is under them")
struct LayerCompositingTests {

    /// The green of every green screen ever hung on a wall.
    static let green = RGBA(hex: "#00D84A")!

    // MARK: - Keying a colour out

    @Test func theKeyColourItselfGoesCompletelyAway() {
        let key = ChromaKey(colorHex: "#00D84A")
        #expect(key.applied(to: Self.green).alpha == 0)
    }

    @Test func aColourNowhereNearTheKeyIsLeftAlone() {
        let key = ChromaKey(colorHex: "#00D84A")
        let skin = RGBA(hex: "#E3AC7F")!
        let out = key.applied(to: skin)
        #expect(out.alpha == 1)
        #expect(abs(out.r - skin.r) < 0.001)
        #expect(abs(out.g - skin.g) < 0.001)
        #expect(abs(out.b - skin.b) < 0.001)
    }

    /// The whole reason the key measures colour rather than brightness. A
    /// screen lit from one side is the same green half a stop darker, and a key
    /// that compared the three numbers straight would leave the dark half of
    /// the wall standing.
    @Test func theSameColourLitDarkerIsStillKeyedOut() {
        let key = ChromaKey(colorHex: "#00D84A")
        let inTheShade = RGBA(r: Self.green.r * 0.55, g: Self.green.g * 0.55, b: Self.green.b * 0.55)
        let inTheSun = RGBA(r: min(1, Self.green.r * 1.4), g: min(1, Self.green.g * 1.4),
                            b: min(1, Self.green.b * 1.4))
        #expect(key.applied(to: inTheShade).alpha == 0)
        #expect(key.applied(to: inTheSun).alpha == 0)
    }

    /// What "clean enough to use rather than fringed" means: the edge is not a
    /// cliff. Half way between the subject and the wall comes out half there.
    @Test func theEdgeFadesRatherThanSteps() {
        let key = ChromaKey(colorHex: "#00D84A")
        let skin = RGBA(hex: "#E3AC7F")!
        var last = -1.0
        var partial: [Double] = []
        for step in 0...20 {
            let mix = Double(step) / 20
            let pixel = RGBA(r: Self.green.r + (skin.r - Self.green.r) * mix,
                             g: Self.green.g + (skin.g - Self.green.g) * mix,
                             b: Self.green.b + (skin.b - Self.green.b) * mix)
            let alpha = key.applied(to: pixel).alpha
            #expect(alpha >= last)
            partial.append(alpha)
            last = alpha
        }
        #expect(last == 1)
        // ...and somewhere along the way it really is part way, rather than the
        // ramp being nought until it snaps to one.
        #expect(partial.contains { $0 > 0.01 && $0 < 0.99 })
    }

    @Test func aWiderToleranceTakesMoreOfTheWallWithIt() {
        let narrow = ChromaKey(colorHex: "#00D84A", tolerance: 0.05, softness: 0.02)
        let wide = ChromaKey(colorHex: "#00D84A", tolerance: 0.7, softness: 0.02)
        // A muddy olive: green-ish, but a long way off the wall's own colour.
        let olive = RGBA(hex: "#6E8F3A")!
        #expect(narrow.applied(to: olive).alpha == 1)
        #expect(wide.applied(to: olive).alpha == 0)
    }

    @Test func aKeyThatIsOffChangesNothing() {
        var key = ChromaKey(colorHex: "#00D84A")
        key.isOn = false
        #expect(key.applied(to: Self.green).alpha == 1)
    }

    // MARK: - Spill: the green light the wall threw on the subject

    /// The fringe is the reason this exists. A pixel on the boundary is part
    /// subject and part wall, so what survives the key is a subject wearing a
    /// green rim. Spill pulls the key's own hue back out of it without
    /// darkening it.
    @Test func spillTakesTheKeysColourOutOfWhatIsLeft() {
        let skin = RGBA(hex: "#E3AC7F")!
        let rimmed = RGBA(r: (skin.r + Self.green.r) / 2,
                          g: (skin.g + Self.green.g) / 2,
                          b: (skin.b + Self.green.b) / 2)
        let without = ChromaKey(colorHex: "#00D84A", spill: 0).applied(to: rimmed)
        let with = ChromaKey(colorHex: "#00D84A", spill: 1).applied(to: rimmed)
        // Less green than it was, and not simply darker: the other two channels
        // are not pulled down with it.
        #expect(with.g < without.g - 0.02)
        #expect(with.r >= without.r - 0.001)
        #expect(with.b >= without.b - 0.001)
    }

    @Test func spillLeavesAColourThatIsNothingLikeTheKeyAlone() {
        let key = ChromaKey(colorHex: "#00D84A", spill: 1)
        let sky = RGBA(hex: "#4F79C4")!
        let out = key.applied(to: sky)
        #expect(abs(out.r - sky.r) < 0.001)
        #expect(abs(out.g - sky.g) < 0.001)
        #expect(abs(out.b - sky.b) < 0.001)
    }

    @Test func spillNeverPushesAChannelOutOfRange() {
        let key = ChromaKey(colorHex: "#00D84A", spill: 1)
        for hex in ["#FFFFFF", "#000000", "#00FF00", "#FF00FF", "#00D84A", "#7FFF7F"] {
            let out = key.applied(to: RGBA(hex: hex)!)
            #expect(out.r >= 0 && out.r <= 1)
            #expect(out.g >= 0 && out.g <= 1)
            #expect(out.b >= 0 && out.b <= 1)
            #expect(out.alpha >= 0 && out.alpha <= 1)
        }
    }

    /// A key on a colour nobody can parse is a key that does nothing, never a
    /// picture that comes out black.
    @Test func aColourThatCannotBeReadKeysNothing() {
        let key = ChromaKey(colorHex: "not a colour")
        #expect(key.applied(to: Self.green).alpha == 1)
    }

    // MARK: - What a document remembers

    @Test func aKeySurvivesBeingSavedAndOpenedAgain() throws {
        var layer = Layer(name: "Subject",
                          content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#00D84A")),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        layer.style.key = ChromaKey(colorHex: "#00D84A", tolerance: 0.3, softness: 0.1, spill: 0.4)
        layer.style.matte = .brightness
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [layer]
        let again = try JSONDecoder().decode(PhotonzDocument.self,
                                             from: JSONEncoder().encode(doc))
        #expect(again.layers[0].style.key?.colorHex == "#00D84A")
        #expect(again.layers[0].style.key?.tolerance == 0.3)
        #expect(again.layers[0].style.key?.spill == 0.4)
        #expect(again.layers[0].style.matte == .brightness)
    }

    /// A build that knows a matte kind this one does not must not take the
    /// whole file down with it, the same bargain `BlendMode.named` strikes.
    @Test func aMatteKindFromTheFutureReadsAsNoMatte() {
        #expect(LayerMatte.named("brightness") == .brightness)
        #expect(LayerMatte.named("holographic") == nil)
        #expect(LayerMatte.named(nil) == nil)
    }

    // MARK: - Masked by the layer below

    static func box(_ name: String) -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#0C0E14")),
              frame: CGRect(x: 0, y: 0, width: 40, height: 40))
    }

    @Test func aMatteComesFromTheLayerDirectlyUnderneath() {
        let shape = Self.box("Matte shape")
        var grade = Self.box("Colour grade")
        grade.style.matte = .shape
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [shape, grade]
        #expect(doc.matteSource(for: grade.id)?.id == shape.id)
        #expect(doc.isSpentAsAMatte(shape.id))
        #expect(!doc.isSpentAsAMatte(grade.id))
    }

    @Test func theBottomLayerHasNothingUnderItToBeMaskedBy() {
        var grade = Self.box("Colour grade")
        grade.style.matte = .shape
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [grade]
        #expect(doc.matteSource(for: grade.id) == nil)
    }

    /// Reordering changes the mask exactly the way it changes the composite,
    /// which is the whole argument for "the layer below" over a stored id.
    @Test func movingALayerChangesWhatMasksIt() {
        let plate = Self.box("Beach plate")
        let shape = Self.box("Matte shape")
        var grade = Self.box("Colour grade")
        grade.style.matte = .shape
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [plate, shape, grade]
        #expect(doc.matteSource(for: grade.id)?.id == shape.id)
        doc.layers = [shape, plate, grade]
        #expect(doc.matteSource(for: grade.id)?.id == plate.id)
    }

    @Test func aMatteInsideAGroupTakesItsSourceFromInsideThatGroup() {
        let outside = Self.box("Outside")
        let inside = Self.box("Inside")
        var top = Self.box("Top")
        top.style.matte = .shape
        var group = Self.box("Card")
        group.content = .group(GroupContent(children: [inside, top]))
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [outside, group]
        #expect(doc.matteSource(for: top.id)?.id == inside.id)
        #expect(doc.isSpentAsAMatte(inside.id))
        #expect(!doc.isSpentAsAMatte(outside.id))
    }

    /// A matte source that is hidden by hand is not a matte source: a layer
    /// nobody can see must not silently be cutting somebody else's shape out.
    @Test func aHiddenLayerIsNotSpentAsAMatte() {
        var shape = Self.box("Matte shape")
        shape.isVisible = false
        var grade = Self.box("Colour grade")
        grade.style.matte = .shape
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [shape, grade]
        #expect(doc.matteSource(for: grade.id) == nil)
        #expect(!doc.isSpentAsAMatte(shape.id))
    }

    /// A matte is not plain styling: a group wearing one has to draw into its
    /// own picture before the mask can cut it, so it can never be passed
    /// straight through onto the canvas.
    @Test func aMatteStopsAGroupBeingAPassThrough() {
        var style = LayerStyle()
        #expect(style.isPlain)
        style.matte = .shape
        #expect(!style.isPlain)
    }
}

/// **The stack on the timeline means what the layers list means.**
///
/// The layers list has always read top down, topmost first, and the renderer
/// has always drawn the array bottom up. The strip read the array straight, so
/// a title laid over a clip drew its bar UNDER the clip's — which says, in the
/// one place a video is arranged, that the title is behind the picture.
@Suite("The timeline stacks the way the layers list does")
struct TimelineStackOrderTests {

    static func clip(_ name: String, inMS: Int = 0, outMS: Int = 2000) -> Layer {
        var layer = Layer(name: name,
                          content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#0C0E14")),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        layer.time = LayerTime(inMS: inMS, outMS: outMS)
        return layer
    }

    @Test func theTopRowOfTheStripIsTheLayerThatDrawsOnTop() {
        let plate = Self.clip("Beach plate")
        let title = Self.clip("Opening card")
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        // Last in the array is drawn last, which is on top.
        doc.layers = [plate, title]
        #expect(doc.motionStrip().map(\.layerName) == ["Opening card", "Beach plate"])
    }

    /// The same order the panel reads, checked against the panel itself rather
    /// than against a list written out by hand, so the two cannot drift apart
    /// again.
    @Test func theStripAndTheLayersPanelAgree() {
        let plate = Self.clip("Beach plate")
        let subject = Self.clip("Subject")
        let title = Self.clip("Opening card")
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [plate, subject, title]
        let panel = doc.panelRows(expanded: []).map(\.id)
        #expect(doc.motionStrip().map(\.layerID) == panel)
    }

    @Test func aGroupsContentsStayUnderTheGroupOnTheStrip() {
        let loose = Self.clip("Beach plate")
        let first = Self.clip("Inside first")
        let second = Self.clip("Inside second")
        var group = Layer(name: "Card",
                          content: .group(GroupContent(children: [first, second])),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        group.time = LayerTime(inMS: 0, outMS: 2000)
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        doc.layers = [loose, group]
        #expect(doc.motionStrip().map(\.layerName)
            == ["Card", "Inside second", "Inside first", "Beach plate"])
    }
}
