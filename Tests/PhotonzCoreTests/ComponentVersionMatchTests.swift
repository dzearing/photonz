import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// One edit reaching every version of a component
/// (`ComponentVersionMatching`). A version is a whole drawing, so a change
/// meant for all of them used to be typed once per version; this is the one
/// command that carries it across.
struct ComponentVersionMatchTests {

    private func box(_ name: String, _ rect: CGRect, radius: CGFloat = 0,
                     fill: String? = "#3355FF") -> Layer {
        var annotation = AnnotationContent(shape: .rectangle, start: .zero,
                                           end: CGPoint(x: rect.width, y: rect.height))
        annotation.cornerRadius = radius
        annotation.fillColorHex = fill
        return Layer(name: name, content: .annotation(annotation), frame: rect)
    }

    private func text(_ name: String, _ string: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .text(TextContent(string: string)), frame: rect)
    }

    /// A component "Button" holding a box and a label, with a second version
    /// called "Hover" duplicated from it.
    private struct Fixture {
        var doc: PhotonzDocument
        var componentID: UUID
        var defaultVersion: UUID
        var hoverVersion: UUID
        var boxID: UUID
        var labelID: UUID

        var defaultMain: Layer { doc.mainComponent(componentID: componentID, version: defaultVersion)! }
        var hoverMain: Layer { doc.mainComponent(componentID: componentID, version: hoverVersion)! }
        /// The piece in Hover standing where `name` stands in Default.
        func hoverPiece(_ name: String) -> Layer {
            hoverMain.selfAndDescendants.first { $0.name == name }!
        }
    }

    private func withTwoVersions() -> Fixture {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [box("Box", CGRect(x: 10, y: 10, width: 120, height: 40), radius: 4),
                                           text("Label", "Save", CGRect(x: 20, y: 18, width: 60, height: 20))])
        let boxID = doc.layers[0].id
        let labelID = doc.layers[1].id
        let main = doc.groupLayers(ids: [boxID, labelID], name: "Button")!
        let componentID = doc.makeComponent(id: main.id)!
        let hover = doc.addComponentVersion(componentID: componentID)!
        doc.renameComponentVersion(componentID: componentID, version: hover, to: "Hover")
        let versions = doc.componentVersions(of: componentID)
        return Fixture(doc: doc, componentID: componentID,
                       defaultVersion: versions[0].id, hoverVersion: hover,
                       boxID: boxID, labelID: labelID)
    }

    // MARK: - A component with one version is unaffected

    @Test func oneVersionOffersNothing() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [box("Box", CGRect(x: 10, y: 10, width: 120, height: 40))])
        let boxID = doc.layers[0].id
        let main = doc.groupLayers(ids: [boxID], name: "Button")!
        _ = doc.makeComponent(id: main.id)
        // Nil rather than an empty plan: there is no row to show at all.
        #expect(doc.componentVersionApply(from: boxID) == nil)
        #expect(doc.canApplyToOtherComponentVersions(from: boxID) == false)
        let before = doc
        #expect(doc.applyToOtherComponentVersions(from: boxID) == nil)
        #expect(doc == before)
    }

    @Test func aLayerOutsideAnyComponentOffersNothing() {
        let doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [box("Loose", CGRect(x: 0, y: 0, width: 20, height: 20))])
        #expect(doc.componentVersionApply(from: doc.layers[0].id) == nil)
    }

    // MARK: - What travels

    @Test func aNewCornerRadiusReachesEveryVersion() {
        var c = withTwoVersions()
        c.doc.updateLayer(id: c.boxID) { layer in
            guard case .annotation(var a) = layer.content else { return }
            a.cornerRadius = 18
            layer.content = .annotation(a)
        }
        #expect(c.doc.canApplyToOtherComponentVersions(from: c.boxID))
        let done = c.doc.applyToOtherComponentVersions(from: c.boxID)
        #expect(done?.changing.map(\.version.name) == ["Hover"])
        guard case .annotation(let hover) = c.hoverPiece("Box").content else {
            Issue.record("Hover's Box is not a shape"); return
        }
        #expect(hover.cornerRadius == 18)
    }

    @Test func newWordingAndItsBoxReachEveryVersion() {
        var c = withTwoVersions()
        c.doc.updateLayer(id: c.labelID) { layer in
            layer.content = .text(TextContent(string: "Submit", fontSize: 14, colorHex: "#101010"))
            layer.frame.size = CGSize(width: 88, height: 22)
        }
        _ = c.doc.applyToOtherComponentVersions(from: c.labelID)
        let label = c.hoverPiece("Label")
        guard case .text(let words) = label.content else {
            Issue.record("Hover's Label is not text"); return
        }
        #expect(words.string == "Submit")
        #expect(words.colorHex == "#101010")
        // The box comes with the words: the same words in the same type need
        // the same room, and the old box would clip them.
        #expect(label.frame.size == CGSize(width: 88, height: 22))
    }

    @Test func theLookOnTheStyleTravelsToo() {
        var c = withTwoVersions()
        c.doc.updateLayer(id: c.boxID) { layer in
            layer.style.cornerRadius = 9
            layer.style.opacity = 0.5
            layer.style.shadow = ShadowStyle()
        }
        _ = c.doc.applyToOtherComponentVersions(from: c.boxID)
        let hover = c.hoverPiece("Box")
        #expect(hover.style.cornerRadius == 9)
        #expect(hover.style.opacity == 0.5)
        #expect(hover.style.shadow != nil)
    }

    // MARK: - What deliberately does not travel

    @Test func whereAPieceSitsIsLeftAlone() {
        var c = withTwoVersions()
        // Hover's own arrangement: its label moved down a bit.
        let hoverLabel = c.hoverPiece("Label").id
        c.doc.updateLayer(id: hoverLabel) { $0.frame.origin = CGPoint(x: 40, y: 90) }
        c.doc.updateLayer(id: c.labelID) { layer in
            guard case .text(var t) = layer.content else { return }
            t.colorHex = "#FF0000"
            layer.content = .text(t)
        }
        _ = c.doc.applyToOtherComponentVersions(from: c.labelID)
        let after = c.doc.layer(id: hoverLabel)!
        #expect(after.frame.origin == CGPoint(x: 40, y: 90))
        guard case .text(let words) = after.content else { Issue.record("not text"); return }
        #expect(words.colorHex == "#FF0000")
    }

    @Test func anExtraPartInAnotherVersionSurvives() {
        var c = withTwoVersions()
        // Hover grew a glow behind everything; Default never had one.
        let glow = box("Glow", CGRect(x: 0, y: 0, width: 140, height: 50))
        let added = c.doc.addLayer(glow, toGroup: c.hoverMain.id, at: 0)
        #expect(added)
        c.doc.updateLayer(id: c.boxID) { layer in
            guard case .annotation(var a) = layer.content else { return }
            a.fillColorHex = "#00AA55"
            layer.content = .annotation(a)
        }
        _ = c.doc.applyToOtherComponentVersions(from: c.boxID)
        // The extra part is still there, and untouched...
        #expect(c.hoverMain.children.map(\.name) == ["Glow", "Box", "Label"])
        guard case .annotation(let glowAfter) = c.hoverPiece("Glow").content else {
            Issue.record("Glow is not a shape"); return
        }
        #expect(glowAfter.fillColorHex == "#3355FF")
        // ...and Hover's Box was still found, by name, though it moved.
        guard case .annotation(let boxAfter) = c.hoverPiece("Box").content else {
            Issue.record("Box is not a shape"); return
        }
        #expect(boxAfter.fillColorHex == "#00AA55")
    }

    @Test func whatIsInsideAGroupIsLeftAlone() {
        var c = withTwoVersions()
        // The main itself is a piece: its own surface travels, its children do
        // not, so applying from the root never flattens the other version.
        let hoverLabel = c.hoverPiece("Label").id
        c.doc.updateLayer(id: hoverLabel) { layer in
            layer.content = .text(TextContent(string: "Hovering"))
        }
        c.doc.updateLayer(id: c.defaultMain.id) { $0.style.opacity = 0.8 }
        _ = c.doc.applyToOtherComponentVersions(from: c.defaultMain.id)
        #expect(c.hoverMain.style.opacity == 0.8)
        guard case .text(let words) = c.doc.layer(id: hoverLabel)!.content else {
            Issue.record("not text"); return
        }
        #expect(words.string == "Hovering")
    }

    // MARK: - Saying what it would do before it does it

    @Test func theTitleNamesTheVersionsItWouldChange() {
        var c = withTwoVersions()
        let third = c.doc.addComponentVersion(componentID: c.componentID)!
        c.doc.renameComponentVersion(componentID: c.componentID, version: third, to: "Disabled")
        c.doc.updateLayer(id: c.boxID) { $0.style.cornerRadius = 12 }
        let plan = c.doc.componentVersionApply(from: c.boxID)!
        #expect(plan.title == "Apply to Hover and Disabled")
        #expect(plan.help.contains("Box in Hover and Disabled"))

        // Four versions is more names than a menu row can carry, so it counts.
        let fourth = c.doc.addComponentVersion(componentID: c.componentID, from: c.hoverVersion)!
        c.doc.renameComponentVersion(componentID: c.componentID, version: fourth, to: "Pressed")
        #expect(c.doc.componentVersionApply(from: c.boxID)!.title == "Apply to 3 Other Versions")
    }

    @Test func aVersionThatAlreadyMatchesIsNotNamed() {
        var c = withTwoVersions()
        let third = c.doc.addComponentVersion(componentID: c.componentID)!
        c.doc.renameComponentVersion(componentID: c.componentID, version: third, to: "Disabled")
        // Only Hover drifted; Disabled is still identical to Default.
        let hoverBox = c.hoverPiece("Box").id
        c.doc.updateLayer(id: hoverBox) { $0.style.cornerRadius = 3 }
        let plan = c.doc.componentVersionApply(from: c.boxID)!
        #expect(plan.matches.count == 2)
        #expect(plan.changing.map(\.version.name) == ["Hover"])
        #expect(plan.title == "Apply to Hover")
    }

    @Test func applyingFromTheDrawingItselfSaysItIsOnlyTheSurface() {
        var c = withTwoVersions()
        // Standing on the drawing rather than on a piece inside it: only the
        // drawing's own surface travels, and the sentence has to say so rather
        // than claiming the whole version matches.
        let plan = c.doc.componentVersionApply(from: c.defaultMain.id)!
        #expect(plan.isWholeDrawing)
        #expect(plan.help.contains("This drawing's own surface already matches"))
        c.doc.updateLayer(id: c.defaultMain.id) { $0.style.cornerRadius = 6 }
        let ready = c.doc.componentVersionApply(from: c.defaultMain.id)!
        #expect(ready.title == "Apply to Hover")
        #expect(ready.help.contains("Gives Hover this drawing's own surface"))
        #expect(ready.help.contains("pieces inside each version are left alone"))
    }

    @Test func nothingToDoSaysSoRatherThanGoingQuiet() {
        let c = withTwoVersions()
        let plan = c.doc.componentVersionApply(from: c.boxID)!
        #expect(plan.wouldChangeAnything == false)
        #expect(plan.title == "Other Versions Already Match")
        #expect(plan.help.contains("already looks and reads the same"))
    }

    @Test func aVersionWithNoMatchingPartIsNamedAsLeftOut() {
        var c = withTwoVersions()
        // Hover threw its label away and the shapes were reordered, so neither
        // its place nor its name finds anything over there.
        c.doc.removeLayer(id: c.hoverPiece("Label").id)
        c.doc.updateLayer(id: c.labelID) { layer in
            guard case .text(var t) = layer.content else { return }
            t.string = "Submit"
            layer.content = .text(t)
        }
        let plan = c.doc.componentVersionApply(from: c.labelID)!
        #expect(plan.matches.isEmpty)
        #expect(plan.skipped.map(\.name) == ["Hover"])
        #expect(plan.title == "No Other Version Has This Part")
        #expect(plan.help.contains("Hover has no Label to change."))
    }

    @Test func aLockedPieceIsLeftOutRatherThanForced() {
        var c = withTwoVersions()
        c.doc.updateLayer(id: c.hoverPiece("Box").id) { $0.isLocked = true }
        c.doc.updateLayer(id: c.boxID) { $0.style.cornerRadius = 7 }
        let plan = c.doc.componentVersionApply(from: c.boxID)!
        #expect(plan.matches.isEmpty)
        #expect(plan.skipped.map(\.name) == ["Hover"])
        #expect(c.doc.applyToOtherComponentVersions(from: c.boxID) == nil)
    }

    // MARK: - Finding the same piece

    @Test func aKnobFindsThePieceEvenWhenTheDrawingWasRearranged() {
        // The label was made adjustable BEFORE the second version existed, so
        // the duplicate carries the same knob id pointing at its own label —
        // which is exactly what versions do with knobs, by design.
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [box("Box", CGRect(x: 10, y: 10, width: 120, height: 40)),
                                           text("Label", "Save", CGRect(x: 20, y: 18, width: 60, height: 20))])
        let boxID = doc.layers[0].id
        let labelID = doc.layers[1].id
        let main = doc.groupLayers(ids: [boxID, labelID], name: "Button")!
        let componentID = doc.makeComponent(id: main.id)!
        let knob = doc.addComponentProperty(componentID: componentID, target: labelID, kind: .text)
        #expect(knob != nil)
        let hover = doc.addComponentVersion(componentID: componentID)!
        doc.renameComponentVersion(componentID: componentID, version: hover, to: "Hover")
        let versions = doc.componentVersions(of: componentID)
        var c = Fixture(doc: doc, componentID: componentID, defaultVersion: versions[0].id,
                        hoverVersion: hover, boxID: boxID, labelID: labelID)
        let hoverLabel = c.hoverPiece("Label").id
        // Hover renamed its label AND moved it to the front, so neither the
        // name nor the position would find it.
        c.doc.updateLayer(id: hoverLabel) { $0.name = "Caption" }
        c.doc.moveLayer(id: hoverLabel, to: 0)
        c.doc.updateLayer(id: c.labelID) { layer in
            guard case .text(var t) = layer.content else { return }
            t.colorHex = "#123456"
            layer.content = .text(t)
        }
        let plan = c.doc.componentVersionApply(from: c.labelID)!
        #expect(plan.matches.map(\.layerID) == [hoverLabel])
        #expect(plan.changing.map(\.version.name) == ["Hover"])
        _ = c.doc.applyToOtherComponentVersions(from: c.labelID)
        guard case .text(let words) = c.doc.layer(id: hoverLabel)!.content else {
            Issue.record("not text"); return
        }
        #expect(words.colorHex == "#123456")
    }

    @Test func twoPiecesWithTheSameNameAreNotGuessedAt() {
        var c = withTwoVersions()
        // Hover holds two things called Box, so matching by name would be a
        // coin toss. Its tree also differs, so position cannot answer either.
        c.doc.removeLayer(id: c.hoverPiece("Label").id)
        let hoverBox = c.hoverPiece("Box").id
        let added = c.doc.addLayer(box("Box", CGRect(x: 0, y: 0, width: 10, height: 10)),
                                   toGroup: c.hoverMain.id, at: 0)
        #expect(added)
        c.doc.removeLayer(id: hoverBox)
        c.doc.updateLayer(id: c.labelID) { layer in
            guard case .text(var t) = layer.content else { return }
            t.string = "Submit"
            layer.content = .text(t)
        }
        let plan = c.doc.componentVersionApply(from: c.labelID)!
        #expect(plan.matches.isEmpty)
        #expect(plan.skipped.map(\.name) == ["Hover"])
    }

    // MARK: - One step, and the copies come with it

    @Test func everyVersionAndEveryCopyChangeInOneUndoStep() {
        var c = withTwoVersions()
        let third = c.doc.addComponentVersion(componentID: c.componentID)!
        c.doc.renameComponentVersion(componentID: c.componentID, version: third, to: "Disabled")
        let copy = c.doc.insertComponentInstance(of: c.componentID,
                                                 at: CGPoint(x: 400, y: 400))!
        _ = c.doc.setInstanceVersion(instance: copy, to: c.hoverVersion)
        c.doc.updateLayer(id: c.boxID) { $0.style.cornerRadius = 14 }

        var history = History(document: c.doc)
        let before = history.current
        history.perform { $0.applyToOtherComponentVersions(from: c.boxID) }
        let after = history.current

        for version in [c.hoverVersion, third] {
            let main = after.mainComponent(componentID: c.componentID, version: version)!
            let piece = main.selfAndDescendants.first { $0.name == "Box" }!
            #expect(piece.style.cornerRadius == 14)
        }
        // The copy shows Hover, so it followed inside the same step...
        let inCopy = after.layer(id: copy)!.selfAndDescendants.first { $0.name == "Box" }!
        #expect(inCopy.style.cornerRadius == 14)
        // ...and one Command Z puts all of it back.
        history.undo()
        #expect(history.current == before)
    }

    // MARK: - Inside a copy there is nothing to push

    @Test func aPieceInsideACopyOffersNothing() {
        var c = withTwoVersions()
        let copy = c.doc.insertComponentInstance(of: c.componentID,
                                                 at: CGPoint(x: 400, y: 400))!
        let inside = c.doc.layer(id: copy)!.selfAndDescendants.first { $0.name == "Box" }!
        #expect(c.doc.componentVersionApply(from: inside.id) == nil)
    }
}
