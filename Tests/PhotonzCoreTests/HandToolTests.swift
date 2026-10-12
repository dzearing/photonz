import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The Hand: pick it and a drag on the canvas moves the view, never a layer.
/// The mocks draw it at the end of every app's tool strip (`Hand (H)`,
/// UX-PATTERNS D4), the way Photoshop keeps it at the foot of its bar.
@Suite("Hand tool")
struct HandToolTests {

    // MARK: The tool

    @Test("The Hand makes nothing, paints nothing and keeps what is picked")
    func handIsANavigationTool() {
        #expect(!Tool.hand.createsLayers)
        #expect(Tool.hand.annotationShape == nil)
        #expect(Tool.hand.colorControl == .hidden)
        #expect(!Tool.hand.paints)
        #expect(!Tool.hand.isRegionSelectionTool)
        // Looking somewhere else is not a reason to let go of the pick, the
        // same as in Photoshop.
        #expect(Tool.hand.preservesLayerSelection)
        // It puts nothing on the picture, so a double click on the matte still
        // does what it does with Select.
        #expect(Tool.hand.doubleClickOnEmptyCanvasZoomsWindow)
    }

    @Test("With the Hand on the bar, H picks the Hand and Highlight moves to U")
    func handTakesH() {
        // The user's answer on 2026-10-11: H picks the Hand, the way it does in
        // Photoshop and in every strip the mocks draw, and Highlight moves.
        #expect(Tool.hand.shortcutKey(handOnBar: true) == "h")
        #expect(Tool.hand.shortcutHint(handOnBar: true) == "H")
        #expect(Tool.highlight.shortcutKey(handOnBar: true) == "u")
        #expect(Tool.highlight.shortcutHint(handOnBar: true) == "U")
        #expect(Tool.allCases.filter { $0.shortcutKey(handOnBar: true) == "h" } == [.hand])
        #expect(Tool.allCases.filter { $0.shortcutKey(handOnBar: true) == "u" } == [.highlight])
        #expect(ToolGroup.containing(.hand) == nil)
    }

    @Test("Without the Hand on the bar, which is the release Photonz, H stays Highlight's")
    func withoutTheHandHStaysHighlight() {
        #expect(Tool.highlight.shortcutKey(handOnBar: false) == "h")
        #expect(Tool.hand.shortcutKey(handOnBar: false) == nil)
        #expect(Tool.allCases.filter { $0.shortcutKey(handOnBar: false) == "h" } == [.highlight])
        #expect(!Tool.allCases.contains { $0.shortcutKey(handOnBar: false) == "u" })
    }

