import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What a layer's drawing can touch, which is bigger than the box it occupies
/// whenever a shadow or a blur reaches past it. A group renders into a buffer
/// this size, so nothing inside it gets clipped.
@Suite("Group render bounds")
struct GroupRenderBoundsTests {

    private func leaf(_ name: String, _ frame: CGRect, style: LayerStyle = LayerStyle()) -> Layer {
        Layer(name: name, content: .text(TextContent(string: name)), frame: frame, style: style)
    }

    @Test func aPlainLeafReachesExactlyItsFrame() {
        let layer = leaf("Box", CGRect(x: 10, y: 20, width: 30, height: 40))
        #expect(layer.renderBounds == CGRect(x: 10, y: 20, width: 30, height: 40))
    }

    @Test func aShadowedLeafReachesPastItsFrame() {
        let style = LayerStyle(shadow: ShadowStyle(radius: 10, offset: CGSize(width: 0, height: 4)))
        let layer = leaf("Box", CGRect(x: 100, y: 100, width: 50, height: 50), style: style)
        let padding = style.previewPadding
        #expect(padding > 0)
        #expect(layer.renderBounds == CGRect(x: 100, y: 100, width: 50, height: 50)
            .insetBy(dx: -padding, dy: -padding))
    }

    @Test func aGroupReachesAsFarAsWhatItHolds() {
        let shadow = LayerStyle(shadow: ShadowStyle(radius: 6, offset: .zero))
        let child = leaf("Card", CGRect(x: 0, y: 0, width: 20, height: 20), style: shadow)
        let group = Layer(name: "Group", content: .group(GroupContent(children: [child])),
                          frame: CGRect(x: 50, y: 50, width: 0, height: 0))
        let padding = shadow.previewPadding
        // The child sits at canvas (50, 50) and its shadow reaches `padding`
        // further in every direction.
        #expect(group.renderBounds == CGRect(x: 50 - padding, y: 50 - padding,
                                             width: 20 + padding * 2, height: 20 + padding * 2))
    }

    @Test func aGroupsOwnStyleAddsItsOwnReach() {
        let child = leaf("Card", CGRect(x: 0, y: 0, width: 20, height: 20))
        let style = LayerStyle(blurRadius: 4)
        let group = Layer(name: "Group", content: .group(GroupContent(children: [child])),
                          frame: CGRect(x: 50, y: 50, width: 0, height: 0), style: style)
        let padding = style.previewPadding
        #expect(group.renderBounds == CGRect(x: 50, y: 50, width: 20, height: 20)
            .insetBy(dx: -padding, dy: -padding))
    }

    @Test func nestedGroupsAccumulateTheirOrigins() {
        let child = leaf("Card", CGRect(x: 5, y: 5, width: 10, height: 10))
        let inner = Layer(name: "Inner", content: .group(GroupContent(children: [child])),
                          frame: CGRect(x: 20, y: 20, width: 0, height: 0))
        let outer = Layer(name: "Outer", content: .group(GroupContent(children: [inner])),
                          frame: CGRect(x: 100, y: 100, width: 0, height: 0))
        #expect(outer.renderBounds == CGRect(x: 125, y: 125, width: 10, height: 10))
    }

    @Test func anEmptyGroupReachesNothing() {
        let group = Layer(name: "Group", content: .group(GroupContent(children: [])),
                          frame: CGRect(x: 10, y: 10, width: 0, height: 0))
        #expect(group.renderBounds.isEmpty)
    }

    // MARK: - Dirty regions

    /// A group's stored `frame` has no size, so a repaint region taken from it
    /// would be a point. What has to repaint is where the group's contents draw.
    @Test func dirtyRegionCoversAnEditInsideAGroup() {
        let child = leaf("Card", CGRect(x: 0, y: 0, width: 40, height: 30))
        let group = Layer(name: "Group", content: .group(GroupContent(children: [child])),
                          frame: CGRect(x: 60, y: 60, width: 0, height: 0))
        let before = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: [group])
        var after = before
        after.updateLayer(id: child.id) { $0.frame = CGRect(x: 0, y: 0, width: 40, height: 80) }

        guard case .rect(let dirty) = RenderDiff.dirtyRegion(from: before, to: after) else {
            Issue.record("an edit inside a group should dirty a region")
            return
        }
        #expect(dirty.contains(CGRect(x: 60, y: 60, width: 40, height: 80)),
                "the region must cover the child's old and new boxes in canvas space, got \(dirty)")
    }

    /// A group that draws its children straight onto the canvas is not one
    /// object, so moving one layer inside it repaints that layer, not the
    /// whole group. On a big canvas that is the difference between a smooth
    /// drag and a stutter.
    @Test func dirtyRegionInsideAPlainGroupCoversOnlyWhatMoved() {
        let far = leaf("Far", CGRect(x: 0, y: 0, width: 40, height: 40))
        let near = leaf("Near", CGRect(x: 300, y: 300, width: 40, height: 40))
        let group = Layer(name: "Group", content: .group(GroupContent(children: [far, near])),
                          frame: CGRect(x: 20, y: 20, width: 0, height: 0))
        let before = PhotonzDocument(canvasSize: CGSize(width: 500, height: 500), layers: [group])
        var after = before
        after.updateLayer(id: near.id) { $0.frame = $0.frame.offsetBy(dx: 4, dy: 4) }

        guard case .rect(let dirty) = RenderDiff.dirtyRegion(from: before, to: after) else {
            Issue.record("an edit inside a group should dirty a region")
            return
        }
        #expect(dirty.contains(CGRect(x: 320, y: 320, width: 44, height: 44)),
                "the moved layer's old and new boxes must repaint, got \(dirty)")
        #expect(!dirty.intersects(CGRect(x: 20, y: 20, width: 20, height: 20)),
                "the layer at the other end of the group must not, got \(dirty)")
    }

    /// A styled group IS one object — its fade and its shadow are computed from
    /// everything inside it — so a change anywhere in it repaints all of it.
    @Test func dirtyRegionInsideAStyledGroupCoversTheWholeGroup() {
        let far = leaf("Far", CGRect(x: 0, y: 0, width: 40, height: 40))
        let near = leaf("Near", CGRect(x: 300, y: 300, width: 40, height: 40))
        let group = Layer(name: "Group", content: .group(GroupContent(children: [far, near])),
                          frame: CGRect(x: 20, y: 20, width: 0, height: 0),
                          style: LayerStyle(opacity: 0.5))
        let before = PhotonzDocument(canvasSize: CGSize(width: 500, height: 500), layers: [group])
        var after = before
        after.updateLayer(id: near.id) { $0.frame = $0.frame.offsetBy(dx: 4, dy: 4) }

        guard case .rect(let dirty) = RenderDiff.dirtyRegion(from: before, to: after) else {
            Issue.record("an edit inside a group should dirty a region")
            return
        }
        #expect(dirty.contains(CGRect(x: 20, y: 20, width: 20, height: 20)),
                "the whole group repaints, got \(dirty)")
    }

    @Test func dirtyRegionCoversACalloutInsideAGroup() {
        let callout = Layer(name: "Zoom",
                            content: .zoomCallout(ZoomCalloutContent(sourceRect: CGRect(x: 10, y: 10, width: 20, height: 20))),
                            frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        let group = Layer(name: "Group", content: .group(GroupContent(children: [callout])),
                          frame: CGRect(x: 200, y: 200, width: 0, height: 0))
        let patch = leaf("Patch", CGRect(x: 0, y: 0, width: 30, height: 30))
        let before = PhotonzDocument(canvasSize: CGSize(width: 400, height: 400), layers: [patch, group])
        var after = before
        after.updateLayer(id: patch.id) { $0.frame = CGRect(x: 5, y: 5, width: 30, height: 30) }

        guard case .rect(let dirty) = RenderDiff.dirtyRegion(from: before, to: after) else {
            Issue.record("moving what a callout magnifies should dirty a region")
            return
        }
        #expect(dirty.intersects(CGRect(x: 200, y: 200, width: 60, height: 60)),
                "the callout inside the group mirrors the moved patch, so its box repaints too, got \(dirty)")
    }
}
