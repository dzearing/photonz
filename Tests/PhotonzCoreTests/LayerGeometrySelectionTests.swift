import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

@Suite("Typed geometry across a whole selection")
struct LayerGeometrySelectionTests {

    private func rectangle(_ frame: CGRect, locked: Bool = false) -> Layer {
        var layer = AnnotationBuilder.layer(content: AnnotationContent(shape: .rectangle),
                                            from: CGPoint(x: frame.minX, y: frame.minY),
                                            to: CGPoint(x: frame.maxX, y: frame.maxY))
        layer.isLocked = locked
        return layer
    }

    private func arrow(_ frame: CGRect) -> Layer {
        AnnotationBuilder.layer(content: AnnotationContent(shape: .arrow),
                               from: CGPoint(x: frame.minX, y: frame.minY),
                               to: CGPoint(x: frame.maxX, y: frame.maxY))
    }

    private func member(_ layer: Layer, _ frame: CGRect) -> LayerGeometrySelection.Member {
        LayerGeometrySelection.Member(id: layer.id, frame: frame,
                                     editing: LayerGeometryEditing(layer: layer))
    }

    private func selection(_ frames: [CGRect]) -> LayerGeometrySelection {
        LayerGeometrySelection(frames.map { member(rectangle($0), $0) })
    }

    // MARK: Reading

    @Test("A field the layers agree on shows that one number")
    func agreedFieldShowsTheNumber() {
        let sel = selection([CGRect(x: 40, y: 10, width: 120, height: 32),
                             CGRect(x: 40, y: 60, width: 120, height: 44)])
        #expect(sel.reading(.x) == .agreed(40))
        #expect(sel.reading(.width) == .agreed(120))
        #expect(sel.reading(.y) == .mixed)
        #expect(sel.reading(.height) == .mixed)
    }

    @Test("Numbers that round to the same whole point read as agreed, because that is what the field shows")
    func roundingDecidesAgreement() {
        let sel = selection([CGRect(x: 39.6, y: 0, width: 10, height: 10),
                             CGRect(x: 40.4, y: 0, width: 10, height: 10)])
        #expect(sel.reading(.x) == .agreed(40))
    }

    @Test("One layer reads exactly as it did before, so the fields do not change meaning when a selection shrinks")
    func oneLayerReadsPlainly() {
        let frame = CGRect(x: 12, y: 34, width: 296, height: 118)
        let sel = selection([frame])
        #expect(sel.count == 1)
        #expect(sel.reading(.x) == .agreed(12))
        #expect(sel.reading(.height) == .agreed(118))
    }

    @Test("A field no selected layer takes has nothing to show")
    func unavailableFieldReadsEmpty() {
        let box = CGRect(x: 0, y: 0, width: 40, height: 40)
        let sel = LayerGeometrySelection([member(arrow(box), box)])
        #expect(sel.reading(.width) == .empty)
        #expect(!sel.allows(.width))
        #expect(sel.fixedReason(for: .width) == LayerGeometryEditing.endpointReason)
    }

    @Test("A field only some layers take reads over just those layers")
    func partialFieldReadsItsOwnLayers() {
        let box = CGRect(x: 0, y: 0, width: 999, height: 40)
        let rect = CGRect(x: 0, y: 0, width: 120, height: 40)
        let sel = LayerGeometrySelection([member(rectangle(rect), rect),
                                          member(arrow(box), box)])
        #expect(sel.reading(.width) == .agreed(120))
        #expect(sel.allows(.width))
        #expect(sel.note(for: .width) == "Applies to 1 of the 2 selected layers.")
        #expect(sel.note(for: .x) == nil)
    }

    @Test("Locked layers take nothing, so tidying the buttons never slides the picture underneath")
    func lockedLayersTakeNothing() {
        let frame = CGRect(x: 5, y: 5, width: 50, height: 50)
        let sel = LayerGeometrySelection([member(rectangle(frame, locked: true), frame)])
        #expect(!sel.allows(.x))
        #expect(sel.fixedReason(for: .x) == LayerGeometryEditing.lockedReason)
    }

    // MARK: Typing

    @Test("Typing a width sets every selected layer to that width")
    func typingWidthSetsEveryLayer() {
        let a = CGRect(x: 0, y: 0, width: 80, height: 32)
        let b = CGRect(x: 0, y: 40, width: 140, height: 32)
        let sel = selection([a, b])
        let moves = sel.applying(120, to: .width)
        #expect(moves.count == 2)
        #expect(Set(moves.values.map(\.width)) == [120])
        #expect(Set(moves.values.map(\.height)) == [32])
    }

