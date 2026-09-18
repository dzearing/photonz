import CoreGraphics
import Foundation

/// What a separated box is CALLED, when the picture gives it something to say.
///
/// Separate into Layers hands back two kinds of piece. A run of text wears the
/// words in it, read off its own pixels, so the layers list reads like the
/// screen. Everything else used to come back as Box 1 to Box 10 in one flat
/// run: a card, a button, a switch and a text field all with the same word and
/// a number. Somebody redlining a settings pane wants the switch beside Launch
/// at login, and the only way to find it was to click boxes on the canvas until
/// the right one lit up.
///
/// A box almost never has words of its own — that is what makes it a box — but
/// it nearly always has words a person would name it BY: the label sitting
/// inside a button, the caption to the left of a switch. This is the rule that
/// picks which run of text that is. It knows nothing about switches, buttons or
/// fields, because the app cannot see those: it takes rectangles and says which
/// run of text each box is next to, so a name can be made from words somebody
/// can read on the screen.
///
/// The name says both halves: the words, and that this is the box wearing them
/// rather than the words themselves. Two rows both reading "Launch at login"
/// would be exactly the puzzle this exists to end.
///
/// Full design: `docs/design/separate-into-layers.md`.
public enum SeparatedBoxNames {

    /// The word the app uses for a piece that is not text, which is all it
    /// honestly knows about one: it is a box. A box with nothing to say keeps
    /// it with a number after it.
    public static let stem = "Box"

    /// The word a named box ends with, so its row is never mistaken for the row
    /// of the words themselves.
    public static let boxWord = "box"

    /// How much of the shorter of two pieces has to line up vertically before
    /// they count as being on the same row. Half: a switch is twice the height
    /// of the words beside it, and words on the row above overlap it by nothing
    /// at all.
    static let sameRowShare = 0.5

    /// The name for a box whose words have been read: the words, cut to a row's
    /// worth exactly as a run of text's own name is, and then the word that
    /// says it is the box. Empty when there are no words, which leaves the
    /// caller holding the number the command gave it.
    public static func name(fromWords words: String) -> String {
        let read = LayerNaming.name(fromWords: words)
        return read.isEmpty ? "" : "\(read) \(boxWord)"
    }

    /// For every piece, the index of the run of text whose words name it, or
    /// nil for a piece that has nothing to be named after — a run of text
    /// itself, a card with a whole list on it, a stripe with nothing beside it.
    ///
    /// `rects` and `isRunOfText` are the pieces in the order the separation
    /// found them, in one shared space. The answer is the same list of pieces
    /// long, so a caller can pair them up by index.
    ///
    /// Two ways a box gets its words, in this order:
    ///
    /// - **Inside it.** A box holding exactly one run of text and nothing else
    ///   that reads is a button wearing its own label. A card holding three
    ///   rows of words is not named after any one of them, so it is left with
    ///   its number.
    /// - **Beside it, on the same row.** Among the pieces that share its
    ///   container, the nearest run of text to its left that lines up with it
    ///   vertically, with nothing in between the two. To the right when there
    ///   is nothing to the left, which is what a checkbox before its label
    ///   looks like.
    ///
    /// One run of text names at most one box, so a row holding a label and two
    /// controls does not come back saying the same thing twice: the nearer box
    /// takes the words and the other keeps its number.
    public static func labels(rects: [CGRect], isRunOfText: [Bool]) -> [Int?] {
        guard rects.count == isRunOfText.count, !rects.isEmpty else {
            return Array(repeating: nil, count: rects.count)
        }
        let boxes = rects.map { $0.standardized }
        let parent = parents(of: boxes)

        /// Every box's best claim on a run, with what makes one claim beat
        /// another: words inside the box beat words beside it, and nearer beats
        /// further.
        struct Claim {
            let box: Int
            let run: Int
            let isInside: Bool
            let gap: CGFloat
        }
        var claims: [Claim] = []
        for box in boxes.indices where !isRunOfText[box] {
            let mine = boxes.indices.filter { parent[$0] == box }
            let runsInside = mine.filter { isRunOfText[$0] }
            if runsInside.count == 1, mine.count == runsInside.count {
                claims.append(Claim(box: box, run: runsInside[0], isInside: true, gap: 0))
                continue
            }
            guard runsInside.isEmpty else { continue }
            let siblings = boxes.indices.filter { $0 != box && parent[$0] == parent[box] }
            let onTheRow = siblings.filter { sharesARow(boxes[$0], boxes[box]) }
            if let found = nearestRun(to: box, among: onTheRow, boxes: boxes,
                                      isRunOfText: isRunOfText) {
                claims.append(Claim(box: box, run: found.run, isInside: false, gap: found.gap))
            }
        }

        // Handed out best claim first, and a run is spoken for once it has
        // named something. Sorted rather than walked in place so the answer
        // cannot depend on the order the boxes happened to come out in.
        claims.sort {
            if $0.isInside != $1.isInside { return $0.isInside }
            if $0.gap != $1.gap { return $0.gap < $1.gap }
            return $0.box < $1.box
        }
        var labels = [Int?](repeating: nil, count: boxes.count)
        var spokenFor = Set<Int>()
        for claim in claims where !spokenFor.contains(claim.run) {
            labels[claim.box] = claim.run
            spokenFor.insert(claim.run)
        }
        return labels
    }

