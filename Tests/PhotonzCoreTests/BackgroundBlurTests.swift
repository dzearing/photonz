import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A blur can soften the layer itself, or what is BEHIND it: the frosted glass
/// of the variants mock (`button.css`, `backdrop-filter`). One effect with a
/// Kind on it, the way a shadow is Drop or Inner and a glow Outer or Inner.
struct BackgroundBlurTests {

    private func box(_ style: LayerStyle = LayerStyle()) -> Layer {
        var annotation = AnnotationContent(shape: .rectangle, start: .zero,
                                           end: CGPoint(x: 100, y: 40))
        annotation.fillColorHex = "#FFFFFF"
        annotation.strokeWidth = 0
        return Layer(name: "Glass", content: .annotation(annotation),
                     frame: CGRect(x: 50, y: 50, width: 100, height: 40), style: style)
    }

    private func glass(_ radius: CGFloat = 12, isOn: Bool = true) -> LayerStyle {
        var style = LayerStyle()
        style.effects = [.blur(BlurEffect(radius: radius, isOn: isOn, kind: .background))]
        return style
    }

    @Test func aBlurIsALayerBlurUnlessItSaysOtherwise() {
        #expect(BlurEffect().kind == .layer)
        #expect(BlurKind.layer.title == "Layer")
        #expect(BlurKind.background.title == "Background")
    }

    /// A file written before blur had a Kind opens with its blur softening the
    /// layer, exactly as it did.
    @Test func anOldBlurReadsAsALayerBlur() throws {
        let old = Data(#"{"radius": 6, "isOn": true}"#.utf8)
        let blur = try JSONDecoder().decode(BlurEffect.self, from: old)
        #expect(blur.kind == .layer)
        #expect(blur.radius == 6)
    }

    @Test func aBackgroundBlurSurvivesTheRoundTrip() throws {
        let blur = BlurEffect(radius: 9, kind: .background)
        let back = try JSONDecoder().decode(BlurEffect.self, from: JSONEncoder().encode(blur))
        #expect(back == blur)
        var style = LayerStyle()
        style.effects = [.blur(blur)]
        let again = try JSONDecoder().decode(LayerStyle.self, from: JSONEncoder().encode(style))
        #expect(again.backgroundBlurRadius == 9)
        #expect(again.blurRadius == 0)
    }

    /// The layer's own softness and the softness behind it are two numbers: the
    /// renderer asks for each, and a background blur never fuzzes the layer.
    @Test func theTwoBlursAreReadApart() {
        let style = glass(12)
        #expect(style.blurRadius == 0)
        #expect(style.backgroundBlurRadius == 12)
        #expect(glass(12, isOn: false).backgroundBlurRadius == 0)
        var soft = LayerStyle()
        soft.blurRadius = 5
        #expect(soft.backgroundBlurRadius == 0)
        #expect(soft.blurRadius == 5)
    }

    /// A blur's own settings changed by the plain-number view tune the layer
    /// blur, never the glass: a transition that blurs a clip through a cut must
    /// not turn a frosted card's glass into a fuzzy card.
    @Test func settingTheLayerBlurLeavesTheGlassAlone() {
        var style = glass(12)
        style.blurRadius = 4
        #expect(style.backgroundBlurRadius == 12)
        #expect(style.blurRadius == 4)
    }

    /// A layer with glass draws what is under it, so everything that asks
    /// whether a layer reads its backdrop (the renderer, the drag preview, the
    /// dirty region) gets yes, and the region it watches is its box grown by
    /// the blur's reach.
    @Test func aGlassLayerReadsWhatIsBehindIt() {
        #expect(!box().readsBackdrop)
        #expect(box().backdropSource == nil)
        let layer = box(glass(10))
        #expect(layer.readsBackdrop)
        #expect(layer.backdropSource == CGRect(x: 20, y: 20, width: 160, height: 100))
        #expect(!box(glass(10, isOn: false)).readsBackdrop)
    }

    /// A group wearing glass has to be one picture before the glass can sit
    /// under it, so it is not a pass-through container.
    @Test func aGroupWithGlassIsNotPlain() {
        #expect(LayerStyle().isPlain)
        #expect(!glass().isPlain)
        #expect(!glass().hasNoFixedSizeDecoration)
    }

    /// Magnifying a document (export at 2x, a zoomed canvas) scales the glass
    /// with everything else, so the picture is the same at every size.
    @Test func magnifyingKeepsTheKindAndScalesTheReach() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 200, height: 200))
        doc.addLayer(box(glass(10)))
        let big = doc.magnified(by: 2)
        let style = big.layers.last?.style
        #expect(style?.backgroundBlurRadius == 20)
        #expect(style?.blurRadius == 0)
    }

    /// The row's Kind and Amount speak for the blur at that place in the list,
    /// on every picked layer whose list holds a blur there, and leave a layer
    /// with something else there alone.
    @Test func theRowTunesTheBlurAtItsPlace() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 200, height: 200))
        var soft = LayerStyle()
        soft.effects = [.blur(BlurEffect(radius: 4))]
        let a = box(soft)
        var shadowed = LayerStyle()
        shadowed.effects = [.shadow(ShadowStyle())]
        let b = box(shadowed)
        doc.addLayer(a)
        doc.addLayer(b)
        let changed = doc.updateBlurEffect(layerIDs: [a.id, b.id], at: 0) {
            $0.kind = .background
            $0.radius = 12
        }
        #expect(changed == 1)
        #expect(doc.layer(id: a.id)?.style.blurEffect(at: 0) == BlurEffect(radius: 12, kind: .background))
        #expect(doc.layer(id: b.id)?.style.effects == shadowed.effects)
        let members = [a.id, b.id].compactMap { id in
            doc.layer(id: id).map { LayerStyleSelection.Member(id: id, style: $0.style, cornerRadiusLimit: 0) }
        }
        let selection = LayerStyleSelection(members: members, selectionCount: 2)
        #expect(selection.blurs(at: 0).layerIDs == [a.id])
    }

    /// On a component copy the glass is part of "the blur": changing it is an
    /// override the copy keeps, and taking it back gives the original's.
    @Test func aCopysGlassIsItsBlur() {
        let original = glass(12)
        var turned = LayerStyle()
        turned.effects = [.blur(BlurEffect(radius: 12))]
        #expect(LayerStyle.differences(original, turned) == [.blur])
        #expect(LayerStyle.differences(original, glass(12)).isEmpty)
        #expect(LayerStyle.differences(original, glass(4)) == [.blur])
        let back = turned.taking(.blur, from: original)
        #expect(back.effects == original.effects)
        let again = original.taking(.blur, from: turned)
        #expect(again.effects == turned.effects)
    }

    /// The plus menu still offers Blur once; the Kind on its row is what makes
    /// it glass.
    @Test func thePlusOffersOneBlur() {
        #expect(AddableEffect.allCases.filter { $0.kind == .blur }.count == 1)
        #expect(AddableEffect.blur.newEffect.blur?.kind == .layer)
    }
}
