import CoreGraphics
import PhotonzCore
import Testing

@Suite("Tool")
struct ToolTests {

    @Test func annotationShapeMapping() {
        #expect(Tool.arrow.annotationShape == .arrow)
        #expect(Tool.line.annotationShape == .line)
        #expect(Tool.rectangle.annotationShape == .rectangle)
        #expect(Tool.ellipse.annotationShape == .ellipse)
        #expect(Tool.highlight.annotationShape == .highlight)
        #expect(Tool.select.annotationShape == nil)
        #expect(Tool.crop.annotationShape == nil)
        #expect(Tool.text.annotationShape == nil)
    }

    @Test func dragToCreateToolsAreExactlyTheAnnotationTools() {
        for tool in Tool.allCases {
            #expect(tool.createsAnnotationByDrag == (tool.annotationShape != nil))
        }
    }

    // Smart defaults (3.6): arrows/shapes are red, highlight is yellow.
    @Test func defaultContentColors() {
        #expect(Tool.arrow.defaultAnnotation?.colorHex == "#FF3B30")
        #expect(Tool.line.defaultAnnotation?.colorHex == "#FF3B30")
        #expect(Tool.rectangle.defaultAnnotation?.colorHex == "#FF3B30")
        #expect(Tool.ellipse.defaultAnnotation?.colorHex == "#FF3B30")
        #expect(Tool.highlight.defaultAnnotation?.colorHex == "#FFD60A")
        #expect(Tool.select.defaultAnnotation == nil)
        #expect(Tool.text.defaultAnnotation == nil)
    }

    @Test func defaultContentShapesMatchTheTool() {
        for tool in Tool.allCases {
            #expect(tool.defaultAnnotation?.shape == tool.annotationShape)
        }
    }

    // Region selection tools (phase 17): rect/ellipse marquee + magic wand.
    @Test func regionSelectionToolsAreExactlyTheThreeNewOnes() {
        for tool in Tool.allCases {
            let isRegion = tool == .rectSelect || tool == .ellipseSelect || tool == .wand
            #expect(tool.isRegionSelectionTool == isRegion)
            // The marquee GROUP (one shared toolbar slot) is the pair minus the wand.
            #expect(tool.isMarqueeSelectTool == (isRegion && tool != .wand))
            if isRegion {
                #expect(tool.annotationShape == nil)
                #expect(!tool.createsAnnotationByDrag)
                #expect(tool.defaultAnnotation == nil)
            }
        }
    }

    /// The selection region survives switching within the selection family
    /// (Photoshop keeps the ants up) and the fill bucket (fill-the-region is
    /// the point of making one); drawing/crop/text tools still clear it.
    @Test func selectionRegionSurvivesTheSelectionFamilyAndFill() {
        #expect(Tool.select.preservesSelectionRegion)
        #expect(Tool.rectSelect.preservesSelectionRegion)
        #expect(Tool.ellipseSelect.preservesSelectionRegion)
        #expect(Tool.wand.preservesSelectionRegion)
        #expect(Tool.fill.preservesSelectionRegion)
        #expect(!Tool.crop.preservesSelectionRegion)
        #expect(!Tool.rectangle.preservesSelectionRegion)
        #expect(!Tool.text.preservesSelectionRegion)
        #expect(!Tool.measure.preservesSelectionRegion)
    }
}

@Suite("AnnotationDrag")
struct AnnotationDragTests {

    @Test func clickDetectionMatchesViewSpaceTolerance() {
        var drag = AnnotationDrag(anchor: CGPoint(x: 10, y: 10))
        drag.update(to: CGPoint(x: 11, y: 11))
        #expect(drag.isClick(atZoom: 1))
        #expect(!drag.isClick(atZoom: 4)) // same doc travel is a real drag when zoomed in
    }

    @Test func unconstrainedEndIsTheRawPointer() {
        var drag = AnnotationDrag(anchor: .zero)
        drag.update(to: CGPoint(x: 30, y: 17))
        #expect(drag.end(constrained: false, shape: .line) == CGPoint(x: 30, y: 17))
        #expect(drag.end(constrained: false, shape: .rectangle) == CGPoint(x: 30, y: 17))
    }

