import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The reworked selection (`the-reworked-selection-ships-cleaner-grips-a-tag`,
/// prototype `selection-transform.html`): one set of grips in every mode, a
/// knob with a clockwise arrow on a dotted stem, a mode chip beside it, a tag
/// below the frame, and in 3D a depth grip below the card.
@Suite("Selection grips: the reworked selection")
struct SelectionGripsTests {

    /// A flat 300 by 210 card at (150, 150) in view points.
    static let card: [CGPoint] = [CGPoint(x: 150, y: 150), CGPoint(x: 450, y: 150),
                                  CGPoint(x: 450, y: 360), CGPoint(x: 150, y: 360)]

    static func grips(_ quad: [CGPoint] = card, mode: TransformMode = .size,
                      rotates: Bool = true, resizes: Bool = true) -> SelectionGrips {
        SelectionGrips(quad: quad, mode: mode, rotates: rotates, resizes: resizes)
    }

    static func near(_ a: CGPoint, _ b: CGPoint, _ tolerance: CGFloat = 0.01) -> Bool {
        hypot(a.x - b.x, a.y - b.y) <= tolerance
    }

    // MARK: Where everything sits

    @Test("Four corner squares sit on the corners, ten points across")
    func cornersOnTheCorners() {
        let g = Self.grips()
        #expect(g.corners.count == 4)
        #expect(g.corners.map(\.handle) == [.topLeft, .topRight, .bottomRight, .bottomLeft])
        for (corner, point) in zip(g.corners, Self.card) {
            #expect(Self.near(corner.center, point))
        }
        #expect(SelectionGrips.cornerSide == 10)
    }

    @Test("Edge pills sit just outside their edge, never on the content")
    func pillsJustOutside() {
        let g = Self.grips()
        let byHandle = Dictionary(uniqueKeysWithValues: g.edges.map { ($0.handle, $0) })
        // Half the pill's 7 point thickness and a point and a half clear.
        #expect(Self.near(byHandle[.top]!.center, CGPoint(x: 300, y: 145)))
        #expect(Self.near(byHandle[.bottom]!.center, CGPoint(x: 300, y: 365)))
        #expect(Self.near(byHandle[.left]!.center, CGPoint(x: 145, y: 255)))
        #expect(Self.near(byHandle[.right]!.center, CGPoint(x: 455, y: 255)))
        // Lying along their edges.
        #expect(abs(byHandle[.top]!.angle) < 1e-9)
        #expect(abs(abs(byHandle[.left]!.angle) - .pi / 2) < 1e-9)
    }

    @Test("The knob floats 30 points off the top edge with a stem that starts past the pill")
    func knobAndStem() {
        let g = Self.grips()
        #expect(Self.near(g.knob!, CGPoint(x: 300, y: 120)))
        let stem = g.stem!
        // Past the top pill (its outer side is 8.5 out) and stopping at the
        // knob's own edge (radius 9.5), so the two never overlap.
        #expect(Self.near(stem.from, CGPoint(x: 300, y: 141)))
        #expect(Self.near(stem.to, CGPoint(x: 300, y: 129.5)))
    }

    @Test("A turned card wears its knob off the top edge it has turned to")
    func knobFollowsTheTurn() {
        // The card turned a quarter turn clockwise about its middle: its top
        // edge is now on the right.
        let c = CGPoint(x: 300, y: 255)
        let turned = Self.card.map { p in CGPoint(x: c.x - (p.y - c.y), y: c.y + (p.x - c.x)) }
        let g = Self.grips(turned)
        #expect(Self.near(g.knob!, CGPoint(x: 300 + 105 + 30, y: 255)))
    }

    @Test("No knob, stem or chip on a layer that does not turn")
    func noKnobWithoutTurning() {
        let g = Self.grips(rotates: false)
        #expect(g.knob == nil)
        #expect(g.stem == nil)
        #expect(g.chip.isEmpty)
    }

    @Test("No corners or pills on a layer that does not resize")
    func noGripsWithoutResize() {
        let g = Self.grips(resizes: false)
        #expect(g.corners.isEmpty)
        #expect(g.edges.isEmpty)
        #expect(g.knob != nil)
    }

    @Test("The chip sits beside the knob, its three modes in the order they apply")
    func chipBesideTheKnob() {
        let g = Self.grips()
        #expect(g.chip.map(\.mode) == [.size, .reshape, .space])
        let first = g.chip[0].frame, second = g.chip[1].frame
        #expect(g.chip[2].frame.minX > second.maxX)
        #expect(first.minX >= g.knob!.x + SelectionGrips.knobRadius)
        #expect(abs(first.midY - g.knob!.y) < 0.01)
        #expect(second.minX > first.maxX)
        #expect(first.size == CGSize(width: 22, height: 20))
    }

    @Test("With only one mode on offer there is no chip")
    func noChipForOneMode() {
        let g = SelectionGrips(quad: Self.card, mode: .size, rotates: true, resizes: true, modes: [.size])
        #expect(g.chip.isEmpty)
        #expect(g.chipPlate == nil)
    }

    @Test("The chip rises above a card whose corner comes up past the knob")
    func chipClearsATurnedCard() {
        // Tipped so the top right corner is high, above where the knob is.
        let quad = [CGPoint(x: 150, y: 150), CGPoint(x: 450, y: 60),
                    CGPoint(x: 450, y: 360), CGPoint(x: 150, y: 360)]
        let g = Self.grips(quad)
        let plate = g.chipPlate!
        #expect(plate.maxY <= 60)
    }

    // MARK: The depth grip, in 3D only

    @Test("3D adds a depth grip below the card on a dotted stem; Size has none")
    func depthGripInSpaceOnly() {
        #expect(Self.grips().depth == nil)
        let g = Self.grips(mode: .space)
        #expect(Self.near(g.depth!, CGPoint(x: 300, y: 390)))
        #expect(g.depthStem != nil)
        // Every other grip is the same in both modes.
        #expect(g.corners == Self.grips().corners)
        #expect(g.edges == Self.grips().edges)
        #expect(g.knob == Self.grips().knob)
    }

    // MARK: What a press takes

    @Test("Each grip answers inside its generous hit area")
    func generousHits() {
        let g = Self.grips()
        // Corner: anywhere within 14 points.
        #expect(g.hit(CGPoint(x: 150 - 9, y: 150 - 9)) == .corner(.topLeft))
        // Edge: a 48 by 24 band round the pill.
        #expect(g.hit(CGPoint(x: 300 + 22, y: 145 - 10)) == .edge(.top))
        #expect(g.hit(CGPoint(x: 455 + 10, y: 255 + 20)) == .edge(.right))
        // Knob: within 15.
        #expect(g.hit(CGPoint(x: 300 + 10, y: 120 - 10)) == .knob)
        // The middle of the card is nobody's: a press there moves it.
        #expect(g.hit(CGPoint(x: 300, y: 255)) == nil)
        // Nor is the stretch of an edge between its pill and its corners.
        #expect(g.hit(CGPoint(x: 220, y: 150)) == nil)
    }

    @Test("A press on the chip picks that mode")
    func chipHit() {
        let g = Self.grips()
        let threeD = g.chip[2].frame
        #expect(g.hit(CGPoint(x: threeD.midX, y: threeD.midY)) == .chip(.space))
        let reshape = g.chip[1].frame
        #expect(g.hit(CGPoint(x: reshape.midX, y: reshape.midY)) == .chip(.reshape))
        #expect(g.hit(CGPoint(x: g.chip[0].frame.midX, y: g.chip[0].frame.midY)) == .chip(.size))
    }

    @Test("In 3D the depth grip answers; in Size the place below is bare")
    func depthHit() {
        let below = CGPoint(x: 300, y: 392)
        #expect(Self.grips(mode: .space).hit(below) == .depth)
        #expect(Self.grips().hit(below) == nil)
    }

    @Test("On a 140 by 45 button every grip has its own target and its own middle wins")
    func smallButton() {
        let quad = [CGPoint(x: 400, y: 300), CGPoint(x: 540, y: 300),
                    CGPoint(x: 540, y: 345), CGPoint(x: 400, y: 345)]
        for mode in [TransformMode.size, .space] {
            let g = Self.grips(quad, mode: mode)
            #expect(g.edges.count == 4)
            var every: [(SelectionGrip, CGPoint)] = g.corners.map { (.corner($0.handle), $0.center) }
            every += g.edges.map { (.edge($0.handle), $0.center) }
            every.append((.knob, g.knob!))
            every += g.chip.map { (.chip($0.mode), CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
            if let depth = g.depth { every.append((.depth, depth)) }
            for (grip, point) in every {
                #expect(g.hit(point) == grip, "\(grip) at \(point) in \(mode)")
            }
            // Measured hit areas: each grip's own target is at least the
            // drawn size, and none of them are shared.
            for (grip, _) in every {
                #expect(g.hitArea(of: grip) >= 100, "\(grip) area \(g.hitArea(of: grip))")
            }
        }
    }

    @Test("A tiny layer keeps its corners outside it and drops its pills")
    func tinyLayer() {
        let quad = [CGPoint(x: 400, y: 300), CGPoint(x: 418, y: 300),
                    CGPoint(x: 418, y: 314), CGPoint(x: 400, y: 314)]
        let g = Self.grips(quad)
        #expect(g.edges.isEmpty)
        // Each corner stepped out so the four never cover the layer.
        let tl = g.corners[0].center
        #expect(tl.x < 400 && tl.y < 300)
        // The middle is still the layer's own, to pick it up.
        #expect(g.hit(CGPoint(x: 409, y: 307)) == nil)
    }

    @Test("In 3D a tiny layer keeps one pill, on its longest edge, so it can still be tipped")
    func tinyLayerIn3D() {
        let quad = [CGPoint(x: 400, y: 300), CGPoint(x: 425, y: 300),
                    CGPoint(x: 425, y: 312), CGPoint(x: 400, y: 312)]
        let g = Self.grips(quad, mode: .space)
        #expect(g.edges.count == 1)
        let pill = g.edges[0]
        #expect(pill.handle == .top || pill.handle == .bottom)
        #expect(g.hit(pill.center) == .edge(pill.handle))
        #expect(g.hit(g.depth!) == .depth)
    }

    // MARK: The tag

    @Test("The tag sits under the frame, centred, and above-left when there is no room")
    func tagPlacement() {
        let g = Self.grips()
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 70, height: 19)
        let under = g.tagFrame(size: size, in: bounds)
        #expect(abs(under.midX - 300) < 0.01)
        #expect(abs(under.minY - 372) < 0.01)
        // A window that ends just under the card: above its top left corner,
        // clear of the knob and the chip.
        let tight = CGRect(x: 0, y: 0, width: 1000, height: 380)
        let above = g.tagFrame(size: size, in: tight)
        #expect(above.maxY <= 150 - 6)
        #expect(abs(above.minX - 150) < 0.01)
        #expect(!above.insetBy(dx: -1, dy: -1).contains(g.knob!))
        for button in g.chip { #expect(!above.intersects(button.frame)) }
    }

    @Test("In 3D the tag drops below the depth grip")
    func tagClearsDepth() {
        let g = Self.grips(mode: .space)
        let tag = g.tagFrame(size: CGSize(width: 90, height: 19), in: CGRect(x: 0, y: 0, width: 1000, height: 800))
        #expect(tag.minY > g.depth!.y + SelectionGrips.depthSize.height / 2)
    }

    @Test("The tag reads the size, the turn, and in 3D the tip, swing and depth")
    func tagWords() {
        #expect(SelectionTag.resting(mode: .size, size: CGSize(width: 300.4, height: 210),
                                     rotation: 0, turn: nil) == "300 × 210")
        #expect(SelectionTag.resting(mode: .size, size: CGSize(width: 300, height: 210),
                                     rotation: 12.4, turn: nil) == "300 × 210 · 12°")
        #expect(SelectionTag.resting(mode: .space, size: .zero, rotation: 0,
                                     turn: LayerTurn3D(rotationX: 10, rotationY: -35)) == "Tip 10° · Swing -35°")
        #expect(SelectionTag.resting(mode: .space, size: .zero, rotation: 0,
                                     turn: LayerTurn3D(depth: -120)) == "Tip 0° · Swing 0° · back 120")
        #expect(SelectionTag.resting(mode: .space, size: .zero, rotation: 0,
                                     turn: LayerTurn3D(depth: 40)) == "Tip 0° · Swing 0° · forward 40")
    }

    @Test("Resting on a grip, the tag says what it does in that mode")
    func hoverWords() {
        #expect(SelectionTag.does(.corner(.topLeft), mode: .size) == "Resize · ⇧ stretch")
        #expect(SelectionTag.does(.edge(.top), mode: .size) == "Stretch")
        #expect(SelectionTag.does(.knob, mode: .size) == "Turn · double-click for 0°")
        #expect(SelectionTag.does(.edge(.left), mode: .space) == "Tip and swing")
        #expect(SelectionTag.does(.depth, mode: .space) == "Push back or pull forward")
        #expect(SelectionTag.does(.corner(.bottomRight), mode: .space) == "Resize · ⇧ stretch")
        #expect(SelectionTag.does(.chip(.space), mode: .size) == "3D")
        #expect(SelectionTag.does(.chip(.size), mode: .space) == "Size")
        // Chrome copy budget: 30 characters.
        for mode in TransformMode.offered {
            for grip in [SelectionGrip.corner(.topLeft), .edge(.top), .knob, .depth, .chip(.size), .chip(.space)] {
                #expect(SelectionTag.does(grip, mode: mode).count <= 30)
            }
        }
    }

    // MARK: What a drag does

    @Test("An edge pill in 3D tips and swings at once, at the arcs' own rate")
    func edgeTipsAndSwings() {
        let turned = SelectionDrag.tilted(LayerTurn3D(), by: CGPoint(x: 67, y: -50), snapped: false)
        #expect(turned.rotationY == 40)
        #expect(turned.rotationX == 30)
        let snapped = SelectionDrag.tilted(LayerTurn3D(), by: CGPoint(x: 40, y: 0), snapped: true)
        #expect(snapped.rotationY == 30)
        #expect(snapped.rotationX == 0)
    }

    @Test("The depth grip dragged up pulls the layer forward, down pushes it back")
    func depthUpIsForward() {
        let forward = SelectionDrag.pushed(LayerTurn3D(), by: CGPoint(x: 0, y: -40), zoom: 1, nearest: nil)
        #expect(forward.depth == 100)
        let back = SelectionDrag.pushed(LayerTurn3D(), by: CGPoint(x: 15, y: 40), zoom: 2, nearest: nil)
        #expect(back.depth == -50)
        let held = SelectionDrag.pushed(LayerTurn3D(), by: CGPoint(x: 0, y: -400), zoom: 1, nearest: 300)
        #expect(held.depth == 300)
    }

    @Test("A corner keeps proportions for every layer unless Shift; an edge stretches one way")
    func resizeKeys() {
        #expect(SelectionDrag.keepsProportions(.topLeft, shift: false))
        #expect(!SelectionDrag.keepsProportions(.bottomRight, shift: true))
        #expect(!SelectionDrag.keepsProportions(.top, shift: false))
        #expect(SelectionDrag.keepsProportions(.right, shift: true))
    }

    @Test("Option resizes from the middle: the opposite side moves by as much")
    func fromTheMiddle() {
        let start = CGRect(x: 100, y: 100, width: 200, height: 100)
        let proposed = CGRect(x: 100, y: 100, width: 260, height: 130)
        let centred = SelectionDrag.fromCentre(start: start, proposed: proposed, handle: .bottomRight)
        #expect(centred == CGRect(x: 40, y: 70, width: 320, height: 160))
        // An edge only moves its own axis.
        let edge = SelectionDrag.fromCentre(start: start, proposed: CGRect(x: 100, y: 100, width: 240, height: 100),
                                            handle: .right)
        #expect(edge == CGRect(x: 60, y: 100, width: 280, height: 100))
        // Dragged past the middle it never inverts.
        let tiny = SelectionDrag.fromCentre(start: start, proposed: CGRect(x: 100, y: 100, width: 50, height: 100),
                                            handle: .right)
        #expect(tiny.width >= 1)
        #expect(abs(tiny.midX - start.midX) < 1e-9)
    }
}

