import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// Resizing places the pieces (`docs/design/ui-building.md`). A container says
/// how its contents line up, a piece may say something different for itself,
/// and a piece that says nothing at all does what this app always did.
@Suite("A resized container keeps its pieces where they belong")
struct LayerPlacementTests {

    // MARK: - Building blocks

    private func box(_ name: String, _ frame: CGRect) -> Layer {
        Layer(name: name, content: .image(ImageRef(pixelSize: frame.size)), frame: frame)
    }

    /// A 100 × 40 plate at the container's origin with a 20 × 10 label sitting
    /// dead centre of it, so "did it stay centred" is one comparison.
    private func plate(contents: LayerPlacement? = nil,
                       background: LayerPlacement? = nil,
                       label: LayerPlacement? = nil) -> Layer {
        var back = box("Background", CGRect(x: 0, y: 0, width: 100, height: 40))
        back.placement = background
        var text = box("Label", CGRect(x: 40, y: 15, width: 20, height: 10))
        text.placement = label
        var group = GroupContent(children: [back, text])
        group.contentPlacement = contents
        return Layer(name: "Plate", content: .group(group), frame: .zero)
    }

    private func piece(_ layer: Layer, _ name: String) -> CGRect {
        layer.children.first { $0.name == name }?.frame ?? .null
    }

    /// The plate pulled from 100 × 40 to `width` × `height`, anchored top left.
    private func widened(_ layer: Layer, to width: CGFloat, _ height: CGFloat = 40) -> Layer {
        layer.resized(to: CGRect(x: 0, y: 0, width: width, height: height))
    }

    // MARK: - Nothing set behaves exactly as it did before

    @Test("A container with nothing set still scales everything proportionally")
    func theDefaultIsTheOldRule() {
        let wider = widened(plate(), to: 200, 80)
        #expect(piece(wider, "Background") == CGRect(x: 0, y: 0, width: 200, height: 80))
        #expect(piece(wider, "Label") == CGRect(x: 80, y: 30, width: 40, height: 20))
    }

    @Test("Scale is what an unset piece resolves to, and it says the container answered")
    func unsetResolvesToScale() {
        let resolved = LayerPlacement.resolving(child: nil, container: nil)
        #expect(resolved.horizontal == .scale)
        #expect(resolved.vertical == .scale)
        #expect(resolved.followsHorizontal)
        #expect(resolved.followsVertical)
    }

    // MARK: - The four placements, one axis at a time

    @Test("A centred piece keeps its offset from the middle and keeps its size")
    func centreHoldsTheMiddle() {
        let wider = widened(plate(contents: LayerPlacement(horizontal: .center,
                                                           vertical: .center)), to: 300)
        // 300 wide, a 20-wide label centred: 140 in from the left, same size.
        #expect(piece(wider, "Label") == CGRect(x: 140, y: 15, width: 20, height: 10))
    }

    @Test("A stretched piece keeps both insets, so a background fills the new width")
    func stretchFillsTheBox() {
        let wider = widened(plate(background: LayerPlacement(horizontal: .stretch,
                                                             vertical: .stretch)), to: 300, 90)
        #expect(piece(wider, "Background") == CGRect(x: 0, y: 0, width: 300, height: 90))
    }

    @Test("A left-placed piece keeps its distance from the left edge and its size")
    func leftHugsTheLeftEdge() {
        let wider = widened(plate(contents: LayerPlacement(horizontal: .left, vertical: .top)),
                            to: 300, 90)
        #expect(piece(wider, "Label") == CGRect(x: 40, y: 15, width: 20, height: 10))
    }

    @Test("A right-placed piece keeps its distance from the right edge")
    func rightHugsTheRightEdge() {
        // The label's right edge sat 40 in from the right of a 100-wide box.
        let wider = widened(plate(contents: LayerPlacement(horizontal: .right, vertical: .bottom)),
                            to: 300, 90)
        #expect(piece(wider, "Label").maxX == 260)
        #expect(piece(wider, "Label").width == 20)
        // Its bottom edge sat 15 up from the bottom of a 40-tall box; it still does.
        #expect(piece(wider, "Label").maxY == 75)
    }

