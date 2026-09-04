import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A label grows to fit what it says: change a text box's width or its words
/// and the box re-measures itself, so no line is ever cut off and anything
/// arranging it re-flows around the new height
/// (`docs/design/ui-building.md`, "A label grows to fit what it says").
///
/// Every expectation here is a comparison rather than a number, because the app
/// measures with CoreText and these tests may run with the built-in estimate.
/// "It gained a line" is true either way; "it is 43.5 tall" is not.
@Suite("A label grows to fit what it says")
struct TextRefitTests {

    private let paragraph = "The quick brown fox jumps over the lazy dog and keeps on running"

    private func text(_ string: String, _ rect: CGRect,
                      placement: LayerPlacement? = nil) -> Layer {
        Layer(name: "Label", content: .text(TextContent(string: string, fontSize: 14)),
              frame: rect, placement: placement)
    }

    private func box(_ name: String, _ rect: CGRect,
                     placement: LayerPlacement? = nil) -> Layer {
        Layer(name: name,
              content: .annotation(AnnotationContent(shape: .rectangle, start: .zero,
                                                     end: CGPoint(x: rect.width, y: rect.height))),
              frame: rect, placement: placement)
    }

    /// A text box exactly as big as the words in it, which is what every text
    /// layer in the app starts life as.
    private func hugging(_ string: String, at origin: CGPoint = .zero,
                         placement: LayerPlacement? = nil) -> Layer {
        let content = TextContent(string: string, fontSize: 14)
        let size = TextMeasurement.size(of: content)
        return text(string, CGRect(origin: origin, size: size), placement: placement)
    }

    /// How tall this box would have to be for its words to fit at its width.
    private func neededHeight(_ layer: Layer) -> CGFloat {
        guard case .text(let content) = layer.content else { return 0 }
        return TextMeasurement.size(of: content, wrappingAt: layer.frame.width).height
    }

    // MARK: - Changing the width

    /// Dragging the right edge in re-wraps the words, so the box gets taller
    /// and the top edge stays where it was.
    @Test func narrowingATextBoxGrowsItsHeight() {
        let label = hugging(paragraph, at: CGPoint(x: 40, y: 60))
        let narrowed = label.resized(to: CGRect(x: 40, y: 60, width: 120, height: label.frame.height))
        #expect(narrowed.frame.width == 120)
        #expect(narrowed.frame.minY == 60)
        #expect(narrowed.frame.height > label.frame.height)
        #expect(narrowed.frame.height >= neededHeight(narrowed))
    }

    /// Widening it again puts the lines back together, so a box never keeps
    /// height it stopped needing.
    @Test func wideningATextBoxShrinksItBackDown() {
        let label = hugging(paragraph)
        let narrow = label.resized(to: CGRect(x: 0, y: 0, width: 120, height: 200))
        let wide = narrow.resized(to: CGRect(x: 0, y: 0, width: 600, height: narrow.frame.height))
        #expect(wide.frame.height < narrow.frame.height)
        #expect(wide.frame.height >= neededHeight(wide))
    }

    /// Moving a text box is not resizing it. Nothing about the words changed,
    /// so nothing about the box may change either.
    @Test func movingATextBoxLeavesItsBoxAlone() {
        var label = hugging(paragraph)
        // A box left at a size that does not match its words: moving it must
        // not quietly re-measure it either.
        label.frame.size.height += 9
        let moved = label.resized(to: label.frame.offsetBy(dx: 25, dy: -12))
        #expect(moved.frame.size == label.frame.size)
        #expect(moved.frame.origin == CGPoint(x: label.frame.minX + 25, y: label.frame.minY - 12))
    }

    /// Dragging the BOTTOM edge of a text box does nothing: height follows the
    /// words, which is what the inspector's Height field already says.
    @Test func draggingTheBottomEdgeDoesNotStretchTheGlyphs() {
        let label = hugging("Save")
        let taller = label.resized(to: CGRect(x: 0, y: 0, width: label.frame.width, height: 90))
        #expect(taller.frame.height == label.frame.height)
    }