/// The walk steps that drive the reworked selection by hand.
@Suite("Selection grips: walk steps")
struct SelectionGripStepTests {
    private func decode(_ json: String) throws -> PlaytestScript {
        try PlaytestScript.decode(Data(json.utf8))
    }

    @Test("A grip step names the grip, how far to drag it and the keys held")
    func gripStep() throws {
        let script = try decode("""
        { "steps": [
          { "do": "grip", "grip": "topRight", "by": [40, -20], "modifiers": ["shift"], "readout": "Tip 0° · Swing 30°" },
          { "do": "grip", "grip": "chip-space" },
          { "do": "grip", "grip": "knob", "clicks": 2 }
        ] }
        """)
        guard case .grip(let grip, let by, let steps, let modifiers, let clicks, let readout) = script.steps[0],
              case .grip(let chip, let none, _, _, let one, _) = script.steps[1],
              case .grip(let knob, _, _, _, let two, _) = script.steps[2] else {
            Issue.record("grip"); return
        }
        #expect(grip == .corner(.topRight))
        #expect(by == CGPoint(x: 40, y: -20))
        #expect(steps == PlaytestStep.defaultDragSteps)
        #expect(modifiers == [.shift])
        #expect(readout == "Tip 0° · Swing 30°")
        #expect(clicks == 1)
        #expect(chip == .chip(.space))
        #expect(none == nil)
        #expect(one == 1)
        #expect(knob == .knob)
        #expect(two == 2)
        #expect(script.steps[0].name == "grip")
        #expect(PlaytestStep.names.contains("grip"))
        #expect(throws: (any Error).self) {
            try decode(#"{ "steps": [ { "do": "grip", "grip": "elbow" } ] }"#)
        }
    }

