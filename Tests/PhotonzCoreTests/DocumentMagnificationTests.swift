import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

@Suite("Document magnification")
struct DocumentMagnificationTests {

    private func textLayer(frame: CGRect, name: String = "Label") -> Layer {
        Layer(name: name, content: .text(TextContent(string: "Padding 16", fontSize: 18)),
              frame: frame)
    }

    @Test func scaleOfOneChangesNothing() {
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300),
                                  layers: [textLayer(frame: CGRect(x: 10, y: 20, width: 100, height: 40))])
        #expect(doc.magnified(by: 1) == doc)
        #expect(doc.magnified(by: 0) == doc)
        #expect(doc.magnified(by: -2) == doc)
    }

    @Test func canvasAndFramesGrowTogether() {
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300),
                                  layers: [textLayer(frame: CGRect(x: 10, y: 20, width: 100, height: 40))])
        let big = doc.magnified(by: 2)
        #expect(big.canvasSize == CGSize(width: 800, height: 600))
        #expect(big.layers[0].frame == CGRect(x: 20, y: 40, width: 200, height: 80))
    }

    @Test func theWordsThemselvesAreUntouched() {
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300),
                                  layers: [textLayer(frame: CGRect(x: 10, y: 20, width: 100, height: 40))])
        let big = doc.magnified(by: 3)
        guard case .text(let text) = big.layers[0].content else {
            Issue.record("expected a text layer"); return
        }
        #expect(text.string == "Padding 16")
        #expect(text.fontSize == 18)
    }

    @Test func everyLengthInAStyleGrows() {
        var style = LayerStyle(opacity: 0.5, blurRadius: 3, cornerRadius: 8, borderWidth: 2)
        style.shadow = ShadowStyle(radius: 6, offset: CGSize(width: 0, height: 4), spread: 1,
                                   colorHex: "#000000", opacity: 0.3)
        let big = style.magnified(by: 2)
        #expect(big.blurRadius == 6)
        #expect(big.cornerRadius == 16)
        #expect(big.borderWidth == 4)
        #expect(big.shadow?.radius == 12)
        #expect(big.shadow?.spread == 2)
        #expect(big.shadow?.offset == CGSize(width: 0, height: 8))
        // No size of its own: unchanged.
        #expect(big.opacity == 0.5)
    }

    @Test func aCropGrowsWithTheContentItCuts() {
        var layer = textLayer(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        layer.crop = CGRect(x: 10, y: 5, width: 50, height: 20)
        let big = layer.magnified(by: 2)
        #expect(big.crop == CGRect(x: 20, y: 10, width: 100, height: 40))
    }

    @Test func childrenInsideAGroupGrowToo() {
        let child = textLayer(frame: CGRect(x: 5, y: 5, width: 50, height: 20), name: "Inside")
        let group = Layer(name: "Card", content: .group(GroupContent(children: [child])),
                          frame: CGRect(x: 100, y: 100, width: 0, height: 0))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: [group])
        let big = doc.magnified(by: 2)
        #expect(big.layers[0].frame.origin == CGPoint(x: 200, y: 200))
        #expect(big.layers[0].children[0].frame == CGRect(x: 10, y: 10, width: 100, height: 40))
    }

    @Test func aZoomCalloutKeepsAimingAtTheSamePlace() {
        let callout = Layer(name: "Callout",
                            content: .zoomCallout(ZoomCalloutContent(
                                sourceRect: CGRect(x: 40, y: 60, width: 20, height: 10),
                                magnification: 3)),
                            frame: CGRect(x: 200, y: 10, width: 60, height: 30))
        let big = callout.magnified(by: 2)
        guard case .zoomCallout(let content) = big.content else {
            Issue.record("expected a callout"); return
        }
        #expect(content.sourceRect == CGRect(x: 80, y: 120, width: 40, height: 20))
        // How much it magnifies is a ratio, not a length.
        #expect(content.magnification == 3)
    }

    @Test func magnifyingIsProportional() {
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300),
                                  layers: [textLayer(frame: CGRect(x: 10, y: 20, width: 100, height: 40))])
        let once = doc.magnified(by: 4)
        let twice = doc.magnified(by: 2).magnified(by: 2)
        #expect(once == twice)
    }
    @Test func aGroupThatArrangesItselfMagnifiesItsLayoutToo() {
        var content = GroupContent(children: [
            Layer(name: "A", content: .annotation(AnnotationContent(shape: .rectangle)),
                  frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        ])
        content.layout = GroupLayout(kind: .stack, gap: 12, rowGap: 8,
                                     padding: GroupPadding(10),
                                     width: 200, height: 100,
                                     minWidth: 60, maxWidth: 300,
                                     minHeight: 30, maxHeight: 150)
        let group = Layer(name: "Card", content: .group(content),
                          frame: CGRect(x: 10, y: 10, width: 0, height: 0))
        let big = group.magnified(by: 2)
        let layout = big.group?.layout
        #expect(layout?.width == 400)
        #expect(layout?.height == 200)
        #expect(layout?.minWidth == 120)
        #expect(layout?.maxWidth == 600)
        #expect(layout?.minHeight == 60)
        #expect(layout?.maxHeight == 300)
        #expect(layout?.gap == 24)
        #expect(layout?.rowGap == 16)
        #expect(layout?.padding == GroupPadding(20))
        // How many cells a row holds is a count, not a length.
        #expect(layout?.columns == group.group?.layout?.columns)
        // …so the box the group draws into is stated in the same unit as the
        // contents it holds, which is what a clipping edge is measured against.
        #expect(big.localBounds.size == CGSize(width: 400, height: 200))
    }
}
