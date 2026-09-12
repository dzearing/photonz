import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The words and the model behind "how this layer mixes with what is under it".
///
/// The renderer's half of this is `PhotonzRenderTests/BlendModeTests`; this
/// suite is the list itself, the words a person reads, and what survives a
/// save, a duplicate, a group and an undo.
@Suite("Blend mode choice")
struct BlendModeChoiceTests {

    // MARK: - The list

    @Test func theListIsShortAndLedByNormal() {
        #expect(BlendMode.allCases == [.normal, .multiply, .screen, .darken, .lighten],
                "five modes, normal first: the list a person reads top to bottom")
    }

    @Test func everyModeHasAPlainNameAndAPlainSentence() {
        for mode in BlendMode.allCases {
            #expect(!mode.title.isEmpty)
            #expect(!mode.explanation.isEmpty, "\(mode) has no sentence saying what it does")
            // The sentence is for somebody who has never used Photoshop, so it
            // may not lean on the vocabulary they would have learned there.
            let jargon = ["multiply", "screen", "luminance", "channel", "alpha", "composite"]
            let words = mode.explanation.lowercased()
            for term in jargon {
                #expect(!words.contains(term),
                        "\(mode) explains itself with the word '\(term)'")
            }
            #expect(mode.explanation.hasSuffix("."), "\(mode)'s sentence is a sentence")
        }
    }

    @Test func titlesAreDistinct() {
        #expect(Set(BlendMode.allCases.map(\.title)).count == BlendMode.allCases.count)
    }

    // MARK: - Saving and opening

    @Test func everyModeRoundTripsThroughAStyle() throws {
        for mode in BlendMode.allCases {
            let data = try JSONEncoder().encode(LayerStyle(blendMode: mode))
            let back = try JSONDecoder().decode(LayerStyle.self, from: data)
            #expect(back.blendMode == mode)
        }
    }

    @Test func aModeThisBuildHasNeverHeardOfOpensAsNormal() throws {
        // A document written by a build with one more mode in the list must
        // still open. Before this the decode threw and took the whole file
        // with it.
        let json = #"{"opacity":1,"blendMode":"linearBurn"}"#
        let style = try JSONDecoder().decode(LayerStyle.self, from: Data(json.utf8))
        #expect(style.blendMode == .normal)
        #expect(style.opacity == 1, "the rest of the style still arrives")
    }

    @Test func aStyleWithNoModeAtAllOpensAsNormal() throws {
        let style = try JSONDecoder().decode(LayerStyle.self, from: Data(#"{"opacity":0.5}"#.utf8))
        #expect(style.blendMode == .normal)
    }

    // MARK: - What it survives

    private func document(mode: BlendMode) -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100))
        let layer = Layer(name: "Tint", content: .annotation(AnnotationContent(shape: .rectangle)),
                          frame: CGRect(x: 10, y: 10, width: 40, height: 40),
                          style: LayerStyle(blendMode: mode))
        doc.addLayer(layer)
        return (doc, layer.id)
    }

    @Test func aDuplicateKeepsTheMode() {
        var (doc, id) = document(mode: .multiply)
        let copies = doc.duplicateLayers(ids: [id])
        #expect(copies.count == 1)
        #expect(copies.first?.style.blendMode == .multiply)
    }

    @Test func groupingAndUngroupingKeepTheMode() {
        var (doc, id) = document(mode: .screen)
        var other = Layer(name: "Other", content: .annotation(AnnotationContent(shape: .rectangle)),
                          frame: CGRect(x: 60, y: 60, width: 20, height: 20))
        other.style.blendMode = .darken
        doc.addLayer(other)
        guard let groupID = doc.groupLayers(ids: [id, other.id])?.id else {
            Issue.record("grouping failed"); return
        }
        let inside = doc.layer(id: groupID)?.group?.children ?? []
        #expect(inside.first(where: { $0.id == id })?.style.blendMode == .screen)
        #expect(inside.first(where: { $0.id == other.id })?.style.blendMode == .darken)
        _ = doc.ungroupLayers(ids: [groupID])
        #expect(doc.layer(id: id)?.style.blendMode == .screen)
        #expect(doc.layer(id: other.id)?.style.blendMode == .darken)
    }

    @Test func undoPutsTheModeBack() {
        let (doc, id) = document(mode: .normal)
        var history = History(document: doc)
        history.perform { $0.updateLayer(id: id) { $0.style.blendMode = .multiply } }
        #expect(history.current.layer(id: id)?.style.blendMode == .multiply)
        history.undo()
        #expect(history.current.layer(id: id)?.style.blendMode == .normal)
        history.redo()
        #expect(history.current.layer(id: id)?.style.blendMode == .multiply)
    }

    @Test func oneStepReachesEveryPickedLayer() {
        var (doc, id) = document(mode: .normal)
        let second = Layer(name: "Second", content: .annotation(AnnotationContent(shape: .rectangle)),
                           frame: CGRect(x: 60, y: 10, width: 20, height: 20))
        doc.addLayer(second)
        var history = History(document: doc)
        history.perform { _ = $0.updateLayerStyles(layerIDs: [id, second.id]) { $0.blendMode = .screen } }
        #expect(history.current.layer(id: id)?.style.blendMode == .screen)
        #expect(history.current.layer(id: second.id)?.style.blendMode == .screen)
        history.undo()
        #expect(history.current.layer(id: id)?.style.blendMode == .normal)
        #expect(history.current.layer(id: second.id)?.style.blendMode == .normal)
    }

    // MARK: - The part that is not a plain choice

    @Test func aHighlightStillMixesWhateverItsStyleSays() {
        // The one layer whose mixing is not a free choice: a highlighter that
        // painted straight over the words would not be a highlighter. This is
        // why the panel leaves the row out for one and says so instead.
        var layer = Layer(name: "Mark",
                          content: .annotation(AnnotationContent(shape: .highlight)),
                          frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(layer.effectiveBlendMode == .multiply)
        layer.style.blendMode = .screen
        #expect(layer.effectiveBlendMode == .multiply)
    }

    @Test func aModeIsNotPlainStyling() {
        // A group with a mode of its own has something to do, so it draws as
        // one object rather than passing its children straight through.
        var style = LayerStyle()
        #expect(style.isPlain)
        for mode in BlendMode.allCases where mode != .normal {
            style.blendMode = mode
            #expect(!style.isPlain, "\(mode) is styling: a group wearing it is an object")
        }
    }

    @Test func aCopyCanOwnItsMixing() {
        var mine = LayerStyle()
        mine.blendMode = .multiply
        let original = LayerStyle()
        #expect(LayerStyle.differences(mine, original) == [.blendMode])
        #expect(mine.taking(.blendMode, from: original).blendMode == .normal)
    }
}
