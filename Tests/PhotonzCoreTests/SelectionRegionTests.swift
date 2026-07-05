import CoreGraphics
import PhotonzCore
import Testing

@Suite("SelectionRegion")
struct SelectionRegionTests {

    // MARK: Builders

    @Test func rectBuilderMatchesTheRect() throws {
        let region = try #require(SelectionRegion.rect(CGRect(x: 10, y: 20, width: 100, height: 50)))
        #expect(region.bounds == CGRect(x: 10, y: 20, width: 100, height: 50))
        #expect(region.contains(CGPoint(x: 60, y: 45)))
        #expect(!region.contains(CGPoint(x: 5, y: 45)))
        #expect(!region.contains(CGPoint(x: 60, y: 90)))
    }

    @Test func emptyRectYieldsNoRegion() {
        #expect(SelectionRegion.rect(.zero) == nil)
        #expect(SelectionRegion.rect(CGRect(x: 10, y: 10, width: 0, height: 40)) == nil)
    }

    @Test func ellipseBuilderFillsTheInscribedEllipse() throws {
        let region = try #require(SelectionRegion.ellipse(in: CGRect(x: 0, y: 0, width: 100, height: 100)))
        #expect(region.bounds == CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(region.contains(CGPoint(x: 50, y: 50)))
        // Bounding-box corners lie outside the inscribed ellipse.
        #expect(!region.contains(CGPoint(x: 3, y: 3)))
        #expect(!region.contains(CGPoint(x: 97, y: 97)))
    }

    @Test func emptyPathYieldsNoRegion() {
        #expect(SelectionRegion(path: CGMutablePath()) == nil)
    }

    // MARK: Booleans

    @Test func addingDisjointRectsKeepsBoth() throws {
        let a = try #require(SelectionRegion.rect(CGRect(x: 0, y: 0, width: 40, height: 40)))
        let b = try #require(SelectionRegion.rect(CGRect(x: 100, y: 100, width: 40, height: 40)))
        let union = try #require(a.combining(b, mode: .add))
        #expect(union.contains(CGPoint(x: 20, y: 20)))
        #expect(union.contains(CGPoint(x: 120, y: 120)))
        #expect(!union.contains(CGPoint(x: 70, y: 70)))
        #expect(union.bounds == CGRect(x: 0, y: 0, width: 140, height: 140))
    }

    @Test func addingOverlappingRectsMergesThem() throws {
        let a = try #require(SelectionRegion.rect(CGRect(x: 0, y: 0, width: 100, height: 100)))
        let b = try #require(SelectionRegion.rect(CGRect(x: 50, y: 50, width: 100, height: 100)))
        let union = try #require(a.combining(b, mode: .add))
        #expect(union.contains(CGPoint(x: 75, y: 75)))
        #expect(union.contains(CGPoint(x: 10, y: 10)))
        #expect(union.contains(CGPoint(x: 140, y: 140)))
        #expect(union.bounds == CGRect(x: 0, y: 0, width: 150, height: 150))
    }

    @Test func subtractRemovesTheOverlap() throws {
        let a = try #require(SelectionRegion.rect(CGRect(x: 0, y: 0, width: 100, height: 100)))
        let b = try #require(SelectionRegion.rect(CGRect(x: 50, y: 50, width: 100, height: 100)))
        let diff = try #require(a.combining(b, mode: .subtract))
        #expect(diff.contains(CGPoint(x: 10, y: 10)))
        #expect(!diff.contains(CGPoint(x: 75, y: 75)))
        #expect(!diff.contains(CGPoint(x: 140, y: 140)))
    }

    @Test func subtractingEverythingCollapsesToNil() throws {
        let a = try #require(SelectionRegion.rect(CGRect(x: 10, y: 10, width: 50, height: 50)))
        let all = try #require(SelectionRegion.rect(CGRect(x: 0, y: 0, width: 200, height: 200)))
        #expect(a.combining(all, mode: .subtract) == nil)
    }

    @Test func intersectKeepsOnlyTheOverlap() throws {
        let a = try #require(SelectionRegion.rect(CGRect(x: 0, y: 0, width: 100, height: 100)))
        let b = try #require(SelectionRegion.rect(CGRect(x: 50, y: 50, width: 100, height: 100)))
        let overlap = try #require(a.combining(b, mode: .intersect))
        #expect(overlap.bounds == CGRect(x: 50, y: 50, width: 50, height: 50))
        #expect(overlap.contains(CGPoint(x: 75, y: 75)))
        #expect(!overlap.contains(CGPoint(x: 10, y: 10)))
    }