    @Test func constrainedLineSnapsToNearest45Degrees() {
        var drag = AnnotationDrag(anchor: .zero)
        drag.update(to: CGPoint(x: 100, y: 8)) // ~4.6° — snaps to horizontal
        let end = drag.end(constrained: true, shape: .line)
        #expect(abs(end.y) < 1e-9)
        #expect(abs(end.x - hypot(100, 8)) < 1e-9) // length preserved

        drag.update(to: CGPoint(x: 50, y: 46)) // ~42.6° — snaps to the diagonal
        let diag = drag.end(constrained: true, shape: .arrow)
        #expect(abs(diag.x - diag.y) < 1e-9)
    }

    @Test func constrainedDiagonalKeepsDirection() {
        var drag = AnnotationDrag(anchor: CGPoint(x: 100, y: 100))
        drag.update(to: CGPoint(x: 40, y: 158)) // up-left-ish drag in doc coords
        let end = drag.end(constrained: true, shape: .line)
        #expect(end.x < 100 && end.y > 100)
        #expect(abs((100 - end.x) - (end.y - 100)) < 1e-9)
    }

    // ⇧ on box shapes means square, not angle snap — a near-horizontal rect
    // drag must never collapse flat.
    @Test func constrainedBoxShapesBecomeSquare() {
        var drag = AnnotationDrag(anchor: CGPoint(x: 100, y: 100))
        drag.update(to: CGPoint(x: 300, y: 150)) // wide, shallow drag
        for shape in [AnnotationShape.rectangle, .ellipse, .highlight] {
            let end = drag.end(constrained: true, shape: shape)
            #expect(end == CGPoint(x: 300, y: 300), "\(shape) squares off the longer axis")
        }
        drag.update(to: CGPoint(x: 40, y: 90)) // up-left drag keeps its direction
        let end = drag.end(constrained: true, shape: .rectangle)
        #expect(end == CGPoint(x: 40, y: 40))
    }
}

@Suite("AnnotationBuilder")
struct AnnotationBuilderTests {

    @Test func rectangleLayerFrameIsTheDragBoundingBox() {
        let content = AnnotationContent(shape: .rectangle, strokeWidth: 4, colorHex: "#FF3B30")
        let layer = AnnotationBuilder.layer(content: content,
                                            from: CGPoint(x: 10, y: 20),
                                            to: CGPoint(x: 110, y: 80))
        #expect(layer.frame == CGRect(x: 10, y: 20, width: 100, height: 60))
        guard case .annotation(let a) = layer.content else {
            Issue.record("expected annotation content")
            return
        }
        #expect(a.start == CGPoint(x: 0, y: 0))
        #expect(a.end == CGPoint(x: 100, y: 60))
    }

    @Test func reversedDragPreservesStartEndOrientation() {
        let content = AnnotationContent(shape: .rectangle, strokeWidth: 4, colorHex: "#FF3B30")
        let layer = AnnotationBuilder.layer(content: content,
                                            from: CGPoint(x: 110, y: 80),
                                            to: CGPoint(x: 10, y: 20))
        #expect(layer.frame == CGRect(x: 10, y: 20, width: 100, height: 60))
        guard case .annotation(let a) = layer.content else {
            Issue.record("expected annotation content")
            return
        }
        #expect(a.start == CGPoint(x: 100, y: 60))
        #expect(a.end == CGPoint(x: 0, y: 0))
    }

    @Test func lineFramePadsForRoundCaps() {
        let content = AnnotationContent(shape: .line, strokeWidth: 4, colorHex: "#FF3B30")
        let layer = AnnotationBuilder.layer(content: content,
                                            from: CGPoint(x: 10, y: 10),
                                            to: CGPoint(x: 60, y: 40))
        // Half the stroke (2pt) on every side so caps aren't clipped.
        #expect(layer.frame == CGRect(x: 8, y: 8, width: 54, height: 34))
        guard case .annotation(let a) = layer.content else {
            Issue.record("expected annotation content")
            return
        }
        #expect(a.start == CGPoint(x: 2, y: 2))
        #expect(a.end == CGPoint(x: 52, y: 32))
    }