    @Test("The Hand moves only its own letter and Highlight's, never another tool's")
    func onlyTwoLettersMove() {
        for tool in Tool.allCases where tool != .hand && tool != .highlight {
            #expect(tool.shortcutKey(handOnBar: true) == tool.shortcutKey(handOnBar: false),
                    "\(tool) changes its letter with the Hand")
        }
    }

    @Test("U is free: the timeline leaves it to the canvas")
    func uIsFree() {
        #expect(TimelineKeys.leavesToTheCanvas("u"))
        #expect(TimelineKeys.leavesToTheCanvas("h"))
    }

    // MARK: The bar

    @Test("With the Hand on, it is the bar's last family, on its own")
    func handIsTheLastFamily() {
        let bar = ToolBarLayout.bar(withFrame: true, withLens: true, withPen: true,
                                    withComponent: true, withHand: true)
        #expect(bar.families.last == [.tool(.hand)])
        #expect(bar.entry(for: .hand) == .tool(.hand))
    }

    @Test("With the Hand off, the bar is exactly what it was")
    func handOffChangesNothing() {
        let off = ToolBarLayout.bar(withFrame: true, withLens: true, withPen: true,
                                    withComponent: true)
        #expect(off.entry(for: .hand) == nil)
        #expect(off.families.last == [.tool(.fill)])
        #expect(ToolBarLayout.families.entry(for: .hand) == nil)
    }

    @Test("Edit > Tools lists the Hand last with H beside it, and Highlight with U")
    func handInTheToolsMenu() {
        let bar = ToolBarLayout.bar(withFrame: true, withLens: true, withPen: true,
                                    withComponent: true, withHand: true)
        let tools = ToolMenu.tools(bar, bounds: [.crop])
        #expect(tools.last == .hand)
        #expect(ToolMenu.printedKey(for: .hand, among: tools, active: .select,
                                    remembered: { $0.tools[0] }) == "h")
        #expect(ToolMenu.printedKey(for: .highlight, among: tools, active: .select,
                                    remembered: { $0.tools[0] }) == "u")
        #expect(ToolMenu.tool(forKey: "h", among: tools, active: .select,
                              remembered: { $0.tools[0] }) == .hand)
        #expect(ToolMenu.tool(forKey: "u", among: tools, active: .select,
                              remembered: { $0.tools[0] }) == .highlight)
    }

    @Test("A bar without the Hand still hands H to Highlight in Edit > Tools")
    func noHandInTheToolsMenu() {
        let bar = ToolBarLayout.bar(withFrame: true, withLens: true, withPen: true,
                                    withComponent: true)
        let tools = ToolMenu.tools(bar, bounds: [.crop])
        #expect(ToolMenu.tool(forKey: "h", among: tools, active: .select,
                              remembered: { $0.tools[0] }) == .highlight)
        #expect(ToolMenu.printedKey(for: .highlight, among: tools, active: .select,
                                    remembered: { $0.tools[0] }) == "h")
        #expect(ToolMenu.tool(forKey: "u", among: tools, active: .select,
                              remembered: { $0.tools[0] }) == nil)
    }

    // MARK: The drag

    /// A picture zoomed in past fit, so there is somewhere for it to go.
    private let zoomedIn = Viewport(documentSize: CGSize(width: 2000, height: 1500),
                                    viewSize: CGSize(width: 800, height: 600),
                                    zoom: 1, origin: CGPoint(x: -600, y: -450))

    @Test("The picture follows the pointer: drag right and down, it moves right and down")
    func panFollowsThePointer() {
        let pan = HandPan(at: CGPoint(x: 400, y: 300), viewport: zoomedIn)
        let next = pan.viewport(at: CGPoint(x: 460, y: 340))
        #expect(next.origin == CGPoint(x: -540, y: -410))
        #expect(next.zoom == zoomedIn.zoom)
    }

    @Test("Measured from where the press began, so a drag that comes back puts it back")
    func panReturnsHome() {
        let pan = HandPan(at: CGPoint(x: 400, y: 300), viewport: zoomedIn)
        _ = pan.viewport(at: CGPoint(x: 900, y: 900))
        #expect(pan.viewport(at: CGPoint(x: 400, y: 300)) == zoomedIn)
    }

    @Test("The picture stops at its edge, and comes back as soon as the pointer does")
    func panStopsAtTheEdge() {
        let pan = HandPan(at: CGPoint(x: 400, y: 300), viewport: zoomedIn)
        // Far past the left edge: the picture's left side meets the window's.
        let pinned = pan.viewport(at: CGPoint(x: 5000, y: 300))
        #expect(pinned.origin.x == 0)
        // Straight back toward the start: no dead travel to win back first.
        let back = pan.viewport(at: CGPoint(x: 340, y: 300))
        #expect(back.origin.x == -660)
    }

    @Test("A picture that fits the window has nowhere to go and stays centred")
    func fittedPictureStays() {
        let fit = Viewport.fit(documentSize: CGSize(width: 400, height: 300),
                               in: CGSize(width: 800, height: 600))
        let pan = HandPan(at: CGPoint(x: 400, y: 300), viewport: fit)
        #expect(pan.viewport(at: CGPoint(x: 600, y: 500)) == fit)
    }
}
