import CoreGraphics
import Testing
@testable import PhotonzCore

/// What the right hand dock becomes in a document that has TIME, worked out
/// with the same budget the app runs and the same measured section heights the
/// pane-load study read off the running app on 2026-09-15.
///
/// This suite is the arithmetic half of the video design pass
/// (`docs/design/video-surface.md`). It exists because the panel was already
/// over its own viewport before video was drawn, and every video clickthrough
/// adds to it: a channel strip, a transition's settings, a caption list, a
/// graph. The question "does video fit" has an answer and it is a number, so
/// the number is pinned here rather than argued in prose.
///
/// Two things about a document with time change the budget, and they pull in
/// opposite directions:
///
///  1. **The bottom dock takes height off the panel.** The timing strip is a
///     full width band under the canvas AND the dock (`EditorView`), so the
///     dock's viewport shrinks by the whole of it. Nothing in the panel moved,
///     and the panel is suddenly further over.
///  2. **The section named after what you picked REPLACES, it does not
///     stack.** Picking a clip gives you a Clip section where picking text
///     gives you a Text section. Video does not add five sections; it adds one
///     (Captions) and re-uses the slot that was always there.
///
/// Where a number here is a DESIGN BUDGET rather than a measurement it says so
/// on its own line. The build tasks (`a-document-can-have-time` and the four
/// after it) have to come in under them, and this suite is how that is checked.
@Suite struct DockWithTimeTests {
    /// The dock's own padding above its first section (`DockMetrics`), the same
    /// constant `DockWithoutPositionAndSizeTests` uses.
    let topPadding: CGFloat = 6

    /// The tallest dock this display gives, measured 2026-09-15 at 1680 x 1000.
    let largestViewport: CGFloat = 968
    /// A laptop window, measured the same day at 1200 x 720.
    let laptopViewport: CGFloat = 688

    // MARK: What the bottom dock costs the panel

    /// The timing strip's own constants, read out of `MotionStripView`:
    /// the ruler is 15, a layer's labelled hairline is 16, a property lane is
    /// 22, there are 10 points of air over the top lane, and past 188 the body
    /// scrolls instead of growing.
    static let stripRuler: CGFloat = 15
    static let stripLayerRow: CGFloat = 16
    static let stripLane: CGFloat = 22
    static let stripTopAir: CGFloat = 10
    static let stripBodyCeiling: CGFloat = 188
    /// The divider, the bar along the top and the air under the body.
    /// DESIGN BUDGET, not a measurement: 1 + 34 + 12. A build task that draws
    /// the video strip has to measure this and correct it here.
    static let stripChrome: CGFloat = 47
    /// What the strip collapses to, from `MotionStripRailView`.
    static let stripRail: CGFloat = 30

    /// How tall the bottom dock is drawn for a document with this many layers
    /// in it and this many property lanes open under them.
    static func stripHeight(layers: Int, lanes: Int) -> CGFloat {
        let content = stripRuler
            + CGFloat(layers) * stripLayerRow
            + CGFloat(lanes) * stripLane
            + stripTopAir
        return min(stripBodyCeiling, content) + stripChrome
    }

    /// A screen recording the moment it is opened: one clip layer, nothing
    /// animated on it yet. This is the shape that matters most, because it is
    /// what every trim-and-send starts as.
    @Test func aRecordingJustOpenedCostsTheDockUnderNinetyPoints() {
        let strip = Self.stripHeight(layers: 1, lanes: 0)
        #expect(strip == 88)
        #expect(largestViewport - strip == 880)
    }

    /// A real edit: three clips with two moving properties each. The body hits
    /// its ceiling here, so this is the WORST the panel ever sees — the strip
    /// cannot take any more room than this however long the document gets.
    @Test func theStripNeverTakesMoreThanTwoHundredAndThirtyFive() {
        let busy = Self.stripHeight(layers: 3, lanes: 6)
        #expect(busy == Self.stripBodyCeiling + Self.stripChrome)
        #expect(busy == 235)
        // However much more you put in it, it stops here and scrolls.
        #expect(Self.stripHeight(layers: 20, lanes: 60) == busy)
    }

    /// The three viewports the panel actually has to fit, in a document with
    /// time. The middle one is the honest default and the one every number
    /// below is quoted against.
    var viewportWithStripOpen: CGFloat { largestViewport - Self.stripHeight(layers: 3, lanes: 6) }
    var viewportWithStripRailed: CGFloat { largestViewport - Self.stripRail }

    @Test func aBusyVideoDocumentLeavesTheDockSevenHundredAndThirtyThree() {
        #expect(viewportWithStripOpen == 733)
        #expect(viewportWithStripRailed == 938)
    }

    // MARK: The sections, measured and budgeted

    func form(_ key: String, height: CGFloat) -> DockHeightBudget.Group {
        .init(key: key, fixed: height, flexible: 0, floor: 0)
    }

    func list(_ key: String, chrome: CGFloat, body: CGFloat,
              floor: CGFloat) -> DockHeightBudget.Group {
        .init(key: key, fixed: chrome, flexible: body, floor: floor)
    }

    /// What one row of the layers list costs, rounded off the measurement:
    /// a three layer document's list body was 160 points, so a row is 53.
    static let layerRow: CGFloat = 53

