import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The six things the Lens tool can be set to do, and what happens when a
/// layer already on the picture is switched from one of them to another.
@Suite("Lens kinds")
struct LensKindTests {

    private let canvas = CGSize(width: 400, height: 300)

    // MARK: - The six

    /// The five adjustments, then Magnify. Magnify is last because the five
    /// were there first: a list a person has learned the order of does not get
    /// reshuffled to make room.
    @Test func theToolOffersTheFiveAdjustmentsAndMagnify() {
        #expect(LensKind.allCases == [.blur, .pixelate, .greyscale, .invert,
                                      .brightness, .magnify])
    }

    @Test func everyKindSaysItsName() {
        for kind in LensKind.allCases {
            #expect(!kind.title.isEmpty)
        }
        #expect(LensKind.magnify.title == "Magnify")
    }

    /// Five of the six are an adjustment a lens layer can hold; Magnify is the
    /// one that is not, because what it draws lives somewhere else on the
    /// picture and is a zoom callout.
    @Test func onlyMagnifyIsNotAnAdjustment() {
        for adjustment in LensAdjustment.allCases {
            let kind = LensKind(adjustment)
            #expect(kind.adjustment == adjustment)
            #expect(!kind.magnifies)
            // The two enums share raw values, so a kind read off disk and an
            // adjustment read off disk can never drift apart.
            #expect(kind.rawValue == adjustment.rawValue)
            #expect(kind.title == adjustment.title)
        }
        #expect(LensKind.magnify.adjustment == nil)
        #expect(LensKind.magnify.magnifies)
    }

    // MARK: - What a picked layer already is

    @Test func aLensLayerReportsTheAdjustmentItHolds() {
        let layer = Layer(name: "Pixelate",
                          content: .lens(LensContent(adjustment: .pixelate)),
                          frame: CGRect(x: 10, y: 10, width: 60, height: 40))
        #expect(layer.lensKind == .pixelate)
    }

    @Test func aZoomCalloutReportsItselfAsMagnify() {
        let layer = Layer(name: "Zoom",
                          content: .zoomCallout(ZoomCalloutContent(
                              sourceRect: CGRect(x: 10, y: 10, width: 30, height: 20))),
                          frame: CGRect(x: 100, y: 10, width: 60, height: 40))
        #expect(layer.lensKind == .magnify)
    }

    @Test func anythingElseIsNeither() {
        let layer = Layer(name: "Text", content: .text(TextContent(string: "hi")),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(layer.lensKind == nil)
    }

    // MARK: - Magnify to an adjustment

    /// The box stays exactly where it is. Somebody switching their magnifier to
    /// Blur is looking AT that box, so it must not move out from under them.
    @Test func switchingAMagnifierToAnAdjustmentKeepsItsBox() {
        let frame = CGRect(x: 200, y: 40, width: 120, height: 80)
        let layer = Layer(name: "Zoom",
                          content: .zoomCallout(ZoomCalloutContent(
                              sourceRect: CGRect(x: 20, y: 40, width: 60, height: 40),
                              magnification: 2)),
                          frame: frame)
        let out = LensConversion.layer(layer, becoming: .blur, canvas: canvas)
        #expect(out.frame == frame)
        #expect(out.lens?.adjustment == .blur)
        #expect(out.zoomCallout == nil)
    }

    /// The tool's own settings come across, so a lens made this way is the lens
    /// the tool would have drawn rather than one at some other strength.
    @Test func switchingToAnAdjustmentUsesTheToolsNumbers() {
        let layer = Layer(name: "Zoom",
                          content: .zoomCallout(ZoomCalloutContent(
                              sourceRect: CGRect(x: 20, y: 40, width: 60, height: 40))),
                          frame: CGRect(x: 200, y: 40, width: 120, height: 80))
        var tool = LensContent()
        tool.blurRadius = 31
        let out = LensConversion.layer(layer, becoming: .blur, canvas: canvas, lensSettings: tool)
        #expect(out.lens?.blurRadius == 31)
    }

    // MARK: - An adjustment to Magnify

    /// The lens's box becomes the region that gets magnified: it is the part of
    /// the picture that lens was covering, which is the part you meant.
    @Test func switchingALensToMagnifyMagnifiesWhatItWasCovering() {
        let frame = CGRect(x: 40, y: 40, width: 60, height: 40)
        let layer = Layer(name: "Blur", content: .lens(LensContent(adjustment: .blur)),
                          frame: frame)
        let out = LensConversion.layer(layer, becoming: .magnify, canvas: canvas,
                                       magnification: 2, shape: .circle)
        let callout = try! #require(out.zoomCallout)
        #expect(callout.sourceRect == frame)
        #expect(callout.magnification == 2)
        #expect(callout.shape == .circle)
        #expect(out.lens == nil)
    }

    /// ...and the box moves off the source, exactly the way a freshly drawn
    /// callout does, so a magnifier never covers the thing it points at.
    @Test func switchingToMagnifyPlacesTheBoxClearOfTheSource() {
        let frame = CGRect(x: 40, y: 40, width: 60, height: 40)
        let layer = Layer(name: "Blur", content: .lens(LensContent(adjustment: .blur)),
                          frame: frame)
        let out = LensConversion.layer(layer, becoming: .magnify, canvas: canvas,
                                       magnification: 2)
        #expect(!out.frame.intersects(frame))
        #expect(out.frame.width == frame.width * 2)
        #expect(out.frame.height == frame.height * 2)
    }

    /// A second magnifier steps clear of the first, the same list the callout
    /// tool already steers around.
    @Test func switchingToMagnifyStepsClearOfTheMagnifiersAlreadyThere() {
        let frame = CGRect(x: 40, y: 40, width: 60, height: 40)
        let layer = Layer(name: "Blur", content: .lens(LensContent(adjustment: .blur)),
                          frame: frame)
        let lonely = LensConversion.layer(layer, becoming: .magnify, canvas: canvas,
                                          magnification: 2)
        let crowded = LensConversion.layer(layer, becoming: .magnify, canvas: canvas,
                                           magnification: 2, avoiding: [lonely.frame])
        #expect(crowded.frame != lonely.frame)
    }

    /// A lens box too small to magnify is left alone rather than turned into a
    /// callout nobody can see: switching does nothing, and the picker snaps
    /// back to what the layer still is.
    @Test func aBoxTooSmallToMagnifyIsLeftAlone() {
        let layer = Layer(name: "Blur", content: .lens(LensContent(adjustment: .blur)),
                          frame: CGRect(x: 10, y: 10, width: 2, height: 2))
        let out = LensConversion.layer(layer, becoming: .magnify, canvas: canvas)
        #expect(out.lensKind == .blur)
    }

    /// A lens wears no ring — it is meant to look like the picture, changed —
    /// and a magnifier's source outline and leader lines are DRAWN in the ring's
    /// colour and weight. Without one they come out a one-point black hairline
    /// that vanishes on a dark screenshot, so switching to Magnify gives the
    /// layer the ring a freshly drawn magnifier has.
    @Test func switchingToMagnifyGivesAPlainLensTheRingItNeeds() throws {
        let layer = Layer(name: "Blur", content: .lens(LensContent(adjustment: .blur)),
                          frame: CGRect(x: 40, y: 40, width: 60, height: 40),
                          style: LensBuilder.defaultStyle)
        #expect(layer.style.borderWidth == 0)
        let out = LensConversion.layer(layer, becoming: .magnify, canvas: canvas)
        #expect(out.style.borderWidth == ZoomCalloutBuilder.defaultStyle.borderWidth)
        #expect(out.style.borderColorHex == ZoomCalloutBuilder.defaultStyle.borderColorHex)
    }

    /// ...and a ring somebody chose is left exactly as they chose it.
    @Test func switchingToMagnifyKeepsARingSomebodyAlreadySet() {
        var style = LayerStyle()
        style.borderWidth = 7
        style.borderColorHex = "#00FF00"
        let layer = Layer(name: "Blur", content: .lens(LensContent(adjustment: .blur)),
                          frame: CGRect(x: 40, y: 40, width: 60, height: 40), style: style)
        let out = LensConversion.layer(layer, becoming: .magnify, canvas: canvas)
        #expect(out.style.borderWidth == 7)
        #expect(out.style.borderColorHex == "#00FF00")
    }

    // MARK: - Nothing to do

    @Test func switchingToWhatItAlreadyIsChangesNothing() {
        let layer = Layer(name: "Zoom",
                          content: .zoomCallout(ZoomCalloutContent(
                              sourceRect: CGRect(x: 20, y: 40, width: 60, height: 40))),
                          frame: CGRect(x: 200, y: 40, width: 120, height: 80))
        #expect(LensConversion.layer(layer, becoming: .magnify, canvas: canvas) == layer)
    }

    @Test func aLayerThatIsNeitherIsLeftAlone() {
        let layer = Layer(name: "Text", content: .text(TextContent(string: "hi")),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        #expect(LensConversion.layer(layer, becoming: .blur, canvas: canvas) == layer)
    }

    // MARK: - A callout saved before any of this

    /// The whole point of the merge: a document with a zoom callout in it opens
    /// as a Magnify lens and is byte for byte the callout it was, so it draws
    /// exactly as it drew — leader lines, source outline and all.
    @Test func aSavedCalloutOpensAsAMagnifyLensAndIsUnchanged() throws {
        let saved = Layer(name: "Zoom",
                          content: .zoomCallout(ZoomCalloutContent(
                              sourceRect: CGRect(x: 21, y: 34, width: 55, height: 89),
                              magnification: 3.5, shape: .circle)),
                          frame: CGRect(x: 120, y: 30, width: 192.5, height: 311.5))
        let data = try JSONEncoder().encode(saved)
        let opened = try JSONDecoder().decode(Layer.self, from: data)

        #expect(opened.lensKind == .magnify)
        let callout = try #require(opened.zoomCallout)
        #expect(callout.sourceRect == CGRect(x: 21, y: 34, width: 55, height: 89))
        #expect(callout.magnification == 3.5)
        #expect(callout.shape == .circle)
        #expect(opened.frame == saved.frame)
        // Still a callout in the model, which is what keeps the renderer, the
        // exporter and every existing walk untouched.
        #expect(opened == saved)
    }

    // MARK: - The name in the layers list

    /// A layer still wearing the name its kind gave it is renamed with the
    /// kind; one somebody named themselves keeps the name they chose.
    @Test func theRowIsRenamedUnlessSomebodyNamedItThemselves() {
        let frame = CGRect(x: 40, y: 40, width: 60, height: 40)
        let auto = Layer(name: "Blur", content: .lens(LensContent(adjustment: .blur)),
                         frame: frame)
        #expect(LensConversion.layer(auto, becoming: .magnify, canvas: canvas).name == "Magnify")

        var named = auto
        named.name = "Street number"
        #expect(LensConversion.layer(named, becoming: .magnify, canvas: canvas).name
                == "Street number")
    }

    /// "Zoom" is what every callout drawn before this existed is called, so it
    /// counts as a name nobody chose.
    @Test func theCalloutsOldNameStillCountsAsUnnamed() {
        let layer = Layer(name: "Zoom",
                          content: .zoomCallout(ZoomCalloutContent(
                              sourceRect: CGRect(x: 20, y: 40, width: 60, height: 40))),
                          frame: CGRect(x: 200, y: 40, width: 120, height: 80))
        #expect(LensConversion.layer(layer, becoming: .blur, canvas: canvas).name == "Blur")
    }
}
