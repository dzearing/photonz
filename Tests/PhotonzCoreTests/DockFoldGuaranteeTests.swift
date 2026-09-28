import CoreGraphics
import Testing
@testable import PhotonzCore

/// The fold the dock GUARANTEES: Appearance and Effects are both whole on
/// screen, on every layer, in every window the arithmetic allows.
///
/// The user asked on 2026-09-07 that Appearance and Effects are the two
/// sections nobody should ever have to scroll to, and it was walked back seven
/// times, because every answer to it was a re-ORDERING and an ordering only
/// decides which section is the one left below the fold. On 2026-09-20 the user
/// chose "Guarantee the fold" over three other answers: the panel works out how
/// much room the sections above the promised pair are allowed, and when the
/// pair is still taller than what is left, THEY scroll inside themselves rather
/// than falling off the bottom.
///
/// Two things make that possible and this suite pins both:
///
///  1. **Appearance is a list, not a form.** It is the parts a thing is made
///     of, and every switched-on part unfolds its settings, so its height is
///     whatever the document happens to make it — 250 points over a rectangle,
///     465 over an arrow, 515 over a measurement. A form is a set of controls
///     somebody chose; this is not one, and while the budget called it a form
///     it was the only promised section the budget could not shorten.
///  2. **The promised pair may be squeezed past its own floor when that is what
///     the fold costs.** Every other list stops at its floor and lets the dock
///     scroll. The pair cannot, because the whole point of the promise is that
///     it never comes to that. What it stops at instead is
///     `DockHeightBudget.foldFloor`.
///
/// Every height below was read off the running app by
/// `Scripts/playtest/dock-picked-first-walk.json` on 2026-09-22, at a 1200 by
/// 720 window whose dock viewport measured 661 points
/// (`/tmp/photonz-playtest/dock-picked-first/log.json`, the `bodies` readings
/// each `selectRow` step prints). Nothing here is guessed.
@Suite struct DockFoldGuaranteeTests {
    /// The dock's own padding above its first section and below its last
    /// (`DockMetrics.listTopPadding`).
    let topPadding: CGFloat = 6
    /// The dock's scrolling area at 1200 by 720, measured.
    let viewport: CGFloat = 661

    /// The two sections the promise is about, by the keys the dock uses for
    /// them. Appearance is drawn by the section the code still calls `color`.
    let promised: Set<String> = ["color", "effects"]

    // MARK: The sections, at the heights the app reported for them

    /// A section whose body is a form: paid in full, never squeezed.
    func form(_ key: String, height: CGFloat) -> DockHeightBudget.Group {
        .init(key: key, fixed: height, flexible: 0, floor: 0)
    }

    /// A section whose body is a list: its chrome up front, the rest squeezable
    /// down to `floor`.
    func list(_ key: String, chrome: CGFloat, body: CGFloat,
              floor: CGFloat) -> DockHeightBudget.Group {
        .init(key: key, fixed: chrome, flexible: body, floor: floor)
    }

    /// The layers list of the walk's document: 33 of header and hairline, 18 of
    /// count line and grab bar, a 200 point list of rows, a 112 point floor.
    var layers: DockHeightBudget.Group { list("layers", chrome: 51, body: 200, floor: 112) }
    /// Measurements, present because the document holds one: 33 of chrome over
    /// 54 points of rows, which is less than its own floor and so cannot give
    /// anything back.
    var measurements: DockHeightBudget.Group {
        list("measurements", chrome: 33, body: 54, floor: 112)
    }
    /// Motion, a form, 32 of header and 1 of hairline over a 48 point body.
    var motion: DockHeightBudget.Group { form("motion", height: 81) }

    /// Appearance as the budget saw it until now: a form, paid in full,
    /// whatever it costs.
    func appearanceAsForm(_ body: CGFloat) -> DockHeightBudget.Group {
        form("color", height: 33 + body)
    }

    /// Appearance as it is now: a list of parts, squeezable like any other.
    func appearanceAsList(_ body: CGFloat) -> DockHeightBudget.Group {
        list("color", chrome: 33, body: body, floor: 112)
    }

