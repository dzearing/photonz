import Foundation
import CoreGraphics
import Testing
@testable import PhotonzCore

/// A component asking two variant questions at once: a Button that is Primary
/// or Secondary AND Default or Large (`ComponentVariantProperty`,
/// `docs/design/mocks/pages/ui-variants.html`, `#segVariant` / `#segSize` and
/// the `.pmatrix` grid).
///
/// The drawings stay a flat list. Each one carries an answer per question, a
/// copy picks each answer on its own, and a combination nobody drew shows the
/// nearest drawing that was rather than a blank.
struct ComponentVariantGridTests {

    private func box(_ name: String, _ rect: CGRect) -> Layer {
        Layer(name: name, content: .annotation(AnnotationContent(shape: .rectangle,
                                                                 start: .zero,
                                                                 end: CGPoint(x: rect.width, y: rect.height))),
              frame: rect)
    }

    /// A Button with two looks, renamed Primary and Secondary, which is where
    /// the second question starts from.
    private func button(width: CGFloat = 120) -> (doc: PhotonzDocument, componentID: UUID,
                                                  primary: UUID, secondary: UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [box("Box", CGRect(x: 10, y: 10, width: width, height: 40))])
        let main = doc.groupLayers(ids: [doc.layers[0].id], name: "Button")!
        let componentID = doc.makeComponent(id: main.id)!
        let secondary = doc.addComponentVersion(componentID: componentID)!
        let primary = doc.componentVersions(of: componentID)[0].id
        doc.renameComponentVersion(componentID: componentID, version: primary, to: "Primary")
        doc.renameComponentVersion(componentID: componentID, version: secondary, to: "Secondary")
        return (doc, componentID, primary, secondary)
    }

    /// The Button with a Size question added from its Primary drawing, which
    /// makes a Primary · Size 2 drawing; that option is then called Large.
    private func buttonWithSize(width: CGFloat = 120)
        -> (doc: PhotonzDocument, componentID: UUID, size: UUID,
            primary: UUID, secondary: UUID, primaryLarge: UUID) {
        var b = button(width: width)
        let added = b.doc.addComponentVariantProperty(componentID: b.componentID, from: b.primary)!
        let large = b.doc.componentVersion(of: b.componentID, id: added.version)!
        _ = b.doc.setComponentVariantOption(componentID: b.componentID, drawing: large.layerID,
                                            property: added.property, to: "Large")
        return (b.doc, b.componentID, added.property, b.primary, b.secondary, added.version)
    }

    private func options(_ doc: PhotonzDocument, _ componentID: UUID, _ index: Int) -> [String] {
        doc.componentVariantProperties(of: componentID)[index].options.map(\.name)
    }

    // MARK: - Adding a second question

    /// The original can ask a second question beside the first. It starts with
    /// two answers, so it is a real choice from the moment it exists: every
    /// drawing it found answers Default, and one new drawing answers the next.
    @Test func aSecondQuestionArrivesBesideTheFirst() {
        var b = button()
        let added = b.doc.addComponentVariantProperty(componentID: b.componentID, from: b.primary)
        #expect(added != nil)
        let properties = b.doc.componentVariantProperties(of: b.componentID)
        #expect(properties.map(\.name) == ["Variant", "Size"])
        #expect(properties[1].id == added?.property)
        #expect(options(b.doc, b.componentID, 0) == ["Primary", "Secondary"])
        #expect(options(b.doc, b.componentID, 1) == ["Default", "Size 2"])
        // The new drawing is the Primary drawing again, answering the new option.
        let drawings = b.doc.componentVersions(of: b.componentID)
        #expect(drawings.count == 3)
        #expect(drawings.map(\.name) == ["Primary · Default", "Secondary · Default", "Primary · Size 2"])
    }

    /// One look is not a question to ask a second question beside: a component
    /// with a single drawing gets its first question from "A second Variant".
    @Test func aComponentWithOneDrawingCannotAskASecondQuestion() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600),
                                  layers: [box("Box", CGRect(x: 10, y: 10, width: 120, height: 40))])
        let main = doc.groupLayers(ids: [doc.layers[0].id], name: "Button")!
        let componentID = doc.makeComponent(id: main.id)!
        #expect(doc.addComponentVariantProperty(componentID: componentID) == nil)
    }

    /// Both questions are named, and each keeps its own name.
    @Test func bothQuestionsCanBeNamed() {
        var b = buttonWithSize()
        let r1 = b.doc.renameComponentVariantProperty(of: b.componentID, property: b.componentID,
                                                     to: "Type")
        #expect(r1)
        let r2 = b.doc.renameComponentVariantProperty(of: b.componentID, property: b.size,
                                                     to: "Scale")
        #expect(r2)
        #expect(b.doc.componentVariantProperties(of: b.componentID).map(\.name) == ["Type", "Scale"])
        // Two questions may not share a name: the copy's rows would be two
        // rows called the same thing.
        let r3 = b.doc.renameComponentVariantProperty(of: b.componentID, property: b.size,
                                                      to: "Type")
        #expect(!r3)
        let r4 = b.doc.renameComponentVariantProperty(of: b.componentID, property: b.size,
                                                      to: "  ")
        #expect(!r4)
    }

    /// A third question's fresh name steps past Size.
    @Test func aThirdQuestionGetsAFreshName() {
        var b = buttonWithSize()
        _ = b.doc.addComponentVariantProperty(componentID: b.componentID)
        #expect(b.doc.componentVariantProperties(of: b.componentID).map(\.name)
                    == ["Variant", "Size", "Property 3"])
    }

    // MARK: - Naming an answer

    /// Typing a new word over an answer renames that option everywhere it is
    /// given: Default becomes Medium on both drawings that answered it.
    @Test func typingANewWordRenamesTheOption() {
        var b = buttonWithSize()
        let primary = b.doc.componentVersion(of: b.componentID, id: b.primary)!
        let r5 = b.doc.setComponentVariantOption(componentID: b.componentID, drawing: primary.layerID,
                                                property: b.size, to: "Medium")
        #expect(r5)
        #expect(options(b.doc, b.componentID, 1) == ["Medium", "Large"])
    }

    /// Typing the word another option already has moves THIS drawing into it,
    /// which is how a second Large is drawn: another Size from Secondary, then
    /// call it Large.
    @Test func typingAnExistingWordJoinsThatOption() {
        var b = buttonWithSize()
        let added = b.doc.addComponentVariantOption(componentID: b.componentID, property: b.size,
                                                    from: b.secondary)!
        let drawing = b.doc.componentVersion(of: b.componentID, id: added)!
        #expect(drawing.name == "Secondary · Size 3")
        let r6 = b.doc.setComponentVariantOption(componentID: b.componentID, drawing: drawing.layerID,
                                                property: b.size, to: "Large")
        #expect(r6)
        #expect(options(b.doc, b.componentID, 1) == ["Default", "Large"])
        #expect(b.doc.componentVersions(of: b.componentID).map(\.name)
                    == ["Primary · Default", "Secondary · Default", "Primary · Large", "Secondary · Large"])
    }

    /// Another Variant from a Large drawing is a Large drawing too: the new
    /// look only differs on the question it was added for.
    @Test func anotherFirstAnswerKeepsTheOtherAnswers() {
        var b = buttonWithSize()
        let added = b.doc.addComponentVariantOption(componentID: b.componentID,
                                                    property: b.componentID, from: b.primaryLarge)!
        #expect(b.doc.componentVersion(of: b.componentID, id: added)?.name == "Variant 3 · Large")
    }

    // MARK: - A copy picks each answer on its own

    @Test func aCopyPicksEachAnswerOnItsOwn() {
        var b = buttonWithSize()
        let copy = b.doc.insertComponentInstance(of: b.componentID, at: CGPoint(x: 400, y: 300),
                                                 version: b.primary)!
        #expect(b.doc.instanceVariantAnswers(of: copy) == [b.componentID: "Primary", b.size: "Default"])
        let r7 = b.doc.setInstanceVariantAnswer(instances: [copy], property: b.size, option: "Large")
        #expect(r7 == 1)
        #expect(b.doc.instanceVersion(of: copy) == b.primaryLarge)
        #expect(b.doc.instanceVariantAnswers(of: copy) == [b.componentID: "Primary", b.size: "Large"])
        // A drawing that exists leaves nothing to remember.
        #expect(b.doc.layer(id: copy)?.group?.instanceAnswers.isEmpty == true)
    }

    /// Secondary · Large was never drawn. The copy shows the nearest drawing
    /// that was, which keeps the answer it was just given (Large), and its rows
    /// still say what was picked.
    @Test func aCombinationNobodyDrewShowsTheNearestOne() {
        var b = buttonWithSize()
        let copy = b.doc.insertComponentInstance(of: b.componentID, at: CGPoint(x: 400, y: 300),
                                                 version: b.secondary)!
        let r8 = b.doc.setInstanceVariantAnswer(instances: [copy], property: b.size, option: "Large")
        #expect(r8 == 1)
        #expect(b.doc.instanceVersion(of: copy) == b.primaryLarge)
        #expect(b.doc.instanceVariantAnswers(of: copy) == [b.componentID: "Secondary", b.size: "Large"])
        // ...and back to Default lands on a drawing that exists again, with
        // nothing left to remember.
        let r9 = b.doc.setInstanceVariantAnswer(instances: [copy], property: b.size, option: "Default")
        #expect(r9 == 1)
        #expect(b.doc.instanceVersion(of: copy) == b.secondary)
        #expect(b.doc.layer(id: copy)?.group?.instanceAnswers.isEmpty == true)
        // The copy always shows SOME drawing, never nothing.
        b.doc.syncComponentInstances()
        #expect(b.doc.layer(id: copy)?.children.isEmpty == false)
    }

    /// Picking the answer a copy already gives changes nothing.
    @Test func pickingTheSameAnswerIsANoOp() {
        var b = buttonWithSize()
        let copy = b.doc.insertComponentInstance(of: b.componentID, at: CGPoint(x: 400, y: 300),
                                                 version: b.primary)!
        let r10 = b.doc.setInstanceVariantAnswer(instances: [copy], property: b.size, option: "Default")
        #expect(r10 == 0)
        let r11 = b.doc.setInstanceVariantAnswer(instances: [copy], property: b.size, option: "Huge")
        #expect(r11 == 0)
    }

    /// Picking a whole drawing (the one-question way) forgets any combination
    /// the copy was asking for, and Reset does too.
    @Test func pickingADrawingOrResettingForgetsTheCombination() {
        var b = buttonWithSize()
        let copy = b.doc.insertComponentInstance(of: b.componentID, at: CGPoint(x: 400, y: 300),
                                                 version: b.secondary)!
        _ = b.doc.setInstanceVariantAnswer(instances: [copy], property: b.size, option: "Large")
        #expect(b.doc.layer(id: copy)?.group?.instanceAnswers.isEmpty == false)
        b.doc.setInstanceVersion(instance: copy, to: b.secondary)
        #expect(b.doc.layer(id: copy)?.group?.instanceAnswers.isEmpty == true)

        _ = b.doc.setInstanceVariantAnswer(instances: [copy], property: b.size, option: "Large")
        #expect(b.doc.canResetInstanceProperties(instance: copy))
        b.doc.resetInstanceProperties(instances: [copy])
        #expect(b.doc.layer(id: copy)?.group?.instanceAnswers.isEmpty == true)
        #expect(b.doc.instanceVersion(of: copy) == b.primary)
    }

    /// The panel's rows: one per question that has a choice in it, each
    /// reading the answer the picked copies share, or nothing when they differ.
    @Test func thePanelReadsOneRowPerQuestion() {
        var b = buttonWithSize()
        let one = b.doc.insertComponentInstance(of: b.componentID, at: CGPoint(x: 400, y: 300),
                                                version: b.primary)!
        let two = b.doc.insertComponentInstance(of: b.componentID, at: CGPoint(x: 400, y: 400),
                                                version: b.primaryLarge)!
        let rows = b.doc.componentKnobSelection(layerIDs: [one, two]).variantRows
        #expect(rows.map(\.name) == ["Variant", "Size"])
        #expect(rows[0].options == ["Primary", "Secondary"])
        #expect(rows[0].chosen == "Primary")
        #expect(rows[1].options == ["Default", "Large"])
        #expect(rows[1].chosen == nil)
    }

    /// A one-question component keeps the row it always had.
    @Test func aOneQuestionComponentHasOneRow() {
        let b = button()
        var doc = b.doc
        let copy = doc.insertComponentInstance(of: b.componentID, at: CGPoint(x: 400, y: 300))!
        let rows = doc.componentKnobSelection(layerIDs: [copy]).variantRows
        #expect(rows.map(\.name) == ["Variant"])
        #expect(rows[0].chosen == "Primary")
    }

    // MARK: - Saved and read back

    @Test func bothQuestionsSurviveARoundTrip() throws {
        var b = buttonWithSize()
        let copy = b.doc.insertComponentInstance(of: b.componentID, at: CGPoint(x: 400, y: 300),
                                                 version: b.secondary)!
        _ = b.doc.setInstanceVariantAnswer(instances: [copy], property: b.size, option: "Large")
        let data = try JSONEncoder().encode(b.doc)
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(back.componentVariantProperties(of: b.componentID).map(\.name) == ["Variant", "Size"])
        #expect(back.instanceVariantAnswers(of: copy) == [b.componentID: "Secondary", b.size: "Large"])
    }

    /// A component asking one question writes neither new key, so a file saved
    /// before a second question existed is byte for byte what it was, and it
    /// opens with its one question unchanged.
    @Test func aOneQuestionComponentWritesNothingNew() throws {
        var b = button()
        _ = b.doc.insertComponentInstance(of: b.componentID, at: CGPoint(x: 400, y: 300))
        let data = try JSONEncoder().encode(b.doc)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("variantAnswers"))
        #expect(!json.contains("instanceAnswers"))
        let back = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        let properties = back.componentVariantProperties(of: b.componentID)
        #expect(properties.map(\.name) == ["Variant"])
        #expect(properties[0].options.map(\.name) == ["Primary", "Secondary"])
        #expect(back.componentVersions(of: b.componentID).map(\.name) == ["Primary", "Secondary"])
    }

    // MARK: - The grid on Edit Original

    /// Edit Original lays the drawings out as Variant rows by Size columns,
    /// and the grid can be read back with its option names along the edges.
    @Test func editOriginalLaysTheDrawingsOutAsAGrid() throws {
        let b = buttonWithSize()
        let space = try #require(b.doc.editingSpace(forComponent: b.componentID))
        let grid = try #require(space.componentVariantGrid(of: b.componentID))
        #expect(grid.rows.map(\.name) == ["Primary", "Secondary"])
        #expect(grid.columns.map(\.name) == ["Default", "Large"])
        let drawings = space.componentVersions(of: b.componentID)
        func box(_ id: UUID) -> CGRect {
            space.canvasBounds(of: drawings.first { $0.id == id }!.layerID)!
        }
        // Primary · Large sits to the right of Primary · Default, on its row.
        #expect(box(b.primaryLarge).minX > box(b.primary).maxX)
        #expect(abs(box(b.primaryLarge).midY - box(b.primary).midY) < 0.5)
        // Secondary sits under Primary, in its column.
        #expect(box(b.secondary).minY > box(b.primary).maxY)
        #expect(abs(box(b.secondary).midX - box(b.primary).midX) < 0.5)
        // Room is left above and to the left for the names along the edges.
        #expect(box(b.primary).minX >= PhotonzDocument.editingSpaceMargin + 40)
        #expect(box(b.primary).minY >= PhotonzDocument.editingSpaceMargin + 20)
        // Everything fits on the page.
        let page = CGRect(origin: .zero, size: space.canvasSize)
        for drawing in drawings { #expect(page.contains(box(drawing.id))) }
    }

    /// A one-question component opens the way it always did: no grid.
    @Test func aOneQuestionComponentHasNoGrid() throws {
        let b = button()
        let space = try #require(b.doc.editingSpace(forComponent: b.componentID))
        #expect(space.componentVariantGrid(of: b.componentID) == nil)
    }

    /// A drawing dragged out of its cell turns the edge names off rather than
    /// leaving them pointing at the wrong drawings.
    @Test func aGridSomebodyRearrangedHasNoEdges() throws {
        let b = buttonWithSize()
        var space = try #require(b.doc.editingSpace(forComponent: b.componentID))
        let drawings = space.componentVersions(of: b.componentID)
        let secondary = drawings.first { $0.id == b.secondary }!
        let primary = space.canvasBounds(of: drawings[0].layerID)!
        space.updateLayer(id: secondary.layerID) { $0.frame.origin.y = primary.minY + 5 }
        #expect(space.componentVariantGrid(of: b.componentID) == nil)
        // Laying it out again puts it back.
        let r12 = space.layOutComponentVariantGrid(componentID: b.componentID)
        #expect(r12)
        #expect(space.componentVariantGrid(of: b.componentID) != nil)
    }

    // MARK: - The panel the grid sits in

    /// The page opens round the grid rather than leaving it small in the
    /// corner of a page the document's size: the drawings, the room for the
    /// names along the edges and the margin, and nothing else.
    @Test func theEditOriginalPageFitsTheGrid() throws {
        let b = buttonWithSize()
        let space = try #require(b.doc.editingSpace(forComponent: b.componentID))
        let grid = try #require(space.componentVariantGrid(of: b.componentID))
        let margin = PhotonzDocument.editingSpaceMargin
        #expect(space.canvasSize.width < b.doc.canvasSize.width)
        #expect(space.canvasSize.height < b.doc.canvasSize.height)
        #expect(abs(space.canvasSize.width - (grid.bounds.maxX + margin)) <= 1)
        #expect(abs(space.canvasSize.height - (grid.bounds.maxY + margin)) <= 1)
    }

    /// Something drawn loose beside the grid keeps the page big enough to
    /// hold it when the grid is laid out again.
    @Test func aLooseDrawingKeepsItsPage() throws {
        let b = buttonWithSize()
        var space = try #require(b.doc.editingSpace(forComponent: b.componentID))
        space.layers.append(box("Note", CGRect(x: 900, y: 700, width: 50, height: 30)))
        space.layOutComponentVariantGridOnPage(componentID: b.componentID)
        #expect(space.canvasSize.width >= 950 + PhotonzDocument.editingSpaceMargin)
        #expect(space.canvasSize.height >= 730 + PhotonzDocument.editingSpaceMargin)
    }

    /// The panel the variants mock draws round its matrix (`.pmatrix`): the
    /// column answers in a band above the drawings, the row answers to their
    /// left, and the padding all round, everything inside one rounded box.
    @Test func thePanelHoldsTheNamesAndTheDrawings() {
        let drawings = CGRect(x: 300, y: 200, width: 400, height: 160)
        let panel = ComponentVariantGrid.Panel(around: drawings, rowNameWidth: 70, columnNameHeight: 12)
        #expect(panel.frame.contains(drawings))
        // The column band sits above the drawings, inside the panel.
        #expect(panel.columnNameBand.maxY < drawings.minY)
        #expect(panel.columnNameBand.minY > panel.frame.minY)
        #expect(panel.columnNameBand.height == 12)
        // The row names end short of the drawings and start inside the panel.
        #expect(panel.rowNameRight < drawings.minX)
        #expect(panel.rowNameRight - 70 > panel.frame.minX)
        // The mock's padding on every side.
        let pad = ComponentVariantGrid.Panel.padding
        #expect(panel.frame.minY == panel.columnNameBand.minY - pad)
        #expect(panel.frame.minX == panel.rowNameRight - 70 - pad)
        #expect(panel.frame.maxX >= drawings.maxX + pad)
        #expect(panel.frame.maxY >= drawings.maxY + pad)
        #expect(ComponentVariantGrid.Panel.cornerRadius == 13)
    }

    /// The panel is painted what the drawings were made to sit on: the
    /// document's Surface, white until somebody recolours it, so a Ghost
    /// look's quiet words read on it the way they do in a real screen.
    @Test func thePanelIsPaintedTheDocumentsSurface() {
        var b = buttonWithSize()
        #expect(b.doc.componentVariantGridSurfaceHex == "#FFFFFF")
        var surface = StarterStyle.surface.colorStyle
        surface.colorHex = "#202024"
        b.doc.colorStyles.append(surface)
        #expect(b.doc.componentVariantGridSurfaceHex == "#202024")
    }

    /// The names along the edges are inked for the panel under them: dark on
    /// a light panel, light on a dark one.
    @Test func theNamesAreInkedForThePanel() {
        #expect(!ComponentVariantGrid.namesWantLightInk(onHex: "#FFFFFF"))
        #expect(!ComponentVariantGrid.namesWantLightInk(onHex: "#F2F2F7"))
        #expect(ComponentVariantGrid.namesWantLightInk(onHex: "#202024"))
        #expect(ComponentVariantGrid.namesWantLightInk(onHex: "#4C6FFF"))
    }

    /// A drawing narrower than its column's name still gets a column wide
    /// enough for the name, so two names never run together into one
    /// ("DEFAULT LARGE" over a pair of small badges).
    @Test func aColumnIsAsWideAsItsName() throws {
        let b = buttonWithSize(width: 16)
        let space = try #require(b.doc.editingSpace(forComponent: b.componentID))
        let grid = try #require(space.componentVariantGrid(of: b.componentID))
        #expect(grid.columns.map(\.name) == ["Default", "Large"])
        let centres = grid.columns.map(\.box.midX)
        let room = PhotonzDocument.variantGridColumnNameRoom("Default") / 2
            + PhotonzDocument.variantGridColumnNameRoom("Large") / 2
        #expect(centres[1] - centres[0] >= room)
    }

    /// The columns share the width evenly, the way the mock's matrix gives
    /// each `1fr`, and the drawings sit closer than loose drawings on a page:
    /// a cell's padding and the matrix gap, not the page's gap.
    @Test func theColumnsShareTheWidthEvenly() throws {
        let b = buttonWithSize()
        var space = try #require(b.doc.editingSpace(forComponent: b.componentID))
        let drawings = space.componentVersions(of: b.componentID)
        let large = try #require(drawings.first { $0.id == b.primaryLarge })
        let inside = try #require(space.layer(id: large.layerID)?.children.first?.id)
        space.updateLayer(id: inside) { $0.frame.size.width = 200 }
        #expect(space.canvasBounds(of: large.layerID)?.width == 200)
        space.layOutComponentVariantGridOnPage(componentID: b.componentID)
        let grid = try #require(space.componentVariantGrid(of: b.componentID))
        let primary = try #require(space.canvasBounds(of: drawings[0].layerID))
        let wide = try #require(space.canvasBounds(of: large.layerID))
        // Centre to centre is one column's width plus the gap: the widest.
        #expect(abs((wide.midX - primary.midX) - (200 + PhotonzDocument.variantGridGap)) <= 1)
        #expect(grid.columns.count == 2)
        let secondary = try #require(drawings.first { $0.id == b.secondary })
        let below = try #require(space.canvasBounds(of: secondary.layerID))
        #expect(abs(below.minY - primary.maxY - PhotonzDocument.variantGridGap) <= 1)
        #expect(PhotonzDocument.variantGridGap < PhotonzDocument.editingSpaceGap)
    }
}
