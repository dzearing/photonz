import CoreGraphics
import Foundation

/// One fact about a layout that can be read but not typed, ready to sit on a
/// row: the word on the left and the answer on the right.
public struct LayoutReadout: Equatable, Hashable, Sendable {
    public let title: String
    public let value: String

    public init(title: String, value: String) {
        self.title = title
        self.value = value
    }
}

extension GroupLayout {
    /// What a copy's Layout section reads back, one row per fact.
    ///
    /// A copy is SHOWN how its original arranges its contents and refused the
    /// typing of it, so the section has answers with no controls to hold them.
    /// It used to say them as a paragraph, which took three lines to say what
    /// three rows say in one word each and put the numbers a long way from the
    /// rows an original keeps them on. These are the same facts, in the same
    /// order and under the same words the editable rows carry, so a copy's
    /// Layout reads as the same section with its answers greyed rather than as
    /// a different section made of prose.
    ///
    /// Anything with a home elsewhere on the panel is left out. The size is
    /// the loud one: W and H in Position & Size are two rows above this and
    /// hold the very same numbers, so "It is 36 tall" was the third time the
    /// panel said 36.
    ///
    /// `clipsContents` is the group's own switch, which lives on the layer
    /// rather than in the layout.
    public func followedReadout(clipsContents: Bool) -> [LayoutReadout] {
        var rows: [LayoutReadout] = []
        switch kind {
        case .stack:
            rows.append(LayoutReadout(title: "Direction", value: direction.title))
        case .grid:
            rows.append(LayoutReadout(title: "Columns", value: "\(usedColumns)"))
        case nil:
            break
        }
        // A limit is the one thing that can stop a group growing, so it is
        // never left off: a copy that stopped at 96 has to be able to say why.
        rows += limitRows()
        if clipsContents {
            rows.append(LayoutReadout(title: "Clip contents", value: "On"))
        }
        rows += gapRows()
        let room = usedPadding
        if room != .none {
            rows.append(LayoutReadout(title: "Padding",
                                      value: room.uniform.map { Self.whole($0) } ?? room.shorthand))
        }
        return rows
    }

    /// The gap, in the words the arrangement holding it uses. A grid keeps two
    /// and names them only while they differ, since one number under one word
    /// is what a grid with even spacing actually has.
    private func gapRows() -> [LayoutReadout] {
        switch kind {
        case .stack:
            // A stack that shares its leftover room says so where the number
            // would be, exactly as the editable field does. With nothing left
            // over there is nothing to share, so the number is the truth.
            let value = spreadsGap && couldSpread ? "Spread" : Self.whole(usedGap)
            return [LayoutReadout(title: "Gap", value: value)]
        case .grid:
            guard usedGap != usedRowGap else {
                return [LayoutReadout(title: "Gap", value: Self.whole(usedGap))]
            }
            return [LayoutReadout(title: "Column gap", value: Self.whole(usedGap)),
                    LayoutReadout(title: "Row gap", value: Self.whole(usedRowGap))]
        case nil:
            return []
        }
    }

    /// The smallest and the largest, under the same names the fields answer to
    /// — "Smallest width", not "Smallest" — because there is no Width row above
    /// them here to say which axis they belong to.
    private func limitRows() -> [LayoutReadout] {
        [usedMinWidth.map { LayoutReadout(title: "Smallest width", value: Self.whole($0)) },
         usedMaxWidth.map { LayoutReadout(title: "Largest width", value: Self.whole($0)) },
         usedMinHeight.map { LayoutReadout(title: "Smallest height", value: Self.whole($0)) },
         usedMaxHeight.map { LayoutReadout(title: "Largest height", value: Self.whole($0)) }]
            .compactMap { $0 }
    }

    /// Whole numbers, the way every field in the section shows them.
    private static func whole(_ value: CGFloat) -> String { "\(Int(value.rounded()))" }
}
