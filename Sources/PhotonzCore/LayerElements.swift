import CoreGraphics
import Foundation

/// The elements the DOCUMENT itself knows about, for the Measure tool's Size
/// mode (Next release).
///
/// `ElementBounds` reads an element out of a picture, because a screenshot has
/// no structure to ask. A box you drew yourself is the opposite problem: the
/// app put it there and knows exactly where it is, to the pixel, so guessing it
/// from gradients would be both slower and worse. Before this, Size mode had
/// only the picture reader, which meant the one thing it could not measure was
/// the thing you had just made: pointing at a rectangle on a blank canvas lit
/// nothing up and clicking it left nothing behind.
///
/// So the ladder Size mode offers is built from both, nested by size, so `[`
/// and `]` climb one stack: a button read out of the screenshot, the highlight
/// box somebody drew around it, the card behind them both. Where the two say
/// the same thing the drawn box wins, because it is known rather than guessed.
///
/// Two things are deliberately not elements. A measurement's bounding box is
/// not something anyone aims at, the same rule foot snapping already follows.
/// And a layer covering the whole canvas is the BACKDROP: it is the picture
/// Size mode reads pixels from, its size is the canvas size, and offering it
/// would turn every miss into a hit on everything.
public enum LayerElements {

    /// Two rungs this close on every side are one box read twice — a group
    /// whose only child fills it, most often.
    private static let sameBox: CGFloat = 0.5

    /// How far a rung read off the PICTURE may sit from a drawn one and still
    /// be the same element described twice — a shape drawn to trace something
    /// in the screenshot. Deliberately tight: a highlight box drawn ten points
    /// around a button is NOT that button, and swallowing it would take away
    /// the very thing the box was drawn to point at.
    private static let sameElement: CGFloat = 2

    /// How many neighbours a readout is asked to steer around. A canvas full of
    /// shapes offers dozens and the far ones cannot be in the way.
    private static let neighborLimit = 8

    /// The nested ladder of drawn boxes around `point`, innermost first, each
    /// containing the one before it. Empty when the pointer is over nothing
    /// the document drew.
    public static func candidates(at point: CGPoint, in document: PhotonzDocument,
                                  limit: Int = ElementBounds.candidateLimit) -> [CGRect] {
        guard limit > 0 else { return [] }
        let hits = boxes(in: document).filter { $0.contains(point) }
        return tidied(hits, limit: limit)
    }

    /// The drawn ladder and the picture's, as ONE ladder, innermost first.
    ///
    /// Not drawn-then-picture: a redliner draws a box around a button to point
    /// at it and then wants the button, so a rung the picture found INSIDE a
    /// drawn one has to come first. Where the two describe the same element the
    /// drawn box is the one kept. With nothing drawn under the pointer this is
    /// the picture's ladder, untouched.
    public static func merged(drawn: [CGRect], picture: [CGRect],
                              limit: Int = ElementBounds.candidateLimit) -> [CGRect] {
        guard limit > 0 else { return [] }
        guard !drawn.isEmpty else { return Array(picture.prefix(limit)) }
        let read = picture.filter { rung in
            !drawn.contains { same($0, rung, within: sameElement) }
        }
        return tidied(drawn + read, limit: limit)
    }

    /// The drawn boxes near `rect` that a readout would land on, so the number
    /// steers around the shapes beside the one it belongs to the way it steers
    /// around the picture's own elements. Anything overlapping `rect` is left
    /// out: that is the measured shape itself, and the groups holding it.
    public static func neighbors(of rect: CGRect, in document: PhotonzDocument,
                                 reach: CGFloat) -> [CGRect] {
        let subject = rect.standardized
        guard subject.width > 0, subject.height > 0 else { return [] }
        let near = boxes(in: document)
            .filter { !$0.intersects(subject) }
            .map { (box: $0, distance: distance(from: subject, to: $0)) }
            .filter { $0.distance <= reach }
            .sorted { $0.distance < $1.distance }
        return Array(near.map(\.box).prefix(neighborLimit))
    }

    // MARK: Reading the document

    /// Every box a person can see, in document space: visible, with a size,
    /// not a measurement, and not the backdrop.
    ///
    /// Public because the readers that aim at a POINT or a LINE rather than at
    /// a box do their own aiming: Gap mode wants whichever edge is nearest the
    /// pointer on each of the four sides, and the alignment scan wants the
    /// edges a guide line runs along. Both take the list and pick from it.
    public static func boxes(in document: PhotonzDocument) -> [CGRect] {
        let canvas = CGRect(origin: .zero, size: document.canvasSize)
        var found: [CGRect] = []
        func walk(_ layers: [Layer], origin: CGPoint) {
            for layer in layers {
                // A turned or slanted layer is left to the picture reader: its
                // box is stored unturned, so offering it would outline a
                // rectangle that is not the shape a person is looking at, and
                // quote a width nobody could see.
                guard layer.isVisible, layer.measure == nil, isSquareOn(layer.transform)
                else { continue }
                let box = layer.contentBounds.standardized.offsetBy(dx: origin.x, dy: origin.y)
                if box.width > 0, box.height > 0, !isBackdrop(box, canvas: canvas) {
                    found.append(box)
                }
                if layer.isGroup {
                    walk(layer.children,
                         origin: CGPoint(x: origin.x + layer.frame.minX,
                                         y: origin.y + layer.frame.minY))
                }
            }
        }
        walk(document.layers, origin: .zero)
        return found
    }

    /// Whether the layer is drawn the way its box says it is. A flip is fine:
    /// mirroring something changes nothing about the room it takes.
    private static func isSquareOn(_ transform: LayerTransform) -> Bool {
        transform.rotation == 0 && transform.skewX == 0 && transform.skewY == 0
    }

    /// Whether this box is the picture everything else sits on rather than
    /// something on top of it.
    private static func isBackdrop(_ box: CGRect, canvas: CGRect) -> Bool {
        guard canvas.width > 0, canvas.height > 0 else { return false }
        return box.insetBy(dx: -sameBox, dy: -sameBox).contains(canvas)
    }

    /// Innermost first, with boxes that agree to within half a point offered
    /// once, capped so `]` stays a handful of presses.
    private static func tidied(_ boxes: [CGRect], limit: Int) -> [CGRect] {
        var ladder: [CGRect] = []
        for box in boxes.sorted(by: { area($0) < area($1) }) {
            if ladder.contains(where: { same($0, box, within: sameBox) }) { continue }
            ladder.append(box)
            if ladder.count == limit { break }
        }
        return ladder
    }

    private static func same(_ a: CGRect, _ b: CGRect, within slack: CGFloat) -> Bool {
        abs(a.minX - b.minX) <= slack && abs(a.minY - b.minY) <= slack
            && abs(a.maxX - b.maxX) <= slack && abs(a.maxY - b.maxY) <= slack
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }

    /// The clear space between two boxes that do not overlap, along whichever
    /// way they are further apart.
    private static func distance(from a: CGRect, to b: CGRect) -> CGFloat {
        let dx = max(0, max(a.minX - b.maxX, b.minX - a.maxX))
        let dy = max(0, max(a.minY - b.maxY, b.minY - a.maxY))
        return max(dx, dy)
    }
}
