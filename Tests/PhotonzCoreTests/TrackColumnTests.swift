import CoreGraphics
import Testing
@testable import PhotonzCore

/// The column of track names down the left of the timeline (user 2026-10-03:
/// "the labels area of the tracks can't be resized, and it's so small the
/// buttons overlap"). These pin that the column can be dragged between a
/// floor where every switch still fits and a ceiling, that nothing chosen is
/// the default, and that at ANY width the header's name gives way before a
/// button touches another.
@Suite("Track column")
struct TrackColumnTests {

    // What a name needs, measured in the app's own font (10pt semibold,
    // kerning 0.2) on 2026-10-03: "V10" is 19.6, "V1…" 21.7, "Audio 2" 39.3.
    let v10: CGFloat = 19.6

    /// Every control a header can carry at once: in a group, with its arrow,
    /// all three switches up under the pointer, and the key diamond.
    func fullest(_ width: CGFloat) -> TrackHeaderLayout {
        TrackHeaderLayout(width: width, inGroup: true, hasTwist: true, switches: 3, hasKey: true,
                          wantsIcon: false)
    }

    /// The boxes along the header, left to right, as [start, end).
    func spans(_ layout: TrackHeaderLayout) -> [(String, CGFloat, CGFloat)] {
        var out: [(String, CGFloat, CGFloat)] = []
        if let twist = layout.twistX { out.append(("twist", twist, twist + TrackHeaderLayout.twistWidth)) }
        out.append(("name", layout.nameX, layout.nameX + layout.nameWidth))
        for (i, x) in layout.switchXs.enumerated() {
            out.append(("switch \(i)", x, x + TrackHeaderLayout.switchSize))
        }
        if let key = layout.keyX { out.append(("key", key, key + TrackHeaderLayout.keySize)) }
        return out
    }

    // MARK: The width

    @Test("Nothing on file is the default width")
    func nothingChosenIsTheDefault() {
        #expect(TrackColumn.width(stored: TrackColumn.defaultStored) == TrackColumn.defaultWidth)
        #expect(TrackColumn.width(stored: .nan) == TrackColumn.defaultWidth)
        #expect(TrackColumn.width(stored: -5) == TrackColumn.defaultWidth)
    }

    @Test("A width on file comes back, held between the floor and the ceiling")
    func storedWidthIsClamped() {
        #expect(TrackColumn.width(stored: 180) == 180)
        #expect(TrackColumn.width(stored: 40) == TrackColumn.minimumWidth)
        #expect(TrackColumn.width(stored: 4000) == TrackColumn.maximumWidth)
    }

    @Test("The edge follows the pointer one for one and stops at both ends")
    func dragFollowsThePointer() {
        #expect(TrackColumn.dragged(from: 150, pointerMovedRight: 30) == 180)
        #expect(TrackColumn.dragged(from: 150, pointerMovedRight: -10) == 140)
        #expect(TrackColumn.dragged(from: 150, pointerMovedRight: -400) == TrackColumn.minimumWidth)
        #expect(TrackColumn.dragged(from: 150, pointerMovedRight: 900) == TrackColumn.maximumWidth)
    }

    @Test("The floor is the fullest header with a few letters of its name")
    func floorFitsTheFullestHeader() {
        let layout = fullest(TrackColumn.minimumWidth)
        #expect(layout.nameWidth >= TrackHeaderLayout.nameMinimum)
        // ...and not a point wider than it has to be, give or take rounding.
        #expect(fullest(TrackColumn.minimumWidth - 2).nameWidth < TrackHeaderLayout.nameMinimum)
    }

    @Test("The default shows V10 whole on the fullest header")
    func defaultShowsV10Whole() {
        #expect(fullest(TrackColumn.defaultWidth).nameWidth >= v10)
        // The mock's 84 points did not, which is the report.
        #expect(TrackColumn.defaultWidth > 84)
        #expect(TrackColumn.minimumWidth < TrackColumn.defaultWidth)
        #expect(TrackColumn.defaultWidth < TrackColumn.maximumWidth)
    }

    // MARK: Nothing touches

