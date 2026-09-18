import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// How many pieces Separate into Layers makes out of the two captures the
/// playtest walks are written against, pinned to the exact number.
///
/// This exists because the number moved without anybody noticing. The four
/// separate walks were written on 2026-09-13 against a separation that found
/// two boxes on the settings pane and none at all on the dense page. Two
/// commits on 2026-09-16 changed that on purpose:
///
/// - `18bbecfb` "A row inside a card comes out as its own layer" took the
///   settings pane from 2 boxes to 10, because the switches and fields sitting
///   on the cards now come out as their own layers inside the card's group.
/// - `eb326b78` "Separate finds the boxes in a dark window, not just on a flat
///   light page" took the dense page from 0 boxes to 30, which is the whole of
///   `SeparateBudget.maxBoxes`.
///
/// Both are the separation getting better, and neither was wrong. What was
/// wrong is that the only thing watching the number was a walk claiming a
/// ceiling of 151 layers, so the change landed silently and surfaced three days
/// later as four failing walks nobody could attribute. A walk is the wrong
/// place for an exact count: it reads the panel, which only renders the rows
/// you can see. So the walks keep the loose claim (it stopped at a limit rather
/// than handing back a wall) and the exact numbers live here, where a change to
/// them is a test diff that has to be read and agreed to.
///
/// Full design: `docs/design/separate-into-layers.md`.
@Suite("Separate: the pieces each fixture makes")
struct SeparateFixturePieceCountTests {

    /// What the app itself hands the separator, from `EditorState+Separate`:
    /// the same two numbers Size mode reads a screenshot with, at the capture's
    /// own scale.
    private struct Taken {
        let result: LayerSeparator.Result
        let document: PhotonzDocument
    }

