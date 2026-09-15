import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Several shapes turn into ONE path, welded where their ends meet
/// (`PathJoining.swift`). Three lines that meet are a triangle, not three lines
/// in a bag.
@Suite("Several shapes into one path")
struct PathJoiningTests {

    // MARK: Helpers

    /// A straight run between two points, the way a line converts
    /// (`AnnotationContent.asPath`): two anchors, no fill, open.
    private func run(_ from: CGPoint, _ to: CGPoint,
                     colorHex: String = "#FF3B30", width: CGFloat = 4) -> PathContent {
        var path = PathContent.line(from: from, to: to)
        path.paint = Paint(hex: colorHex)
        path.strokeWidth = width
        path.fill = nil
        return path
    }

    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    /// The document-space corners of a triangle nobody could draw by accident.
    private let a = CGPoint(x: 100, y: 40)
    private let b = CGPoint(x: 180, y: 180)
    private let c = CGPoint(x: 20, y: 180)

    /// The outline's points as a cycle, so two walks of the same triangle can
    /// be compared whichever corner they start at and whichever way round they
    /// go.
    private func ring(_ path: PathContent) -> Set<[String]> {
        let points = path.anchors.map { "\(($0.point.x * 1000).rounded()),\(($0.point.y * 1000).rounded())" }
        guard !points.isEmpty else { return [] }
        var walks: Set<[String]> = []
        for direction in [points, points.reversed()] {
            for shift in direction.indices {
                walks.insert(Array(direction[shift...] + direction[..<shift]))
            }
        }
        return walks
    }

    private func layer(_ from: CGPoint, _ to: CGPoint, name: String = "Line",
                       width: CGFloat = 4, colorHex: String = "#FF3B30") -> Layer {
        let shape = AnnotationContent(shape: .line, strokeWidth: width, colorHex: colorHex,
                                      start: .zero, end: .zero)
        var made = AnnotationBuilder.layer(content: shape, from: from, to: to)
        made.name = name
        return made
    }

    /// A line layer's two ends, back in document coordinates.
    private func ends(_ layer: Layer) -> [CGPoint] {
        guard let path = layer.path else { return [] }
        return [path.anchors.first?.point, path.anchors.last?.point].compactMap { $0 }
            .map { CGPoint(x: $0.x + layer.frame.origin.x, y: $0.y + layer.frame.origin.y) }
    }

    // MARK: - Runs that meet end to end