    @Test func arrowFramePadsForTheArrowheadWings() {
        let content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        let layer = AnnotationBuilder.layer(content: content,
                                            from: CGPoint(x: 0, y: 50),
                                            to: CGPoint(x: 100, y: 50))
        // Wings reach arrowheadHalfWidth past the shaft; the frame must contain them.
        let pad = Geometry.arrowheadHalfWidth(strokeWidth: 4).rounded(.up)
        #expect(pad > content.strokeWidth / 2)
        #expect(layer.frame.minY <= 50 - pad)
        #expect(layer.frame.maxY >= 50 + pad)
        guard case .annotation(let a) = layer.content else {
            Issue.record("expected annotation content")
            return
        }
        // Local points sit inside the frame by the padding amount.
        #expect(a.start.x == 0 - layer.frame.minX)
        #expect(a.end.x == 100 - layer.frame.minX)
    }

    @Test func degenerateDragStillProducesARasterizableFrame() {
        let content = AnnotationContent(shape: .highlight, strokeWidth: 4, colorHex: "#FFD60A")
        let layer = AnnotationBuilder.layer(content: content,
                                            from: CGPoint(x: 10, y: 30),
                                            to: CGPoint(x: 90, y: 30)) // zero height
        #expect(layer.frame.width >= 1)
        #expect(layer.frame.height >= 1)
    }

    @Test func layerIsNamedAfterTheShape() {
        let content = AnnotationContent(shape: .ellipse, strokeWidth: 4, colorHex: "#FF3B30")
        let layer = AnnotationBuilder.layer(content: content, from: .zero, to: CGPoint(x: 10, y: 10))
        #expect(layer.name == "Ellipse")
    }

    @Test func arrowheadHalfWidthMatchesActualWingExtent() {
        let points = Geometry.arrowhead(start: CGPoint(x: 0, y: 50), end: CGPoint(x: 80, y: 50), strokeWidth: 6)
        let halfWidth = Geometry.arrowheadHalfWidth(strokeWidth: 6)
        #expect(abs(abs(points[1].y - 50) - halfWidth) < 1e-9)
    }

    // MARK: Keyboard shortcuts
    //
    // The letter map is a product decision, not a rendering detail, so it lives
    // in the model where a test can hold it still. It drifted once already: the
    // redline mock had the Arrow tool on P, the letter every other surface uses
    // for the vector Pen.

    @Test func arrowIsOnAAndNeverOnP() {
        #expect(Tool.arrow.shortcutKey == "a")
        // P belongs to the Pen everywhere else in the product. Nothing in the
        // tool set may claim it until an actual Pen tool exists to do so.
        #expect(!Tool.allCases.contains { $0.shortcutKey == "p" })
    }

    @Test func noTwoToolsClaimTheSameKey() {
        var seen: [Character: Tool] = [:]
        for tool in Tool.allCases {
            guard let key = tool.shortcutKey else { continue }
            if let other = seen[key] {
                Issue.record("\(tool) and \(other) both claim \(key)")
            }
            seen[key] = tool
        }
    }

    @Test func everyToolbarToolTeachesAKey() {
        // A tool a person can pick from the bar can be picked from the keyboard.
        // The marquee family is the one exception: the three region selectors
        // share a slot and M / ⇧M / W are resolved by the group, not per tool.
        for tool in Tool.allCases where !tool.isRegionSelectionTool {
            #expect(tool.shortcutKey != nil, "\(tool) has no keyboard shortcut")
        }
    }

    @Test func shortcutKeysAreLowercaseLetters() {
        for tool in Tool.allCases {
            guard let key = tool.shortcutKey else { continue }
            #expect(key.isLetter && key.isLowercase, "\(tool) key \(key) is not a lowercase letter")
        }
    }

    @Test func theKeyHintMatchesTheKey() {
        // What a tooltip or menu row prints is derived from the same letter the
        // shortcut fires on, so the two can never disagree.
        #expect(Tool.arrow.shortcutHint == "A")
        #expect(Tool.select.shortcutHint == "V")
        #expect(Tool.rectSelect.shortcutHint == nil)
    }

}

