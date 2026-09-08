import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What the line under Position & Size says after a number the picked layers
/// would not take.
///
/// The read-back half landed first: the box comes back to the width they kept
/// rather than showing what was asked for. On its own that reads as a box that
/// ignored you. This is the other half — the line under the section carries the
/// reason, in the wording law's two halves, for a few seconds.
///
/// The sentence is never held. It is worked out afresh from what you DID (the
/// number you typed and where it landed), so taking the rule off takes the
/// sentence with it instead of leaving it explaining a rule that is gone.
@Suite("Why a typed size sprang back")
struct GeometryRefusalTests {

    private func rectangle(_ frame: CGRect) -> Layer {
        AnnotationBuilder.layer(content: AnnotationContent(shape: .rectangle),
                                from: CGPoint(x: frame.minX, y: frame.minY),
                                to: CGPoint(x: frame.maxX, y: frame.maxY))
    }

    /// A stack held between a smallest and a largest width — the pair the
    /// Layout section's Smallest and Largest rows set. 200 wide as it stands.
    private func heldStack(from: CGFloat? = 160, to: CGFloat? = 260,
                           tallest: CGFloat? = nil, shortest: CGFloat? = nil) -> Layer {
        var content = GroupContent(children: [rectangle(CGRect(x: 0, y: 0, width: 200, height: 60)),
                                              rectangle(CGRect(x: 0, y: 0, width: 200, height: 40))])
        content.layout = GroupLayout(kind: .stack, minWidth: from, maxWidth: to,
                                     minHeight: shortest, maxHeight: tallest)
        return Layer(name: "Held", content: .group(content),
                     frame: CGRect(x: 10, y: 10, width: 0, height: 0))
    }

    private func text(_ frame: CGRect) -> Layer {
        Layer(name: "Words", content: .text(TextContent(string: "Hello there wide words")),
              frame: frame)
    }

    private func selection(_ layers: [Layer]) -> LayerGeometrySelection {
        LayerGeometrySelection(layers.map { layer in
            LayerGeometrySelection.Member(id: layer.id,
                                          frame: layer.withoutSlack(layer.shownBox),
                                          editing: LayerGeometryEditing(layer: layer),
                                          slack: layer.boxSlack)
        })
    }

    /// Typing `value` and letting the document take it, the same way
    /// `EditorState.commitGeometry` does.
    private func committing(_ value: CGFloat, into field: LayerGeometryField,
                            _ layers: [Layer]) -> [Layer] {
        let moves = selection(layers).applying(value, to: field)
        return layers.map { layer in
            guard let frame = moves[layer.id] else { return layer }
            return layer.geometrySet(to: frame, canvas: CGSize(width: 900, height: 600),
                                     byHand: true)
        }
    }

    /// Typing a number and asking what the panel says afterwards: the whole
    /// round trip the field makes.
    private func said(_ value: CGFloat, into field: LayerGeometryField,
                      _ layers: [Layer]) -> String? {
        let after = selection(committing(value, into: field, layers))
        return after.refusal(asking: value, for: field, landedOn: after.reading(field))
    }

    // MARK: The limits are known before you type

    @Test("A group's Smallest width is a floor the panel knows about, not a surprise")
    func smallestWidthIsAKnownFloor() {
        let editing = LayerGeometryEditing(layer: heldStack())
        #expect(editing.minimum(for: .width) == 160)
        #expect(editing.maximum(for: .width) == 260)
        // So the hover tip warns before the number springs back.
        #expect(selection([heldStack()]).note(for: .width)?.contains("160") == true)
    }

    @Test("A group with no limits has none, so nothing is invented")
    func aFreeGroupHasNoLimits() {
        let editing = LayerGeometryEditing(layer: heldStack(from: nil, to: nil))
        #expect(editing.minimum(for: .width) == LayerGeometry.minimumSide)
        #expect(editing.maximum(for: .width) == nil)
        #expect(selection([heldStack(from: nil, to: nil)]).note(for: .width) == nil)
    }

    @Test("A group's Smallest and Largest hold a typed height too")
    func heightLimitsAreKnownAsWell() {
        let editing = LayerGeometryEditing(layer: heldStack(from: nil, to: nil,
                                                            tallest: 300, shortest: 120))
        #expect(editing.minimum(for: .height) == 120)
        #expect(editing.maximum(for: .height) == 300)
    }

    // MARK: What it says

