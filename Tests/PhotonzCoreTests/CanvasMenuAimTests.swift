import Foundation
import Testing
@testable import PhotonzCore

/// What a right click on the picture is ABOUT, and what it has to pick before
/// the menu opens (`CanvasMenuAim`).
@Suite("What a right click on the canvas aims at")
struct CanvasMenuAimTests {

    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    @Test("Nothing under the pointer means the menu is about the canvas")
    func emptyCanvas() {
        #expect(CanvasMenuAim.aim(at: nil, picked: []) == .canvas)
        #expect(CanvasMenuAim.aim(at: nil, picked: [a, b]) == .canvas)
    }

    @Test("A layer nobody has picked is picked first, and the menu is about it alone")
    func picksWhatYouPointAt() {
        let aim = CanvasMenuAim.aim(at: c, picked: [a, b])
        #expect(aim == .layer(id: c, acts: [c], picks: [c]))
        #expect(aim.picks == [c])
    }

    @Test("A layer already in the selection brings the rest of the selection with it")
    func aMemberActsOnAllOfThem() {
        let aim = CanvasMenuAim.aim(at: b, picked: [a, b])
        #expect(aim == .layer(id: b, acts: [a, b], picks: nil))
        #expect(aim.picks == nil)
    }

    @Test("The one layer already picked is not picked again")
    func theOnlyPickedLayer() {
        #expect(CanvasMenuAim.aim(at: a, picked: [a]) == .layer(id: a, acts: [a], picks: nil))
    }

    @Test("With nothing picked at all, the layer under the pointer becomes the pick")
    func nothingPickedYet() {
        #expect(CanvasMenuAim.aim(at: a, picked: []) == .layer(id: a, acts: [a], picks: [a]))
    }

    @Test("What it acts on is what a layer row menu would act on, once the pick has landed")
    func agreesWithTheRowRule() {
        // The row rule: the whole selection when the thing you aimed at is in
        // it, else that one thing. Picking first is what makes the two agree.
        for picked in [Set([a, b]), Set([a]), Set<UUID>()] {
            let aim = CanvasMenuAim.aim(at: c, picked: picked)
            let after = aim.picks ?? picked
            #expect(aim.acts == (after.contains(c) ? after : [c]))
        }
    }
}