    /// The nearest run of text on `box`'s row with nothing between the two of
    /// them: to the left first, because that is where a label sits in nearly
    /// every pane ever drawn, and to the right when the left is empty.
    private static func nearestRun(to box: Int, among row: [Int], boxes: [CGRect],
                                   isRunOfText: [Bool]) -> (run: Int, gap: CGFloat)? {
        let me = boxes[box]
        func nearest(_ candidates: [Int], gap: (CGRect) -> CGFloat) -> (Int, CGFloat)? {
            candidates.filter { isRunOfText[$0] }
                .map { ($0, gap(boxes[$0])) }
                .filter { $0.1 >= 0 }
                .min { ($0.1, $0.0) < ($1.1, $1.0) }
        }
        let before = row.filter { boxes[$0].maxX <= me.minX }
        if let (run, gap) = nearest(before, gap: { me.minX - $0.maxX }),
           !anythingBetween(boxes[run].maxX, me.minX, row: row, boxes: boxes, ignoring: run) {
            return (run, gap)
        }
        let after = row.filter { boxes[$0].minX >= me.maxX }
        if let (run, gap) = nearest(after, gap: { $0.minX - me.maxX }),
           !anythingBetween(me.maxX, boxes[run].minX, row: row, boxes: boxes, ignoring: run) {
            return (run, gap)
        }
        return nil
    }

    /// Whether any other piece on the row reaches into the gap between a box
    /// and the words that would name it. A label on the far side of another
    /// control is not this control's label.
    private static func anythingBetween(_ from: CGFloat, _ to: CGFloat, row: [Int],
                                        boxes: [CGRect], ignoring run: Int) -> Bool {
        guard to > from else { return false }
        return row.contains { $0 != run && boxes[$0].maxX > from && boxes[$0].minX < to }
    }

    /// Whether two pieces are on the same row: they overlap vertically by at
    /// least half the shorter one.
    static func sharesARow(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        let shorter = min(a.height, b.height)
        guard shorter > 0 else { return false }
        return overlap >= shorter * sameRowShare
    }

    /// Which piece holds which, as a flat lookup. The same rule the layers list
    /// is built with (`LayerNesting`), so a box and the words that name it are
    /// siblings here exactly when they are siblings in the list.
    private static func parents(of rects: [CGRect]) -> [Int?] {
        var parent = [Int?](repeating: nil, count: rects.count)
        func walk(_ nodes: [LayerNesting.Node], under owner: Int?) {
            for node in nodes {
                parent[node.index] = owner
                walk(node.children, under: node.index)
            }
        }
        walk(LayerNesting.nest(rects), under: nil)
        return parent
    }
}
