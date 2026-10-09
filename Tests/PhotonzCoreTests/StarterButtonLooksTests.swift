import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The starter Button the way the variants mock draws it
/// (`docs/design/mocks/pages/ui-variants.html`, the `.pmatrix` cells and the
/// Properties group): Primary, Secondary or Ghost, Small, Medium or Large, with
/// a leading icon a copy can show, hide and swap.
struct StarterButtonLooksTests {

    private func dropped() -> (doc: PhotonzDocument, copy: UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 800))
        let copy = doc.insertStarterComponent(.button, at: CGPoint(x: 400, y: 400))
        #expect(copy != nil)
        return (doc, copy ?? UUID())
    }

    private var buttonID: UUID { StarterComponent.button.componentID }

    /// What `History.perform` does after every edit: arrange, follow the
    /// originals, arrange again.
    private func settle(_ doc: inout PhotonzDocument) {
        doc.reflowLayouts()
        if doc.syncComponentInstances().updatedInstances > 0 { doc.reflowLayouts() }
    }

    private func look(_ doc: PhotonzDocument, _ variant: String, _ size: String) -> Layer? {
        let properties = doc.componentVariantProperties(of: buttonID)
        guard properties.count == 2 else { return nil }
        for drawing in doc.componentVersions(of: buttonID) {
            let answers = doc.componentVariantAnswers(of: buttonID, drawing: drawing)
            if answers[properties[0].id] == variant, answers[properties[1].id] == size {
                return doc.layer(id: drawing.layerID)
            }
        }
        return nil
    }

    private func piece(_ layer: Layer?, _ name: String) -> Layer? {
        layer?.selfAndDescendants.dropFirst().first { $0.name == name }
    }

    /// Where a piece sits in the drawing's own box, through any group between.
    private func box(_ layer: Layer?, _ name: String) -> CGRect? {
        guard let layer else { return nil }
        for child in layer.children {
            if child.name == name { return child.frame }
            if let inner = box(child, name) {
                return inner.offsetBy(dx: child.frame.minX, dy: child.frame.minY)
            }
        }
        return nil
    }

    private func fillHex(_ layer: Layer?) -> String? {
        guard case .annotation(let box)? = layer?.content else { return nil }
        return box.fillColorHex
    }

    private func textHex(_ layer: Layer?) -> String? {
        guard case .text(let text)? = layer?.content else { return nil }
        return text.colorHex
    }

    private func property(_ doc: PhotonzDocument, _ name: String) -> ComponentProperty? {
        doc.componentProperties(of: buttonID).first { $0.name == name }
    }

    // MARK: - Reading icon outlines

    @Test func aStraightOutlineReadsAsAnchors() {
        let runs = IconPathData.runs("M0 0L10 0 10 10z")
        #expect(runs.count == 1)
        #expect(runs.first?.isClosed == true)
        #expect(runs.first?.anchors.map(\.point)
                == [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10)])
    }

    /// Relative numbers run on from where the pen is, and SVG lets them sit
    /// against each other with only a sign between.
    @Test func relativeNumbersRunOnFromThePen() {
        let runs = IconPathData.runs("M1 1l2-1.5.5.5h3v-2M5 5L6 6")
        #expect(runs.count == 2)
        #expect(runs.first?.anchors.map(\.point) == [
            CGPoint(x: 1, y: 1), CGPoint(x: 3, y: -0.5), CGPoint(x: 3.5, y: 0),
            CGPoint(x: 6.5, y: 0), CGPoint(x: 6.5, y: -2)])
        #expect(runs.first?.isClosed == false)
        #expect(runs.last?.anchors.count == 2)
    }

    /// Half a circle from left to right, sweeping clockwise on a y-down page,
    /// bulges upward by its radius and ends exactly where it was asked to.
    @Test func anArcBecomesCurvesThatReachItsEnd() {
        let runs = IconPathData.runs("M0 0a5 5 0 0 1 10 0")
        let path = PathContent(anchors: runs[0].anchors, isClosed: false)
        #expect(runs[0].anchors.last?.point == CGPoint(x: 10, y: 0))
        #expect(abs(path.bounds.minY + 5) < 0.05)
        #expect(abs(path.bounds.width - 10) < 0.05)
    }

    /// Every icon the Icon menu offers is drawn, inside its own square.
    @Test func everyIconIsDrawnInsideItsSquare() {
        #expect(StarterIcon.allCases.map(\.name) == ["Sparkle", "Wand", "Swatch", "Layers", "Brush"])
        for icon in StarterIcon.allCases {
            let glyph = icon.layer(size: 24, colorHex: "#000000")
            #expect(!glyph.children.isEmpty, "\(icon.name)")
            for mark in glyph.children {
                #expect(mark.frame.minX >= 0 && mark.frame.maxX <= 24, "\(icon.name)")
                #expect(mark.frame.minY >= 0 && mark.frame.maxY <= 24, "\(icon.name)")
                #expect(mark.frame.width > 0 || mark.frame.height > 0, "\(icon.name)")
            }
        }
    }

    // MARK: - The nine looks

    @Test func aDroppedButtonAsksVariantAndSize() {
        let (doc, _) = dropped()
        let properties = doc.componentVariantProperties(of: buttonID)
        #expect(properties.map(\.name) == ["Variant", "Size"])
        #expect(properties.first?.options.map(\.name) == ["Primary", "Secondary", "Ghost"])
        #expect(properties.last?.options.map(\.name) == ["Small", "Medium", "Large"])
        #expect(doc.componentVersions(of: buttonID).count == 9)
    }

    /// The copy a drop places is the mock's live instance: Primary, Medium.
    @Test func theDroppedCopyIsPrimaryMedium() {
        let (doc, copy) = dropped()
        let properties = doc.componentVariantProperties(of: buttonID)
        let answers = doc.instanceVariantAnswers(of: copy)
        #expect(answers[properties[0].id] == "Primary")
        #expect(answers[properties[1].id] == "Medium")
        #expect(doc.layer(id: copy)?.localBounds.height == 32)
        // ...and so is the next one off the shelf.
        var again = doc
        let second = again.insertStarterComponent(.button, at: CGPoint(x: 200, y: 200))
        #expect(second.map { again.instanceVariantAnswers(of: $0)[properties[1].id] } == "Medium")
    }

    /// Height, rounding and the room either side follow the mock's sizes:
    /// 24, 32 and 40 tall, a capsule, 12, 16 and 20 in from each side.
    @Test func eachSizeIsTheMocksHeightAndPadding() {
        let (doc, _) = dropped()
        let sizes: [(String, CGFloat, CGFloat, CGFloat)] =
            [("Small", 24, 12, 13), ("Medium", 32, 16, 15), ("Large", 40, 20, 17)]
        for variant in ["Primary", "Secondary", "Ghost"] {
            for (size, height, padding, icon) in sizes {
                let drawing = look(doc, variant, size)
                #expect(drawing?.localBounds.height == height, "\(variant) \(size)")
                let background = piece(drawing, "Background")
                if case .annotation(let box)? = background?.content {
                    #expect(box.cornerRadius == height / 2, "\(variant) \(size)")
                }
                let glyph = box(drawing, "Icon")
                #expect(glyph?.minX == padding, "\(variant) \(size)")
                #expect(glyph?.width == icon, "\(variant) \(size)")
                let label = box(drawing, "Label")
                let right = (drawing?.localBounds.width ?? 0) - (label?.maxX ?? 0)
                #expect(abs(right - (padding - StarterComponents.textSlack)) <= 1,
                        "\(variant) \(size) right room \(right)")
            }
        }
    }

    /// Primary is the accent with light words; Secondary a surface with a
    /// hairline and dark words; Ghost nothing behind quiet words.
    @Test func eachVariantPaintsFromTheMocksColours() {
        let (doc, _) = dropped()
        for size in ["Small", "Medium", "Large"] {
            let primary = look(doc, "Primary", size)
            #expect(fillHex(piece(primary, "Background")) == StarterStyle.accent.colorHex)
            #expect(textHex(piece(primary, "Label")) == StarterStyle.surface.colorHex)

            let secondary = look(doc, "Secondary", size)
            #expect(fillHex(piece(secondary, "Background")) == StarterStyle.surface.colorHex)
            #expect(piece(secondary, "Background")?.style.borderEffectIndex != nil)
            #expect(textHex(piece(secondary, "Label")) == StarterStyle.text.colorHex)

            let ghost = look(doc, "Ghost", size)
            #expect(fillHex(piece(ghost, "Background")) == nil)
            #expect(piece(ghost, "Background")?.style.borderEffectIndex == nil)
            #expect(textHex(piece(ghost, "Label")) == StarterStyle.muted.colorHex)
        }
    }

    /// The colours are the design system's: its accent, and its quiet text.
    @Test func theKitPaintsInTheDesignSystemsColours() {
        #expect(StarterStyle.accent.colorHex == "#4C6FFF")
        #expect(StarterStyle.muted.colorHex == "#5C6371")
    }

    // MARK: - What a copy can set

    @Test func aCopyOffersShowIconLabelAndIcon() {
        let (doc, copy) = dropped()
        let selection = doc.componentKnobSelection(layerIDs: [copy])
        #expect(selection.properties.map(\.name) == ["Show icon", "Label", "Icon"])
        #expect(selection.properties.map(\.kind) == [.visible, .text, .variant])
        let icon = property(doc, "Icon")
        let options = icon.map {
            doc.componentVariantOptionLabels(componentID: buttonID, version: doc.instanceVersion(of: copy),
                                             propertyID: $0.id).map(\.label)
        }
        #expect(options == ["Sparkle", "Wand", "Swatch", "Layers", "Brush"])
        #expect(selection.variantRows.map(\.name) == ["Variant", "Size"])
    }

    /// Picking Large makes the copy 40 tall on the canvas, in one change.
    @Test func pickingLargeMakesTheCopyTaller() {
        var (doc, copy) = dropped()
        let size = doc.componentVariantProperties(of: buttonID)[1].id
        #expect(doc.setInstanceVariantAnswer(instances: [copy], property: size, option: "Large") == 1)
        settle(&doc)
        #expect(doc.layer(id: copy)?.localBounds.height == 40)
    }

    /// Hiding the icon takes it out of the row, so the copy closes up round
    /// its label rather than keeping an empty slot.
    ///
    /// ...and a copy dragged wider keeps the icon and the words together in
    /// the middle of the capsule (`aWidenedButtonKeepsItsRowCentred`).
    @Test func hidingTheIconClosesTheRowUp() {
        var (doc, copy) = dropped()
        let before = doc.layer(id: copy)?.localBounds.width ?? 0
        let show = property(doc, "Show icon")
        #expect(show != nil)
        _ = doc.setInstanceOverride(instance: copy, property: show?.id ?? UUID(), value: .visible(false))
        settle(&doc)
        let after = doc.layer(id: copy)?.localBounds.width ?? 0
        #expect(abs((before - after) - (15 + 8)) <= 1, "before \(before) after \(after)")
    }

    /// An icon picked on a Medium copy is still that icon after the copy is
    /// made Large: each look draws its own Wand, and the copy's choice finds it.
    @Test func aChosenIconCarriesAcrossLooks() {
        var (doc, copy) = dropped()
        guard let icon = property(doc, "Icon") else { Issue.record("no Icon knob"); return }
        let options = doc.componentVariantOptionLabels(componentID: buttonID,
                                                       version: doc.instanceVersion(of: copy),
                                                       propertyID: icon.id)
        guard let wand = options.first(where: { $0.label == "Wand" }) else {
            Issue.record("no Wand"); return
        }
        let took = doc.setInstanceOverride(instance: copy, property: icon.id, value: .variant(wand.id))
        #expect(took)
        let size = doc.componentVariantProperties(of: buttonID)[1].id
        doc.setInstanceVariantAnswer(instances: [copy], property: size, option: "Large")
        let variant = doc.componentVariantProperties(of: buttonID)[0].id
        doc.setInstanceVariantAnswer(instances: [copy], property: variant, option: "Ghost")
        settle(&doc)
        let shown = piece(doc.layer(id: copy), "Icon")?.children.filter(\.isVisible).map(\.name)
        #expect(shown == ["Wand"])
        // ...and the panel reads Wand against the look the copy now shows.
        let reading = doc.componentKnobSelection(layerIDs: [copy]).reading(icon.id).optionValue
        let large = doc.componentVariantOptionLabels(componentID: buttonID,
                                                     version: doc.instanceVersion(of: copy),
                                                     propertyID: icon.id)
        #expect(large.first { $0.id == reading }?.label == "Wand")
    }

    /// The words on a copy showing Primary · Medium, which is not the first
    /// drawing, are still a piece of the original: they can be typed over and
    /// dressed in a text style on the canvas.
    @Test func aCopysWordsArePiecesOfTheLookItShows() {
        let (doc, copy) = dropped()
        guard let words = piece(doc.layer(id: copy), "Label") else {
            Issue.record("no label"); return
        }
        let piece = doc.componentPiece(of: words.id)
        #expect(piece != nil)
        #expect(piece.flatMap { doc.layer(id: $0.source)?.name } == "Label")
        #expect(doc.canSetPieceTextStyle(of: words.id))
    }

    /// Dragged wider, the capsule fills and the icon and the words stay
    /// together in its middle, the way a lone word always did.
    @Test func aWidenedButtonKeepsItsRowCentred() {
        let button = StarterComponents.layer(.button)
        for width in [128.0, 200.0] as [CGFloat] {
            let resized = button.resized(to: CGRect(x: 0, y: 0, width: width,
                                                    height: button.localBounds.height))
            guard let icon = box(resized, "Icon"), let label = box(resized, "Label") else {
                Issue.record("lost a piece"); return
            }
            #expect(box(resized, "Background")?.width == width)
            let ink = label.maxX - StarterComponents.textSlack
            #expect(abs((icon.minX + ink) / 2 - width / 2) <= 1, "\(width)")
            #expect(label.minX - icon.maxX == 8)
        }
    }

    /// A copy told to say something much longer grows to the right of its
    /// icon: the words never reach back past it and swap places.
    @Test func longerWordsStayAfterTheIcon() {
        var (doc, copy) = dropped()
        guard let label = property(doc, "Label") else { Issue.record("no Label knob"); return }
        _ = doc.setInstanceOverride(instance: copy, property: label.id,
                                    value: .text("Save every change you made today"))
        settle(&doc)
        let built = doc.layer(id: copy)
        guard let icon = box(built, "Icon"), let words = box(built, "Label") else {
            Issue.record("lost a piece"); return
        }
        #expect(words.minX - icon.maxX == 8)
        #expect(abs((built?.localBounds.width ?? 0) - (words.maxX - StarterComponents.textSlack + 16)) <= 1)
    }

    // MARK: - What it leaves alone

    /// A document that already took the old one-look Button keeps it: the
    /// next drop is another copy of THAT, not nine new drawings.
    @Test func aDocumentWithTheOldButtonKeepsIt() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 800))
        var old = StarterComponents.layer(.button)
        old.name = "Button"
        doc.addOriginal(old)
        let copy = doc.insertStarterComponent(.button, at: CGPoint(x: 300, y: 300))
        #expect(copy != nil)
        #expect(doc.componentVersions(of: buttonID).count == 1)
    }

    /// The other four starters are one drawing each, as they were.
    @Test func theOtherStartersStayOneLook() {
        for kind in StarterComponent.allCases where kind != .button {
            var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 800))
            _ = doc.insertStarterComponent(kind, at: CGPoint(x: 400, y: 400))
            #expect(doc.componentVersions(of: kind.componentID).count == 1, "\(kind.name)")
        }
    }
}