    @Test("Typing an X lines every selected layer up on that left edge")
    func typingXLinesLayersUp() {
        let a = CGRect(x: 10, y: 0, width: 80, height: 32)
        let b = CGRect(x: 90, y: 40, width: 140, height: 32)
        let sel = selection([a, b])
        let moves = sel.applying(24, to: .x)
        #expect(Set(moves.values.map(\.minX)) == [24])
        // ...and nothing else about them changed.
        #expect(Set(moves.values.map(\.width)) == [80, 140])
        #expect(Set(moves.values.map(\.minY)) == [0, 40])
    }

    @Test("Layers already at the typed number are left out, so a no-op edit costs no undo step")
    func unchangedLayersAreLeftOut() {
        let a = CGRect(x: 24, y: 0, width: 80, height: 32)
        let b = CGRect(x: 90, y: 40, width: 80, height: 32)
        let sel = selection([a, b])
        #expect(sel.applying(24, to: .x).count == 1)
        #expect(sel.applying(80, to: .width).isEmpty)
    }

    @Test("A typed size is clamped for every layer the same way one layer is")
    func typedSizeIsClamped() {
        let a = CGRect(x: 0, y: 0, width: 80, height: 32)
        let b = CGRect(x: 0, y: 40, width: 140, height: 32)
        let sel = selection([a, b])
        #expect(Set(sel.applying(0, to: .width).values.map(\.width)) == [LayerGeometry.minimumSide])
    }

    @Test("Layers that do not take the field are never touched by it")
    func fixedLayersAreNeverTouched() {
        let rect = CGRect(x: 0, y: 0, width: 120, height: 40)
        let box = CGRect(x: 0, y: 0, width: 999, height: 40)
        let head = rectangle(rect)
        let tail = arrow(box)
        let sel = LayerGeometrySelection([member(head, rect), member(tail, box)])
        let moves = sel.applying(60, to: .width)
        #expect(Array(moves.keys) == [head.id])
        #expect(moves[tail.id] == nil)
    }

    // MARK: Stepping

    @Test("An arrow key steps every selected layer together, keeping what is different about them")
    func steppingKeepsDifferences() {
        let a = CGRect(x: 10, y: 0, width: 80, height: 32)
        let b = CGRect(x: 90, y: 40, width: 80, height: 32)
        let sel = selection([a, b])
        let moves = sel.stepping(.x, direction: 1, coarse: false)
        #expect(Set(moves.values.map(\.minX)) == [11, 91])
    }

    @Test("Shift steps every selected layer by ten")
    func coarseStepping() {
        let a = CGRect(x: 10, y: 0, width: 80, height: 32)
        let b = CGRect(x: 90, y: 40, width: 80, height: 32)
        let sel = selection([a, b])
        #expect(Set(sel.stepping(.x, direction: -1, coarse: true).values.map(\.minX)) == [0, 80])
    }

    @Test("Stepping walks from the whole number on screen, not from a fraction a drag left behind")
    func steppingRoundsFirst() {
        let frame = CGRect(x: 10.4, y: 0, width: 80, height: 32)
        let sel = selection([frame])
        #expect(Set(sel.stepping(.x, direction: 1, coarse: false).values.map(\.minX)) == [11])
    }

    @Test("Nothing at all is stepped when no layer takes the field")
    func steppingAFixedFieldDoesNothing() {
        let box = CGRect(x: 0, y: 0, width: 40, height: 40)
        let sel = LayerGeometrySelection([member(arrow(box), box)])
        #expect(sel.stepping(.width, direction: 1, coarse: false).isEmpty)
    }

    // MARK: What the section says

    @Test("An empty selection has nothing to say and takes nothing")
    func emptySelection() {
        let sel = LayerGeometrySelection([])
        #expect(sel.count == 0)
        #expect(sel.reading(.x) == .empty)
        #expect(!sel.allows(.x))
        #expect(sel.fixedReason(for: .x) == nil)
        #expect(sel.applying(10, to: .x).isEmpty)
    }

    // MARK: The floor each layer stops at

    private func text(_ frame: CGRect) -> Layer {
        Layer(name: "Text", content: .text(TextContent(string: "hi")), frame: frame)
    }