    @Test("hoverGrips and expectGrips read back what the canvas drew")
    func hoverAndExpect() throws {
        let script = try decode("""
        { "steps": [
          { "do": "hoverGrips", "name": "small", "minArea": 150 },
          { "do": "expectGrips", "mode": "space", "tag": "Tip 0° · Swing 0°", "count": 9 }
        ] }
        """)
        guard case .hoverGrips(let name, let minArea) = script.steps[0],
              case .expectGrips(let mode, let tag, let count) = script.steps[1] else {
            Issue.record("steps"); return
        }
        #expect(name == "small")
        #expect(minArea == 150)
        #expect(mode == .space)
        #expect(tag == "Tip 0° · Swing 0°")
        #expect(count == 9)
        #expect(PlaytestStep.names.contains("hoverGrips"))
        #expect(PlaytestStep.names.contains("expectGrips"))
        #expect(throws: (any Error).self) {
            try decode(#"{ "steps": [ { "do": "expectGrips" } ] }"#)
        }
    }

    @Test("The grip steps run on a locked screen: they find grips by where they are drawn")
    func lockSafe() {
        for name in ["grip", "hoverGrips", "expectGrips"] {
            #expect(PlaytestLockSafety.stepsThatSurviveALock.contains(name))
        }
    }
}