    // MARK: - The container's default, and a piece overriding it

    @Test("The container's default reaches every piece that says nothing")
    func theContainerDefaultReachesEverything() {
        let wider = widened(plate(contents: LayerPlacement(horizontal: .center, vertical: .center)),
                            to: 300, 90)
        // Both pieces were centred in their box, so both stay centred.
        #expect(piece(wider, "Background").midX == 150)
        #expect(piece(wider, "Label").midX == 150)
        #expect(piece(wider, "Background").width == 100)
    }

    @Test("A piece's own setting wins over the container's, one axis at a time")
    func anOverrideWinsPerAxis() {
        // Container: centre everything. Background: stretch across only, so it
        // fills the width but still follows the container up and down.
        let wider = widened(plate(contents: LayerPlacement(horizontal: .center, vertical: .center),
                                  background: LayerPlacement(horizontal: .stretch)), to: 300, 90)
        // Across: both edges pinned, so it fills 300. Down: it follows the
        // container's centre, keeping its own 40 in the middle of the new 90.
        #expect(piece(wider, "Background") == CGRect(x: 0, y: 25, width: 300, height: 40))
        #expect(piece(wider, "Label") == CGRect(x: 140, y: 40, width: 20, height: 10))
    }

    @Test("Resolving says which axes are following the container and which are overriding")
    func resolvingReportsWhoAnswered() {
        let container = plate(contents: LayerPlacement(horizontal: .center, vertical: .center),
                              background: LayerPlacement(horizontal: .stretch))
        let background = container.children.first { $0.name == "Background" }
        let resolved = background?.resolvedPlacement(in: container)
        #expect(resolved?.horizontal == .stretch)
        #expect(resolved?.followsHorizontal == false)
        #expect(resolved?.vertical == .center)
        #expect(resolved?.followsVertical == true)
    }

    @Test("Setting an axis back to follow drops the setting rather than storing an empty one")
    func settingBackToFollowClearsIt() {
        var layer = box("Label", CGRect(x: 0, y: 0, width: 10, height: 10))
        layer.placement = LayerPlacement(horizontal: .stretch)
        layer.placement = layer.settingPlacement(horizontal: nil)
        #expect(layer.placement == nil)
    }

    // MARK: - The thing the user actually complained about

    @Test("A built-in button dragged wider keeps its label centred and its background filling")
    func aStarterButtonSurvivesBeingWidened() {
        let button = StarterComponents.layer(.button)
        let start = button.localBounds
        #expect(start.width == 128)
        for width in [96.0, 128.0, 260.0] as [CGFloat] {
            let resized = button.resized(to: CGRect(x: 0, y: 0, width: width, height: start.height))
            let background = piece(resized, "Background")
            let label = piece(resized, "Label")
            #expect(background == CGRect(x: 0, y: 0, width: width, height: start.height))
            // The label is centred on its INK, which is its frame less the
            // measuring slack, exactly as the starter drew it at 128.
            let ink = label.width - StarterComponents.textSlack
            #expect(abs(label.minX - ((width - ink) / 2).rounded()) <= 1)
            // ...and its type never changed size.
            guard case .text(let content)? = resized.children.last?.content else {
                Issue.record("the label stopped being text")
                return
            }
            #expect(content.fontSize == 14)
        }
    }