    /// Effects with nothing open in it — one line saying how to add something —
    /// which is 35 points and under its own floor.
    var effectsEmpty: DockHeightBudget.Group {
        list("effects", chrome: 33, body: 35, floor: 35)
    }

    /// Effects with the drop shadow a piece of text comes with open: 339 points
    /// of pane, whose floor is the 292 points that draws it whole (capped at
    /// `floorShareOfDock` of the dock, which is where 292 comes from).
    var effectsOpenShadow: DockHeightBudget.Group {
        list("effects", chrome: 33, body: 339, floor: 292)
    }

    // MARK: Reading the dock back

    /// Where each section starts and ends down the dock, once the budget has
    /// said how tall the lists may be drawn.
    func spans(_ groups: [DockHeightBudget.Group],
               promised: Set<String>) -> [(key: String, top: CGFloat, bottom: CGFloat)] {
        let heights = DockHeightBudget.flexibleHeights(groups,
                                                       viewport: viewport - 2 * topPadding,
                                                       promised: promised)
        var top = topPadding
        return groups.map { group in
            let bottom = top + group.fixed + (heights[group.key] ?? group.flexible)
            defer { top = bottom }
            return (group.key, top, bottom)
        }
    }

    func span(_ key: String, in groups: [DockHeightBudget.Group],
              promised: Set<String>) -> (key: String, top: CGFloat, bottom: CGFloat) {
        spans(groups, promised: promised).first { $0.key == key }!
    }

    /// Whether this section's whole box is inside the dock's viewport, which is
    /// what a walk's `sectionInView` asks and what "without scrolling" means.
    func isWhollyInView(_ key: String, in groups: [DockHeightBudget.Group],
                        promised: Set<String>) -> Bool {
        span(key, in: groups, promised: promised).bottom <= viewport
    }

    // MARK: A piece of text picked, which is the case the task was filed on

    /// Layers 200, Text 165 of form, Appearance 250, Effects 339 with the
    /// shadow open, Motion 48, Measurements 54. Read off the app 2026-09-22.
    var textPicked: [DockHeightBudget.Group] {
        [layers, form("text", height: 198), appearanceAsForm(250), effectsOpenShadow,
         motion, measurements]
    }

    /// The same selection with Appearance treated as what it is.
    var textPickedWithAppearanceAsAList: [DockHeightBudget.Group] {
        [layers, form("text", height: 198), appearanceAsList(250), effectsOpenShadow,
         motion, measurements]
    }

    /// BEFORE. The defect, in numbers: Effects ran to 975 in a 661 point dock,
    /// so 314 points of it were below the fold and its header was the last
    /// thing you could see of it.
    @Test func beforeTheFixEffectsRanThreeHundredPointsPastTheBottom() {
        let effects = span("effects", in: textPicked, promised: [])
        #expect(effects.top == 650)
        #expect(effects.bottom == 975)
        #expect(!isWhollyInView("effects", in: textPicked, promised: []))
        // Appearance itself only just made it, at 650 of 661, and one more
        // section above it would have taken that too.
        #expect(span("color", in: textPicked, promised: []).bottom == 650)
    }

    /// AFTER. Both promised sections are whole inside the 661 points the dock
    /// has, and the arithmetic says how: the pair splits the 334 points left
    /// once Layers' floor and the Text form are paid, 111 points each.
    @Test func afterTheFixBothPromisedSectionsAreWhollyInView() {
        let groups = textPickedWithAppearanceAsAList
        let appearance = span("color", in: groups, promised: promised)
        let effects = span("effects", in: groups, promised: promised)
        #expect(appearance.top == 367)
        #expect(appearance.bottom == 511)
        #expect(effects.top == 511)
        #expect(effects.bottom == 655)
        #expect(isWhollyInView("color", in: groups, promised: promised))
        #expect(isWhollyInView("effects", in: groups, promised: promised))
    }

    /// What it costs, said out loud: Motion and Measurements go below the fold
    /// and the dock scrolls to them. They are BOTH better off than they were —
    /// Motion started at 975 and now starts at 655 — but neither is whole on
    /// screen, and that is the trade the promise is paid with.
    @Test func whatTheFoldCostsIsTheSectionsUnderThePair() {
        let groups = textPickedWithAppearanceAsAList
        #expect(span("motion", in: groups, promised: promised).top == 655)
        #expect(!isWhollyInView("motion", in: groups, promised: promised))
        #expect(span("motion", in: textPicked, promised: []).top == 975)
    }