    @Test("A width below the group's Smallest names Smallest, not the W field")
    func refusedBelowSmallestNamesSmallest() {
        let sentence = said(50, into: .width, [heldStack()])
        #expect(sentence == LayerGeometryEditing.smallestReason(for: .width, 160))
        #expect(sentence?.contains("Smallest") == true)
        #expect(sentence?.contains("Layout section") == true)
        #expect(sentence?.contains("160") == true)
        // The field's own letter is never the answer.
        #expect(sentence?.contains("W field") == false)
    }

    @Test("A width past the group's Largest names Largest")
    func refusedPastLargestNamesLargest() {
        let sentence = said(400, into: .width, [heldStack()])
        #expect(sentence == LayerGeometryEditing.largestReason(for: .width, 260))
        #expect(sentence?.contains("Largest") == true)
        #expect(sentence?.contains("260") == true)
    }

    @Test("A height below the group's Smallest height says height, not width")
    func refusedHeightNamesTheHeightRow() {
        let stack = heldStack(from: nil, to: nil, shortest: 400)
        let sentence = said(50, into: .height, [stack])
        #expect(sentence == LayerGeometryEditing.smallestReason(for: .height, 400))
        #expect(sentence?.contains("Smallest height") == true)
    }

    @Test("A width below what the words need names the words")
    func refusedTextWidthNamesTheWords() {
        let words = text(CGRect(x: 0, y: 0, width: 200, height: 30))
        let sentence = said(5, into: .width, [words])
        #expect(sentence == LayerGeometryEditing
                .wordsReason(for: .width, TextMeasurement.minimumContentWidth))
        #expect(sentence?.contains("words") == true)
        #expect(sentence?.contains("Text section") == true)
    }

    // MARK: When it says nothing at all

    @Test("A width the layers take says nothing")
    func anAcceptedWidthSaysNothing() {
        #expect(said(240, into: .width, [heldStack()]) == nil)
    }

    @Test("Typing the number they already have says nothing")
    func typingWhatTheyAlreadyAreSaysNothing() {
        #expect(said(200, into: .width, [heldStack()]) == nil)
    }

    @Test("A position is never refused, so it never explains itself")
    func aPositionNeverExplainsItself() {
        let after = selection(committing(-40, into: .x, [heldStack()]))
        #expect(after.refusal(asking: -40, for: .x, landedOn: after.reading(.x)) == nil)
    }

    @Test("Nothing picked has nothing to say")
    func anEmptySelectionSaysNothing() {
        let sel = LayerGeometrySelection([])
        #expect(sel.refusal(asking: 50, for: .width, landedOn: sel.reading(.width)) == nil)
    }

    // MARK: The sentence never outlives its rule

    @Test("Taking the Smallest off takes the sentence with it, before its time is up")
    func theSentenceGoesWhenTheRuleGoes() {
        // Refused, so there is a sentence.
        let held = committing(50, into: .width, [heldStack()])
        let after = selection(held)
        #expect(after.refusal(asking: 50, for: .width, landedOn: after.reading(.width)) != nil)
        // The same report, read against a selection whose Smallest has been
        // cleared and whose width is still 160: the rule is gone, so the words
        // go with it rather than sitting there for the rest of six seconds.
        var freed = held[0]
        var layout = freed.group?.layout ?? GroupLayout(kind: .stack)
        layout.minWidth = nil
        freed.setGroupLayout(layout)
        let now = selection([freed])
        #expect(now.reading(.width) == .agreed(160))
        #expect(now.refusal(asking: 50, for: .width, landedOn: .agreed(160)) == nil)
    }

    @Test("A number that has since moved on is history, so the line goes quiet")
    func aStaleLandingSaysNothing() {
        let after = selection(committing(50, into: .width, [heldStack()]))
        // The report says it landed on 160; the layers now read 240, so the
        // report is about a moment that has passed.
        #expect(after.refusal(asking: 50, for: .width, landedOn: .agreed(240)) == nil)
    }

    // MARK: Several layers

    @Test("One number two layers land differently on names the rule that held one back")
    func aPartialRefusalNamesTheRule() {
        let plain = rectangle(CGRect(x: 0, y: 400, width: 200, height: 40))
        let sentence = said(50, into: .width, [heldStack(), plain])
        #expect(sentence != nil)
        // The named rule wins over a count: one of them has a Smallest and
        // that is the thing to change.
        #expect(sentence?.contains("Smallest") == true)
    }

    @Test("Two layers held by the same rule say it once, not twice")
    func twoHeldLayersSayItOnce() {
        let sentence = said(50, into: .width, [heldStack(), heldStack()])
        #expect(sentence == LayerGeometryEditing.smallestReason(for: .width, 160))
    }
}