// MARK: - Tool groups and the family layout
//
// The bar groups tools the way a pro editor does: a family of tools shares one
// slot, the slot shows the last member you used, and shift plus a member's key
// walks the family. The model is pure so the order and the key vocabulary can
// be held still here.
struct ToolGroupTests {

    @Test func everyGroupMemberBelongsToExactlyOneGroup() {
        var seen: [Tool: ToolGroup] = [:]
        for group in ToolGroup.allCases {
            for tool in group.tools {
                #expect(seen[tool] == nil, "\(tool) sits in \(group) and \(String(describing: seen[tool]))")
                seen[tool] = group
                #expect(ToolGroup.containing(tool) == group)
            }
        }
        #expect(ToolGroup.containing(.select) == nil)
        #expect(ToolGroup.containing(.arrow) == nil)
    }

    @Test func theSelectionGroupIsTheMarqueeFamily() {
        #expect(ToolGroup.selection.tools == [.rectSelect, .ellipseSelect, .wand])
        #expect(ToolGroup.selection.groupKey == "m")
    }

    @Test func theShapesGroupHoldsLineRectangleAndEllipse() {
        #expect(ToolGroup.shapes.tools == [.line, .rectangle, .ellipse])
        // Each shape keeps its own Photoshop letter, so no group key.
        #expect(ToolGroup.shapes.groupKey == nil)
    }

    @Test func cyclingWalksTheGroupAndWraps() {
        #expect(ToolGroup.shapes.next(after: .line) == .rectangle)
        #expect(ToolGroup.shapes.next(after: .rectangle) == .ellipse)
        #expect(ToolGroup.shapes.next(after: .ellipse) == .line)
        // A tool from outside the group starts the walk at the first member.
        #expect(ToolGroup.shapes.next(after: .wand) == .line)
    }

    @Test func shiftPlusAnyMemberKeyCyclesTheGroup() {
        // Selection: M is the group key, W is the wand's own. Both cycle with shift.
        #expect(ToolGroup.selection.cycleKeys == ["m", "w"])
        #expect(ToolGroup.shapes.cycleKeys == ["l", "r", "o"])
        for group in ToolGroup.allCases {
            #expect(!group.cycleKeys.isEmpty)
            #expect(Set(group.cycleKeys).count == group.cycleKeys.count)
        }
    }

    @Test func rememberedMemberFallsBackToTheFirst() {
        #expect(ToolGroup.shapes.member(from: "rectangle") == .rectangle)
        #expect(ToolGroup.shapes.member(from: "wand") == .line)
        #expect(ToolGroup.shapes.member(from: nil) == .line)
        #expect(ToolGroup.selection.member(from: "garbage") == .rectSelect)
    }

    // MARK: A plain letter, pressed again
    //
    // A letter that stands for ONE tool hands that tool back however often you
    // press it (O is always Ellipse, never a walk to Line). M is the only
    // letter that owns two tools, Photoshop's marquee pair, so it is the only
    // one where pressing again means something: it swaps the box for the
    // ellipse. The wand keeps W, and M never hands it over.

    @Test func aLetterOwnsTheMembersThatHaveNoLetterOfTheirOwn() {
        #expect(ToolGroup.selection.tools(answeringTo: "m") == [.rectSelect, .ellipseSelect])
        #expect(ToolGroup.selection.tools(answeringTo: "w") == [.wand])
        #expect(ToolGroup.shapes.tools(answeringTo: "l") == [.line])
        #expect(ToolGroup.shapes.tools(answeringTo: "o") == [.ellipse])
        // A letter this family never answers to owns nothing.
        #expect(ToolGroup.shapes.tools(answeringTo: "m").isEmpty)
        #expect(ToolGroup.selection.tools(answeringTo: "l").isEmpty)
    }