    /// The pair is squeezed past its own floor ONLY when that is what the fold
    /// costs. Effects' floor is 292 — the room to draw its open shadow whole —
    /// and with the promise off it takes all 292 and pushes itself off the
    /// bottom. With the promise on it takes 111 and stays.
    @Test func thePromisedPairGivesUpItsFloorForTheFold() {
        let groups = textPickedWithAppearanceAsAList
        let withoutThePromise = DockHeightBudget.flexibleHeights(
            groups, viewport: viewport - 2 * topPadding, promised: [])
        #expect(withoutThePromise["effects"] == 292)
        let withThePromise = DockHeightBudget.flexibleHeights(
            groups, viewport: viewport - 2 * topPadding, promised: promised)
        #expect(withThePromise["effects"] == 111)
        #expect(withThePromise["color"] == 111)
        // ...and no further than `foldFloor`, whatever is asked of it.
        #expect(withThePromise["effects"]! >= DockHeightBudget.foldFloor)
    }

    // MARK: An arrow picked, which asks for different sections

    /// An arrow: no section of its own at all, and 465 points of Appearance,
    /// because every one of its parts unfolds its settings. Effects is empty.
    /// Read off the app 2026-09-22.
    var arrowPicked: [DockHeightBudget.Group] {
        [layers, appearanceAsForm(465), effectsEmpty, motion, measurements]
    }

    var arrowPickedWithAppearanceAsAList: [DockHeightBudget.Group] {
        [layers, appearanceAsList(465), effectsEmpty, motion, measurements]
    }

    /// BEFORE, the reading `dock-picked-first-walk` failed on: Appearance ran
    /// 169 to 667 in a 661 point dock, so its last 6 points were below the
    /// fold, and Effects, Motion and Measurements were entirely under it.
    @Test func beforeTheFixAnArrowPushedAppearanceItselfOffTheBottom() {
        let appearance = span("color", in: arrowPicked, promised: [])
        #expect(appearance.top == 169)
        #expect(appearance.bottom == 667)
        #expect(!isWhollyInView("color", in: arrowPicked, promised: []))
        #expect(!isWhollyInView("effects", in: arrowPicked, promised: []))
    }