    private static func capture(_ name: String) -> CGImage? {
        guard let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "png"),
              let data = try? Data(contentsOf: url) else { return nil }
        return ImageCodec.decode(data)
    }

    /// The capture taken apart and landed in a document exactly the way the
    /// command lands one: pieces named Text N and Box N, nested by
    /// `LayerNesting`, each group carrying the body row the app gives it.
    private func takeApart(_ name: String, scale: CGFloat) throws -> Taken {
        let image = try #require(Self.capture(name), "no fixture called \(name)")
        let store = ImageStore()
        let gap = Double(AlignmentScan.visibleGap * scale)
        let minElement = Double(max(10, 10 * scale))
        let result = try #require(LayerSeparator.separate(
            image, luma: EdgeMapAnalyzer.analyzeFully(image).luma,
            gap: gap, minElement: minElement))

        let source = store.register(image)
        var document = PhotonzDocument(
            canvasSize: CGSize(width: image.width, height: image.height),
            layers: [Layer(name: "Background", content: .image(source),
                           frame: CGRect(x: 0, y: 0, width: CGFloat(image.width),
                                         height: CGFloat(image.height)))])
        var runs = 0, boxes = 0
        var bodyNames: [String] = []
        let flat = result.pieces.map { piece -> PhotonzDocument.SeparatedPiece in
            let isRun = piece.kind == .text
            if isRun { runs += 1 } else { boxes += 1 }
            let name = isRun ? "Text \(runs)" : "Box \(boxes)"
            switch piece.body {
            case .picture(let cut):
                bodyNames.append("Picture")
                return PhotonzDocument.SeparatedPiece(
                    frame: piece.rect, content: .picture(store.register(cut)),
                    name: name, isRunOfText: isRun)
            case .shape(let shape):
                bodyNames.append("Fill")
                return PhotonzDocument.SeparatedPiece(
                    frame: piece.rect,
                    content: .shape(fill: shape.fill, radii: shape.radii,
                                    borderWidth: shape.borderWidth,
                                    borderColor: shape.borderColor),
                    name: name, isRunOfText: isRun)
            }
        }
        func assemble(_ node: LayerNesting.Node) -> PhotonzDocument.SeparatedPiece {
            let piece = flat[node.index]
            guard !node.children.isEmpty else { return piece }
            return PhotonzDocument.SeparatedPiece(
                frame: piece.frame, content: piece.content, name: piece.name,
                bodyName: bodyNames[node.index], children: node.children.map(assemble),
                shadow: piece.shadow, isRunOfText: piece.isRunOfText)
        }
        _ = document.separateIntoLayers(id: document.layers[0].id,
                                        patched: store.register(result.background),
                                        pieces: result.nested.map(assemble))
        return Taken(result: result, document: document)
    }

    // MARK: - The settings pane

    @Test func theSettingsPaneComesApartIntoNineteenPieces() throws {
        let taken = try takeApart("settings-pane-2x", scale: 2)
        #expect(taken.result.runs.count == 9)
        #expect(taken.result.boxes.count == 10)
        #expect(taken.result.skipped == 0)
        #expect(taken.result.crowded == 0)
        // One command, one pass: nothing is left in the picture for a second.
        #expect(taken.result.left == 0)
    }

    @Test func theSettingsPaneListIsFiveRowsOverFourGroups() throws {
        let taken = try takeApart("settings-pane-2x", scale: 2)
        // 1 background + 19 pieces + a body row for each of the four groups.
        #expect(taken.document.allLayers.count == 24)
        let top = taken.document.layers.map(\.name)
        #expect(top == ["Background", "Box 1", "Box 2", "Box 3", "Box 4", "Text 1"])
    }

    @Test func theCardsHoldTheControlsThatSatOnThem() throws {
        let taken = try takeApart("settings-pane-2x", scale: 2)
        // Box 1 and Box 2 are the two cards, and each one opens onto its own
        // picture, its three labels and the three controls that sat on it.
        for card in ["Box 1", "Box 2"] {
            let group = try #require(taken.document.allLayers.first { $0.name == card })
            let inside = group.children.map(\.name)
            #expect(inside.count == 7, "\(card) holds \(inside)")
            #expect(inside.contains("Picture"), "\(card) holds \(inside)")
            #expect(inside.filter { $0.hasPrefix("Box ") }.count == 3, "\(card) holds \(inside)")
            #expect(inside.filter { $0.hasPrefix("Text ") }.count == 3, "\(card) holds \(inside)")
        }
        // Box 3 and Box 4 are the two buttons: a real rectangle and its label.
        for button in ["Box 3", "Box 4"] {
            let group = try #require(taken.document.allLayers.first { $0.name == button })
            let inside = group.children.map(\.name)
            #expect(inside.count == 2, "\(button) holds \(inside)")
            #expect(inside.contains("Fill"), "\(button) holds \(inside)")
        }
    }

    // MARK: - The dense page

    @Test func theDensePageStopsAtTheCeilingRatherThanHandingBackAWall() throws {
        let taken = try takeApart("dense-page-1x", scale: 1)
        #expect(taken.result.runs.count == 142)
        // The box pass is the one that hits its limit on a page this dense.
        #expect(taken.result.boxes.count == SeparateBudget.maxBoxes)
        #expect(taken.result.boxes.count == 30)
        // And everything it did not take is counted rather than dropped, so
        // the pill's number is the number still in the picture.
        //
        // 355 rather than the 357 pinned here until 2026-09-18. That number was
        // never a fact about the picture: `TextRunSweep.components` handed its
        // runs back in dictionary hash order, Swift reseeds that every process,
        // and the pass that drops a run overlapping one already taken kept a
        // different one each time. The same fixture came out 355, 357 or 359 in
        // consecutive runs of this one test, so the suite was a coin toss. The
        // order is now reading order and the answer is one number; 355 is what
        // the picture actually holds, and it is what the seed-pinned run
        // (SWIFT_DETERMINISTIC_HASHING=1) gave before the fix as well.
        #expect(taken.result.skipped == 8)
        #expect(taken.result.crowded == 355)
    }

    @Test func theDensePageLandsAsOneHundredAndSeventyThreeLayers() throws {
        let taken = try takeApart("dense-page-1x", scale: 1)
        // This is the number `separate-whole-screenshot-walk` sees. It is well
        // under the 500 runs the page offers, which is the claim the walk makes
        // in words, and it is under the ceiling the budget allows at all:
        // 1 background + 150 runs + 30 boxes + a body row per group.
        #expect(taken.document.allLayers.count == 173)
        #expect(taken.document.allLayers.count
            <= 1 + SeparateBudget.maxTextRuns + SeparateBudget.maxBoxes * 2)
    }
}