    /// A text member as the panel builds one: the field speaks the WORDS, and
    /// the empty room a measured text box carries on its far edges rides along
    /// so whatever is typed comes back as the box to store.
    private func textMember(_ words: CGRect) -> (Layer, LayerGeometrySelection.Member) {
        let label = text(CGRect(x: words.minX, y: words.minY,
                                width: words.width + TextMeasurement.slack,
                                height: words.height + TextMeasurement.slack))
        return (label, LayerGeometrySelection.Member(id: label.id, frame: words,
                                                     editing: LayerGeometryEditing(layer: label),
                                                     slack: label.boxSlack))
    }

    @Test("A typed width on a text box stops where dragging its edge stops")
    func typedTextWidthStopsAtTheCanvasFloor() {
        let (label, member) = textMember(CGRect(x: 0, y: 0, width: 200, height: 30))
        let sel = LayerGeometrySelection([member])
        #expect(sel.applying(12, to: .width)[label.id]?.width
                == TextMeasurement.minimumContentWidth + TextMeasurement.slack)
    }

    @Test("Each layer stops at its own floor, so one number can land differently on two of them")
    func eachLayerKeepsItsOwnFloor() {
        let box = CGRect(x: 0, y: 0, width: 200, height: 40)
        let rect = rectangle(box)
        let (label, words) = textMember(CGRect(x: 0, y: 60, width: 200, height: 30))
        let sel = LayerGeometrySelection([member(rect, box), words])
        let moves = sel.applying(12, to: .width)
        #expect(moves[rect.id]?.width == 12)
        #expect(moves[label.id]?.width
                == TextMeasurement.minimumContentWidth + TextMeasurement.slack)
    }

    @Test("An arrow key cannot step a text box below its floor")
    func steppingStopsAtTheFloor() {
        let (_, words) = textMember(CGRect(x: 0, y: 0,
                                           width: TextMeasurement.minimumContentWidth, height: 30))
        let sel = LayerGeometrySelection([words])
        #expect(sel.stepping(.width, direction: -1, coarse: false).isEmpty)
    }

    // MARK: What the field shows afterwards

    @Test("The field reads back what the layers took, not what was typed")
    func landingIsWhatTheLayersTook() {
        let (_, words) = textMember(CGRect(x: 0, y: 0, width: 200, height: 30))
        let sel = LayerGeometrySelection([words])
        #expect(sel.landing(12, in: .width) == .agreed(TextMeasurement.minimumContentWidth))
        #expect(sel.landing(296, in: .width) == .agreed(296))
    }

    @Test("One number that lands differently on two layers reads as Mixed")
    func landingOnDifferentFloorsIsMixed() {
        let box = CGRect(x: 0, y: 0, width: 200, height: 40)
        let words = CGRect(x: 0, y: 60, width: 200, height: 30)
        let sel = LayerGeometrySelection([member(rectangle(box), box), member(text(words), words)])
        #expect(sel.landing(12, in: .width) == .mixed)
        #expect(sel.landing(300, in: .width) == .agreed(300))
    }

    @Test("A field no layer takes has nothing to read back")
    func landingOnAFixedFieldIsEmpty() {
        let box = CGRect(x: 0, y: 0, width: 100, height: 40)
        let sel = LayerGeometrySelection([member(arrow(box), box)])
        #expect(sel.landing(60, in: .width) == .empty)
    }

    // MARK: Numbers you can read but not type

    @Test("A text box shows how tall it turned out, even though the height cannot be typed")
    func textHeightIsReadableWithoutBeingTypeable() {
        let words = CGRect(x: 0, y: 0, width: 200, height: 74)
        let sel = LayerGeometrySelection([member(text(words), words)])
        #expect(sel.reading(.height) == .agreed(74))
        #expect(!sel.allows(.height))
        #expect(sel.fixedReason(for: .height) == LayerGeometryEditing.textHeightReason)
    }

    @Test("Two text boxes of different heights read as Mixed, the same as any other field would")
    func textHeightsThatDifferReadMixed() {
        let a = CGRect(x: 0, y: 0, width: 200, height: 74)
        let b = CGRect(x: 0, y: 90, width: 200, height: 40)
        let sel = LayerGeometrySelection([member(text(a), a), member(text(b), b)])
        #expect(sel.reading(.height) == .mixed)
        #expect(LayerGeometrySelection([member(text(a), a),
                                        member(text(a), a)]).reading(.height) == .agreed(74))
    }

    @Test("A locked layer still says where it is and how big it is")
    func lockedLayerStillReadsItsNumbers() {
        let frame = CGRect(x: 5, y: 6, width: 50, height: 60)
        let sel = LayerGeometrySelection([member(rectangle(frame, locked: true), frame)])
        #expect(sel.reading(.x) == .agreed(5))
        #expect(sel.reading(.width) == .agreed(50))
        #expect(!sel.allows(.width))
    }

    @Test("A shape dragged by its ends still shows nothing, because its box is padding and not the shape")
    func endpointShapesStayBlank() {
        let box = CGRect(x: 0, y: 0, width: 100, height: 40)
        let sel = LayerGeometrySelection([member(arrow(box), box)])
        #expect(sel.reading(.width) == .empty)
        #expect(sel.reading(.height) == .empty)
        // ...but where it sits is still a real number.
        #expect(sel.reading(.x) == .agreed(0))
    }

    @Test("A number only some of the selected layers could show is shown for none of them")
    func aReadOnlyNumberSpeaksForEveryoneOrNobody() {
        let words = CGRect(x: 0, y: 0, width: 200, height: 74)
        let box = CGRect(x: 0, y: 0, width: 200, height: 74)
        let sel = LayerGeometrySelection([member(text(words), words), member(arrow(box), box)])
        #expect(sel.reading(.height) == .empty)
    }

    @Test("A number worked out for you is read only, and the one beside it you type is not")
    func aWorkedOutNumberIsReadOnly() {
        let words = CGRect(x: 0, y: 0, width: 200, height: 74)
        let sel = LayerGeometrySelection([member(text(words), words)])
        #expect(sel.isReadOnly(.height))
        #expect(!sel.isReadOnly(.width))
        #expect(!sel.isReadOnly(.x))
    }

    @Test("Every number on a locked layer is read only, not just its size")
    func aLockedLayerIsReadOnlyAllTheWayThrough() {
        let frame = CGRect(x: 5, y: 6, width: 50, height: 60)
        let sel = LayerGeometrySelection([member(rectangle(frame, locked: true), frame)])
        #expect(LayerGeometryField.allCases.allSatisfy { sel.isReadOnly($0) })
    }

    @Test("A field with no number to show is still read only, so it does not look like one you can type into")
    func aBlankFieldIsStillReadOnly() {
        let box = CGRect(x: 0, y: 0, width: 100, height: 40)
        let sel = LayerGeometrySelection([member(arrow(box), box)])
        #expect(sel.reading(.width) == .empty)
        #expect(sel.isReadOnly(.width))
    }

    @Test("Nothing selected is an empty panel, not a panel full of fields you cannot type into")
    func nothingSelectedIsNotReadOnly() {
        let sel = LayerGeometrySelection([])
        #expect(LayerGeometryField.allCases.allSatisfy { !sel.isReadOnly($0) })
        #expect(LayerGeometryField.allCases.allSatisfy { sel.explanation(for: $0) == nil })
    }

    @Test("Clicking a number you cannot type answers with the sentence the hover tip carries")
    func aReadOnlyFieldAnswersAClick() {
        let words = CGRect(x: 0, y: 0, width: 200, height: 74)
        let sel = LayerGeometrySelection([member(text(words), words)])
        #expect(sel.explanation(for: .height) == LayerGeometryEditing.textHeightReason)
        #expect(sel.explanation(for: .width) == nil)
    }

    @Test("Every field that takes no typing has an answer ready, whatever took it away")
    func everyReadOnlyFieldHasAnAnswer() {
        let frame = CGRect(x: 5, y: 6, width: 50, height: 60)
        let locked = LayerGeometrySelection([member(rectangle(frame, locked: true), frame)])
        for field in LayerGeometryField.allCases {
            #expect(locked.explanation(for: field) == LayerGeometryEditing.lockedReason)
        }
        let box = CGRect(x: 0, y: 0, width: 100, height: 40)
        let ends = LayerGeometrySelection([member(arrow(box), box)])
        #expect(ends.explanation(for: .width) == LayerGeometryEditing.endpointReason)
        #expect(ends.explanation(for: .x) == nil)
    }

    @Test("A field some layer takes still reads over just those layers, not the ones sitting out")
    func typeableFieldsIgnoreTheReadOnlyOnes() {
        let box = CGRect(x: 0, y: 0, width: 120, height: 40)
        let words = CGRect(x: 0, y: 60, width: 200, height: 74)
        let sel = LayerGeometrySelection([member(rectangle(box), box), member(text(words), words)])
        #expect(sel.reading(.height) == .agreed(40))
        #expect(sel.allows(.height))
    }

    @Test("The hover tip says where a width stops, so a number that changes on its own is explained")
    func theTipNamesTheFloor() {
        let words = CGRect(x: 0, y: 0, width: 200, height: 30)
        let sel = LayerGeometrySelection([member(text(words), words)])
        let note = sel.note(for: .width)
        #expect(note?.contains("80") == true)
        let box = CGRect(x: 0, y: 0, width: 200, height: 40)
        #expect(LayerGeometrySelection([member(rectangle(box), box)]).note(for: .width) == nil)
    }

    // MARK: The line under the fields

    @Test("One layer's caption says what the numbers mean and how to step them")
    func oneLayerCaptionExplainsTheNumbers() {
        let frame = CGRect(x: 12, y: 34, width: 296, height: 118)
        #expect(selection([frame]).caption
                == "\(LayerGeometry.unitSuffix) from the top left. Up or down arrow steps by 1, Shift by 10.")
    }

    @Test("A locked layer's caption says it is locked, where you are already looking")
    func aLockedLayerSaysSoInTheCaption() {
        let frame = CGRect(x: 12, y: 34, width: 296, height: 118)
        let sel = LayerGeometrySelection([member(rectangle(frame, locked: true), frame)])
        #expect(sel.isLocked)
        // The same sentence the hover tip gives, so the panel says one thing.
        #expect(sel.caption == LayerGeometryEditing.lockedReason)
    }

    @Test("Unlocking the layer puts the ordinary caption straight back")
    func unlockingRestoresTheOrdinaryCaption() {
        let frame = CGRect(x: 12, y: 34, width: 296, height: 118)
        var layer = rectangle(frame, locked: true)
        #expect(LayerGeometrySelection([member(layer, frame)]).isLocked)
        layer.isLocked = false
        let sel = LayerGeometrySelection([member(layer, frame)])
        #expect(!sel.isLocked)
        #expect(sel.caption == selection([frame]).caption)
    }

    @Test("Several layers still say that one number lands on all of them")
    func manyLayersKeepTheirOwnCaption() {
        let sel = selection([CGRect(x: 0, y: 0, width: 120, height: 32),
                             CGRect(x: 0, y: 40, width: 120, height: 32)])
        #expect(!sel.isLocked)
        #expect(sel.caption.hasPrefix("2 layers, all at once."))
        #expect(sel.caption.contains("Shift by 10"))
    }

    @Test("A selection that is locked all the way through says so once, not per layer")
    func everyLayerLockedSaysSoOnce() {
        let a = CGRect(x: 0, y: 0, width: 120, height: 32)
        let b = CGRect(x: 0, y: 40, width: 120, height: 32)
        let sel = LayerGeometrySelection([member(rectangle(a, locked: true), a),
                                          member(rectangle(b, locked: true), b)])
        #expect(sel.isLocked)
        #expect(sel.caption
                == "2 locked layers. Unlock them in the Layers list to change their position or size.")
    }

    @Test("One locked layer among unlocked ones leaves the caption alone, because the fields still work")
    func aPartlyLockedSelectionKeepsTheOrdinaryCaption() {
        let a = CGRect(x: 0, y: 0, width: 120, height: 32)
        let b = CGRect(x: 0, y: 40, width: 120, height: 32)
        let sel = LayerGeometrySelection([member(rectangle(a, locked: true), a),
                                          member(rectangle(b), b)])
        #expect(!sel.isLocked)
        #expect(sel.caption.hasPrefix("2 layers, all at once."))
    }

    @Test("A layer a stack owns is not locked, so its caption is the ordinary one")
    func aStackedLayerIsNotLocked() {
        let frame = CGRect(x: 0, y: 0, width: 40, height: 20)
        let child = rectangle(frame)
        var content = GroupContent(children: [child])
        content.layout = GroupLayout(kind: .stack)
        let stack = Layer(name: "Group", content: .group(content), frame: .zero)
        let editing = LayerGeometryEditing(layer: child, in: stack)
        let sel = LayerGeometrySelection([
            LayerGeometrySelection.Member(id: child.id, frame: frame, editing: editing)])
        #expect(!editing.allows(.x))
        #expect(!sel.isLocked)
        #expect(sel.caption == selection([frame]).caption)
    }

    @Test("Nothing selected reads as nothing, and the caption stays the plain one")
    func anEmptySelectionIsNotLocked() {
        let sel = LayerGeometrySelection([])
        #expect(!sel.isLocked)
        #expect(sel.caption == selection([CGRect(x: 0, y: 0, width: 1, height: 1)]).caption)
    }
}