    @Test func disjointIntersectCollapsesToNil() throws {
        let a = try #require(SelectionRegion.rect(CGRect(x: 0, y: 0, width: 40, height: 40)))
        let b = try #require(SelectionRegion.rect(CGRect(x: 100, y: 100, width: 40, height: 40)))
        #expect(a.combining(b, mode: .intersect) == nil)
    }

    @Test func replaceModeReturnsTheNewShape() throws {
        let a = try #require(SelectionRegion.rect(CGRect(x: 0, y: 0, width: 40, height: 40)))
        let b = try #require(SelectionRegion.rect(CGRect(x: 100, y: 100, width: 40, height: 40)))
        let replaced = try #require(a.combining(b, mode: .replace))
        #expect(replaced == b)
    }

    @Test func subtractCanPunchAHole() throws {
        let outer = try #require(SelectionRegion.rect(CGRect(x: 0, y: 0, width: 100, height: 100)))
        let inner = try #require(SelectionRegion.rect(CGRect(x: 25, y: 25, width: 50, height: 50)))
        let donut = try #require(outer.combining(inner, mode: .subtract))
        #expect(!donut.contains(CGPoint(x: 50, y: 50)))
        #expect(donut.contains(CGPoint(x: 10, y: 50)))
        // Bounds still span the outer rect.
        #expect(donut.bounds == CGRect(x: 0, y: 0, width: 100, height: 100))
    }

    @Test func rectAndEllipseCompose() throws {
        let rect = try #require(SelectionRegion.rect(CGRect(x: 0, y: 0, width: 100, height: 100)))
        let ellipse = try #require(SelectionRegion.ellipse(in: CGRect(x: 50, y: 50, width: 100, height: 100)))
        let union = try #require(rect.combining(ellipse, mode: .add))
        #expect(union.contains(CGPoint(x: 100, y: 100)))   // ellipse center
        #expect(union.contains(CGPoint(x: 5, y: 5)))       // rect corner
        let diff = try #require(rect.combining(ellipse, mode: .subtract))
        #expect(!diff.contains(CGPoint(x: 95, y: 95)))
        #expect(diff.contains(CGPoint(x: 5, y: 5)))
    }

    // MARK: Combining against no existing selection

    @Test func combineWithNilBaseStartsFromTheShape() throws {
        let shape = try #require(SelectionRegion.rect(CGRect(x: 0, y: 0, width: 40, height: 40)))
        #expect(SelectionRegion.combine(nil, with: shape, mode: .replace) == shape)
        #expect(SelectionRegion.combine(nil, with: shape, mode: .add) == shape)
        // Subtracting from or intersecting with nothing selects nothing.
        #expect(SelectionRegion.combine(nil, with: shape, mode: .subtract) == nil)
        #expect(SelectionRegion.combine(nil, with: shape, mode: .intersect) == nil)
    }

    @Test func combineWithABaseDelegatesToTheMode() throws {
        let a = try #require(SelectionRegion.rect(CGRect(x: 0, y: 0, width: 100, height: 100)))
        let b = try #require(SelectionRegion.rect(CGRect(x: 50, y: 50, width: 100, height: 100)))
        let added = try #require(SelectionRegion.combine(a, with: b, mode: .add))
        #expect(added.bounds == CGRect(x: 0, y: 0, width: 150, height: 150))
    }

    // MARK: Modifier mapping (⇧ add, ⌥ subtract, ⇧⌥ intersect)

    @Test func modifiersMapToModes() {
        #expect(SelectionRegion.Mode(shift: false, option: false) == .replace)
        #expect(SelectionRegion.Mode(shift: true, option: false) == .add)
        #expect(SelectionRegion.Mode(shift: false, option: true) == .subtract)
        #expect(SelectionRegion.Mode(shift: true, option: true) == .intersect)
    }

    // MARK: Equatable

    @Test func equalityFollowsThePath() throws {
        let a = try #require(SelectionRegion.rect(CGRect(x: 0, y: 0, width: 40, height: 40)))
        let b = try #require(SelectionRegion.rect(CGRect(x: 0, y: 0, width: 40, height: 40)))
        let c = try #require(SelectionRegion.rect(CGRect(x: 1, y: 0, width: 40, height: 40)))
        #expect(a == b)
        #expect(a != c)
    }
}