    @Test("At every width from the floor to the ceiling, every pair of controls is 4 points apart")
    func nothingOverlapsAtAnyWidth() {
        var width = TrackColumn.minimumWidth
        while width <= TrackColumn.maximumWidth {
            for inGroup in [false, true] {
                for hasTwist in [false, true] {
                    for switches in 0...3 {
                        for hasKey in [false, true] {
                            let layout = TrackHeaderLayout(width: width, inGroup: inGroup, hasTwist: hasTwist,
                                                           switches: switches, hasKey: hasKey,
                                                           wantsIcon: true)
                            let boxes = spans(layout)
                            for (a, b) in zip(boxes, boxes.dropFirst()) {
                                // The arrow sits right against the name it opens.
                                let least: CGFloat = a.0 == "twist" ? 0 : 4
                                #expect(b.1 - a.2 >= least - 0.001,
                                        "\(a.0) and \(b.0) at \(width): \(b.1 - a.2)pt apart")
                            }
                            #expect((boxes.last?.2 ?? 0) <= width + 0.001)
                            #expect(boxes.first?.1 ?? -1 >= 0)
                            #expect(layout.nameWidth >= TrackHeaderLayout.nameMinimum - 0.001)
                        }
                    }
                }
            }
            width += 1
        }
    }

    @Test("The switches and the key keep to the right edge; the name takes the rest")
    func controlsHugTheRightEdge() {
        let layout = TrackHeaderLayout(width: 200, inGroup: false, hasTwist: false, switches: 1, hasKey: true,
                                       wantsIcon: false)
        let key = layout.keyX
        #expect(key == 200 - TrackHeaderLayout.trailing - TrackHeaderLayout.keySize)
        #expect(layout.switchXs == [(key ?? 0) - TrackHeaderLayout.gap - TrackHeaderLayout.switchSize])
        #expect(layout.nameX == 0)
        #expect(layout.nameWidth == (layout.switchXs.first ?? 0) - TrackHeaderLayout.gap)
    }

    @Test("A bare header gives the name the whole column but the trailing air")
    func bareHeader() {
        let layout = TrackHeaderLayout(width: 140, inGroup: false, hasTwist: false, switches: 0, hasKey: false,
                                       wantsIcon: true)
        #expect(layout.switchXs.isEmpty)
        #expect(layout.keyX == nil)
        #expect(layout.twistX == nil)
        #expect(layout.nameWidth == 140 - TrackHeaderLayout.trailing)
        #expect(layout.showsIcon)
    }

    @Test("A group's track is indented and its arrow comes before the name")
    func groupAndTwist() {
        let layout = TrackHeaderLayout(width: 140, inGroup: true, hasTwist: true, switches: 0, hasKey: false,
                                       wantsIcon: false)
        #expect(layout.twistX == TrackHeaderLayout.groupIndent)
        #expect(layout.nameX == TrackHeaderLayout.groupIndent + TrackHeaderLayout.twistWidth)
    }

    @Test("The kind icon gives way before the name gets short")
    func iconGivesWay() {
        // Room for the icon and a few letters: it shows.
        let roomy = TrackHeaderLayout(width: 140, inGroup: false, hasTwist: true, switches: 1, hasKey: true,
                                      wantsIcon: true)
        #expect(roomy.showsIcon)
        // The floor with every control up: the name keeps its letters, the icon goes.
        let tight = TrackHeaderLayout(width: TrackColumn.minimumWidth, inGroup: true, hasTwist: true,
                                      switches: 3, hasKey: true, wantsIcon: true)
        #expect(!tight.showsIcon)
        #expect(tight.textWidth >= TrackHeaderLayout.nameMinimum)
        // Not asked for, never shown.
        #expect(!TrackHeaderLayout(width: 300, inGroup: false, hasTwist: false, switches: 0, hasKey: false,
                                   wantsIcon: false).showsIcon)
    }

    @Test("The text's room is the name's room less the icon's, when the icon shows")
    func textWidthLeavesTheIcon() {
        let layout = TrackHeaderLayout(width: 140, inGroup: false, hasTwist: false, switches: 0, hasKey: false,
                                       wantsIcon: true)
        #expect(layout.textWidth == layout.nameWidth - TrackHeaderLayout.iconRoom)
    }

    @Test("The switches are 4 points apart from each other")
    func switchSpacing() {
        let layout = TrackHeaderLayout(width: 200, inGroup: false, hasTwist: false, switches: 3, hasKey: false,
                                       wantsIcon: false)
        #expect(layout.switchXs.count == 3)
        for (a, b) in zip(layout.switchXs, layout.switchXs.dropFirst()) {
            #expect(b - a == TrackHeaderLayout.switchSize + TrackHeaderLayout.switchSpacing)
        }
        #expect(TrackHeaderLayout.switchSpacing >= 4)
    }
}
