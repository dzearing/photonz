import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What a Border round a LABEL goes round: the letters, or the box the label
/// sits in. Every other layer has only a box, so the question is a label's
/// alone (`BorderFollows.swift`).
@Suite("What a border follows")
struct BorderFollowsTests {

    private func label(_ string: String = "Ship it") -> Layer {
        Layer(name: "Label",
              content: .text(TextContent(string: string, fontSize: 24, colorHex: "#FFFFFF")),
              frame: CGRect(x: 10, y: 10, width: 200, height: 40))
    }

    private func box() -> Layer {
        Layer(name: "Box",
              content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 0,
                                                     start: .zero,
                                                     end: CGPoint(x: 100, y: 60))),
              frame: CGRect(x: 10, y: 10, width: 100, height: 60))
    }

    /// A border arrives round the LETTERS, which is what a border on type has
    /// always meant here and what a caption over a screenshot wants.
    @Test func aNewBorderFollowsTheLetters() {
        #expect(BorderEffect().follows == .letters)
    }

    /// A file written before the choice existed says nothing about it, and its
    /// letter outline has to open as a letter outline.
    @Test func aSavedBorderWithNoAnswerFollowsTheLetters() throws {
        let old = ##"{"width":4,"colorHex":"#000000","position":"outside","isOn":true}"##
        let border = try JSONDecoder().decode(BorderEffect.self, from: Data(old.utf8))
        #expect(border.follows == .letters)
        #expect(border.width == 4)
    }

    @Test func aBoxBorderSurvivesBeingSavedAndOpened() throws {
        var border = BorderEffect(width: 3)
        border.follows = .box
        let data = try JSONEncoder().encode(border)
        #expect(try JSONDecoder().decode(BorderEffect.self, from: data) == border)
    }

    /// Nothing is written for the ordinary answer, so a label bordered today
    /// still draws its outline in a build that has never heard of the choice.
    @Test func onlyTheBoxAnswerIsWrittenDown() throws {
        let written = String(decoding: try JSONEncoder().encode(BorderEffect()), as: UTF8.self)
        #expect(!written.contains("follows"))
    }

    /// The split the renderer draws from: one ring baked round the letters, one
    /// drawn round the frame, and a label can wear both at once.
    @Test func aLabelCanWearOneOfEach() {
        var letters = BorderEffect(width: 6, colorHex: "#000000")
        letters.follows = .letters
        var frame = BorderEffect(width: 2, colorHex: "#FF0000")
        frame.follows = .box
        var label = label()
        label.style.effects = [.border(letters), .border(frame)]

        #expect(label.letterBorders.map(\.width) == [6])
        #expect(label.boxBorders.map(\.width) == [2])
    }

    /// A ring that is switched off, or nought wide, is in neither list: the
    /// same rule `paintedBorders` already follows.
    @Test func aBorderThatDrawsNothingIsInNeitherList() {
        var off = BorderEffect(width: 6)
        off.isOn = false
        var label = label()
        label.style.effects = [.border(off)]
        #expect(label.letterBorders.isEmpty)
        #expect(label.boxBorders.isEmpty)
    }

    /// Everything that is not a label has no letters for a ring to follow, so
    /// its borders all go round its box whatever they say.
    @Test func aShapeHasNoLettersSoEveryRingIsABox() {
        var letters = BorderEffect(width: 6)
        letters.follows = .letters
        var shape = box()
        shape.style.effects = [.border(letters)]
        #expect(!shape.hasLetters)
        #expect(shape.letterBorders.isEmpty)
        #expect(shape.boxBorders.map(\.width) == [6])
    }

    @Test func aLabelHasLetters() {
        #expect(label().hasLetters)
    }

    /// The row only ASKS the question of a label. A selection with a box in it
    /// gets no Follows popup, because a box has no letters for the answer to
    /// mean anything to.
    @Test func onlyASelectionOfLabelsIsAskedWhatItsBorderFollows() {
        let first = label(), second = label("Second"), shape = box()
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300),
                                  layers: [first, second, shape])
        #expect(doc.layerStyleSelection(layerIDs: [first.id]).hasLettersEverywhere)
        #expect(doc.layerStyleSelection(layerIDs: [first.id, second.id]).hasLettersEverywhere)
        #expect(!doc.layerStyleSelection(layerIDs: [first.id, shape.id]).hasLettersEverywhere)
        #expect(!doc.layerStyleSelection(layerIDs: [shape.id]).hasLettersEverywhere)
        #expect(!doc.layerStyleSelection(layerIDs: []).hasLettersEverywhere)
    }

    /// The word on the picker, so the row says which of the two it is without
    /// having to try it.
    @Test func eachAnswerHasAWordOfItsOwn() {
        #expect(BorderFollows.letters.title == "Letters")
        #expect(BorderFollows.box.title == "Box")
        #expect(BorderFollows.allCases.count == 2)
    }
}