    @Test("Every starter component keeps its background filling at a new size")
    func everyStarterStretchesItsBackground() {
        for kind in StarterComponent.allCases {
            let layer = StarterComponents.layer(kind)
            let start = layer.localBounds
            let resized = layer.resized(to: CGRect(x: 0, y: 0,
                                                   width: start.width * 1.5,
                                                   height: start.height * 1.5))
            let background = resized.children.first { $0.name == "Background" }
            #expect(background?.frame == CGRect(x: 0, y: 0, width: start.width * 1.5,
                                                height: start.height * 1.5),
                    "\(kind.name)'s background did not fill its new box")
        }
    }

    @Test("A nav bar's divider stays a hairline along the bottom at any width")
    func aDividerStaysAHairline() {
        let bar = StarterComponents.layer(.navBar)
        let start = bar.localBounds
        let taller = bar.resized(to: CGRect(x: 0, y: 0, width: 640, height: 96))
        let divider = piece(taller, "Divider")
        #expect(divider.width == 640)
        #expect(divider.height == 1)
        #expect(divider.maxY == 96)
        #expect(start.height == 48)
    }

    // MARK: - Groups inside groups

    @Test("A stretched group inside a container lays its own contents out by its own rules")
    func aNestedGroupUsesItsOwnRules() {
        var inner = plate(contents: LayerPlacement(horizontal: .center, vertical: .center),
                          background: LayerPlacement(horizontal: .stretch, vertical: .stretch))
        inner.placement = LayerPlacement(horizontal: .stretch, vertical: .stretch)
        let outer = Layer(name: "Outer", content: .group(GroupContent(children: [inner])),
                          frame: .zero)
        let wider = outer.resized(to: CGRect(x: 0, y: 0, width: 300, height: 40))
        guard let nested = wider.children.first else {
            Issue.record("the nested group vanished")
            return
        }
        #expect(nested.localBounds == CGRect(x: 0, y: 0, width: 300, height: 40))
        #expect(piece(nested, "Background").width == 300)
        #expect(piece(nested, "Label") == CGRect(x: 140, y: 15, width: 20, height: 10))
    }

    @Test("A piece that keeps its size does not renumber what is inside it")
    func aFixedSizeNestedGroupJustMoves() {
        var inner = plate()
        inner.placement = LayerPlacement(horizontal: .right, vertical: .top)
        let outer = Layer(name: "Outer", content: .group(GroupContent(children: [
            box("Base", CGRect(x: 0, y: 0, width: 100, height: 40)), inner,
        ])), frame: .zero)
        let wider = outer.resized(to: CGRect(x: 0, y: 0, width: 300, height: 40))
        guard let nested = wider.children.first(where: { $0.name == "Plate" }) else {
            Issue.record("the nested group vanished")
            return
        }
        #expect(nested.localBounds.maxX == 300)
        #expect(piece(nested, "Label") == CGRect(x: 40, y: 15, width: 20, height: 10))
    }

    // MARK: - A screen is a container too

    /// A screen with a bar across the top, a button hugging the bottom right,
    /// and a note nobody has given a rule to.
    private func screen(contents: LayerPlacement? = nil) -> Layer {
        var bar = box("Bar", CGRect(x: 0, y: 0, width: 320, height: 48))
        bar.placement = LayerPlacement(horizontal: .stretch, vertical: .top)
        var action = box("Action", CGRect(x: 240, y: 500, width: 64, height: 32))
        action.placement = LayerPlacement(horizontal: .right, vertical: .bottom)
        let note = box("Note", CGRect(x: 20, y: 100, width: 80, height: 20))
        var layer = Layer.frameLayer(name: "Screen", origin: CGPoint(x: 10, y: 10),
                                     size: CGSize(width: 320, height: 568),
                                     children: [bar, action, note])
        if var group = layer.group {
            group.contentPlacement = contents
            layer.content = .group(group)
        }
        return layer
    }

    @Test("Widening a screen stretches the bar across it and keeps the button in the corner")
    func aScreenPlacesItsContents() {
        let wide = screen().resized(to: CGRect(x: 10, y: 10, width: 480, height: 700))
        #expect(piece(wide, "Bar") == CGRect(x: 0, y: 0, width: 480, height: 48))
        #expect(piece(wide, "Action") == CGRect(x: 400, y: 632, width: 64, height: 32))
    }

    @Test("A piece on a screen with no rule holds still, exactly as it does today")
    func aScreenLeavesUnsetPiecesAlone() {
        let wide = screen().resized(to: CGRect(x: 10, y: 10, width: 480, height: 700))
        #expect(piece(wide, "Note") == CGRect(x: 20, y: 100, width: 80, height: 20))
    }

    @Test("A screen's own default reaches the pieces that said nothing")
    func aScreenDefaultReachesUnsetPieces() {
        let centred = screen(contents: LayerPlacement(horizontal: .center))
        let wide = centred.resized(to: CGRect(x: 10, y: 10, width: 480, height: 700))
        // The note sat 100 left of a 320-wide screen's middle; it still does.
        #expect(abs(piece(wide, "Note").midX - 140) < 0.001)
        #expect(piece(wide, "Note").width == 80)
    }

    @Test("Typing a new size into a screen places its contents the same way dragging does")
    func typingAScreenSizePlacesItsContents() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1000, height: 1000),
                                  layers: [screen()])
        let id = doc.layers[0].id
        doc.setFrameSize(id: id, size: CGSize(width: 480, height: 700))
        let bar = doc.allLayers.first { $0.name == "Bar" }
        #expect(bar?.frame == CGRect(x: 0, y: 0, width: 480, height: 48))
    }

    @Test("A screen inside a group that doubled still scales, contents and all")
    func aNestedScreenStillScales() {
        let group = Layer(name: "Group", content: .group(GroupContent(children: [screen()])),
                          frame: .zero)
        let doubled = group.resized(to: CGRect(x: 10, y: 10, width: 640, height: 1136))
        guard let inner = doubled.children.first else {
            Issue.record("the screen vanished")
            return
        }
        #expect(inner.frame.size == CGSize(width: 640, height: 1136))
        // The note had no rule of its own, so scaling the whole thing scales it.
        #expect(piece(inner, "Note") == CGRect(x: 40, y: 200, width: 160, height: 40))
    }

    // MARK: - Degenerate boxes stay finite

    @Test("A container with no width does not move its pieces sideways")
    func aFlatContainerIsLeftAlone() {
        var child = box("Rule", CGRect(x: 0, y: 0, width: 0, height: 40))
        child.placement = LayerPlacement(horizontal: .stretch, vertical: .stretch)
        let group = Layer(name: "Group", content: .group(GroupContent(children: [child])),
                          frame: .zero)
        let resized = group.resized(to: CGRect(x: 0, y: 0, width: 200, height: 80))
        for layer in resized.selfAndDescendants {
            #expect(layer.frame.origin.x.isFinite && layer.frame.origin.y.isFinite)
            #expect(layer.frame.width.isFinite && layer.frame.height.isFinite)
        }
        #expect(piece(resized, "Rule").width == 0)
        #expect(piece(resized, "Rule").height == 80)
    }

    @Test("Shrinking past what a stretched piece can give never makes a negative width")
    func stretchNeverGoesNegative() {
        var child = box("Fill", CGRect(x: 20, y: 0, width: 60, height: 10))
        child.placement = LayerPlacement(horizontal: .stretch)
        var outer = box("Edge", CGRect(x: 0, y: 0, width: 100, height: 10))
        outer.placement = LayerPlacement(horizontal: .stretch)
        let group = Layer(name: "Group", content: .group(GroupContent(children: [outer, child])),
                          frame: .zero)
        let tiny = group.resized(to: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(piece(tiny, "Fill").width == 0)
        #expect(piece(tiny, "Fill").width >= 0)
    }

    // MARK: - On disk, and in a copy

    @Test("A layer with no placement writes no placement key")
    func nothingSetWritesNothing() throws {
        let layer = box("Plain", CGRect(x: 0, y: 0, width: 10, height: 10))
        let json = try String(decoding: JSONEncoder().encode(layer), as: UTF8.self)
        #expect(!json.contains("placement"))
    }

    @Test("A placement survives a save and a load")
    func placementRoundTripsThroughJSON() throws {
        let original = plate(contents: LayerPlacement(horizontal: .center, vertical: .center),
                             background: LayerPlacement(horizontal: .stretch))
        let data = try JSONEncoder().encode(original)
        let back = try JSONDecoder().decode(Layer.self, from: data)
        #expect(back.group?.contentPlacement == LayerPlacement(horizontal: .center, vertical: .center))
        #expect(back.children.first?.placement == LayerPlacement(horizontal: .stretch))
        #expect(back.children.last?.placement == nil)
    }

    @Test("Duplicating a container carries its placement and its pieces'")
    func aDuplicateKeepsItsPlacement() {
        let original = plate(contents: LayerPlacement(horizontal: .center, vertical: .center),
                             background: LayerPlacement(horizontal: .stretch, vertical: .stretch))
        let copy = original.duplicated()
        #expect(copy.group?.contentPlacement == LayerPlacement(horizontal: .center, vertical: .center))
        #expect(copy.children.first?.placement == LayerPlacement(horizontal: .stretch, vertical: .stretch))
        let wider = copy.resized(to: CGRect(x: 0, y: 0, width: 300, height: 40))
        #expect(piece(wider, "Background").width == 300)
        #expect(piece(wider, "Label").midX == 150)
    }
    // MARK: - The group says which pieces are not following it

    @Test("A group with nothing overriding it lists nobody")
    func noOverridesListsNobody() {
        #expect(plate().contentsWithTheirOwnPlacement.isEmpty)
        #expect(plate(contents: LayerPlacement(horizontal: .center)).contentsWithTheirOwnPlacement
                    .isEmpty)
    }

    @Test("A group lists exactly the pieces that placed themselves")
    func overridesAreTheOnesWithARuleOfTheirOwn() {
        let group = plate(contents: LayerPlacement(horizontal: .center, vertical: .center),
                          background: LayerPlacement(horizontal: .stretch))
        let overrides = group.contentsWithTheirOwnPlacement
        #expect(overrides.count == 1)
        #expect(overrides.first?.name == "Background")
        #expect(overrides.first?.id == group.children.first?.id)
        #expect(overrides.first?.horizontal == .stretch)
        #expect(overrides.first?.vertical == nil)
    }

    @Test("The list reads top-most first, the way the Layers list does")
    func overridesReadTopMostFirst() {
        let group = plate(background: LayerPlacement(horizontal: .stretch),
                          label: LayerPlacement(vertical: .top))
        #expect(group.contentsWithTheirOwnPlacement.map(\.name) == ["Label", "Background"])
    }

    @Test("Each listed piece says what its own rule is, per axis")
    func eachOverrideSaysWhatItDoes() {
        let acrossOnly = PlacementOverride(id: UUID(), name: "Title", horizontal: .left,
                                           vertical: nil)
        let downOnly = PlacementOverride(id: UUID(), name: "Rule", horizontal: nil,
                                         vertical: .bottom)
        let both = PlacementOverride(id: UUID(), name: "Badge", horizontal: .right,
                                     vertical: .center)
        let filling = PlacementOverride(id: UUID(), name: "Background", horizontal: .stretch,
                                        vertical: .stretch)
        #expect(acrossOnly.summary == "Left across")
        #expect(downOnly.summary == "Bottom down")
        #expect(both.summary == "Right across, Middle down")
        #expect(filling.summary == "Stretch both ways")
    }

    @Test("Only the pieces directly inside are listed, not what is deeper in")
    func onlyDirectChildrenAreListed() {
        var inner = plate(background: LayerPlacement(horizontal: .stretch))
        inner.name = "Inner"
        let outer = Layer(name: "Outer", content: .group(GroupContent(children: [inner])),
                          frame: .zero)
        #expect(outer.contentsWithTheirOwnPlacement.isEmpty)
    }

    @Test("A piece that says the same thing the group says is still not following it")
    func matchingTheGroupIsStillItsOwnRule() {
        // It looks identical today, and stops looking identical the moment the
        // group's answer changes, which is exactly why it is worth naming.
        let group = plate(contents: LayerPlacement(horizontal: .center),
                          label: LayerPlacement(horizontal: .center))
        #expect(group.contentsWithTheirOwnPlacement.map(\.name) == ["Label"])
    }

    @Test("Something that is not a group lists nobody")
    func aLeafListsNobody() {
        #expect(box("Plain", CGRect(x: 0, y: 0, width: 10, height: 10))
                    .contentsWithTheirOwnPlacement.isEmpty)
    }
}