    /// Today's panel, for reference: a piece of text picked in a three layer
    /// document, after Position & Size left. 922 points, and it is the number
    /// every claim below is compared against.
    var textPickedToday: [DockHeightBudget.Group] {
        [list("layers", chrome: 51, body: 160, floor: 112),
         form("text", height: 198),
         form("color", height: 223),
         list("effects", chrome: 33, body: 299, floor: 299)]
    }

    /// A clip picked in a five layer recording: two shots, a title, a logo and
    /// the audio that came off the picture. One drop shadow open on the clip.
    ///
    /// `clip` is a DESIGN BUDGET of 198, which is exactly what the Text section
    /// costs today. The rule it encodes: the section named after what you
    /// picked REPLACES the one that was there, so it may not be bigger than the
    /// biggest one already in the slot. Everything about WHEN — in, out,
    /// duration, speed — is set by dragging on the strip and is not in it, for
    /// the same reason Position & Size is not in it.
    var clipPickedInAVideoDocument: [DockHeightBudget.Group] {
        [list("layers", chrome: 51, body: 5 * Self.layerRow, floor: 112),
         form("clip", height: 198),
         form("color", height: 223),
         list("effects", chrome: 33, body: 299, floor: 299)]
    }

    /// The same document with captions in it, so the one section video adds is
    /// showing. Captions is a LIST — twelve cues here — and it is optional, so
    /// automatic takes it away in a document that has none.
    var clipPickedWithCaptions: [DockHeightBudget.Group] {
        clipPickedInAVideoDocument
            + [list("captions", chrome: 51, body: 636, floor: 112)]
    }

    func drawnHeight(_ groups: [DockHeightBudget.Group], viewport: CGFloat) -> CGFloat {
        let heights = DockHeightBudget.flexibleHeights(groups, viewport: viewport - 2 * topPadding)
        return groups.reduce(topPadding) { $0 + $1.fixed + (heights[$1.key] ?? $1.flexible) }
    }

    // MARK: The answer

    /// The headline, and it is not good news. Nothing video does to the panel
    /// is as expensive as what the bottom dock does to the window.
    ///
    /// Today, in the largest window this display gives, the panel FITS: 962 of
    /// 968, for the first time ever, and that was the whole point of taking
    /// Position & Size out a week ago. Open a document with time and the same
    /// panel is 189 points over, and not one point of that is a section video
    /// added.
    @Test func theStripCostsThePanelMoreThanVideosOwnSectionsDo() {
        let today = drawnHeight(textPickedToday, viewport: largestViewport)
        #expect(today == 962)
        #expect(today <= largestViewport)
        // A clip picked instead of text, in a document with two more layers in
        // it. The dock asks for slightly LESS than the text did, because the
        // layers list is the section giving way.
        let clip = drawnHeight(clipPickedInAVideoDocument, viewport: viewportWithStripOpen)
        #expect(clip == 922)
        #expect(clip < today)
        // ...and it has 733 points to draw it in rather than 968.
        #expect(clip - viewportWithStripOpen == 189)
    }

    /// The one section video adds does not make it materially worse, because it
    /// is a list and lists give way. That is the whole reason Captions is
    /// shaped as a list and not as a form.
    @Test func addingCaptionsCostsOnlyItsOwnChrome() {
        let without = drawnHeight(clipPickedInAVideoDocument, viewport: viewportWithStripOpen)
        let with = drawnHeight(clipPickedWithCaptions, viewport: viewportWithStripOpen)
        #expect(with - without == 163)   // its chrome, and its floor of three rows
    }

    /// Putting the strip away gives the panel back more room than every video
    /// section costs put together. So the first answer to "the panel is full"
    /// in a video document is the control that is already on screen.
    @Test func railingTheStripBuysBackMoreThanCaptionsCosts() {
        let open = viewportWithStripOpen
        let railed = viewportWithStripRailed
        #expect(railed - open == 205)
        #expect(railed - open > 51 + 112)
    }

    /// A recording opened to be trimmed and sent, which is what the app is
    /// actually used for today: one clip, one layer, nothing animated. The
    /// panel fits, and this is the case the design is allowed to optimise for.
    @Test func aRecordingJustOpenedStillFitsTheLargestWindow() {
        let viewport = largestViewport - Self.stripHeight(layers: 1, lanes: 0)
        let oneClip: [DockHeightBudget.Group] =
            [list("layers", chrome: 51, body: Self.layerRow, floor: 112),
             form("clip", height: 198),
             form("color", height: 223)]
        #expect(drawnHeight(oneClip, viewport: viewport) <= viewport)
    }

    /// And the case the design is NOT allowed to pretend about: on a laptop,
    /// with the strip open, the panel is nearly three hundred points over. This
    /// is not a video problem — the same selection is over on the same laptop
    /// today — but video makes it worse and the design says so rather than
    /// quietly scrolling.
    @Test func aLaptopWindowWithTheStripOpenIsFarOver() {
        let viewport = laptopViewport - Self.stripHeight(layers: 3, lanes: 6)
        #expect(viewport == 453)
        let clip = drawnHeight(clipPickedInAVideoDocument, viewport: viewport)
        #expect(clip > viewport)
        #expect(clip - viewport > 280)
    }
}