    @Test("Three runs that meet become one closed outline of three corners")
    func threeRunsBecomeATriangle() throws {
        let runs = PathJoin.join([run(a, b), run(b, c), run(c, a)])
        #expect(runs.count == 1)
        let joined = try #require(runs.first)
        #expect(joined.sources.count == 3)
        #expect(joined.didClose)
        #expect(joined.path.isClosed)
        #expect(joined.path.anchors.count == 3)
        #expect(joined.pulledTogether == 0)
        #expect(ring(joined.path).contains(ring(PathContent(anchors: [a, b, c].map { PathAnchor(point: $0) },
                                                            isClosed: true)).first ?? []))
        // Closed AND enclosing an area is what makes it fillable.
        #expect(joined.path.enclosesAnArea)
    }

    @Test("Two runs that meet at one end only become one open outline")
    func twoRunsStayOpen() throws {
        let runs = PathJoin.join([run(a, b), run(b, c)])
        #expect(runs.count == 1)
        let joined = try #require(runs.first)
        #expect(!joined.didClose)
        #expect(!joined.path.isClosed)
        #expect(joined.path.anchors.map(\.point) == [a, b, c])
    }

    @Test("A run drawn the other way round is turned before it is carried on")
    func directionDoesNotMatter() throws {
        let forwards = try #require(PathJoin.join([run(a, b), run(b, c), run(c, a)]).first)
        // The middle one drawn from c to b instead, and the last from a to c.
        let backwards = try #require(PathJoin.join([run(a, b), run(c, b), run(a, c)]).first)
        #expect(backwards.didClose)
        #expect(ring(backwards.path) == ring(forwards.path))
    }

    @Test("The order they were picked in does not change the outline")
    func orderDoesNotMatter() throws {
        let one = try #require(PathJoin.join([run(a, b), run(b, c), run(c, a)]).first)
        let two = try #require(PathJoin.join([run(c, a), run(a, b), run(b, c)]).first)
        let three = try #require(PathJoin.join([run(b, c), run(c, a), run(a, b)]).first)
        #expect(one.path.anchors == two.path.anchors)
        #expect(one.path.anchors == three.path.anchors)
    }

    // MARK: - Ends that are near but not touching

    @Test("Ends within the tolerance are pulled together, and the joint sits half way")
    func aNearMissJoins() throws {
        let gapped = point(b.x + 1, b.y + 1)   // 1.41pt away from b, inside the 2pt tolerance
        let runs = PathJoin.join([run(a, b), run(gapped, c)])
        #expect(runs.count == 1)
        let joined = try #require(runs.first)
        #expect(joined.pulledTogether == 1)
        let joint = try #require(joined.path.anchors.dropFirst().first)
        #expect(abs(joint.point.x - (b.x + 0.5)) < 1e-9)
        #expect(abs(joint.point.y - (b.y + 0.5)) < 1e-9)
    }

    @Test("Ends further apart than the tolerance are left alone, and stay two outlines")
    func aWideMissDoesNotJoin() {
        let gapped = point(b.x + 3, b.y)       // 3pt away, outside the tolerance
        let runs = PathJoin.join([run(a, b), run(gapped, c)])
        #expect(runs.count == 2)
        #expect(runs.allSatisfy { $0.sources.count == 1 })
        #expect(runs.allSatisfy { !$0.didClose })
        #expect(runs.allSatisfy { $0.pulledTogether == 0 })
    }

    @Test("The tolerance is a number the caller can state, and nothing joins at zero")
    func theToleranceIsStated() {
        let gapped = point(b.x + 1, b.y)
        #expect(PathJoin.join([run(a, b), run(gapped, c)], tolerance: 0).count == 2)
        #expect(PathJoin.join([run(a, b), run(gapped, c)], tolerance: 2).count == 1)
        #expect(PathJoin.tolerance == 2)
    }

    // MARK: - What does not join

    @Test("Shapes that do not touch at all come back one outline each")
    func untouchingShapesStaySeparate() {
        let far = run(point(400, 400), point(500, 500))
        let runs = PathJoin.join([run(a, b), far])
        #expect(runs.count == 2)
        #expect(runs.map(\.sources) == [[0], [1]])
        #expect(runs.allSatisfy { !$0.changedAnything })
    }

    @Test("A closed outline has no free ends, so a rectangle comes straight back")
    func closedShapesPassThrough() throws {
        let box = PathContent.rectangle(in: CGRect(x: 0, y: 0, width: 50, height: 50))
        let runs = PathJoin.join([box, run(a, b)])
        #expect(runs.count == 2)
        #expect(runs.first?.path == box)
    }

    @Test("An outline that doubles back on itself is not closed into nothing")
    func aFlatRingIsNotClosed() {
        // Out and back along the same line: closing it would sweep no area and
        // leave a layer painting no pixels, which the Pen already refuses.
        let runs = PathJoin.join([run(a, b), run(b, a)])
        #expect(runs.count == 1)
        #expect(runs.first?.didClose == false)
        #expect(runs.first?.path.isClosed == false)
    }

    @Test("One run whose own two ends meet closes on its own")
    func oneRunCanCloseItself() throws {
        var squiggle = PathContent(anchors: [a, b, c].map { PathAnchor(point: $0) },
                                   isClosed: false)
        squiggle.anchors.append(PathAnchor(point: point(a.x + 1, a.y)))
        let runs = PathJoin.join([squiggle])
        let joined = try #require(runs.first)
        #expect(joined.didClose)
        #expect(joined.path.anchors.count == 3)
    }

    // MARK: - What the joined outline wears

    @Test("The joined outline keeps the look of the first shape handed over")
    func theLookComesFromTheFirst() throws {
        let runs = PathJoin.join([run(a, b, colorHex: "#112233", width: 8),
                                  run(b, c, colorHex: "#445566", width: 2)])
        let joined = try #require(runs.first)
        #expect(joined.path.colorHex == "#112233")
        #expect(joined.path.strokeWidth == 8)
    }

    @Test("Welded corners are drawn round where the ends they replace were round")
    func weldedCornersKeepThePicture() throws {
        // Two round-capped lines meeting at a point paint a full disc there,
        // which is exactly what one round join paints, so the picture does not
        // change at the joint.
        var first = run(a, b), second = run(b, c)
        first.lineEnd = .round
        second.lineEnd = .round
        let joined = try #require(PathJoin.join([first, second]).first)
        #expect(joined.path.lineCorner == .round)

        // Butt ends painted no disc, so nothing is claimed about the corner and
        // the shape's own setting stands.
        first.lineEnd = .flat
        first.lineCorner = .sharp
        second.lineEnd = .flat
        let butted = try #require(PathJoin.join([first, second]).first)
        #expect(butted.path.lineCorner == .sharp)
    }

    @Test("Turning an outline round draws the same shape the other way")
    func reversingKeepsTheShape() {
        var curved = PathContent(anchors: [
            PathAnchor(point: a, handleOut: point(20, 0)),
            PathAnchor(point: b, handleIn: point(-10, -30), handleOut: point(10, 30), kind: .smooth),
            PathAnchor(point: c)
        ])
        curved.isClosed = false
        let back = curved.reversed()
        #expect(back.anchors.map(\.point) == [c, b, a])
        #expect(back.anchors[1].handleIn == curved.anchors[1].handleOut)
        #expect(back.anchors[1].handleOut == curved.anchors[1].handleIn)
        #expect(back.reversed() == curved)
    }

    // MARK: - The document: three line LAYERS become one path layer

    private func documentOfThreeLines() -> (PhotonzDocument, [Layer]) {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        let lines = [layer(a, b, name: "Line"), layer(b, c, name: "Line 2"),
                     layer(c, a, name: "Line 3")]
        for line in lines { document.addLayer(line) }
        return (document, lines)
    }

    @Test("Three line layers picked together become ONE closed path layer")
    func threeLineLayersBecomeOne() throws {
        var (document, lines) = documentOfThreeLines()
        let plan = document.turnLayersIntoPath(ids: Set(lines.map(\.id)))
        #expect(document.layers.count == 1)
        let survivor = try #require(document.layers.first)
        let outline = try #require(survivor.path)
        #expect(outline.isClosed)
        #expect(outline.anchors.count == 3)
        #expect(outline.enclosesAnArea)
        #expect(plan.takes == 3)
        #expect(plan.leaves == 1)
        #expect(plan.closed == 1)
        #expect(plan.pulledTogether == 0)
    }

    @Test("The command acts on everything picked, not on one row of the several")
    func everyPickedRowIsActedOn() throws {
        // Three shapes that touch nothing: the old command turned one of them
        // and left the other two as they were.
        var document = PhotonzDocument(canvasSize: CGSize(width: 800, height: 600))
        let ids = [CGPoint(x: 10, y: 10), CGPoint(x: 300, y: 10), CGPoint(x: 600, y: 10)]
            .map { origin -> UUID in
                let shape = AnnotationContent(shape: .rectangle, strokeWidth: 4, colorHex: "#FF3B30",
                                              start: .zero, end: CGPoint(x: 80, y: 60))
                let made = Layer(name: "Rectangle", content: .annotation(shape),
                                 frame: CGRect(origin: origin, size: CGSize(width: 80, height: 60)))
                document.addLayer(made)
                return made.id
            }
        let plan = document.turnLayersIntoPath(ids: Set(ids))
        #expect(plan.takes == 3)
        #expect(plan.leaves == 3)
        #expect(ids.allSatisfy { document.layer(id: $0)?.path != nil })
        #expect(document.layers.count == 3)
    }

    @Test("The survivor keeps its place, its id and its effects, and is renamed off Line")
    func theSurvivorKeepsWhatItWas() throws {
        var (document, lines) = documentOfThreeLines()
        document.updateLayer(id: lines[2].id) { $0.style.opacity = 0.4 }
        let plan = document.turnLayersIntoPath(ids: Set(lines.map(\.id)))
        // The topmost of the three is the one that survives.
        let survivor = try #require(document.layer(id: lines[2].id))
        #expect(document.layers.map(\.id) == [survivor.id])
        #expect(survivor.style.opacity == 0.4)
        // "Line 3" is a poor name for a triangle, and it was a name the app
        // wrote rather than one a person typed.
        #expect(survivor.name == PathBuilder.defaultName)
        #expect(plan.keeper == "Line 3")
    }

    @Test("A name somebody typed survives the join")
    func aTypedNameIsKept() throws {
        var (document, lines) = documentOfThreeLines()
        document.updateLayer(id: lines[2].id) { $0.name = "Roof" }
        document.turnLayersIntoPath(ids: Set(lines.map(\.id)))
        #expect(document.layer(id: lines[2].id)?.name == "Roof")
    }

    @Test("The outline lands exactly where the lines were")
    func nothingMoves() throws {
        var (document, lines) = documentOfThreeLines()
        document.turnLayersIntoPath(ids: Set(lines.map(\.id)))
        let survivor = try #require(document.layers.first)
        let outline = try #require(survivor.path)
        let corners = outline.anchors.map {
            CGPoint(x: $0.point.x + survivor.frame.origin.x, y: $0.point.y + survivor.frame.origin.y)
        }
        for corner in [a, b, c] {
            #expect(corners.contains { PathJoin.distance($0, corner) < 1e-6 })
        }
    }

    @Test("It is one undo step, and undo brings back the three separate lines")
    func oneUndoStep() throws {
        let (document, lines) = documentOfThreeLines()
        var history = History(document: document)
        _ = history.perform { $0.turnLayersIntoPath(ids: Set(lines.map(\.id))) }
        #expect(history.current.layers.count == 1)
        history.undo()
        #expect(history.current.layers.count == 3)
        for line in lines {
            let back = try #require(history.current.layer(id: line.id))
            #expect(back.annotation?.shape == .line)
            #expect(back == line)
        }
    }

    @Test("A locked layer is never swallowed by a join")
    func lockedLayersStayPut() throws {
        var (document, lines) = documentOfThreeLines()
        document.updateLayer(id: lines[0].id) { $0.isLocked = true }
        document.turnLayersIntoPath(ids: Set(lines.map(\.id)))
        #expect(document.layer(id: lines[0].id) != nil)
        #expect(document.layers.count == 2)
    }

    @Test("A rotated shape is not welded onto anything, because its outline has moved")
    func rotatedShapesDoNotJoin() throws {
        var (document, lines) = documentOfThreeLines()
        document.updateLayer(id: lines[1].id) { $0.transform = LayerTransform(rotation: .pi / 6) }
        let plan = document.turnLayersIntoPath(ids: Set(lines.map(\.id)))
        #expect(document.layers.count == 2)
        #expect(plan.takes == 3)
        #expect(plan.leaves == 2)
    }

    @Test("Layers that have no outline to find are left alone rather than failing it all")
    func layersWithNoOutlineAreLeftAlone() throws {
        var (document, lines) = documentOfThreeLines()
        let picture = Layer(name: "Screenshot", content: .image(ImageRef(pixelSize: CGSize(width: 100, height: 100))),
                            frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        document.addLayer(picture)
        let plan = document.turnLayersIntoPath(ids: Set(lines.map(\.id) + [picture.id]))
        #expect(plan.takes == 3)
        #expect(document.layer(id: picture.id)?.path == nil)
    }

    @Test("An open path already on the canvas joins onto a line picked with it")
    func anExistingPathJoinsOn() throws {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        let drawn = PathBuilder.layer(run(a, b), at: point(min(a.x, b.x), min(a.y, b.y)))
        document.addLayer(drawn)
        let line = layer(b, c)
        document.addLayer(line)
        let plan = document.turnLayersIntoPath(ids: [drawn.id, line.id])
        #expect(plan.takes == 2)
        #expect(plan.leaves == 1)
        #expect(document.layers.count == 1)
    }

    // MARK: - The question it asks first

    @Test("The question says how many shapes become how many paths")
    func theQuestionCounts() {
        let one = TurnIntoPathQuestion(plan: TurnIntoPathPlan(takes: 3, leaves: 1, closed: 1,
                                                             keeper: "Line 3"))
        #expect(one.title == "Turn these 3 shapes into one path?")
        let two = TurnIntoPathQuestion(plan: TurnIntoPathPlan(takes: 4, leaves: 2))
        #expect(two.title == "Turn these 4 shapes into 2 paths?")
        let both = TurnIntoPathQuestion(plan: TurnIntoPathPlan(takes: 2, leaves: 1))
        #expect(both.title == "Turn both shapes into one path?")
    }

    @Test("The question announces the closing, because that is the visible change")
    func theQuestionAnnouncesClosing() {
        let question = TurnIntoPathQuestion(plan: TurnIntoPathPlan(takes: 3, leaves: 1, closed: 1))
        #expect(question.message.contains("Their ends meet"))
        #expect(question.message.contains("closes"))
        #expect(question.message.contains("paint inside it"))
        #expect(question.message.contains("Undo puts it back"))
    }

    @Test("The question states the tolerance rather than guessing silently")
    func theQuestionStatesTheTolerance() {
        let missed = TurnIntoPathQuestion(plan: TurnIntoPathPlan(takes: 3, leaves: 3, openRuns: 3))
        #expect(missed.message.contains("within 2 pt"))
        #expect(missed.message.contains("stay separate outlines"))

        let pulled = TurnIntoPathQuestion(plan: TurnIntoPathPlan(takes: 3, leaves: 1, closed: 1,
                                                                pulledTogether: 1))
        #expect(pulled.message.contains("near rather than touching"))
        #expect(pulled.message.contains("within 2 pt"))
    }

    @Test("The question owns up when the shapes are not painted alike")
    func theQuestionOwnsUpToMixedLooks() {
        let mixed = TurnIntoPathQuestion(plan: TurnIntoPathPlan(takes: 2, leaves: 1,
                                                               mixedLooks: true, keeper: "Line 2"))
        #expect(mixed.message.contains("not all painted alike"))
        #expect(mixed.message.contains("Line 2"))
    }

    @Test("One shape asks the question it always asked")
    func oneShapeKeepsItsOwnQuestion() {
        #expect(TurnIntoPathQuestion(plan: TurnIntoPathPlan(takes: 1, leaves: 1),
                                     pluralOnly: true) == nil)
        #expect(TurnIntoPathQuestion(plan: TurnIntoPathPlan(takes: 2, leaves: 1),
                                     pluralOnly: true) != nil)
    }

    @Test("A mixed batch reports both what joined and what did not")
    func aMixedBatchReadsHonestly() throws {
        // Two that meet, and one across the canvas that meets nothing.
        var document = PhotonzDocument(canvasSize: CGSize(width: 600, height: 400))
        let joined = [layer(a, b), layer(b, c)]
        let loner = layer(point(400, 300), point(500, 350))
        for line in joined + [loner] { document.addLayer(line) }
        let plan = document.turnLayersIntoPath(ids: Set((joined + [loner]).map(\.id)))
        #expect(plan.takes == 3)
        #expect(plan.leaves == 2)
        #expect(plan.closed == 0)
        let question = TurnIntoPathQuestion(plan: plan)
        #expect(question.title == "Turn these 3 shapes into 2 paths?")
        #expect(question.message.contains("the rest stay as they are"))
    }
}