    @Test func mPicksTheMarqueeAndPressingItAgainSwapsIt() {
        let selection = ToolGroup.selection
        // From another tool: the marquee you used last.
        #expect(selection.tool(forKey: "m", active: .arrow, remembered: .rectSelect) == .rectSelect)
        #expect(selection.tool(forKey: "m", active: .arrow, remembered: .ellipseSelect) == .ellipseSelect)
        // Again, and again: box, ellipse, box.
        #expect(selection.tool(forKey: "m", active: .rectSelect, remembered: .rectSelect) == .ellipseSelect)
        #expect(selection.tool(forKey: "m", active: .ellipseSelect, remembered: .ellipseSelect) == .rectSelect)
    }

    @Test func mAlwaysHandsYouAMarqueeAndNeverTheWand() {
        let selection = ToolGroup.selection
        // The wand is the family's remembered member, and M still means marquee.
        #expect(selection.tool(forKey: "m", active: .wand, remembered: .wand) == .rectSelect)
        #expect(selection.tool(forKey: "m", active: .select, remembered: .wand) == .rectSelect)
        // W is the wand's, from anywhere, and pressing it again keeps it.
        #expect(selection.tool(forKey: "w", active: .rectSelect, remembered: .rectSelect) == .wand)
        #expect(selection.tool(forKey: "w", active: .wand, remembered: .wand) == .wand)
    }

    @Test func aShapeLetterKeepsHandingBackItsOwnShape() {
        let shapes = ToolGroup.shapes
        #expect(shapes.tool(forKey: "o", active: .line, remembered: .ellipse) == .ellipse)
        // Pressing it again is not a walk: O is Ellipse, always.
        #expect(shapes.tool(forKey: "o", active: .ellipse, remembered: .ellipse) == .ellipse)
        #expect(shapes.tool(forKey: "r", active: .ellipse, remembered: .ellipse) == .rectangle)
        #expect(shapes.tool(forKey: "l", active: .rectangle, remembered: .rectangle) == .line)
    }

    @Test func aLetterThisFamilyDoesNotAnswerToPicksNothing() {
        #expect(ToolGroup.shapes.tool(forKey: "m", active: .line, remembered: .line) == nil)
        #expect(ToolGroup.selection.tool(forKey: "z", active: .wand, remembered: .wand) == nil)
    }

    @Test func onlyMSwapsOnASecondPress() {
        #expect(ToolGroup.selection.swapKeys == ["m"])
        #expect(ToolGroup.shapes.swapKeys.isEmpty)
        // Every swap key is a key the family answers to at all.
        for group in ToolGroup.allCases {
            for key in group.swapKeys { #expect(group.cycleKeys.contains(key)) }
        }
    }

    @Test func groupsHaveNamesForTheirMenus() {
        #expect(ToolGroup.selection.title == "Selection")
        #expect(ToolGroup.shapes.title == "Shapes")
    }
}

struct ToolBarLayoutTests {

    @Test func everyToolAppearsExactlyOnce() {
        // The frame tool is flagged (`next-frames`), so the plain bar does not
        // hold it and the bar that does holds it exactly once.
        for bar in [ToolBarLayout.families, ToolBarLayout.familiesWithFrame] {
            var counts: [Tool: Int] = [:]
            for entry in bar.entries {
                switch entry {
                case .tool(let tool): counts[tool, default: 0] += 1
                case .group(let group): for tool in group.tools { counts[tool, default: 0] += 1 }
                }
            }
            for tool in Tool.allCases where tool != .frame {
                #expect(counts[tool] == 1, "\(tool) appears \(counts[tool] ?? 0) times")
            }
            #expect(counts[.frame] == (bar == ToolBarLayout.familiesWithFrame ? 1 : nil))
        }
    }

    /// The frame tool joins the END of the drawing family, so no tool anybody
    /// already reaches for moves to a new slot when the flag comes on.
    @Test func theFrameToolJoinsTheEndOfTheDrawingFamily() {
        let plain = ToolBarLayout.families.families
        let framed = ToolBarLayout.familiesWithFrame.families
        #expect(framed[0] == plain[0])
        #expect(framed[2] == plain[2])
        #expect(framed[1] == plain[1] + [.tool(.frame)])
        #expect(ToolBarLayout.bar(withFrame: false) == ToolBarLayout.families)
        #expect(ToolBarLayout.bar(withFrame: true) == ToolBarLayout.familiesWithFrame)
    }

