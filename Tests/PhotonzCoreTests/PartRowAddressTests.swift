import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A colour row is addressed by the NAME of the part it paints, not by the
/// layers that happened to be picked when it was drawn.
///
/// That is what lets the right hand panel leave a colour row alone when a click
/// changes nothing about it: the row keeps its id across the click and asks
/// which layers that id reaches at the moment somebody paints
/// (`ColorTarget.Source`, `EditorState.resolved(_:)`). The danger in skipping
/// is a row still painting the layer it was drawn for, so what has to be true
/// is exactly this: the same part of two different shapes carries the SAME row
/// id, and that id names the layers picked NOW.
struct PartRowAddressTests {

    private func arrow(_ name: String, color: String = "#FF0000") -> Layer {
        var annotation = AnnotationContent(shape: .arrow, start: .zero,
                                           end: CGPoint(x: 80, y: 40))
        annotation.colorHex = color
        return Layer(name: name, content: .annotation(annotation),
                     frame: CGRect(x: 0, y: 0, width: 80, height: 40))
    }

    private func box(_ name: String, fill: String = "#3366FF") -> Layer {
        var annotation = AnnotationContent(shape: .rectangle, start: .zero,
                                           end: CGPoint(x: 60, y: 30))
        annotation.colorHex = "#101010"
        annotation.fillColorHex = fill
        return Layer(name: name, content: .annotation(annotation),
                     frame: CGRect(x: 0, y: 0, width: 60, height: 30))
    }

    private func document(_ layers: [Layer]) -> PhotonzDocument {
        PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: layers)
    }

    @Test("Two arrows that read alike show rows with the same ids")
    func sameIdsAcrossAnAlikePick() {
        let one = arrow("Arrow"), two = arrow("Arrow 2")
        let doc = document([one, two])
        let first = doc.layerPartRows(layerIDs: [one.id]).map(\.id)
        let second = doc.layerPartRows(layerIDs: [two.id]).map(\.id)
        #expect(!first.isEmpty)
        #expect(first == second)
    }

    @Test("A row id names the layers picked NOW, not the ones it was built over")
    func idsReachWhatIsPickedNow() {
        let one = arrow("Arrow"), two = arrow("Arrow 2")
        let doc = document([one, two])
        // The row a panel drawn over the first arrow is holding.
        guard let held = doc.layerPartRows(layerIDs: [one.id]).first else {
            Issue.record("no rows over an arrow"); return
        }
        #expect(held.colors.flatMap { $0.layerIDs ?? [] } == [one.id])
        // The same row, looked up again after the second arrow is picked: this
        // is the lookup `EditorState.resolved(_:)` makes before it paints.
        guard let now = doc.layerPartRows(layerIDs: [two.id]).first(where: { $0.id == held.id })
        else {
            Issue.record("the row \(held.id) is gone after picking the other arrow"); return
        }
        #expect(now.colors.flatMap { $0.layerIDs ?? [] } == [two.id])
    }

    @Test("A row whose part the new selection does not have is simply gone")
    func aRowCanLeave() {
        let filled = box("Box"), line = arrow("Arrow")
        let doc = document([filled, line])
        let fill = doc.layerPartRows(layerIDs: [filled.id]).first { $0.part == .fill }
        #expect(fill != nil)
        // An arrow has no inside, so the Fill row is not among its rows at all:
        // a row held over from the box resolves to nothing rather than to the
        // box it was drawn for.
        let overTheArrow = doc.layerPartRows(layerIDs: [line.id])
        #expect(!overTheArrow.contains { $0.id == fill?.id })
    }

    @Test("Two arrows that read alike give their rows the same appearance")
    func alikeArrowsLookAlike() {
        let one = arrow("Arrow"), two = arrow("Arrow 2")
        let doc = document([one, two])
        guard let row = doc.layerPartRows(layerIDs: [one.id]).first,
              let slot = row.colors.first?.slot else {
            Issue.record("no rows over an arrow"); return
        }
        let first = doc.colorStyleSelection(layerIDs: [one.id], slot: slot)
        let second = doc.colorStyleSelection(layerIDs: [two.id], slot: slot)
        #expect(first != second)
        #expect(first.appearance == second.appearance)
    }

    @Test("Two arrows painted differently do NOT look alike")
    func differentColorsLookDifferent() {
        let red = arrow("Arrow", color: "#FF0000"), blue = arrow("Arrow 2", color: "#0000FF")
        let doc = document([red, blue])
        guard let row = doc.layerPartRows(layerIDs: [red.id]).first,
              let slot = row.colors.first?.slot else {
            Issue.record("no rows over an arrow"); return
        }
        #expect(doc.colorStyleSelection(layerIDs: [red.id], slot: slot).appearance
                != doc.colorStyleSelection(layerIDs: [blue.id], slot: slot).appearance)
    }
}
