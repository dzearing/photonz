import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// One outline you already finished, shut (`PathClosing.swift`).
///
/// The Pen closes a path only WHILE you are drawing it, by clicking back on
/// the first point. Press Return and the run is open for good, so it can never
/// be filled, and somebody building an icon is exactly the person who finishes
/// an outline, looks at it and then wants it closed.
@Suite("Closing an outline you already finished")
struct PathClosingTests {

    // MARK: Helpers

    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    /// An open run through the points given, corners all the way.
    private func run(_ points: [CGPoint]) -> PathContent {
        var path = PathContent(anchors: points.map { PathAnchor(point: $0) })
        path.fill = nil
        return path
    }

    /// Three corners of a triangle with the last run missing: what the Pen
    /// leaves when you stop before clicking back on the start.
    private let a = CGPoint(x: 100, y: 40)
    private let b = CGPoint(x: 180, y: 180)
    private let c = CGPoint(x: 20, y: 180)

    private func openTriangle() -> PathContent { run([a, b, c]) }

    private func documentOf(_ contents: [PathContent]) -> (PhotonzDocument, [Layer]) {
        var document = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300))
        var made: [Layer] = []
        for content in contents {
            let layer = PathBuilder.layer(content, at: content.bounds.origin)
            document.addLayer(layer)
            made.append(layer)
        }
        return (document, made)
    }

    // MARK: - The geometry

    @Test("Closing an open run leaves a ring with an inside")
    func closingLeavesARing() throws {
        let closed = try #require(openTriangle().closingTheOutline())
        #expect(closed.isClosed)
        #expect(closed.anchors.count == 3)
        #expect(closed.enclosesAnArea)
    }

    @Test("Neither end moves: the two ends are joined by a straight run")
    func neitherEndMoves() throws {
        let closed = try #require(openTriangle().closingTheOutline())
        #expect(closed.anchors.first?.point == a)
        #expect(closed.anchors.last?.point == c)
        // The run that closes the ring is the one leaving the last anchor and
        // arriving at the first. Straight means no handle on either side of it.
        #expect(closed.anchors.first?.handleIn == nil)
        #expect(closed.anchors.last?.handleOut == nil)
    }

    @Test("A gap of any size closes: the tolerance is the join's, not this")
    func anyGapCloses() throws {
        // Ends 160 pt apart, eighty times PathJoin's two point tolerance.
        let wide = try #require(run([a, b, c]).closingTheOutline())
        #expect(wide.isClosed)
        #expect(PathJoin.distance(a, c) > PathJoin.tolerance * 50)
    }

    @Test("Handles already on the outline are kept, only the closing run is straightened")
    func keepsTheCurvesItAlreadyHad() throws {
        var curved = openTriangle()
        curved.anchors[1].handleIn = point(-20, -10)
        curved.anchors[1].handleOut = point(20, 10)
        curved.anchors[1].kind = .smooth
        // Invisible on an open path: a handle on the way IN to the first anchor
        // and OUT of the last shapes only the run that does not exist yet.
        curved.anchors[0].handleIn = point(-90, 30)
        curved.anchors[2].handleOut = point(90, 30)
        let closed = try #require(curved.closingTheOutline())
        #expect(closed.anchors[1].handleIn == point(-20, -10))
        #expect(closed.anchors[1].handleOut == point(20, 10))
        #expect(closed.anchors[0].handleIn == nil)
        #expect(closed.anchors[2].handleOut == nil)
    }

    @Test("Two ends already sitting on the same spot become one point, not two")
    func endsOnTheSameSpotMerge() throws {
        let closed = try #require(run([a, b, c, a]).closingTheOutline())
        #expect(closed.isClosed)
        #expect(closed.anchors.count == 3)
        #expect(closed.anchors.map(\.point) == [a, b, c])
    }

    @Test("An outline whose points are in a line is refused")
    func flatOutlineIsRefused() {
        #expect(run([point(0, 0), point(50, 0), point(120, 0)]).closingTheOutline() == nil)
        #expect(run([point(0, 0), point(50, 0)]).closingTheOutline() == nil)
    }

    @Test("Two points with a curve on them close, the same shape the Pen allows")
    func twoPointsWithACurveClose() throws {
        var leaf = run([point(0, 0), point(100, 0)])
        leaf.anchors[0].handleOut = point(30, 40)
        leaf.anchors[1].handleIn = point(-30, 40)
        let closed = try #require(leaf.closingTheOutline())
        #expect(closed.isClosed)
        #expect(closed.enclosesAnArea)
    }

    @Test("A path that is already closed has nothing to do")
    func alreadyClosedIsRefused() {
        var ring = openTriangle()
        ring.isClosed = true
        #expect(ring.closingTheOutline() == nil)
    }

    // MARK: - What the command is offered on

    @Test("One open path picked on its own is offered the close")
    func onePathIsOffered() {
        let (document, layers) = documentOf([openTriangle()])
        #expect(document.openPathsThatCouldClose(ids: [layers[0].id]) == Set([layers[0].id]))
    }

    @Test("A closed path and a locked one are not offered it")
    func closedAndLockedAreLeftOut() {
        var ring = openTriangle()
        ring.isClosed = true
        var (document, layers) = documentOf([ring, openTriangle()])
        #expect(document.openPathsThatCouldClose(ids: [layers[0].id]).isEmpty)
        document.updateLayer(id: layers[1].id) { $0.isLocked = true }
        #expect(document.openPathsThatCouldClose(ids: [layers[1].id]).isEmpty)
    }

    @Test("It is offered on a flat outline too, and refuses out loud instead")
    func flatOutlineIsStillOffered() {
        // Offered and honest beats dimmed and silent: a row dimmed because the
        // points happen to be in a line teaches nobody what to do about it.
        let (document, layers) = documentOf([run([point(0, 0), point(50, 0), point(120, 0)])])
        #expect(document.openPathsThatCouldClose(ids: [layers[0].id]).count == 1)
        let plan = document.closingPaths(ids: [layers[0].id]).plan
        #expect(plan.isEmpty)
        #expect(plan.refused == 1)
    }

    // MARK: - What it does to the document

    @Test("Closing one path leaves a filled ring in one undo step")
    func closingOnePathInOneStep() throws {
        let (start, layers) = documentOf([openTriangle()])
        var history = History(document: start)
        _ = history.perform { $0.closePaths(ids: [layers[0].id]) }
        let closed = try #require(history.current.layer(id: layers[0].id)?.path)
        #expect(closed.isClosed)
        #expect(closed.enclosesAnArea)
        history.undo()
        #expect(history.current.layer(id: layers[0].id)?.path?.isClosed == false)
    }

    @Test("The plan says how many closed and how wide the widest gap was")
    func planSaysWhatHappened() {
        var (document, layers) = documentOf([openTriangle()])
        let plan = document.closePaths(ids: [layers[0].id])
        #expect(plan.closes == 1)
        #expect(plan.refused == 0)
        #expect((plan.gap - PathJoin.distance(a, c)).magnitude < 0.001)
        #expect(!plan.isEmpty)
    }

    @Test("The layer keeps its id, its name and where it sits")
    func theLayerSurvivesAsItself() throws {
        var (document, layers) = documentOf([openTriangle()])
        document.updateLayer(id: layers[0].id) { $0.name = "Roof" }
        let before = try #require(document.layer(id: layers[0].id)?.frame)
        document.closePaths(ids: [layers[0].id])
        let after = try #require(document.layer(id: layers[0].id))
        #expect(after.name == "Roof")
        #expect(after.frame == before)
    }

    @Test("Several picked outlines each close on their own ends")
    func severalCloseAtOnce() {
        var (document, layers) = documentOf([openTriangle(),
                                           run([point(200, 20), point(260, 90), point(200, 160)])])
        let plan = document.closePaths(ids: Set(layers.map(\.id)))
        #expect(plan.closes == 2)
        #expect(layers.allSatisfy { document.layer(id: $0.id)?.path?.isClosed == true })
    }

    @Test("The look is untouched: closing offers an inside rather than painting one")
    func closingOffersAnInsideRatherThanPaintingOne() throws {
        // The same bargain Join Paths already strikes: the shape closes, the
        // picture keeps the colour and line it had, and the Fill row turns up
        // on the panel for somebody to switch on. A command that filled the
        // outline itself would drop a solid block of colour on the canvas
        // nobody asked for.
        let (start, layers) = documentOf([openTriangle()])
        var document = start
        let before = try #require(document.layer(id: layers[0].id)?.path)
        document.closePaths(ids: [layers[0].id])
        let after = try #require(document.layer(id: layers[0].id))
        let closed = try #require(after.path)
        #expect(closed.paint == before.paint)
        #expect(closed.strokeWidth == before.strokeWidth)
        #expect(closed.fill == before.fill)
        // ...and the inside is offered now, where an open path had none.
        #expect(after.colorSlots.contains(.fill))
    }

    // MARK: - What it says first

    @Test("The question over one path names the gap and promises nothing moves")
    func questionOverOnePath() throws {
        let question = try #require(ClosePathQuestion(plan: ClosePathPlan(closes: 1, gap: 40)))
        #expect(question.title == "Close this path?")
        #expect(question.confirm == "Close Path")
        #expect(question.message.contains("40 pt"))
        #expect(question.message.lowercased().contains("straight run"))
        #expect(question.message.contains("Neither end moves"))
        #expect(question.message.contains("paint inside it"))
        #expect(question.message.contains("Undo puts it back."))
    }

    @Test("Ends already touching are not described as being joined across a gap")
    func questionWhenTheEndsAlreadyTouch() throws {
        let question = try #require(ClosePathQuestion(plan: ClosePathPlan(closes: 1, gap: 0)))
        #expect(!question.message.contains("0 pt"))
        #expect(question.message.contains("already in the same place"))
    }

    @Test("Several paths ask the plural question")
    func questionOverSeveralPaths() throws {
        let question = try #require(ClosePathQuestion(plan: ClosePathPlan(closes: 3, gap: 12)))
        #expect(question.title == "Close these 3 paths?")
        #expect(question.confirm == "Close Paths")
        let both = try #require(ClosePathQuestion(plan: ClosePathPlan(closes: 2, gap: 12)))
        #expect(both.title == "Close both paths?")
    }

    @Test("Nothing to close asks nothing")
    func nothingToCloseAsksNothing() {
        #expect(ClosePathQuestion(plan: ClosePathPlan(closes: 0, refused: 1)) == nil)
    }

    @Test("The refusal is the Pen's own, and says the way out")
    func refusalIsThePens() {
        let line = PathEditHint.nothingClosed()
        #expect(line.contains("in a line"))
        #expect(line.contains("no inside"))
        #expect(line.contains("Nothing closed"))
    }

    @Test("The line after it closed says what happened and how to go back")
    func chipAfterClosing() {
        #expect(PathEditHint.justClosed(paths: 1).contains("Closed"))
        #expect(PathEditHint.justClosed(paths: 1).contains("Command Z"))
        #expect(PathEditHint.justClosed(paths: 3).contains("3 paths"))
    }

    @Test("The menu row says Close Path and promises a question")
    func theMenuRow() {
        #expect(PathClose.menuItem == "Close Path\u{2026}")
    }
}