/// The sentences the plural question writes for selections that cannot join.
@Suite("Turning several shapes that have no ends to meet")
struct TurnIntoPathClosedShapesTests {

    private func rectangle(at origin: CGPoint) -> Layer {
        let shape = AnnotationContent(shape: .rectangle, strokeWidth: 4, colorHex: "#FF3B30",
                                      start: .zero, end: CGPoint(x: 80, y: 60))
        return Layer(name: "Rectangle", content: .annotation(shape),
                     frame: CGRect(origin: origin, size: CGSize(width: 80, height: 60)))
    }

    @Test("Closed shapes are never told their ends did not meet, because they have none")
    func closedShapesGetTheirOwnSentence() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 600, height: 400))
        let boxes = [CGPoint(x: 10, y: 10), CGPoint(x: 200, y: 10), CGPoint(x: 400, y: 10)]
            .map { rectangle(at: $0) }
        for box in boxes { document.addLayer(box) }
        let plan = document.turnLayersIntoPath(ids: Set(boxes.map(\.id)))
        #expect(plan.takes == 3)
        #expect(plan.leaves == 3)
        #expect(plan.openRuns == 0)
        let question = TurnIntoPathQuestion(plan: plan)
        #expect(question.title == "Turn these 3 shapes into 3 paths?")
        #expect(question.message.contains("Each becomes its own path."))
        #expect(!question.message.contains("ends"))
    }

    @Test("Lines that miss each other ARE told their ends did not meet")
    func openRunsGetTheToleranceSentence() {
        var document = PhotonzDocument(canvasSize: CGSize(width: 600, height: 400))
        let shape = AnnotationContent(shape: .line, strokeWidth: 4, colorHex: "#FF3B30",
                                      start: .zero, end: .zero)
        let lines = [
            AnnotationBuilder.layer(content: shape, from: CGPoint(x: 20, y: 20),
                                    to: CGPoint(x: 120, y: 20)),
            AnnotationBuilder.layer(content: shape, from: CGPoint(x: 300, y: 300),
                                    to: CGPoint(x: 400, y: 300))
        ]
        for line in lines { document.addLayer(line) }
        let plan = document.turnLayersIntoPath(ids: Set(lines.map(\.id)))
        #expect(plan.openRuns == 2)
        #expect(TurnIntoPathQuestion(plan: plan).message.contains("within 2 pt"))
    }
}