    /// AFTER: the whole dock fits, so nothing is below the fold at all. An
    /// arrow never needed the promise's own machinery — treating Appearance as
    /// a list was the whole of it.
    @Test func afterTheFixAnArrowFitsTheWholeDock() {
        let groups = arrowPickedWithAppearanceAsAList
        for key in ["layers", "color", "effects", "motion", "measurements"] {
            #expect(isWhollyInView(key, in: groups, promised: promised))
        }
        #expect(DockHeightBudget.overflow(groups, viewport: viewport - 2 * topPadding,
                                          promised: promised) == 0)
        // Appearance is drawn at 164 of the 465 it wants and scrolls inside
        // itself for the rest; the layers list is levelled to the same 164,
        // which is 52 points MORE than it used to get.
        let heights = DockHeightBudget.flexibleHeights(groups,
                                                       viewport: viewport - 2 * topPadding,
                                                       promised: promised)
        #expect(heights["color"] == 164)
        #expect(heights["layers"] == 164)
    }

    // MARK: A rectangle and a measurement, the other two the walk reads

    /// A plain rectangle has no section of its own either. Before, the dock ran
    /// to 688 and Measurements' last 27 points were below the fold; after, the
    /// whole thing fits.
    @Test func aRectangleFitsWhereItUsedToOverrunByTwentySeven() {
        let before = [layers, appearanceAsForm(250), effectsEmpty, motion, measurements]
        #expect(spans(before, promised: []).last!.bottom == 688)
        let after = [layers, appearanceAsList(250), effectsEmpty, motion, measurements]
        #expect(spans(after, promised: promised).last!.bottom <= viewport)
    }

    /// A measurement is the tallest Appearance in the app: 515 points of parts
    /// — the line, its ticks, the chip, the label — against a 649 point room.
    /// Appearance goes to its 112 point floor here, and that is enough that
    /// every section in the dock, the pair included, is whole on screen: the
    /// promise never has to be invoked.
    @Test func aMeasurementKeepsThePairOnScreenToo() {
        let groups = [layers, form("measure", height: 109), appearanceAsList(515),
                      effectsEmpty, motion, measurements]
        #expect(isWhollyInView("color", in: groups, promised: promised))
        #expect(isWhollyInView("effects", in: groups, promised: promised))
        #expect(span("effects", in: groups, promised: promised).bottom == 491)
        #expect(spans(groups, promised: promised).last!.bottom == 659)
    }

    // MARK: The rule, in the cases that test its edges

    /// A dock with room to spare is left exactly as it was: the promise costs
    /// nothing where it is already kept, so the common panel gains no scrollers
    /// it does not need.
    @Test func aDockWithRoomToSpareIsUntouched() {
        let groups = [layers, appearanceAsList(120), effectsEmpty]
        let promisedHeights = DockHeightBudget.flexibleHeights(
            groups, viewport: viewport - 2 * topPadding, promised: promised)
        let plainHeights = DockHeightBudget.flexibleHeights(
            groups, viewport: viewport - 2 * topPadding, promised: [])
        #expect(promisedHeights == plainHeights)
        #expect(promisedHeights["color"] == 120)
    }

    /// The fold is not a promise the panel can keep in every window, and where
    /// it cannot, nothing is thrown away to pretend otherwise: the dock scrolls
    /// as it always did. This is a 1200 by 720 window with the timing strip at
    /// its ceiling under it, which takes 235 points off the dock
    /// (`docs/design/video-surface.md` §4), so the pair cannot be kept whatever
    /// is squeezed — and the heights come back the same as they would with no
    /// promise at all rather than starved into slivers. (The 235 point strip is
    /// the timeline now; its real heights, re-measured, are
    /// `DockFoldOnAVideoDocumentTests` below.)
    @Test func aDockTooShortForThePairIsLeftToScrollRatherThanStarved() {
        let groups = textPickedWithAppearanceAsAList
        let shortRoom = 426 - 2 * topPadding
        let withThePromise = DockHeightBudget.flexibleHeights(groups, viewport: shortRoom,
                                                              promised: promised)
        let withoutIt = DockHeightBudget.flexibleHeights(groups, viewport: shortRoom,
                                                         promised: [])
        #expect(withThePromise == withoutIt)
    }

    /// A promised section that is not in the dock at all changes nothing: the
    /// fold is worked out from the sections actually drawn, so a document with
    /// no Effects section has its own last promised section and no phantom one.
    @Test func aPromisedSectionThatIsNotDrawnIsNotWaitedFor() {
        let groups = [layers, appearanceAsList(465), motion, measurements]
        #expect(isWhollyInView("color", in: groups, promised: promised))
        #expect(isWhollyInView("motion", in: groups, promised: promised))
    }
}

/// The fold on a DOCUMENT WITH TIME, at the laptop window, re-measured on
/// 2026-09-28 after the timeline replaced the strip and took the Layers list
/// out of a video's panel.
///
/// Every height here was read off the running probe at 1200 by 720 with the
/// timeline open under the sample recording (the `dockSections`, `dockViewport`
/// and `dockListRoom` readings a walk's `describe` prints). The timeline runs
/// the full width of the window, under the panel as well as the picture, as
/// `docs/design/mocks/pages/video.html` draws it, so it takes its height off
/// both: the panel's scrolling area is 583 points with the timeline railed,
/// 336 with a clip picked and the timeline open, and 302 once a title adds a
/// track of its own.
///
/// What these pin is that the budget cannot keep the promise at this size in
/// ANY order: the answer is a change to what the window shows, which is a
/// question for the user (`queue/decisions/`, task
/// the-panel-keeps-its-promise-on-a-video-document).
@Suite struct DockFoldOnAVideoDocumentTests {
    let topPadding: CGFloat = 6
    let promised: Set<String> = ["color", "effects"]

    /// The panel's scrolling area at 1200 by 720, measured.
    let railed: CGFloat = 583
    let clipWithTimeline: CGFloat = 336
    let titleWithTimeline: CGFloat = 302