    /// F is free: it collides with no tool letter already spent.
    @Test func theFrameToolTakesTheDesignToolLetter() {
        #expect(Tool.frame.shortcutKey == "f")
        #expect(Tool.allCases.filter { $0.shortcutKey == "f" }.count == 1)
        #expect(!Tool.frame.createsAnnotationByDrag)
    }

    @Test func theFamiliesReadPickCutMeasureThenDrawThenPaint() {
        let families = ToolBarLayout.families.families
        #expect(families.count == 3)
        #expect(families[0] == [.tool(.select), .group(.selection), .tool(.crop), .tool(.measure)])
        #expect(families[1] == [.tool(.arrow), .group(.shapes), .tool(.highlight), .tool(.text), .tool(.zoomCallout)])
        #expect(families[2] == [.tool(.fill)])
    }

    @Test func groupingTakesFewerSlotsThanOneButtonPerTool() {
        // 13 slots before (12 tools with the marquee pair sharing one, plus
        // Resize); the grouped bar must be strictly narrower.
        #expect(ToolBarLayout.families.entries.count == 10)
        #expect(ToolBarLayout.families.entries.count < 13)
        #expect(!ToolBarLayout.families.families.contains { $0.isEmpty })
    }

    @Test func aToolResolvesToItsOwnSlot() {
        #expect(ToolBarLayout.families.entry(for: .rectSelect) == .group(.selection))
        #expect(ToolBarLayout.families.entry(for: .wand) == .group(.selection))
        #expect(ToolBarLayout.families.entry(for: .ellipse) == .group(.shapes))
        #expect(ToolBarLayout.families.entry(for: .arrow) == .tool(.arrow))
        #expect(ToolBarLayout.families.entry(for: .fill) == .tool(.fill))
    }

    // MARK: - Which tools paint (the tool bar's colour capsule)

    /// The colour capsule belongs to the tools that put colour on the picture.
    /// Select, the marquee pair, the wand, crop, measure, the zoom callout and
    /// the frame put none there, so they get no swatches at all.
    @Test func onlyPaintingToolsCarryColour() {
        let painting: Set<Tool> = [.arrow, .line, .rectangle, .ellipse,
                                   .highlight, .text, .fill]
        for tool in Tool.allCases {
            #expect(tool.paints == painting.contains(tool))
            #expect((tool.colorControl == .hidden) == !painting.contains(tool))
        }
    }

    @Test func theToolsThatShowNoColourAreNamedOneByOne() {
        for tool in [Tool.select, .crop, .measure, .zoomCallout,
                     .rectSelect, .ellipseSelect, .wand, .frame] {
            #expect(tool.colorControl == .hidden)
            #expect(!tool.paints)
        }
    }

    /// A box has two tones, a stroke has one, and the bucket works from the
    /// foreground/background pair. Each tool answers with exactly one of them.
    @Test func eachPaintingToolAsksForOneKindOfColourControl() {
        #expect(Tool.rectangle.colorControl == .fillAndBorder)
        #expect(Tool.ellipse.colorControl == .fillAndBorder)
        #expect(Tool.arrow.colorControl == .toolColor)
        #expect(Tool.line.colorControl == .toolColor)
        #expect(Tool.highlight.colorControl == .toolColor)
        #expect(Tool.text.colorControl == .toolColor)
        #expect(Tool.fill.colorControl == .foregroundBackground)
    }

    /// Every tool that draws by dragging paints, so a new annotation tool
    /// cannot be added and quietly lose its colour.
    @Test func everyDragToCreateToolPaints() {
        for tool in Tool.allCases where tool.createsAnnotationByDrag {
            #expect(tool.paints)
        }
    }

    /// The pair the bucket and the fill shortcuts work from has exactly one
    /// home on the bar. If it ever grows a second the two can drift.
    @Test func theForegroundBackgroundPairHasOneHome() {
        let homes = Tool.allCases.filter { $0.colorControl == .foregroundBackground }
        #expect(homes == [.fill])
    }
}
