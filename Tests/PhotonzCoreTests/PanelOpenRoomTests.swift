import CoreGraphics
import Testing
@testable import PhotonzCore

/// Opening a folded section of the right hand panel leaves the sections past
/// it alone, and folds sections on the near side of it when it needs room
/// (the user, 2026-10-24: "if I expand a collapsed pane, it should not pull
/// other panes behind it out but can collapse panes on the other side to make
/// room").
@Suite("Opening a folded panel section makes its room on the near side")
struct PanelOpenRoomTests {

    private func entry(_ key: String, folded: CGFloat = 30, open: CGFloat, isOpen: Bool = true,
                       promised: Bool = false) -> PanelOpenRoom.Entry {
        PanelOpenRoom.Entry(key: key, folded: folded, open: open, isOpen: isOpen, isPromised: promised)
    }

    // MARK: Room to spare

    @Test("With room to spare nothing else folds")
    func roomToSpare() {
        let entries = [entry("layers", open: 150), entry("appearance", open: 200, isOpen: false),
                       entry("library", open: 180)]
        let plan = PanelOpenRoom.plan(entries, opening: 1, room: 600)
        #expect(plan.folds.isEmpty)
        #expect(plan.fits)
    }

    @Test("Exactly the room it has counts as fitting")
    func exactlyEnough() {
        let entries = [entry("a", open: 100), entry("b", open: 100, isOpen: false)]
        #expect(PanelOpenRoom.plan(entries, opening: 1, room: 200) == .init(folds: [], fits: true))
    }

    // MARK: The middle

    @Test("A middle section short of room folds the open section just above it first")
    func middleFoldsNearestAbove() {
        // 150 + 120 + 200 + 30 + 180 = 680 against 600: 80 short.
        let entries = [entry("layers", open: 150), entry("text", open: 120),
                       entry("appearance", open: 200, isOpen: false),
                       entry("effects", open: 60, isOpen: false), entry("library", open: 180)]
        let plan = PanelOpenRoom.plan(entries, opening: 2, room: 600)
        #expect(plan.folds == ["text"])
        #expect(plan.fits)
    }

    @Test("Only as many as needed, nearest first, skipping sections already folded")
    func onlyAsManyAsNeeded() {
        // 150 + 100 + 30 + 100 + 250 + 30 = 660 against 450: 210 short.
        // Folding `d` saves 70, `b` 70, `a` 120: d and b are not enough, a is next.
        let entries = [entry("a", open: 150), entry("b", open: 100), entry("c", open: 90, isOpen: false),
                       entry("d", open: 100), entry("e", open: 250, isOpen: false),
                       entry("f", open: 90, isOpen: false)]
        let plan = PanelOpenRoom.plan(entries, opening: 4, room: 450)
        #expect(plan.folds == ["d", "b", "a"])
        #expect(plan.fits)
    }

    @Test("Sections after the opened one are never folded, even when folding them would be enough")
    func neverFoldsBehind() {
        // 30 + 300 + 400 = 730 against 400. Folding `after` alone would do it;
        // it is past the opened section, so it stays open and nothing fits.
        let entries = [entry("before", open: 30, isOpen: false),
                       entry("opened", open: 300, isOpen: false), entry("after", open: 400)]
        let plan = PanelOpenRoom.plan(entries, opening: 1, room: 400)
        #expect(plan.folds.isEmpty)
        #expect(!plan.fits)
    }

    // MARK: The promised pair

    @Test("Appearance and Effects fold last: a nearer ordinary section and the lists above go first")
    func promisedFoldLast() {
        // 150 + 200 + 60 + 200 + 180 = 790 against 680: 110 short. Effects is
        // nearer, and folding it and Appearance would do; Layers goes instead.
        let entries = [entry("layers", open: 150), entry("appearance", open: 200, promised: true),
                       entry("effects", open: 60, promised: true), entry("motion", open: 200, isOpen: false),
                       entry("library", open: 180)]
        let plan = PanelOpenRoom.plan(entries, opening: 3, room: 680)
        #expect(plan.folds == ["layers"])
        #expect(plan.fits)
    }

    @Test("A promised section still folds, nearest first, once nothing else is left to fold")
    func promisedFoldWhenNothingElse() {
        // 30 + 200 + 60 + 300 = 590 against 400: 190 short. Effects saves 30,
        // Appearance 170: both go, Effects first.
        let entries = [entry("layers", open: 150, isOpen: false), entry("appearance", open: 200, promised: true),
                       entry("effects", open: 60, promised: true), entry("motion", open: 300, isOpen: false)]
        let plan = PanelOpenRoom.plan(entries, opening: 3, room: 400)
        #expect(plan.folds == ["effects", "appearance"])
        #expect(plan.fits)
    }

    // MARK: The ends

    @Test("The top section has nothing on its near side: short of room it folds nothing")
    func topFoldsNothing() {
        let entries = [entry("layers", open: 300, isOpen: false), entry("appearance", open: 200),
                       entry("library", open: 180)]
        let plan = PanelOpenRoom.plan(entries, opening: 0, room: 500)
        #expect(plan.folds.isEmpty)
        #expect(!plan.fits)
    }

    @Test("The top section with room opens and nothing folds")
    func topWithRoom() {
        let entries = [entry("layers", open: 200, isOpen: false), entry("appearance", open: 200),
                       entry("library", open: 30, isOpen: false)]
        #expect(PanelOpenRoom.plan(entries, opening: 0, room: 500) == .init(folds: [], fits: true))
    }

    @Test("The Library at the foot folds the sections above it, the one just above first")
    func bottomFoldsAbove() {
        // 150 + 200 + 60 + 140 + 250 = 800 against 600: 200 short. Motion saves 110,
        // Layers 120 (Appearance and Effects are promised and wait).
        let entries = [entry("layers", open: 150), entry("appearance", open: 200, promised: true),
                       entry("effects", open: 60, promised: true), entry("motion", open: 140),
                       entry("library", open: 250, isOpen: false)]
        let plan = PanelOpenRoom.plan(entries, opening: 4, room: 600)
        #expect(plan.folds == ["motion", "layers"])
        #expect(plan.fits)
    }

    // MARK: When nothing is enough

    @Test("When folding everything on the near side is still not enough, nothing is folded")
    func notEnoughFoldsNothing() {
        // The opened section alone is taller than the panel: folding the rest
        // would cost the person every open section and buy nothing.
        let entries = [entry("layers", open: 150), entry("appearance", open: 200, promised: true),
                       entry("text", open: 900, isOpen: false)]
        let plan = PanelOpenRoom.plan(entries, opening: 2, room: 600)
        #expect(plan.folds.isEmpty)
        #expect(!plan.fits)
    }

    @Test("Sections after it that already fill the panel leave nothing to win: nothing folds")
    func behindFillsThePanel() {
        let entries = [entry("layers", open: 150), entry("opened", open: 100, isOpen: false),
                       entry("after", open: 480)]
        let plan = PanelOpenRoom.plan(entries, opening: 1, room: 560)
        #expect(plan.folds.isEmpty)
        #expect(!plan.fits)
    }

    @Test("A stale request, a section already open or out of range, folds nothing")
    func staleRequest() {
        let entries = [entry("a", open: 400), entry("b", open: 400)]
        #expect(PanelOpenRoom.plan(entries, opening: 1, room: 500).folds.isEmpty)
        #expect(PanelOpenRoom.plan(entries, opening: 7, room: 500).folds.isEmpty)
    }
}
