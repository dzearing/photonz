import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// What a colour row SHOWS, told apart from WHICH LAYERS it is speaking for.
///
/// Clicking from one arrow to an identical one used to rebuild every colour row
/// in the panel, because the reading behind a row carries the picked layers'
/// ids and two arrows are never the same two ids. A person looking at the panel
/// sees none of that: the chip, the word, the name beside it and the sentence
/// under it are all the same. `appearance` is that half of the reading, so a
/// row can compare what it draws and skip the work when nothing about it moved.
struct ColorRowAppearanceTests {

    private func member(_ id: UUID, _ hex: String, _ style: UUID? = nil)
    -> ColorStyleSelection.Member {
        ColorStyleSelection.Member(id: id, colorHex: hex, styleID: style)
    }

    private func selection(_ members: [ColorStyleSelection.Member],
                           slot: ColorSlot = .fill,
                           selectionCount: Int? = nil,
                           capableCount: Int? = nil) -> ColorStyleSelection {
        ColorStyleSelection(slot: slot, members: members,
                            selectionCount: selectionCount ?? members.count,
                            capableCount: capableCount)
    }

    @Test("Two rows over different layers wearing the same colour look the same")
    func sameColorDifferentLayers() {
        let one = selection([member(UUID(), "#FF0000")])
        let two = selection([member(UUID(), "#FF0000")])
        #expect(one != two)
        #expect(one.appearance == two.appearance)
    }

    @Test("A different colour is a different row")
    func differentColor() {
        let id = UUID()
        #expect(selection([member(id, "#FF0000")]).appearance
                != selection([member(id, "#0000FF")]).appearance)
    }

    @Test("A different gradient under the same base colour is a different row")
    func differentGradient() {
        let flat = Paint(hex: "#FF0000")
        let ramp = Paint(hex: "#FF0000", kind: .linear,
                         stops: [GradientStop(hex: "#FF0000", position: 0),
                                 GradientStop(hex: "#00FF00", position: 1)])
        let a = selection([ColorStyleSelection.Member(id: UUID(), paint: flat)])
        let b = selection([ColorStyleSelection.Member(id: UUID(), paint: ramp)])
        #expect(a.appearance != b.appearance)
    }

    @Test("A different slot is a different row")
    func differentSlot() {
        let hex = "#FF0000"
        #expect(selection([member(UUID(), hex)], slot: .fill).appearance
                != selection([member(UUID(), hex)], slot: .stroke).appearance)
    }

    @Test("Wearing a style, and wearing a different one, are different rows")
    func styles() {
        let accent = UUID(), brand = UUID()
        let a = selection([member(UUID(), "#FF0000", accent)])
        let b = selection([member(UUID(), "#FF0000", accent)])
        let c = selection([member(UUID(), "#FF0000", brand)])
        #expect(a.appearance == b.appearance)
        #expect(a.appearance != c.appearance)
    }

    @Test("Some layers styled and some not is a different row from none styled")
    func styledCountShows() {
        let accent = UUID()
        let mixedWithStyle = selection([member(UUID(), "#FF0000", accent),
                                        member(UUID(), "#00FF00")])
        let mixedWithout = selection([member(UUID(), "#FF0000"),
                                      member(UUID(), "#00FF00")])
        #expect(mixedWithStyle.reading == .mixed)
        #expect(mixedWithout.reading == .mixed)
        #expect(mixedWithStyle.appearance != mixedWithout.appearance)
        #expect(mixedWithStyle.unlinkNote != mixedWithout.unlinkNote)
    }

    @Test("How many layers the row speaks for shows, because the row says so")
    func counts() {
        let two = selection([member(UUID(), "#FF0000"), member(UUID(), "#FF0000")],
                            selectionCount: 3, capableCount: 3)
        let twoOfFour = selection([member(UUID(), "#FF0000"), member(UUID(), "#FF0000")],
                                  selectionCount: 4, capableCount: 4)
        #expect(two.appearance != twoOfFour.appearance)
        #expect(two.note != twoOfFour.note)
    }

    @Test("A row that leaves a layer out says so, and that shows")
    func capableCountShows() {
        let members = [member(UUID(), "#FF0000")]
        let all = selection(members, selectionCount: 1, capableCount: 1)
        let some = selection(members, selectionCount: 2, capableCount: 2)
        #expect(all.note == nil)
        #expect(some.note != nil)
        #expect(all.appearance != some.appearance)
    }

    @Test("An empty row looks like any other empty row")
    func empties() {
        #expect(selection([], selectionCount: 1).appearance
                == selection([], selectionCount: 1).appearance)
        #expect(selection([], selectionCount: 1).appearance
                != selection([], selectionCount: 2).appearance)
    }

    @Test("Every sentence the row can say is decided by what appearance carries")
    func sentencesFollowAppearance() {
        // The guard that keeps this honest as the row grows: anything a row
        // prints has to be a function of the appearance, or two rows that
        // compare equal could print different words.
        let accent = UUID()
        let a = selection([member(UUID(), "#FF0000", accent), member(UUID(), "#00FF00")],
                          selectionCount: 3, capableCount: 3)
        let b = selection([member(UUID(), "#FF0000", accent), member(UUID(), "#00FF00")],
                          selectionCount: 3, capableCount: 3)
        #expect(a.appearance == b.appearance)
        #expect(a.reading == b.reading)
        #expect(a.note == b.note)
        #expect(a.unlinkNote == b.unlinkNote)
        #expect(a.styleReplacementNote == b.styleReplacementNote)
        #expect(a.savableColorHex == b.savableColorHex)
        #expect(a.savablePaint == b.savablePaint)
        #expect(a.boundStyleID == b.boundStyleID)
        #expect(a.wearsAnyStyle == b.wearsAnyStyle)
        #expect(a.count == b.count)
    }
}