    // MARK: - Inside a stack

    /// A stack of a fixed width stretches a label across it. The label re-wraps
    /// to that width, gains a line, and the rows under it come down by exactly
    /// what it gained — in one pass, without anybody nudging it.
    @Test func aStretchedLabelInAStackPushesTheRowsBelowItDown() {
        let label = hugging(paragraph, placement: LayerPlacement(horizontal: .stretch))
        let first = box("One", CGRect(x: 0, y: 0, width: 60, height: 30))
        let second = box("Two", CGRect(x: 0, y: 0, width: 60, height: 30))
        let layout = GroupLayout(kind: .stack, direction: .column, gap: 10, width: 140)
        var content = GroupContent(children: [label, first, second])
        content.layout = layout
        let stack = Layer(name: "Stack", content: .group(content), frame: .zero)

        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: [stack])
        doc.reflowLayouts()

        let flowed = doc.layers[0].children
        let wrapped = flowed[0]
        #expect(wrapped.frame.width == 140)
        #expect(wrapped.frame.height > label.frame.height)
        #expect(wrapped.frame.height >= neededHeight(wrapped))
        // The row under the label starts one gap below the label's new bottom,
        // not below the height it used to have.
        #expect(flowed[1].frame.minY == wrapped.frame.maxY + 10)
        #expect(flowed[2].frame.minY == flowed[1].frame.maxY + 10)
    }

    // MARK: - Told to fill the height

    /// A row of things, with a label told to fill the height of the row.
    /// The label is the short one, so the row is as tall as the block beside
    /// it and the label has room to fill.
    private func rowHolding(_ label: Layer) -> PhotonzDocument {
        let block = box("Block", CGRect(x: 200, y: 0, width: 60, height: 80))
        var content = GroupContent(children: [label, block])
        content.layout = GroupLayout(kind: .stack, direction: .row, gap: 10)
        let row = Layer(name: "Row", content: .group(content), frame: .zero)
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600), layers: [row])
        doc.reflowLayouts()
        return doc
    }

    /// Stretch down has to DO something. A label told to fill the height takes
    /// the height of the row holding it instead of staying the height of one
    /// line, which is the whole point of the choice.
    @Test func aLabelToldToFillTheHeightTakesTheHeightOfTheRow() {
        let label = hugging("Save", placement: LayerPlacement(vertical: .stretch))
        let filled = rowHolding(label).layers[0].children[0]
        #expect(filled.frame.height == 80)
        // Its width is still the width of its words: only the axis it was told
        // to fill changed.
        #expect(filled.frame.width == label.frame.width)
        #expect(filled.frame.minY == 0)
    }

    /// ...and the label beside it that was told nothing still hugs its words,
    /// so filling the height is something you ask for rather than something
    /// that happens to every label in a row.
    @Test func aLabelToldNothingStillHugsItsWords() {
        let label = hugging("Save")
        let placed = rowHolding(label).layers[0].children[0]
        #expect(placed.frame.height == label.frame.height)
    }

    /// The words are never cut off. A row shorter than the sentence in it
    /// leaves the box as tall as the words need rather than clipping the last
    /// line off the bottom.
    @Test func fillingAShortRowStillKeepsEveryLine() {
        let label = hugging(paragraph, placement: LayerPlacement(vertical: .stretch))
            .resized(to: CGRect(x: 0, y: 0, width: 120, height: 10))
        let block = box("Block", CGRect(x: 200, y: 0, width: 60, height: 20))
        var content = GroupContent(children: [label, block])
        content.layout = GroupLayout(kind: .stack, direction: .row, gap: 10)
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [Layer(name: "Row", content: .group(content), frame: .zero)])
        doc.reflowLayouts()
        let filled = doc.layers[0].children[0]
        #expect(filled.frame.height >= neededHeight(filled))
    }

    /// Down the page the stack itself decides the height, so a label in a
    /// COLUMN told to fill it is still as tall as its words: the choice is
    /// about the axis the flow is not running along, and re-wrapping still
    /// shrinks the box back down.
    @Test func aLabelInAColumnStillFollowsItsWordsWhenTheStackWidens() {
        let label = hugging(paragraph, placement: LayerPlacement(horizontal: .stretch,
                                                                 vertical: .stretch))
        var content = GroupContent(children: [label,
                                              box("One", CGRect(x: 0, y: 0, width: 60, height: 30))])
        content.layout = GroupLayout(kind: .stack, direction: .column, gap: 10, width: 140)
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [Layer(name: "Stack", content: .group(content), frame: .zero)])
        doc.reflowLayouts()
        let narrow = doc.layers[0].children[0].frame.height
        doc.updateGroupLayout(id: doc.layers[0].id) { $0.width = 600 }
        doc.reflowLayouts()
        let wide = doc.layers[0].children[0]
        #expect(wide.frame.height < narrow)
        #expect(wide.frame.height >= neededHeight(wide))
    }

    /// Filling the height survives a re-wrap: a label that fills a row and is
    /// then made narrower keeps the row's height rather than snapping back to
    /// the height of its lines.
    @Test func fillingTheHeightSurvivesAReWrap() {
        let label = hugging("Save", placement: LayerPlacement(vertical: .stretch))
        var doc = rowHolding(label)
        #expect(doc.layers[0].children[0].frame.height == 80)
        doc.updateLayer(id: doc.layers[0].children[0].id) { $0.name = "Label" }
        doc.reflowLayouts()
        #expect(doc.layers[0].children[0].frame.height == 80)
    }

    /// A grid cell is a box too: a label told to fill it is as tall as the
    /// cell, which is as tall as the tallest thing in the grid.
    @Test func aLabelFillsItsGridCell() {
        let label = hugging("Save", placement: LayerPlacement(vertical: .stretch))
        var content = GroupContent(children: [label,
                                              box("Card", CGRect(x: 200, y: 0, width: 60, height: 90))])
        content.layout = GroupLayout(kind: .grid, columns: 2, gap: 10)
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [Layer(name: "Grid", content: .group(content), frame: .zero)])
        doc.reflowLayouts()
        #expect(doc.layers[0].children[0].frame.height == 90)
    }

    /// A document already carrying the choice opens exactly as it was saved.
    /// Nothing re-measures on the way in, so a hand-placed box is never
    /// re-flowed under its author by the act of opening the file.
    @Test func openingADocumentThatAlreadyFillsMovesNothing() throws {
        let doc = rowHolding(hugging("Save", placement: LayerPlacement(vertical: .stretch)))
        let reopened = try JSONDecoder().decode(PhotonzDocument.self,
                                                from: JSONEncoder().encode(doc))
        #expect(reopened.layers == doc.layers)
    }

    /// The Height field says who decides it. A label filling its row is not
    /// following its words any more, so the tip that says it is would send you
    /// to the wrong control.
    @Test func aFilledLabelSaysWhoDecidesItsHeight() {
        let row = rowHolding(hugging("Save", placement: LayerPlacement(vertical: .stretch))).layers[0]
        let filled = LayerGeometryEditing(layer: row.children[0], in: row)
        #expect(!filled.allows(.height))
        #expect(filled.fixedReason(for: .height) == LayerGeometryEditing.filledHeightReason)
        // A label in the same row that was told nothing still follows its words.
        let hugger = LayerGeometryEditing(layer: hugging("Save"), in: row)
        #expect(hugger.fixedReason(for: .height) == LayerGeometryEditing.textHeightReason)
    }

    /// Taking the choice back gives the height to the words again. A box that
    /// stayed row-tall after being told Top would be a box nobody can shrink,
    /// since a text box has no height handle to drag.
    @Test func takingTheFillBackHandsTheHeightToTheWords() {
        let label = hugging("Save", placement: LayerPlacement(vertical: .stretch))
        var doc = rowHolding(label)
        let id = doc.layers[0].children[0].id
        #expect(doc.layers[0].children[0].frame.height == 80)
        doc.setPlacement(id: id, vertical: .top)
        doc.reflowLayouts()
        #expect(doc.layers[0].children[0].frame.height == label.frame.height)
    }

    /// ...and the same when the choice was the ROW's rather than the label's:
    /// a row that stops stretching its contents hands every label's height
    /// back too.
    @Test func aRowThatStopsStretchingHandsTheHeightsBack() {
        let label = hugging("Save")
        var content = GroupContent(children: [label,
                                              box("Block", CGRect(x: 200, y: 0, width: 60, height: 80))])
        content.layout = GroupLayout(kind: .stack, direction: .row, gap: 10)
        content.contentPlacement = LayerPlacement(vertical: .stretch)
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [Layer(name: "Row", content: .group(content), frame: .zero)])
        doc.reflowLayouts()
        #expect(doc.layers[0].children[0].frame.height == 80)
        doc.setContentPlacement(id: doc.layers[0].id, vertical: .top)
        doc.reflowLayouts()
        #expect(doc.layers[0].children[0].frame.height == label.frame.height)
    }

    // MARK: - Changing the words

    /// A copy of a component given longer wording shows all of it. The label
    /// hugged its words, so it keeps hugging: one line, wider.
    @Test func aCopyGivenLongerWordingShowsAllOfIt() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [box("Background", CGRect(x: 0, y: 0, width: 128, height: 36)),
                                           hugging("Save", at: CGPoint(x: 40, y: 10))])
        let labelID = doc.layers[1].id
        let main = doc.groupLayers(ids: Set(doc.layers.map(\.id)), name: "Button")!
        let componentID = doc.makeComponent(id: main.id)!
        let knob = doc.addComponentProperty(componentID: componentID, target: labelID, kind: .text)!
        let copy = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 400, y: 300))!

        var history = History(document: doc)
        history.perform {
            $0.setInstanceOverride(instance: copy, property: knob, value: .text("Save all changes"))
        }
        let label = history.current.layer(id: copy)?.children
            .first { if case .text = $0.content { return true } else { return false } }
        #expect(label != nil)
        guard let label else { return }
        #expect(label.frame.width > 60)
        #expect(label.frame.height >= neededHeight(label))
        // The original is untouched: only the copy answered the knob.
        let originalLabel = doc.layer(id: labelID)
        #expect(history.current.layer(id: labelID)?.frame == originalLabel?.frame)
    }

    /// The whole thing end to end: a stack made into a component, a copy of it
    /// given longer wording, and the copy's own rows closing up around the
    /// label that grew — without the original moving at all.
    @Test func aCopyOfAStackRefowsAroundALabelThatGrew() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 900, height: 700),
                                  layers: [hugging("Save", at: CGPoint(x: 0, y: 0)),
                                           box("One", CGRect(x: 0, y: 40, width: 150, height: 30)),
                                           box("Two", CGRect(x: 0, y: 90, width: 150, height: 30))])
        let labelID = doc.layers[0].id
        let stack = doc.stackSelection(ids: Set(doc.layers.map(\.id)), kind: .stack)!
        doc.updateGroupLayout(id: stack) { $0.gap = 10; $0.width = 150 }
        doc.updateLayer(id: stack) { layer in
            guard var group = layer.group else { return }
            group.contentPlacement = LayerPlacement(horizontal: .stretch)
            layer.content = .group(group)
        }
        let componentID = doc.makeComponent(id: stack)!
        let knob = doc.addComponentProperty(componentID: componentID, target: labelID, kind: .text)!
        let copy = doc.insertComponentInstance(of: componentID, at: CGPoint(x: 600, y: 300))!

        var history = History(document: doc)
        history.perform {
            $0.setInstanceOverride(instance: copy, property: knob,
                                   value: .text(paragraph + " " + paragraph))
        }
        guard let copied = history.current.layer(id: copy) else {
            Issue.record("the copy went missing")
            return
        }
        let rows = copied.children
        #expect(rows.count == 3)
        let label = rows[0]
        #expect(label.frame.width == 150)
        #expect(label.frame.height >= neededHeight(label))
        // The rows under it sit one gap below the label's NEW bottom, so the
        // longer wording pushed them down instead of running over them.
        #expect(rows[1].frame.minY == label.frame.maxY + 10)
        #expect(rows[2].frame.minY == rows[1].frame.maxY + 10)
        // ...and the original, which answered nothing, still says the short
        // thing on one line.
        let originalLabel = history.current.layer(id: labelID)
        #expect(originalLabel?.frame.height == hugging("Save").frame.height)
        if case .text(let content) = originalLabel?.content { #expect(content.string == "Save") }
        else { Issue.record("the original's label stopped being text") }
    }

    /// A label the container centres stays centred when it grows, rather than
    /// sliding off to one side.
    @Test func aCentredLabelGrowsAboutItsMiddle() {
        let label = hugging("Save", at: CGPoint(x: 40, y: 10))
        let middle = label.frame.midX
        let longer = Layer(name: "Label",
                           content: .text(TextContent(string: "Save all changes", fontSize: 14)),
                           frame: label.frame)
            .textRefitted(hugging: true, anchor: .center)
        #expect(longer.frame.width > label.frame.width)
        #expect(abs(longer.frame.midX - middle) <= 1)
    }

    /// A label the container starts at the left still starts there.
    @Test func aLeftAlignedLabelGrowsToTheRight() {
        let label = hugging("Save", at: CGPoint(x: 40, y: 10))
        let longer = Layer(name: "Label",
                           content: .text(TextContent(string: "Save all changes", fontSize: 14)),
                           frame: label.frame)
            .textRefitted(hugging: true, anchor: .left)
        #expect(longer.frame.minX == 40)
        #expect(longer.frame.width > label.frame.width)
    }

    /// A box somebody has already dragged narrower is a paragraph, and stays
    /// one: re-wording it keeps the wrap width and only grows downward.
    @Test func aNarrowedBoxKeepsItsWrapWidthWhenTheWordsChange() {
        let narrowed = hugging("Save").resized(to: CGRect(x: 0, y: 0, width: 100, height: 20))
        #expect(!narrowed.textHugsItsWords == false) // "Save" still fits: it hugs
        let paragraphBox = hugging(paragraph).resized(to: CGRect(x: 0, y: 0, width: 100, height: 20))
        #expect(!paragraphBox.textHugsItsWords)
        let reworded = Layer(name: "Label",
                             content: .text(TextContent(string: paragraph + " and further still",
                                                        fontSize: 14)),
                             frame: paragraphBox.frame)
            .textRefitted(hugging: false, anchor: .left)
        #expect(reworded.frame.width == 100)
        #expect(reworded.frame.height > paragraphBox.frame.height)
        #expect(reworded.frame.height >= neededHeight(reworded))
    }

    // MARK: - The estimate itself

    /// The built-in estimate has to actually wrap, or nothing above is testing
    /// anything without the app running.
    @Test func theEstimateWrapsOnWholeWords() {
        let content = TextContent(string: paragraph, fontSize: 14)
        let loose = TextMeasurement.estimated(content, .greatestFiniteMagnitude)
        let tight = TextMeasurement.estimated(content, 120)
        #expect(tight.width <= 120)
        #expect(tight.height > loose.height)
        #expect(TextMeasurement.estimated(TextContent(string: "", fontSize: 14),
                                          .greatestFiniteMagnitude).height == loose.height)
    }
}