/// Agents get what the grips do: a flat turn, a tip, a swing and a depth.
@Suite("Selection grips: set_layer turns in 3D")
struct SetLayerTurnTests {
    private func set(_ json: String, on layer: Layer) throws -> Layer {
        let request = try AgentTools.request(tool: "set_layer", arguments: try AgentJSON.parse(Data(json.utf8))).get()
        guard case .setLayer(_, _, let change) = request else { throw AgentToolError("not set_layer") }
        return try AgentDrawing.applying(change, to: layer, canvas: nil).get()
    }

    private static let card = Layer(name: "Card",
                                    content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#FF0000")),
                                    frame: CGRect(x: 10, y: 10, width: 100, height: 60))

    @Test("rotation, tip, swing and depth land on the layer as the grips would put them")
    func turns() throws {
        let turned = try set(#"{"layer": "x", "rotation": 15, "tip": 10, "swing": -35, "depth": -120}"#, on: Self.card)
        #expect(turned.transform.rotation == 15)
        #expect(turned.turn3D?.rotationX == 10)
        #expect(turned.turn3D?.rotationY == -35)
        #expect(turned.turn3D?.depth == -120)
        #expect(turned.frame == Self.card.frame)
        // Put back flat, it carries no turn at all.
        let flat = try set(#"{"layer": "x", "tip": 0, "swing": 0, "depth": 0}"#, on: turned)
        #expect(flat.turn3D == nil)
        #expect(flat.transform.rotation == 15)
    }

    @Test("The schema offers them")
    func schema() {
        let tool = AgentTools.all.first { $0.name == "set_layer" }
        let text = String(describing: tool?.inputSchema ?? .null)
        for word in ["rotation", "tip", "swing", "depth"] { #expect(text.contains(word)) }
    }

    @Test("Ask is not shown them, so its tight window keeps its room")
    func notForAsk() {
        let tool = AskTools.modelTools.first { $0["function"]?["name"]?.stringValue == "set_layer" }
        let properties = tool?["function"]?["parameters"]?["properties"]
        #expect(properties?["x"] != nil)
        for word in ["rotation", "tip", "swing", "depth"] { #expect(properties?[word] == nil) }
    }
}