    func form(_ key: String, _ height: CGFloat) -> DockHeightBudget.Group {
        .init(key: key, fixed: height, flexible: 0, floor: 0)
    }

    /// Appearance over a title: 33 of chrome, 164 of parts, 112 floor.
    var appearanceOverTitle: DockHeightBudget.Group {
        .init(key: "color", fixed: 33, flexible: 164, floor: 112)
    }
    /// Effects over a title, whose drop shadow comes open: 512 of panes, and
    /// the 131 that draws the open one whole.
    var effectsOverTitle: DockHeightBudget.Group {
        .init(key: "effects", fixed: 33, flexible: 512, floor: 131)
    }
    /// Appearance over a clip: 33 of chrome over 134 of parts.
    var appearanceOverClip: DockHeightBudget.Group {
        .init(key: "color", fixed: 33, flexible: 134, floor: 112)
    }
    /// Effects over a clip, empty: one line saying how to add one.
    var effectsOverClip: DockHeightBudget.Group {
        .init(key: "effects", fixed: 33, flexible: 35, floor: 35)
    }

    /// Title picked, in the order the panel draws today: Properties 128, Time
    /// 75, Text 209, then the pair.
    var titleToday: [DockHeightBudget.Group] {
        [form("properties", 128), form("time", 75), form("text", 209),
         appearanceOverTitle, effectsOverTitle]
    }
    /// Clip picked, today: Properties 143, Time 105, Channel 95, Fades 108,
    /// Gain 96, then the pair.
    var clipToday: [DockHeightBudget.Group] {
        [form("properties", 143), form("time", 105), form("channel", 95),
         form("fades", 108), form("gain", 96), appearanceOverClip, effectsOverClip]
    }

    func bottom(of key: String, in groups: [DockHeightBudget.Group],
                viewport: CGFloat) -> CGFloat {
        let heights = DockHeightBudget.flexibleHeights(groups, viewport: viewport - 2 * topPadding,
                                                       promised: promised)
        var top = topPadding
        for group in groups {
            top += group.fixed + (heights[group.key] ?? group.flexible)
            if group.key == key { return top }
        }
        return .infinity
    }

    /// BEFORE, title picked: the forms above the pair are 412 points against
    /// a 302 point panel, so Appearance starts below the bottom edge.
    @Test func aTitlePutsBothOfThePairBelowTheFold() {
        let above: CGFloat = 128 + 75 + 209
        #expect(above > titleWithTimeline)
        #expect(bottom(of: "color", in: titleToday, viewport: titleWithTimeline)
                > titleWithTimeline)
    }

    /// BEFORE, clip picked: 547 points of forms above the pair, against 336.
    @Test func aClipPutsBothOfThePairBelowTheFold() {
        let above: CGFloat = 143 + 105 + 95 + 108 + 96
        #expect(above == 547)
        #expect(bottom(of: "effects", in: clipToday, viewport: clipWithTimeline)
                > clipWithTimeline)
    }

    /// Why no ordering fixes it: even with the pair straight under Properties
    /// and squeezed to `foldFloor`, a title's panel needs 348 points and has
    /// 302. The timeline has to give the panel height back.
    @Test func noOrderKeepsThePairWithTheTimelineOpenUnderATitle() {
        let least = topPadding + 128 + 2 * (33 + DockHeightBudget.foldFloor)
        #expect(least == 348)
        #expect(least > titleWithTimeline)
    }

    /// What a panel the full height of the window WOULD do: with the pair
    /// straight under Properties, both are whole in the 583 points the panel
    /// has with nothing under it, for a title and for a clip.
    @Test func thePairFitsInAFullHeightPanelWhenItComesFirst() {
        let title = [form("properties", 128), appearanceOverTitle, effectsOverTitle,
                     form("time", 75), form("text", 209)]
        #expect(bottom(of: "effects", in: title, viewport: railed) <= railed)
        let clip = [form("properties", 143), appearanceOverClip, effectsOverClip,
                    form("time", 105), form("channel", 95)]
        #expect(bottom(of: "effects", in: clip, viewport: railed) <= railed)
    }
}
